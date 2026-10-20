# Validação da Entrega O2 (API REST de salas e endereço de escuta).
#  1. ambiente; 2. arquivos preservados (git e SHA-256) e formato dos novos;
#  3. compilação (scripts\build.cmd); 4. independência das units sem Indy;
#  5. EngineCheck (45 casos das entregas anteriores + OP-01 = 46);
#  6. checagem de tipos dos testes Playwright;
#  7. suíte Playwright completa com o servidor iniciado pelo Playwright (bind padrão);
#  8. suíte completa de novo, com o servidor iniciado pelo script em --bind 127.0.0.1,
#     e o log desse servidor verificado (sem 5xx, sem tokens);
#  9. OV-08: endereço de escuta (Get-NetTCPConnection) e opções inválidas;
# 10. sabotagens SB-07, SB-08, SB-10 e SB-12 contra o servidor real.
# Com -RedPhase: só 1 a 7, contra os esqueletos de uServerOptions e uRoomHttp.
# Saída em logs\online-o2.log (ou logs\online-o2-red.log). Windows PowerShell 5.1.
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'online-o2-red.log' } else { 'online-o2.log' })
$ServerDir = Join-Path $Root 'server'
$TestsDir  = Join-Path $Root 'tests'
$WebDir    = Join-Path $Root 'web'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'

$OldCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3','M-05-C1','M-05-C2',
    'M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08','M-09','M-10','M-11','M-12',
    'J-01','J-02','J-03','J-04','J-05','SV-01','SV-02','SV-03',
    'SL-01','SL-02','SL-03','SL-04','SL-05','SL-06','SL-07','SL-08','SL-09','SL-10',
    'SL-11','SL-12','MEM-01','SC-01','SC-02','RJ-01','RJ-02','RJ-03')
$NewCases = @('OP-01')
$AllCases = $OldCases + $NewCases
$Expected = @{ api = 80; chromium = 29; 'online-api' = 28 }
$ExpectedTotal = 137

# Arquivos que a O2 não pode alterar, conferidos contra o último commit.
$Preserved = @('server/src/uGameEngine.pas','server/src/uGameService.pas','server/src/uConsoleLog.pas',
    'server/tests/uMiniTest.pas','server/tests/uEngineTests.pas','server/tests/uServiceTests.pas',
    'server/tests/uJsonTests.pas','web','tests/api','tests/rules','tests/ui','tests/support/api.ts',
    'tests/support/fixtures.ts','tests/support/raw-http.ts','tests/support/sequences.ts','tests/support/ui.ts',
    'tests/package.json','tests/package-lock.json','tests/tsconfig.json','docs/test-plan.md')
# Arquivos da O1 (ainda fora do git): SHA-256 das versões aprovadas na O1.
$O1Hashes = [ordered]@{
    'server/src/uClock.pas'                   = '87142FE997345C909B797F2940080A19EDC87A046A83721AD84163D7903F11D5'
    'server/src/uSecureRandom.pas'            = '0323BFDB1586E8FC697DF84AE15422444BEED4BCD72610D0894BB341A11F1F33'
    'server/src/uRoom.pas'                    = '77CABC56139576236E47A9ECA8C7C2519039D90681DB066F7E217C8B2385283A'
    'server/src/uRoomRegistry.pas'            = '803F17485EFCFAF48429E88CB9E229B2A81828C64136E0DA1BA06FD7A3C6AE54'
    'server/src/uRoomJson.pas'                = '6B13B1A128A4020BA909DE301A33D72C3A7632F3FD6BB78228E58AB64FD6D8E0'
    'server/src/uGameJson.pas'                = '5E5F66BA863ED98189EB1E9A9353906D20AD130F283D31E63F5A44B636CE1AD5'
    'server/tests/uRoomTests.pas'             = '48283B3C71D2DC7609E8C7DF2F896615AA320948F97F0547255AAFB2E372CE38'
    'server/tests/uRoomConcurrencyTests.pas'  = 'C3FCC88689F8A46025771B4B2AD00128A77B2717D16927261FB40FBC421662CD'
    'server/tests/uRoomJsonTests.pas'         = '824DC1751170E304F4ACAB0B4F500A84DF5F3827E8C613009F648F8972C02822'
}
$PascalChanged = @('server/src/uServerOptions.pas','server/src/uRoomHttp.pas','server/src/uHttpApp.pas',
    'server/tests/uOptionsTests.pas','server/TicTacToeServer.dpr','server/EngineCheck.dpr')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Content -Path $LogFile -Value '' -Encoding UTF8
$Results = New-Object System.Collections.ArrayList
$Servers = New-Object System.Collections.ArrayList

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

function Test-FullSuite($r) {
    if ($null -eq $r) { return $false }
    if (($r.Stats.expected -ne $ExpectedTotal) -or ($r.Stats.unexpected -ne 0) -or ($r.Stats.flaky -ne 0) -or ($r.Stats.skipped -ne 0)) { return $false }
    foreach ($k in $Expected.Keys) { if (-not $r.ByProject[$k] -or $r.ByProject[$k].ok -ne $Expected[$k]) { return $false } }
    return $true
}

function Write-PlaywrightSummary($run) {
    $clean = $run.Output -replace '\x1b\[[0-9;]*m', ''
    Write-Log ((($clean -split "`r?`n") | Where-Object { $_ -match '^\s+\d+ (passed|failed|flaky|skipped|did not run)' }) -join "`r`n")
}

function Start-Server([string]$Exe, [int]$Port, [string[]]$Extra, [string]$Name) {
    $busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw "A porta $Port já está em uso (processo $($busy[0].OwningProcess))." }
    $procArgs = @('--port', "$Port", '--www', "`"$WebDir`"") + $Extra
    $p = Start-Process -FilePath $Exe -ArgumentList $procArgs -RedirectStandardOutput (Join-Path $LogDir "$Name.out.log") -RedirectStandardError (Join-Path $LogDir "$Name.err.log") -PassThru -WindowStyle Hidden
    [void]$Servers.Add($p)
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
        if ("$code".Trim() -eq '200') { return $p }
        if ($p.HasExited) { throw "Servidor $Name terminou com código $($p.ExitCode)." }
        Start-Sleep -Milliseconds 250
    }
    throw "Servidor $Name não respondeu em 10 s."
}

function Stop-Server($Proc) {
    if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force; $Proc.WaitForExit(5000) | Out-Null }
}

function Invoke-External([int]$Port, [string]$CommandLine) {
    $env:PW_EXTERNAL_SERVER = '1'; $env:PW_PORT = "$Port"
    try { return Invoke-InTests $CommandLine }
    finally { Remove-Item Env:PW_EXTERNAL_SERVER, Env:PW_PORT -ErrorAction SilentlyContinue }
}

function Get-ListenAddresses([int]$Port) {
    return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress } | Sort-Object -Unique)
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega O2 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: uServerOptions e uRoomHttp ainda são esqueletos)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"

    # ---- 1. Ambiente -------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2}); PowerShell {3}" -f $os.Caption, $os.Version, $os.BuildNumber, $PSVersionTable.PSVersion)
    Write-Log ("git: " + (& cmd.exe /c "git --version 2>&1" | Out-String).Trim() + " | Node.js: " + (& cmd.exe /c "node --version 2>&1" | Out-String).Trim())

    # ---- 2. Arquivos preservados e formato --------------------------------
    Write-Log "`n===== 2. Arquivos preservados e formato"
    Push-Location $Root
    try {
        & cmd.exe /c "git diff --quiet HEAD -- $($Preserved -join ' ') 2>&1" | Out-Null
        $quietCode = $LASTEXITCODE
        $diff = (& cmd.exe /c "git diff --stat HEAD -- $($Preserved -join ' ') 2>&1" | Out-String).Trim()
        $cfgDiff = @(& cmd.exe /c "git diff -U0 HEAD -- tests/playwright.config.ts 2>&1" | Where-Object { ($_ -match '^[+-]') -and ($_ -notmatch '^(\+\+\+|---) ') })
        $httpDiff = (& cmd.exe /c "git diff --stat HEAD -- server/src/uHttpApp.pas server/TicTacToeServer.dpr server/EngineCheck.dpr docs/spec.md docs/plan.md README.md 2>&1" | Out-String).Trim()
        $status = (& cmd.exe /c "git status --short --untracked-files=all -- server scripts docs web tests 2>&1" | Out-String).TrimEnd()
    } finally { Pop-Location }
    Write-Log "Conferidos contra o commit: $($Preserved -join ', ')"
    Write-Log ("git diff (preservados): " + $(if ($diff) { $diff } else { '(nenhuma diferença)' }))
    Add-Check 'P-01' 'Motor, serviço, log, testes antigos (EngineCheck e Playwright), interface e plano de testes antigo idênticos ao último commit' ($quietCode -eq 0) "git diff --quiet: código $quietCode"

    $hashProblems = @()
    foreach ($rel in $O1Hashes.Keys) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $hashProblems += "$rel ausente"; continue }
        $h = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
        if ($h -ne $O1Hashes[$rel]) { $hashProblems += "$rel ($h)" }
    }
    Add-Check 'P-02' "Units e testes da O1 idênticos às versões aprovadas (SHA-256 de $($O1Hashes.Count) arquivos)" ($hashProblems.Count -eq 0) ($hashProblems -join '; ')

    Write-Log ("Diferenças de tests/playwright.config.ts:`r`n    " + ($cfgDiff -join "`r`n    "))
    $removed = @($cfgDiff | Where-Object { $_ -like '-*' })
    Add-Check 'P-03' 'playwright.config.ts: só acréscimos (projeto online-api); projetos api e chromium intactos' (($removed.Count -eq 0) -and (@($cfgDiff | Where-Object { $_ -like "+*online-api*" }).Count -eq 1)) ("linhas removidas: {0}" -f $removed.Count)
    Write-Log "Alterações previstas na O2:`r`n$httpDiff"
    Write-Log "git status (server, scripts, docs, web, tests):`r`n$status"

    $badFormat = @()
    foreach ($rel in $PascalChanged) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $badFormat += "$rel (não existe)"; continue }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $lfOnly = ([regex]::Matches([System.Text.Encoding]::UTF8.GetString($bytes), '(?<!\r)\n')).Count
        if (-not $bom -or $lfOnly -gt 0) { $badFormat += "$rel (BOM: $bom; LF sem CR: $lfOnly)" }
    }
    Add-Check 'P-04' 'Units novas e alteradas em UTF-8 com BOM e CRLF (DT-17)' ($badFormat.Count -eq 0) ($badFormat -join '; ')

    # ---- 3. Compilação -----------------------------------------------------
    Write-Log "`n===== 3. Compilação (scripts\build.cmd)"
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`" 2>&1" | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $hints    = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $compiled = ($buildCode -eq 0) -and ($build -match 'compiler version 31\.0') -and (Test-Path $EngineExe) -and (Test-Path $ServerExe)
    Add-Check 'B-01' 'Servidor e EngineCheck compilados pelo Delphi 10.1 Berlin (31.0) sem erros' $compiled "Código $buildCode"
    if ($RedPhase) {
        Write-Log ("Fase vermelha: {0} warning(s) e {1} hint(s) nos esqueletos (não bloqueiam esta fase)." -f $warnings.Count, $hints.Count)
    } else {
        Add-Check 'B-02' 'Nenhum warning nem hint do compilador' (($warnings.Count + $hints.Count) -eq 0) ("Warnings: {0}; hints: {1}; {2}" -f $warnings.Count, $hints.Count, (($warnings + $hints) -join ' | '))
    }
    if (-not (Test-Path $EngineExe) -or -not (Test-Path $ServerExe)) { throw 'Executáveis não gerados.' }

    # ---- 4. Independência --------------------------------------------------
    Write-Log "`n===== 4. Independência das units sem Indy"
    $forbidden = '^(Id\w*|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameService|Vcl\..*|FMX\..*)$'
    $indep = @()
    foreach ($u in @('uServerOptions','uRoomHttp','uClock','uSecureRandom','uRoom','uRoomRegistry','uRoomJson')) {
        $src = Get-Content (Join-Path $ServerDir "src\$u.pas") -Raw -Encoding UTF8
        $src = [regex]::Replace($src, '(?s)\{.*?\}|\(\*.*?\*\)', '')
        $usesText = (([regex]::Matches($src, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',')
        $used = @($usesText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $bad = @($used | Where-Object { $_ -match $forbidden })
        if ($src -match '(?i)\bWriteln\b|\bLog\s*\(') { $bad += 'escrita de log/console' }
        Write-Log ("{0}: {1}" -f $u, ($used -join ', '))
        if ($bad.Count) { $indep += "$u -> $($bad -join ', ')" }
    }
    Add-Check 'I-01' 'uServerOptions, uRoomHttp e as units da O1 sem Indy, sem servidor e sem log' ($indep.Count -eq 0) ($indep -join '; ')

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
    if ($RedPhase) {
        Add-Check 'R-01' 'Fase vermelha: EngineCheck sai com código 1' ($run.Code -eq 1) "Código $($run.Code)"
        Add-Check 'R-02' 'Fase vermelha: os 46 casos executados' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($seen.Count -eq 46)) ("Ausentes: {0}; a mais: {1}" -f ($missing -join ', '), ($extra -join ', '))
        Add-Check 'R-03' 'Fase vermelha: os 45 casos anteriores aprovados e o OP-01 falha' (($oldFailed.Count -eq 0) -and ($failIds -contains 'OP-01')) ("Anteriores que falharam: " + ($oldFailed -join ', '))
    } else {
        Add-Check 'E-01' 'EngineCheck sai com código 0 e diz RESULTADO: APROVADO' (($run.Code -eq 0) -and ($run.Output -match 'RESULTADO: APROVADO')) "Código $($run.Code)"
        Add-Check 'E-02' '46 casos executados e aprovados (45 anteriores + OP-01)' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($failIds.Count -eq 0) -and ($okIds.Count -eq 46)) ("OK: {0}; falharam: {1}; ausentes: {2}; a mais: {3}" -f $okIds.Count, ($failIds -join ','), ($missing -join ','), ($extra -join ','))
        $repeatOk = $true; $repeatInfo = @()
        foreach ($n in 2..3) {
            $rr = Invoke-Engine $EngineExe
            $rf = Get-CaseIds $rr.Output 'FALHOU'; $ro = Get-CaseIds $rr.Output 'OK'
            $repeatInfo += ("execução {0}: código {1}, {2} OK, falharam [{3}], {4} s" -f $n, $rr.Code, $ro.Count, ($rf -join ','), $rr.Seconds)
            if (($rr.Code -ne 0) -or ($rf.Count -gt 0) -or ($ro.Count -ne 46)) { $repeatOk = $false; Write-Log $rr.Output.TrimEnd() }
        }
        Add-Check 'E-03' 'EngineCheck aprovado em mais duas execuções seguidas (46/46 em cada)' $repeatOk ($repeatInfo -join ' | ')
    }

    # ---- 6. Tipos ----------------------------------------------------------
    Write-Log "`n===== 6. Checagem de tipos dos testes (tsc --noEmit)"
    if (-not (Test-Path (Join-Path $TestsDir 'node_modules\@playwright\test'))) { throw 'tests\node_modules não tem o @playwright/test (rode npm ci da Entrega 5).' }
    Write-Log ("Playwright: " + (Invoke-InTests 'npx --no-install playwright --version').Output.Trim())
    $tsc = Invoke-InTests 'npm run typecheck'
    Write-Log $tsc.Output.TrimEnd()
    Add-Check 'T-01' 'TypeScript sem erros (suíte antiga e testes novos)' ($tsc.Code -eq 0) "Código $($tsc.Code)"

    # ---- 7. Suíte completa, servidor do Playwright (bind padrão) -------------
    Write-Log "`n===== 7. Suíte completa (api, chromium, online-api), servidor iniciado pelo Playwright (bind padrão 0.0.0.0)"
    $resultsFile = Join-Path $TestsDir 'test-results\results.json'
    if (Test-Path $resultsFile) { Remove-Item $resultsFile -Force }
    $pw = Invoke-InTests 'npx --no-install playwright test'
    Write-PlaywrightSummary $pw
    $res = Read-Results
    if ($res) { Copy-Item (Join-Path $TestsDir 'test-results\results.json') (Join-Path $LogDir "online-o2$(if ($RedPhase) { '-red' })-results-run1.json") -Force }
    Write-Log ("Resultado: " + (Format-Results $res))
    if ($res -and $res.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res.Failed -join "`r`n  ")) }
    if ($RedPhase) {
        $okRed = $res -and ($res.ByProject['api'].ok -eq 80) -and ($res.ByProject['chromium'].ok -eq 29) -and ($res.ByProject['online-api'].fail -eq 28)
        Add-Check 'R-04' 'Fase vermelha: api 80 e chromium 29 aprovados; os 28 testes online-api falham' ([bool]$okRed) (Format-Results $res)
    } else {
        if ($res -and $res.Failed.Count) { Write-Log $pw.Output.TrimEnd() }
        Add-Check 'PW-01' "Suíte completa, execução 1 (bind padrão): $ExpectedTotal aprovados (api 80, chromium 29, online-api 28)" (($pw.Code -eq 0) -and (Test-FullSuite $res)) (Format-Results $res)

        # ---- 8. Suíte completa com --bind 127.0.0.1 e log do servidor -------
        Write-Log "`n===== 8. Suíte completa de novo, servidor iniciado pelo script com --bind 127.0.0.1"
        $srv = Start-Server $ServerExe 8765 @('--bind', '127.0.0.1') 'server-o2'
        $listen = @(Get-ListenAddresses 8765)
        Write-Log ("Escuta na porta 8765: " + ($listen -join ', '))
        if (Test-Path $resultsFile) { Remove-Item $resultsFile -Force }
        $pw2 = Invoke-External 8765 'npx --no-install playwright test'
        Stop-Server $srv
        Write-PlaywrightSummary $pw2
        $res2 = Read-Results
        if ($res2) { Copy-Item (Join-Path $TestsDir 'test-results\results.json') (Join-Path $LogDir 'online-o2-results-run2.json') -Force }
        Write-Log ("Resultado: " + (Format-Results $res2))
        if ($res2 -and $res2.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res2.Failed -join "`r`n  ")); Write-Log $pw2.Output.TrimEnd() }
        Add-Check 'PW-02' "Suíte completa, execução 2 (--bind 127.0.0.1): $ExpectedTotal aprovados, as outras rotas iguais" (($pw2.Code -eq 0) -and (Test-FullSuite $res2) -and ($listen.Count -eq 1) -and ($listen[0] -eq '127.0.0.1')) (Format-Results $res2)

        $srvLog = @(Get-Content (Join-Path $LogDir 'server-o2.out.log') -Encoding UTF8)
        Write-Log ("Primeiras linhas do log do servidor:`r`n" + (($srvLog | Select-Object -First 6) -join "`r`n"))
        $bad = @($srvLog | Where-Object { $_ -match '-> 5\d\d|ERRO em|AVISO|Erro fatal' })
        $tokens = @($srvLog | Where-Object { $_ -match '(?i)\b[0-9a-f]{32}\b|Bearer|Authorization' })
        $roomLines = @($srvLog | Where-Object { $_ -match ' /api/rooms' }).Count
        Write-Log ("Linhas no log: {0}; requisições de sala: {1}" -f $srvLog.Count, $roomLines)
        Add-Check 'S-01' 'Log do servidor sem 5xx, exceções ou avisos' (($bad.Count -eq 0) -and ($roomLines -gt 0)) (($bad | Select-Object -First 3) -join ' | ')
        Add-Check 'S-02' 'Nenhum token (32 hex), "Bearer" ou "Authorization" no log do servidor' ($tokens.Count -eq 0) (($tokens | Select-Object -First 3) -join ' | ')

        # Concorrência por HTTP repetida: o OR-18 (360 requisições de uma vez) mais 5 vezes.
        Write-Log "`n----- OR-16 a OR-18 repetidos 5 vezes (servidor do Playwright, bind padrão)"
        if (Test-Path $resultsFile) { Remove-Item $resultsFile -Force }
        $pw3 = Invoke-InTests 'npx --no-install playwright test --project online-api --grep "OR-1[678]" --repeat-each 5'
        Write-PlaywrightSummary $pw3
        $res3 = Read-Results
        Write-Log ("Resultado: " + (Format-Results $res3))
        if ($res3 -and $res3.Failed.Count) { Write-Log $pw3.Output.TrimEnd() }
        Add-Check 'PW-03' 'Concorrência HTTP (OR-16, OR-17, OR-18) aprovada em 5 repetições seguidas (15 de 15)' (($pw3.Code -eq 0) -and $res3 -and ($res3.Stats.expected -eq 15) -and ($res3.Stats.unexpected -eq 0) -and ($res3.Stats.flaky -eq 0)) (Format-Results $res3)

        # ---- 9. OV-08: endereço de escuta ------------------------------------
        Write-Log "`n===== 9. OV-08: endereço de escuta e opções inválidas"
        $lanIp = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.AddressState -eq 'Preferred' } | Sort-Object InterfaceMetric | ForEach-Object { $_.IPAddress }) | Select-Object -First 1
        Write-Log ("IPv4 da rede local usado no teste: " + $(if ($lanIp) { $lanIp } else { '(nenhum)' }))
        $cases = @(
            @{ Id = 'OV-08a'; Port = 8781; Args = @(); Expect = '0.0.0.0'; Lan = 200 },
            @{ Id = 'OV-08b'; Port = 8782; Args = @('--bind', '127.0.0.1'); Expect = '127.0.0.1'; Lan = 0 },
            @{ Id = 'OV-08c'; Port = 8783; Args = @('--public'); Expect = '127.0.0.1'; Lan = 0 }
        )
        foreach ($c in $cases) {
            $s = Start-Server $ServerExe $c.Port $c.Args ("server-o2-" + $c.Id)
            $addr = @(Get-ListenAddresses $c.Port)
            $local = & curl.exe -s -o NUL -w '%{http_code}' --max-time 2 "http://127.0.0.1:$($c.Port)/health" 2>$null
            $lanCode = if ($lanIp) { "$(& curl.exe -s -o NUL -w '%{http_code}' --max-time 2 "http://$($lanIp):$($c.Port)/health" 2>$null)".Trim() } else { 'n/d' }
            $rooms = & curl.exe -s -o NUL -w '%{http_code}' --max-time 2 -X POST "http://127.0.0.1:$($c.Port)/api/rooms" 2>$null
            $game = & curl.exe -s -o NUL -w '%{http_code}' --max-time 2 "http://127.0.0.1:$($c.Port)/api/game" 2>$null
            Stop-Server $s
            $lanOk = if (-not $lanIp) { $true } elseif ($c.Lan -eq 200) { $lanCode -eq '200' } else { $lanCode -ne '200' }
            $ok = ($addr.Count -eq 1) -and ($addr[0] -eq $c.Expect) -and ("$local".Trim() -eq '200') -and $lanOk -and ("$rooms".Trim() -eq '201') -and ("$game".Trim() -eq '200')
            Add-Check $c.Id ("Opções [{0}]: escuta só em {1}; /health local 200; pelo IP da rede {2}; /api/rooms 201; /api/game 200" -f ($c.Args -join ' '), $c.Expect, $(if ($c.Lan -eq 200) { '200' } else { 'sem resposta' })) $ok ("escuta: {0}; local {1}; rede {2}; rooms {3}; game {4}" -f ($addr -join ','), "$local".Trim(), $lanCode, "$rooms".Trim(), "$game".Trim())
        }
        $badOpts = @(@('--port', '0'), @('--bind', '999.1.1.1'), @('--bind'), @('--bnd', '127.0.0.1'), @('--room-ttl-seconds', '-5'))
        $optProblems = @()
        foreach ($o in $badOpts) {
            $p = Start-Process -FilePath $ServerExe -ArgumentList $o -RedirectStandardOutput (Join-Path $LogDir 'server-o2-badopt.out.log') -RedirectStandardError (Join-Path $LogDir 'server-o2-badopt.err.log') -PassThru -WindowStyle Hidden -Wait
            $msg = (Get-Content (Join-Path $LogDir 'server-o2-badopt.out.log') -Raw -Encoding UTF8)
            Write-Log ("    [{0}] -> código {1}: {2}" -f ($o -join ' '), $p.ExitCode, "$msg".Trim())
            if (($p.ExitCode -ne 2) -or ("$msg" -notmatch 'Parâmetros inválidos')) { $optProblems += ($o -join ' ') }
        }
        Add-Check 'OV-08d' 'Opções inválidas: o servidor sai com código 2 e mostra o uso' ($optProblems.Count -eq 0) ($optProblems -join '; ')

        # ---- 10. Sabotagens contra o servidor real ----------------------------
        Write-Log "`n===== 10. Sabotagens (cópias do servidor em logs\sabotage; o código original não é alterado)"
        $CR = "`r`n"
        $sabotages = @(
            @{ Id = 'SB-07'; Desc = 'Todas as salas compartilham o mesmo TGameEngine'; Grep = 'OR-10|OR-13|OR-18'; MustFail = @('OR-10', 'OR-13', 'OR-18');
               Edits = @(
                 @{ Find = '{ ---- TRoom ---'; Replace = "var$CR  GSharedEngine: TGameEngine;   { sabotagem SB-07 }$CR$CR{ ---- TRoom ---" },
                 @{ Find = '  FEngine := TGameEngine.Create;'; Replace = "  if GSharedEngine = nil then$CR    GSharedEngine := TGameEngine.Create;$CR  FEngine := GSharedEngine;" },
                 @{ Find = '  FEngine.Free;'; Replace = '  { sabotagem SB-07: o motor compartilhado nao e liberado }' }) },
            @{ Id = 'SB-08'; Desc = 'Room.Play não verifica de quem é a vez'; Grep = 'OR-02|OR-08|OR-16|OR-17'; MustFail = @('OR-02', 'OR-08', 'OR-16');
               Edits = @(
                 @{ Find = "  if Game.CurrentPlayer <> SeatToCell(Seat) then$CR    Exit(Unchanged(rrNotYourTurn));"; Replace = '  { sabotagem SB-08: a vez nao e verificada }' }) },
            @{ Id = 'SB-10'; Desc = 'TRoom.Play sem seção crítica, com Sleep(50) entre a validação e a gravação'; Grep = 'OR-16|OR-17'; MustFail = @('OR-16');
               Edits = @(
                 @{ Find = "  FLock.Enter;$CR  try$CR    Result := DoPlay(AToken, APosition);$CR  finally$CR    FLock.Leave;$CR  end;"; Replace = "  Result := DoPlay(AToken, APosition);   { sabotagem SB-10: sem secao critica }" },
                 @{ Find = '  MoveResult := FEngine.Play(APosition);'; Replace = "  Sleep(50);   { sabotagem SB-10 }$CR  MoveResult := FEngine.Play(APosition);" }) },
            @{ Id = 'SB-12'; Desc = 'Qualquer token de 32 caracteres é aceito como o lugar da vez'; Grep = 'OR-06'; MustFail = @('OR-06');
               Edits = @(
                 @{ Find = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;";
                    Replace = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;$CR  if (Length(AToken) = 32) and (AToken <> FSeats[seX].Token) and (AToken <> FSeats[seO].Token) then$CR  begin   { sabotagem SB-12 }$CR    if FEngine.GetSnapshot.CurrentPlayer = ceO then$CR      ASeat := seO$CR    else$CR      ASeat := seX;$CR    Exit(True);$CR  end;" }) }
        )
        foreach ($sb in $sabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o2"
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
            Copy-Item (Join-Path $ServerDir 'TicTacToeServer.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
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
            $c = Invoke-Compile $dir 'TicTacToeServer.dpr'
            if ($c.Code -ne 0) { Write-Log $c.Output.TrimEnd(); Add-Check $sb.Id "$($sb.Desc): cópia sabotada compila" $false "Código $($c.Code)"; continue }
            $sab = Start-Server (Join-Path $dir 'bin\TicTacToeServer.exe') 8766 @('--bind', '127.0.0.1') ("server-o2-" + $sb.Id)
            $stale = Join-Path $TestsDir 'test-results\results.json'
            if (Test-Path $stale) { Remove-Item $stale -Force }
            $r = Invoke-External 8766 "npx --no-install playwright test --project online-api --grep `"$($sb.Grep)`""
            Stop-Server $sab
            $sres = Read-Results
            $failedIds = @()
            if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, 'OR-\d\d')) { $failedIds += $m.Value } } }
            $failedIds = @($failedIds | Sort-Object -Unique)
            $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
            Write-Log ("Código: {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
            # Motivo das falhas, para conferir que vêm da sabotagem e não de outra causa.
            $why = @((($r.Output -replace '\x1b\[[0-9;]*m', '') -split "`r?`n") | Where-Object { $_ -match '^\s+(Error:|Expected|Received|\+|-)\s' -or $_ -match '\d+\) \[online-api\]' } | Select-Object -First 24)
            foreach ($w in $why) { Write-Log ("    " + $w.TrimEnd()) }
            Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
        }
    }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    foreach ($s in $Servers) { Stop-Server $s }
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-7} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
