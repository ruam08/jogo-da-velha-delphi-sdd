# Entrega O7: inventário somente leitura (nada é alterado no projeto nem no Windows).
#  - estado do Git (status, branch, últimos commits, remoto, stash);
#  - lista exata dos arquivos de diagnóstico das O5 e O6 (para você decidir se apaga);
#  - rede e firewall do Windows (perfil da rede, IPv4, perfis e regras do firewall que citam
#    o TicTacToeServer.exe ou a porta 8765) — só leitura;
#  - SHA-256 de todos os arquivos do projeto (fora logs, .git, node_modules, binários e
#    resultados de teste), em logs\o7-hashes-<Tag>.txt; com -CompareWith, a diferença
#    em relação a um inventário anterior.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\o7-inventory.ps1 -Tag inicio
param([string]$Tag = 'inicio', [string]$CompareWith = '', [switch]$HashesOnly)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$Out = Join-Path $LogDir "o7-inventory-$Tag.log"
if (Test-Path $Out) { Remove-Item $Out -Force }
function W([string]$Text) { Add-Content -Path $Out -Value $Text -Encoding UTF8; Write-Host $Text }

# Pastas e arquivos que não entram no inventário de hashes (gerados ou fora do projeto).
$SkipDirs = '^(logs|\.git|tests\\node_modules|tests\\test-results|tests\\playwright-report|tests\\demo-results|server\\bin|server\\dcu|server\\Win32|server\\Win64)(\\|$)|(^|\\)__history(\\|$)|(^|\\)__recovery(\\|$)'
$SkipFiles = '\.(dcu|exe|identcache|local|stat|dsk)$|\.~'

function Get-ProjectHashes {
    $rootLen = $Root.TrimEnd('\').Length + 1
    $list = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($rootLen)
        if ($rel -match $SkipDirs) { continue }
        if ($rel -match $SkipFiles) { continue }
        $h = (Get-FileHash -Algorithm SHA256 -Path $f.FullName).Hash
        [void]$list.Add(("{0}  {1}" -f $h, $rel))
    }
    @($list | Sort-Object { $_.Substring(66) })
}

W ("===== Inventário da O7 ({0}) - {1}" -f $Tag, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W "Pasta do projeto: $Root"

if (-not $HashesOnly) {
    W "`n===== 1. Git (somente leitura)"
    Push-Location $Root
    try {
        W ("git: " + (& cmd.exe /c "git --version 2>&1" | Out-String).Trim())
        W ("Branch:`r`n" + (& cmd.exe /c "git branch -vv 2>&1" | Out-String).TrimEnd())
        W ("Últimos commits:`r`n" + (& cmd.exe /c "git log --oneline -8 2>&1" | Out-String).TrimEnd())
        W ("Remoto:`r`n" + (& cmd.exe /c "git remote -v 2>&1" | Out-String).TrimEnd())
        W ("Stash:`r`n" + (& cmd.exe /c "git stash list 2>&1" | Out-String).TrimEnd())
        W ("Arquivos versionados alterados (git diff --stat HEAD):`r`n" + (& cmd.exe /c "git diff --stat HEAD 2>&1" | Out-String).TrimEnd())
        W ("git status --porcelain --untracked-files=all:`r`n" + (& cmd.exe /c "git status --porcelain=v1 --untracked-files=all 2>&1" | Out-String).TrimEnd())
        W ("Ignorados pelo .gitignore (resumo por pasta):`r`n" + ((& cmd.exe /c "git status --porcelain=v1 --ignored=matching --untracked-files=normal 2>&1" | Where-Object { $_ -like '!!*' }) -join "`r`n"))
    } finally { Pop-Location }

    W "`n===== 2. Arquivos de diagnóstico (não fazem parte das entregas; nada foi apagado)"
    $diag = @('scripts\o5-compile-probe.cmd', 'scripts\o5-compile-probe.ps1', 'scripts\o6-compile-check.cmd', 'scripts\o6-compile-check.ps1',
              'logs\o5-compile-probe.log', 'logs\o6-compile-check.log', 'logs\o5-probe', 'logs\o5-probe-src', 'logs\o6-compile', 'logs\o6-compile-src', 'tests\demo-results',
              'logs\o7-nao-autorizado-19out')
    foreach ($rel in $diag) {
        $p = Join-Path $Root $rel
        if (-not (Test-Path $p)) { W ("  (não existe) {0}" -f $rel); continue }
        $item = Get-Item $p -Force
        if ($item.PSIsContainer) {
            $files = @(Get-ChildItem $p -Recurse -File -Force)
            $bytes = ($files | Measure-Object -Property Length -Sum).Sum
            W ("  pasta   {0}  ({1} arquivos, {2:N0} bytes, modificada em {3:dd/MM HH:mm})" -f $rel, $files.Count, $bytes, $item.LastWriteTime)
            foreach ($f in $files) { W ("            {0}  {1:N0} bytes" -f $f.FullName.Substring($Root.Length + 1), $f.Length) }
        } else {
            W ("  arquivo {0}  ({1:N0} bytes, modificado em {2:dd/MM HH:mm})" -f $rel, $item.Length, $item.LastWriteTime)
        }
    }

    # Fora da pasta do projeto: a cópia da tentativa não autorizada de 19/10 (19:42).
    $tempCopy = Join-Path $env:TEMP 'jogo-da-velha-o7-limpo'
    if (Test-Path $tempCopy) {
        $files = @(Get-ChildItem $tempCopy -Recurse -File -Force -ErrorAction SilentlyContinue)
        W ("  pasta   {0}  (fora do projeto; {1} arquivos, {2:N0} bytes)" -f $tempCopy, $files.Count, ($files | Measure-Object -Property Length -Sum).Sum)
    } else { W ("  (não existe) {0}" -f $tempCopy) }

    W "`n===== 2b. Processos do projeto abertos agora (servidor, EngineCheck, Node)"
    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -in @('TicTacToeServer.exe', 'EngineCheck.exe', 'dcc32.exe')) -or (($_.Name -eq 'node.exe') -and ($_.CommandLine -match 'playwright|ws-hold'))
    })
    if ($procs.Count -eq 0) { W "  nenhum" }
    foreach ($p in $procs) { W ("  {0} PID {1}: {2}" -f $p.Name, $p.ProcessId, $p.CommandLine) }

    W "`n===== 3. Rede e firewall do Windows (somente leitura)"
    try {
        foreach ($p in @(Get-NetConnectionProfile -ErrorAction Stop)) {
            W ("Perfil de rede: '{0}' na interface '{1}' -> categoria {2} (IPv4: {3})" -f $p.Name, $p.InterfaceAlias, $p.NetworkCategory, $p.IPv4Connectivity)
        }
    } catch { W ("Get-NetConnectionProfile falhou: " + $_.Exception.Message) }
    try {
        foreach ($a in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })) {
            W ("IPv4: {0}/{1} em '{2}'" -f $a.IPAddress, $a.PrefixLength, $a.InterfaceAlias)
        }
    } catch { W ("Get-NetIPAddress falhou: " + $_.Exception.Message) }
    try {
        foreach ($fp in @(Get-NetFirewallProfile -ErrorAction Stop)) {
            W ("Firewall, perfil {0}: ativo={1}; entrada padrão={2}; regras de entrada permitidas={3}" -f $fp.Name, $fp.Enabled, $fp.DefaultInboundAction, $fp.AllowInboundRules)
        }
    } catch { W ("Get-NetFirewallProfile falhou: " + $_.Exception.Message) }
    try {
        $rules = @(Get-NetFirewallApplicationFilter -ErrorAction Stop | Where-Object { $_.Program -like '*TicTacToeServer*' } | Get-NetFirewallRule -ErrorAction Stop)
        if ($rules.Count -eq 0) { W "Regras do firewall para o TicTacToeServer.exe: nenhuma" }
        foreach ($r in $rules) {
            $app = ($r | Get-NetFirewallApplicationFilter).Program
            W ("Regra '{0}': ativa={1}; direção={2}; ação={3}; perfis={4}; programa={5}" -f $r.DisplayName, $r.Enabled, $r.Direction, $r.Action, $r.Profile, $app)
        }
        $portRules = @(Get-NetFirewallPortFilter -ErrorAction Stop | Where-Object { $_.LocalPort -contains '8765' } | Get-NetFirewallRule -ErrorAction Stop)
        if ($portRules.Count -eq 0) { W "Regras do firewall para a porta 8765: nenhuma" }
        foreach ($r in $portRules) { W ("Regra da porta 8765 '{0}': ativa={1}; direção={2}; ação={3}; perfis={4}" -f $r.DisplayName, $r.Enabled, $r.Direction, $r.Action, $r.Profile) }
    } catch { W ("Leitura das regras do firewall falhou: " + $_.Exception.Message) }
    $listen = @(Get-NetTCPConnection -State Listen -LocalPort 8765 -ErrorAction SilentlyContinue)
    W ("Porta 8765 em escuta agora: " + $(if ($listen.Count) { ($listen | ForEach-Object { "$($_.LocalAddress) (PID $($_.OwningProcess))" }) -join ', ' } else { 'não' }))
}

W "`n===== 4. SHA-256 dos arquivos do projeto"
$hashes = Get-ProjectHashes
$HashFile = Join-Path $LogDir "o7-hashes-$Tag.txt"
[System.IO.File]::WriteAllLines($HashFile, [string[]]$hashes, (New-Object System.Text.UTF8Encoding($false)))
W ("{0} arquivos; lista em {1}" -f $hashes.Count, $HashFile)
if ($CompareWith) {
    $old = Join-Path $LogDir "o7-hashes-$CompareWith.txt"
    if (-not (Test-Path $old)) { W "Inventário '$CompareWith' não encontrado." }
    else {
        $a = @{}; foreach ($l in [System.IO.File]::ReadAllLines($old)) { $a[$l.Substring(66)] = $l.Substring(0, 64) }
        $b = @{}; foreach ($l in $hashes) { $b[$l.Substring(66)] = $l.Substring(0, 64) }
        $changed = @($b.Keys | Where-Object { $a.ContainsKey($_) -and $a[$_] -ne $b[$_] } | Sort-Object)
        $added = @($b.Keys | Where-Object { -not $a.ContainsKey($_) } | Sort-Object)
        $removed = @($a.Keys | Where-Object { -not $b.ContainsKey($_) } | Sort-Object)
        W ("Comparação com '{0}': alterados {1}; novos {2}; removidos {3}" -f $CompareWith, $changed.Count, $added.Count, $removed.Count)
        foreach ($x in $changed) { W "  alterado: $x" }
        foreach ($x in $added) { W "  novo:     $x" }
        foreach ($x in $removed) { W "  removido: $x" }
        W ("RESULTADO DA COMPARAÇÃO: " + $(if (($changed.Count + $added.Count + $removed.Count) -eq 0) { 'NENHUM ARQUIVO MUDOU' } else { 'HOUVE MUDANÇAS' }))
    }
}
W "`n===== Fim"
