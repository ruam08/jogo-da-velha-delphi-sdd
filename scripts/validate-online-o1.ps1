# Validação da Entrega O1 (domínio das salas: tokens, versões, concorrência e JSON).
#  1. ambiente; 2. arquivos preservados (git) e formato dos novos (UTF-8 com BOM, CRLF);
#  3. compilação (scripts\build.cmd); 4. independência das units novas;
#  5. EngineCheck (27 casos antigos + 18 da O1 = 45);
#  6. sabotagens SB-07, SB-08, SB-10, SB-12 e SB-13 em cópias;
#  7. regressão Playwright (109 testes), duas execuções.
# Com -RedPhase: só 1 a 5, contra os esqueletos (os casos novos precisam falhar).
# Saída em logs\online-o1.log (ou logs\online-o1-red.log). Windows PowerShell 5.1.
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'online-o1-red.log' } else { 'online-o1.log' })
$ServerDir = Join-Path $Root 'server'
$TestsDir  = Join-Path $Root 'tests'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'

$OldCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3','M-05-C1','M-05-C2',
    'M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08','M-09','M-10','M-11','M-12',
    'J-01','J-02','J-03','J-04','J-05','SV-01','SV-02','SV-03')
$NewCases = @('SL-01','SL-02','SL-03','SL-04','SL-05','SL-06','SL-07','SL-08','SL-09','SL-10',
    'SL-11','SL-12','MEM-01','SC-01','SC-02','RJ-01','RJ-02','RJ-03')
$AllCases = $OldCases + $NewCases

# Arquivos que a O1 não pode alterar (conferidos contra o último commit).
$Preserved = @('server/src/uGameEngine.pas','server/src/uGameService.pas','server/src/uHttpApp.pas',
    'server/src/uConsoleLog.pas','server/TicTacToeServer.dpr','server/tests/uMiniTest.pas',
    'server/tests/uEngineTests.pas','server/tests/uServiceTests.pas','server/tests/uJsonTests.pas',
    'web','tests/api','tests/rules','tests/ui','tests/support','tests/playwright.config.ts',
    'tests/package.json','docs/spec.md','docs/plan.md','docs/test-plan.md')
$NewUnits = @('server/src/uClock.pas','server/src/uSecureRandom.pas','server/src/uRoom.pas',
    'server/src/uRoomRegistry.pas','server/src/uRoomJson.pas','server/tests/uRoomTests.pas',
    'server/tests/uRoomConcurrencyTests.pas','server/tests/uRoomJsonTests.pas')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Content -Path $LogFile -Value '' -Encoding UTF8
$Results = New-Object System.Collections.ArrayList

function Write-Log([string]$Text) {
    Add-Content -Path $LogFile -Value $Text -Encoding UTF8
    Write-Host $Text
}

function Add-Check([string]$Id, [string]$Description, [bool]$Ok, [string]$Detail) {
    $status = if ($Ok) { 'PASSOU' } else { 'FALHOU' }
    [void]$Results.Add([pscustomobject]@{ Id = $Id; Status = $status; Description = $Description })
    Write-Log ("[{0}] {1} - {2}" -f $status, $Id, $Description)
    if ($Detail) { Write-Log ("         " + $Detail) }
}

function Invoke-Compile([string]$Dir, [string]$Dpr) {
    $out = & cmd.exe /c "`"$Compile`" `"$Dir`" $Dpr 2>&1" | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

function Invoke-Engine([string]$Exe) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $out = & $Exe 2>&1 | Out-String
    $code = $LASTEXITCODE
    $sw.Stop()
    [pscustomobject]@{ Code = $code; Output = $out; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}

function Get-CaseIds([string]$Output, [string]$Tag) {
    $ids = @()
    foreach ($m in [regex]::Matches($Output, "(?m)^\[$Tag\]\s+(\S+)")) { $ids += $m.Groups[1].Value }
    return ,$ids
}

function Invoke-InTests([string]$CommandLine) {
    Write-Log "> cd tests && $CommandLine"
    Push-Location $TestsDir
    try {
        $out = & cmd.exe /c "$CommandLine 2>&1" | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    [pscustomobject]@{ Code = $code; Output = $out }
}

function Read-Results {
    $file = Join-Path $TestsDir 'test-results\results.json'
    if (-not (Test-Path $file)) { return $null }
    $json = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $byProject = @{}
    $failedTitles = New-Object System.Collections.ArrayList
    $walk = $null
    $walk = {
        param($suite)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                $p = $t.projectName
                if (-not $byProject.ContainsKey($p)) { $byProject[$p] = @{ ok = 0; fail = 0 } }
                if ($t.status -eq 'expected') { $byProject[$p].ok++ } else { $byProject[$p].fail++; [void]$failedTitles.Add("[$p] $($spec.title)") }
            }
        }
        foreach ($child in @($suite.suites)) { if ($child) { & $walk $child } }
    }
    foreach ($s in @($json.suites)) { & $walk $s }
    [pscustomobject]@{ Stats = $json.stats; ByProject = $byProject; Failed = $failedTitles }
}

function Format-Results($r) {
    if (-not $r) { return 'results.json não foi gerado' }
    $parts = @()
    foreach ($k in ($r.ByProject.Keys | Sort-Object)) { $parts += ("{0}: {1} ok, {2} falha(s)" -f $k, $r.ByProject[$k].ok, $r.ByProject[$k].fail) }
    ("aprovados {0}; falharam {1}; instáveis {2}; pulados {3}; {4}; duração {5} s" -f $r.Stats.expected, $r.Stats.unexpected, $r.Stats.flaky, $r.Stats.skipped, ($parts -join '; '), [math]::Round($r.Stats.duration / 1000, 1))
}

function Test-Suite109($r) {
    return ($null -ne $r) -and ($r.Stats.expected -eq 109) -and ($r.Stats.unexpected -eq 0) -and
        ($r.Stats.flaky -eq 0) -and ($r.Stats.skipped -eq 0) -and
        ($r.ByProject['api'].ok -eq 80) -and ($r.ByProject['chromium'].ok -eq 29)
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega O1 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: uRoom, uRoomRegistry e uRoomJson ainda são esqueletos)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"

    # ---- 1. Ambiente -------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2}); PowerShell {3}" -f $os.Caption, $os.Version, $os.BuildNumber, $PSVersionTable.PSVersion)
    $gitVer = (& cmd.exe /c "git --version 2>&1" | Out-String).Trim()
    Write-Log "git: $gitVer"
    if (-not $RedPhase) {
        Write-Log ("Node.js: " + (& cmd.exe /c "node --version 2>&1" | Out-String).Trim())
    }

    # ---- 2. Arquivos preservados e formato dos novos ------------------------
    Write-Log "`n===== 2. Arquivos preservados e formato dos arquivos novos"
    Push-Location $Root
    try {
        # uHttpApp.pas tem uma alteração do usuário anterior à O1 (Binding.IP '0.0.0.0',
        # para acessar do celular); é conferida à parte: só essa linha pode diferir.
        $strict = @($Preserved | Where-Object { $_ -ne 'server/src/uHttpApp.pas' })
        $diff = (& cmd.exe /c "git diff --stat HEAD -- $($strict -join ' ') 2>&1" | Out-String).Trim()
        $diffCode = $LASTEXITCODE
        & cmd.exe /c "git diff --quiet HEAD -- $($strict -join ' ') 2>&1" | Out-Null
        $quietCode = $LASTEXITCODE
        $httpDiff = @(& cmd.exe /c "git diff -U0 HEAD -- server/src/uHttpApp.pas 2>&1" | Where-Object { ($_ -match '^[+-]') -and ($_ -notmatch '^(\+\+\+|---) ') })
        $status = (& cmd.exe /c "git status --short --untracked-files=all -- server scripts docs web tests 2>&1" | Out-String).TrimEnd()
        $jsonDiff = (& cmd.exe /c "git diff --stat HEAD -- server/src/uGameJson.pas server/EngineCheck.dpr 2>&1" | Out-String).Trim()
    } finally { Pop-Location }
    Write-Log "Arquivos conferidos: $($Preserved -join ', ')"
    Write-Log ("git diff (preservados): " + $(if ($diff) { $diff } else { '(nenhuma diferença)' }))
    Add-Check 'P-01' 'Motor, serviço, testes antigos (EngineCheck e Playwright), interface e documentos antigos idênticos ao último commit' (($quietCode -eq 0) -and ($diffCode -eq 0)) "git diff --quiet: código $quietCode"
    Write-Log ("Diferenças de uHttpApp.pas em relação ao commit:`r`n    " + $(if ($httpDiff.Count) { $httpDiff -join "`r`n    " } else { '(nenhuma)' }))
    $httpOk = ($httpDiff.Count -eq 0) -or (($httpDiff.Count -eq 2) -and ($httpDiff[0] -like '-*') -and ($httpDiff[1] -like '+*') -and ($httpDiff[1] -match "Binding\.IP\s*:=\s*'0\.0\.0\.0'"))
    Add-Check 'P-01b' "uHttpApp.pas: única diferença é a linha Binding.IP := '0.0.0.0' (alteração do usuário anterior à O1)" $httpOk ("{0} linha(s) diferente(s)" -f $httpDiff.Count)
    Write-Log "Alterações permitidas (uGameJson aditivo, EngineCheck.dpr com as units novas):`r`n$jsonDiff"
    Write-Log "git status (server, scripts, docs, web, tests):`r`n$status"

    $badFormat = @()
    foreach ($rel in $NewUnits + @('server/src/uGameJson.pas', 'server/EngineCheck.dpr')) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $badFormat += "$rel (não existe)"; continue }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $lfOnly = ([regex]::Matches($text, '(?<!\r)\n')).Count
        if (-not $bom -or $lfOnly -gt 0) { $badFormat += "$rel (BOM: $bom; LF sem CR: $lfOnly)" }
    }
    Add-Check 'P-02' 'Units novas e alteradas em UTF-8 com BOM e CRLF (DT-17)' ($badFormat.Count -eq 0) ($badFormat -join '; ')

    # ---- 3. Compilação -----------------------------------------------------
    Write-Log "`n===== 3. Compilação (scripts\build.cmd)"
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`" 2>&1" | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $hints    = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$') | ForEach-Object { $_.Value.Trim() })
    foreach ($w in $warnings + $hints) { Write-Log "         $w" }
    $compiled = ($buildCode -eq 0) -and ($build -match 'compiler version 31\.0') -and (Test-Path $EngineExe) -and (Test-Path $ServerExe)
    Add-Check 'B-01' 'Servidor e EngineCheck compilados pelo Delphi 10.1 Berlin (31.0) sem erros' $compiled "Código $buildCode"
    if ($RedPhase) {
        Write-Log ("Fase vermelha: {0} warning(s) e {1} hint(s) nos esqueletos (não bloqueiam esta fase)." -f $warnings.Count, $hints.Count)
    } else {
        Add-Check 'B-02' 'Nenhum warning nem hint do compilador' (($warnings.Count + $hints.Count) -eq 0) ("Warnings: {0}; hints: {1}" -f $warnings.Count, $hints.Count)
    }
    if (-not (Test-Path $EngineExe)) { throw 'EngineCheck.exe não foi gerado.' }

    # ---- 4. Independência --------------------------------------------------
    Write-Log "`n===== 4. Independência das units da O1"
    $forbiddenAll = '^(Id\w*|IdGlobal|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameService|Vcl\..*|FMX\..*)$'
    $indepProblems = @()
    foreach ($u in @('uClock','uSecureRandom','uRoom','uRoomRegistry','uRoomJson')) {
        $src = Get-Content (Join-Path $ServerDir "src\$u.pas") -Raw -Encoding UTF8
        $src = [regex]::Replace($src, '(?s)\{.*?\}|\(\*.*?\*\)', '')
        $usesText = (([regex]::Matches($src, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',')
        $used = @($usesText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $bad = @($used | Where-Object { $_ -match $forbiddenAll })
        if ($u -ne 'uRoomJson') { $bad += @($used | Where-Object { $_ -match '^(System\.JSON|uGameJson)$' }) }
        if ($src -match '(?i)\bWriteln\b|\bLogLine\b|\bLogRequest\b') { $bad += 'escrita de log/console' }
        Write-Log ("{0}: {1}" -f $u, ($used -join ', '))
        if ($bad.Count) { $indepProblems += "$u -> $($bad -join ', ')" }
    }
    Add-Check 'I-01' 'Units da O1 sem Indy, HTTP, servidor, log ou console (JSON só em uRoomJson)' ($indepProblems.Count -eq 0) ($indepProblems -join '; ')

    # ---- 5. EngineCheck ----------------------------------------------------
    Write-Log "`n===== 5. EngineCheck.exe"
    $run = Invoke-Engine $EngineExe
    Write-Log $run.Output.TrimEnd()
    Write-Log "Código de saída do EngineCheck: $($run.Code); duração $($run.Seconds) s"
    $okIds = Get-CaseIds $run.Output 'OK'
    $failIds = Get-CaseIds $run.Output 'FALHOU'
    $seen = @($okIds + $failIds)
    $missing = @($AllCases | Where-Object { $seen -notcontains $_ })
    $extra = @($seen | Where-Object { $AllCases -notcontains $_ })
    $oldFailed = @($OldCases | Where-Object { $failIds -contains $_ })
    $summaryLine = ([regex]::Match($run.Output, '(?m)^Casos:.*$')).Value
    Write-Log ("Casos executados: {0} (esperados {1}); resumo: {2}" -f $seen.Count, $AllCases.Count, $summaryLine)

    if ($RedPhase) {
        $newFailed = @($NewCases | Where-Object { $failIds -contains $_ })
        $newPassed = @($NewCases | Where-Object { $okIds -contains $_ })
        Add-Check 'R-01' 'Fase vermelha: EngineCheck sai com código 1' ($run.Code -eq 1) "Código $($run.Code)"
        Add-Check 'R-02' 'Fase vermelha: os 45 casos foram executados (nenhum ausente, nenhum a mais)' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($seen.Count -eq 45)) ("Ausentes: {0}; a mais: {1}" -f ($missing -join ', '), ($extra -join ', '))
        Add-Check 'R-03' 'Fase vermelha: os 27 casos antigos continuam aprovados' (($oldFailed.Count -eq 0) -and (@($OldCases | Where-Object { $okIds -contains $_ }).Count -eq 27)) ("Antigos que falharam: " + ($oldFailed -join ', '))
        Add-Check 'R-04' 'Fase vermelha: casos novos falham contra os esqueletos' ($newFailed.Count -gt 0) ("Falharam {0} de 18: {1}" -f $newFailed.Count, ($newFailed -join ', '))
        Write-Log ("Casos novos que passaram contra o esqueleto: " + $(if ($newPassed.Count) { $newPassed -join ', ' } else { '(nenhum)' }))
    } else {
        Add-Check 'E-01' 'EngineCheck sai com código 0 e diz RESULTADO: APROVADO' (($run.Code -eq 0) -and ($run.Output -match 'RESULTADO: APROVADO')) "Código $($run.Code)"
        Add-Check 'E-02' '45 casos executados e aprovados (27 antigos + 18 da O1)' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($failIds.Count -eq 0) -and ($okIds.Count -eq 45)) ("OK: {0}; falharam: {1}; ausentes: {2}; a mais: {3}" -f $okIds.Count, ($failIds -join ','), ($missing -join ','), ($extra -join ','))
        Add-Check 'E-03' 'Os 27 casos antigos continuam aprovados' (@($OldCases | Where-Object { $okIds -contains $_ }).Count -eq 27) ("Antigos que falharam: " + ($oldFailed -join ', '))
        Copy-Item $EngineExe (Join-Path $LogDir 'online-o1-EngineCheck.exe') -Force

        # Repetição: a concorrência não pode passar por sorte numa única execução.
        Write-Log "`n----- EngineCheck: execuções 2 e 3 (repetição dos casos de concorrência)"
        $repeatOk = $true; $repeatInfo = @()
        foreach ($n in 2..3) {
            $rr = Invoke-Engine $EngineExe
            $rf = Get-CaseIds $rr.Output 'FALHOU'
            $ro = Get-CaseIds $rr.Output 'OK'
            $repeatInfo += ("execução {0}: código {1}, {2} OK, falharam [{3}], {4} s" -f $n, $rr.Code, $ro.Count, ($rf -join ','), $rr.Seconds)
            foreach ($line in ($rr.Output -split "`r?`n" | Where-Object { $_ -match '^\[(OK|FALHOU)\]\s+(SC-|MEM-)' })) { Write-Log "    $line" }
            if (($rr.Code -ne 0) -or ($rf.Count -gt 0) -or ($ro.Count -ne 45)) { $repeatOk = $false; Write-Log $rr.Output.TrimEnd() }
        }
        foreach ($i in $repeatInfo) { Write-Log "    $i" }
        Add-Check 'E-04' 'EngineCheck aprovado em mais duas execuções seguidas (45/45 em cada)' $repeatOk ($repeatInfo -join ' | ')

        # ---- 6. Sabotagens ---------------------------------------------------
        Write-Log "`n===== 6. Sabotagens (cópias em logs\sabotage; o código original não é alterado)"
        $CR = "`r`n"
        $sabotages = @(
            @{ Id = 'SB-07'; Desc = 'Todas as salas compartilham o mesmo TGameEngine'; MustFail = @('SL-06', 'SC-02');
               Edits = @(
                 @{ Find = '{ ---- TRoom ---'; Replace = "var$CR  GSharedEngine: TGameEngine;   { sabotagem SB-07 }$CR$CR{ ---- TRoom ---" },
                 @{ Find = '  FEngine := TGameEngine.Create;'; Replace = "  if GSharedEngine = nil then$CR    GSharedEngine := TGameEngine.Create;$CR  FEngine := GSharedEngine;" },
                 @{ Find = '  FEngine.Free;'; Replace = '  { sabotagem SB-07: o motor compartilhado nao e liberado }' }) },
            @{ Id = 'SB-08'; Desc = 'Room.Play não verifica de quem é a vez'; MustFail = @('SL-04');
               Edits = @(
                 @{ Find = "  if Game.CurrentPlayer <> SeatToCell(Seat) then$CR    Exit(Unchanged(rrNotYourTurn));"; Replace = '  { sabotagem SB-08: a vez nao e verificada }' }) },
            @{ Id = 'SB-10'; Desc = 'TRoom.Play sem seção crítica, com Sleep(50) entre a validação e a gravação'; MustFail = @('SC-01');
               Edits = @(
                 @{ Find = "  FLock.Enter;$CR  try$CR    Result := DoPlay(AToken, APosition);$CR  finally$CR    FLock.Leave;$CR  end;"; Replace = "  Result := DoPlay(AToken, APosition);   { sabotagem SB-10: sem secao critica }" },
                 @{ Find = '  MoveResult := FEngine.Play(APosition);'; Replace = "  Sleep(50);   { sabotagem SB-10 }$CR  MoveResult := FEngine.Play(APosition);" }) },
            @{ Id = 'SB-12'; Desc = 'Qualquer token de 32 caracteres é aceito como o lugar da vez'; MustFail = @('SL-07');
               Edits = @(
                 @{ Find = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;";
                    Replace = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;$CR  if (Length(AToken) = 32) and (AToken <> FSeats[seX].Token) and (AToken <> FSeats[seO].Token) then$CR  begin   { sabotagem SB-12 }$CR    if FEngine.GetSnapshot.CurrentPlayer = ceO then$CR      ASeat := seO$CR    else$CR      ASeat := seX;$CR    Exit(True);$CR  end;" }) },
            @{ Id = 'SB-13'; Desc = 'O faxineiro nunca encerra salas'; MustFail = @('SL-11');
               Edits = @(
                 @{ Find = '  if (not AnyConnectedLocked) and (ANowMs - FLastActivity > ATtlMs) then'; Replace = '  if False then   { sabotagem SB-13 }' }) }
        )
        $sabRoot = Join-Path $LogDir 'sabotage'
        foreach ($sb in $sabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $sabRoot $sb.Id
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src'), (Join-Path $dir 'tests') | Out-Null
            Copy-Item (Join-Path $ServerDir 'EngineCheck.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
            Copy-Item (Join-Path $ServerDir 'tests\*.pas') (Join-Path $dir 'tests')
            $target = Join-Path $dir 'src\uRoom.pas'
            $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            $applied = $true
            foreach ($e in $sb.Edits) {
                $count = ([regex]::Matches($text, [regex]::Escape($e.Find))).Count
                if ($count -ne 1) { $applied = $false; Write-Log "Trecho encontrado $count vez(es) (esperado 1): $($e.Find)"; break }
                $text = $text.Replace($e.Find, $e.Replace)
            }
            if (-not $applied) { Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false ''; continue }
            [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($true)))
            $c = Invoke-Compile $dir 'EngineCheck.dpr'
            if ($c.Code -ne 0) {
                Write-Log $c.Output.TrimEnd()
                Add-Check $sb.Id "$($sb.Desc): cópia sabotada compila" $false "Código do dcc32: $($c.Code)"
                continue
            }
            $r = Invoke-Engine (Join-Path $dir 'bin\EngineCheck.exe')
            Set-Content -Path (Join-Path $dir 'EngineCheck-output.log') -Value $r.Output -Encoding UTF8
            $sbFail = Get-CaseIds $r.Output 'FALHOU'
            $notCaught = @($sb.MustFail | Where-Object { $sbFail -notcontains $_ })
            foreach ($line in ($r.Output -split "`r?`n" | Where-Object { $_ -match '^\[FALHOU\]' } | Select-Object -First 8)) { Write-Log "    $line" }
            Write-Log ("Código de saída: {0}; duração {1} s; casos que falharam: {2}" -f $r.Code, $r.Seconds, ($sbFail -join ', '))
            Add-Check $sb.Id "$($sb.Desc): EngineCheck detecta (código 1 e falham $($sb.MustFail -join ', '))" (($r.Code -eq 1) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
        }

        # ---- 7. Regressão Playwright ----------------------------------------
        Write-Log "`n===== 7. Regressão Playwright (109 testes: api 80 + chromium 29)"
        if (-not (Test-Path (Join-Path $TestsDir 'node_modules\@playwright\test'))) { throw 'tests\node_modules não tem o @playwright/test (rode npm ci da Entrega 5).' }
        Write-Log ("Playwright: " + (Invoke-InTests 'npx --no-install playwright --version').Output.Trim())
        foreach ($n in 1..2) {
            Write-Log "`n----- Execução $n"
            $pw = Invoke-InTests 'npx --no-install playwright test'
            Write-Log ((($pw.Output -replace '\x1b\[[0-9;]*m', '') -split "`r?`n" | Where-Object { $_ -match '^\s+\d+ (passed|failed|flaky|skipped|did not run)' }) -join "`r`n")
            $res = Read-Results
            if ($res) { Copy-Item (Join-Path $TestsDir 'test-results\results.json') (Join-Path $LogDir "online-o1-results-run$n.json") -Force }
            Write-Log ("Resultado: " + (Format-Results $res))
            if ($res -and $res.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res.Failed -join "`r`n  ")); Write-Log $pw.Output.TrimEnd() }
            Add-Check "PW-0$n" "Suíte Playwright completa, execução $n`: 109 aprovados (api 80, chromium 29), nenhum falho, instável ou pulado" (($pw.Code -eq 0) -and (Test-Suite109 $res)) (Format-Results $res)
        }
    }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-6} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
