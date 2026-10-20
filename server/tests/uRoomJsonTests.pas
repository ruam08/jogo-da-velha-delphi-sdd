unit uRoomJsonTests;

(* Casos RJ do docs/test-plan-online.md (secao 5): JSON do modo online
   (uRoomJson), sem HTTP. Os textos esperados seguem docs/plan-online.md,
   secoes 6.2, 6.3, 6.6 e 7. Comentario com parenteses e asterisco porque o
   texto contem chaves. *)

interface

procedure RunRoomJsonTests;

implementation

uses
  System.SysUtils, System.JSON, uMiniTest, uGameEngine, uGameJson, uRoom, uRoomJson;

const
  INITIAL_GAME_JSON = '{"tabuleiro":["","","","","","","","",""],"status":"EM_ANDAMENTO",' +
    '"jogadorDaVez":"X","vencedor":null,"celulasVencedoras":[]}';
  TOKEN = '3f9c0a6d1e7b42c8a5d09e61f2b4c7a8';

function GameAfter(const AMoves: array of Integer): TGameSnapshot;
var
  Engine: TGameEngine;
  I: Integer;
begin
  Engine := TGameEngine.Create;
  try
    for I := 0 to High(AMoves) do
      Engine.Play(AMoves[I]);
    Result := Engine.GetSnapshot;
  finally
    Engine.Free;
  end;
end;

function MakeState(const ACode: string; ASituation: TRoomSituation; AVersion: Int64;
  AGameNumber: Integer; AXOcc, AXConn, AOOcc, AOConn: Boolean;
  const AGame: TGameSnapshot; AReason: TCloseReason): TRoomSnapshot;
begin
  Result.Code := ACode;
  Result.Situation := ASituation;
  Result.Version := AVersion;
  Result.GameNumber := AGameNumber;
  Result.Seats[seX].Occupied := AXOcc;
  Result.Seats[seX].Connected := AXConn;
  Result.Seats[seO].Occupied := AOOcc;
  Result.Seats[seO].Connected := AOConn;
  Result.Game := AGame;
  Result.CloseReason := AReason;
end;

function Waiting: TRoomSnapshot;
begin
  Result := MakeState('K7PM2Q', rsWaiting, 1, 1, True, False, False, False, GameAfter([]), crNone);
end;

const
  WAITING_JSON = '{"codigo":"K7PM2Q","situacao":"AGUARDANDO_OPONENTE","versao":1,"numeroDaPartida":1,' +
    '"jogadores":{"X":{"ocupado":true,"conectado":false},"O":{"ocupado":false,"conectado":false}},' +
    '"partida":' + INITIAL_GAME_JSON + ',"motivoEncerramento":null}';

{ Decodifica e devolve o valor texto de um campo (para mensagens com acentos,
  que o ToJSON pode escapar como \uXXXX). }
function FieldText(const AJson, AName: string): string;
var
  V: TJSONValue;
begin
  Result := '<JSON invalido>';
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if (V is TJSONObject) and (TJSONObject(V).GetValue(AName) <> nil) then
      Result := TJSONObject(V).GetValue(AName).Value;
  finally
    V.Free;
  end;
end;

{ ---- RJ-01 -------------------------------------------------------------------- }

procedure RJ01_RoomJson;
var
  S: TRoomSnapshot;
  Json, GameJson: string;
begin
  CheckEqualsStr(WAITING_JSON, RoomToJson(Waiting), 'sala aguardando oponente');

  S := MakeState('K7PM2Q', rsPlaying, 7, 1, True, True, True, False, GameAfter([0, 4]), crNone);
  CheckEqualsStr('{"codigo":"K7PM2Q","situacao":"EM_JOGO","versao":7,"numeroDaPartida":1,' +
    '"jogadores":{"X":{"ocupado":true,"conectado":true},"O":{"ocupado":true,"conectado":false}},' +
    '"partida":{"tabuleiro":["X","","","","O","","","",""],"status":"EM_ANDAMENTO","jogadorDaVez":"X",' +
    '"vencedor":null,"celulasVencedoras":[]},"motivoEncerramento":null}', RoomToJson(S), 'sala em jogo');

  { Vitoria dupla (S-DUP): a partida e identica, byte a byte, ao JSON do modo local. }
  S := MakeState('ABCDEF', rsPlaying, 12, 3, True, True, True, True, GameAfter([0, 1, 2, 3, 6, 5, 8, 7, 4]), crNone);
  GameJson := SnapshotToJson(S.Game);
  Json := RoomToJson(S);
  Check(Pos('"partida":' + GameJson + ',', Json) > 0, 'partida da sala = SnapshotToJson: ' + Json);
  Check(Pos('"celulasVencedoras":[0,2,4,6,8]', GameJson) > 0, 'celulas da vitoria dupla: ' + GameJson);
  Check(Pos('"numeroDaPartida":3', Json) > 0, 'numero da partida');

  S := MakeState('ABCDEF', rsClosed, 9, 1, True, False, True, False, GameAfter([0]), crLeave);
  Check(Pos('"situacao":"ENCERRADA"', RoomToJson(S)) > 0, 'situacao encerrada');
  Check(Pos('"motivoEncerramento":"SAIDA"}', RoomToJson(S)) > 0, 'motivo SAIDA no fim do objeto');
  S.CloseReason := crAbandoned;
  Check(Pos('"motivoEncerramento":"ABANDONO"}', RoomToJson(S)) > 0, 'motivo ABANDONO');
  S.Version := 3000000000;
  Check(Pos('"versao":3000000000,', RoomToJson(S)) > 0, 'versao acima de 32 bits: ' + RoomToJson(S));

  CheckEqualsStr('{"sala":' + WAITING_JSON + '}', RoomResponseJson(Waiting), 'resposta {sala}');
  CheckEqualsStr('{"sala":' + WAITING_JSON + ',"jogador":{"simbolo":"X","token":"' + TOKEN + '"}}',
    PlayerResponseJson(Waiting, seX, TOKEN), 'resposta de criacao/entrada');
  Check(Pos('token', RoomToJson(Waiting)) = 0, 'o objeto sala nunca contem token');
end;

{ ---- RJ-02 -------------------------------------------------------------------- }

procedure ExpectError(AResult: TRoomResult; AHttp: Integer; const ACode, AMessage: string);
var
  Http: Integer;
  Code, Msg: string;
begin
  RoomErrorInfo(AResult, Http, Code, Msg);
  CheckEqualsInt(AHttp, Http, ACode + ': HTTP');
  CheckEqualsStr(ACode, Code, ACode + ': codigo');
  CheckEqualsStr(AMessage, Msg, ACode + ': mensagem');
end;

procedure RJ02_ServerMessages;
var
  Json: string;
begin
  CheckEqualsStr('{"tipo":"bem_vindo","protocolo":1,"voce":"O","intervaloPingMs":20000,"sala":' + WAITING_JSON + '}',
    WelcomeJson(Waiting, seO, 20000), 'bem_vindo');
  CheckEqualsStr('{"tipo":"estado","motivo":"ENTRADA","sala":' + WAITING_JSON + '}', StateEventJson(Waiting, srEntry), 'estado ENTRADA');
  CheckEqualsStr('{"tipo":"estado","motivo":"JOGADA","sala":' + WAITING_JSON + '}', StateEventJson(Waiting, srMove), 'estado JOGADA');
  CheckEqualsStr('{"tipo":"estado","motivo":"NOVA_PARTIDA","sala":' + WAITING_JSON + '}', StateEventJson(Waiting, srNewGame), 'estado NOVA_PARTIDA');
  CheckEqualsStr('{"tipo":"estado","motivo":"CONEXAO","sala":' + WAITING_JSON + '}', StateEventJson(Waiting, srConnect), 'estado CONEXAO');
  CheckEqualsStr('{"tipo":"estado","motivo":"DESCONEXAO","sala":' + WAITING_JSON + '}', StateEventJson(Waiting, srDisconnect), 'estado DESCONEXAO');
  CheckEqualsStr('{"tipo":"pong","id":17}', PongJson(17), 'pong');

  Json := RoomClosedEventJson(MakeState('ABCDEF', rsClosed, 9, 1, True, False, True, False, GameAfter([]), crLeave));
  Check(Copy(Json, 1, 48) = '{"tipo":"sala_encerrada","motivo":"SAIDA","sala"', 'sala_encerrada: ' + Json);

  Json := ErrorEventJson(ERR_INVALID_TOKEN, MSG_INVALID_TOKEN);
  CheckEqualsStr('erro', FieldText(Json, 'tipo'), 'erro: tipo');
  CheckEqualsStr('TOKEN_INVALIDO', FieldText(Json, 'codigo'), 'erro: codigo');
  CheckEqualsStr('Jogador não identificado nesta sala.', FieldText(Json, 'mensagem'), 'erro: mensagem com acento');

  { Tabela de docs/plan-online.md 6.6 (e os codigos do modo local reaproveitados). }
  ExpectError(rrNotFound, 404, 'SALA_INEXISTENTE', 'Sala não encontrada. Confira o código.');
  ExpectError(rrClosed, 410, 'SALA_ENCERRADA', 'Esta sala foi encerrada.');
  ExpectError(rrFull, 409, 'SALA_CHEIA', 'Esta sala já tem dois jogadores.');
  ExpectError(rrInvalidToken, 401, 'TOKEN_INVALIDO', 'Jogador não identificado nesta sala.');
  ExpectError(rrWaitingOpponent, 409, 'AGUARDANDO_OPONENTE', 'Aguarde o segundo jogador entrar na sala.');
  ExpectError(rrNotYourTurn, 409, 'VEZ_DO_OPONENTE', 'Não é a sua vez.');
  ExpectError(rrGameInProgress, 409, 'PARTIDA_EM_ANDAMENTO', 'A partida ainda está em andamento.');
  ExpectError(rrCapacity, 503, 'CAPACIDADE_ESGOTADA', 'O servidor está sem vagas para novas salas. Tente mais tarde.');
  ExpectError(rrInvalidPosition, 400, 'POSICAO_INVALIDA', 'A posição deve ser um número inteiro de 0 a 8.');
  ExpectError(rrGameOver, 409, 'PARTIDA_ENCERRADA', 'A partida já terminou. Clique em "Nova partida" para jogar novamente.');
  ExpectError(rrCellOccupied, 409, 'CELULA_OCUPADA', 'Esta célula já está ocupada.');
end;

{ ---- RJ-03 -------------------------------------------------------------------- }

procedure ExpectInvalid(const AText: string; const ALabel: string);
var
  M: TClientMessage;
begin
  Check(not ParseClientMessage(TEncoding.UTF8.GetBytes(AText), M), 'deveria ser invalida: ' + ALabel);
end;

procedure RJ03_ClientMessages;
var
  M: TClientMessage;
  Bad: TBytes;
begin
  Check(ParseClientMessage(TEncoding.UTF8.GetBytes('{"tipo":"entrar","protocolo":1,"sala":"K7PM2Q","token":"' + TOKEN + '"}'), M)
    and (M.Kind = cmEnter) and (M.Room = 'K7PM2Q') and (M.Token = TOKEN), 'entrar valido');
  Check(ParseClientMessage(TEncoding.UTF8.GetBytes(' {"token":"t","sala":"s","protocolo":1,"tipo":"entrar","extra":[1]} '), M)
    and (M.Kind = cmEnter) and (M.Room = 's') and (M.Token = 't'), 'entrar com campos em outra ordem e campo extra');
  Check(ParseClientMessage(TEncoding.UTF8.GetBytes('{"tipo":"ping","id":17}'), M) and (M.Kind = cmPing) and (M.PingId = 17), 'ping 17');
  Check(ParseClientMessage(TEncoding.UTF8.GetBytes('{"tipo":"ping","id":2147483647}'), M) and (M.PingId = 2147483647), 'ping no maximo');
  Check(ParseClientMessage(TEncoding.UTF8.GetBytes('{"tipo":"ping","id":0}'), M) and (M.PingId = 0), 'ping 0');

  ExpectInvalid('{"tipo":"jogada","posicao":0}', 'tipo jogada (CAO-28)');
  ExpectInvalid('{"tipo":"estado","sala":{"partida":{"vencedor":"X"}}}', 'tipo estado (CAO-28)');
  ExpectInvalid('{"tipo":"entrar","protocolo":1,"sala":"K7PM2Q"}', 'entrar sem token');
  ExpectInvalid('{"tipo":"entrar","protocolo":1,"token":"t"}', 'entrar sem sala');
  ExpectInvalid('{"tipo":"entrar","sala":"s","token":"t"}', 'entrar sem protocolo');
  ExpectInvalid('{"tipo":"entrar","protocolo":2,"sala":"s","token":"t"}', 'protocolo 2');
  ExpectInvalid('{"tipo":"entrar","protocolo":"1","sala":"s","token":"t"}', 'protocolo texto');
  ExpectInvalid('{"tipo":"entrar","protocolo":1,"sala":5,"token":"t"}', 'sala numero');
  ExpectInvalid('{"tipo":"ping","id":"7"}', 'id texto');
  ExpectInvalid('{"tipo":"ping","id":-1}', 'id negativo');
  ExpectInvalid('{"tipo":"ping","id":4.5}', 'id fracionario');
  ExpectInvalid('{"tipo":"ping","id":2147483648}', 'id acima de 32 bits');
  ExpectInvalid('{"tipo":"ping"}', 'ping sem id');
  ExpectInvalid('{"Tipo":"ping","id":1}', 'nome do campo com maiuscula');
  ExpectInvalid('{"tipo":1}', 'tipo numero');
  ExpectInvalid('[1]', 'array');
  ExpectInvalid('"x"', 'texto JSON');
  ExpectInvalid('{}', 'objeto vazio');
  ExpectInvalid('{"tipo":"ping","id":1', 'JSON malformado');
  ExpectInvalid('nao-json', 'texto que nao e JSON');
  ExpectInvalid('', 'vazio');
  Bad := TEncoding.UTF8.GetBytes('{"tipo":"ping","id":1}');
  Bad[9] := $FF;
  Check(not ParseClientMessage(Bad, M), 'deveria ser invalida: UTF-8 invalido');
end;

procedure RunRoomJsonTests;
begin
  RunCase('RJ-01', 'Objeto sala exato (campos, ordem, sem tokens) e respostas', RJ01_RoomJson);
  RunCase('RJ-02', 'Mensagens do servidor e tabela de erros', RJ02_ServerMessages);
  RunCase('RJ-03', 'Leitura das mensagens do cliente (validas e invalidas)', RJ03_ClientMessages);
end;

end.
