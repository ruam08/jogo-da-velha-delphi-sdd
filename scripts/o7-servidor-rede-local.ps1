# Entrega O7: servidor para a validação manual na rede local (roteiro MV-L, docs/test-plan-online.md, 13.4).
# Sobe o TicTacToeServer.exe já compilado, no modo local (bind padrão 0.0.0.0, porta 8765), mostra o
# endereço para abrir no celular e grava o que o servidor escreve em logs\o7-rede-local-<hora>-servidor.log
# (cada canal aberto registra o IP do aparelho: é a evidência de que o celular se conectou).
# Registra também (somente leitura) o perfil da rede e o estado do firewall no início.
# Não altera nada no Windows. Encerre com Ctrl+C nesta janela: o servidor recebe o Ctrl+C e
# fecha os canais com 1001, como no uso normal.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $Root 'server\bin\TicTacToeServer.exe'
$Web = Join-Path $Root 'web'
$LogDir = Join-Path $Root 'logs'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Log = Join-Path $LogDir "o7-rede-local-$Stamp.log"
$ServerLog = Join-Path $LogDir "o7-rede-local-$Stamp-servidor.log"
$ServerErr = Join-Path $LogDir "o7-rede-local-$Stamp-servidor.err.log"
function W([string]$Text) { Add-Content -Path $Log -Value $Text -Encoding UTF8; Write-Host $Text }

W ("===== Validação na rede local (MV-L) - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if (-not (Test-Path $Exe)) { W "Servidor não encontrado: $Exe (rode scripts\build.cmd)."; exit 1 }
W ("Executável: {0} (SHA-256 {1})" -f $Exe, (Get-FileHash -Algorithm SHA256 $Exe).Hash)
try { foreach ($p in @(Get-NetConnectionProfile -ErrorAction Stop)) { W ("Perfil de rede: '{0}' ({1}) -> {2}" -f $p.Name, $p.InterfaceAlias, $p.NetworkCategory) } } catch { W "Perfil de rede: não lido ($($_.Exception.Message))" }
try { foreach ($f in @(Get-NetFirewallProfile -ErrorAction Stop)) { W ("Firewall, perfil {0}: ativo={1}; entrada padrão={2}" -f $f.Name, $f.Enabled, $f.DefaultInboundAction) } } catch { W "Firewall: não lido ($($_.Exception.Message))" }
try {
    $rules = @(Get-NetFirewallApplicationFilter -ErrorAction Stop | Where-Object { $_.Program -like '*TicTacToeServer*' } | Get-NetFirewallRule -ErrorAction Stop)
    if ($rules.Count -eq 0) { W "Regras do firewall para o TicTacToeServer.exe: nenhuma (o Windows deve perguntar ao iniciar)" }
    foreach ($r in $rules) { W ("Regra '{0}': ativa={1}; direção={2}; ação={3}; perfis={4}; programa={5}" -f $r.DisplayName, $r.Enabled, $r.Direction, $r.Action, $r.Profile, ($r | Get-NetFirewallApplicationFilter).Program) }
} catch { W "Regras do firewall: não lidas ($($_.Exception.Message))" }
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' } | ForEach-Object { $_.IPAddress })
foreach ($ip in $ips) { W "No celular (mesma rede Wi-Fi): http://${ip}:8765/online.html" }
W "Neste computador: http://127.0.0.1:8765/online.html (ou pelo IP acima)"
if (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue) { W 'A porta 8765 já está em uso. Feche o outro servidor (ou a validação em andamento) e rode de novo.'; exit 1 }
W "Iniciando o servidor. Ctrl+C nesta janela encerra. Log do servidor: $ServerLog`r`n"
$p = Start-Process -FilePath $Exe -ArgumentList @('--port', '8765', '--www', "`"$Web`"") -NoNewWindow -PassThru `
    -RedirectStandardOutput $ServerLog -RedirectStandardError $ServerErr
try {
    $shown = 0
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 500
        if (Test-Path $ServerLog) {
            $lines = @(Get-Content $ServerLog -Encoding UTF8 -ErrorAction SilentlyContinue)
            for ($i = $shown; $i -lt $lines.Count; $i++) { Write-Host $lines[$i] }
            $shown = $lines.Count
        }
    }
} finally {
    Start-Sleep -Milliseconds 800
    W ("`r`n===== Servidor encerrado - {0} (código {1})" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($p.HasExited) { $p.ExitCode } else { 'ainda aberto' }))
    $peers = @(Get-Content $ServerLog -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { if ($_ -match 'WS \d+ aberta: ([0-9.]+)') { $Matches[1] } } | Sort-Object -Unique)
    W ("Endereços que abriram canais: " + $(if ($peers.Count) { $peers -join ', ' } else { 'nenhum' }))
}
