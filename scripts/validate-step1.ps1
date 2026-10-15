# Validação da Entrega 1 (estrutura do servidor + GET /health).
# Compila, inicia o servidor, faz requisições HTTP reais e grava tudo em
# logs\step1-validation.log. Compatível com Windows PowerShell 5.1.
# Execute por: scripts\validate-step1.cmd

# 'Continue': no Windows PowerShell 5.1, 'Stop' transforma qualquer texto em
# stderr de um programa nativo (curl, dcc32) em erro fatal.
$ErrorActionPreference = 'Continue'
$Root    = Split-Path -Parent $PSScriptRoot
$LogDir  = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'step1-validation.log'
$Exe     = Join-Path $Root 'server\bin\TicTacToeServer.exe'
$Port    = 8765
$Base    = "http://127.0.0.1:$Port"
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

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

# Faz uma requisição com curl.exe e devolve status, cabeçalhos e corpo (bytes).
function Invoke-Http([string]$Method, [string]$Path) {
    $bodyFile = [System.IO.Path]::GetTempFileName()
    $headFile = [System.IO.Path]::GetTempFileName()
    try {
        $curlArgs = @('-s', '-S', '-X', $Method, '-D', $headFile, '-o', $bodyFile, '-w', '%{http_code}', '--max-time', '5')
        if ($Method -eq 'POST') { $curlArgs += @('-H', 'Content-Length: 0') }
        $code = & curl.exe @curlArgs ($Base + $Path) 2>$null
        $codeNum = 0
        [void][int]::TryParse("$code".Trim(), [ref]$codeNum)
        $headers = Get-Content -Path $headFile -Raw -ErrorAction SilentlyContinue
        $bytes = [System.IO.File]::ReadAllBytes($bodyFile)
        [pscustomobject]@{ Code = $codeNum; Headers = "$headers"; Bytes = $bytes }
    } finally {
        Remove-Item $bodyFile, $headFile -ErrorAction SilentlyContinue
    }
}

# Envia um HEAD direto pelo socket e lê tudo até o servidor fechar a conexão.
function Invoke-RawHead([string]$Path) {
    $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $Port)
    try {
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        $request = [System.Text.Encoding]::ASCII.GetBytes("HEAD $Path HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n")
        $stream.Write($request, 0, $request.Length)
        $buffer = New-Object byte[] 4096
        $all = New-Object System.IO.MemoryStream
        while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $all.Write($buffer, 0, $n) }
        $text = [System.Text.Encoding]::ASCII.GetString($all.ToArray())
        $sep = $text.IndexOf("`r`n`r`n")
        if ($sep -lt 0) { return [pscustomobject]@{ Headers = $text; BodyLength = -1 } }
        [pscustomobject]@{ Headers = $text.Substring(0, $sep); BodyLength = $text.Length - ($sep + 4) }
    } finally {
        $client.Close()
    }
}

function Get-Header([string]$Headers, [string]$Name) {
    foreach ($line in ($Headers -split "`r?`n")) {
        if ($line -match ('^' + [regex]::Escape($Name) + ':\s*(.*)$')) { return $Matches[1].Trim() }
    }
    return $null
}

function Log-Response([string]$Title, $Resp) {
    Write-Log "----- $Title"
    Write-Log ($Resp.Headers.TrimEnd())
    if ($Resp.Bytes.Length -gt 0) {
        try { Write-Log ('Corpo: ' + $Utf8Strict.GetString($Resp.Bytes)) }
        catch { Write-Log ('Corpo (bytes UTF-8 inválidos): ' + [BitConverter]::ToString($Resp.Bytes)) }
    } else {
        Write-Log 'Corpo: (vazio)'
    }
}

function Wait-Health([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "$Base/health" 2>$null
        if ("$code".Trim() -eq '200') { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Start-Server([string]$Suffix) {
    $out = Join-Path $LogDir "server-step1-$Suffix.out.log"
    $err = Join-Path $LogDir "server-step1-$Suffix.err.log"
    return Start-Process -FilePath $Exe -ArgumentList @('--port', "$Port") `
        -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
}

function Stop-Server($Proc) {
    if ($Proc -and -not $Proc.HasExited) {
        Stop-Process -Id $Proc.Id -Force
        $Proc.WaitForExit(5000) | Out-Null
    }
}

$server = $null
$failed = 1
try {
    Write-Log "===== Validação da Entrega 1 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Pasta do projeto: $Root"

    # ---- Ambiente ---------------------------------------------------------
    Write-Log "`n===== Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2})" -f $os.Caption, $os.Version, $os.BuildNumber)
    Write-Log ("PowerShell: " + $PSVersionTable.PSVersion)
    foreach ($tool in @('curl.exe', 'git', 'node', 'npm')) {
        $cmd = Get-Command $tool -ErrorAction SilentlyContinue
        if ($cmd) {
            $ver = (& $tool --version 2>&1 | Select-Object -First 1)
            Write-Log ("{0}: {1}  ({2})" -f $tool, $ver, $cmd.Source)
        } else {
            Write-Log ("{0}: NÃO ENCONTRADO" -f $tool)
        }
    }

    # ---- Compilação -------------------------------------------------------
    Write-Log "`n===== Compilação (scripts\build.cmd)"
    if (Test-Path $Exe) { Remove-Item $Exe -Force }
    $buildCmd = Join-Path $Root 'scripts\build.cmd'
    $buildOut = & cmd.exe /c "`"$buildCmd`"" 2>&1 | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $buildOut.TrimEnd()
    Write-Log "Código de saída do build: $buildCode"
    Add-Check 'B-01' 'Compilação com dcc32 sem erros' ($buildCode -eq 0) ''
    Add-Check 'B-02' 'Compilador é o Delphi 10.1 Berlin (compiler version 31.0)' ($buildOut -match 'compiler version 31\.0') ''
    Add-Check 'B-03' 'Executável gerado em server\bin' (Test-Path $Exe) ''
    if (-not (Test-Path $Exe)) { throw 'Sem executável: validação interrompida.' }

    # ---- Porta livre ------------------------------------------------------
    $busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw "A porta $Port já está em uso (processo $($busy[0].OwningProcess)). Feche-o e rode de novo." }

    # ---- Servidor ---------------------------------------------------------
    Write-Log "`n===== Execução"
    $server = Start-Server 'run1'
    $up = Wait-Health 10
    Add-Check 'S-01' "Servidor iniciou e respondeu em $Base/health em até 10 s" $up ("PID " + $server.Id)
    if (-not $up) { throw 'Servidor não respondeu.' }

    $listen = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    $addrs = ($listen | ForEach-Object { $_.LocalAddress } | Sort-Object -Unique) -join ', '
    Add-Check 'S-02' 'Escuta somente em 127.0.0.1 (RNF-04)' (($listen.Count -ge 1) -and ($addrs -eq '127.0.0.1')) "Endereços em escuta: $addrs"

    # GET /health
    $r = Invoke-Http 'GET' '/health'
    Log-Response 'GET /health' $r
    $ct = Get-Header $r.Headers 'Content-Type'
    $json = $null
    try { $json = $Utf8Strict.GetString($r.Bytes) | ConvertFrom-Json } catch { }
    $keys = if ($json) { @($json.PSObject.Properties.Name) -join ',' } else { '' }
    Add-Check 'H-01' 'GET /health responde HTTP 200 (CA-27)' ($r.Code -eq 200) "Status: $($r.Code)"
    Add-Check 'H-02' 'Content-Type application/json com charset=utf-8' (($ct -match '^application/json') -and ($ct -match 'charset=utf-8')) "Content-Type: $ct"
    Add-Check 'H-03' 'Corpo é exatamente {"status":"ok"}' (($keys -eq 'status') -and ($json.status -eq 'ok')) ('Campos: ' + $keys)
    Add-Check 'H-04' 'Cache-Control: no-store' ((Get-Header $r.Headers 'Cache-Control') -eq 'no-store') ''

    # HEAD /health - leitura crua do socket: o curl -I não serve para medir
    # o corpo, porque grava os próprios cabeçalhos na saída.
    $raw = Invoke-RawHead '/health'
    Write-Log '----- HEAD /health (resposta crua do socket)'
    Write-Log $raw.Headers.TrimEnd()
    Write-Log ("Bytes depois dos cabeçalhos: " + $raw.BodyLength)
    Add-Check 'H-05' 'HEAD /health responde 200 sem corpo' (($raw.Headers -match '^HTTP/1\.1 200') -and ($raw.BodyLength -eq 0)) "Bytes no corpo: $($raw.BodyLength)"

    # POST /health e DELETE /health -> 405
    foreach ($m in @('POST', 'DELETE')) {
        $r = Invoke-Http $m '/health'
        Log-Response "$m /health" $r
        $body = $null
        try { $body = $Utf8Strict.GetString($r.Bytes) | ConvertFrom-Json } catch { }
        $ok = ($r.Code -eq 405) -and ((Get-Header $r.Headers 'Allow') -eq 'GET, HEAD') -and ($body.erro.codigo -eq 'METODO_NAO_PERMITIDO')
        Add-Check "H-06-$m" "$m /health responde 405, Allow: GET, HEAD e erro METODO_NAO_PERMITIDO" $ok "Status: $($r.Code); Allow: $(Get-Header $r.Headers 'Allow')"
    }

    # Rota inexistente -> 404 com mensagem acentuada correta
    $r = Invoke-Http 'GET' '/nao-existe'
    Log-Response 'GET /nao-existe' $r
    $expected = 'Rota n' + [char]0x00E3 + 'o encontrada.'
    $body = $null; $utf8ok = $true
    try { $body = $Utf8Strict.GetString($r.Bytes) | ConvertFrom-Json } catch { $utf8ok = $false }
    $ok = ($r.Code -eq 404) -and $utf8ok -and ($body.erro.codigo -eq 'ROTA_NAO_ENCONTRADA') -and ($body.erro.mensagem -eq $expected)
    Add-Check 'H-07' 'Rota inexistente responde 404 JSON, mensagem "Rota não encontrada." em UTF-8 válido' $ok "Status: $($r.Code); mensagem: $($body.erro.mensagem)"

    # Encerrar e subir de novo na mesma porta
    Write-Log "`n===== Reinício na mesma porta"
    Stop-Server $server
    Start-Sleep -Milliseconds 500
    $still = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    Add-Check 'S-03' 'Porta liberada depois que o processo é finalizado' (-not $still) ''
    $server = Start-Server 'run2'
    $up2 = Wait-Health 10
    Add-Check 'S-04' 'Servidor sobe de novo na mesma porta e responde /health' $up2 ("PID " + $server.Id)
    Stop-Server $server
    $server = $null

    # Log do próprio servidor
    Write-Log "`n===== Saída do servidor (1ª execução)"
    Write-Log ((Get-Content (Join-Path $LogDir 'server-step1-run1.out.log') -Raw -Encoding UTF8) | Out-String).TrimEnd()
    $errText = (Get-Content (Join-Path $LogDir 'server-step1-run1.err.log') -Raw -ErrorAction SilentlyContinue)
    if ($errText) { Write-Log ("Erros do servidor:`n" + $errText) }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    Stop-Server $server
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-9} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
