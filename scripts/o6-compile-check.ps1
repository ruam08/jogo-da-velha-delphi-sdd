# Verificação de compilação da O6 numa cópia (logs\o6-compile\), sem alterar o projeto.
# Copia server\ e sobrepõe os arquivos de logs\o6-compile-src\ (src\, tests\ e os .dpr).
# Compila os dois programas com limite de 180 s cada. Saída: logs\o6-compile-check.log
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
$Src = Join-Path $LogDir 'o6-compile-src'
$Dir = Join-Path $LogDir 'o6-compile'
$Log = Join-Path $LogDir 'o6-compile-check.log'
$Compile = Join-Path $Root 'scripts\compile-dpr.cmd'
Set-Content -Path $Log -Value '' -Encoding UTF8
function W([string]$t) { Add-Content -Path $Log -Value $t -Encoding UTF8; Write-Host $t }
W ("===== Compilação da O6 numa cópia - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'src'), (Join-Path $Dir 'tests') | Out-Null
Copy-Item (Join-Path $Root 'server\*.dpr') $Dir
Copy-Item (Join-Path $Root 'server\src\*.pas') (Join-Path $Dir 'src')
Copy-Item (Join-Path $Root 'server\tests\*.pas') (Join-Path $Dir 'tests')
foreach ($f in Get-ChildItem $Src -File) {
    if ($f.Extension -eq '.dpr') { $dest = $Dir }
    elseif ($f.Name -like '*Tests.pas') { $dest = Join-Path $Dir 'tests' }
    else { $dest = Join-Path $Dir 'src' }
    Copy-Item $f.FullName $dest -Force
    W ("sobreposto: {0}" -f $f.Name)
}
foreach ($dpr in @('TicTacToeServer.dpr', 'EngineCheck.dpr')) {
    $out = Join-Path $Dir "compile-$dpr.log"
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"`"$Compile`" `"$Dir`" $dpr > `"$out`" 2>&1`"" -WindowStyle Hidden -PassThru
    $done = $p.WaitForExit(180000)
    if (-not $done) {
        foreach ($c in @(Get-CimInstance Win32_Process -Filter "Name = 'dcc32.exe'")) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        W "$dpr : TEMPO ESGOTADO"
    } else {
        W ("{0}: código {1}" -f $dpr, $p.ExitCode)
    }
    if (Test-Path $out) { foreach ($l in @(Get-Content $out -Encoding Default | Where-Object { $_ -match 'Error|Fatal|Warning|Hint|lines,' })) { W ("    " + $l.Trim()) } }
}
$engine = Join-Path $Dir 'bin\EngineCheck.exe'
if (Test-Path $engine) {
    W "`n----- EngineCheck da cópia"
    $o = & $engine 2>&1 | Out-String
    W ((($o -split "`r?`n") | Where-Object { $_ -match '^(\[FALHOU\]|\[OK\]\s+(RL|OP)-|Casos:|RESULTADO|\s+-\s|\s+·)' }) -join "`r`n")
}
W "`n===== Fim"
