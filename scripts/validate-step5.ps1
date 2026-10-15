# Validação da Entrega 5 (interface web + testes no navegador).
#  1. ambiente; 2. compilação Delphi + EngineCheck; 3. npm ci;
#  4. instalação do Chromium do Playwright (cache do usuário);
#  5. tipos; 6. suíte completa com o servidor iniciado pelo Playwright;
#  7. suíte completa com servidor iniciado pelo script (log do servidor verificado);
#  8. cada arquivo isolado; 9. SB-06 (interface que não espera o servidor);
#  10. SB-04 (servidor sem trava); 11. capturas de tela.
# Com -RedPhase: só 1 a 6, esperando falhas na interface e nos estáticos.
# Saída em logs\step5-validation.log (ou logs\step5-red.log). Windows PowerShell 5.1.
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'step5-red.log' } else { 'step5-validation.log' })
$TestsDir  = Join-Path $Root 'tests'
$ServerDir = Join-Path $Root 'server'
$WebDir    = Join-Path $Root 'web'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$ShotsDir  = Join-Path $Root 'docs\screenshots'

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

function Invoke-InTests([string]$CommandLine) {
    Write-Log "> cd tests && $CommandLine"
    Push-Location $TestsDir
    try {
        $out = & cmd.exe /c "$CommandLine 2>&1" | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    [pscustomobject]@{ Code = $code; Output = $out }
}

# Lê tests\test-results\results.json e conta resultados por projeto.
function Read-Results {
    $file = Join-Path $TestsDir 'test-results\results.json'
    if (-not (Test-Path $file)) { return $null }
    $json = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $byProject = @{}
    $failedTitles = New-Object System.Collections.ArrayList
    $walk = $null
    $walk = {
        param($suite, $prefix)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                $p = $t.projectName
                if (-not $byProject.ContainsKey($p)) { $byProject[$p] = @{ ok = 0; fail = 0 } }
                if ($t.status -eq 'expected') { $byProject[$p].ok++ } else { $byProject[$p].fail++; [void]$failedTitles.Add("[$p] $($spec.title)") }
            }
        }
        foreach ($child in @($suite.suites)) { if ($child) { & $walk $child $prefix } }
    }
    foreach ($s in @($json.suites)) { & $walk $s '' }
    [pscustomobject]@{ Stats = $json.stats; ByProject = $byProject; Failed = $failedTitles }
}

function Format-Results($r) {
    if (-not $r) { return 'results.json não foi gerado' }
    $parts = @()
    foreach ($k in ($r.ByProject.Keys | Sort-Object)) { $parts += ("{0}: {1} ok, {2} falha(s)" -f $k, $r.ByProject[$k].ok, $r.ByProject[$k].fail) }
    ("aprovados {0}; falharam {1}; instáveis {2}; pulados {3}; {4}; duração {5} s" -f $r.Stats.expected, $r.Stats.unexpected, $r.Stats.flaky, $r.Stats.skipped, ($parts -join '; '), [math]::Round($r.Stats.duration / 1000, 1))
}

function Start-Server([string]$Exe, [int]$Port, [string]$Www, [string]$Name) {
    $busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw "A porta $Port já está em uso (processo $($busy[0].OwningProcess))." }
    $procArgs = @('--port', "$Port")
    if ($Www) { $procArgs += @('--www', "`"$Www`"") }
    $p = Start-Process -FilePath $Exe -ArgumentList $procArgs -RedirectStandardOutput (Join-Path $LogDir "$Name.out.log") -RedirectStandardError (Join-Path $LogDir "$Name.err.log") -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
        if ("$code".Trim() -eq '200') { return $p }
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

$servers = New-Object System.Collections.ArrayList
$failed = 1
try {
    Write-Log ("===== Validação da Entrega 5 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: interface e estáticos ainda não implementados)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"

    # ---- 1. Ambiente -------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2})" -f $os.Caption, $os.Version, $os.BuildNumber)
    Write-Log ("Node.js: " + (& cmd.exe /c "node --version 2>&1" | Out-String).Trim() + " | npm: " + (& cmd.exe /c "npm --version 2>&1" | Out-String).Trim())

    # ---- 2. Delphi ---------------------------------------------------------
    Write-Log "`n===== 2. Compilação com o Delphi Berlin e EngineCheck"
    foreach ($exe in @($ServerExe, $EngineExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`" 2>&1" | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warn = @([regex]::Matches($build, '(?m)^.*\b(Warning: W|Hint: H)\d+.*$')).Count
    Add-Check 'B-01' 'Compilação Delphi 10.1 Berlin (31.0) sem erros, warnings ou hints' (($buildCode -eq 0) -and ($build -match 'compiler version 31\.0') -and ($warn -eq 0)) "Código $buildCode; warnings+hints $warn"
    if (-not (Test-Path $ServerExe)) { throw 'Servidor não compilado.' }
    $engine = & $EngineExe 2>&1 | Out-String
    $engineCode = $LASTEXITCODE
    $summary = ([regex]::Match($engine, '(?m)^Casos:.*$')).Value
    Add-Check 'B-02' 'EngineCheck aprovado' ($engineCode -eq 0) $summary

    # ---- 3. Dependências ---------------------------------------------------
    Write-Log "`n===== 3. Dependências locais (npm ci)"
    $install = Invoke-InTests 'npm ci --no-audit --no-fund'
    Write-Log $install.Output.TrimEnd()
    Add-Check 'D-01' 'npm ci com o package-lock.json' ($install.Code -eq 0) "Código $($install.Code)"
    if ($install.Code -ne 0) { throw 'Falha no npm ci.' }

    # ---- 4. Chromium -------------------------------------------------------
    Write-Log "`n===== 4. Chromium do Playwright"
    $chromium = Invoke-InTests 'npx --no-install playwright install chromium'
    Write-Log $chromium.Output.TrimEnd()
    $cache = Join-Path $env:LOCALAPPDATA 'ms-playwright'
    $dirs = if (Test-Path $cache) { @(Get-ChildItem $cache -Directory | ForEach-Object { $_.Name }) } else { @() }
    Write-Log ("Cache de navegadores: $cache -> " + ($dirs -join ', '))
    Add-Check 'C-01' 'Chromium instalado pelo Playwright 1.64.1' (($chromium.Code -eq 0) -and (@($dirs | Where-Object { $_ -like 'chromium*' }).Count -gt 0)) "Código $($chromium.Code)"
    if ($chromium.Code -ne 0) { throw 'Falha na instalação do Chromium (ver saída acima).' }

    # ---- 5. Tipos ----------------------------------------------------------
    Write-Log "`n===== 5. Checagem de tipos"
    $tsc = Invoke-InTests 'npm run typecheck'
    Write-Log $tsc.Output.TrimEnd()
    Add-Check 'T-01' 'TypeScript sem erros' ($tsc.Code -eq 0) "Código $($tsc.Code)"

    # ---- 6. Suíte completa (webServer do Playwright) -------------------------
    Write-Log "`n===== 6. Suíte completa (API + navegador), servidor iniciado pelo Playwright"
    $run = Invoke-InTests 'npx --no-install playwright test'
    Write-Log $run.Output.TrimEnd()
    $res = Read-Results
    if ($res) { Copy-Item (Join-Path $TestsDir 'test-results\results.json') (Join-Path $LogDir 'step5-results-run1.json') -Force }
    Write-Log ("Resultado: " + (Format-Results $res))
    if ($res -and $res.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res.Failed -join "`r`n  ")) }

    if ($RedPhase) {
        # Falhas do projeto api que NÃO são de estáticos (A-10): precisam ser zero.
        $apiOther = @($res.Failed | Where-Object { $_.StartsWith('[api]') -and -not $_.Contains('A-10') })
        $apiOk = ($null -ne $res) -and ($apiOther.Count -eq 0)
        Add-Check 'R-01' 'Fase vermelha: a suíte executou com o Chromium e há falhas' ($res -and $res.Stats.unexpected -gt 0) (Format-Results $res)
        Add-Check 'R-02' 'Fase vermelha: no projeto api, só os testes de estáticos (A-10) falham' ([bool]$apiOk) ''
        Add-Check 'R-03' 'Fase vermelha: todos os testes de navegador falham (página ainda não existe)' ($res -and $res.ByProject['chromium'] -and $res.ByProject['chromium'].ok -eq 0) ''
    } else {
        $ok = ($run.Code -eq 0) -and $res -and ($res.Stats.unexpected -eq 0) -and ($res.Stats.flaky -eq 0) -and ($res.Stats.skipped -eq 0)
        Add-Check 'P-01' 'Suíte completa aprovada (servidor iniciado pelo Playwright)' $ok (Format-Results $res)
        Add-Check 'P-02' 'Relatório HTML gerado' (Test-Path (Join-Path $TestsDir 'playwright-report\index.html')) (Join-Path $TestsDir 'playwright-report\index.html')

        # ---- 7. Suíte completa com log do servidor ----------------------------
        Write-Log "`n===== 7. Suíte completa com o servidor iniciado pelo script (log do servidor verificado)"
        $srv = Start-Server $ServerExe 8765 $null 'server-step5'
        [void]$servers.Add($srv)
        $run2 = Invoke-External 8765 'npx --no-install playwright test'
        Stop-Server $srv
        $res2 = Read-Results
        Write-Log (($run2.Output -split "`r?`n" | Select-Object -Last 3) -join "`r`n")
        Write-Log ("Resultado: " + (Format-Results $res2))
        $ok2 = ($run2.Code -eq 0) -and $res2 -and ($res2.Stats.unexpected -eq 0) -and ($res2.Stats.flaky -eq 0)
        Add-Check 'P-03' 'Suíte completa aprovada pela segunda vez (servidor externo)' $ok2 (Format-Results $res2)
        $srvLog = Get-Content (Join-Path $LogDir 'server-step5.out.log') -Encoding UTF8
        Write-Log ("Primeiras linhas do log do servidor:`r`n" + (($srvLog | Select-Object -First 5) -join "`r`n"))
        $bad = @($srvLog | Where-Object { $_ -match '-> 5\d\d|ERRO em|AVISO' })
        $statics = @($srvLog | Where-Object { $_ -match 'GET /(app\.js|style\.css|index\.html)? -> 200' }).Count
        Write-Log ("Requisições registradas: {0}; estáticos servidos com 200: {1}" -f $srvLog.Count, $statics)
        Add-Check 'S-01' 'Log do servidor sem erros internos (500), exceções ou avisos' ($bad.Count -eq 0 -and $srvLog.Count -gt 0) (($bad | Select-Object -First 3) -join ' | ')

        # ---- 8. Cada arquivo isolado -----------------------------------------
        Write-Log "`n===== 8. Cada arquivo de teste sozinho (ordem inversa)"
        Push-Location $TestsDir
        $specs = @(Get-ChildItem -Path 'api', 'rules', 'ui' -Filter '*.spec.ts' | ForEach-Object { (Resolve-Path -Relative $_.FullName) -replace '^\.\\', '' -replace '\\', '/' })
        Pop-Location
        $isoFail = @()
        foreach ($spec in ($specs | Sort-Object -Descending)) {
            $r = Invoke-InTests "npx --no-install playwright test $spec --reporter=line"
            $last = (($r.Output.Trim() -split "`r?`n") | Select-Object -Last 1)
            Write-Log "    $spec -> código $($r.Code): $last"
            if ($r.Code -ne 0) { $isoFail += $spec; Write-Log $r.Output.TrimEnd() }
        }
        Add-Check 'P-04' "Cada um dos $($specs.Count) arquivos passa sozinho" ($isoFail.Count -eq 0) ("Falharam: " + ($isoFail -join ', '))

        # ---- 9. SB-06: interface desenha a jogada sem esperar o servidor ------
        Write-Log "`n===== 9. SB-06: app.js desenha 'X' localmente antes da resposta do servidor"
        $sabWeb = Join-Path $LogDir 'sabotage\SB-06\web'
        if (Test-Path (Split-Path $sabWeb)) { Remove-Item (Split-Path $sabWeb) -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $sabWeb | Out-Null
        Copy-Item (Join-Path $WebDir '*') $sabWeb
        $appPath = Join-Path $sabWeb 'app.js'
        $app = [System.IO.File]::ReadAllText($appPath, [System.Text.Encoding]::UTF8)
        $marker = '  function play(index) {'
        $count = ([regex]::Matches($app, [regex]::Escape($marker))).Count
        $app = $app.Replace($marker, $marker + "`n    cells[index].textContent = 'X'; // sabotagem SB-06")
        [System.IO.File]::WriteAllText($appPath, $app, (New-Object System.Text.UTF8Encoding($false)))
        if ($count -ne 1) {
            Add-Check 'P-05' 'SB-06: sabotagem aplicada' $false "Trecho encontrado $count vez(es)"
        } else {
            $sab = Start-Server $ServerExe 8766 $sabWeb 'server-step5-SB-06'
            [void]$servers.Add($sab)
            $r = Invoke-External 8766 'npx --no-install playwright test ui/end-and-reset.spec.ts --grep U-08 --reporter=line'
            Stop-Server $sab
            $excerpt = (($r.Output -split "`r?`n") | Where-Object { $_ -match 'U-08|Expected|Received|célula' } | Select-Object -First 5) -join ' | '
            Write-Log "Código: $($r.Code). Trecho: $excerpt"
            Add-Check 'P-05' 'SB-06: com a interface desenhando antes do servidor, o U-08 falha' ($r.Code -ne 0) $excerpt
        }

        # ---- 10. SB-04 com a suíte atual ---------------------------------------
        Write-Log "`n===== 10. SB-04: servidor sem trava (R-27)"
        $dir = Join-Path $LogDir 'sabotage\SB-04-step5'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src') | Out-Null
        Copy-Item (Join-Path $ServerDir 'TicTacToeServer.dpr') $dir
        Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
        $svcPath = Join-Path $dir 'src\uGameService.pas'; $engPath = Join-Path $dir 'src\uGameEngine.pas'
        $svc = [System.IO.File]::ReadAllText($svcPath, [System.Text.Encoding]::UTF8)
        $eng = [System.IO.File]::ReadAllText($engPath, [System.Text.Encoding]::UTF8)
        $svc = [regex]::Replace($svc, 'FLock\.(Enter|Leave);', '{ sabotagem }')
        $eng = $eng.Replace('  FBoard[APosition] := FCurrentPlayer;', "  Sleep(50);`r`n  FBoard[APosition] := FCurrentPlayer;")
        $eng = ([regex]'(?m)^implementation\r?$').Replace($eng, "implementation`r`n`r`nuses`r`n  Winapi.Windows;", 1)
        [System.IO.File]::WriteAllText($svcPath, $svc, (New-Object System.Text.UTF8Encoding($true)))
        [System.IO.File]::WriteAllText($engPath, $eng, (New-Object System.Text.UTF8Encoding($true)))
        $c = & cmd.exe /c "`"$Compile`" `"$dir`" TicTacToeServer.dpr 2>&1" | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Log $c.TrimEnd()
            Add-Check 'P-06' 'SB-04: cópia sabotada compila' $false ''
        } else {
            $sab = Start-Server (Join-Path $dir 'bin\TicTacToeServer.exe') 8766 $WebDir 'server-step5-SB-04'
            [void]$servers.Add($sab)
            $r = Invoke-External 8766 'npx --no-install playwright test rules/concurrency.spec.ts --grep R-27 --reporter=line'
            Stop-Server $sab
            Add-Check 'P-06' 'SB-04: sem a trava, o R-27 falha' ($r.Code -ne 0) "Código $($r.Code)"
        }

        # ---- 11. Capturas de tela ----------------------------------------------
        Write-Log "`n===== 11. Capturas de tela da interface real"
        New-Item -ItemType Directory -Force -Path $ShotsDir | Out-Null
        $shot = Start-Server $ServerExe 8767 $null 'server-step5-screens'
        [void]$servers.Add($shot)
        $r = Invoke-InTests "node tools/capture.cjs http://127.0.0.1:8767 `"$ShotsDir`""
        Stop-Server $shot
        Write-Log $r.Output.TrimEnd()
        Add-Check 'P-07' 'Capturas de tela geradas em docs\screenshots' ($r.Code -eq 0) "Código $($r.Code)"
    }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    foreach ($s in $servers) { Stop-Server $s }
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-5} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Relatório HTML: " + (Join-Path $TestsDir 'playwright-report\index.html'))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
