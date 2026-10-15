# Validação da Entrega 3 (serviço de jogo + API HTTP).
# - compila (servidor e EngineCheck) e roda o EngineCheck (casos M, SV e J);
# - inicia o servidor real e executa os cenários A e R do docs/test-plan.md
#   com requisições HTTP reais (System.Net.Http.HttpClient);
# - sabotagem SB-04: servidor sem trava e com atraso deve falhar no R-27;
# - regressão do /health.
# Saída em logs\step3-validation.log (ou logs\step3-red.log com -RedPhase).
# Compatível com Windows PowerShell 5.1. Execute por: scripts\validate-step3.cmd
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Net.Http
[System.Net.ServicePointManager]::Expect100Continue = $false
[System.Net.ServicePointManager]::DefaultConnectionLimit = 64

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'step3-red.log' } else { 'step3-validation.log' })
$ServerDir = Join-Path $Root 'server'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$Port      = 8765
$script:Base = "http://127.0.0.1:$Port"
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

$Client = New-Object System.Net.Http.HttpClient
$Client.Timeout = [TimeSpan]::FromSeconds(15)
$Client.DefaultRequestHeaders.ExpectContinue = $false

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Content -Path $LogFile -Value '' -Encoding UTF8
$Results = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# Registro
# ---------------------------------------------------------------------------
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

# Executa um cenário; exceção vira falha do cenário, sem interromper os demais.
# O bloco devolve uma lista de problemas (vazia = passou).
function Test-Case([string]$Id, [string]$Description, [scriptblock]$Body) {
    $problems = @()
    try { $problems = @(& $Body) } catch { $problems = @("exceção: " + $_.Exception.Message) }
    $problems = @($problems | Where-Object { $_ })
    $detail = if ($problems.Count) { ($problems | Select-Object -First 6) -join ' | ' } else { '' }
    Add-Check $Id $Description ($problems.Count -eq 0) $detail
}

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
function New-Request([string]$Method, [string]$Path, $Body, [string]$ContentType, [string]$BaseUrl) {
    if (-not $BaseUrl) { $BaseUrl = $script:Base }
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), "$BaseUrl$Path")
    if ($null -ne $Body) {
        # Atribuição direta: um 'if' como expressão desmontaria um array vazio em $null.
        if ($Body -is [byte[]]) { $bytes = [byte[]]$Body } else { $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Body) }
        $content = New-Object System.Net.Http.ByteArrayContent(,$bytes)
        if ($ContentType) { $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($ContentType) }
        $req.Content = $content
    }
    return $req
}

function Convert-Response($Resp) {
    $bytes = $Resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    $text = $null; $utf8 = $true
    try { $text = $Utf8Strict.GetString($bytes) } catch { $utf8 = $false }
    $json = $null
    if ($text) { try { $json = $text | ConvertFrom-Json } catch { } }
    $ct = if ($Resp.Content.Headers.ContentType) { $Resp.Content.Headers.ContentType.ToString() } else { '' }
    $cache = if ($Resp.Headers.CacheControl) { $Resp.Headers.CacheControl.ToString() } else { '' }
    [pscustomobject]@{
        Status = [int]$Resp.StatusCode; Text = $text; Json = $json; Utf8 = $utf8
        ContentType = $ct; Allow = (@($Resp.Content.Headers.Allow) -join ', '); CacheControl = $cache
    }
}

function Send([string]$Method, [string]$Path, $Body = $null, [string]$ContentType = 'application/json', [string]$BaseUrl = $null) {
    $req = New-Request $Method $Path $Body $ContentType $BaseUrl
    $resp = $Client.SendAsync($req).GetAwaiter().GetResult()
    return Convert-Response $resp
}

# Dispara várias requisições ao mesmo tempo e devolve as respostas na ordem.
function Send-Parallel([object[]]$Requests) {
    $tasks = @()
    foreach ($r in $Requests) { $tasks += $Client.SendAsync($r) }
    [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks)
    return @($tasks | ForEach-Object { Convert-Response $_.Result })
}

function Move-Body([int]$Position) { '{"posicao":' + $Position + '}' }

function Reset-Game([string]$BaseUrl = $null) {
    $r = Send 'POST' '/api/game/reset' $null 'application/json' $BaseUrl
    if ($r.Status -ne 200) { throw "POST /api/game/reset devolveu $($r.Status)" }
}

function Get-StateResponse([string]$BaseUrl = $null) { Send 'GET' '/api/game' $null 'application/json' $BaseUrl }

# ---------------------------------------------------------------------------
# Estado em texto (mesma notação do EngineCheck)
# ---------------------------------------------------------------------------
function Get-StateKey($Json) {
    if ($null -eq $Json -or $null -eq $Json.tabuleiro) { return '<sem estado JSON>' }
    $tab = (@($Json.tabuleiro) | ForEach-Object { if ($_ -eq '') { '.' } else { $_ } }) -join ''
    $vez = if ($Json.jogadorDaVez) { $Json.jogadorDaVez } else { '-' }
    $venc = if ($Json.vencedor) { $Json.vencedor } else { '-' }
    $cel = (@($Json.celulasVencedoras) -join ',')
    "tab=$tab status=$($Json.status) vez=$vez venc=$venc cel=[$cel]"
}

function Current-Key([string]$BaseUrl = $null) { Get-StateKey (Get-StateResponse $BaseUrl).Json }

$INITIAL_KEY = 'tab=......... status=EM_ANDAMENTO vez=X venc=- cel=[]'
$INITIAL_JSON = '{"tabuleiro":["","","","","","","","",""],"status":"EM_ANDAMENTO","jogadorDaVez":"X","vencedor":null,"celulasVencedoras":[]}'

$MSG = @{
    CORPO_INVALIDO       = 'O corpo da requisição deve ser um objeto JSON válido.'
    POSICAO_INVALIDA     = 'A posição deve ser um número inteiro de 0 a 8.'
    PARTIDA_ENCERRADA    = 'A partida já terminou. Clique em "Nova partida" para jogar novamente.'
    CELULA_OCUPADA       = 'Esta célula já está ocupada.'
    ROTA_NAO_ENCONTRADA  = 'Rota não encontrada.'
    METODO_NAO_PERMITIDO = 'Método não permitido para esta rota.'
}

# Verifica uma resposta de erro: status, código, mensagem exata, Content-Type.
function Test-Error($Resp, [int]$Status, [string]$Code, [string]$Label) {
    $p = @()
    if ($Resp.Status -ne $Status) { $p += "${Label}: status $($Resp.Status), esperado $Status" }
    if (-not $Resp.Utf8) { $p += "${Label}: corpo não é UTF-8 válido" }
    if ($Resp.ContentType -notmatch '^application/json' -or $Resp.ContentType -notmatch 'charset=utf-8') { $p += "${Label}: Content-Type '$($Resp.ContentType)'" }
    if ($null -eq $Resp.Json -or $null -eq $Resp.Json.erro) { $p += "${Label}: sem objeto erro (corpo: $($Resp.Text))"; return $p }
    if ($Resp.Json.erro.codigo -ne $Code) { $p += "${Label}: codigo '$($Resp.Json.erro.codigo)', esperado '$Code'" }
    if ($Resp.Json.erro.mensagem -cne $MSG[$Code]) { $p += "${Label}: mensagem '$($Resp.Json.erro.mensagem)'" }
    if (@($Resp.Json.PSObject.Properties.Name).Count -ne 1) { $p += "${Label}: o corpo de erro tem campos além de 'erro'" }
    return $p
}

# Joga a sequência e exige 200 em todas as jogadas.
function Invoke-Moves([int[]]$Moves, [string]$BaseUrl = $null) {
    $p = @()
    $i = 0
    foreach ($m in $Moves) {
        $i++
        $r = Send 'POST' '/api/game/moves' (Move-Body $m) 'application/json' $BaseUrl
        if ($r.Status -ne 200) { $p += "jogada $i (posição $m): status $($r.Status) $($r.Text)" }
    }
    return $p
}

# Faz a requisição e confere que o estado do jogo não mudou.
function Test-Unchanged([scriptblock]$Action, [string]$Label) {
    $before = Current-Key
    $resp = & $Action
    $after = Current-Key
    $p = @()
    if ($before -ne $after) { $p += "${Label}: estado mudou de '$before' para '$after'" }
    return ,@($resp, $p)
}

# Devolve '' se o estado é coerente com as regras, ou o motivo.
function Get-CoherenceProblem($Json) {
    if ($null -eq $Json -or $null -eq $Json.tabuleiro) { return 'sem estado' }
    $tab = @($Json.tabuleiro)
    if ($tab.Count -ne 9) { return "tabuleiro com $($tab.Count) células" }
    $xs = @($tab | Where-Object { $_ -eq 'X' }).Count
    $os = @($tab | Where-Object { $_ -eq 'O' }).Count
    $empty = @($tab | Where-Object { $_ -eq '' }).Count
    $cells = @($Json.celulasVencedoras)
    if (($xs - $os) -lt 0 -or ($xs - $os) -gt 1) { return "X=$xs O=$os" }
    switch ($Json.status) {
        'EM_ANDAMENTO' {
            $expected = if ($xs -eq $os) { 'X' } else { 'O' }
            if ($Json.jogadorDaVez -ne $expected) { return "vez $($Json.jogadorDaVez), esperado $expected" }
            if ($Json.vencedor -or $cells.Count) { return 'em andamento com vencedor' }
            if ($empty -eq 0) { return 'em andamento com tabuleiro cheio' }
        }
        'VITORIA' {
            if ($Json.jogadorDaVez) { return 'vitória com jogador da vez' }
            if (-not $Json.vencedor) { return 'vitória sem vencedor' }
            if ($cells.Count -ne 3 -and $cells.Count -ne 5) { return "vitória com $($cells.Count) células" }
            foreach ($c in $cells) { if ($tab[$c] -ne $Json.vencedor) { return 'célula vencedora sem o símbolo do vencedor' } }
        }
        'EMPATE' {
            if ($Json.jogadorDaVez -or $Json.vencedor -or $cells.Count) { return 'empate com vez/vencedor' }
            if ($empty -ne 0) { return 'empate com células vazias' }
        }
        default { return "status desconhecido '$($Json.status)'" }
    }
    return ''
}

# Leitura crua de um HEAD (o corpo precisa ter 0 bytes).
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
    } finally { $client.Close() }
}

function Wait-Health([string]$BaseUrl, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try { if ((Send 'GET' '/health' $null 'application/json' $BaseUrl).Status -eq 200) { return $true } } catch { }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Start-Server([string]$Exe, [int]$OnPort, [string]$Name) {
    $busy = Get-NetTCPConnection -LocalPort $OnPort -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw "A porta $OnPort já está em uso (processo $($busy[0].OwningProcess))." }
    $out = Join-Path $LogDir "$Name.out.log"
    $err = Join-Path $LogDir "$Name.err.log"
    Start-Process -FilePath $Exe -ArgumentList @('--port', "$OnPort") -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
}

function Stop-Server($Proc) {
    if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force; $Proc.WaitForExit(5000) | Out-Null }
}

# R-27: duas jogadas simultâneas na mesma célula, repetido N vezes.
function Test-SimultaneousSameCell([string]$BaseUrl, [int]$Repetitions) {
    $p = @()
    for ($i = 1; $i -le $Repetitions; $i++) {
        Reset-Game $BaseUrl
        $resps = Send-Parallel @((New-Request 'POST' '/api/game/moves' (Move-Body 0) 'application/json' $BaseUrl),
                                 (New-Request 'POST' '/api/game/moves' (Move-Body 0) 'application/json' $BaseUrl))
        $codes = (@($resps | ForEach-Object { $_.Status }) | Sort-Object) -join ','
        $conflict = @($resps | Where-Object { $_.Status -eq 409 })
        $final = Current-Key $BaseUrl
        if ($codes -ne '200,409') { $p += "repetição ${i}: status $codes" }
        elseif ($conflict[0].Json.erro.codigo -ne 'CELULA_OCUPADA') { $p += "repetição ${i}: 409 com código $($conflict[0].Json.erro.codigo)" }
        if ($final -ne 'tab=X........ status=EM_ANDAMENTO vez=O venc=- cel=[]') { $p += "repetição ${i}: estado final $final" }
    }
    return $p
}

# ---------------------------------------------------------------------------
# Sequências de referência (docs/test-plan.md, seção 5)
# ---------------------------------------------------------------------------
$Wins = @(
    @{ Id = 'R-09'; Name = 'linha 0-1-2';          Moves = @(0,3,1,4,2);         Board = 'XXXOO....'; Winner = 'X'; Cells = '0,1,2' },
    @{ Id = 'R-10'; Name = 'linha 3-4-5';          Moves = @(3,0,4,1,5);         Board = 'OO.XXX...'; Winner = 'X'; Cells = '3,4,5' },
    @{ Id = 'R-11'; Name = 'linha 6-7-8 (O)';      Moves = @(0,6,1,7,4,8);       Board = 'XX..X.OOO'; Winner = 'O'; Cells = '6,7,8' },
    @{ Id = 'R-12'; Name = 'coluna 0-3-6';         Moves = @(0,1,3,2,6);         Board = 'XOOX..X..'; Winner = 'X'; Cells = '0,3,6' },
    @{ Id = 'R-13'; Name = 'coluna 1-4-7 (O)';     Moves = @(0,1,3,4,8,7);       Board = 'XO.XO..OX'; Winner = 'O'; Cells = '1,4,7' },
    @{ Id = 'R-14'; Name = 'coluna 2-5-8';         Moves = @(2,0,5,1,8);         Board = 'OOX..X..X'; Winner = 'X'; Cells = '2,5,8' },
    @{ Id = 'R-15'; Name = 'diagonal 0-4-8';       Moves = @(0,1,4,2,8);         Board = 'XOO.X...X'; Winner = 'X'; Cells = '0,4,8' },
    @{ Id = 'R-16'; Name = 'diagonal 2-4-6';       Moves = @(2,0,4,1,6);         Board = 'OOX.X.X..'; Winner = 'X'; Cells = '2,4,6' },
    @{ Id = 'R-17'; Name = 'na 9ª jogada (2-5-8)'; Moves = @(0,1,2,4,5,3,7,6,8); Board = 'XOXOOXOXX'; Winner = 'X'; Cells = '2,5,8' },
    @{ Id = 'R-18'; Name = 'duas diagonais';       Moves = @(0,1,2,3,6,5,8,7,4); Board = 'XOXOXOXOX'; Winner = 'X'; Cells = '0,2,4,6,8' }
)
$SEQ_L1  = @(0,3,1,4,2)
$SEQ_EMP = @(0,1,2,4,3,5,7,6,8)
$KEY_L1  = 'tab=XXXOO.... status=VITORIA vez=- venc=X cel=[0,1,2]'
$KEY_EMP = 'tab=XOXXOOOXX status=EMPATE vez=- venc=- cel=[]'

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------
$server = $null
$sabServer = $null
$failed = 1
try {
    Write-Log ("===== Validação da Entrega 3 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: serviço, JSON e rotas ainda não implementados)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (build {1}); PowerShell {2}; .NET CLR {3}" -f $os.Caption, $os.BuildNumber, $PSVersionTable.PSVersion, $PSVersionTable.CLRVersion)

    # ---- Compilação ---------------------------------------------------------
    Write-Log "`n===== Compilação (scripts\build.cmd)"
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $build = & cmd.exe /c "`"$(Join-Path $Root 'scripts\build.cmd')`"" 2>&1 | Out-String
    $buildCode = $LASTEXITCODE
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $hints    = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$') | ForEach-Object { $_.Value.Trim() })
    Add-Check 'B-01' 'Compilação do servidor e do EngineCheck sem erros' ($buildCode -eq 0) "Código: $buildCode"
    Add-Check 'B-02' 'Compilador é o Delphi 10.1 Berlin (compiler version 31.0)' ($build -match 'compiler version 31\.0') ''
    Add-Check 'B-03' 'Nenhum warning do compilador' ($warnings.Count -eq 0) ("Warnings: {0}; hints: {1}" -f $warnings.Count, $hints.Count)
    foreach ($w in ($warnings + $hints)) { Write-Log "         $w" }
    if (-not (Test-Path $ServerExe) -or -not (Test-Path $EngineExe)) { throw 'Executáveis não foram gerados.' }

    # ---- Independência ------------------------------------------------------
    $engineSrc  = Get-Content (Join-Path $ServerDir 'src\uGameEngine.pas') -Raw -Encoding UTF8
    $serviceSrc = Get-Content (Join-Path $ServerDir 'src\uGameService.pas') -Raw -Encoding UTF8
    $jsonSrc    = Get-Content (Join-Path $ServerDir 'src\uGameJson.pas') -Raw -Encoding UTF8
    $usesOf = { param($src) (([regex]::Matches($src, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',') -split ',' | ForEach-Object { ($_ -replace '\{.*?\}', '').Trim() } | Where-Object { $_ } }
    $indyIn = @((& $usesOf $engineSrc) + (& $usesOf $serviceSrc) + (& $usesOf $jsonSrc) | Where-Object { $_ -match '^(Id\w+|uHttpApp|Vcl\..*|FMX\..*)$' })
    Add-Check 'I-01' 'Motor, serviço e JSON não dependem do Indy nem da interface' ($indyIn.Count -eq 0) ("Encontradas: " + ($indyIn -join ', '))

    # ---- EngineCheck --------------------------------------------------------
    Write-Log "`n===== EngineCheck.exe (motor, serviço e JSON, sem HTTP)"
    $engineOut = & $EngineExe 2>&1 | Out-String
    $engineCode = $LASTEXITCODE
    Write-Log $engineOut.TrimEnd()
    Write-Log "Código de saída do EngineCheck: $engineCode"
    $failIds = @([regex]::Matches($engineOut, '(?m)^\[FALHOU\]\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
    $okIds   = @([regex]::Matches($engineOut, '(?m)^\[OK\]\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
    $newCases = @('SV-01','SV-02','SV-03','J-01','J-02','J-03','J-04','J-05')
    $mFailed = @($failIds | Where-Object { $_ -like 'M-*' })
    Add-Check 'E-01' 'Casos do motor (M) continuam aprovados (regressão da Entrega 2)' (($mFailed.Count -eq 0) -and (@($okIds | Where-Object { $_ -like 'M-*' }).Count -eq 19)) ("M que falharam: " + ($mFailed -join ', '))
    $newOk = @($newCases | Where-Object { $okIds -contains $_ })
    Add-Check 'E-02' 'Casos novos de serviço (SV) e JSON (J) aprovados' ($newOk.Count -eq $newCases.Count) ("Aprovados: {0}/{1}; falharam: {2}" -f $newOk.Count, $newCases.Count, (@($failIds | Where-Object { $_ -notlike 'M-*' }) -join ', '))

    # ---- Servidor real ------------------------------------------------------
    Write-Log "`n===== Servidor real em $script:Base"
    $server = Start-Server $ServerExe $Port 'server-step3'
    $up = Wait-Health $script:Base 10
    Add-Check 'S-01' 'Servidor iniciou e /health respondeu' $up ("PID " + $server.Id)
    if (-not $up) { throw 'Servidor não respondeu.' }

    Write-Log "`n----- Grupo A: endpoints"
    Test-Case 'A-01' 'GET /api/game: 200, cabeçalhos e JSON exato do estado inicial' {
        Reset-Game
        $r = Get-StateResponse
        if ($r.Status -ne 200) { "status $($r.Status)" }
        if ($r.ContentType -notmatch '^application/json' -or $r.ContentType -notmatch 'charset=utf-8') { "Content-Type '$($r.ContentType)'" }
        if ($r.CacheControl -notmatch 'no-store') { "Cache-Control '$($r.CacheControl)'" }
        if ($r.Text -cne $INITIAL_JSON) { "corpo '$($r.Text)'" }
    }
    Test-Case 'A-02' 'POST /api/game/reset com e sem corpo devolve o estado inicial' {
        $null = Invoke-Moves @(0,4)
        $r1 = Send 'POST' '/api/game/reset'
        if ($r1.Status -ne 200 -or $r1.Text -cne $INITIAL_JSON) { "sem corpo: $($r1.Status) $($r1.Text)" }
        $null = Invoke-Moves @(0)
        $r2 = Send 'POST' '/api/game/reset' '{"qualquer":1}'
        if ($r2.Status -ne 200 -or $r2.Text -cne $INITIAL_JSON) { "com corpo: $($r2.Status) $($r2.Text)" }
    }
    Test-Case 'A-03' 'Resposta da jogada é igual ao estado consultado depois' {
        Reset-Game
        $m = Send 'POST' '/api/game/moves' (Move-Body 4)
        $g = Get-StateResponse
        if ($m.Status -ne 200) { "status da jogada $($m.Status)" }
        if ($m.Text -cne $g.Text) { "jogada '$($m.Text)' x GET '$($g.Text)'" }
        if ($m.CacheControl -notmatch 'no-store') { "Cache-Control da jogada '$($m.CacheControl)'" }
    }
    Test-Case 'A-04' 'Posições inválidas: 400 POSICAO_INVALIDA e estado inalterado' {
        Reset-Game; $null = Invoke-Moves @(0)
        foreach ($body in @('{"posicao":9}','{"posicao":-1}','{"posicao":4.5}','{"posicao":0.5}','{"posicao":"4"}','{"posicao":null}','{"posicao":true}','{}','{"Posicao":4}','{"posicao":99999999999}')) {
            $res = Test-Unchanged { Send 'POST' '/api/game/moves' $body } $body
            Test-Error $res[0] 400 'POSICAO_INVALIDA' $body
            $res[1]
        }
    }
    Test-Case 'A-05' 'Corpos inválidos: 400 CORPO_INVALIDO e estado inalterado' {
        Reset-Game; $null = Invoke-Moves @(0)
        $badUtf8 = [System.Text.Encoding]::ASCII.GetBytes('{"posicao":4,"x":"__"}'); $badUtf8[18] = 0xFF; $badUtf8[19] = 0xFE
        $cases = @(
            @{ Label = 'sem corpo';  Body = $null },
            @{ Label = 'corpo vazio'; Body = [byte[]]@() },
            @{ Label = 'abc'; Body = 'abc' },
            @{ Label = 'JSON incompleto'; Body = '{"posicao":' },
            @{ Label = '[4]'; Body = '[4]' },
            @{ Label = '4'; Body = '4' },
            @{ Label = '"x"'; Body = '"x"' },
            @{ Label = 'UTF-8 inválido'; Body = $badUtf8 }
        )
        foreach ($c in $cases) {
            $res = Test-Unchanged { Send 'POST' '/api/game/moves' $c.Body } $c.Label
            Test-Error $res[0] 400 'CORPO_INVALIDO' $c.Label
            $res[1]
        }
    }
    Test-Case 'A-06' 'Content-Type text/plain é aceito; 4.0 e 1e0 valem como inteiros' {
        Reset-Game
        $r = Send 'POST' '/api/game/moves' (Move-Body 4) 'text/plain'
        if ($r.Status -ne 200) { "text/plain: status $($r.Status) $($r.Text)" }
        if ((Get-StateKey $r.Json) -ne 'tab=....X.... status=EM_ANDAMENTO vez=O venc=- cel=[]') { "text/plain: estado $(Get-StateKey $r.Json)" }
        Reset-Game
        $r = Send 'POST' '/api/game/moves' '{"posicao":4.0}'
        if ($r.Status -ne 200 -or @($r.Json.tabuleiro)[4] -ne 'X') { "4.0: status $($r.Status) $($r.Text)" }
        $r = Send 'POST' '/api/game/moves' '{"posicao":1e0}'
        if ($r.Status -ne 200 -or @($r.Json.tabuleiro)[1] -ne 'O') { "1e0: status $($r.Status) $($r.Text)" }
    }
    Test-Case 'A-07' 'Mensagens com acentos chegam em UTF-8 válido (CELULA_OCUPADA, PARTIDA_ENCERRADA)' {
        Reset-Game; $null = Invoke-Moves @(0)
        Test-Error (Send 'POST' '/api/game/moves' (Move-Body 0)) 409 'CELULA_OCUPADA' 'célula ocupada'
        Reset-Game; $null = Invoke-Moves $SEQ_L1
        Test-Error (Send 'POST' '/api/game/moves' (Move-Body 5)) 409 'PARTIDA_ENCERRADA' 'partida encerrada'
    }
    Test-Case 'A-08' 'Rotas inexistentes: 404 ROTA_NAO_ENCONTRADA e estado inalterado' {
        Reset-Game; $null = Invoke-Moves @(0)
        foreach ($rq in @(@('GET','/api/inexistente'), @('POST','/api/game/movimento'), @('GET','/api/game/'), @('GET','/qualquer'))) {
            # O HttpClient do .NET Framework não envia corpo em GET.
            $res = Test-Unchanged { Send $rq[0] $rq[1] $(if ($rq[0] -eq 'GET') { $null } else { '{"posicao":1}' }) } "$($rq[0]) $($rq[1])"
            Test-Error $res[0] 404 'ROTA_NAO_ENCONTRADA' "$($rq[0]) $($rq[1])"
            $res[1]
        }
    }
    Test-Case 'A-09' 'Métodos não permitidos: 405 com Allow e estado inalterado' {
        Reset-Game; $null = Invoke-Moves @(0)
        foreach ($rq in @(@('POST','/api/game','GET, HEAD'), @('DELETE','/api/game','GET, HEAD'), @('GET','/api/game/moves','POST'), @('PUT','/api/game/moves','POST'), @('GET','/api/game/reset','POST'), @('DELETE','/api/game/reset','POST'), @('POST','/health','GET, HEAD'))) {
            $res = Test-Unchanged { Send $rq[0] $rq[1] $(if ($rq[0] -eq 'GET') { $null } else { Move-Body 1 }) } "$($rq[0]) $($rq[1])"
            Test-Error $res[0] 405 'METODO_NAO_PERMITIDO' "$($rq[0]) $($rq[1])"
            if ($res[0].Allow -ne $rq[2]) { "$($rq[0]) $($rq[1]): Allow '$($res[0].Allow)', esperado '$($rq[2])'" }
            $res[1]
        }
    }
    Test-Case 'A-11' 'HEAD /api/game: 200 sem corpo' {
        $h = Invoke-RawHead '/api/game'
        if ($h.Headers -notmatch '^HTTP/1\.1 200') { "status: $(($h.Headers -split "`r`n")[0])" }
        if ($h.BodyLength -ne 0) { "corpo com $($h.BodyLength) bytes" }
        if ($h.Headers -notmatch '(?im)^Content-Type: application/json; charset=utf-8') { 'Content-Type ausente ou diferente' }
    }
    Test-Case 'A-12' 'GET /health continua 200 {"status":"ok"} e não altera a partida' {
        Reset-Game; $null = Invoke-Moves @(0)
        $res = Test-Unchanged { Send 'GET' '/health' } 'GET /health'
        if ($res[0].Status -ne 200 -or $res[0].Text -cne '{"status":"ok"}') { "GET /health: $($res[0].Status) $($res[0].Text)" }
        $res[1]
        $h = Invoke-RawHead '/health'
        if ($h.Headers -notmatch '^HTTP/1\.1 200' -or $h.BodyLength -ne 0) { "HEAD /health: corpo $($h.BodyLength) bytes" }
    }

    Write-Log "`n----- Grupo R: regras de negócio pela API"
    Test-Case 'R-01' 'Estado inicial de uma partida' {
        Reset-Game
        $k = Current-Key; if ($k -ne $INITIAL_KEY) { "estado $k" }
    }
    Test-Case 'R-02' 'Primeira jogada é de X e passa a vez para O' {
        Reset-Game
        $r = Send 'POST' '/api/game/moves' (Move-Body 0)
        if ($r.Status -ne 200) { "status $($r.Status)" }
        if ((Get-StateKey $r.Json) -ne 'tab=X........ status=EM_ANDAMENTO vez=O venc=- cel=[]') { "estado $(Get-StateKey $r.Json)" }
    }
    Test-Case 'R-03' 'Segunda jogada é de O e devolve a vez para X' {
        Reset-Game; $null = Invoke-Moves @(0)
        $r = Send 'POST' '/api/game/moves' (Move-Body 4)
        if ((Get-StateKey $r.Json) -ne 'tab=X...O.... status=EM_ANDAMENTO vez=X venc=- cel=[]') { "estado $(Get-StateKey $r.Json)" }
    }
    Test-Case 'R-04' 'Alternância ao longo de 8 jogadas' {
        Reset-Game
        $moves = @(0,1,2,4,3,5,7,6)
        for ($i = 0; $i -lt $moves.Count; $i++) {
            $sym = if ($i % 2 -eq 0) { 'X' } else { 'O' }
            $next = if ($sym -eq 'X') { 'O' } else { 'X' }
            $r = Send 'POST' '/api/game/moves' (Move-Body $moves[$i])
            if ($r.Status -ne 200) { "jogada $($i+1): status $($r.Status)"; continue }
            if (@($r.Json.tabuleiro)[$moves[$i]] -ne $sym) { "jogada $($i+1): célula $($moves[$i]) com '$(@($r.Json.tabuleiro)[$moves[$i]])', esperado $sym" }
            if ($r.Json.jogadorDaVez -ne $next) { "jogada $($i+1): vez $($r.Json.jogadorDaVez), esperado $next" }
            if ($r.Json.status -ne 'EM_ANDAMENTO') { "jogada $($i+1): status $($r.Json.status)" }
        }
    }
    Test-Case 'R-05' 'O cliente não escolhe o símbolo (campos extras ignorados)' {
        Reset-Game
        $r = Send 'POST' '/api/game/moves' '{"posicao":0,"simbolo":"O","jogador":"O"}'
        if ($r.Status -ne 200) { "status $($r.Status)" }
        if ((Get-StateKey $r.Json) -ne 'tab=X........ status=EM_ANDAMENTO vez=O venc=- cel=[]') { "estado $(Get-StateKey $r.Json)" }
    }
    Test-Case 'R-06' 'Jogada na célula do adversário: 409 CELULA_OCUPADA, estado inalterado' {
        Reset-Game; $null = Invoke-Moves @(0)
        $res = Test-Unchanged { Send 'POST' '/api/game/moves' (Move-Body 0) } 'O em 0'
        Test-Error $res[0] 409 'CELULA_OCUPADA' 'O em 0'
        $res[1]
    }
    Test-Case 'R-07' 'Jogada na própria célula também é recusada' {
        Reset-Game; $null = Invoke-Moves @(0,4)
        $res = Test-Unchanged { Send 'POST' '/api/game/moves' (Move-Body 0) } 'X em 0'
        Test-Error $res[0] 409 'CELULA_OCUPADA' 'X em 0'
        $res[1]
        if ((Current-Key) -notmatch 'vez=X') { 'a vez deveria continuar de X' }
    }
    Test-Case 'R-08' 'Após uma recusa, a partida segue normalmente' {
        Reset-Game; $null = Invoke-Moves @(0)
        $null = Send 'POST' '/api/game/moves' (Move-Body 0)
        $r = Send 'POST' '/api/game/moves' (Move-Body 4)
        if ($r.Status -ne 200 -or (Get-StateKey $r.Json) -ne 'tab=X...O.... status=EM_ANDAMENTO vez=X venc=- cel=[]') { "status $($r.Status), estado $(Get-StateKey $r.Json)" }
    }
    foreach ($w in $Wins) {
        Test-Case $w.Id ("Vitória: " + $w.Name) {
            Reset-Game
            $all = $w.Moves
            $before = @($all[0..($all.Count - 2)])
            Invoke-Moves $before
            $mid = Current-Key
            if ($mid -notmatch 'status=EM_ANDAMENTO') { "a partida terminou antes da última jogada: $mid" }
            $r = Send 'POST' '/api/game/moves' (Move-Body $all[-1])
            $expected = "tab=$($w.Board) status=VITORIA vez=- venc=$($w.Winner) cel=[$($w.Cells)]"
            if ($r.Status -ne 200) { "última jogada: status $($r.Status)" }
            if ((Get-StateKey $r.Json) -ne $expected) { "esperado $expected, obtido $(Get-StateKey $r.Json)" }
            if ((Current-Key) -ne $expected) { "GET depois: $(Current-Key)" }
        }
    }
    Test-Case 'R-19' 'Empate com tabuleiro cheio sem combinação' {
        Reset-Game
        Invoke-Moves @($SEQ_EMP[0..7])
        if ((Current-Key) -notmatch 'status=EM_ANDAMENTO') { 'terminou antes da 9ª jogada' }
        $r = Send 'POST' '/api/game/moves' (Move-Body 8)
        if ($r.Status -ne 200 -or (Get-StateKey $r.Json) -ne $KEY_EMP) { "status $($r.Status), estado $(Get-StateKey $r.Json)" }
    }
    Test-Case 'R-20' 'Nenhuma célula aceita jogada após vitória (409 PARTIDA_ENCERRADA)' {
        Reset-Game; Invoke-Moves $SEQ_L1
        foreach ($pos in @(5,6,7,8,0)) {
            $res = Test-Unchanged { Send 'POST' '/api/game/moves' (Move-Body $pos) } "posição $pos"
            Test-Error $res[0] 409 'PARTIDA_ENCERRADA' "posição $pos"
            $res[1]
        }
        if ((Current-Key) -ne $KEY_L1) { "estado final $(Current-Key)" }
    }
    Test-Case 'R-21' 'Após empate, a resposta é PARTIDA_ENCERRADA (não CELULA_OCUPADA)' {
        Reset-Game; Invoke-Moves $SEQ_EMP
        $res = Test-Unchanged { Send 'POST' '/api/game/moves' (Move-Body 4) } 'posição 4'
        Test-Error $res[0] 409 'PARTIDA_ENCERRADA' 'posição 4'
        $res[1]
    }
    Test-Case 'R-22' 'Posição inválida tem precedência sobre partida encerrada' {
        Reset-Game; Invoke-Moves $SEQ_L1
        $res = Test-Unchanged { Send 'POST' '/api/game/moves' (Move-Body 9) } 'posição 9'
        Test-Error $res[0] 400 'POSICAO_INVALIDA' 'posição 9'
        $res[1]
    }
    Test-Case 'R-23' 'Reiniciar após vitória' {
        Reset-Game; Invoke-Moves $SEQ_L1
        $r = Send 'POST' '/api/game/reset'
        if ($r.Text -cne $INITIAL_JSON) { "reset: $($r.Text)" }
        if ((Current-Key) -ne $INITIAL_KEY) { "GET depois: $(Current-Key)" }
    }
    Test-Case 'R-24' 'Reiniciar após empate' {
        Reset-Game; Invoke-Moves $SEQ_EMP
        $r = Send 'POST' '/api/game/reset'
        if ($r.Text -cne $INITIAL_JSON) { "reset: $($r.Text)" }
    }
    Test-Case 'R-25' 'Reiniciar no meio da partida' {
        Reset-Game; Invoke-Moves @(0,4)
        $r = Send 'POST' '/api/game/reset'
        if ($r.Text -cne $INITIAL_JSON) { "reset: $($r.Text)" }
    }
    Test-Case 'R-26' 'Partida nova é jogável desde o início (inclusive células antes ocupadas)' {
        Reset-Game; Invoke-Moves $SEQ_L1
        Reset-Game
        $r = Send 'POST' '/api/game/moves' (Move-Body 0)
        if ($r.Status -ne 200 -or (Get-StateKey $r.Json) -ne 'tab=X........ status=EM_ANDAMENTO vez=O venc=- cel=[]') { "status $($r.Status), estado $(Get-StateKey $r.Json)" }
    }
    Test-Case 'R-27' 'Duas jogadas simultâneas na mesma célula (20 repetições)' {
        Test-SimultaneousSameCell $script:Base 20
    }
    Test-Case 'R-28' 'Rajada de 18 jogadas simultâneas mantém o estado coerente (10 repetições)' {
        for ($i = 1; $i -le 10; $i++) {
            Reset-Game
            $reqs = @()
            foreach ($pos in (0..8 + 0..8)) { $reqs += (New-Request 'POST' '/api/game/moves' (Move-Body $pos) 'application/json' $null) }
            $resps = Send-Parallel $reqs
            $state = (Get-StateResponse).Json
            $ok = @($resps | Where-Object { $_.Status -eq 200 }).Count
            $bad = @($resps | Where-Object { $_.Status -ne 200 -and -not ($_.Status -eq 409 -and @('CELULA_OCUPADA','PARTIDA_ENCERRADA') -contains $_.Json.erro.codigo) })
            if ($bad.Count) { "repetição ${i}: respostas inesperadas: " + ((@($bad | ForEach-Object { "$($_.Status) $($_.Text)" }) | Select-Object -First 2) -join '; ') }
            $filled = @(@($state.tabuleiro) | Where-Object { $_ -ne '' }).Count
            if ($ok -ne $filled) { "repetição ${i}: $ok respostas 200 e $filled células preenchidas" }
            $problem = Get-CoherenceProblem $state
            if ($problem) { "repetição ${i}: estado final incoerente ($problem): $(Get-StateKey $state)" }
            for ($k = 0; $k -lt $resps.Count; $k++) {
                if ($resps[$k].Status -eq 200) {
                    $pos = $k % 9
                    if (@($resps[$k].Json.tabuleiro)[$pos] -eq '') { "repetição ${i}: resposta 200 para a posição $pos com a célula vazia" }
                    $pp = Get-CoherenceProblem $resps[$k].Json
                    if ($pp) { "repetição ${i}: resposta 200 incoerente ($pp)" }
                }
            }
        }
    }
    Stop-Server $server
    $server = $null

    # ---- Sabotagem SB-04 ----------------------------------------------------
    if (-not $RedPhase) {
        Write-Log "`n===== Sabotagem SB-04: servidor sem trava e com atraso de 50 ms entre verificar e gravar"
        $dir = Join-Path $LogDir 'sabotage\SB-04'
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
        $writeLine = "  FBoard[APosition] := FCurrentPlayer;"
        $writes = ([regex]::Matches($eng, [regex]::Escape($writeLine))).Count
        $eng = $eng.Replace($writeLine, "  Sleep(50);   { sabotagem: atraso entre verificar e gravar }`r`n" + $writeLine)
        $eng = ([regex]'(?m)^implementation\r?$').Replace($eng, "implementation`r`n`r`nuses`r`n  Winapi.Windows;", 1)
        [System.IO.File]::WriteAllText($svcPath, $svc, (New-Object System.Text.UTF8Encoding($true)))
        [System.IO.File]::WriteAllText($engPath, $eng, (New-Object System.Text.UTF8Encoding($true)))
        Write-Log "Trechos alterados: $locks chamadas à trava removidas; $writes ponto(s) de gravação com atraso."
        if ($locks -lt 2 -or $writes -ne 1) {
            Add-Check 'SB-04' 'Sabotagem aplicada' $false "Esperado: >= 2 chamadas à trava e 1 ponto de gravação."
        } else {
            $c = & cmd.exe /c "`"$Compile`" `"$dir`" TicTacToeServer.dpr" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                Write-Log $c.TrimEnd()
                Add-Check 'SB-04' 'Cópia sabotada compila' $false "Código do dcc32: $LASTEXITCODE"
            } else {
                $sabBase = 'http://127.0.0.1:8766'
                $sabServer = Start-Server (Join-Path $dir 'bin\TicTacToeServer.exe') 8766 'server-step3-SB-04'
                if (-not (Wait-Health $sabBase 10)) {
                    Add-Check 'SB-04' 'Servidor sabotado iniciou' $false ''
                } else {
                    $sabProblems = @(Test-SimultaneousSameCell $sabBase 20)
                    Write-Log ("R-27 contra o servidor sabotado: {0} problema(s). Exemplos: {1}" -f $sabProblems.Count, (($sabProblems | Select-Object -First 3) -join ' | '))
                    Add-Check 'SB-04' 'Sem a trava, o R-27 detecta jogadas simultâneas incompatíveis' ($sabProblems.Count -gt 0) ''
                }
                Stop-Server $sabServer
                $sabServer = $null
            }
        }
    }

    Write-Log "`n===== Saída do servidor (log de requisições, últimas 15 linhas)"
    $srvLog = Join-Path $LogDir 'server-step3.out.log'
    if (Test-Path $srvLog) { Write-Log ((Get-Content $srvLog -Encoding UTF8 | Select-Object -Last 15) -join "`r`n") }
    $srvErr = Join-Path $LogDir 'server-step3.err.log'
    if ((Test-Path $srvErr) -and (Get-Item $srvErr).Length -gt 0) { Write-Log ("Erros do servidor:`r`n" + (Get-Content $srvErr -Raw)) }
    $errLines = @(Get-Content $srvLog -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '-> 500|ERRO em' })
    Add-Check 'S-02' 'Nenhum erro interno (500) registrado pelo servidor' ($errLines.Count -eq 0) (($errLines | Select-Object -First 3) -join ' | ')
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    Stop-Server $server
    Stop-Server $sabServer
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-6} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    if ($RedPhase) {
        Write-Log "Fase vermelha: as falhas acima são esperadas para o que ainda não foi implementado."
    }
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
