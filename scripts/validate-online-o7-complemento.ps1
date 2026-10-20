# Complemento da validação da Entrega O7 (docs/test-plan-online.md, 13.3, itens 2 e 3), rodado DEPOIS de
# scripts\validate-online-o7.cmd, na mesma cópia limpa (%TEMP%\jogo-da-velha-o7-limpo-autorizado, já compilada):
#  X-01 matriz de rastreabilidade: todo CAO-01 a CAO-56 tem um teste com o seu identificador no título
#       aprovado nas três execuções da suíte (logs\online-o7-results-run1..3.json); o CAO-50 (Ctrl+C) é
#       conferido pelas verificações D-01 a D-03 e o CAO-47 (cobertura e sabotagens) pelo resumo de
#       logs\online-o7.log e pelas sabotagens deste script (X-02);
#  SB-01, SB-02, SB-03 e SB-05 (motor; EngineCheck), SB-04 (serviço sem trava; R-27 contra o servidor real)
#  e SB-06 (app.js desenha antes da resposta; U-08 no Chromium) — as sabotagens do modo local, como nas
#  Entregas 2 a 5, contra o código atual;
#  D-01 nenhum processo órfão e portas livres.
# Saída em logs\online-o7-complemento.log. Windows PowerShell 5.1.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Source    = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Source 'logs'
$LogFile   = Join-Path $LogDir 'online-o7-complemento.log'
$CopyDir   = Join-Path $env:TEMP 'jogo-da-velha-o7-limpo-autorizado'
$Root      = $Source
$TestPorts = @(8765, 8766)
function Set-RootPaths([string]$Dir) {
    $script:Root      = $Dir
    $script:ServerDir = Join-Path $Dir 'server'
    $script:TestsDir  = Join-Path $Dir 'tests'
    $script:WebDir    = Join-Path $Dir 'web'
    $script:EngineExe = Join-Path $script:ServerDir 'bin\EngineCheck.exe'
    $script:ServerExe = Join-Path $script:ServerDir 'bin\TicTacToeServer.exe'
    $script:Compile   = Join-Path $Dir 'scripts\compile-dpr.cmd'
    $script:CtrlC     = Join-Path $Dir 'scripts\send-ctrl-c.ps1'
    $script:ResultsFile = Join-Path $script:TestsDir 'test-results\results.json'
}
Set-RootPaths $Source

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

# Comando de compilação com limite de tempo: se o dcc32 travar (como na primeira fase
# vermelha da O5), ele é encerrado e o passo falha, em vez de a validação parar para sempre.
function Invoke-CmdWithTimeout([string]$CommandLine, [string]$OutFile, [int]$Seconds) {
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"$CommandLine > `"$OutFile`" 2>&1`"" -WindowStyle Hidden -PassThru
    $done = $p.WaitForExit($Seconds * 1000)
    if (-not $done) {
        foreach ($c in @(Get-CimInstance Win32_Process -Filter "Name = 'dcc32.exe'")) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
    }
    $out = if (Test-Path $OutFile) { Get-Content $OutFile -Raw -Encoding Default } else { '' }
    if (-not $done) { $out += "`r`nTEMPO ESGOTADO: o compilador não terminou em $Seconds s e foi encerrado." }
    [pscustomobject]@{ Code = $(if ($done) { $p.ExitCode } else { 124 }); Output = $out; TimedOut = (-not $done) }
}

function Invoke-Compile([string]$Dir, [string]$Dpr) {
    Invoke-CmdWithTimeout "`"$Compile`" `"$Dir`" $Dpr" (Join-Path $Dir "compile-$Dpr.log") 180
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


function Get-Sha256Bytes([byte[]]$Bytes) {
    [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($Bytes)).Replace('-', '')
}

function Get-MsOfDay($m) { ((([int]$m.Groups[1].Value * 60 + [int]$m.Groups[2].Value) * 60 + [int]$m.Groups[3].Value) * 1000 + [int]$m.Groups[4].Value) }

# Processos de teste deste projeto ainda vivos (servidor, EngineCheck, cliente ws-hold, Playwright),
# na cópia limpa e na pasta original (onde ficam as cópias sabotadas, em logs\sabotage).
function Get-ProjectProcesses {
    $roots = @($Root.ToLowerInvariant(), $Source.ToLowerInvariant())
    @(Get-CimInstance Win32_Process | Where-Object {
        $exe = if ($_.ExecutablePath) { $_.ExecutablePath.ToLowerInvariant() } else { '' }
        $cl = if ($_.CommandLine) { $_.CommandLine.ToLowerInvariant() } else { '' }
        $inProject = $false
        foreach ($r in $roots) { if ($exe.StartsWith($r) -or $cl.Contains($r)) { $inProject = $true } }
        ((($_.Name -eq 'TicTacToeServer.exe') -or ($_.Name -eq 'EngineCheck.exe')) -and $inProject) -or
        (($_.Name -eq 'node.exe') -and ($cl.Contains('ws-hold') -or ($cl.Contains('playwright') -and $inProject)))
    })
}

# Ctrl+C real (send-ctrl-c.ps1) num servidor com 2 x $Rooms canais abertos (tools/ws-hold.mjs ou,
# no modo público, tools/ws-hold-origin.mjs, que manda o Origin configurado).
# Com $Abandoned > 0: cria salas sem ninguém conectado antes e logo antes do Ctrl+C,
# para o faxineiro estar encerrando salas no momento do desligamento.

$failed = 1
try {
    Write-Log ("===== Complemento da validação da Entrega O7 - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    if (-not (Test-Path (Join-Path $CopyDir 'server\bin\TicTacToeServer.exe'))) { throw "Cópia limpa não encontrada (rode antes scripts\validate-online-o7.cmd): $CopyDir" }
    Set-RootPaths $CopyDir
    Write-Log "Pasta em uso: $Root"
    Write-Log ("Servidor: SHA-256 {0}" -f (Get-FileHash -Algorithm SHA256 $ServerExe).Hash)

    # ---- X-01 / X-02: matriz de rastreabilidade --------------------------------
    Write-Log "`n===== 1. Matriz de rastreabilidade (CAO-01 a CAO-56)"
    $ScriptOnly = @('CAO-47', 'CAO-50')
    $all = @(1..56 | ForEach-Object { 'CAO-{0:D2}' -f $_ })
    $runProblems = @()
    foreach ($tag in @('run1', 'run2', 'run3')) {
        $f = Join-Path $LogDir "online-o7-results-$tag.json"
        if (-not (Test-Path $f)) { $runProblems += "$tag ausente"; continue }
        $json = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        $passed = @{}
        $count = @{}
        $walk = $null
        $walk = {
            param($suite)
            foreach ($spec in @($suite.specs)) {
                $ids = @([regex]::Matches($spec.title, 'CAO-\d\d') | ForEach-Object { $_.Value } | Sort-Object -Unique)
                foreach ($t in @($spec.tests)) {
                    $ok = ($t.status -eq 'expected') -and (@($t.results | Where-Object { $_.status -ne 'passed' }).Count -eq 0)
                    foreach ($id in $ids) { if ($ok) { $passed[$id] = 1; $count[$id] = 1 + [int]$count[$id] } }
                }
            }
            foreach ($child in @($suite.suites)) { if ($child) { & $walk $child } }
        }
        foreach ($s in @($json.suites)) { & $walk $s }
        $missing = @($all | Where-Object { ($ScriptOnly -notcontains $_) -and -not $passed.ContainsKey($_) })
        Write-Log ("{0}: {1} de 54 CAO com teste aprovado; sem teste aprovado: {2}" -f $tag, (54 - $missing.Count), $(if ($missing.Count) { $missing -join ', ' } else { 'nenhum' }))
        if ($tag -eq 'run1') { Write-Log ("  testes por CAO (execução 1): " + (($all | Where-Object { $ScriptOnly -notcontains $_ } | ForEach-Object { "$_=$([int]$count[$_])" }) -join ' ')) }
        if ($missing.Count) { $runProblems += "$tag sem: $($missing -join ', ')" }
    }
    $mainLog = Join-Path $LogDir 'online-o7.log'
    $mainText = if (Test-Path $mainLog) { Get-Content $mainLog -Raw -Encoding UTF8 } else { '' }
    $dOk = ($mainText -match '\[PASSOU\] D-01') -and ($mainText -match '\[PASSOU\] D-02') -and ($mainText -match '\[PASSOU\] D-03')
    $mainApproved = $mainText -match 'Resultado final: APROVADO'
    $sbMain = @([regex]::Matches($mainText, '(?m)^PASSOU\s+(SB-\d\d)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Write-Log ("CAO-50 (Ctrl+C com canais): D-01 a D-03 aprovados em logs\online-o7.log: {0}" -f $dOk)
    Write-Log ("CAO-47 (sabotagens): validação principal {0}; sabotagens aprovadas nela: {1}" -f $(if ($mainApproved) { 'APROVADA' } else { 'NÃO aprovada' }), ($sbMain -join ', '))
    Add-Check 'X-01' 'Matriz: CAO-01 a CAO-56 cobertos — 54 por testes aprovados nas três execuções da suíte, CAO-50 por D-01 a D-03 (Ctrl+C)' (($runProblems.Count -eq 0) -and $dOk) ($runProblems -join '; ')

    # ---- 2. Sabotagens do motor (EngineCheck) -----------------------------------
    Write-Log "`n===== 2. Sabotagens do modo local (cópias em logs\sabotage\*-o7; o código não é alterado)"
    $CR = "`r`n"
    $engineSabotages = @(
        @{ Id = 'SB-01'; Desc = 'Trocar (2,4,6) por (0,1,2) em WIN_LINES'; Find = '(0, 4, 8), (2, 4, 6));'; Replace = '(0, 4, 8), (0, 1, 2));'; MustFail = @('M-05-D2', 'M-06', 'M-12') },
        @{ Id = 'SB-02'; Desc = 'Desligar a verificação de célula ocupada'; Find = '  if FBoard[APosition] <> ceEmpty then'; Replace = '  if False then'; MustFail = @('M-03', 'M-12') },
        @{ Id = 'SB-03'; Desc = 'Verificar célula ocupada antes de partida encerrada';
           Find = "  if FStatus <> gsInProgress then$CR    Exit(mrGameOver);$CR  if FBoard[APosition] <> ceEmpty then$CR    Exit(mrCellOccupied);";
           Replace = "  if FBoard[APosition] <> ceEmpty then$CR    Exit(mrCellOccupied);$CR  if FStatus <> gsInProgress then$CR    Exit(mrGameOver);"; MustFail = @('M-08', 'M-12') },
        @{ Id = 'SB-05'; Desc = 'Não trocar o turno após a jogada'; Find = '    FCurrentPlayer := OtherPlayer(FCurrentPlayer);'; Replace = '    { sabotagem: o turno nao troca }'; MustFail = @('M-02', 'M-12') }
    )
    foreach ($sb in $engineSabotages) {
        Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
        $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o7"
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src'), (Join-Path $dir 'tests') | Out-Null
        Copy-Item (Join-Path $ServerDir 'EngineCheck.dpr') $dir
        Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
        Copy-Item (Join-Path $ServerDir 'tests\*.pas') (Join-Path $dir 'tests')
        $target = Join-Path $dir 'src\uGameEngine.pas'
        $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
        $count = ([regex]::Matches($text, [regex]::Escape($sb.Find))).Count
        if ($count -ne 1) { Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false "Trecho encontrado $count vez(es); esperado 1."; continue }
        [System.IO.File]::WriteAllText($target, $text.Replace($sb.Find, $sb.Replace), (New-Object System.Text.UTF8Encoding($true)))
        $c = Invoke-Compile $dir 'EngineCheck.dpr'
        if ($c.Code -ne 0) { Write-Log $c.Output.TrimEnd(); Add-Check $sb.Id "$($sb.Desc): cópia sabotada compila" $false "dcc32: $($c.Code)"; continue }
        $r = Invoke-Engine (Join-Path $dir 'bin\EngineCheck.exe')
        $sbFail = Get-CaseIds $r.Output 'FALHOU'
        $notCaught = @($sb.MustFail | Where-Object { $sbFail -notcontains $_ })
        Write-Log ("EngineCheck sabotado: código {0}; casos que falharam: {1}" -f $r.Code, ($sbFail -join ', '))
        Add-Check $sb.Id "$($sb.Desc): EngineCheck detecta (código 1; falham $($sb.MustFail -join ', '))" (($r.Code -eq 1) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
    }

    # ---- 3. SB-04: serviço sem trava, contra o servidor real ----------------------
    Write-Log "----- SB-04: serviço da partida local sem trava e com Sleep(50) entre verificar e gravar (R-27)"
    $dir = Join-Path $LogDir 'sabotage\SB-04-o7'
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
    Copy-Item (Join-Path $ServerDir 'TicTacToeServer.dpr') $dir
    Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
    $svcPath = Join-Path $dir 'src\uGameService.pas'; $engPath = Join-Path $dir 'src\uGameEngine.pas'
    $svc = [System.IO.File]::ReadAllText($svcPath, [System.Text.Encoding]::UTF8)
    $eng = [System.IO.File]::ReadAllText($engPath, [System.Text.Encoding]::UTF8)
    $locks = ([regex]::Matches($svc, 'FLock\.(Enter|Leave);')).Count
    $writes = ([regex]::Matches($eng, [regex]::Escape('  FBoard[APosition] := FCurrentPlayer;'))).Count
    $svc = [regex]::Replace($svc, 'FLock\.(Enter|Leave);', '{ sabotagem SB-04 }')
    $eng = $eng.Replace('  FBoard[APosition] := FCurrentPlayer;', "  Sleep(50);$CR  FBoard[APosition] := FCurrentPlayer;")
    $eng = ([regex]'(?m)^implementation\r?$').Replace($eng, "implementation$CR${CR}uses$CR  Winapi.Windows;", 1)
    [System.IO.File]::WriteAllText($svcPath, $svc, (New-Object System.Text.UTF8Encoding($true)))
    [System.IO.File]::WriteAllText($engPath, $eng, (New-Object System.Text.UTF8Encoding($true)))
    if (($locks -lt 2) -or ($writes -ne 1)) {
        Add-Check 'SB-04' 'Serviço sem trava: sabotagem aplicada' $false "chamadas à trava: $locks; pontos de gravação: $writes"
    } else {
        $c = Invoke-Compile $dir 'TicTacToeServer.dpr'
        if ($c.Code -ne 0) { Write-Log $c.Output.TrimEnd(); Add-Check 'SB-04' 'Serviço sem trava: cópia sabotada compila' $false "dcc32: $($c.Code)" }
        else {
            $sab = Start-Server (Join-Path $dir 'bin\TicTacToeServer.exe') 8766 @('--bind', '127.0.0.1') 'server-o7-SB-04'
            $r = Invoke-Playwright 'npx --no-install playwright test --project api --grep "(^|\s)R-27\s"' @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766' }
            Stop-Server $sab
            $sres = Read-Results
            Write-Log ("Playwright contra o servidor sabotado: código {0}; {1}" -f $r.Code, (Format-Results $sres))
            Write-FailureExcerpt $r 8
            if (-not $sres) { Write-Log (($r.Output -replace '\x1b\[[0-9;]*m', '').Trim() -split "`r?`n" | Select-Object -Last 15 | Out-String) }
            $caught = $sres -and (@($sres.Failed | Where-Object { $_ -match 'R-27' }).Count -gt 0)
            Add-Check 'SB-04' 'Serviço sem trava e com atraso: o R-27 detecta jogadas simultâneas incompatíveis' (($r.Code -ne 0) -and $caught) ''
        }
    }

    # ---- 4. SB-06: app.js desenha antes da resposta --------------------------------
    Write-Log "----- SB-06: app.js desenha 'X' localmente antes da resposta do servidor (U-08)"
    $dir = Join-Path $LogDir 'sabotage\SB-06-o7'
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    $sabWeb = Join-Path $dir 'web'
    New-Item -ItemType Directory -Force -Path $sabWeb | Out-Null
    Copy-Item (Join-Path $WebDir '*') $sabWeb
    $appPath = Join-Path $sabWeb 'app.js'
    $app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
    $marker = '  function play(index) {'
    $count = ([regex]::Matches($app, [regex]::Escape($marker))).Count
    if ($count -ne 1) { Add-Check 'SB-06' 'app.js desenha antes do servidor: sabotagem aplicada' $false "Trecho encontrado $count vez(es)" }
    else {
        [System.IO.File]::WriteAllText($appPath, $app.Replace($marker, $marker + "`n    cells[index].textContent = 'X'; // sabotagem SB-06"), (New-Object System.Text.UTF8Encoding($false)))
        $sab = Start-Server $ServerExe 8766 @('--bind', '127.0.0.1') 'server-o7-SB-06' $sabWeb
        $r = Invoke-Playwright 'npx --no-install playwright test --project chromium --grep "(^|\s)U-08\s"' @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766' }
        Stop-Server $sab
        $sres = Read-Results
        Write-Log ("Playwright contra a interface sabotada: código {0}; {1}" -f $r.Code, (Format-Results $sres))
        Write-FailureExcerpt $r 8
        if (-not $sres) { Write-Log (($r.Output -replace '\x1b\[[0-9;]*m', '').Trim() -split "`r?`n" | Select-Object -Last 15 | Out-String) }
        $caught = $sres -and (@($sres.Failed | Where-Object { $_ -match 'U-08' }).Count -gt 0)
        Add-Check 'SB-06' 'app.js desenha antes da resposta do servidor: o U-08 falha' (($r.Code -ne 0) -and $caught) ''
    }

    # CAO-47: todas as sabotagens (as da validação principal e as deste complemento) detectadas.
    $sbHere = @($Results | Where-Object { $_.Id -match '^SB-' })
    $allSb = (@($sbHere | Where-Object { $_.Status -ne 'PASSOU' }).Count -eq 0) -and ($sbHere.Count -eq 6) -and $mainApproved
    Add-Check 'X-02' "Sabotagens SB-01 a SB-27 detectadas: SB-01 a SB-06 aqui; na validação principal, $($sbMain.Count) ($($sbMain -join ', ')) (CAO-47)" $allSb ''

    # ---- 5. Processos e portas -------------------------------------------------
    Write-Log "`n===== 5. Processos órfãos e portas"
    Start-Sleep -Seconds 2
    $orphans = @(Get-ProjectProcesses)
    foreach ($o in $orphans) { Write-Log ("Processo ainda aberto: {0} PID {1}: {2}" -f $o.Name, $o.ProcessId, $o.CommandLine) }
    $busyPorts = @()
    foreach ($port in $TestPorts) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$port/health" 2>$null
        if ("$code".Trim() -ne '000') { $busyPorts += $port }
    }
    Add-Check 'D-01' 'Nenhum processo órfão e as portas 8765 e 8766 livres' (($orphans.Count -eq 0) -and ($busyPorts.Count -eq 0)) ("processos: {0}; portas ocupadas: {1}" -f $orphans.Count, ($busyPorts -join ', '))
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    foreach ($s in $Servers) { Stop-Server $s }
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-6} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
