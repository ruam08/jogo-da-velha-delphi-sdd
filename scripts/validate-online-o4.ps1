# Validação da Entrega O4 (interface online: web/online.html, online.css, online.js).
#  1. ambiente; 2. arquivos preservados (git e SHA-256 das entregas O1 a O3), interface
#     local intacta (app.js e style.css sem mudança; index.html só com o link "Jogar online")
#     e uHttpApp só com os três estáticos novos;
#  3. compilação; 4. independência das units sem Indy;
#  5. EngineCheck (57 casos, sem casos novos na O4), três vezes;
#  6. checagem de tipos dos testes Playwright;
#  7. suíte completa com o servidor do Playwright (bind padrão) - inclui o projeto online-ui;
#  8. suíte completa com o servidor do script (--bind 127.0.0.1) e o log dele verificado;
#  9. repetição: projeto online-ui duas vezes seguidas;
# 10. Ctrl+C com 10 canais abertos (regressão da O3);
# 11. sabotagens: SB-09 e SB-16 (online.js) e SB-11 (hub) contra o servidor real;
# 12. capturas de tela da interface online (docs\screenshots\online-*.png).
# Com -RedPhase: só 1 a 7, sem a interface online (antes de online.html/js/css e da lista de estáticos).
# Saída em logs\online-o4.log (ou logs\online-o4-red.log). Windows PowerShell 5.1.
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'online-o4-red.log' } else { 'online-o4.log' })
$ServerDir = Join-Path $Root 'server'
$TestsDir  = Join-Path $Root 'tests'
$WebDir    = Join-Path $Root 'web'
$ShotsDir  = Join-Path $Root 'docs\screenshots'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$CtrlC     = Join-Path $Root 'scripts\send-ctrl-c.ps1'
$ResultsFile = Join-Path $TestsDir 'test-results\results.json'

$AllCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3','M-05-C1','M-05-C2',
    'M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08','M-09','M-10','M-11','M-12',
    'J-01','J-02','J-03','J-04','J-05','SV-01','SV-02','SV-03',
    'SL-01','SL-02','SL-03','SL-04','SL-05','SL-06','SL-07','SL-08','SL-09','SL-10',
    'SL-11','SL-12','MEM-01','SC-01','SC-02','RJ-01','RJ-02','RJ-03','OP-01',
    'OP-02','WS-01','WS-02','WS-03','WS-04','WS-05','WS-06','WS-07','HB-01','HB-02','HB-03')
$Expected = [ordered]@{ api = 80; chromium = 29; 'online-api' = 31; 'online-ws' = 18; 'online-lifecycle' = 6; 'online-ui' = 25 }
$ExpectedTotal = 189

# Sob controle do git (último commit): motor, serviço, log, testes antigos e a interface local.
# index.html fica de fora: a O4 acrescenta só o link "Jogar online" (P-06).
$Preserved = @('server/src/uGameEngine.pas','server/src/uGameService.pas','server/src/uConsoleLog.pas',
    'server/tests/uMiniTest.pas','server/tests/uEngineTests.pas','server/tests/uServiceTests.pas',
    'server/tests/uJsonTests.pas','web/app.js','web/style.css','tests/api','tests/rules','tests/ui','tests/support/api.ts',
    'tests/support/fixtures.ts','tests/support/raw-http.ts','tests/support/sequences.ts','tests/support/ui.ts',
    'tests/package.json','tests/package-lock.json','tests/tsconfig.json','docs/test-plan.md')
# Arquivos das entregas O1, O2 e O3 que a O4 não altera (ainda fora do git): SHA-256 aprovados.
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
    'server/src/uWebSocket.pas'               = 'CC27AA638BBB639D97A0AA83EEEDD85DFF2BB668D8045BFF3628D35EDDB3E189'
    'server/src/uOriginPolicy.pas'            = '77AA746ECE101DA3BE466023A18A7FC4414C669103AFBCFF1DC3BA9CE36403A2'
    'server/src/uRoomHub.pas'                 = 'B7C5878C9EB42761A3F387493A14079228223580C49C9D80B8D540DD2EAFFBD5'
    'server/src/uWsSession.pas'               = '599DB613A085BA07AC9307E84FD86EFD9C7F96C0D21EFA6446E9FFAB91F3A10A'
    'server/src/uRoomHttp.pas'                = 'C5C7A3A8C03054B5327AE3014B25322E72C5387E7EF5F483F6EDD72E1311BA4D'
    'server/src/uServerOptions.pas'           = 'B52C50E20BDF558559757BE1321BE8DC040F6BB97755866CFBB8E95F8D374ECC'
    'server/TicTacToeServer.dpr'              = '87721360CB37093C401FC181971F07F9873812F66E9A67FCBF935F2B4A1A83E3'
    'server/EngineCheck.dpr'                  = 'D6F0D3B2848E4CD9D28929B4D4F96D18C7D8D278CA8D513A627759C716064F16'
    'server/tests/uWebSocketTests.pas'        = 'D69AE30C530590DB52FB5B8DBD6796A812F03A7C1AF409E8223D26C4D568B5AC'
    'server/tests/uRoomHubTests.pas'          = 'A4014773C0BBF9A480B2C1DD0E6156645C47CE0886F4D48DFF5DEB8161C833F8'
    'server/tests/uOptionsTests.pas'          = 'DBA36BA8EC60344C5414B0009BB4AF3EF16A9D1017580E649C34F747D1190280'
    'tests/online/room-ws/channel.spec.ts'    = '747CF64A73817ECF1C7C241FF0095B0EE9B7E837947F1B54B9105B2D01773AB4'
    'tests/online/room-ws/sync.spec.ts'       = '295F79F1F92DDDEDDD3B0485ED7063742CBEB0BA3ED7A735F84AB100F4B74F2D'
    'tests/online/room-ws/timeouts.spec.ts'   = '923C288DB7FBE1DC77ADCF057901620823244667C3ABFB4187C10404AEAC0D27'
    'tests/online/lifecycle/load.spec.ts'     = 'F2DF458D841A3A5AD0332A1DA8E9B14BC425639628433DF5B764DA6DDF5F2EF3'
    'tests/online/lifecycle/origin.spec.ts'   = 'F6F93B2FFC8DB158F07EB96052B1735C85EF186EC56694DE7C48877119873C75'
    'tests/online/room-api/origin.spec.ts'    = 'C9EC574A755BBDC537019820561E85E1B77D464CD4B8E9999ECCA6F0629B24A7'
    'tests/online/room-api/legacy-auth.spec.ts' = 'CF9C07DC8BB9C7D529980DD3111A76D13D17C11E5EA4BC5C532CE17A8A8E1B71'
    'tests/support/online/fixtures.ts'        = 'E2493F7B9509CC0BCD686AD435EF66F69B10DD8A786351F87C361259BE024301'
    'tests/support/online/rooms.ts'           = 'DCE560484C95E5D7FF0E52DF8A8F5580A6AB6D7CC849DE763CE58F9C1E8DD678'
    'tests/support/online/server-process.ts'  = 'E496220BC9E4770610ECC7CF207C8BD398177E27544D09F1819A8C04DBDE4989'
    'tests/support/online/ws-client.ts'       = '422A440391E94E66961A04AE7FB7FDB872AB3B09F37B9BE2ACB2B9270361161F'
    'tests/support/online/raw-request.ts'     = '4D9CF31EC7CEACE58590A41002179912076B87E1BC538882E3C925080BC58483'
    'tests/tools/ws-hold.mjs'                 = '7CEC0BA9A5FEF200FE1930966B8DA0473230796DD50457C14AF14405D61C821A'
    'scripts/validate-online-o3.ps1'          = '5112C63B3BD2ED343AA6C1BEEA9E566477868C7CE80EF241A62B8F9BB5DFE3A6'
    'scripts/send-ctrl-c.ps1'                 = '3AE8AEF39DED0F410D43E620A110AE277AEABB8B57F600808DE84757536240DD'
}
# uHttpApp.pas aprovado na O3; a O4 só acrescenta estes trechos (MC-04).
$HttpAppApproved = '74678B4FC5A046782051210BBCDB53B53B5230859A28DD271C1BDD7C96CC1544'
$HttpAppAdded = @(
    "    GET|HEAD /online.html, /online.css, /online.js -> idem (interface online, O4)`r`n",
    ((@("  { Interface online (docs/plan-online.md, MC-04). }",
        "  else if APath = '/online.html' then", "  begin", "    AFileName := 'online.html';", "    AContentType := 'text/html';", "  end",
        "  else if APath = '/online.css' then", "  begin", "    AFileName := 'online.css';", "    AContentType := 'text/css';", "  end",
        "  else if APath = '/online.js' then", "  begin", "    AFileName := 'online.js';", "    AContentType := 'text/javascript';", "  end") -join "`r`n") + "`r`n"))
$LinkLine = '    <p class="app__hint"><a href="/online.html">Jogar online</a> — cada pessoa no seu navegador, pela rede local.</p>'
$WebNew = @('web/online.html', 'web/online.css', 'web/online.js')

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

function Start-Server([string]$Exe, [int]$Port, [string[]]$Extra, [string]$Name, [string]$Www = $WebDir) {
    $busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw "A porta $Port já está em uso (processo $($busy[0].OwningProcess))." }
    $procArgs = @('--port', "$Port", '--www', "`"$Www`"") + $Extra
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


function Write-Annotations {
    if (-not (Test-Path $ResultsFile)) { return }
    $json = Get-Content $ResultsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $walk = $null
    $walk = {
        param($suite)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                $seen = @{}
                foreach ($a in @($t.annotations) + @($t.results | ForEach-Object { $_.annotations })) {
                    if ($a -and $a.type -and -not $seen.ContainsKey("$($a.type)|$($a.description)")) {
                        $seen["$($a.type)|$($a.description)"] = 1
                        Write-Log ("  anotação [{0}] {1}: {2}" -f ($spec.title -split ' ')[0], $a.type, $a.description)
                    }
                }
            }
        }
        foreach ($child in @($suite.suites)) { if ($child) { & $walk $child } }
    }
    foreach ($s in @($json.suites)) { & $walk $s }
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega O4 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: sem online.html/js/css e sem os estáticos novos no servidor)' } else { '' }))
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
        $idxDiff = @(& cmd.exe /c "git -c core.quotepath=off diff -U0 HEAD -- web/index.html 2>&1" | Where-Object { ($_ -match '^[+-]') -and ($_ -notmatch '^(\+\+\+|---) ') })
        $status = (& cmd.exe /c "git status --short --untracked-files=all -- server scripts docs web tests 2>&1" | Out-String).TrimEnd()
    } finally { Pop-Location }
    Add-Check 'P-01' 'Motor, serviço, log, testes antigos (EngineCheck e Playwright), app.js, style.css e plano de testes antigo idênticos ao último commit' ($quietCode -eq 0) "git diff --quiet: código $quietCode"
    $hashProblems = @()
    foreach ($rel in $Hashes.Keys) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $hashProblems += "$rel ausente"; continue }
        $h = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
        if ($h -ne $Hashes[$rel]) { $hashProblems += "$rel ($h)" }
    }
    Add-Check 'P-02' "Arquivos das O1, O2 e O3 não alterados pela O4 idênticos aos aprovados (SHA-256 de $($Hashes.Count) arquivos)" ($hashProblems.Count -eq 0) ($hashProblems -join '; ')
    # ReadAllText descarta o BOM; ele volta ao calcular o SHA-256 (o arquivo aprovado tem BOM).
    $httpText = [System.IO.File]::ReadAllText((Join-Path $ServerDir 'src\uHttpApp.pas'), (New-Object System.Text.UTF8Encoding($false)))
    $addedFound = 0
    foreach ($a in $HttpAppAdded) { if ($httpText.Contains($a)) { $addedFound++; $httpText = $httpText.Replace($a, '') } }
    $httpHash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([byte[]](@(0xEF, 0xBB, 0xBF) + (New-Object System.Text.UTF8Encoding($false)).GetBytes($httpText)))).Replace('-', '')
    $expectedAdded = $(if ($RedPhase) { 0 } else { 2 })
    Add-Check 'P-03' "uHttpApp.pas igual ao aprovado na O3, salvo os estáticos novos (MC-04; trechos acrescentados: $expectedAdded)" (($httpHash -eq $HttpAppApproved) -and ($addedFound -eq $expectedAdded)) "SHA-256 sem os trechos: $httpHash; trechos encontrados: $addedFound"
    Write-Log ("Diferenças de tests/playwright.config.ts em relação ao commit:`r`n    " + ($cfgDiff -join "`r`n    "))
    $removed = @($cfgDiff | Where-Object { $_ -like '-*' })
    Add-Check 'P-04' 'playwright.config.ts: só acréscimos (projetos online-api, online-ws, online-lifecycle, online-ui)' (($removed.Count -eq 0) -and ($cfgDiff -match "name: 'online-ui'")) ("linhas removidas: {0}" -f $removed.Count)
    Write-Log ("Diferenças de web/index.html em relação ao commit:`r`n    " + ($idxDiff -join "`r`n    "))
    if ($RedPhase) {
        Add-Check 'P-06' 'Fase vermelha: web/index.html sem mudança' ($idxDiff.Count -eq 0) ("linhas alteradas: {0}" -f $idxDiff.Count)
    } else {
        $idxOk = ($idxDiff.Count -eq 1) -and ($idxDiff[0].TrimEnd() -eq ('+' + $LinkLine))
        Add-Check 'P-06' 'web/index.html: só uma linha acrescentada, com o link "Jogar online" (MC-05)' $idxOk ("linhas alteradas: {0}" -f $idxDiff.Count)
    }
    Write-Log "git status:`r`n$status"
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $ServerDir 'src\uHttpApp.pas'))
    $bom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
    $lfOnly = ([regex]::Matches([System.Text.Encoding]::UTF8.GetString($bytes), '(?<!\r)\n')).Count
    Add-Check 'P-05' 'uHttpApp.pas em UTF-8 com BOM e CRLF (DT-17)' ($bom -and ($lfOnly -eq 0)) "BOM: $bom; LF sem CR: $lfOnly"
    $webPresent = @($WebNew | Where-Object { Test-Path (Join-Path $Root $_) })
    if ($RedPhase) {
        Add-Check 'P-07' 'Fase vermelha: online.html, online.css e online.js ainda não existem' ($webPresent.Count -eq 0) ("presentes: " + ($webPresent -join ', '))
    } else {
        $webBad = @()
        foreach ($rel in $WebNew) {
            $path = Join-Path $Root $rel
            if (-not (Test-Path $path)) { $webBad += "$rel ausente"; continue }
            $b = [System.IO.File]::ReadAllBytes($path)
            $txt = [System.Text.Encoding]::UTF8.GetString($b)
            if (($b.Length -ge 3) -and ($b[0] -eq 0xEF)) { $webBad += "$rel com BOM" }
            if ($txt -match '(?i)https?://(?!127\.0\.0\.1|localhost)[a-z0-9.-]+\.[a-z]{2,}') { $webBad += "$rel referencia endereço externo" }
            if ($txt -match '(?i)console\.(log|info|debug)') { $webBad += "$rel escreve no console" }
        }
        Add-Check 'P-07' 'online.html, online.css e online.js: UTF-8 sem BOM, sem dependências externas e sem escrita no console' ($webBad.Count -eq 0) ($webBad -join '; ')
    }

    # ---- 3. Compilação -----------------------------------------------------
    Write-Log "`n===== 3. Compilação (scripts\build.cmd)"
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
    Add-Check 'B-02' 'Nenhum warning nem hint do compilador' (($warnings.Count + $hints.Count) -eq 0) ("Warnings: {0}; hints: {1}; {2}" -f $warnings.Count, $hints.Count, (($warnings + $hints) -join ' | '))
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
        if ($bad.Count) { $indep += "$u -> $($bad -join ', ')" }
    }
    Add-Check 'I-01' 'Protocolo, origem, hub, opções, rotas de sala e domínio sem Indy, sem servidor e sem log (DTO-21)' ($indep.Count -eq 0) ($indep -join '; ')

    # ---- 5. EngineCheck ----------------------------------------------------
    Write-Log "`n===== 5. EngineCheck.exe (sem casos novos na O4)"
    $run = Invoke-Engine $EngineExe
    Write-Log (($run.Output -split "`r?`n" | Where-Object { $_ -match '^(Casos:|RESULTADO|\[FALHOU\])' }) -join "`r`n")
    Write-Log "Código de saída do EngineCheck: $($run.Code); duração $($run.Seconds) s"
    $okIds = Get-CaseIds $run.Output 'OK'
    $failIds = Get-CaseIds $run.Output 'FALHOU'
    $seen = @($okIds + $failIds)
    $missing = @($AllCases | Where-Object { $seen -notcontains $_ })
    $extra = @($seen | Where-Object { $AllCases -notcontains $_ })
    Add-Check 'E-01' 'EngineCheck sai com código 0 e diz RESULTADO: APROVADO' (($run.Code -eq 0) -and ($run.Output -match 'RESULTADO: APROVADO')) "Código $($run.Code)"
    Add-Check 'E-02' '57 casos executados e aprovados (os mesmos da O3)' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($failIds.Count -eq 0) -and ($okIds.Count -eq 57)) ("OK: {0}; falharam: {1}; ausentes: {2}; a mais: {3}" -f $okIds.Count, ($failIds -join ','), ($missing -join ','), ($extra -join ','))
    if (-not $RedPhase) {
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
    if ($res) { Copy-Item $ResultsFile (Join-Path $LogDir "online-o4$(if ($RedPhase) { '-red' })-results-run1.json") -Force }
    Write-Log ("Resultado: " + (Format-Results $res))
    Write-Annotations
    if ($res -and $res.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res.Failed -join "`r`n  ")); Write-FailureExcerpt $pw 60 }
    if ($RedPhase) {
        $lc = $res.ByProject['online-lifecycle']; $ui = $res.ByProject['online-ui']; $oa = $res.ByProject['online-api']
        $okRed = $res -and ($res.ByProject['api'].ok -eq 80) -and ($res.ByProject['chromium'].ok -eq 29) -and ($oa.ok -eq 30) -and ($oa.fail -eq 1) -and
            ($res.ByProject['online-ws'].ok -eq 18) -and ($lc.ok -eq 4) -and ($lc.fail -eq 2) -and ($ui.ok -eq 0) -and ($ui.fail -eq 25)
        Add-Check 'R-01' 'Fase vermelha: os 161 testes anteriores aprovados (api 80, chromium 29, online-api 30, online-ws 18, online-lifecycle 4); os 28 novos falham (OA-12, OU-23, OV-10 e os 25 de online-ui)' ([bool]$okRed) (Format-Results $res)
    } else {
        Add-Check 'PW-01' "Suíte completa, execução 1 (bind padrão): $ExpectedTotal aprovados (api 80, chromium 29, online-api 31, online-ws 18, online-lifecycle 6, online-ui 25)" (($pw.Code -eq 0) -and (Test-FullSuite $res)) (Format-Results $res)

        # ---- 8. Suíte completa, servidor do script --------------------------
        Write-Log "`n===== 8. Suíte completa de novo, servidor iniciado pelo script com --bind 127.0.0.1"
        $srv = Start-Server $ServerExe 8765 @('--bind', '127.0.0.1') 'server-o4'
        $pw2 = Invoke-Playwright 'npx --no-install playwright test' @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8765' }
        Stop-Server $srv
        Write-PlaywrightSummary $pw2
        $res2 = Read-Results
        if ($res2) { Copy-Item $ResultsFile (Join-Path $LogDir 'online-o4-results-run2.json') -Force }
        Write-Log ("Resultado: " + (Format-Results $res2))
        Write-Annotations
        if ($res2 -and $res2.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res2.Failed -join "`r`n  ")); Write-FailureExcerpt $pw2 60 }
        Add-Check 'PW-02' "Suíte completa, execução 2 (--bind 127.0.0.1): $ExpectedTotal aprovados" (($pw2.Code -eq 0) -and (Test-FullSuite $res2)) (Format-Results $res2)
        Test-ServerLog (Join-Path $LogDir 'server-o4.out.log') 'S-01' 'Log do servidor da execução 2'
        $serverLines = @(Get-Content (Join-Path $LogDir 'server-o4.out.log') -Encoding UTF8)
        $statics = @($serverLines | Where-Object { $_ -match 'GET /online\.(html|js|css) -> 200' }).Count
        # As páginas da suíte são abertas em http://127.0.0.1:8765 e http://localhost:8765: uma recusa
        # dessas origens viria da interface. As outras recusas são as origens inválidas do OA-10.
        $refusedAll = @($serverLines | Where-Object { $_ -match 'Origem recusada' })
        $refusedUi = @($refusedAll | Where-Object { $_ -match 'de [0-9.]+: "http://(127\.0\.0\.1|localhost):8765"\s*$' })
        Write-Log ("Recusas de origem no log: {0}; origens recusadas: {1}" -f $refusedAll.Count, (@($refusedAll | ForEach-Object { if ($_ -match '"([^"]*)"\s*$') { $Matches[1] } } | Sort-Object -Unique) -join ', '))
        Add-Check 'S-02' 'Páginas online servidas pelo servidor real; nenhuma recusa das origens da própria interface' (($statics -gt 0) -and ($refusedUi.Count -eq 0)) ("GET de /online.*: {0}; recusas da origem da interface: {1}" -f $statics, (($refusedUi | Select-Object -First 3) -join ' | '))

        # ---- 9. Repetição da interface ------------------------------------------
        Write-Log "`n===== 9. Repetição: projeto online-ui duas vezes seguidas"
        $pw3 = Invoke-Playwright 'npx --no-install playwright test --project online-ui --repeat-each 2'
        Write-PlaywrightSummary $pw3
        $res3 = Read-Results
        Write-Log ("Resultado: " + (Format-Results $res3))
        Write-Annotations
        if ($res3 -and $res3.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res3.Failed -join "`r`n  ")); Write-FailureExcerpt $pw3 40 }
        Add-Check 'PW-03' 'Projeto online-ui repetido 2 vezes: 50 de 50' (($pw3.Code -eq 0) -and $res3 -and ($res3.Stats.expected -eq 50) -and ($res3.Stats.unexpected -eq 0) -and ($res3.Stats.flaky -eq 0)) (Format-Results $res3)

        # ---- 10. Ctrl+C com canais abertos (regressão da O3) ----------------
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
        $downLog = Join-Path $LogDir 'server-o4-ctrlc.log'
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
        $ready = Join-Path $LogDir 'o4-hold-ready.txt'; $holdOut = Join-Path $LogDir 'o4-hold-result.json'; $holdLog = Join-Path $LogDir 'o4-hold-client.log'
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
        # Interface: cópia da pasta web com online.js alterado, servida pelo servidor real (--www).
        $webSabotages = @(
            @{ Id = 'SB-09'; Desc = 'online.js desenha o símbolo na célula clicada antes da resposta do servidor';
               Grep = 'OU-09'; MustFail = @('OU-09');
               Find = "      return request('POST', roomPath(code) + '/moves', token, { posicao: index }).then(handleRoomResponse);";
               Replace = "      cells[index].textContent = seat;   /* sabotagem SB-09 */$CR      return request('POST', roomPath(code) + '/moves', token, { posicao: index }).then(handleRoomResponse);" },
            @{ Id = 'SB-16'; Desc = 'online.js coloca o token na URL da página';
               Grep = 'OU-01|OU-03|OU-17'; MustFail = @('OU-01', 'OU-03', 'OU-17');
               Find = "    window.history.replaceState(null, '', pagePath(code));$CR    clearError();";
               Replace = "    window.history.replaceState(null, '', pagePath(code) + '&t=' + token);   /* sabotagem SB-16 */$CR    clearError();" }
        )
        foreach ($sb in $webSabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o4"
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            $sabWeb = Join-Path $dir 'web'
            New-Item -ItemType Directory -Force -Path $sabWeb | Out-Null
            Copy-Item (Join-Path $WebDir '*') $sabWeb
            $target = Join-Path $sabWeb 'online.js'
            $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            $text = $text.Replace("`r`n", "`n")
            $find = $sb.Find.Replace("`r`n", "`n"); $repl = $sb.Replace.Replace("`r`n", "`n")
            $count = ([regex]::Matches($text, [regex]::Escape($find))).Count
            if ($count -ne 1) { Write-Log "Trecho encontrado $count vez(es) (esperado 1): $find"; Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false ''; continue }
            [System.IO.File]::WriteAllText($target, $text.Replace($find, $repl), (New-Object System.Text.UTF8Encoding($false)))
            $sab = Start-Server $ServerExe 8766 @('--bind', '127.0.0.1') ("server-o4-" + $sb.Id) $sabWeb
            $r = Invoke-Playwright "npx --no-install playwright test --project online-ui --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766' }
            Stop-Server $sab
            $sres = Read-Results
            $failedIds = @()
            if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, 'OU-\d\d')) { $failedIds += $m.Value } } }
            $failedIds = @($failedIds | Sort-Object -Unique)
            $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
            Write-Log ("Playwright contra a interface sabotada: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
            Write-FailureExcerpt $r 16
            Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
        }
        # Servidor: cópia sabotada do código Delphi (mesmo procedimento da O3).
        $sabotages = @(
            @{ Id = 'SB-11'; Desc = 'Hub.Publish não publica nada (a interface deixa de receber as jogadas)'; File = 'uRoomHub.pas'; Engine = @('HB-02', 'HB-03');
               Grep = 'OU-06|OU-08|OW-04|OW-05|OW-06'; Projects = '--project online-ui --project online-ws'; MustFail = @('OU-06', 'OU-08', 'OW-04', 'OW-05', 'OW-06');
               Edits = @(
                 @{ Find = "    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then$CR        Inc(Result);"; Replace = '    { sabotagem SB-11: estado nao e publicado }' },
                 @{ Find = "    for Sub in List do$CR    begin$CR      Sub.Outbox.EnqueueTerminal(AText, ACloseCode);$CR      Inc(Result);$CR    end;"; Replace = '    { sabotagem SB-11: encerramento nao e publicado }' }) }
        )
        foreach ($sb in $sabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o4"
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
            $sab = Start-Server $sabExe 8766 @('--bind', '127.0.0.1') ("server-o4-" + $sb.Id)
            $r = Invoke-Playwright "npx --no-install playwright test $($sb.Projects) --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766'; PW_SERVER_EXE = $sabExe }
            Stop-Server $sab
            $sres = Read-Results
            $failedIds = @()
            if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, '(OW|OA|OV|OR|OU)-\d\d[a-c]?')) { $failedIds += $m.Value } } }
            $failedIds = @($failedIds | Sort-Object -Unique)
            $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
            Write-Log ("Playwright contra o servidor sabotado: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
            Write-FailureExcerpt $r 24
            Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ') e, no EngineCheck, $($sb.Engine -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0) -and ($er.Code -eq 1) -and ($engineMissed.Count -eq 0)) ("Não detectados: " + (($notCaught + $engineMissed) -join ', '))
        }

        # ---- 12. Capturas de tela ---------------------------------------------
        Write-Log "`n===== 12. Capturas de tela da interface online (docs\screenshots)"
        $shot = Start-Server $ServerExe 8767 @('--bind', '127.0.0.1') 'server-o4-screens'
        $cap = Invoke-InTests "node tools/capture-online.cjs http://127.0.0.1:8767 `"$ShotsDir`""
        Stop-Server $shot
        Write-Log $cap.Output.TrimEnd()
        $shotFiles = @('online-desktop-inicio.png','online-desktop-sala-criada.png','online-desktop-jogando-a.png','online-desktop-jogando-b.png',
            'online-desktop-vitoria-a.png','online-desktop-vitoria-b.png','online-celular-jogando.png','online-celular-encerrada.png')
        $missingShots = @($shotFiles | Where-Object { -not (Test-Path (Join-Path $ShotsDir $_)) })
        Add-Check 'C-01' 'Capturas de tela da interface online geradas (desktop e 360 px)' (($cap.Code -eq 0) -and ($missingShots.Count -eq 0)) ("Código $($cap.Code); ausentes: " + ($missingShots -join ', '))
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
