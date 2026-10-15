# Validação da Entrega 2 (motor do jogo + EngineCheck).
# Compila, roda o EngineCheck, aplica sabotagens em cópias temporárias,
# confere a independência do motor e a regressão do /health.
# Tudo é gravado em logs\step2-validation.log (ou logs\step2-red.log com -RedPhase).
# Compatível com Windows PowerShell 5.1. Execute por: scripts\validate-step2.cmd
param([switch]$RedPhase)

# 'Continue': no Windows PowerShell 5.1, 'Stop' transforma texto em stderr de
# programas nativos (dcc32, curl) em erro fatal.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogName   = if ($RedPhase) { 'step2-red.log' } else { 'step2-validation.log' }
$LogFile   = Join-Path $LogDir $LogName
$ServerDir = Join-Path $Root 'server'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$Port      = 8765

$ExpectedCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3',
    'M-05-C1','M-05-C2','M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08',
    'M-09','M-10','M-11','M-12')

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

# Roda um programa, devolve código de saída e saída completa.
function Invoke-Program([string]$Exe, [string[]]$Arguments) {
    $out = & $Exe @Arguments 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

function Invoke-Compile([string]$Dir, [string]$Dpr) {
    $out = & cmd.exe /c "`"$Compile`" `"$Dir`" $Dpr" 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

function Get-CaseIds([string]$Output, [string]$Tag) {
    $ids = @()
    foreach ($m in [regex]::Matches($Output, "(?m)^\[$Tag\]\s+(\S+)")) { $ids += $m.Groups[1].Value }
    return ,$ids
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega 2 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: motor ainda é um esqueleto)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (build {1}); PowerShell {2}" -f $os.Caption, $os.BuildNumber, $PSVersionTable.PSVersion)

    # ---- Compilação -------------------------------------------------------
    Write-Log "`n===== Compilação (scripts\build.cmd)"
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`"" 2>&1 | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    Write-Log "Código de saída do build: $buildCode"
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $hints    = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$') | ForEach-Object { $_.Value.Trim() })
    Add-Check 'B-01' 'Compilação do servidor e do EngineCheck sem erros' ($buildCode -eq 0) ''
    Add-Check 'B-02' 'Compilador é o Delphi 10.1 Berlin (compiler version 31.0)' ($build -match 'compiler version 31\.0') ''
    Add-Check 'B-03' 'Executáveis gerados (TicTacToeServer.exe e EngineCheck.exe)' ((Test-Path $EngineExe) -and (Test-Path $ServerExe)) ''
    Add-Check 'B-04' 'Nenhum warning do compilador' ($warnings.Count -eq 0) ("Warnings: {0}; hints: {1}" -f $warnings.Count, $hints.Count)
    foreach ($w in $warnings) { Write-Log "         $w" }
    foreach ($h in $hints) { Write-Log "         $h" }
    if (-not (Test-Path $EngineExe)) { throw 'EngineCheck.exe não foi gerado.' }

    # ---- Independência do motor --------------------------------------------
    Write-Log "`n===== Independência do motor"
    $engineSrc = Get-Content (Join-Path $ServerDir 'src\uGameEngine.pas') -Raw -Encoding UTF8
    $usesText = (([regex]::Matches($engineSrc, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',')
    $usedUnits = @($usesText -split ',' | ForEach-Object { ($_ -replace '\{.*?\}', '').Trim() } | Where-Object { $_ })
    $forbidden = @($usedUnits | Where-Object { $_ -match '^(Id\w+|System\.JSON|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameJson|uGameService|Vcl\..*|FMX\..*)$' })
    Write-Log ("Units usadas por uGameEngine: " + $(if ($usedUnits.Count) { $usedUnits -join ', ' } else { '(nenhuma)' }))
    Add-Check 'I-01' 'uGameEngine não usa Indy, HTTP, JSON, interface nem log' ($forbidden.Count -eq 0) ("Proibidas encontradas: " + ($forbidden -join ', '))

    # ---- EngineCheck --------------------------------------------------------
    Write-Log "`n===== EngineCheck.exe"
    $run = Invoke-Program $EngineExe @()
    Write-Log $run.Output.TrimEnd()
    Write-Log "Código de saída do EngineCheck: $($run.Code)"
    $okIds = Get-CaseIds $run.Output 'OK'
    $failIds = Get-CaseIds $run.Output 'FALHOU'
    $missing = @($ExpectedCases | Where-Object { ($okIds -notcontains $_) -and ($failIds -notcontains $_) })

    if ($RedPhase) {
        Add-Check 'R-01' 'Fase vermelha: EngineCheck compila contra o esqueleto e sai com código 1' ($run.Code -eq 1) "Código: $($run.Code)"
        Add-Check 'R-02' 'Fase vermelha: todos os casos esperados foram executados' ($missing.Count -eq 0) ("Ausentes: " + ($missing -join ', '))
        Write-Log ("Casos que falharam no esqueleto: " + ($failIds -join ', '))
        Write-Log ("Casos que passaram no esqueleto: " + $(if ($okIds.Count) { $okIds -join ', ' } else { '(nenhum)' }))
    } else {
        Add-Check 'E-01' 'EngineCheck sai com código 0' ($run.Code -eq 0) "Código: $($run.Code)"
        Add-Check 'E-02' 'Todos os casos M (e os demais) executados e aprovados' (($missing.Count -eq 0) -and ($failIds.Count -eq 0) -and ($okIds.Count -ge $ExpectedCases.Count)) ("OK: {0}; falharam: {1}; ausentes: {2}" -f $okIds.Count, ($failIds -join ','), ($missing -join ','))
        Add-Check 'E-03' 'Resumo do EngineCheck diz APROVADO' ($run.Output -match 'RESULTADO: APROVADO') ''

        # ---- Sabotagens -------------------------------------------------------
        Write-Log "`n===== Sabotagens (cópias temporárias; o código original não é alterado)"
        $sabotages = @(
            @{ Id = 'SB-01'; Desc = 'Trocar (2,4,6) por (0,1,2) em WIN_LINES';
               Find = '(0, 4, 8), (2, 4, 6));'; Replace = '(0, 4, 8), (0, 1, 2));';
               MustFail = @('M-05-D2', 'M-06', 'M-12') },
            @{ Id = 'SB-02'; Desc = 'Desligar a verificação de célula ocupada';
               Find = '  if FBoard[APosition] <> ceEmpty then'; Replace = '  if False then';
               MustFail = @('M-03', 'M-12') },
            @{ Id = 'SB-03'; Desc = 'Verificar célula ocupada antes de partida encerrada';
               Find = "  if FStatus <> gsInProgress then`r`n    Exit(mrGameOver);`r`n  if FBoard[APosition] <> ceEmpty then`r`n    Exit(mrCellOccupied);";
               Replace = "  if FBoard[APosition] <> ceEmpty then`r`n    Exit(mrCellOccupied);`r`n  if FStatus <> gsInProgress then`r`n    Exit(mrGameOver);";
               MustFail = @('M-08', 'M-12') },
            @{ Id = 'SB-05'; Desc = 'Não trocar o turno após a jogada';
               Find = '    FCurrentPlayer := OtherPlayer(FCurrentPlayer);'; Replace = '    { sabotagem: o turno nao troca }';
               MustFail = @('M-02', 'M-12') }
        )
        $sabRoot = Join-Path $LogDir 'sabotage'
        foreach ($sb in $sabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $sabRoot $sb.Id
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src'), (Join-Path $dir 'tests') | Out-Null
            Copy-Item (Join-Path $ServerDir 'EngineCheck.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
            Copy-Item (Join-Path $ServerDir 'tests\*.pas') (Join-Path $dir 'tests')

            $target = Join-Path $dir 'src\uGameEngine.pas'
            $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            $count = ([regex]::Matches($text, [regex]::Escape($sb.Find))).Count
            if ($count -ne 1) {
                Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false "Trecho encontrado $count vez(es); esperado 1."
                continue
            }
            $text = $text.Replace($sb.Find, $sb.Replace)
            [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($true)))

            $c = Invoke-Compile $dir 'EngineCheck.dpr'
            if ($c.Code -ne 0) {
                Write-Log $c.Output.TrimEnd()
                Add-Check $sb.Id "$($sb.Desc): cópia sabotada compila" $false "Código do dcc32: $($c.Code)"
                continue
            }
            $r = Invoke-Program (Join-Path $dir 'bin\EngineCheck.exe') @()
            Set-Content -Path (Join-Path $dir 'EngineCheck-output.log') -Value $r.Output -Encoding UTF8
            $sbFail = Get-CaseIds $r.Output 'FALHOU'
            $notCaught = @($sb.MustFail | Where-Object { $sbFail -notcontains $_ })
            Write-Log ("Código de saída: {0}; casos que falharam: {1}" -f $r.Code, ($sbFail -join ', '))
            Add-Check $sb.Id "$($sb.Desc): EngineCheck detecta (código 1 e falham $($sb.MustFail -join ', '))" (($r.Code -eq 1) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
        }

        # ---- Regressão da Entrega 1 -----------------------------------------
        Write-Log "`n===== Regressão: GET /health"
        $busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($busy) { throw "A porta $Port já está em uso (processo $($busy[0].OwningProcess))." }
        $srvOut = Join-Path $LogDir 'server-step2.out.log'
        $srvErr = Join-Path $LogDir 'server-step2.err.log'
        $server = Start-Process -FilePath $ServerExe -ArgumentList @('--port', "$Port") -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr -PassThru -WindowStyle Hidden
        try {
            $body = ''; $code = ''
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline) {
                $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
                if ("$code".Trim() -eq '200') { break }
                Start-Sleep -Milliseconds 250
            }
            $body = & curl.exe -s --max-time 2 "http://127.0.0.1:$Port/health" 2>$null
            Write-Log "Status: $code; corpo: $body"
            Add-Check 'G-01' 'GET /health continua respondendo 200 {"status":"ok"}' (("$code".Trim() -eq '200') -and ("$body".Trim() -eq '{"status":"ok"}')) ''
        } finally {
            if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force; $server.WaitForExit(5000) | Out-Null }
        }
    }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-6} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
