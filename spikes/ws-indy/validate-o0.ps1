# Validação da Entrega O0: prova de conceito WebSocket sobre o Indy do Delphi Berlin.
# Descartável. Não compila nem altera o servidor do jogo, e não executa a suíte atual.
#  1. ambiente e versão do Indy; impressões digitais (SHA-256) dos arquivos de produção
#  2. compilação do WsSpike.dpr com o dcc32
#  3. autoteste do protocolo (sem rede)
#  4. servidor 8790: testes Node repetidos, Chromium repetido, carga de 50 canais
#  5. servidor 8791 com 3 s de inatividade
#  6. servidor 8792: Ctrl+C com 20 canais abertos; porta liberada
#  7. log dos servidores; arquivos de produção inalterados
# Saída em logs\online-o0.log e logs\online-o0\*. Windows PowerShell 5.1.
param([int]$Repeat = 3, [int]$BrowserRepeat = 2, [int]$LoadSeconds = 30, [int]$LoadClients = 50)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Spike    = $PSScriptRoot
$Root     = (Resolve-Path (Join-Path $Spike '..\..')).Path
$LogDir   = Join-Path $Root 'logs'
$WorkDir  = Join-Path $LogDir 'online-o0'
$LogFile  = Join-Path $LogDir 'online-o0.log'
$Exe      = Join-Path $Spike 'bin\WsSpike.exe'
$Compile  = Join-Path $Root 'scripts\compile-dpr.cmd'
$Client   = Join-Path $Spike 'client'
$CtrlC    = Join-Path $Spike 'tools\send-ctrl-c.ps1'
$TestsDir = Join-Path $Root 'tests'

New-Item -ItemType Directory -Force -Path $LogDir, $WorkDir | Out-Null
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

# SHA-256 dos arquivos do jogo que esta entrega não pode alterar.
function Get-ProductionHashes {
    $list = @()
    $patterns = @(
        @('server\src', '*.pas'), @('server\tests', '*.pas'), @('server', '*.dpr'), @('server', '*.dproj'),
        @('server\bin', '*.exe'), @('web', '*.*'), @('scripts', '*.*'),
        @('tests', '*.json'), @('tests', '*.ts'), @('tests\api', '*.ts'), @('tests\rules', '*.ts'),
        @('tests\ui', '*.ts'), @('tests\support', '*.ts'), @('tests\tools', '*.*'),
        @('docs', 'spec.md'), @('docs', 'plan.md'), @('docs', 'test-plan.md'), @('.', 'README.md'), @('.', '.gitignore'))
    foreach ($p in $patterns) {
        $dir = Join-Path $Root $p[0]
        if (Test-Path $dir) {
            foreach ($f in Get-ChildItem -Path $dir -Filter $p[1] -File -ErrorAction SilentlyContinue) {
                $list += [pscustomobject]@{ Path = $f.FullName.Substring($Root.Length + 1); Hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
            }
        }
    }
    $list | Sort-Object Path
}

function Test-PortFree([int]$Port) {
    -not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Get-ListenerPid([int]$Port) {
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return [int]$c.OwningProcess }
    return 0
}

function Wait-Health([int]$Port, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
        if ("$code".Trim() -eq '200') { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

# Inicia o WsSpike num console próprio (oculto), com a saída num arquivo.
# O cmd registra o código de saída do servidor na última linha ("SAIDA=n").
function Start-Spike([int]$Port, [string]$Extra, [string]$Name) {
    if (-not (Test-PortFree $Port)) { throw "A porta $Port já está em uso (processo $(Get-ListenerPid $Port))." }
    $log = Join-Path $WorkDir "$Name.log"
    if (Test-Path $log) { Remove-Item $log -Force }
    $line = "/v:on /s /c `"`"$Exe`" --port $Port $Extra > `"$log`" 2>&1 & echo SAIDA=!ERRORLEVEL! >> `"$log`"`""
    $cmd = Start-Process -FilePath 'cmd.exe' -ArgumentList $line -WindowStyle Hidden -PassThru
    if (-not (Wait-Health $Port 10)) { throw "WsSpike na porta $Port não respondeu em 10 s (veja $log)." }
    [pscustomobject]@{ Cmd = $cmd; Port = $Port; Log = $log; Name = $Name; ServerPid = (Get-ListenerPid $Port) }
}

# Encerra pelo evento nomeado (mesmo caminho de código do Ctrl+C) e espera o fim.
function Stop-SpikeByEvent($S) {
    try {
        $ev = [System.Threading.EventWaitHandle]::OpenExisting("Local\WsSpikeStop_$($S.Port)")
        [void]$ev.Set(); $ev.Dispose()
    } catch { Write-Log "  (evento nomeado indisponível: $($_.Exception.Message))" }
    if (-not $S.Cmd.WaitForExit(10000)) {
        Write-Log "  servidor $($S.Name) não encerrou em 10 s; finalizado à força"
        Stop-Process -Id $S.ServerPid -Force -ErrorAction SilentlyContinue
        $S.Cmd.WaitForExit(5000) | Out-Null
    }
}

function Read-SpikeLog($S) {
    if (Test-Path $S.Log) { return (Get-Content $S.Log -Raw -Encoding UTF8) }
    return ''
}

function Invoke-Node([string]$Arguments, [string]$Title) {
    Write-Log "> node $Arguments"
    Push-Location $Client
    try {
        $out = & cmd.exe /c "node $Arguments 2>&1" | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    Write-Log $out.TrimEnd()
    [pscustomobject]@{ Code = $code; Output = $out }
}

function Summary-Line([string]$Output) {
    ([regex]::Match($Output, '(?m)^RESUMO:.*$')).Value
}

$servers = New-Object System.Collections.ArrayList
$failed = 1
try {
    Write-Log ("===== Validação da Entrega O0 (prova de conceito WebSocket) - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-Log "Pasta do projeto: $Root"
    Write-Log "Repetições: testes Node $Repeat x, Chromium $BrowserRepeat x; carga $LoadClients canais por $LoadSeconds s"

    # ---- 1. Ambiente ------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2})" -f $os.Caption, $os.Version, $os.BuildNumber)
    $nodeVersion = (& cmd.exe /c "node --version 2>&1" | Out-String).Trim()
    Write-Log "Node.js: $nodeVersion"
    $pwPkg = Join-Path $TestsDir 'node_modules\@playwright\test\package.json'
    $pwVersion = if (Test-Path $pwPkg) { (Get-Content $pwPkg -Raw | ConvertFrom-Json).version } else { '(não instalado)' }
    Write-Log "Playwright em tests\node_modules: $pwVersion (já instalado; nada é instalado por este script)"

    $rsvars = if ($env:DELPHI_RSVARS) { $env:DELPHI_RSVARS } else { 'C:\Program Files (x86)\Embarcadero\Studio\18.0\bin\rsvars.bat' }
    $bdsDir = Split-Path -Parent (Split-Path -Parent $rsvars)
    $idVers = Join-Path $bdsDir 'source\Indy10\System\IdVers.inc'
    $indyFile = '(IdVers.inc não encontrado)'
    if (Test-Path $idVers) { $indyFile = ([regex]::Match((Get-Content $idVers -Raw), "gsIdVersion\s*=\s*'([^']+)'")).Groups[1].Value }
    Write-Log "Indy no código-fonte instalado ($idVers): $indyFile"

    $hashesBefore = Get-ProductionHashes
    Write-Log ("Arquivos de produção com impressão digital registrada: {0}" -f @($hashesBefore).Count)
    Add-Check 'A-01' 'Node.js com WebSocket nativo (22 ou superior) e Playwright já instalado em tests\' (($nodeVersion -match '^v(2[2-9]|[3-9]\d)\.') -and ($pwVersion -ne '(não instalado)')) "Node $nodeVersion; Playwright $pwVersion"

    # ---- 2. Compilação ----------------------------------------------------
    Write-Log "`n===== 2. Compilação do WsSpike.dpr (Delphi 10.1 Berlin)"
    if (Test-Path $Exe) { Remove-Item $Exe -Force }
    $build = & cmd.exe /c "`"$Compile`" `"$Spike`" WsSpike.dpr 2>&1" | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$')).Count
    $hints = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$')).Count
    Add-Check 'E0-01a' 'WsSpike compila no Berlin (31.0) sem erros e sem warnings' (($buildCode -eq 0) -and (Test-Path $Exe) -and ($build -match 'compiler version 31\.0') -and ($warnings -eq 0)) "Código $buildCode; warnings $warnings; hints $hints"
    if (-not (Test-Path $Exe)) { throw 'WsSpike.exe não foi gerado; veja os erros de compilação acima.' }

    # ---- 3. Autoteste -------------------------------------------------------
    Write-Log "`n===== 3. Autoteste do protocolo (sem rede)"
    $self = & $Exe --selftest 2>&1 | Out-String
    $selfCode = $LASTEXITCODE
    Write-Log $self.TrimEnd()
    $indyBin = ([regex]::Match($self, 'Indy compilado: (\S+)')).Groups[1].Value
    Add-Check 'E0-01b' 'Autoteste: aceite da RFC 6455 pela RTL e pelo Indy, quadros, fragmentos, limites e UTF-8' ($selfCode -eq 0) (([regex]::Match($self, '(?m)Autoteste:.*$')).Value)
    Add-Check 'E0-01c' 'Versão do Indy compilada no executável = versão do código-fonte instalado' (($indyBin -ne '') -and ($indyBin -eq $indyFile)) "executável: $indyBin; IdVers.inc: $indyFile"

    # ---- 4. Servidor principal ----------------------------------------------
    Write-Log "`n===== 4. Servidor na porta 8790"
    $main = Start-Spike 8790 '' 'spike-8790'
    [void]$servers.Add($main)
    Write-Log "WsSpike iniciado (processo $($main.ServerPid))"

    $basicOk = 0
    for ($i = 1; $i -le $Repeat; $i++) {
        Write-Log "`n----- Testes Node, execução $i de $Repeat"
        $r = Invoke-Node "ws-tests.mjs basic --port 8790 --json `"$WorkDir\basic-$i.json`"" "básico $i"
        if ($r.Code -eq 0) { $basicOk++ }
        Add-Check ("E0-03/E0-09 #$i") 'Testes do canal sem navegador (handshake, 2 clientes, envio de outra thread, fragmentos, mensagens inválidas, limites, fechamentos)' ($r.Code -eq 0) (Summary-Line $r.Output)
    }

    $browserOk = 0
    for ($i = 1; $i -le $BrowserRepeat; $i++) {
        Write-Log "`n----- Chromium, execução $i de $BrowserRepeat"
        $r = Invoke-Node "browser-test.cjs --port 8790 --tests-dir `"$TestsDir`"" "navegador $i"
        if ($r.Code -eq 0) { $browserOk++ }
        Add-Check ("E0-02/E0-08 #$i") 'Dois navegadores Chromium, envio de outra thread, fechamento da página e queda simulada (routeWebSocket)' ($r.Code -eq 0) (Summary-Line $r.Output)
    }

    Write-Log "`n----- Carga: $LoadClients canais por $LoadSeconds s"
    $r = Invoke-Node "ws-tests.mjs load --port 8790 --clients $LoadClients --seconds $LoadSeconds" 'carga'
    Add-Check 'E0-06' "$LoadClients canais simultâneos por $LoadSeconds s, com eco e envio de outra thread, sem perdas nem erros" ($r.Code -eq 0) (Summary-Line $r.Output)

    Stop-SpikeByEvent $main
    $mainLog = Read-SpikeLog $main
    Add-Check 'E0-07a' 'Servidor 8790 encerra pelo evento de parada (mesmo código do Ctrl+C) com código 0' (($mainLog -match 'ENCERRADO em') -and ($mainLog -match 'SAIDA=0')) (([regex]::Match($mainLog, '(?m)^.*ENCERRADO em.*$')).Value.Trim())

    # ---- 5. Inatividade -------------------------------------------------------
    Write-Log "`n===== 5. Servidor na porta 8791 com 3 s de inatividade"
    $idle = Start-Spike 8791 '--idle-seconds 3' 'spike-8791-idle'
    [void]$servers.Add($idle)
    $r = Invoke-Node 'ws-tests.mjs idle --port 8791' 'inatividade'
    Add-Check 'E0-05b' 'Cliente calado é desconectado com 4408 no prazo; cliente ativo continua conectado' ($r.Code -eq 0) (Summary-Line $r.Output)
    Stop-SpikeByEvent $idle

    # ---- 6. Ctrl+C com canais abertos ----------------------------------------
    Write-Log "`n===== 6. Ctrl+C com 20 canais abertos (porta 8792)"
    $down = Start-Spike 8792 '' 'spike-8792-ctrlc'
    [void]$servers.Add($down)
    $ready = Join-Path $WorkDir 'hold-ready.txt'
    $holdOut = Join-Path $WorkDir 'hold-result.json'
    $holdLog = Join-Path $WorkDir 'hold-client.log'
    foreach ($f in @($ready, $holdOut, $holdLog)) { if (Test-Path $f) { Remove-Item $f -Force } }
    $hold = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"node `"$Client\ws-tests.mjs`" hold --port 8792 --clients 20 --ready `"$ready`" --out `"$holdOut`" > `"$holdLog`" 2>&1`"" -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path $ready)) { throw 'Os 20 canais do teste de Ctrl+C não abriram em 15 s.' }
    Write-Log "Canais abertos pelo cliente: $(Get-Content $ready)"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$CtrlC`" -ProcessId $($down.ServerPid)" -WindowStyle Hidden -PassThru -Wait
    $ctrlCode = $p.ExitCode
    Write-Log "send-ctrl-c.ps1 terminou com código $ctrlCode (0 = Ctrl+C enviado)"
    $usedFallback = $false
    if ($ctrlCode -ne 0) {
        Write-Log 'Ctrl+C não pôde ser enviado por script; usando o evento nomeado (mesmo caminho de código).'
        $usedFallback = $true
        $sw.Restart()
        $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\WsSpikeStop_8792'); [void]$ev.Set(); $ev.Dispose()
    }
    $exited = $down.Cmd.WaitForExit(10000)
    $elapsed = $sw.ElapsedMilliseconds
    if (-not $exited) { Stop-Process -Id $down.ServerPid -Force -ErrorAction SilentlyContinue; $down.Cmd.WaitForExit(5000) | Out-Null }
    $hold.WaitForExit(25000) | Out-Null
    if (Test-Path $holdLog) { Write-Log (Get-Content $holdLog -Raw -Encoding UTF8).TrimEnd() }
    $downLog = Read-SpikeLog $down
    Write-Log "Log do servidor 8792 (trecho final):"
    Write-Log ((($downLog -split "`r?`n") | Where-Object { $_ -match 'Encerramento|restantes|ENCERRADO|SAIDA' }) -join "`n")
    $codesOk = $false; $codesText = '(sem resultado)'
    if (Test-Path $holdOut) {
        $h = Get-Content $holdOut -Raw | ConvertFrom-Json
        $codesOk = (@($h.codes | Where-Object { $_ -ne 1001 }).Count -eq 0) -and (@($h.codes).Count -eq 20)
        $codesText = "códigos: " + ((@($h.codes) | Sort-Object -Unique) -join ', ') + "; motivos: " + (@($h.reasons) -join ', ')
    }
    $mEnd = [regex]::Match($downLog, 'ENCERRADO em (\d+) ms')
    $serverMs = if ($mEnd.Success) { [int]$mEnd.Groups[1].Value } else { 999999 }
    $signalOk = if ($usedFallback) { $downLog -match 'solicitado por evento nomeado' } else { $downLog -match 'solicitado por Ctrl\+C' }
    Add-Check 'E0-07b' 'Com 20 canais abertos: todos recebem 1001 e o processo termina com código 0 em até 5 s' ($exited -and ($serverMs -le 5000) -and $codesOk -and ($downLog -match 'SAIDA=0') -and $signalOk) "servidor encerrou em $serverMs ms após o sinal (total medido pelo script, incluindo iniciar o PowerShell auxiliar: $elapsed ms); $codesText; sinal: $(if ($usedFallback) { 'evento nomeado (Ctrl+C por script indisponível)' } else { 'Ctrl+C real' })"
    Add-Check 'E0-07c' 'Ctrl+C real enviado por script (sem recorrer ao evento nomeado)' (-not $usedFallback) "send-ctrl-c.ps1: código $ctrlCode"

    $again = Start-Spike 8792 '' 'spike-8792-reinicio'
    [void]$servers.Add($again)
    Add-Check 'E0-07d' 'A porta 8792 fica livre: um novo servidor sobe na mesma porta' $true "processo $($again.ServerPid)"
    Stop-SpikeByEvent $again

    # ---- 7. Logs e arquivos de produção -------------------------------------
    Write-Log "`n===== 7. Logs dos servidores e arquivos de produção"
    $allLogs = ''
    foreach ($s in $servers) { $allLogs += (Read-SpikeLog $s) + "`n" }
    $errLines = @(($allLogs -split "`r?`n") | Where-Object { $_ -match '\bERRO\b|Erro fatal' })
    $opened = @([regex]::Matches($allLogs, 'WS \d+ aberta')).Count
    $closed = @([regex]::Matches($allLogs, 'WS \d+ fechada')).Count
    Add-Check 'E0-12' 'Logs dos servidores sem erros inesperados; todo canal aberto foi fechado' (($errLines.Count -eq 0) -and ($opened -eq $closed) -and ($opened -gt 0)) ("canais abertos $opened, fechados $closed; linhas de erro: " + $(if ($errLines.Count) { $errLines -join ' | ' } else { 'nenhuma' }))
    $reasons = ($allLogs -split "`r?`n") | ForEach-Object { if ($_ -match 'fechada: (.*)$') { ($matches[1] -replace '\d+', 'N') } } | Group-Object | Sort-Object Count -Descending
    Write-Log 'Motivos de fechamento registrados pelo servidor:'
    foreach ($g in $reasons) { Write-Log ("  {0,4} x {1}" -f $g.Count, $g.Name) }

    $hashesAfter = Get-ProductionHashes
    $diff = Compare-Object -ReferenceObject @($hashesBefore) -DifferenceObject @($hashesAfter) -Property Path, Hash
    Add-Check 'E0-11' 'Arquivos de produção (servidor, interface, testes, scripts, documentos antigos) idênticos antes e depois' (-not $diff) $(if ($diff) { ($diff | ForEach-Object { "$($_.SideIndicator) $($_.Path)" }) -join '; ' } else { "$(@($hashesAfter).Count) arquivos conferidos por SHA-256" })

    Write-Log "`nRegressão do jogo (109 testes Playwright e 27 casos do EngineCheck): NÃO EXECUTADA nesta entrega."
    Write-Log 'Motivo: a O0 não altera nenhum arquivo de produção (ver E0-11); a regressão volta a ser obrigatória a partir da O1.'

    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
} catch {
    Write-Log "ERRO na validação: $($_.Exception.Message)"
    $failed = 1
} finally {
    foreach ($s in $servers) {
        if ($s.Cmd -and -not $s.Cmd.HasExited) { Stop-SpikeByEvent $s }
    }
}

Write-Log "`n===== Resumo"
foreach ($r in $Results) { Write-Log ("{0,-7} {1,-18} {2}" -f $r.Status, $r.Id, $r.Description) }
$verdict = if ($failed -eq 0) { 'APROVADO' } else { 'REPROVADO' }
Write-Log "`nResultado final: $verdict"
exit $(if ($failed -eq 0) { 0 } else { 1 })
