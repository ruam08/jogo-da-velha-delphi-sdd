# Diagnóstico da O5: o dcc32 travou ao compilar tests\uRoomJanitorTests.pas (fase vermelha).
# 1. Encerra só o dcc32 travado (a validação vermelha então termina sozinha, sem executáveis).
# 2. Compila o EngineCheck com cada variante do arquivo de teste numa cópia em logs\o5-probe\<V>,
#    com limite de 60 s cada; registra se compilou, falhou ou travou.
# Não altera o código do projeto. Saída: logs\o5-compile-probe.log
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
$Src = Join-Path $LogDir 'o5-probe-src'
$Log = Join-Path $LogDir 'o5-compile-probe.log'
$Compile = Join-Path $Root 'scripts\compile-dpr.cmd'
$ServerDir = Join-Path $Root 'server'
Set-Content -Path $Log -Value '' -Encoding UTF8
function W([string]$t) { Add-Content -Path $Log -Value $t -Encoding UTF8; Write-Host $t }

W ("===== Diagnóstico do dcc32 - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name = 'dcc32.exe'")) {
    W ("dcc32 em execução: PID {0}, iniciado {1}; linha: {2}" -f $p.ProcessId, $p.CreationDate, $p.CommandLine)
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    W "  encerrado."
}
W 'Esperando a validação vermelha terminar (até 120 s)...'
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $v = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.CommandLine -match 'validate-online-o5\.ps1' })
    if ($v.Count -eq 0) { break }
    Start-Sleep -Seconds 2
}
W ("Validação vermelha ainda em execução: {0}" -f (@(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.CommandLine -match 'validate-online-o5\.ps1' }).Count))

$variants = [ordered]@{
    'V0' = 'arquivo original (com métodos anônimos; TInterlocked.Increment numa variável capturada)'
    'V1' = 'igual ao V0, com Inc no lugar de TInterlocked.Increment na variável capturada'
    'V2' = 'sem métodos anônimos (Col.Add passado como referência de método)'
    'V3' = 'só o JN-01 (com o método anônimo simples)'
    'V4' = 'só o JN-02 (com o método anônimo que captura duas variáveis)'
    'V5' = 'V2 com o uRoomJanitor real (fase verde)'
}
foreach ($v in $variants.Keys) {
    W ("`n----- {0}: {1}" -f $v, $variants[$v])
    $dir = Join-Path $LogDir "o5-probe\$v"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src'), (Join-Path $dir 'tests') | Out-Null
    Copy-Item (Join-Path $ServerDir '*.dpr') $dir
    Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
    Copy-Item (Join-Path $ServerDir 'tests\*.pas') (Join-Path $dir 'tests')
    $pas = if ($v -eq 'V5') { 'V2.pas' } else { "$v.pas" }
    Copy-Item (Join-Path $Src $pas) (Join-Path $dir 'tests\uRoomJanitorTests.pas') -Force
    if ($v -eq 'V5') { Copy-Item (Join-Path $Src 'uRoomJanitor-real.pas') (Join-Path $dir 'src\uRoomJanitor.pas') -Force }
    $out = Join-Path $dir 'compile.log'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"`"$Compile`" `"$dir`" EngineCheck.dpr > `"$out`" 2>&1`"" -WindowStyle Hidden -PassThru
    $done = $p.WaitForExit(60000)
    $sw.Stop()
    if (-not $done) {
        foreach ($c in @(Get-CimInstance Win32_Process -Filter "Name = 'dcc32.exe'")) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        W ("{0}: TRAVOU (mais de 60 s; dcc32 encerrado)" -f $v)
    } else {
        $exe = Test-Path (Join-Path $dir 'bin\EngineCheck.exe')
        W ("{0}: terminou em {1:N1} s, código {2}, EngineCheck.exe gerado: {3}" -f $v, $sw.Elapsed.TotalSeconds, $p.ExitCode, $exe)
    }
    if (Test-Path $out) {
        $lines = @(Get-Content $out -Encoding Default | Where-Object { $_ -match 'Error|Fatal|Warning|Hint|lines,' } | Select-Object -First 12)
        foreach ($l in $lines) { W ("    " + $l.Trim()) }
    }
}
W "`n===== Fim"
