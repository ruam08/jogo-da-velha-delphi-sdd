# Validação da Entrega 4 (Playwright + TypeScript contra a API real).
# 1. ambiente (Windows, Node, npm) - nada é instalado globalmente;
# 2. compila o servidor com o Delphi Berlin e roda o EngineCheck (regressão);
# 3. instala as dependências locais de tests\ (npm ci, ou npm install na 1ª vez);
# 4. checagem de tipos (tsc --noEmit);
# 5. suíte completa duas vezes (relatório HTML em tests\playwright-report);
# 6. cada arquivo de teste isolado (independência da ordem);
# 7. sem o executável, a suíte precisa falhar (prova de que usa o servidor real);
# 8. SB-04: o R-27 precisa falhar contra um servidor sem a trava.
# Saída em logs\step4-validation.log. Windows PowerShell 5.1.
# Execute por: scripts\validate-step4.cmd

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir 'step4-validation.log'
$TestsDir  = Join-Path $Root 'tests'
$ServerDir = Join-Path $Root 'server'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$ExpectedPlaywright = '1.64.1'

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

# Executa um comando via cmd.exe dentro de tests\ e devolve código e saída.
function Invoke-InTests([string]$CommandLine) {
    Write-Log "> cd tests && $CommandLine"
    Push-Location $TestsDir
    try {
        $out = & cmd.exe /c "$CommandLine 2>&1" | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    [pscustomobject]@{ Code = $code; Output = $out }
}

function Read-Stats {
    $file = Join-Path $TestsDir 'test-results\results.json'
    if (-not (Test-Path $file)) { return $null }
    $json = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    return $json.stats
}

function Stop-Server($Proc) {
    if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force; $Proc.WaitForExit(5000) | Out-Null }
}

$renamed = $false
$backupExe = "$ServerExe.validacao.bak"
$sabServer = $null
$failed = 1
try {
    Write-Log ("===== Validação da Entrega 4 - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-Log "Pasta do projeto: $Root"

    # ---- 1. Ambiente ----------------------------------------------------------
    Write-Log "`n===== 1. Ambiente (nada é instalado globalmente)"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2})" -f $os.Caption, $os.Version, $os.BuildNumber)
    $nodeVersion = (& cmd.exe /c "node --version 2>&1" | Out-String).Trim()
    $npmVersion = (& cmd.exe /c "npm --version 2>&1" | Out-String).Trim()
    $nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
    Write-Log "Node.js: $nodeVersion ($nodePath)"
    Write-Log "npm: $npmVersion"
    $nodeMajor = 0
    if ($nodeVersion -match '^v(\d+)\.') { $nodeMajor = [int]$Matches[1] }
    Add-Check 'V-01' 'Node.js instalado atende ao Playwright 1.64 (>= 20; documentação: 22, 24 ou 26)' (@(22, 24, 26) -contains $nodeMajor) "Node $nodeVersion"

    # ---- 2. Delphi ------------------------------------------------------------
    Write-Log "`n===== 2. Compilação com o Delphi Berlin e regressão do EngineCheck"
    foreach ($exe in @($ServerExe, $EngineExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`" 2>&1" | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\b(Warning: W|Hint: H)\d+.*$')).Count
    Add-Check 'B-01' 'Servidor e EngineCheck compilados com o Delphi 10.1 Berlin (31.0), sem warnings nem hints' (($buildCode -eq 0) -and ($build -match 'compiler version 31\.0') -and ($warnings -eq 0) -and (Test-Path $ServerExe)) "Código $buildCode; warnings+hints: $warnings"
    if (-not (Test-Path $ServerExe)) { throw 'Servidor não compilado.' }
    $engine = & $EngineExe 2>&1 | Out-String
    $engineCode = $LASTEXITCODE
    $summary = ([regex]::Match($engine, '(?m)^Casos:.*$')).Value
    Write-Log $summary
    Add-Check 'B-02' 'EngineCheck (motor, serviço, JSON) continua aprovado' ($engineCode -eq 0) $summary

    # ---- 3. Dependências locais -----------------------------------------------
    Write-Log "`n===== 3. Dependências locais em tests\ (node_modules)"
    $lock = Join-Path $TestsDir 'package-lock.json'
    if (Test-Path $lock) {
        $install = Invoke-InTests 'npm ci --no-audit --no-fund'
    } else {
        Write-Log 'package-lock.json ainda não existe: primeira instalação com npm install (gera o lock).'
        $install = Invoke-InTests 'npm install --no-audit --no-fund'
    }
    Write-Log $install.Output.TrimEnd()
    Add-Check 'D-01' 'Dependências instaladas localmente (npm)' ($install.Code -eq 0) "Código $($install.Code)"
    if ($install.Code -ne 0) { throw 'Falha ao instalar as dependências.' }
    $pwVersion = (Invoke-InTests 'npx --no-install playwright --version').Output.Trim()
    $tscVersion = (Invoke-InTests 'npx --no-install tsc --version').Output.Trim()
    Write-Log "Playwright: $pwVersion | TypeScript: $tscVersion"
    Add-Check 'D-02' "Playwright na versão fixada ($ExpectedPlaywright)" ($pwVersion -match [regex]::Escape($ExpectedPlaywright)) $pwVersion

    # ---- 4. Tipos -------------------------------------------------------------
    Write-Log "`n===== 4. Checagem de tipos"
    $tsc = Invoke-InTests 'npm run typecheck'
    Write-Log $tsc.Output.TrimEnd()
    Add-Check 'T-01' 'TypeScript sem erros (tsc --noEmit)' ($tsc.Code -eq 0) "Código $($tsc.Code)"

    # ---- 5. Suíte completa (duas vezes) ----------------------------------------
    foreach ($run in 1, 2) {
        Write-Log "`n===== 5.$run Suíte completa, execução $run"
        $r = Invoke-InTests 'npx --no-install playwright test'
        Write-Log $r.Output.TrimEnd()
        $stats = Read-Stats
        if ($stats) {
            $resultsCopy = Join-Path $LogDir "step4-results-run$run.json"
            Copy-Item (Join-Path $TestsDir 'test-results\results.json') $resultsCopy -Force
            $detail = "aprovados: $($stats.expected); falharam: $($stats.unexpected); instáveis: $($stats.flaky); pulados: $($stats.skipped); duração: $([math]::Round($stats.duration / 1000, 1)) s"
            $ok = ($r.Code -eq 0) -and ($stats.unexpected -eq 0) -and ($stats.flaky -eq 0) -and ($stats.skipped -eq 0) -and ($stats.expected -gt 0)
        } else {
            $detail = 'results.json não foi gerado'
            $ok = $false
        }
        Add-Check "P-0$run" "Suíte Playwright completa, execução $run (sem retries)" $ok "Código $($r.Code); $detail"
    }
    $report = Join-Path $TestsDir 'playwright-report\index.html'
    Add-Check 'P-03' 'Relatório HTML gerado' (Test-Path $report) $report

    # ---- 6. Cada arquivo isolado ------------------------------------------------
    Write-Log "`n===== 6. Cada arquivo de teste executado sozinho (independência da ordem)"
    Push-Location $TestsDir
    $specs = @(Get-ChildItem -Path 'api', 'rules' -Filter '*.spec.ts' | ForEach-Object { (Resolve-Path -Relative $_.FullName) -replace '^\.\\', '' -replace '\\', '/' })
    Pop-Location
    $isolatedFailures = @()
    foreach ($spec in ($specs | Sort-Object -Descending)) {
        $r = Invoke-InTests "npx --no-install playwright test $spec --reporter=line"
        $last = (($r.Output.Trim() -split "`r?`n") | Select-Object -Last 1)
        Write-Log "    $spec -> código $($r.Code): $last"
        if ($r.Code -ne 0) { $isolatedFailures += $spec; Write-Log $r.Output.TrimEnd() }
    }
    Add-Check 'P-04' "Cada um dos $($specs.Count) arquivos passa sozinho (ordem inversa)" ($isolatedFailures.Count -eq 0 -and $specs.Count -gt 0) ("Falharam: " + ($isolatedFailures -join ', '))

    # ---- 7. Sem o executável, a suíte falha ---------------------------------
    Write-Log "`n===== 7. Prova de que a suíte usa o servidor real: executável renomeado"
    Move-Item $ServerExe $backupExe -Force
    $renamed = $true
    $r = Invoke-InTests 'npx --no-install playwright test api/contract.spec.ts --reporter=line'
    Move-Item $backupExe $ServerExe -Force
    $renamed = $false
    $excerpt = (($r.Output -split "`r?`n") | Where-Object { $_ -match 'webServer|TicTacToeServer|reconhecido|not recognized|Error' } | Select-Object -First 4) -join ' | '
    Write-Log "Código: $($r.Code). Trecho: $excerpt"
    Add-Check 'P-05' 'Sem o TicTacToeServer.exe, a suíte falha ao iniciar o servidor' ($r.Code -ne 0) $excerpt

    # ---- 8. SB-04: servidor sem trava ------------------------------------------
    Write-Log "`n===== 8. SB-04: R-27 (Playwright) contra um servidor sem trava e com atraso"
    $dir = Join-Path $LogDir 'sabotage\SB-04-playwright'
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
    Copy-Item (Join-Path $ServerDir 'TicTacToeServer.dpr') $dir
    Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
    $svcPath = Join-Path $dir 'src\uGameService.pas'
    $engPath = Join-Path $dir 'src\uGameEngine.pas'
    $svc = [System.IO.File]::ReadAllText($svcPath, [System.Text.Encoding]::UTF8)
    $eng = [System.IO.File]::ReadAllText($engPath, [System.Text.Encoding]::UTF8)
    $locks = ([regex]::Matches($svc, 'FLock\.(Enter|Leave);')).Count
    $svc = [regex]::Replace($svc, 'FLock\.(Enter|Leave);', '{ sabotagem: sem trava }')
    $writeLine = '  FBoard[APosition] := FCurrentPlayer;'
    $writes = ([regex]::Matches($eng, [regex]::Escape($writeLine))).Count
    $eng = $eng.Replace($writeLine, "  Sleep(50);   { sabotagem }`r`n" + $writeLine)
    $eng = ([regex]'(?m)^implementation\r?$').Replace($eng, "implementation`r`n`r`nuses`r`n  Winapi.Windows;", 1)
    [System.IO.File]::WriteAllText($svcPath, $svc, (New-Object System.Text.UTF8Encoding($true)))
    [System.IO.File]::WriteAllText($engPath, $eng, (New-Object System.Text.UTF8Encoding($true)))
    $c = & cmd.exe /c "`"$Compile`" `"$dir`" TicTacToeServer.dpr 2>&1" | Out-String
    if ($LASTEXITCODE -ne 0 -or $locks -lt 2 -or $writes -ne 1) {
        Write-Log $c.TrimEnd()
        Add-Check 'P-06' 'SB-04: cópia sabotada compilada' $false "dcc32: $LASTEXITCODE; travas: $locks; gravações: $writes"
    } else {
        $sabExe = Join-Path $dir 'bin\TicTacToeServer.exe'
        $sabServer = Start-Process -FilePath $sabExe -ArgumentList @('--port', '8766') -RedirectStandardOutput (Join-Path $LogDir 'server-step4-SB-04.out.log') -RedirectStandardError (Join-Path $LogDir 'server-step4-SB-04.err.log') -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 2
        $env:PW_EXTERNAL_SERVER = '1'
        $env:PW_PORT = '8766'
        try {
            $r = Invoke-InTests 'npx --no-install playwright test rules/concurrency.spec.ts --grep R-27 --reporter=line'
        } finally {
            Remove-Item Env:PW_EXTERNAL_SERVER -ErrorAction SilentlyContinue
            Remove-Item Env:PW_PORT -ErrorAction SilentlyContinue
        }
        Stop-Server $sabServer
        $sabServer = $null
        $excerpt = (($r.Output -split "`r?`n") | Where-Object { $_ -match 'repetição|Expected|Received|failed|passed' } | Select-Object -First 6) -join ' | '
        Write-Log "Código: $($r.Code). Trecho: $excerpt"
        Add-Check 'P-06' 'SB-04: sem a trava, o R-27 do Playwright detecta jogadas simultâneas incompatíveis' ($r.Code -ne 0 -and $r.Output -match 'R-27') $excerpt
    }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    if ($renamed -and (Test-Path $backupExe)) { Move-Item $backupExe $ServerExe -Force }
    Stop-Server $sabServer
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-5} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Relatório HTML: " + (Join-Path $TestsDir 'playwright-report\index.html'))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
