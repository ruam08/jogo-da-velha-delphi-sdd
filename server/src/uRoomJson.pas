unit uRoomJson;

(* JSON do modo online (docs/plan-online.md, secoes 6.2, 6.3, 6.6 e 7):
   - objeto sala, sem tokens, com a partida no formato exato do modo local
     (a mesma funcao SnapshotToJsonValue de uGameJson);
   - respostas de criacao/entrada e de operacoes de sala;
   - mensagens do canal em tempo real (servidor -> cliente) e leitura das
     mensagens do cliente;
   - codigos e mensagens dos erros novos.
   Este comentario usa parenteses com asterisco porque contem chaves.
   Sem dependencia de Indy nem de HTTP. *)

interface

uses
  System.SysUtils, System.JSON, uGameEngine, uRoom;

const
  ERR_ROOM_NOT_FOUND = 'SALA_INEXISTENTE';
  ERR_ROOM_CLOSED = 'SALA_ENCERRADA';
  ERR_ROOM_FULL = 'SALA_CHEIA';
  ERR_INVALID_TOKEN = 'TOKEN_INVALIDO';
  ERR_WAITING_OPPONENT = 'AGUARDANDO_OPONENTE';
  ERR_NOT_YOUR_TURN = 'VEZ_DO_OPONENTE';
  ERR_GAME_IN_PROGRESS = 'PARTIDA_EM_ANDAMENTO';
  ERR_BODY_TOO_LARGE = 'CORPO_MUITO_GRANDE';
  ERR_RATE_LIMIT = 'LIMITE_DE_REQUISICOES';
  ERR_CAPACITY = 'CAPACIDADE_ESGOTADA';
  ERR_BAD_HANDSHAKE = 'HANDSHAKE_INVALIDO';
  ERR_WS_VERSION = 'VERSAO_WEBSOCKET';
  ERR_ORIGIN = 'ORIGEM_NAO_PERMITIDA';
  ERR_INVALID_MESSAGE = 'MENSAGEM_INVALIDA';
  ERR_TIMEOUT = 'TEMPO_ESGOTADO';
  ERR_REPLACED = 'SUBSTITUIDA';

  MSG_ROOM_NOT_FOUND = 'Sala não encontrada. Confira o código.';
  MSG_ROOM_CLOSED = 'Esta sala foi encerrada.';
  MSG_ROOM_FULL = 'Esta sala já tem dois jogadores.';
  MSG_INVALID_TOKEN = 'Jogador não identificado nesta sala.';
  MSG_WAITING_OPPONENT = 'Aguarde o segundo jogador entrar na sala.';
  MSG_NOT_YOUR_TURN = 'Não é a sua vez.';
  MSG_GAME_IN_PROGRESS = 'A partida ainda está em andamento.';
  MSG_BODY_TOO_LARGE = 'O corpo da requisição é grande demais.';
  MSG_RATE_LIMIT = 'Muitas requisições. Tente novamente em instantes.';
  MSG_CAPACITY = 'O servidor está sem vagas para novas salas. Tente mais tarde.';
  MSG_BAD_HANDSHAKE = 'Requisição de WebSocket inválida.';
  MSG_WS_VERSION = 'Versão de WebSocket não suportada.';
  MSG_ORIGIN = 'Origem não permitida.';
  MSG_INVALID_MESSAGE = 'Mensagem inválida.';
  MSG_TIMEOUT = 'Tempo esgotado.';
  MSG_REPLACED = 'Esta sala foi aberta em outra aba.';

  PROTOCOL_VERSION = 1;

type
  TStateReason = (srEntry, srMove, srNewGame, srConnect, srDisconnect);

  TClientMessageKind = (cmEnter, cmPing);

  TClientMessage = record
    Kind: TClientMessageKind;
    Room: string;
    Token: string;
    PingId: Integer;
  end;

function RoomToJsonValue(const AState: TRoomSnapshot): TJSONObject;
function RoomToJson(const AState: TRoomSnapshot): string;
(* {"sala":{...}} *)
function RoomResponseJson(const AState: TRoomSnapshot): string;
(* {"sala":{...},"jogador":{"simbolo":"X","token":"..."}} *)
function PlayerResponseJson(const AState: TRoomSnapshot; ASeat: TSeat; const AToken: string): string;

function WelcomeJson(const AState: TRoomSnapshot; ASeat: TSeat; APingIntervalMs: Integer): string;
function StateEventJson(const AState: TRoomSnapshot; AReason: TStateReason): string;
function RoomClosedEventJson(const AState: TRoomSnapshot): string;
function PongJson(AId: Integer): string;
function ErrorEventJson(const ACode, AMessage: string): string;

{ Codigo HTTP, codigo e mensagem de erro de um resultado de sala diferente de rrOk. }
procedure RoomErrorInfo(AResult: TRoomResult; out AHttpStatus: Integer;
  out ACode, AMessage: string);

{ True so para "entrar" (protocolo 1, sala e token texto) ou "ping" (id inteiro
  de 0 a 2147483647), em objeto JSON UTF-8 valido. Campos extras sao ignorados. }
function ParseClientMessage(const ABytes: TBytes; out AMessage: TClientMessage): Boolean;

function SituationText(ASituation: TRoomSituation): string;
function StateReasonText(AReason: TStateReason): string;

implementation

uses
  uGameJson;

function SituationText(ASituation: TRoomSituation): string;
begin
  case ASituation of
    rsWaiting: Result := 'AGUARDANDO_OPONENTE';
    rsPlaying: Result := 'EM_JOGO';
  else
    Result := 'ENCERRADA';
  end;
end;

function StateReasonText(AReason: TStateReason): string;
begin
  case AReason of
    srEntry: Result := 'ENTRADA';
    srMove: Result := 'JOGADA';
    srNewGame: Result := 'NOVA_PARTIDA';
    srConnect: Result := 'CONEXAO';
  else
    Result := 'DESCONEXAO';
  end;
end;

function BoolValue(AValue: Boolean): TJSONValue;
begin
  if AValue then
    Result := TJSONTrue.Create
  else
    Result := TJSONFalse.Create;
end;

function SeatValue(const AView: TSeatView): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ocupado', BoolValue(AView.Occupied));
  Result.AddPair('conectado', BoolValue(AView.Connected));
end;

function CloseReasonValue(AReason: TCloseReason): TJSONValue;
begin
  case AReason of
    crLeave: Result := TJSONString.Create('SAIDA');
    crAbandoned: Result := TJSONString.Create('ABANDONO');
  else
    Result := TJSONNull.Create;
  end;
end;

function RoomToJsonValue(const AState: TRoomSnapshot): TJSONObject;
var
  Players: TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('codigo', AState.Code);
    Result.AddPair('situacao', SituationText(AState.Situation));
    Result.AddPair('versao', TJSONNumber.Create(AState.Version));
    Result.AddPair('numeroDaPartida', TJSONNumber.Create(AState.GameNumber));
    Players := TJSONObject.Create;
    Result.AddPair('jogadores', Players);
    Players.AddPair('X', SeatValue(AState.Seats[seX]));
    Players.AddPair('O', SeatValue(AState.Seats[seO]));
    Result.AddPair('partida', SnapshotToJsonValue(AState.Game));
    Result.AddPair('motivoEncerramento', CloseReasonValue(AState.CloseReason));
  except
    Result.Free;
    raise;
  end;
end;

{ Serializa e libera o objeto. }
function Render(AObject: TJSONObject): string;
begin
  try
    Result := AObject.ToJSON;
  finally
    AObject.Free;
  end;
end;

function RoomToJson(const AState: TRoomSnapshot): string;
begin
  Result := Render(RoomToJsonValue(AState));
end;

function RoomResponseJson(const AState: TRoomSnapshot): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('sala', RoomToJsonValue(AState));
  Result := Render(Root);
end;

function PlayerResponseJson(const AState: TRoomSnapshot; ASeat: TSeat; const AToken: string): string;
var
  Root, Player: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('sala', RoomToJsonValue(AState));
  Player := TJSONObject.Create;
  Root.AddPair('jogador', Player);
  Player.AddPair('simbolo', SeatName(ASeat));
  Player.AddPair('token', AToken);
  Result := Render(Root);
end;

function WelcomeJson(const AState: TRoomSnapshot; ASeat: TSeat; APingIntervalMs: Integer): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('tipo', 'bem_vindo');
  Root.AddPair('protocolo', TJSONNumber.Create(PROTOCOL_VERSION));
  Root.AddPair('voce', SeatName(ASeat));
  Root.AddPair('intervaloPingMs', TJSONNumber.Create(APingIntervalMs));
  Root.AddPair('sala', RoomToJsonValue(AState));
  Result := Render(Root);
end;

function StateEventJson(const AState: TRoomSnapshot; AReason: TStateReason): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('tipo', 'estado');
  Root.AddPair('motivo', StateReasonText(AReason));
  Root.AddPair('sala', RoomToJsonValue(AState));
  Result := Render(Root);
end;

function RoomClosedEventJson(const AState: TRoomSnapshot): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('tipo', 'sala_encerrada');
  Root.AddPair('motivo', CloseReasonValue(AState.CloseReason));
  Root.AddPair('sala', RoomToJsonValue(AState));
  Result := Render(Root);
end;

function PongJson(AId: Integer): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('tipo', 'pong');
  Root.AddPair('id', TJSONNumber.Create(AId));
  Result := Render(Root);
end;

function ErrorEventJson(const ACode, AMessage: string): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  Root.AddPair('tipo', 'erro');
  Root.AddPair('codigo', ACode);
  Root.AddPair('mensagem', AMessage);
  Result := Render(Root);
end;

procedure RoomErrorInfo(AResult: TRoomResult; out AHttpStatus: Integer;
  out ACode, AMessage: string);
begin
  case AResult of
    rrNotFound:
      begin AHttpStatus := 404; ACode := ERR_ROOM_NOT_FOUND; AMessage := MSG_ROOM_NOT_FOUND; end;
    rrClosed:
      begin AHttpStatus := 410; ACode := ERR_ROOM_CLOSED; AMessage := MSG_ROOM_CLOSED; end;
    rrInvalidToken:
      begin AHttpStatus := 401; ACode := ERR_INVALID_TOKEN; AMessage := MSG_INVALID_TOKEN; end;
    rrFull:
      begin AHttpStatus := 409; ACode := ERR_ROOM_FULL; AMessage := MSG_ROOM_FULL; end;
    rrWaitingOpponent:
      begin AHttpStatus := 409; ACode := ERR_WAITING_OPPONENT; AMessage := MSG_WAITING_OPPONENT; end;
    rrInvalidPosition:
      begin AHttpStatus := 400; ACode := ERR_INVALID_POSITION; AMessage := MSG_INVALID_POSITION; end;
    rrGameOver:
      begin AHttpStatus := 409; ACode := ERR_GAME_OVER; AMessage := MSG_GAME_OVER; end;
    rrNotYourTurn:
      begin AHttpStatus := 409; ACode := ERR_NOT_YOUR_TURN; AMessage := MSG_NOT_YOUR_TURN; end;
    rrCellOccupied:
      begin AHttpStatus := 409; ACode := ERR_CELL_OCCUPIED; AMessage := MSG_CELL_OCCUPIED; end;
    rrGameInProgress:
      begin AHttpStatus := 409; ACode := ERR_GAME_IN_PROGRESS; AMessage := MSG_GAME_IN_PROGRESS; end;
    rrCapacity:
      begin AHttpStatus := 503; ACode := ERR_CAPACITY; AMessage := MSG_CAPACITY; end;
  else
    begin AHttpStatus := 500; ACode := ERR_INTERNAL; AMessage := MSG_INTERNAL; end;
  end;
end;

{ ---- Mensagens do cliente -------------------------------------------------- }

function FindField(AObject: TJSONObject; const AName: string): TJSONValue;
var
  I: Integer;
begin
  { Comparacao exata do nome, como em ParseMoveBody. }
  Result := nil;
  for I := 0 to AObject.Count - 1 do
    if AObject.Pairs[I].JsonString.Value = AName then
      Exit(AObject.Pairs[I].JsonValue);
end;

function IntegerField(AObject: TJSONObject; const AName: string; out AValue: Integer): Boolean;
var
  Field: TJSONValue;
begin
  Field := FindField(AObject, AName);
  Result := (Field is TJSONNumber) and TryStrToInt(TJSONNumber(Field).Value, AValue);
end;

function StringField(AObject: TJSONObject; const AName: string; out AValue: string): Boolean;
var
  Field: TJSONValue;
begin
  Field := FindField(AObject, AName);
  { No Delphi, TJSONNumber herda de TJSONString: numero nao vale como texto. }
  Result := (Field is TJSONString) and not (Field is TJSONNumber);
  if Result then
    AValue := TJSONString(Field).Value
  else
    AValue := '';
end;

function ParseClientMessage(const ABytes: TBytes; out AMessage: TClientMessage): Boolean;
var
  Value: TJSONValue;
  Obj: TJSONObject;
  Kind: string;
  Protocol: Integer;
begin
  Result := False;
  AMessage.Kind := cmPing;
  AMessage.Room := '';
  AMessage.Token := '';
  AMessage.PingId := 0;
  if (Length(ABytes) = 0) or not IsValidUtf8(ABytes) then
    Exit;
  try
    Value := TJSONObject.ParseJSONValue(ABytes, 0, True);
  except
    Value := nil;
  end;
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit;
  end;
  try
    Obj := TJSONObject(Value);
    if not StringField(Obj, 'tipo', Kind) then
      Exit;
    if Kind = 'entrar' then
    begin
      if not IntegerField(Obj, 'protocolo', Protocol) or (Protocol <> PROTOCOL_VERSION) then
        Exit;
      if not StringField(Obj, 'sala', AMessage.Room) or not StringField(Obj, 'token', AMessage.Token) then
        Exit;
      AMessage.Kind := cmEnter;
      Result := True;
    end
    else if Kind = 'ping' then
    begin
      if not IntegerField(Obj, 'id', AMessage.PingId) or (AMessage.PingId < 0) then
        Exit;
      AMessage.Kind := cmPing;
      Result := True;
    end;
  finally
    Value.Free;
  end;
end;

end.
