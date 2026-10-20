# Validação da Entrega O3 (canal em tempo real e política de origem).
#  1. ambiente; 2. arquivos preservados (git e SHA-256) e formato dos novos;
#  3. compilação; 4. independência das units sem Indy;
#  5. EngineCheck (46 casos anteriores + OP-02, WS-01 a WS-07, HB-01 a HB-03 = 57);
#  6. checagem de tipos dos testes Playwright;
#  7. suíte completa com o servidor do Playwright (bind padrão);
#  8. suíte completa com o servidor do script (--bind 127.0.0.1) e o log dele verificado;
#  9. repetições: canal (online-ws) e concorrência HTTP;
# 10. Ctrl+C com 10 canais abertos (todos recebem 1001; saída 0 em até 5 s);
# 11. sabotagens SB-11, SB-12, SB-14 e SB-15 (EngineCheck e servidor real).
# Com -RedPhase: só 1 a 7, contra os esqueletos de uWebSocket, uOriginPolicy e uRoomHub.
# Saída em logs\online-o3.log (ou logs\online-o3-red.log). Windows PowerShell 5.1.
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'online-o3-red.log' } else { 'online-o3.log' })
$ServerDir = Join-Path $Root 'server'
$TestsDir  = Join-Path $Root 'tests'
$WebDir    = Join-Path $Root 'web'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$CtrlC     = Join-Path $Root 'scripts\send-ctrl-c.ps1'
$ResultsFile = Join-Path $TestsDir 'test-results\results.json'

$OldCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3','M-05-C1','M-05-C2',
    'M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08','M-09','M-10','M-11','M-12',
    'J-01','J-02','J-03','J-04','J-05','SV-01','SV-02','SV-03',
    'SL-01','SL-02','SL-03','SL-04','SL-05','SL-06','SL-07','SL-08','SL-09','SL-10',
    'SL-11','SL-12','MEM-01','SC-01','SC-02','RJ-01','RJ-02','RJ-03','OP-01')
$NewCases = @('OP-02','WS-01','WS-02','WS-03','WS-04','WS-05','WS-06','WS-07','HB-01','HB-02','HB-03')
$AllCases = $OldCases + $NewCases
$Expected = [ordered]@{ api = 80; chromium = 29; 'online-api' = 30; 'online-ws' = 18; 'online-lifecycle' = 4 }
$ExpectedTotal = 161

$Preserved = @('server/src/uGameEngine.pas','server/src/uGameService.pas','server/src/uConsoleLog.pas',
    'server/tests/uMiniTest.pas','server/tests/uEngineTests.pas','server/tests/uServiceTests.pas',
    'server/tests/uJsonTests.pas','web','tests/api','tests/rules','tests/ui','tests/support/api.ts',
    'tests/support/fixtures.ts','tests/support/raw-http.ts','tests/support/sequences.ts','tests/support/ui.ts',
    'tests/package.json','tests/package-lock.json','tests/tsconfig.json','docs/test-plan.md')
# Arquivos das entregas O1 e O2 que a O3 não altera (ainda fora do git): SHA-256 aprovados.
$Hashes = [ordered]@{
    'server/src/uClock.pas'                   = '87142FE997345C909B797F2940080A19EDC87A046A83721AD84163D7903F11D5'
    'server/src/uSecureRandom.pas'            = '0323BFDB1586E8FC697DF84AE15422444BEED4BCD72610D0894BB341A11F1F33'
    'server/src/uRoom.pas'                    = '77CABC56139576236E47A9ECA8C7C2519039D90681DB066F7E217C8B2385283A'
    'server/src/uRoomRegistry.pas'            = '803F17485EFCFAF48429E88CB9E229B2A81828C64136E0DA1BA06FD7A3C6AE54'
    'server/src/uRoomJson.pas'                = '6B13B1A128A4020BA909DE301A33D72C3A7632F3FD6BB78228E58AB64FD6D8E0'
    'server/src/uGameJson.pas'                = '5E5F66BA863ED98189EB1E9A9353906D20AD130F283D31E63F5A44B636CE1AD5'
    'server/tests/uRoomTests.pas'             = '48283B3C71D2DC7609E8C7DF2F896615AA320948F97F0547255AAFB2E372CE38'
    'server/tests/uRoomConcurrencyTests.pas'  = 'C3FCC88689F8A46025771B4B2AD00128A77B2717D16927261FB40FBC421662CD'
    'server/tests/uRoomJsonTests.pas'         = '824DC1751170E304F4ACAB0B4F500A84DF5F3827E8C613009F648F8972C02822'
    'tests/online/room-api/contract.spec.ts'  = '14D49275266D677AEC65C1083D86B706CE48D9350F3247A44AFD160E5037B74F'
    'tests/online/room-api/errors.spec.ts'    = 'C155D577751EBE8C25FECD578E465FE5A1222F55DDEB4773675DF2544D437B65'
    'tests/online/room-api/routes.spec.ts'    = 'BC7F23A7BF8D6F687E3955DF8C31DDB4FC573F34A6BF9464B38E8B17430E323C'
    'tests/online/room-rules/concurrency.spec.ts' = 'A74188A5CC57E91D78DE18CE30CFE2B7E0E3AF18EB2720C6D529E2C2F4047057'
    'tests/online/room-rules/games.spec.ts'   = '3235385F25760CCE528DB1B4CC2F62E5C02FE81DD1BD46441363601FE82A14FC'
    'tests/online/room-rules/moves.spec.ts'   = '83246670BD6CA2E6154D4D0D834728BBCEB2BE310ED0E5EA13B7975333E981AD'
    'docs/spec.md'                            = 'D47723E3C479BFACC4F90349DD0ED39417B4EE7EBC5460FC7DE1B1060E1C3C02'
    'docs/plan.md'                            = 'EF473161A5B52CAE689AC03713D29E97F73EB23A4B35B624C3FC3F8AD426E069'
}
# Texto do procedimento OP01_Options aprovado na O2 (o arquivo ganhou o OP-02).
$Op01Hash = '90286614FFF92F822ECCDA8F61622F9E8408D96F0728CED569C5E3D244A55500'
$PascalChanged = @('server/src/uWebSocket.pas','server/src/uOriginPolicy.pas','server/src/uRoomHub.pas',
    'server/src/uWsSession.pas','server/src/uRoomHttp.pas','server/src/uServerOptions.pas','server/src/uHttpApp.pas',
    'server/tests/uWebSocketTests.pas','server/tests/uRoomHubTests.pas','server/tests/uOptionsTests.pas',
    'server/TicTacToeServer.dpr','server/EngineCheck.dpr')

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

function Invoke-Playwright([string]$CommandLine, [hashtable]$Env = @{}) {
    if (Test-Path $ResultsFile) { Remove-Item $ResultsFile -Force }
    foreach ($k in $Env.Keys) { Set-Item -Path "Env:$k" -Value $Env[$k] }
    try { return Invoke-InTests $CommandLine }
    finally { foreach ($k in $Env.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue } }
}

function Read-Results {
    if (-not (Test-Path $ResultsFile)) { return $null }
    $json = Get-Content $ResultsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $byProject = @{}
    $failedTitles = New-Object System.Collections.ArrayList
    $walk = $null
    $walk = {
        param($suite)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                $p = $t.projectName
                if (-not $byProject.ContainsKey($p)) { $byProject[$p] = @{ ok = 0; fail = 0 } }
                $ok = $true
                foreach ($r in @($t.results)) { if ($r.status -ne 'passed') { $ok = $false } }
                if ($t.status -eq 'expected' -and $ok) { $byProject[$p].ok++ } else { $byProject[$p].fail++; [void]$failedTitles.Add("[$p] $($spec.title)") }
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

function Write-FailureExcerpt($run, [int]$Max = 30) {
    $clean = $run.Output -replace '\x1b\[[0-9;]*m', ''
    $why = @(($clean -split "`r?`n") | Where-Object { $_ -match '^\s+(Error:|Expected|Received|\+|-)\s' -or $_ -match '^\s+\d+\) \[' } | Select-Object -First $Max)
    foreach ($w in $why) { Write-Log ("    " + $w.TrimEnd()) }
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

function Test-ServerLog([string]$Path, [string]$Id, [string]$What) {
    $lines = @(Get-Content $Path -Encoding UTF8)
    $bad = @($lines | Where-Object { $_ -match '-> 5\d\d|ERRO em|ERRO inesperado|AVISO|Erro fatal' })
    $tokens = @($lines | Where-Object { $_ -match '(?i)\b[0-9a-f]{32}\b|Bearer|Authorization' })
    $opened = @($lines | Where-Object { $_ -match 'WS \d+ aberta' }).Count
    $closed = @($lines | Where-Object { $_ -match 'WS \d+ fechada' }).Count
    $origins = ($lines | Where-Object { $_ -match 'Origens permitidas' } | Select-Object -First 1)
    Write-Log ("{0}: {1} linhas; canais abertos {2}, fechados {3}; {4}" -f $What, $lines.Count, $opened, $closed, $origins)
    Add-Check $Id "$What sem 5xx, exceções ou avisos; nenhum token; todo canal aberto foi fechado" (($bad.Count -eq 0) -and ($tokens.Count -eq 0) -and ($opened -eq $closed) -and ($opened -gt 0) -and $origins) ((@($bad + $tokens) | Select-Object -First 3) -join ' | ')
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega O3 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: uWebSocket, uOriginPolicy e uRoomHub ainda são esqueletos)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"

    # ---- 1. Ambiente -------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2}); PowerShell {3}" -f $os.Caption, $os.Version, $os.BuildNumber, $PSVersionTable.PSVersion)
    Write-Log ("git: " + (& cmd.exe /c "git --version 2>&1" | Out-String).Trim() + " | Node.js: " + (& cmd.exe /c "node --version 2>&1" | Out-String).Trim())

    # ---- 2. Preservados e formato -----------------------------------------
    Write-Log "`n===== 2. Arquivos preservados e formato"
    Push-Location $Root
    try {
        & cmd.exe /c "git diff --quiet HEAD -- $($Preserved -join ' ') 2>&1" | Out-Null
        $quietCode = $LASTEXITCODE
        $cfgDiff = @(& cmd.exe /c "git diff -U0 HEAD -- tests/playwright.config.ts 2>&1" | Where-Object { ($_ -match '^[+-]') -and ($_ -notmatch '^(\+\+\+|---) ') })
        $status = (& cmd.exe /c "git status --short --untracked-files=all -- server scripts docs web tests 2>&1" | Out-String).TrimEnd()
    } finally { Pop-Location }
    Add-Check 'P-01' 'Motor, serviço, log, testes antigos (EngineCheck e Playwright), interface e plano de testes antigo idênticos ao último commit' ($quietCode -eq 0) "git diff --quiet: código $quietCode"
    $hashProblems = @()
    foreach ($rel in $Hashes.Keys) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $hashProblems += "$rel ausente"; continue }
        $h = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
        if ($h -ne $Hashes[$rel]) { $hashProblems += "$rel ($h)" }
    }
    Add-Check 'P-02' "Arquivos das O1 e O2 não alterados pela O3 idênticos aos aprovados (SHA-256 de $($Hashes.Count) arquivos)" ($hashProblems.Count -eq 0) ($hashProblems -join '; ')
    $optText = [System.IO.File]::ReadAllText((Join-Path $ServerDir 'tests\uOptionsTests.pas'), [System.Text.Encoding]::UTF8)
    $op01 = [regex]::Match($optText, '(?s)procedure OP01_Options;.*?\r\nend;').Value
    $op01Hash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($op01))).Replace('-', '')
    Add-Check 'P-03' 'OP-01 (procedimento OP01_Options) idêntico ao aprovado na O2' ($op01Hash -eq $Op01Hash) "SHA-256 $op01Hash"
    Write-Log ("Diferenças de tests/playwright.config.ts em relação ao commit:`r`n    " + ($cfgDiff -join "`r`n    "))
    $removed = @($cfgDiff | Where-Object { $_ -like '-*' })
    Add-Check 'P-04' 'playwright.config.ts: só acréscimos (projetos online-api, online-ws, online-lifecycle)' ($removed.Count -eq 0) ("linhas removidas: {0}" -f $removed.Count)
    Write-Log "git status:`r`n$status"
    $badFormat = @()
    foreach ($rel in $PascalChanged) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $badFormat += "$rel (não existe)"; continue }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $lfOnly = ([regex]::Matches([System.Text.Encoding]::UTF8.GetString($bytes), '(?<!\r)\n')).Count
        if (-not $bom -or $lfOnly -gt 0) { $badFormat += "$rel (BOM: $bom; LF sem CR: $lfOnly)" }
    }
    Add-Check 'P-05' 'Units novas e alteradas em UTF-8 com BOM e CRLF (DT-17)' ($badFormat.Count -eq 0) ($badFormat -join '; ')

    # ---- 3. Compilação -----------------------------------------------------
    Write-Log "`n===== 3. Compilação (scripts\build.cmd)"
    # Servidores deste projeto que sobraram de uma execução interrompida prendem o .exe.
    $binDir = (Join-Path $ServerDir 'bin').ToLowerInvariant()
    foreach ($old in @(Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe' OR Name = 'EngineCheck.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.ToLowerInvariant().StartsWith($binDir) })) {
        Write-Log "Processo de execução anterior ainda aberto: $($old.Name) PID $($old.ProcessId) ($($old.CommandLine)); encerrado."
        Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`" 2>&1" | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $hints    = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$') | ForEach-Object { $_.Value.Trim() })
    Add-Check 'B-01' 'Servidor e EngineCheck compilados pelo Delphi 10.1 Berlin (31.0) sem erros' (($buildCode -eq 0) -and ($build -match 'compiler version 31\.0') -and (Test-Path $EngineExe) -and (Test-Path $ServerExe)) "Código $buildCode"
    if ($RedPhase) {
        Write-Log ("Fase vermelha: {0} warning(s) e {1} hint(s) (não bloqueiam esta fase)." -f $warnings.Count, $hints.Count)
    } else {
        Add-Check 'B-02' 'Nenhum warning nem hint do compilador' (($warnings.Count + $hints.Count) -eq 0) ("Warnings: {0}; hints: {1}; {2}" -f $warnings.Count, $hints.Count, (($warnings + $hints) -join ' | '))
    }
    if (-not (Test-Path $EngineExe) -or -not (Test-Path $ServerExe)) { throw 'Executáveis não gerados.' }

    # ---- 4. Independência --------------------------------------------------
    Write-Log "`n===== 4. Independência das units sem Indy"
    $forbidden = '^(Id\w*|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameService|uWsSession|Vcl\..*|FMX\..*)$'
    $indep = @()
    foreach ($u in @('uWebSocket','uOriginPolicy','uRoomHub','uServerOptions','uRoomHttp','uClock','uSecureRandom','uRoom','uRoomRegistry','uRoomJson')) {
        $src = Get-Content (Join-Path $ServerDir "src\$u.pas") -Raw -Encoding UTF8
        $src = [regex]::Replace($src, '(?s)\{.*?\}|\(\*.*?\*\)', '')
        $usesText = (([regex]::Matches($src, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',')
        $used = @($usesText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $bad = @($used | Where-Object { $_ -match $forbidden })
        if ($src -match '(?i)\bWriteln\b|\bLog\s*\(') { $bad += 'escrita de log/console' }
        Write-Log ("{0}: {1}" -f $u, ($used -join ', '))
        if ($bad.Count) { $indep += "$u -> $($bad -join ', ')" }
    }
    Add-Check 'I-01' 'Protocolo, origem, hub, opções, rotas de sala e domínio sem Indy, sem servidor e sem log (DTO-21)' ($indep.Count -eq 0) ($indep -join '; ')

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
        $newFailed = @($NewCases | Where-Object { $failIds -contains $_ })
        Add-Check 'R-01' 'Fase vermelha: EngineCheck sai com código 1' ($run.Code -eq 1) "Código $($run.Code)"
        Add-Check 'R-02' 'Fase vermelha: os 57 casos executados' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($seen.Count -eq 57)) ("Ausentes: {0}; a mais: {1}" -f ($missing -join ', '), ($extra -join ', '))
        Add-Check 'R-03' 'Fase vermelha: os 46 casos anteriores aprovados' ($oldFailed.Count -eq 0) ("Anteriores que falharam: " + ($oldFailed -join ', '))
        Add-Check 'R-04' 'Fase vermelha: os casos novos falham contra os esqueletos' ($newFailed.Count -gt 0) ("Falharam {0} de {1}: {2}" -f $newFailed.Count, $NewCases.Count, ($newFailed -join ', '))
        Write-Log ("Casos novos que passaram contra o esqueleto: " + (@($NewCases | Where-Object { $okIds -contains $_ }) -join ', '))
    } else {
        Add-Check 'E-01' 'EngineCheck sai com código 0 e diz RESULTADO: APROVADO' (($run.Code -eq 0) -and ($run.Output -match 'RESULTADO: APROVADO')) "Código $($run.Code)"
        Add-Check 'E-02' '57 casos executados e aprovados (46 anteriores + 11 da O3)' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($failIds.Count -eq 0) -and ($okIds.Count -eq 57)) ("OK: {0}; falharam: {1}; ausentes: {2}; a mais: {3}" -f $okIds.Count, ($failIds -join ','), ($missing -join ','), ($extra -join ','))
        $repeatOk = $true; $repeatInfo = @()
        foreach ($n in 2..3) {
            $rr = Invoke-Engine $EngineExe
            $rf = Get-CaseIds $rr.Output 'FALHOU'; $ro = Get-CaseIds $rr.Output 'OK'
            $repeatInfo += ("execução {0}: código {1}, {2} OK, falharam [{3}], {4} s" -f $n, $rr.Code, $ro.Count, ($rf -join ','), $rr.Seconds)
            if (($rr.Code -ne 0) -or ($rf.Count -gt 0) -or ($ro.Count -ne 57)) { $repeatOk = $false; Write-Log $rr.Output.TrimEnd() }
        }
        Add-Check 'E-03' 'EngineCheck aprovado em mais duas execuções seguidas (57/57 em cada)' $repeatOk ($repeatInfo -join ' | ')
    }

    # ---- 6. Tipos ----------------------------------------------------------
    Write-Log "`n===== 6. Checagem de tipos dos testes (tsc --noEmit)"
    if (-not (Test-Path (Join-Path $TestsDir 'node_modules\@playwright\test'))) { throw 'tests\node_modules não tem o @playwright/test (rode npm ci da Entrega 5).' }
    Write-Log ("Playwright: " + (Invoke-InTests 'npx --no-install playwright --version').Output.Trim())
    $tsc = Invoke-InTests 'npm run typecheck'
    Write-Log $tsc.Output.TrimEnd()
    Add-Check 'T-01' 'TypeScript sem erros (suíte antiga e testes novos)' ($tsc.Code -eq 0) "Código $($tsc.Code)"

    # ---- 7. Suíte completa, servidor do Playwright -------------------------
    Write-Log "`n===== 7. Suíte completa, servidor iniciado pelo Playwright (bind padrão 0.0.0.0)"
    $pw = Invoke-Playwright 'npx --no-install playwright test'
    Write-PlaywrightSummary $pw
    $res = Read-Results
    if ($res) { Copy-Item $ResultsFile (Join-Path $LogDir "online-o3$(if ($RedPhase) { '-red' })-results-run1.json") -Force }
    Write-Log ("Resultado: " + (Format-Results $res))
    if ($res -and $res.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res.Failed -join "`r`n  ")); Write-FailureExcerpt $pw 60 }
    if ($RedPhase) {
        $newOk = 0
        foreach ($k in @('online-ws', 'online-lifecycle')) { if ($res -and $res.ByProject[$k]) { $newOk += $res.ByProject[$k].ok } }
        $okRed = $res -and ($res.ByProject['api'].ok -eq 80) -and ($res.ByProject['chromium'].ok -eq 29) -and ($res.ByProject['online-api'].ok -ge 28) -and ($newOk -eq 0)
        Add-Check 'R-05' 'Fase vermelha: api 80, chromium 29 e os 28 testes de sala da O2 aprovados; nenhum teste de canal ou de ciclo de vida passa' ([bool]$okRed) (Format-Results $res)
    } else {
        Add-Check 'PW-01' "Suíte completa, execução 1 (bind padrão): $ExpectedTotal aprovados (api 80, chromium 29, online-api 30, online-ws 18, online-lifecycle 4)" (($pw.Code -eq 0) -and (Test-FullSuite $res)) (Format-Results $res)

        # ---- 8. Suíte completa, servidor do script --------------------------
        Write-Log "`n===== 8. Suíte completa de novo, servidor iniciado pelo script com --bind 127.0.0.1"
        $srv = Start-Server $ServerExe 8765 @('--bind', '127.0.0.1') 'server-o3'
        $pw2 = Invoke-Playwright 'npx --no-install playwright test' @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8765' }
        Stop-Server $srv
        Write-PlaywrightSummary $pw2
        $res2 = Read-Results
        if ($res2) { Copy-Item $ResultsFile (Join-Path $LogDir 'online-o3-results-run2.json') -Force }
        Write-Log ("Resultado: " + (Format-Results $res2))
        if ($res2 -and $res2.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res2.Failed -join "`r`n  ")); Write-FailureExcerpt $pw2 60 }
        Add-Check 'PW-02' "Suíte completa, execução 2 (--bind 127.0.0.1): $ExpectedTotal aprovados" (($pw2.Code -eq 0) -and (Test-FullSuite $res2)) (Format-Results $res2)
        Test-ServerLog (Join-Path $LogDir 'server-o3.out.log') 'S-01' 'Log do servidor da execução 2'
        $serverLines = @(Get-Content (Join-Path $LogDir 'server-o3.out.log') -Encoding UTF8)
        $refused = @($serverLines | Where-Object { $_ -match 'Origem recusada' })
        Write-Log ("Recusas de origem registradas: {0}; exemplos:`r`n    {1}" -f $refused.Count, (($refused | Select-Object -First 3) -join "`r`n    "))
        Add-Check 'S-02' 'Recusas de origem registradas com o IP e a origem (OA-10)' ($refused.Count -gt 0) ''

        # ---- 9. Repetições ----------------------------------------------------
        Write-Log "`n===== 9. Repetições: canal (online-ws, 2 vezes) e concorrência HTTP (OR-16 a OR-18, 3 vezes)"
        $pw3 = Invoke-Playwright 'npx --no-install playwright test --project online-ws --repeat-each 2'
        Write-PlaywrightSummary $pw3
        $res3 = Read-Results
        Write-Log ("Resultado: " + (Format-Results $res3))
        if ($res3 -and $res3.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res3.Failed -join "`r`n  ")); Write-FailureExcerpt $pw3 40 }
        Add-Check 'PW-03' 'Projeto online-ws repetido 2 vezes: 36 de 36' (($pw3.Code -eq 0) -and $res3 -and ($res3.Stats.expected -eq 36) -and ($res3.Stats.unexpected -eq 0) -and ($res3.Stats.flaky -eq 0)) (Format-Results $res3)
        $pw4 = Invoke-Playwright 'npx --no-install playwright test --project online-api --grep "OR-1[678]" --repeat-each 3'
        Write-PlaywrightSummary $pw4
        $res4 = Read-Results
        Write-Log ("Resultado: " + (Format-Results $res4))
        if ($res4 -and $res4.Failed.Count) { Write-FailureExcerpt $pw4 30 }
        Add-Check 'PW-04' 'Concorrência HTTP (OR-16, OR-17, OR-18) repetida 3 vezes: 9 de 9' (($pw4.Code -eq 0) -and $res4 -and ($res4.Stats.expected -eq 9) -and ($res4.Stats.unexpected -eq 0)) (Format-Results $res4)

        # ---- 10. Ctrl+C com canais abertos ----------------------------------
        Write-Log "`n===== 10. Ctrl+C com 10 canais identificados (porta 8790)"
        $port = 8790
        # Sobra de uma execução anterior interrompida: só o próprio servidor do jogo é encerrado.
        foreach ($old in @(Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe'" | Where-Object { $_.CommandLine -match "--port $port\b" })) {
            Write-Log "Servidor de execução anterior ainda na porta $port (PID $($old.ProcessId)); encerrado."
            Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
        $busy = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$port/health" 2>$null
        if ("$busy".Trim() -ne '000') { throw "A porta $port já está em uso." }
        $downLog = Join-Path $LogDir 'server-o3-ctrlc.log'
        foreach ($f in @($downLog)) { if (Test-Path $f) { Remove-Item $f -Force } }
        $line = "/v:on /s /c `"`"$ServerExe`" --port $port --bind 127.0.0.1 --www `"$WebDir`" > `"$downLog`" 2>&1 & echo SAIDA=!ERRORLEVEL! >> `"$downLog`"`""
        $cmd = Start-Process -FilePath 'cmd.exe' -ArgumentList $line -WindowStyle Hidden -PassThru
        # Espera pelo /health (como na O2). Na primeira execução, Get-NetTCPConnection
        # demorou mais que o prazo inteiro, com milhares de conexões em TIME_WAIT
        # deixadas pelas rajadas, e o servidor ficou órfão.
        $deadline = (Get-Date).AddSeconds(15)
        $up = $false
        while ((Get-Date) -lt $deadline -and -not $up) {
            $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$port/health" 2>$null
            if ("$code".Trim() -eq '200') { $up = $true } else { Start-Sleep -Milliseconds 200 }
        }
        $serverPid = $null
        $srv = @(Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe'" | Where-Object { $_.ParentProcessId -eq $cmd.Id })
        if ($srv.Count -eq 1) { $serverPid = $srv[0].ProcessId }
        if (-not $up -or -not $serverPid) {
            foreach ($s in $srv) { Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue }
            throw "Servidor da porta $port não subiu (health: $up; processos filhos: $($srv.Count))."
        }
        Write-Log "Servidor da porta $port no ar (PID $serverPid)."
        $ready = Join-Path $LogDir 'o3-hold-ready.txt'; $holdOut = Join-Path $LogDir 'o3-hold-result.json'; $holdLog = Join-Path $LogDir 'o3-hold-client.log'
        foreach ($f in @($ready, $holdOut, $holdLog)) { if (Test-Path $f) { Remove-Item $f -Force } }
        $hold = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"node `"$TestsDir\tools\ws-hold.mjs`" --port $port --rooms 5 --ready `"$ready`" --out `"$holdOut`" > `"$holdLog`" 2>&1`"" -WindowStyle Hidden -PassThru
        $deadline = (Get-Date).AddSeconds(15)
        while (-not (Test-Path $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
        if (-not (Test-Path $ready)) { if (Test-Path $holdLog) { Write-Log (Get-Content $holdLog -Raw) }; throw 'Os 10 canais não abriram em 15 s.' }
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$CtrlC`" -ProcessId $serverPid" -WindowStyle Hidden -PassThru -Wait
        Write-Log "send-ctrl-c.ps1 terminou com código $($p.ExitCode) (0 = Ctrl+C enviado)"
        $exited = $cmd.WaitForExit(10000)
        if (-not $exited) { Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue; $cmd.WaitForExit(5000) | Out-Null }
        $hold.WaitForExit(25000) | Out-Null
        if (Test-Path $holdLog) { Write-Log (Get-Content $holdLog -Raw -Encoding UTF8).TrimEnd() }
        $log = if (Test-Path $downLog) { Get-Content $downLog -Raw -Encoding UTF8 } else { '' }
        Write-Log ("Log do servidor (trecho final):`r`n" + ((($log -split "`r?`n") | Select-Object -Last 16) -join "`r`n"))
        $codesOk = $false; $codesText = '(sem resultado)'
        if (Test-Path $holdOut) {
            $h = Get-Content $holdOut -Raw | ConvertFrom-Json
            $codes = @($h.fechamentos | ForEach-Object { $_.codigo })
            $codesOk = ($codes.Count -eq 10) -and (@($codes | Where-Object { $_ -ne 1001 }).Count -eq 0)
            $codesText = "códigos: " + (($codes | Sort-Object -Unique) -join ', ')
        }
        $t1 = [regex]::Match($log, '(?m)^(\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+Encerrando o servidor')
        $t2 = [regex]::Match($log, '(?m)^(\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+Servidor encerrado')
        $ms = 999999
        if ($t1.Success -and $t2.Success) {
            $toMs = { param($m) ((([int]$m.Groups[1].Value * 60 + [int]$m.Groups[2].Value) * 60 + [int]$m.Groups[3].Value) * 1000 + [int]$m.Groups[4].Value) }
            $ms = (& $toMs $t2) - (& $toMs $t1)
        }
        Add-Check 'D-01' 'Ctrl+C com 10 canais: todos recebem 1001; o servidor sai com código 0 em até 5 s' ($exited -and ($p.ExitCode -eq 0) -and $codesOk -and ($log -match 'SAIDA=0') -and ($ms -le 5000)) ("encerramento em $ms ms; $codesText")
        $after = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$port/health" 2>$null
        $portFree = ("$after".Trim() -eq '000') -and -not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)
        Add-Check 'D-02' 'Depois do Ctrl+C a porta fica livre' $portFree ''

        # ---- 11. Sabotagens ---------------------------------------------------
        Write-Log "`n===== 11. Sabotagens (cópias em logs\sabotage; o código original não é alterado)"
        $CR = "`r`n"
        $sabotages = @(
            @{ Id = 'SB-11'; Desc = 'Hub.Publish não publica nada'; File = 'uRoomHub.pas'; Engine = @('HB-02', 'HB-03');
               Grep = 'OW-04|OW-05|OW-06'; Projects = '--project online-ws'; MustFail = @('OW-04', 'OW-05', 'OW-06');
               Edits = @(
                 @{ Find = "    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then$CR        Inc(Result);"; Replace = '    { sabotagem SB-11: estado nao e publicado }' },
                 @{ Find = "    for Sub in List do$CR    begin$CR      Sub.Outbox.EnqueueTerminal(AText, ACloseCode);$CR      Inc(Result);$CR    end;"; Replace = '    { sabotagem SB-11: encerramento nao e publicado }' }) },
            @{ Id = 'SB-12'; Desc = 'Qualquer token de 32 caracteres é aceito como o lugar da vez (canal)'; File = 'uRoom.pas'; Engine = @('SL-07');
               Grep = 'OW-08'; Projects = '--project online-ws'; MustFail = @('OW-08');
               Edits = @(
                 @{ Find = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;";
                    Replace = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;$CR  if (Length(AToken) = 32) and (AToken <> FSeats[seX].Token) and (AToken <> FSeats[seO].Token) then$CR  begin   { sabotagem SB-12 }$CR    if FEngine.GetSnapshot.CurrentPlayer = ceO then$CR      ASeat := seO$CR    else$CR      ASeat := seX;$CR    Exit(True);$CR  end;" }) },
            @{ Id = 'SB-14'; Desc = 'uOriginPolicy aceita qualquer Origin'; File = 'uOriginPolicy.pas'; Engine = @('WS-07');
               Grep = 'OA-10|OV-05'; Projects = '--project online-api --project online-lifecycle'; MustFail = @('OA-10', 'OV-05a', 'OV-05b', 'OV-05c');
               Edits = @(
                 @{ Find = "  if Length(AOrigins) = 0 then$CR    { Sem Origin"; Replace = "  Exit(True);   { sabotagem SB-14 }$CR  if Length(AOrigins) = 0 then$CR    { Sem Origin" }) },
            @{ Id = 'SB-15'; Desc = 'Hub entrega o estado de uma sala a todas as salas'; File = 'uRoomHub.pas'; Engine = @('HB-02', 'HB-03');
               Grep = 'OW-07'; Projects = '--project online-ws'; MustFail = @('OW-07');
               Edits = @(
                 @{ Find = "    if not FRooms.TryGetValue(ACode, List) then$CR      Exit;$CR    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then";
                    Replace = "    for List in FRooms.Values do   { sabotagem SB-15: todas as salas }$CR    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then" }) }
        )
        foreach ($sb in $sabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o3"
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src'), (Join-Path $dir 'tests') | Out-Null
            Copy-Item (Join-Path $ServerDir 'TicTacToeServer.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'EngineCheck.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
            Copy-Item (Join-Path $ServerDir 'tests\*.pas') (Join-Path $dir 'tests')
            $target = Join-Path $dir "src\$($sb.File)"
            $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            $applied = $true
            foreach ($e in $sb.Edits) {
                $count = ([regex]::Matches($text, [regex]::Escape($e.Find))).Count
                if ($count -ne 1) { $applied = $false; Write-Log "Trecho encontrado $count vez(es) (esperado 1): $($e.Find)"; break }
                $text = $text.Replace($e.Find, $e.Replace)
            }
            if (-not $applied) { Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false ''; continue }
            [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($true)))
            $c1 = Invoke-Compile $dir 'TicTacToeServer.dpr'
            $c2 = Invoke-Compile $dir 'EngineCheck.dpr'
            if (($c1.Code -ne 0) -or ($c2.Code -ne 0)) { Write-Log ($c1.Output + $c2.Output).TrimEnd(); Add-Check $sb.Id "$($sb.Desc): cópia sabotada compila" $false ''; continue }
            # EngineCheck sabotado
            $er = Invoke-Engine (Join-Path $dir 'bin\EngineCheck.exe')
            $ef = Get-CaseIds $er.Output 'FALHOU'
            $engineMissed = @($sb.Engine | Where-Object { $ef -notcontains $_ })
            Write-Log ("EngineCheck sabotado: código {0}; casos que falharam: {1}" -f $er.Code, ($ef -join ', '))
            # Servidor real sabotado
            $sabExe = Join-Path $dir 'bin\TicTacToeServer.exe'
            $sab = Start-Server $sabExe 8766 @('--bind', '127.0.0.1') ("server-o3-" + $sb.Id)
            $r = Invoke-Playwright "npx --no-install playwright test $($sb.Projects) --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766'; PW_SERVER_EXE = $sabExe }
            Stop-Server $sab
            $sres = Read-Results
            $failedIds = @()
            if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, '(OW|OA|OV|OR)-\d\d[a-c]?')) { $failedIds += $m.Value } } }
            $failedIds = @($failedIds | Sort-Object -Unique)
            $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
            Write-Log ("Playwright contra o servidor sabotado: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
            Write-FailureExcerpt $r 24
            Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ') e, no EngineCheck, $($sb.Engine -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0) -and ($er.Code -eq 1) -and ($engineMissed.Count -eq 0)) ("Não detectados: " + (($notCaught + $engineMissed) -join ', '))
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
