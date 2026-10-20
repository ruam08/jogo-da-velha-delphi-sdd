unit uLimitTests;

(* Casos RL-01 a RL-05 e OP-03 (Entrega O6; docs/test-plan-online.md,
  seção 5): limites por cliente, corpo com teto, cliente por trás de proxy,
  classificação das taxas e opções novas. Sem rede; relógio manual onde há
  tempo. *)

interface

procedure RunLimitTests;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, uMiniTest, uClock, uRateLimiter,
  uRequestLimits, uServerOptions;

procedure RL01_RateLimiter;
var
  Clock: TManualClock;
  ClockRef: IClock;
  L, Off, Small: TRateLimiter;
  D: TRateDecision;
  I: Integer;
begin
  Clock := TManualClock.Create(1000);
  ClockRef := Clock;
  L := TRateLimiter.Create(ClockRef, 3, 60000);
  Off := TRateLimiter.Create(ClockRef, 0, 60000);
  Small := TRateLimiter.Create(ClockRef, 1, 10000, 2);
  try
    { Abaixo e no limite. }
    for I := 1 to 3 do
    begin
      D := L.Hit('10.0.0.1');
      Check(D.Allowed, Format('tentativa %d de 3: aceita', [I]));
      CheckEqualsInt(I, D.Count, Format('contagem da tentativa %d', [I]));
    end;
    { Acima: recusada, com o tempo que falta para a janela acabar. }
    D := L.Hit('10.0.0.1');
    Check(not D.Allowed, '4a tentativa recusada');
    CheckEqualsInt(60, D.RetryAfterSeconds, 'Retry-After no início da janela');
    Clock.Advance(30500);
    D := L.Hit('10.0.0.1');
    Check(not D.Allowed, 'ainda recusada no meio da janela');
    CheckEqualsInt(30, D.RetryAfterSeconds, 'Retry-After arredondado para cima (29,5 s -> 30)');
    { Outro cliente não é afetado. }
    D := L.Hit('10.0.0.2');
    Check(D.Allowed, 'outro cliente aceito');
    CheckEqualsInt(1, D.Count, 'outro cliente começa do zero');
    { A janela reabre exatamente no fim. }
    Clock.Advance(29499);
    D := L.Hit('10.0.0.1');
    Check(not D.Allowed, '1 ms antes do fim da janela: recusada');
    CheckEqualsInt(1, D.RetryAfterSeconds, 'Retry-After mínimo de 1 s');
    Clock.Advance(1);
    D := L.Hit('10.0.0.1');
    Check(D.Allowed, 'no fim da janela: aceita de novo');
    CheckEqualsInt(1, D.Count, 'janela nova');
    { Limite 0: sem limite e nada guardado. }
    for I := 1 to 1000 do
      Check(Off.Hit('x').Allowed, 'limite 0 nunca recusa');
    CheckEqualsInt(0, Off.KeyCount, 'limite 0 não guarda clientes');
    Check(not Off.Enabled, 'limite 0 desligado');
    { Teto de clientes em memória (B15). }
    Check(Small.Hit('a').Allowed, 'a: aceita');
    Check(Small.Hit('b').Allowed, 'b: aceita');
    D := Small.Hit('c');
    Check(not D.Allowed, 'c: sem espaço para um terceiro cliente, recusada');
    CheckEqualsInt(10, D.RetryAfterSeconds, 'c: Retry-After = janela');
    CheckEqualsInt(2, Small.KeyCount, 'c não foi guardado');
    Clock.Advance(10000);
    Check(Small.Hit('c').Allowed, 'c: aceita depois que as janelas vencem');
    CheckEqualsInt(1, Small.KeyCount, 'janelas vencidas descartadas');
  finally
    Small.Free;
    Off.Free;
    L.Free;
  end;
end;

type
  TCounterWorker = class(TThread)
  private
    FCounter: TConnectionCounter;
    FKey: string;
    FHeld: PInteger;
    FMaxSeen: PInteger;
    FDenied: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(ACounter: TConnectionCounter; const AKey: string; AHeld, AMaxSeen: PInteger);
    property Denied: Integer read FDenied;
  end;

constructor TCounterWorker.Create(ACounter: TConnectionCounter; const AKey: string; AHeld, AMaxSeen: PInteger);
begin
  FCounter := ACounter;
  FKey := AKey;
  FHeld := AHeld;
  FMaxSeen := AMaxSeen;
  inherited Create(True);
end;

procedure TCounterWorker.Execute;
var
  I, Cur: Integer;
begin
  for I := 1 to 5000 do
    if FCounter.TryAcquire(FKey) then
    begin
      Cur := TInterlocked.Increment(FHeld^);
      if Cur > TInterlocked.CompareExchange(FMaxSeen^, 0, 0) then
        TInterlocked.Exchange(FMaxSeen^, Cur);
      TInterlocked.Decrement(FHeld^);
      FCounter.Release(FKey);
    end
    else
      Inc(FDenied);
end;

procedure RL02_ConnectionCounter;
const
  N = 8;
var
  C, Off: TConnectionCounter;
  Workers: array[0..N - 1] of TCounterWorker;
  Held, MaxSeen, I, Denied: Integer;
begin
  C := TConnectionCounter.Create(2);
  Off := TConnectionCounter.Create(0);
  try
    Check(C.TryAcquire('a'), '1o canal de a');
    Check(C.TryAcquire('a'), '2o canal de a (no limite)');
    Check(not C.TryAcquire('a'), '3o canal de a recusado (acima)');
    Check(C.TryAcquire('b'), 'outro cliente não é afetado');
    C.Release('a');
    CheckEqualsInt(1, C.CountOf('a'), 'a com 1 depois de soltar um');
    Check(C.TryAcquire('a'), 'a volta a abrir depois de soltar');
    C.Release('a');
    C.Release('a');
    C.Release('a');
    CheckEqualsInt(0, C.CountOf('a'), 'soltar a mais não fica negativo');
    C.Release('b');
    CheckEqualsInt(0, C.KeyCount, 'nada sobra depois de soltar tudo');
    for I := 1 to 100 do
      Check(Off.TryAcquire('x'), 'limite 0 nunca recusa');
    CheckEqualsInt(0, Off.KeyCount, 'limite 0 não guarda clientes');
  finally
    Off.Free;
    C.Free;
  end;
  { 8 threads disputando o mesmo cliente com limite 3. }
  C := TConnectionCounter.Create(3);
  try
    Held := 0;
    MaxSeen := 0;
    for I := 0 to N - 1 do
      Workers[I] := TCounterWorker.Create(C, 'mesmo', @Held, @MaxSeen);
    for I := 0 to N - 1 do
      Workers[I].Start;
    Denied := 0;
    for I := 0 to N - 1 do
    begin
      Workers[I].WaitFor;
      Inc(Denied, Workers[I].Denied);
      Workers[I].Free;
    end;
    Check(MaxSeen <= 3, Format('nunca mais de 3 ao mesmo tempo (visto: %d)', [MaxSeen]));
    CheckEqualsInt(0, C.CountOf('mesmo'), 'contagem volta a zero');
    CheckEqualsInt(0, C.KeyCount, 'nenhum cliente sobra');
    Note(Format('8 threads x 5000 tentativas, limite 3: máximo simultâneo %d, recusas %d', [MaxSeen, Denied]));
  finally
    C.Free;
  end;
end;

procedure RL03_CappedStream;
var
  S: TCappedStream;
  B: TBytes;
  Buf: array[0..15] of Byte;
  N: Integer;
begin
  S := TCappedStream.Create(8);
  try
    { O Indy anota o tamanho declarado antes de ler: nada é alocado. }
    S.Size := Int64(1) shl 40;
    CheckEqualsInt(0, Integer(S.Size), 'Size continua 0 depois de anotar 1 TB');
    Check(S.Declared = Int64(1) shl 40, 'tamanho declarado anotado');
    B := TEncoding.ASCII.GetBytes('abcde');
    CheckEqualsInt(5, S.Write(B[0], 5), 'escreve 5');
    Check(not S.Overflowed, '5 de 8: sem estouro');
    B := TEncoding.ASCII.GetBytes('fghijklmno');
    CheckEqualsInt(10, S.Write(B[0], 10), 'aceita 10 (descarta o excedente)');
    Check(S.Overflowed, '15 de 8: estourou');
    Check(S.Total = 15, 'total recebido 15');
    CheckEqualsInt(8, Integer(S.Size), 'guardados 8');
    CheckEqualsStr('abcdefgh', TEncoding.ASCII.GetString(S.StoredBytes), 'bytes guardados');
    S.Position := 0;
    N := S.Read(Buf[0], 16);
    CheckEqualsInt(8, N, 'leitura devolve só o guardado');
    S.Position := 6;
    N := S.Read(Buf[0], 16);
    CheckEqualsInt(2, N, 'leitura a partir da posição 6');
    S.Position := 100;
    CheckEqualsInt(8, Integer(S.Position), 'posição limitada ao guardado');
  finally
    S.Free;
  end;
  S := TCappedStream.Create(MAX_REQUEST_BODY_BYTES);
  try
    SetLength(B, 1024);
    for N := 1 to 1000 do
      S.Write(B[0], Length(B));
    Check(S.Total = 1024000, 'recebeu 1.000 KB');
    CheckEqualsInt(MAX_REQUEST_BODY_BYTES, Integer(S.Size), 'guardou só 64 KB');
  finally
    S.Free;
  end;
end;

procedure RL04_MessageWindow;
var
  W, Off: TMessageWindow;
  I: Integer;
begin
  W.Init(3, 10000);
  Check(W.Hit(1000), '1a mensagem');
  Check(W.Hit(1001), '2a mensagem');
  Check(W.Hit(1002), '3a mensagem (no limite)');
  Check(not W.Hit(1003), '4a mensagem recusada (acima)');
  Check(not W.Hit(10999), 'ainda na janela: recusada');
  Check(W.Hit(11003), 'janela nova: aceita');
  Off.Init(0);
  for I := 1 to 10000 do
    Check(Off.Hit(I), 'limite 0 nunca recusa');
end;

procedure RL05_ClientAndKinds;
begin
  { Cliente (B8). }
  CheckEqualsStr('10.0.0.9', ClientKey('10.0.0.9', ['1.2.3.4'], True), 'X-Forwarded-For ignorado fora do loopback');
  CheckEqualsStr('127.0.0.1', ClientKey('127.0.0.1', ['1.2.3.4'], False), 'X-Forwarded-For ignorado sem --trust-proxy');
  CheckEqualsStr('1.2.3.4', ClientKey('127.0.0.1', ['9.9.9.9, 1.2.3.4'], True), 'último da lista (o do proxy)');
  CheckEqualsStr('1.2.3.4', ClientKey('127.0.0.1', ['9.9.9.9', '1.2.3.4'], True), 'dois cabeçalhos: o último');
  CheckEqualsStr('1.2.3.4', ClientKey('127.0.0.1', ['1.2.3.4, '], True), 'vazio no fim é ignorado');
  CheckEqualsStr('127.0.0.1', ClientKey('127.0.0.1', ['1.2.3.4, x'], True), 'último inválido: o IP da conexão');
  CheckEqualsStr('127.0.0.1', ClientKey('127.0.0.1', ['001.2.3.4'], True), 'zeros à esquerda: inválido');
  CheckEqualsStr('127.0.0.1', ClientKey('127.0.0.1', [], True), 'sem o cabeçalho: o IP da conexão');
  { Taxa de cada rota (B5). }
  Check(ClassifyRateKind('POST', '/api/rooms') = rtCreate, 'POST /api/rooms: criação');
  Check(ClassifyRateKind('POST', '/api/rooms?x=1') = rtCreate, 'com query: criação');
  Check(ClassifyRateKind('GET', '/api/rooms') = rtNone, 'GET /api/rooms: nenhuma');
  Check(ClassifyRateKind('GET', '/api/rooms/K7PM2Q') = rtJoin, 'GET da sala: consulta');
  Check(ClassifyRateKind('HEAD', '/api/rooms/ZZZZZZ') = rtJoin, 'HEAD da sala (mesmo inexistente): consulta');
  Check(ClassifyRateKind('POST', '/api/rooms/K7PM2Q/players') = rtJoin, 'entrada');
  Check(ClassifyRateKind('POST', '/api/rooms//players') = rtNone, 'sem código: nenhuma');
  Check(ClassifyRateKind('POST', '/api/rooms/K7PM2Q') = rtNone, 'POST na sala: nenhuma (405)');
  Check(ClassifyRateKind('POST', '/api/rooms/K7PM2Q/moves') = rtNone, 'jogada: nenhuma');
  Check(ClassifyRateKind('POST', '/api/rooms/K7PM2Q/leave') = rtNone, 'saída: nenhuma');
  Check(ClassifyRateKind('GET', '/ws') = rtWs, '/ws: canal');
  Check(ClassifyRateKind('POST', '/ws?a=b') = rtWs, 'qualquer pedido a /ws');
  Check(ClassifyRateKind('GET', '/health') = rtNone, '/health: nenhuma');
  Check(ClassifyRateKind('GET', '/api/game') = rtNone, '/api/game: nenhuma');
  CheckEqualsStr('a?b', SafeForLog('a'#10'b'), 'log sem quebra de linha');
  CheckEqualsStr('abc', SafeForLog('abcdef', 3), 'log truncado');
end;

procedure ExpectOk(const AArgs: array of string; const AWhat: string; out AOptions: TServerOptions);
var
  Error: string;
begin
  Check(ParseServerOptions(AArgs, 'C:\jogo\web', AOptions, Error), AWhat + ': deveria ser aceito; erro: ' + Error);
end;

procedure ExpectRejected(const AArgs: array of string; const AWhat: string);
var
  O: TServerOptions;
  Error: string;
begin
  Check(not ParseServerOptions(AArgs, 'C:\jogo\web', O, Error), AWhat + ': deveria ser recusado');
  Check(Error <> '', AWhat + ': mensagem de erro');
end;

procedure OP03_HardeningOptions;
var
  O: TServerOptions;
  Error: string;
begin
  ExpectOk([], 'sem argumentos', O);
  CheckEqualsInt(0, O.RateCreate, 'local: rate-create 0');
  CheckEqualsInt(0, O.RateJoin, 'local: rate-join 0');
  CheckEqualsInt(0, O.RateWs, 'local: rate-ws 0');
  CheckEqualsInt(60, O.RateWindowSeconds, 'janela 60 s');
  CheckEqualsInt(0, O.WsPerClient, 'local: ws-per-client 0');
  CheckEqualsInt(0, O.WsMsgRate, 'local: ws-msg-rate 0');
  CheckEqualsInt(30, O.HttpTimeoutSeconds, 'http-timeout 30 s');
  Check(not O.TrustProxy, 'trust-proxy desligado');

  ExpectOk(['--public', '--allowed-origin', 'https://jogo.test'], '--public', O);
  CheckEqualsInt(10, O.RateCreate, 'público: rate-create 10');
  CheckEqualsInt(30, O.RateJoin, 'público: rate-join 30');
  CheckEqualsInt(30, O.RateWs, 'público: rate-ws 30');
  CheckEqualsInt(8, O.WsPerClient, 'público: ws-per-client 8');
  CheckEqualsInt(30, O.WsMsgRate, 'público: ws-msg-rate 30');
  Check(ValidateServerOptions(O, Error), '--public com https: ' + Error);

  ExpectOk(['--public', '--allowed-origin', 'https://jogo.test', '--rate-create', '0', '--ws-per-client', '2'],
    'valor explícito vence o padrão do modo', O);
  CheckEqualsInt(0, O.RateCreate, 'público com --rate-create 0');
  CheckEqualsInt(2, O.WsPerClient, 'público com --ws-per-client 2');
  CheckEqualsInt(30, O.RateJoin, 'os outros continuam com o padrão público');
  ExpectOk(['--rate-create', '5', '--rate-join', '6', '--rate-ws', '7', '--rate-window-seconds', '2',
    '--ws-per-client', '3', '--ws-msg-rate', '4', '--http-timeout-seconds', '9', '--trust-proxy'], 'todas no modo local', O);
  CheckEqualsInt(5, O.RateCreate, '--rate-create');
  CheckEqualsInt(6, O.RateJoin, '--rate-join');
  CheckEqualsInt(7, O.RateWs, '--rate-ws');
  CheckEqualsInt(2, O.RateWindowSeconds, '--rate-window-seconds');
  CheckEqualsInt(3, O.WsPerClient, '--ws-per-client');
  CheckEqualsInt(4, O.WsMsgRate, '--ws-msg-rate');
  CheckEqualsInt(9, O.HttpTimeoutSeconds, '--http-timeout-seconds');
  Check(O.TrustProxy, '--trust-proxy');
  Check(not O.PublicMode, 'continua local');
  ExpectOk(['--rate-create', '10000', '--rate-window-seconds', '3600', '--http-timeout-seconds', '3600'],
    'máximos aceitos', O);

  ExpectRejected(['--rate-create', '-1'], 'rate-create negativo');
  ExpectRejected(['--rate-create', '10001'], 'rate-create acima do máximo');
  ExpectRejected(['--rate-join', 'abc'], 'rate-join não numérico');
  ExpectRejected(['--rate-ws'], 'rate-ws sem valor');
  ExpectRejected(['--rate-window-seconds', '0'], 'janela 0');
  ExpectRejected(['--rate-window-seconds', '3601'], 'janela acima do máximo');
  ExpectRejected(['--http-timeout-seconds', '0'], 'prazo de leitura 0');
  ExpectRejected(['--ws-per-client', '1.5'], 'ws-per-client fracionário');
  ExpectRejected(['--ws-msg-rate', '--public'], 'ws-msg-rate seguido de outra opção');
  ExpectRejected(['--trust-proxy', 'sim'], 'trust-proxy não tem valor');
end;

procedure RunLimitTests;
begin
  RunCase('RL-01', 'Taxa por cliente: abaixo, no limite, acima, Retry-After, janela que reabre, teto de clientes', RL01_RateLimiter);
  RunCase('RL-02', 'Canais por cliente: limite, liberação e 8 threads disputando', RL02_ConnectionCounter);
  RunCase('RL-03', 'Corpo com teto: tamanho declarado não aloca; excedente contado e descartado', RL03_CappedStream);
  RunCase('RL-04', 'Mensagens por canal numa janela de 10 s', RL04_MessageWindow);
  RunCase('RL-05', 'Cliente atrás de proxy (X-Forwarded-For) e taxa de cada rota', RL05_ClientAndKinds);
  RunCase('OP-03', 'Opções da O6: padrões local e público, valores explícitos e inválidos', OP03_HardeningOptions);
end;

end.
