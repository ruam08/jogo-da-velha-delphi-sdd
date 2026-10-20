unit uRoomHttp;

(* Rotas REST das salas (docs/plan-online.md, seções 6.1 a 6.6).

  Esta unit não usa Indy: recebe método, caminho cru, cabeçalho
  Authorization e corpo já lidos por uHttpApp e devolve status, JSON e
  cabeçalhos. Assim a tradução HTTP <-> domínio fica separada do servidor
  (mesmo princípio da DTO-21).

  Rotas:
    POST      /api/rooms                    -> 201 {sala, jogador} + Location
    GET|HEAD  /api/rooms/{codigo}           -> 200 {sala}
    POST      /api/rooms/{codigo}/players   -> 201 {sala, jogador}; reentrada 200
    POST      /api/rooms/{codigo}/moves     -> 200 {sala}   (Authorization obrigatório)
    POST      /api/rooms/{codigo}/reset     -> 200 {sala}   (idem)
    POST      /api/rooms/{codigo}/leave     -> 200 {sala}   (idem)

  Ordem de validação (seção 6.5): rota e método -> Origin, quando presente,
  permitida (só nos POST, seção 7.7) -> corpo <= 1.024 bytes ->
  sala existe -> sala não encerrada -> token -> corpo e posição (moves) ->
  as regras da sala (RNO-10). Os passos a partir do token são decididos pela
  própria sala, dentro da seção crítica dela (uRoom).

  O token só é lido do cabeçalho Authorization: Bearer <32 hex>. Nunca vem
  da URL, nunca é escrito em log e nunca aparece em {sala}.

  Toda mudança aceita é publicada no hub (O3), fora da seção crítica da
  sala: entrada -> estado ENTRADA; jogada -> JOGADA; nova partida ->
  NOVA_PARTIDA; saída -> sala_encerrada (fechamento 4410). *)

interface

uses
  System.SysUtils, uRoom, uRoomRegistry, uRoomHub, uOriginPolicy;

const
  ROOMS_PATH = '/api/rooms';
  MAX_ROOM_BODY_BYTES = 1024;

type
  TRoomHttpRequest = record
    Method: string;          { em maiúsculas }
    RawPath: string;         { caminho como chegou, sem a query, sem decodificar }
    Authorization: string;   { valor do cabeçalho, ou vazio }
    Origins: TArray<string>; { todos os valores do cabeçalho Origin (vazio = ausente) }
    Body: TBytes;
    BodySize: Int64;         { maior entre Content-Length e o corpo lido }
  end;

  TRoomHttpResponse = record
    Status: Integer;
    Json: string;
    Allow: string;           { só no 405 }
    Location: string;        { só no 201 da criação }
    Seat: string;            { 'X' ou 'O' quando o pedido identificou um lugar (log) }
    RejectedOrigin: Boolean; { 403 pela política de origem (o servidor registra no log) }
  end;

{ True se o caminho cru é desta unit: /api/rooms ou /api/rooms/... }
function IsRoomPath(const ARawPath: string): Boolean;

{ Atende um pedido de sala. Nunca levanta exceção por causa de dados do
  cliente; exceções internas sobem para o tratamento de 500 do servidor. }
function HandleRoomRequest(ARegistry: TRoomRegistry; AHub: TRoomHub; APolicy: TOriginPolicy;
  const ARequest: TRoomHttpRequest): TRoomHttpResponse;

{ Token de "Bearer <32 hex minúsculos>" (esquema sem distinção de maiúsculas,
  exatamente um espaço). Qualquer outra forma devolve vazio. }
function ParseBearer(const AHeader: string): string;

implementation

uses
  uGameEngine, uGameJson, uSecureRandom, uRoomJson;

const
  ALLOW_POST = 'POST';
  ALLOW_GET_HEAD = 'GET, HEAD';
  BEARER = 'bearer';

type
  TRoomRouteKind = (rkNone, rkCollection, rkRoom, rkPlayers, rkMoves, rkReset, rkLeave);

function IsRoomPath(const ARawPath: string): Boolean;
begin
  Result := (ARawPath = ROOMS_PATH) or ARawPath.StartsWith(ROOMS_PATH + '/');
end;

function ParseBearer(const AHeader: string): string;
var
  Token: string;
begin
  Result := '';
  if Length(AHeader) <> Length(BEARER) + 1 + 32 then
    Exit;
  if not SameText(Copy(AHeader, 1, Length(BEARER)), BEARER) then
    Exit;
  if AHeader[Length(BEARER) + 1] <> ' ' then
    Exit;
  Token := Copy(AHeader, Length(BEARER) + 2, 32);
  if IsValidTokenFormat(Token) then
    Result := Token;
end;

{ Separa /api/rooms[/codigo[/acao]]. ACode volta como veio (sem normalizar). }
function ParseRoute(const ARawPath: string; out ACode: string): TRoomRouteKind;
var
  Rest: string;
  Slash: Integer;
  Action: string;
begin
  ACode := '';
  Result := rkNone;
  if ARawPath = ROOMS_PATH then
    Exit(rkCollection);
  if not ARawPath.StartsWith(ROOMS_PATH + '/') then
    Exit;
  { Separação manual: sem Split, para que "/api/rooms/K7PM2Q/" (barra no
    fim) tenha uma ação vazia, e não seja confundido com a sala. }
  Rest := Copy(ARawPath, Length(ROOMS_PATH) + 2, MaxInt);
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    if Rest = '' then
      Exit;
    ACode := Rest;
    Exit(rkRoom);
  end;
  ACode := Copy(Rest, 1, Slash - 1);
  Action := Copy(Rest, Slash + 1, MaxInt);
  if ACode = '' then
    Exit;
  if Action = 'players' then
    Result := rkPlayers
  else if Action = 'moves' then
    Result := rkMoves
  else if Action = 'reset' then
    Result := rkReset
  else if Action = 'leave' then
    Result := rkLeave;
end;

function JsonResponse(AStatus: Integer; const AJson: string): TRoomHttpResponse;
begin
  Result.Status := AStatus;
  Result.Json := AJson;
  Result.Allow := '';
  Result.Location := '';
  Result.Seat := '';
  Result.RejectedOrigin := False;
end;

function ErrorResponse(AStatus: Integer; const ACode, AMessage: string): TRoomHttpResponse;
begin
  Result := JsonResponse(AStatus, ErrorToJson(ACode, AMessage));
end;

function RoomErrorResponse(AResult: TRoomResult): TRoomHttpResponse;
var
  Status: Integer;
  Code, Msg: string;
begin
  RoomErrorInfo(AResult, Status, Code, Msg);
  Result := ErrorResponse(Status, Code, Msg);
end;

function MethodNotAllowed(const AAllow: string): TRoomHttpResponse;
begin
  Result := ErrorResponse(405, ERR_METHOD_NOT_ALLOWED, MSG_METHOD_NOT_ALLOWED);
  Result.Allow := AAllow;
end;

(* Resposta {sala} de uma operação aceita, ou o erro do resultado. *)
function OutcomeResponse(const AOutcome: TRoomOutcome): TRoomHttpResponse;
begin
  if AOutcome.Result = rrOk then
    Result := JsonResponse(200, RoomResponseJson(AOutcome.Snapshot))
  else
    Result := RoomErrorResponse(AOutcome.Result);
end;

{ Notifica os canais da sala sobre uma mudança aceita (fora da seção da sala). }
procedure PublishOutcome(AHub: TRoomHub; const AOutcome: TRoomOutcome; AReason: TStateReason);
begin
  if not AOutcome.Changed then
    Exit;
  if AOutcome.Snapshot.Situation = rsClosed then
    AHub.PublishTerminal(AOutcome.Snapshot.Code, RoomClosedEventJson(AOutcome.Snapshot), 4410)
  else
    AHub.PublishState(AOutcome.Snapshot.Code, StateEventJson(AOutcome.Snapshot, AReason),
      AOutcome.Snapshot.Version);
end;

function PublishedResponse(AHub: TRoomHub; const AOutcome: TRoomOutcome; AReason: TStateReason): TRoomHttpResponse;
begin
  PublishOutcome(AHub, AOutcome, AReason);
  Result := OutcomeResponse(AOutcome);
end;

function HandleCreate(ARegistry: TRoomRegistry): TRoomHttpResponse;
var
  Room: IRoom;
  Token: string;
  RoomResult: TRoomResult;
begin
  RoomResult := ARegistry.CreateRoom(Room, Token);
  if RoomResult <> rrOk then
    Exit(RoomErrorResponse(RoomResult));
  Result := JsonResponse(201, PlayerResponseJson(Room.Snapshot, seX, Token));
  Result.Location := ROOMS_PATH + '/' + Room.Code;
  Result.Seat := SeatName(seX);
end;

function HandleGet(const ARoom: IRoom): TRoomHttpResponse;
var
  State: TRoomSnapshot;
begin
  State := ARoom.Snapshot;
  if State.Situation = rsClosed then   { encerrada entre o Find e a cópia }
    Exit(RoomErrorResponse(rrClosed));
  Result := JsonResponse(200, RoomResponseJson(State));
end;

function HandleJoin(AHub: TRoomHub; const ARoom: IRoom; const AToken: string): TRoomHttpResponse;
var
  Outcome: TRoomOutcome;
  Seat: TSeat;
  Issued: string;
begin
  { Token ausente ou inválido em players = entrada nova (seção 6.5, passo 5). }
  Outcome := ARoom.Join(AToken, Seat, Issued);
  if Outcome.Result <> rrOk then
    Exit(RoomErrorResponse(Outcome.Result));
  if Outcome.Changed then
  begin
    AHub.PublishState(ARoom.Code, StateEventJson(Outcome.Snapshot, srEntry), Outcome.Snapshot.Version);
    Result := JsonResponse(201, PlayerResponseJson(Outcome.Snapshot, Seat, Issued));
  end
  else
    Result := JsonResponse(200, PlayerResponseJson(Outcome.Snapshot, Seat, Issued));  { reentrada }
  Result.Seat := SeatName(Seat);
end;

function HandleMove(AHub: TRoomHub; const ARoom: IRoom; const AToken: string; const ABody: TBytes): TRoomHttpResponse;
var
  Position: Integer;
  BodyResult: TMoveBodyResult;
  Probe: TRoomOutcome;
begin
  BodyResult := ParseMoveBody(ABody, Position);
  if BodyResult = mbOk then
    Exit(PublishedResponse(AHub, ARoom.Play(AToken, Position), srMove));
  { Corpo ou posição não inteira: o erro do corpo (passo 6) só vale depois
    dos passos 4 e 5 (sala encerrada, token). A sala responde a uma jogada
    numa posição impossível sem mudar nada: rrClosed, rrInvalidToken ou,
    se os dois estão em ordem, rrInvalidPosition. }
  Probe := ARoom.Play(AToken, BOARD_FIRST - 1);
  if Probe.Result <> rrInvalidPosition then
    Exit(RoomErrorResponse(Probe.Result));
  if BodyResult = mbInvalidBody then
    Result := ErrorResponse(400, ERR_INVALID_BODY, MSG_INVALID_BODY)
  else
    Result := ErrorResponse(400, ERR_INVALID_POSITION, MSG_INVALID_POSITION);
end;

function HandleRoomRequest(ARegistry: TRoomRegistry; AHub: TRoomHub; APolicy: TOriginPolicy;
  const ARequest: TRoomHttpRequest): TRoomHttpResponse;
var
  Kind: TRoomRouteKind;
  Code, Token: string;
  Room: IRoom;
  FindResult: TRoomResult;
begin
  { Passo 0: rota e método. }
  Kind := ParseRoute(ARequest.RawPath, Code);
  case Kind of
    rkNone:
      Exit(ErrorResponse(404, ERR_ROUTE_NOT_FOUND, MSG_ROUTE_NOT_FOUND));
    rkRoom:
      if (ARequest.Method <> 'GET') and (ARequest.Method <> 'HEAD') then
        Exit(MethodNotAllowed(ALLOW_GET_HEAD));
  else
    if ARequest.Method <> 'POST' then
      Exit(MethodNotAllowed(ALLOW_POST));
  end;

  { Passo 1: Origin, quando presente, em toda rota POST de sala (seção 7.7).
    O cabeçalho Host nunca entra nesta decisão. }
  if (ARequest.Method = 'POST') and not APolicy.Allowed(ARequest.Origins, False) then
  begin
    Result := ErrorResponse(403, ERR_ORIGIN, MSG_ORIGIN);
    Result.RejectedOrigin := True;
    Exit;
  end;

  { Passo 2: tamanho do corpo, em todas as rotas. }
  if (ARequest.BodySize > MAX_ROOM_BODY_BYTES) or (Length(ARequest.Body) > MAX_ROOM_BODY_BYTES) then
    Exit(ErrorResponse(413, ERR_BODY_TOO_LARGE, MSG_BODY_TOO_LARGE));

  if Kind = rkCollection then
    Exit(HandleCreate(ARegistry));   { o corpo, se houver, é ignorado }

  { Passos 3 e 4: a sala existe e não está encerrada. }
  FindResult := ARegistry.Find(Code, Room);
  if FindResult <> rrOk then
    Exit(RoomErrorResponse(FindResult));

  Token := ParseBearer(ARequest.Authorization);
  case Kind of
    rkRoom:
      Result := HandleGet(Room);
    rkPlayers:
      Result := HandleJoin(AHub, Room, Token);
    rkMoves:
      Result := HandleMove(AHub, Room, Token, ARequest.Body);
    rkReset:
      Result := PublishedResponse(AHub, Room.NewGame(Token), srNewGame);
  else
    Result := PublishedResponse(AHub, Room.Leave(Token), srMove);
  end;
end;

end.
