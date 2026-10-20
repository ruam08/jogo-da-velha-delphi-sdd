unit uHttpApp;

(* Servidor HTTP do jogo, baseado no TIdHTTPServer do Indy 10 que acompanha
  o Delphi 10.1 Berlin. Contrato: docs/plan.md, seção 3.

  Esta unit só traduz HTTP <-> serviço:
  - regras e estado ficam em uGameEngine / uGameService;
  - JSON fica em uGameJson.
  - salas do modo online: regras em uRoom / uRoomRegistry, rotas em
    uRoomHttp (docs/plan-online.md, seção 6). Esta unit só lê o pedido do
    Indy e escreve a resposta.

  - canal em tempo real (/ws, O3): avaliação da abertura em uWebSocket,
    origem em uOriginPolicy, sessão em uWsSession, notificações em uRoomHub.

  - ciclo de vida (O5): o faxineiro (uRoomJanitor) encerra as salas
    abandonadas e esquece as lembradas; começa em Start e para em Stop.

  - endurecimento (O6, docs/plan-online.md, seção 13.1): taxas por cliente
    (uRateLimiter) antes do roteador; canais simultâneos por cliente; corpo
    com teto de 64 KB em memória (uRequestLimits.TCappedStream); prazo de
    leitura por conexão; 503 em JSON quando --max-connections estoura;
    cabeçalhos de segurança em todas as respostas; com --public, /api/game*
    respondem 404 e / redireciona para /online.html.

  Endereço de escuta: TServerOptions.BindIP (--bind). Padrão 0.0.0.0, todas
  as interfaces IPv4, para jogar pela rede local; --bind 127.0.0.1 (ou
  --public sem --bind) restringe ao próprio computador (DTO-16, MC-01).

  Rotas:
    GET|HEAD /health            -> 200 {"status":"ok"}
    GET|HEAD /api/game          -> 200 estado
    POST     /api/game/moves    -> 200 estado | 400 | 409
    POST     /api/game/reset    -> 200 estado inicial
    /api/rooms e /api/rooms/... -> uRoomHttp (salas do modo online)
    GET      /ws                -> 101 e sessão WebSocket | 400 | 403 | 405 | 426
    GET|HEAD /, /index.html, /style.css, /app.js -> arquivos da pasta --www
    GET|HEAD /online.html, /online.css, /online.js -> idem (interface online, O4)
    método errado em rota conhecida -> 405 com Allow
    qualquer outra rota         -> 404 JSON (DT-21)
    com --public: /api/game* -> 404; / e /index.html -> 302 /online.html (O6) *)

interface

uses
  System.SysUtils, System.Classes,
  IdContext, IdCustomHTTPServer, IdHTTPServer, IdHeaderList,
  uGameService, uServerOptions, uRoom, uRoomRegistry, uRoomHub, uOriginPolicy, uRoomJanitor,
  uRateLimiter;

type
  TGameHttpServer = class
  private
    FServer: TIdHTTPServer;
    FService: TGameService;
    FRegistry: TRoomRegistry;
    FHub: TRoomHub;
    FJanitor: TRoomJanitor;
    { O6: taxas por cliente e canais simultâneos por cliente. }
    FRateCreate: TRateLimiter;
    FRateJoin: TRateLimiter;
    FRateWs: TRateLimiter;
    FWsPerClient: TConnectionCounter;
    FPolicy: TOriginPolicy;
    FOriginsLock: TObject;
    FOriginsAt: Int64;
    FStopping: Boolean;
    FOptions: TServerOptions;
    FPort: Word;
    FWebRoot: string;
    { Salas encerradas por abandono pelo faxineiro (thread do faxineiro). }
    procedure RoomsAbandoned(const AClosed: TArray<TRoomSnapshot>);
    { O6: prazo de leitura e corpo com teto. }
    procedure HandleConnect(AContext: TIdContext);
    procedure HandleCreatePostStream(AContext: TIdContext; AHeaders: TIdHeaderList;
      var VPostStream: TStream);
    { O6: True quando a taxa recusou (a resposta 429 já foi escrita). }
    function RateLimited(const AMethod: string; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo; const AClient: string; out ALogNote: string): Boolean;
    procedure HandleParseAuthentication(AContext: TIdContext;
      const AAuthType, AAuthData: string; var VUsername, VPassword: string;
      var VHandled: Boolean);
    function HandleRooms(AContext: TIdContext; const AMethod: string; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo): string;
    procedure HandleWebSocket(AContext: TIdContext; const AMethod, AClient: string;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    { Recalcula a lista automática de origens (a cada 60 s, ou já com AForce). }
    procedure RefreshOrigins(AForce: Boolean);
    procedure HandleCommand(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    function Route(AContext: TIdContext; const AMethod, APath, AClient: string;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): string;
    procedure HandleHealth(const AMethod: string; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleGetState(const AMethod: string; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleMove(const AMethod: string; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleReset(const AMethod: string; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleStatic(const AMethod, AFileName, AContentType: string;
      AResponseInfo: TIdHTTPResponseInfo);
  public
    { AOptions.WebRoot: pasta com index.html, style.css e app.js (caminho completo). }
    constructor Create(const AOptions: TServerOptions);
    destructor Destroy; override;
    procedure Start;
    { Seção 11.3: avisa os canais (fechamento 1001), espera até 1,5 s por eles,
      para o Indy e depois o faxineiro. }
    procedure Stop;
    property Port: Word read FPort;
    property WebRoot: string read FWebRoot;
    property Options: TServerOptions read FOptions;
  end;

implementation

uses
  System.Diagnostics, System.IOUtils, IdGlobal, IdSocketHandle, IdStack, IdIOHandler,
  IdIOHandlerSocket, uConsoleLog, uGameEngine, uGameJson, uClock, uSecureRandom, uRoomJson,
  uRoomHttp, uWebSocket, uWsSession, uRequestLimits;

type
  { O6 (seção 13.1, H-05): acima de --max-connections, o Indy aceita a conexão
    e a fecha sem resposta. Aqui ela recebe um 503 em JSON antes de fechar. }
  TGameIdHTTPServer = class(TIdHTTPServer)
  protected
    procedure DoMaxConnectionsExceeded(AIOHandler: TIdIOHandler); override;
  end;

const
  ORIGINS_REFRESH_MS = 60000;
  STOP_WAIT_MS = 1500;

var
  { Relógio monotônico (GetTickCount64 não está declarado no Winapi.Windows do Berlin). }
  GWatch: TStopwatch;

function MonoMs: Int64;
begin
  Result := GWatch.ElapsedMilliseconds;
end;

const
  ALLOW_GET_HEAD = 'GET, HEAD';
  ALLOW_POST = 'POST';

{ ---- Montagem de respostas ---------------------------------------------- }

{ Grava o corpo como bytes em ContentStream.
  Usar ContentText deixaria a codificação a cargo do Indy, que pode trocar
  acentos por "?" (RNF-08, DT-08). O Indy libera o ContentStream sozinho e
  não envia o corpo em respostas a HEAD. }
procedure WriteBytes(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const AContentType, ACacheControl: string; const ABytes: TBytes);
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
    Stream.Position := 0;
  except
    Stream.Free;
    raise;
  end;
  AResponseInfo.ResponseNo := AStatus;
  AResponseInfo.ContentType := AContentType;
  AResponseInfo.CharSet := 'utf-8';
  AResponseInfo.CustomHeaders.Values['Cache-Control'] := ACacheControl;
  AResponseInfo.ContentStream := Stream;
  AResponseInfo.ContentLength := Stream.Size;
end;

procedure WriteJson(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const AJson: string);
begin
  WriteBytes(AResponseInfo, AStatus, 'application/json', 'no-store',
    TEncoding.UTF8.GetBytes(AJson));
end;

{ Lista fixa de arquivos estáticos (DT-04): nada fora dela é servido, o que
  dispensa qualquer tratamento de caminhos como "/../". }
function FindStaticFile(const APath: string; out AFileName, AContentType: string): Boolean;
begin
  Result := True;
  if (APath = '/') or (APath = '/index.html') then
  begin
    AFileName := 'index.html';
    AContentType := 'text/html';
  end
  else if APath = '/style.css' then
  begin
    AFileName := 'style.css';
    AContentType := 'text/css';
  end
  else if APath = '/app.js' then
  begin
    AFileName := 'app.js';
    AContentType := 'text/javascript';
  end
  { Interface online (docs/plan-online.md, MC-04). }
  else if APath = '/online.html' then
  begin
    AFileName := 'online.html';
    AContentType := 'text/html';
  end
  else if APath = '/online.css' then
  begin
    AFileName := 'online.css';
    AContentType := 'text/css';
  end
  else if APath = '/online.js' then
  begin
    AFileName := 'online.js';
    AContentType := 'text/javascript';
  end
  else
    Result := False;
end;

procedure WriteError(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const ACode, AMessage: string);
begin
  WriteJson(AResponseInfo, AStatus, ErrorToJson(ACode, AMessage));
end;

procedure WriteState(AResponseInfo: TIdHTTPResponseInfo; const AState: TGameSnapshot);
begin
  WriteJson(AResponseInfo, 200, SnapshotToJson(AState));
end;

procedure WriteMethodNotAllowed(AResponseInfo: TIdHTTPResponseInfo;
  const AAllow: string);
begin
  WriteError(AResponseInfo, 405, ERR_METHOD_NOT_ALLOWED, MSG_METHOD_NOT_ALLOWED);
  AResponseInfo.CustomHeaders.Values['Allow'] := AAllow;
end;

{ Lê o corpo da requisição como bytes. PostStream é nil quando não há corpo.
  Com o TCappedStream (O6), no máximo 64 KB. }
function ReadBody(ARequestInfo: TIdHTTPRequestInfo): TBytes;
var
  Stream: TStream;
begin
  Result := nil;
  Stream := ARequestInfo.PostStream;
  if Stream is TCappedStream then
    Exit(TCappedStream(Stream).StoredBytes);
  if (Stream = nil) or (Stream.Size = 0) then
    Exit;
  Stream.Position := 0;
  SetLength(Result, Stream.Size);
  Stream.ReadBuffer(Result[0], Length(Result));
end;

{ Tamanho real do corpo: o maior entre o Content-Length declarado e o que
  chegou (inclusive o que o teto descartou). }
function BodySizeOf(ARequestInfo: TIdHTTPRequestInfo): Int64;
var
  Stream: TStream;
begin
  Result := 0;
  Stream := ARequestInfo.PostStream;
  if Stream is TCappedStream then
    Result := TCappedStream(Stream).Total
  else if Stream <> nil then
    Result := Stream.Size;
  if ARequestInfo.ContentLength > Result then
    Result := ARequestInfo.ContentLength;
end;

{ O6 (B11): cabeçalhos de segurança em toda resposta; CSP nas páginas. }
procedure ApplySecurityHeaders(AResponseInfo: TIdHTTPResponseInfo);
begin
  AResponseInfo.CustomHeaders.Values['X-Content-Type-Options'] := HEADER_NOSNIFF;
  AResponseInfo.CustomHeaders.Values['Referrer-Policy'] := HEADER_REFERRER_POLICY;
  if AResponseInfo.ContentType.StartsWith('text/html') then
  begin
    AResponseInfo.CustomHeaders.Values['Content-Security-Policy'] := PAGE_CSP;
    AResponseInfo.CustomHeaders.Values['X-Frame-Options'] := PAGE_FRAME_OPTIONS;
  end;
end;

{ Todos os valores de um cabeçalho (pode vir repetido). }
function HeaderValues(ARequestInfo: TIdHTTPRequestInfo; const AName: string): TArray<string>;
var
  List: TStringList;
  I: Integer;
begin
  List := TStringList.Create;
  try
    ARequestInfo.RawHeaders.Extract(AName, List);
    SetLength(Result, List.Count);
    for I := 0 to List.Count - 1 do
      Result[I] := List[I];
  finally
    List.Free;
  end;
end;

{ ---- TGameIdHTTPServer ---------------------------------------------------- }

procedure TGameIdHTTPServer.DoMaxConnectionsExceeded(AIOHandler: TIdIOHandler);
var
  Body: TBytes;
  Head, Peer: string;
begin
  { Roda na thread de aceite: tudo curto e protegido. }
  try
    Peer := '?';
    if AIOHandler is TIdIOHandlerSocket then
      Peer := TIdIOHandlerSocket(AIOHandler).Binding.PeerIP;
    Log('Conexão recusada de %s: limite de %d conexões simultâneas (503)', [Peer, MaxConnections]);
    { Lê o pedido que já chegou (até 20 ms): fechar o socket com bytes não
      lidos faria o Windows mandar RST, e o cliente perderia o 503. }
    AIOHandler.CheckForDataOnSource(20);
    AIOHandler.InputBuffer.Clear;
    Body := TEncoding.UTF8.GetBytes(ErrorToJson(ERR_SERVER_BUSY, MSG_SERVER_BUSY));
    Head := 'HTTP/1.1 503 Service Unavailable'#13#10 +
      'Content-Type: application/json; charset=utf-8'#13#10 +
      'Cache-Control: no-store'#13#10 +
      'Retry-After: ' + IntToStr(SERVER_BUSY_RETRY_SECONDS) + #13#10 +
      'X-Content-Type-Options: ' + HEADER_NOSNIFF + #13#10 +
      'Referrer-Policy: ' + HEADER_REFERRER_POLICY + #13#10 +
      'Connection: close'#13#10 +
      'Content-Length: ' + IntToStr(Length(Body)) + #13#10#13#10;
    AIOHandler.Write(ToBytes(Head, IndyTextEncoding_ASCII));
    AIOHandler.Write(TIdBytes(Body));
  except
    { o cliente pode já ter ido embora }
  end;
end;

{ ---- TGameHttpServer ----------------------------------------------------- }

constructor TGameHttpServer.Create(const AOptions: TServerOptions);
var
  Binding: TIdSocketHandle;
  Clock: IClock;
  Rng: IRandomSource;
begin
  inherited Create;
  FOptions := AOptions;
  FPort := AOptions.Port;
  FWebRoot := AOptions.WebRoot;
  FService := TGameService.Create;
  Clock := TSystemClock.Create;
  Rng := TSystemRandom.Create;
  FRegistry := TRoomRegistry.Create(Clock, Rng, AOptions.MaxRooms,
    Int64(AOptions.RememberSeconds) * 1000);
  FHub := TRoomHub.Create;
  { Faxineiro (seção 11.2, O5): começa em Start e para em Stop. }
  FJanitor := TRoomJanitor.Create(FRegistry, Int64(AOptions.RoomTtlSeconds) * 1000,
    Cardinal(AOptions.SweepMs), RoomsAbandoned,
    procedure(const AMessage: string)
    begin
      Log('ERRO no faxineiro: %s', [AMessage]);
    end);
  FPolicy := TOriginPolicy.Create(AOptions.PublicMode, AOptions.BindIP, AOptions.Port,
    AOptions.AllowedOrigins);
  FOriginsLock := TObject.Create;
  { O6 (seção 13.1): taxas por cliente, janela fixa; 0 = sem limite. }
  FRateCreate := TRateLimiter.Create(Clock, AOptions.RateCreate, Int64(AOptions.RateWindowSeconds) * 1000);
  FRateJoin := TRateLimiter.Create(Clock, AOptions.RateJoin, Int64(AOptions.RateWindowSeconds) * 1000);
  FRateWs := TRateLimiter.Create(Clock, AOptions.RateWs, Int64(AOptions.RateWindowSeconds) * 1000);
  FWsPerClient := TConnectionCounter.Create(AOptions.WsPerClient);
  FServer := TGameIdHTTPServer.Create(nil);
  FServer.DefaultPort := FPort;
  { Um único Binding explícito, IPv4, no endereço de --bind (padrão 0.0.0.0,
    todas as interfaces; 127.0.0.1 restringe ao próprio computador). Sem um
    Binding explícito o Indy escolheria os endereços sozinho. }
  FServer.Bindings.Clear;
  Binding := FServer.Bindings.Add;
  Binding.IP := AOptions.BindIP;
  Binding.Port := FPort;
  Binding.IPVersion := Id_IPv4;
  FServer.MaxConnections := AOptions.MaxConnections;
  { Fila de conexões aguardando aceite. O padrão do Indy (15) fazia o Windows
    recusar conexões numa rajada de requisições simultâneas (OR-18, 360 de
    uma vez); 200 é o máximo usual do Windows (SOMAXCONN). }
  FServer.ListenQueue := 200;
  FServer.KeepAlive := False;
  FServer.ServerSoftware := 'JogoDaVelha';
  { GET, POST e HEAD chegam em OnCommandGet; PUT, DELETE e os demais
    métodos chegam em OnCommandOther. Os dois vão para o mesmo roteador. }
  FServer.OnCommandGet := HandleCommand;
  FServer.OnCommandOther := HandleCommand;
  { Sem este evento, o Indy recusa qualquer esquema de Authorization que não
    seja Basic (exceção antes de OnCommandGet, conexão derrubada). O
    cabeçalho é lido cru por HandleRooms. }
  FServer.OnParseAuthentication := HandleParseAuthentication;
  { O6: prazo de leitura por conexão e corpo com teto em memória. }
  FServer.OnConnect := HandleConnect;
  FServer.OnCreatePostStream := HandleCreatePostStream;
end;

destructor TGameHttpServer.Destroy;
begin
  Stop;
  FServer.Free;
  { O faxineiro já parou em Stop; é liberado antes do hub e do registro que usa. }
  FJanitor.Free;
  FHub.Free;
  FPolicy.Free;
  FOriginsLock.Free;
  FWsPerClient.Free;
  FRateWs.Free;
  FRateJoin.Free;
  FRateCreate.Free;
  FRegistry.Free;
  FService.Free;
  inherited;
end;

procedure TGameHttpServer.Start;
begin
  { A lista de origens existe antes do primeiro pedido. }
  RefreshOrigins(True);
  FServer.Active := True;
  FJanitor.Start;
end;

procedure TGameHttpServer.RoomsAbandoned(const AClosed: TArray<TRoomSnapshot>);
var
  Closed: TRoomSnapshot;
begin
  { Normalmente ninguém está inscrito (a sala só é encerrada sem conexões);
    a publicação cobre o caso de uma inscrição ainda não removida. }
  for Closed in AClosed do
  begin
    Log('Sala %s encerrada por abandono', [Closed.Code]);
    FHub.PublishTerminal(Closed.Code, RoomClosedEventJson(Closed), 4410);
  end;
end;

procedure TGameHttpServer.Stop;
var
  Deadline: Int64;
begin
  { Deve ser chamado pela thread principal, nunca de dentro de um evento
    do Indy, para não travar à espera da própria thread. }
  if FServer.Active then
  begin
    { Seção 11.3: os canais enviam 1001 na próxima volta do laço (~50 ms). }
    FStopping := True;
    Deadline := MonoMs + STOP_WAIT_MS;
    while (ActiveWsSessions > 0) and (MonoMs < Deadline) do
      Sleep(20);
    FServer.Active := False;
  end;
  { Depois do Indy: nenhuma requisição ou canal usa mais as salas. Espera a
    varredura em andamento terminar; depois disso nada mais publica no hub. }
  FJanitor.Stop;
end;

{ IPv4 das interfaces desta máquina (Indy 10.6.2.5341, IdStack.pas). }
function LocalIPv4Addresses: TArray<string>;
var
  List: TIdStackLocalAddressList;
  I: Integer;
begin
  Result := nil;
  TIdStack.IncUsage;
  try
    List := TIdStackLocalAddressList.Create;
    try
      GStack.GetLocalAddressList(List);
      for I := 0 to List.Count - 1 do
        if List[I].IPVersion = Id_IPv4 then
          Result := Result + [List[I].IPAddress];
    finally
      List.Free;
    end;
  finally
    TIdStack.DecUsage;
  end;
end;

procedure TGameHttpServer.RefreshOrigins(AForce: Boolean);
var
  Now64: Int64;
  IPs: TArray<string>;
  Changed: Boolean;
begin
  Now64 := MonoMs;
  TMonitor.Enter(FOriginsLock);
  try
    if (not AForce) and (Now64 - FOriginsAt < ORIGINS_REFRESH_MS) then
      Exit;
    FOriginsAt := Now64;
  finally
    TMonitor.Exit(FOriginsLock);
  end;
  try
    IPs := LocalIPv4Addresses;
  except
    on E: Exception do
    begin
      Log('Não foi possível ler os endereços IPv4 da máquina (%s); a lista de origens não mudou.', [E.ClassName]);
      Exit;
    end;
  end;
  Changed := FPolicy.SetLocalAddresses(IPs);
  if Changed or AForce then
    Log('Origens permitidas: %s', [FPolicy.AllowedText]);
end;

{ Todos os valores do cabeçalho Origin (dois cabeçalhos = recusa, seção 7.7). }
function OriginHeaders(ARequestInfo: TIdHTTPRequestInfo): TArray<string>;
begin
  Result := HeaderValues(ARequestInfo, 'Origin');
end;

function OriginsForLog(const AOrigins: TArray<string>): string;
var
  O: string;
begin
  if Length(AOrigins) = 0 then
    Exit('(sem Origin)');
  Result := '';
  for O in AOrigins do
  begin
    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + '"' + OriginForLog(O) + '"';
  end;
end;

procedure TGameHttpServer.HandleConnect(AContext: TIdContext);
begin
  { B13: prazo de cada leitura até a requisição chegar inteira. A sessão do
    canal lê com CheckForDataOnSource e prazos próprios, sem este valor. }
  AContext.Connection.IOHandler.ReadTimeout := FOptions.HttpTimeoutSeconds * 1000;
end;

procedure TGameHttpServer.HandleCreatePostStream(AContext: TIdContext; AHeaders: TIdHeaderList;
  var VPostStream: TStream);
begin
  { B3: o corpo nunca ocupa mais que 64 KB, qualquer que seja o tamanho
    declarado ou enviado em blocos. }
  VPostStream := TCappedStream.Create(MAX_REQUEST_BODY_BYTES);
end;

function TGameHttpServer.RateLimited(const AMethod: string; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo; const AClient: string; out ALogNote: string): Boolean;
var
  Kind: TRateKind;
  Limiter: TRateLimiter;
  Decision: TRateDecision;
  KindName: string;
begin
  Result := False;
  ALogNote := '';
  Kind := ClassifyRateKind(AMethod, ARequestInfo.URI);
  if Kind = rtNone then
    Exit;
  Limiter := FRateCreate;
  KindName := 'criação de salas';
  if Kind = rtJoin then
  begin
    Limiter := FRateJoin;
    KindName := 'consulta e entrada em salas';
  end
  else if Kind = rtWs then
  begin
    Limiter := FRateWs;
    KindName := 'abertura de canal';
  end;
  if not Limiter.Enabled then
    Exit;
  Decision := Limiter.Hit(AClient);
  if Decision.Allowed then
    Exit;
  WriteError(AResponseInfo, 429, ERR_RATE_LIMIT, MSG_RATE_LIMIT);
  AResponseInfo.CustomHeaders.Values['Retry-After'] := IntToStr(Decision.RetryAfterSeconds);
  ALogNote := Format('limite de %s: %d por %d s, cliente %s', [KindName, Limiter.Limit,
    FOptions.RateWindowSeconds, AClient]);
  Result := True;
end;

procedure TGameHttpServer.HandleCommand(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Method, Path, Seat, Client, Note: string;
begin
  Method := UpperCase(ARequestInfo.Command);
  Path := ARequestInfo.Document;
  Seat := '';
  Note := '';
  try
    { B8: quem é o cliente (Host e X-Forwarded-Host nunca entram). }
    Client := ClientKey(AContext.Binding.PeerIP, HeaderValues(ARequestInfo, 'X-Forwarded-For'),
      FOptions.TrustProxy);
    { B7: a taxa vem antes de tudo o mais nas rotas que ela cobre. }
    if not RateLimited(Method, ARequestInfo, AResponseInfo, Client, Note) then
      Seat := Route(AContext, Method, Path, Client, ARequestInfo, AResponseInfo);
  except
    on E: Exception do
    begin
      Log('ERRO em %s %s: %s: %s', [Method, Path, E.ClassName, E.Message]);
      { Depois do 101 a conexão já é WebSocket: não há resposta HTTP a escrever. }
      if not AResponseInfo.HeaderHasBeenWritten then
      begin
        AResponseInfo.CustomHeaders.Clear;
        AResponseInfo.Location := '';
        WriteError(AResponseInfo, 500, ERR_INTERNAL, MSG_INTERNAL);
      end;
    end;
  end;
  { B11: depois da resposta montada (inclusive 4xx e 500). A 101 já foi
    escrita pelo canal e não passa por aqui. }
  if not AResponseInfo.HeaderHasBeenWritten then
    ApplySecurityHeaders(AResponseInfo);
  { Nunca registra o cabeçalho Authorization nem o corpo (token). }
  if Note <> '' then
    Log('%s %s -> %d (%s)', [Method, Path, AResponseInfo.ResponseNo, Note])
  else if Seat <> '' then
    Log('%s %s -> %d (%s)', [Method, Path, AResponseInfo.ResponseNo, Seat])
  else
    Log('%s %s -> %d', [Method, Path, AResponseInfo.ResponseNo]);
end;

procedure TGameHttpServer.HandleParseAuthentication(AContext: TIdContext;
  const AAuthType, AAuthData: string; var VUsername, VPassword: string;
  var VHandled: Boolean);
begin
  { Aceita qualquer esquema sem decodificar nada; a validação do token é
    feita por uRoomHttp, só nas rotas de sala. }
  VUsername := '';
  VPassword := '';
  VHandled := True;
end;

function TGameHttpServer.HandleRooms(AContext: TIdContext; const AMethod: string;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): string;
var
  Request: TRoomHttpRequest;
  Response: TRoomHttpResponse;
begin
  Request.Method := AMethod;
  Request.RawPath := ARequestInfo.URI;
  Request.Authorization := ARequestInfo.RawHeaders.Values['Authorization'];
  Request.Origins := OriginHeaders(ARequestInfo);
  if (AMethod = 'POST') and (Length(Request.Origins) > 0) then
    RefreshOrigins(False);
  Request.Body := ReadBody(ARequestInfo);
  Request.BodySize := BodySizeOf(ARequestInfo);
  if Length(Request.Body) > Request.BodySize then
    Request.BodySize := Length(Request.Body);
  Response := HandleRoomRequest(FRegistry, FHub, FPolicy, Request);
  if Response.RejectedOrigin then
    Log('Origem recusada em %s %s de %s: %s', [AMethod, ARequestInfo.Document,
      AContext.Binding.PeerIP, OriginsForLog(Request.Origins)]);
  WriteJson(AResponseInfo, Response.Status, Response.Json);
  if Response.Allow <> '' then
    AResponseInfo.CustomHeaders.Values['Allow'] := Response.Allow;
  if Response.Location <> '' then
    AResponseInfo.Location := Response.Location;
  Result := Response.Seat;
end;

procedure TGameHttpServer.HandleWebSocket(AContext: TIdContext; const AMethod, AClient: string;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Origins: TArray<string>;
  Opening: TWsOpening;
  Config: TWsSessionConfig;
  SessionId: Int64;
  Summary, Peer: string;
begin
  Origins := OriginHeaders(ARequestInfo);
  RefreshOrigins(False);
  Opening := EvaluateOpening(AMethod, ARequestInfo.RawHeaders.Values['Upgrade'],
    ARequestInfo.RawHeaders.Values['Connection'], ARequestInfo.RawHeaders.Values['Sec-WebSocket-Key'],
    ARequestInfo.RawHeaders.Values['Sec-WebSocket-Version'], FPolicy.Allowed(Origins, True));
  Peer := AContext.Binding.PeerIP + ':' + IntToStr(AContext.Binding.PeerPort);
  if Opening.Status <> 101 then
  begin
    WriteError(AResponseInfo, Opening.Status, Opening.ErrorCode, Opening.ErrorMessage);
    if Opening.HeaderName <> '' then
      AResponseInfo.CustomHeaders.Values[Opening.HeaderName] := Opening.HeaderValue;
    if Opening.Status = 403 then
      Log('Origem recusada em /ws de %s: %s', [AContext.Binding.PeerIP, OriginsForLog(Origins)]);
    Exit;
  end;

  { O6 (H-04): canais simultâneos por cliente, reservados antes do 101 e
    sempre devolvidos no fim da sessão. }
  if not FWsPerClient.TryAcquire(AClient) then
  begin
    WriteError(AResponseInfo, 429, ERR_CONNECTION_LIMIT, MSG_CONNECTION_LIMIT);
    Log('Canal recusado de %s: limite de %d canais por cliente', [AClient, FWsPerClient.Limit]);
    Exit;
  end;
  try

  { Resposta 101 escrita diretamente (seção 7.1): o WriteHeader do Indy
    acrescentaria "Connection: close" (KeepAlive = False) e não conhece o 101.
    Sem subprotocolo e sem extensões. }
  AContext.Connection.IOHandler.Write(ToBytes('HTTP/1.1 101 Switching Protocols'#13#10 +
    'Upgrade: websocket'#13#10 + 'Connection: Upgrade'#13#10 +
    'Sec-WebSocket-Accept: ' + Opening.AcceptKey + #13#10#13#10, IndyTextEncoding_ASCII));
  AResponseInfo.ResponseNo := 101;
  AResponseInfo.HeaderHasBeenWritten := True;

  SessionId := NextWsSessionId;
  Log('WS %d aberta: %s, origem %s', [SessionId, Peer, OriginsForLog(Origins)]);
  Config.Registry := FRegistry;
  Config.Hub := FHub;
  Config.HelloMs := Int64(FOptions.WsHelloSeconds) * 1000;
  Config.IdleMs := Int64(FOptions.WsIdleSeconds) * 1000;
  { 7.3: intervaloPingMs = um terço do prazo de inatividade. }
  Config.PingIntervalMs := FOptions.WsIdleSeconds * 1000 div 3;
  Config.IsStopping :=
    function: Boolean
    begin
      Result := FStopping;
    end;
  Config.MsgRateLimit := FOptions.WsMsgRate;
  RunWsSession(AContext, SessionId, Config, Summary);
  Log('WS %d fechada: %s', [SessionId, Summary]);
  finally
    FWsPerClient.Release(AClient);
  end;
end;

function TGameHttpServer.Route(AContext: TIdContext; const AMethod, APath, AClient: string;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): string;
var
  FileName, ContentType: string;
begin
  Result := '';
  if APath = '/ws' then
    HandleWebSocket(AContext, AMethod, AClient, ARequestInfo, AResponseInfo)
  { O6 (B10, DTO-17): com --public, a partida global do modo local não existe. }
  else if FOptions.PublicMode and ((APath = '/api/game') or (APath = '/api/game/moves') or
    (APath = '/api/game/reset')) then
    WriteError(AResponseInfo, 404, ERR_ROUTE_NOT_FOUND, MSG_ROUTE_NOT_FOUND)
  { O6 (B9): a página local depende de /api/game*; no modo público, a raiz
    leva à página online. }
  else if FOptions.PublicMode and ((APath = '/') or (APath = '/index.html')) then
  begin
    WriteBytes(AResponseInfo, 302, 'text/plain', 'no-store', nil);
    AResponseInfo.Location := '/online.html';
  end
  else if APath = '/health' then
    HandleHealth(AMethod, AResponseInfo)
  else if APath = '/api/game' then
    HandleGetState(AMethod, AResponseInfo)
  else if APath = '/api/game/moves' then
    HandleMove(AMethod, ARequestInfo, AResponseInfo)
  else if APath = '/api/game/reset' then
    HandleReset(AMethod, AResponseInfo)
  else if IsRoomPath(ARequestInfo.URI) then
    { Caminho cru (sem decodificar %xx): "/api/rooms/..%2Fx" é um código
      inválido (404 SALA_INEXISTENTE), não outro caminho. }
    Result := HandleRooms(AContext, AMethod, ARequestInfo, AResponseInfo)
  else if FindStaticFile(APath, FileName, ContentType) then
    HandleStatic(AMethod, FileName, ContentType, AResponseInfo)
  else
    WriteError(AResponseInfo, 404, ERR_ROUTE_NOT_FOUND, MSG_ROUTE_NOT_FOUND);
end;

procedure TGameHttpServer.HandleHealth(const AMethod: string;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  if (AMethod <> 'GET') and (AMethod <> 'HEAD') then
    WriteMethodNotAllowed(AResponseInfo, ALLOW_GET_HEAD)
  else
    WriteJson(AResponseInfo, 200, '{"status":"ok"}');
end;

procedure TGameHttpServer.HandleGetState(const AMethod: string;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  if (AMethod <> 'GET') and (AMethod <> 'HEAD') then
    WriteMethodNotAllowed(AResponseInfo, ALLOW_GET_HEAD)
  else
    WriteState(AResponseInfo, FService.GetState);
end;

procedure TGameHttpServer.HandleMove(const AMethod: string;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Position: Integer;
  Outcome: TPlayOutcome;
begin
  if AMethod <> 'POST' then
  begin
    WriteMethodNotAllowed(AResponseInfo, ALLOW_POST);
    Exit;
  end;

  { O6 (B3): acima do teto de 64 KB em memória, 413 (antes era lido inteiro). }
  if BodySizeOf(ARequestInfo) > MAX_REQUEST_BODY_BYTES then
  begin
    WriteError(AResponseInfo, 413, ERR_BODY_TOO_LARGE, MSG_BODY_TOO_LARGE);
    Exit;
  end;

  { Ordem de validação da RN-15: corpo -> posição inteira -> (no motor)
    intervalo -> partida em andamento -> célula vazia. }
  case ParseMoveBody(ReadBody(ARequestInfo), Position) of
    mbInvalidBody:
      begin
        WriteError(AResponseInfo, 400, ERR_INVALID_BODY, MSG_INVALID_BODY);
        Exit;
      end;
    mbInvalidPosition:
      begin
        WriteError(AResponseInfo, 400, ERR_INVALID_POSITION, MSG_INVALID_POSITION);
        Exit;
      end;
  end;

  Outcome := FService.Play(Position);
  case Outcome.MoveResult of
    mrAccepted:
      WriteState(AResponseInfo, Outcome.State);
    mrInvalidPosition:
      WriteError(AResponseInfo, 400, ERR_INVALID_POSITION, MSG_INVALID_POSITION);
    mrGameOver:
      WriteError(AResponseInfo, 409, ERR_GAME_OVER, MSG_GAME_OVER);
    mrCellOccupied:
      WriteError(AResponseInfo, 409, ERR_CELL_OCCUPIED, MSG_CELL_OCCUPIED);
  end;
end;

procedure TGameHttpServer.HandleReset(const AMethod: string;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  if AMethod <> 'POST' then
    WriteMethodNotAllowed(AResponseInfo, ALLOW_POST)
  else
    { O corpo, se existir, é ignorado (plano 3.3). }
    WriteState(AResponseInfo, FService.Reset);
end;

procedure TGameHttpServer.HandleStatic(const AMethod, AFileName,
  AContentType: string; AResponseInfo: TIdHTTPResponseInfo);
var
  FullPath: string;
begin
  if (AMethod <> 'GET') and (AMethod <> 'HEAD') then
  begin
    WriteMethodNotAllowed(AResponseInfo, ALLOW_GET_HEAD);
    Exit;
  end;
  { Lido do disco a cada requisição: editar a interface não exige recompilar. }
  FullPath := TPath.Combine(FWebRoot, AFileName);
  if not TFile.Exists(FullPath) then
  begin
    Log('AVISO: arquivo estático ausente: %s', [FullPath]);
    WriteError(AResponseInfo, 404, ERR_ROUTE_NOT_FOUND, MSG_ROUTE_NOT_FOUND);
    Exit;
  end;
  { no-cache: o navegador revalida e sempre usa a versão atual. }
  WriteBytes(AResponseInfo, 200, AContentType, 'no-cache', TFile.ReadAllBytes(FullPath));
end;

initialization
  GWatch := TStopwatch.StartNew;

end.
