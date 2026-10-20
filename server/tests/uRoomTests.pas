unit uRoomTests;

{ Casos SL do docs/test-plan-online.md (secao 5): dominio das salas
  (uRoom, uRoomRegistry, uSecureRandom, uClock), sem HTTP e sem rede.
  Tambem o MEM-01 (memoria devolvida ao fim das operacoes de sala). }

{$Q-}  { O gerador de teste depende de estouro aritmetico. }
{$R-}

interface

procedure RunRoomTests;

implementation

uses
  System.SysUtils, System.Generics.Collections, uMiniTest, uGameEngine,
  uClock, uSecureRandom, uRoom, uRoomRegistry, uRoomJson, uEngineTests;

{ ---- Gerador com bytes definidos pelo teste --------------------------------- }

type
  TScriptedRandom = class(TInterfacedObject, IRandomSource)
  private
    FQueue: TQueue<TBytes>;
    FSeed: Cardinal;
    FFillCount: Integer;
  public
    constructor Create(ASeed: Cardinal);
    destructor Destroy; override;
    { O proximo Fill usa estes bytes (repetidos ou cortados ao tamanho pedido). }
    procedure Push(const ABytes: TBytes);
    procedure Fill(var ABuffer: TBytes);
    property FillCount: Integer read FFillCount;
  end;

constructor TScriptedRandom.Create(ASeed: Cardinal);
begin
  inherited Create;
  FQueue := TQueue<TBytes>.Create;
  FSeed := ASeed;
end;

destructor TScriptedRandom.Destroy;
begin
  FQueue.Free;
  inherited;
end;

procedure TScriptedRandom.Push(const ABytes: TBytes);
begin
  FQueue.Enqueue(Copy(ABytes));
end;

procedure TScriptedRandom.Fill(var ABuffer: TBytes);
var
  Source: TBytes;
  I: Integer;
begin
  Inc(FFillCount);
  if FQueue.Count > 0 then
  begin
    Source := FQueue.Dequeue;
    for I := 0 to High(ABuffer) do
      if Length(Source) > 0 then
        ABuffer[I] := Source[I mod Length(Source)]
      else
        ABuffer[I] := 0;
    Exit;
  end;
  for I := 0 to High(ABuffer) do
  begin
    FSeed := FSeed * 1103515245 + 12345;
    ABuffer[I] := Byte(FSeed shr 16);
  end;
end;

function Zeros(ACount: Integer): TBytes;
begin
  SetLength(Result, ACount);
  if ACount > 0 then
    FillChar(Result[0], ACount, 0);
end;

{ ---- Texto do estado completo (comparar estes textos compara tudo) --------- }

function ResultStr(AResult: TRoomResult): string;
begin
  case AResult of
    rrOk: Result := 'rrOk';
    rrNotFound: Result := 'rrNotFound';
    rrClosed: Result := 'rrClosed';
    rrInvalidToken: Result := 'rrInvalidToken';
    rrFull: Result := 'rrFull';
    rrWaitingOpponent: Result := 'rrWaitingOpponent';
    rrInvalidPosition: Result := 'rrInvalidPosition';
    rrGameOver: Result := 'rrGameOver';
    rrNotYourTurn: Result := 'rrNotYourTurn';
    rrCellOccupied: Result := 'rrCellOccupied';
    rrGameInProgress: Result := 'rrGameInProgress';
  else
    Result := 'rrCapacity';
  end;
end;

function SeatStr(const AView: TSeatView): string;
begin
  Result := '';
  if AView.Occupied then Result := Result + 'ocupado' else Result := Result + 'livre';
  if AView.Connected then Result := Result + '+conectado';
end;

function ReasonStr(AReason: TCloseReason): string;
begin
  case AReason of
    crLeave: Result := 'SAIDA';
    crAbandoned: Result := 'ABANDONO';
  else
    Result := '-';
  end;
end;

function StateStr(const S: TRoomSnapshot): string;
begin
  Result := Format('cod=%s sit=%s v=%d n=%d X=%s O=%s fim=%s | %s',
    [S.Code, SituationText(S.Situation), S.Version, S.GameNumber,
     SeatStr(S.Seats[seX]), SeatStr(S.Seats[seO]), ReasonStr(S.CloseReason),
     SnapshotStr(S.Game)]);
end;

{ ---- Montagem de cenarios ----------------------------------------------------- }

type
  TPair2 = record
    Room: IRoom;
    TokenX: string;
    TokenO: string;
  end;

function NewRegistry(const AClock: IClock = nil; const ARandom: IRandomSource = nil;
  AMaxRooms: Integer = 1000; ARememberMs: Int64 = 3600000): TRoomRegistry;
var
  Clock: IClock;
  Rnd: IRandomSource;
begin
  Clock := AClock;
  if Clock = nil then
    Clock := TManualClock.Create;
  Rnd := ARandom;
  if Rnd = nil then
    Rnd := TSystemRandom.Create;
  Result := TRoomRegistry.Create(Clock, Rnd, AMaxRooms, ARememberMs);
end;

{ Sala criada por X; com AWithO, O tambem entra. }
function NewRoom(ARegistry: TRoomRegistry; AWithO: Boolean): TPair2;
var
  Seat: TSeat;
  Outcome: TRoomOutcome;
begin
  Result.TokenO := '';
  if ARegistry.CreateRoom(Result.Room, Result.TokenX) <> rrOk then
    raise Exception.Create('CreateRoom falhou ao montar o cenario');
  if AWithO then
  begin
    Outcome := Result.Room.Join('', Seat, Result.TokenO);
    if (Outcome.Result <> rrOk) or (Seat <> seO) then
      raise Exception.Create('Join falhou ao montar o cenario');
  end;
end;

{ Jogadas alternadas (a partir de X, ou de O com AFirstIsO); cada uma precisa
  ser aceita. }
procedure PlayAll(const P: TPair2; const AMoves: array of Integer; const AContext: string;
  AFirstIsO: Boolean = False);
var
  I: Integer;
  Token: string;
  Outcome: TRoomOutcome;
begin
  for I := 0 to High(AMoves) do
  begin
    if (I mod 2 = 0) <> AFirstIsO then Token := P.TokenX else Token := P.TokenO;
    Outcome := P.Room.Play(Token, AMoves[I]);
    if Outcome.Result <> rrOk then
      Check(False, Format('%s: jogada %d (posicao %d) recusada com %s',
        [AContext, I + 1, AMoves[I], ResultStr(Outcome.Result)]));
  end;
end;

{ A operacao precisa ser recusada com AExpected, sem mudar a sala. }
procedure ExpectRefused(const ARoom: IRoom; const AOutcome: TRoomOutcome;
  const ABefore: string; AExpected: TRoomResult; const AContext: string);
begin
  CheckEqualsStr(ResultStr(AExpected), ResultStr(AOutcome.Result), AContext + ': resultado');
  Check(not AOutcome.Changed, AContext + ': Changed deveria ser False');
  CheckEqualsStr(ABefore, StateStr(AOutcome.Snapshot), AContext + ': estado devolvido');
  CheckEqualsStr(ABefore, StateStr(ARoom.Snapshot), AContext + ': estado da sala');
end;

const
  INITIAL_GAME = 'tab=......... status=EM_ANDAMENTO vez=X venc=- cel=[]';
  S_L1: array[0..4] of Integer = (0, 3, 1, 4, 2);          { X vence 0-1-2 }
  S_L3: array[0..5] of Integer = (0, 6, 1, 7, 4, 8);       { O vence 6-7-8 }
  S_EMP: array[0..8] of Integer = (0, 1, 2, 4, 3, 5, 7, 6, 8);

{ ---- SL-01 ------------------------------------------------------------------ }

procedure SL01_CreateRoom;
var
  Reg: TRoomRegistry;
  Room: IRoom;
  Token: string;
  S: TRoomSnapshot;
begin
  Reg := NewRegistry;
  try
    CheckEqualsStr('rrOk', ResultStr(Reg.CreateRoom(Room, Token)), 'CreateRoom');
    if Room = nil then
    begin
      Check(False, 'CreateRoom nao devolveu a sala');
      Exit;
    end;
    S := Room.Snapshot;
    Check(IsValidRoomCode(S.Code), 'codigo fora do formato: "' + S.Code + '"');
    CheckEqualsStr(S.Code, Room.Code, 'Room.Code = codigo do estado');
    Check(IsValidTokenFormat(Token), 'token fora do formato (32 hex): "' + Token + '"');
    CheckEqualsStr('cod=' + S.Code + ' sit=AGUARDANDO_OPONENTE v=1 n=1 X=ocupado O=livre fim=- | ' + INITIAL_GAME,
      StateStr(S), 'estado inicial da sala');
    CheckEqualsInt(1, Reg.OpenCount, 'salas abertas');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-02 ------------------------------------------------------------------ }

procedure SL02_UniqueCodes;
var
  Reg: TRoomRegistry;
  Rnd: TScriptedRandom;
  RndRef: IRandomSource;
  A, B, C: TPair2;
  Codes: TDictionary<string, Boolean>;
  Room: IRoom;
  Token: string;
  I, Duplicates, Malformed: Integer;
begin
  { Colisao forcada: 16 bytes zero geram o codigo "222222". }
  Rnd := TScriptedRandom.Create(12345);
  RndRef := Rnd;
  Reg := NewRegistry(nil, RndRef);
  try
    Rnd.Push(Zeros(16));
    A := NewRoom(Reg, False);
    CheckEqualsStr('222222', A.Room.Code, 'sala A com o codigo forcado');
    Rnd.Push(Zeros(16));
    B := NewRoom(Reg, False);
    Check(B.Room.Code <> '222222', 'sala B repetiu o codigo de uma sala ativa');
    Check(IsValidRoomCode(B.Room.Code), 'codigo da sala B fora do formato');

    { Sala A encerrada e lembrada: o codigo continua reservado. }
    A.Room.Leave(A.TokenX);
    Reg.Sweep(MaxInt);
    CheckEqualsInt(1, Reg.RememberedCount, 'salas lembradas depois do Sweep');
    Rnd.Push(Zeros(16));
    C := NewRoom(Reg, False);
    Check(C.Room.Code <> '222222', 'sala C repetiu o codigo de uma sala lembrada');
  finally
    Reg.Free;
  end;

  { 10.000 salas com o gerador real: todos os codigos distintos. }
  Reg := NewRegistry(nil, nil, 20000);
  Codes := TDictionary<string, Boolean>.Create;
  try
    Duplicates := 0;
    Malformed := 0;
    for I := 1 to 10000 do
    begin
      if Reg.CreateRoom(Room, Token) <> rrOk then
      begin
        Check(False, Format('CreateRoom recusou a sala %d', [I]));
        Break;
      end;
      if not IsValidRoomCode(Room.Code) then
        Inc(Malformed);
      if Codes.ContainsKey(Room.Code) then
        Inc(Duplicates)
      else
        Codes.Add(Room.Code, True);
    end;
    CheckEqualsInt(0, Duplicates, 'codigos repetidos em 10.000 salas');
    CheckEqualsInt(0, Malformed, 'codigos fora do formato');
    CheckEqualsInt(10000, Reg.OpenCount, 'salas abertas');
    Note(Format('%d codigos distintos', [Codes.Count]));
  finally
    Codes.Free;
    Reg.Free;
  end;
end;

{ ---- SL-03 ------------------------------------------------------------------ }

procedure SL03_Join;
var
  Reg: TRoomRegistry;
  P: TPair2;
  Seat: TSeat;
  Token, Before: string;
  O: TRoomOutcome;
begin
  Reg := NewRegistry;
  try
    P := NewRoom(Reg, False);
    O := P.Room.Join('', Seat, Token);
    CheckEqualsStr('rrOk', ResultStr(O.Result), 'entrada de O');
    Check(O.Changed, 'entrada de O deveria mudar a sala');
    Check(Seat = seO, 'quem entra deveria ser O');
    Check(IsValidTokenFormat(Token), 'token de O fora do formato');
    Check(Token <> P.TokenX, 'token de O igual ao de X');
    CheckEqualsStr('cod=' + P.Room.Code + ' sit=EM_JOGO v=2 n=1 X=ocupado O=ocupado fim=- | ' + INITIAL_GAME,
      StateStr(O.Snapshot), 'estado depois da entrada');
    P.TokenO := Token;

    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Join('', Seat, Token), Before, rrFull, 'terceiro sem token');
    CheckEqualsStr('', Token, 'sala cheia nao entrega token');
    ExpectRefused(P.Room, P.Room.Join(StringOfChar('a', 32), Seat, Token), Before, rrFull, 'terceiro com token desconhecido');

    O := P.Room.Join(P.TokenO, Seat, Token);
    CheckEqualsStr('rrOk', ResultStr(O.Result), 'reentrada de O');
    Check(not O.Changed, 'reentrada de O nao deveria mudar a sala');
    Check(Seat = seO, 'reentrada de O devolve o lugar O');
    CheckEqualsStr(P.TokenO, Token, 'reentrada de O devolve o mesmo token');
    CheckEqualsStr(Before, StateStr(P.Room.Snapshot), 'sala depois da reentrada de O');

    O := P.Room.Join(P.TokenX, Seat, Token);
    Check((O.Result = rrOk) and not O.Changed and (Seat = seX) and (Token = P.TokenX),
      'reentrada de X devolve o lugar X e o mesmo token, sem mudar a sala');

    P.Room.Leave(P.TokenX);
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Join('', Seat, Token), Before, rrClosed, 'entrada em sala encerrada');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-04: validacao e precedencia (tabela P do test-plan-online, OR-08) ----- }

procedure SL04_Validation;
var
  Reg: TRoomRegistry;
  P: TPair2;
  Before: string;
  Pos: Integer;
const
  WRONG = 'ffffffffffffffffffffffffffffffff';
begin
  Reg := NewRegistry;
  try
    { P-01: sala encerrada + token invalido + posicao 9 -> encerrada. }
    P := NewRoom(Reg, True);
    P.Room.Leave(P.TokenX);
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(WRONG, 9), Before, rrClosed, 'P-01');

    { P-02: em jogo + token invalido + posicao 9 -> token. }
    P := NewRoom(Reg, True);
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(WRONG, 9), Before, rrInvalidToken, 'P-02');
    { P-03 (corpo que nao e JSON) e verificado na API (O2): o dominio recebe a posicao ja lida. }

    { P-04 e P-05: aguardando oponente. }
    P := NewRoom(Reg, False);
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 9), Before, rrInvalidPosition, 'P-04');
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, -1), Before, rrInvalidPosition, 'P-04 (-1)');
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 0), Before, rrWaitingOpponent, 'P-05 (CAO-19)');

    { P-06 e P-07: vitoria de X. }
    P := NewRoom(Reg, True);
    PlayAll(P, S_L1, 'S-L1');
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 0), Before, rrGameOver, 'P-06');
    ExpectRefused(P.Room, P.Room.Play(P.TokenO, 9), Before, rrInvalidPosition, 'P-07');
    for Pos := 5 to 8 do
    begin
      ExpectRefused(P.Room, P.Room.Play(P.TokenX, Pos), Before, rrGameOver, Format('vitoria, X em %d (CAO-18)', [Pos]));
      ExpectRefused(P.Room, P.Room.Play(P.TokenO, Pos), Before, rrGameOver, Format('vitoria, O em %d (CAO-18)', [Pos]));
    end;

    { Empate: todas as celulas, pelos dois -> partida encerrada. }
    P := NewRoom(Reg, True);
    PlayAll(P, S_EMP, 'S-EMP');
    Before := StateStr(P.Room.Snapshot);
    Check(P.Room.Snapshot.Game.Status = gsDraw, 'S-EMP deveria terminar empatada');
    for Pos := 0 to 8 do
      ExpectRefused(P.Room, P.Room.Play(P.TokenO, Pos), Before, rrGameOver, Format('empate, O em %d (CAO-18)', [Pos]));

    { P-08 e P-09: X:0, vez de O. }
    P := NewRoom(Reg, True);
    PlayAll(P, [0], 'X:0');
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 0), Before, rrNotYourTurn, 'P-08');
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 1), Before, rrNotYourTurn, 'fora da vez em celula vazia (CAO-16)');
    ExpectRefused(P.Room, P.Room.Play(P.TokenO, 0), Before, rrCellOccupied, 'P-09 (CAO-17)');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-05: jogada aceita usa o simbolo do lugar ------------------------------ }

procedure SL05_AcceptedMove;
var
  Reg: TRoomRegistry;
  P: TPair2;
  O: TRoomOutcome;
  I: Integer;
  Version: Int64;
  Token: string;
begin
  Reg := NewRegistry;
  try
    P := NewRoom(Reg, True);
    O := P.Room.Play(P.TokenX, 0);
    Check((O.Result = rrOk) and O.Changed, 'X em 0 deveria ser aceita e mudar a sala');
    CheckEqualsStr('tab=X........ status=EM_ANDAMENTO vez=O venc=- cel=[]', SnapshotStr(O.Snapshot.Game), 'depois de X:0');
    CheckEqualsInt(3, Integer(O.Snapshot.Version), 'versao depois de X:0');
    O := P.Room.Play(P.TokenO, 4);
    CheckEqualsStr('tab=X...O.... status=EM_ANDAMENTO vez=X venc=- cel=[]', SnapshotStr(O.Snapshot.Game), 'depois de O:4');
    CheckEqualsStr(StateStr(O.Snapshot), StateStr(P.Room.Snapshot), 'estado devolvido = estado da sala');

    { S-L3 (vitoria de O): cada jogada aceita sobe a versao em exatamente 1. }
    P := NewRoom(Reg, True);
    Version := P.Room.Snapshot.Version;
    for I := 0 to High(S_L3) do
    begin
      if I mod 2 = 0 then Token := P.TokenX else Token := P.TokenO;
      O := P.Room.Play(Token, S_L3[I]);
      Check(O.Result = rrOk, Format('S-L3, jogada %d recusada: %s', [I + 1, ResultStr(O.Result)]));
      CheckEqualsInt(Integer(Version + 1), Integer(O.Snapshot.Version), Format('versao na jogada %d', [I + 1]));
      Version := O.Snapshot.Version;
    end;
    CheckEqualsStr('tab=XX..X.OOO status=VITORIA vez=- venc=O cel=[6,7,8]', SnapshotStr(P.Room.Snapshot.Game), 'S-L3');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-06: salas isoladas ---------------------------------------------------- }

procedure SL06_Isolation;
var
  Reg: TRoomRegistry;
  S1, S2: TPair2;
  Before: string;
begin
  Reg := NewRegistry;
  try
    S1 := NewRoom(Reg, True);
    S2 := NewRoom(Reg, True);
    PlayAll(S2, [0], 'S2 X:0');
    Before := StateStr(S2.Room.Snapshot);

    PlayAll(S1, S_L1, 'S1 S-L1');
    CheckEqualsStr(Before, StateStr(S2.Room.Snapshot), 'S2 depois da partida em S1 (CAO-09)');
    S1.Room.NewGame(S1.TokenO);
    CheckEqualsStr(Before, StateStr(S2.Room.Snapshot), 'S2 depois da nova partida em S1 (CAO-41)');
    PlayAll(S1, [4, 0], 'S1 nova partida');
    CheckEqualsStr(Before, StateStr(S2.Room.Snapshot), 'S2 depois das jogadas em S1');
    CheckEqualsStr('tab=O...X.... status=EM_ANDAMENTO vez=X venc=- cel=[]', SnapshotStr(S1.Room.Snapshot.Game), 'S1');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-07: tokens ------------------------------------------------------------- }

procedure SL07_Tokens;
var
  Reg: TRoomRegistry;
  S1, S2: TPair2;
  Before: string;
  Bad: array of string;
  I: Integer;
  Seat: TSeat;
  Replaced: Int64;
begin
  Reg := NewRegistry;
  try
    S1 := NewRoom(Reg, True);
    S2 := NewRoom(Reg, True);
    SetLength(Bad, 5);
    Bad[0] := '';
    Bad[1] := Copy(S1.TokenX, 1, 31);
    Bad[2] := S1.TokenX + 'a';
    Bad[3] := UpperCase(S1.TokenX);
    Bad[4] := S2.TokenX;               { token de outra sala (CAO-11) }
    Before := StateStr(S1.Room.Snapshot);
    for I := 0 to High(Bad) do
    begin
      ExpectRefused(S1.Room, S1.Room.Play(Bad[I], 0), Before, rrInvalidToken, Format('Play com token %d', [I]));
      ExpectRefused(S1.Room, S1.Room.NewGame(Bad[I]), Before, rrInvalidToken, Format('NewGame com token %d', [I]));
      ExpectRefused(S1.Room, S1.Room.Leave(Bad[I]), Before, rrInvalidToken, Format('Leave com token %d', [I]));
      ExpectRefused(S1.Room, S1.Room.Attach(Bad[I], 99, Seat, Replaced), Before, rrInvalidToken, Format('Attach com token %d', [I]));
    end;
    Check(S1.TokenX <> S2.TokenX, 'salas diferentes com o mesmo token de X');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-08: nova partida ------------------------------------------------------- }

procedure SL08_NewGame;
var
  Reg: TRoomRegistry;
  P, W: TPair2;
  O: TRoomOutcome;
  Before: string;
begin
  Reg := NewRegistry;
  try
    W := NewRoom(Reg, False);
    Before := StateStr(W.Room.Snapshot);
    ExpectRefused(W.Room, W.Room.NewGame(W.TokenX), Before, rrWaitingOpponent, 'nova partida sem oponente');

    P := NewRoom(Reg, True);
    PlayAll(P, [0], 'X:0');
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.NewGame(P.TokenO), Before, rrGameInProgress, 'nova partida em andamento (CAO-40)');

    PlayAll(P, [3, 1, 4, 2], 'resto de S-L1', True);
    O := P.Room.NewGame(P.TokenO);
    Check((O.Result = rrOk) and O.Changed, 'nova partida depois da vitoria, pedida por O');
    CheckEqualsStr(INITIAL_GAME, SnapshotStr(O.Snapshot.Game), 'partida depois da nova partida');
    CheckEqualsInt(2, O.Snapshot.GameNumber, 'numero da partida');
    Check(O.Snapshot.Seats[seX].Occupied and O.Snapshot.Seats[seO].Occupied, 'os dois lugares continuam ocupados');
    ExpectRefused(P.Room, P.Room.Play(P.TokenO, 0), StateStr(P.Room.Snapshot), rrNotYourTurn, 'X comeca a nova partida');
    PlayAll(P, S_EMP, 'S-EMP');
    O := P.Room.NewGame(P.TokenX);
    Check(O.Result = rrOk, 'nova partida depois do empate, pedida por X');
    CheckEqualsInt(3, O.Snapshot.GameNumber, 'numero da partida depois do empate');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-09: presenca e lugar reservado ---------------------------------------- }

procedure SL09_Presence;
var
  Reg: TRoomRegistry;
  P: TPair2;
  O: TRoomOutcome;
  Seat: TSeat;
  Replaced: Int64;
  Version: Int64;
  Before, Token: string;
begin
  Reg := NewRegistry;
  try
    P := NewRoom(Reg, True);
    Version := P.Room.Snapshot.Version;
    O := P.Room.Attach(P.TokenX, 101, Seat, Replaced);
    Check((O.Result = rrOk) and O.Changed and (Seat = seX) and (Replaced = 0), 'primeiro canal de X');
    Check(O.Snapshot.Seats[seX].Connected, 'X conectado');
    CheckEqualsInt(Integer(Version + 1), Integer(O.Snapshot.Version), 'versao depois da conexao');

    O := P.Room.Attach(P.TokenX, 102, Seat, Replaced);
    Check((O.Result = rrOk) and not O.Changed and (Replaced = 101), 'segundo canal de X substitui o primeiro sem mudar a versao (CAO-36)');
    O := P.Room.Detach(seX, 101);
    Check(not O.Changed and O.Snapshot.Seats[seX].Connected, 'fim do canal substituido nao desconecta X');
    O := P.Room.Detach(seX, 102);
    Check(O.Changed and not O.Snapshot.Seats[seX].Connected and O.Snapshot.Seats[seX].Occupied,
      'fim do canal atual desconecta X e mantem o lugar (CAO-32)');

    { O desconectado na sua vez: lugar reservado (CAO-37). }
    PlayAll(P, [0], 'X:0');
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 1), Before, rrNotYourTurn, 'X na vez de O desconectado');
    ExpectRefused(P.Room, P.Room.Join('', Seat, Token), Before, rrFull, 'terceiro com O desconectado');
    O := P.Room.Attach(P.TokenO, 201, Seat, Replaced);
    Check((O.Result = rrOk) and (Seat = seO) and O.Snapshot.Seats[seO].Connected, 'O reconecta');
    O := P.Room.Play(P.TokenO, 1);
    Check(O.Result = rrOk, 'O joga depois de reconectar');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-10: saida -------------------------------------------------------------- }

procedure SL10_Leave;
var
  Reg: TRoomRegistry;
  P: TPair2;
  O: TRoomOutcome;
  Room: IRoom;
  Before, Token: string;
  Seat: TSeat;
  Replaced: Int64;
begin
  Reg := NewRegistry;
  try
    P := NewRoom(Reg, True);
    O := P.Room.Leave(P.TokenO);
    Check((O.Result = rrOk) and O.Changed, 'saida de O');
    CheckEqualsStr('ENCERRADA', SituationText(O.Snapshot.Situation), 'situacao depois da saida');
    CheckEqualsStr('SAIDA', ReasonStr(O.Snapshot.CloseReason), 'motivo do encerramento');
    Before := StateStr(P.Room.Snapshot);
    ExpectRefused(P.Room, P.Room.Play(P.TokenX, 0), Before, rrClosed, 'jogar depois da saida');
    ExpectRefused(P.Room, P.Room.NewGame(P.TokenX), Before, rrClosed, 'nova partida depois da saida');
    ExpectRefused(P.Room, P.Room.Leave(P.TokenX), Before, rrClosed, 'sair de novo');
    ExpectRefused(P.Room, P.Room.Join('', Seat, Token), Before, rrClosed, 'entrar depois da saida');
    ExpectRefused(P.Room, P.Room.Attach(P.TokenX, 5, Seat, Replaced), Before, rrClosed, 'conectar depois da saida');

    CheckEqualsStr('rrClosed', ResultStr(Reg.Find(P.Room.Code, Room)), 'Find antes do Sweep');
    Reg.Sweep(MaxInt);
    CheckEqualsInt(0, Reg.OpenCount, 'salas abertas depois do Sweep');
    CheckEqualsInt(1, Reg.RememberedCount, 'salas lembradas depois do Sweep');
    CheckEqualsStr('rrClosed', ResultStr(Reg.Find(P.Room.Code, Room)), 'Find depois do Sweep (CAO-31)');
    CheckEqualsStr('rrClosed', ResultStr(Reg.Find('  ' + LowerCase(P.Room.Code) + ' ', Room)), 'Find com codigo em minusculas e espacos');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-11: abandono e periodo de lembranca (relogio manual) ------------------ }

procedure SL11_Abandoned;
var
  Clock: TManualClock;
  ClockRef: IClock;
  Reg: TRoomRegistry;
  A, B: TPair2;
  Room: IRoom;
  Closed: TArray<TRoomSnapshot>;
  Seat: TSeat;
  Replaced: Int64;
begin
  Clock := TManualClock.Create(10000);
  ClockRef := Clock;
  Reg := NewRegistry(ClockRef, nil, 100, 3000);
  try
    A := NewRoom(Reg, True);
    B := NewRoom(Reg, True);
    B.Room.Attach(B.TokenX, 1, Seat, Replaced);

    Clock.Advance(500);
    Closed := Reg.Sweep(1000);
    CheckEqualsInt(0, Length(Closed), 'nenhuma sala encerrada antes do limite');
    Clock.Advance(600);
    Closed := Reg.Sweep(1000);
    CheckEqualsInt(1, Length(Closed), 'uma sala encerrada depois do limite');
    if Length(Closed) = 1 then
    begin
      CheckEqualsStr(A.Room.Code, Closed[0].Code, 'a sala encerrada e a sem conexoes');
      CheckEqualsStr('ABANDONO', ReasonStr(Closed[0].CloseReason), 'motivo');
    end;
    CheckEqualsStr('rrClosed', ResultStr(Reg.Find(A.Room.Code, Room)), 'sala abandonada: encerrada (CAO-38)');
    CheckEqualsStr('rrOk', ResultStr(Reg.Find(B.Room.Code, Room)), 'sala com X conectado continua aberta');

    Clock.Advance(3100);
    Reg.Sweep(1000);
    CheckEqualsStr('rrNotFound', ResultStr(Reg.Find(A.Room.Code, Room)), 'depois do periodo de lembranca: inexistente');
    CheckEqualsStr('rrOk', ResultStr(Reg.Find(B.Room.Code, Room)), 'sala conectada nunca expira');

    { Depois que X sai do canal, o limite conta a partir da desconexao. }
    B.Room.Detach(seX, 1);
    Clock.Advance(900);
    CheckEqualsInt(0, Length(Reg.Sweep(1000)), 'B logo depois da desconexao');
    Clock.Advance(200);
    CheckEqualsInt(1, Length(Reg.Sweep(1000)), 'B depois do limite contado da desconexao');
  finally
    Reg.Free;
  end;
end;

{ ---- SL-12: capacidade --------------------------------------------------------- }

procedure SL12_Capacity;
var
  Reg: TRoomRegistry;
  Rooms: array[0..2] of TPair2;
  Room: IRoom;
  Token: string;
  I: Integer;
begin
  Reg := NewRegistry(nil, nil, 3);
  try
    for I := 0 to 2 do
      Rooms[I] := NewRoom(Reg, False);
    CheckEqualsStr('rrCapacity', ResultStr(Reg.CreateRoom(Room, Token)), 'quarta sala com limite 3 (CAO-53)');
    Check((Room = nil) and (Token = ''), 'sem sala nem token quando o limite e atingido');
    Rooms[0].Room.Leave(Rooms[0].TokenX);
    CheckEqualsStr('rrOk', ResultStr(Reg.CreateRoom(Room, Token)), 'depois de encerrar uma, a criacao volta a funcionar');
  finally
    Reg.Free;
  end;
end;

{ ---- MEM-01 -------------------------------------------------------------------- }

function AllocatedBytes: Int64;
var
  State: TMemoryManagerState;
  I: Integer;
begin
  GetMemoryManagerState(State);
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(Result, Int64(State.SmallBlockTypeStates[I].InternalBlockSize) *
      Int64(State.SmallBlockTypeStates[I].AllocatedBlockCount));
end;

procedure RoomWorkload;
var
  Reg: TRoomRegistry;
  P: TPair2;
  Room: IRoom;
  Seat: TSeat;
  Replaced: Int64;
  I: Integer;
  Text: string;
begin
  Reg := NewRegistry(nil, nil, 1000, 0);
  try
    for I := 1 to 200 do
    begin
      P := NewRoom(Reg, True);
      P.Room.Attach(P.TokenX, I, Seat, Replaced);
      PlayAll(P, S_L1, 'carga');
      P.Room.NewGame(P.TokenO);
      P.Room.Detach(seX, I);
      Text := RoomToJson(P.Room.Snapshot) + PlayerResponseJson(P.Room.Snapshot, seO, P.TokenO);
      if Text = '' then
        raise Exception.Create('JSON vazio');
      if I mod 2 = 0 then
        P.Room.Leave(P.TokenX);
      Reg.Find(P.Room.Code, Room);
    end;
    Reg.Sweep(0);
    Reg.Sweep(0);
  finally
    P.Room := nil;
    Room := nil;
    Reg.Free;
  end;
end;

procedure MEM01_NoLeaks;
var
  Before, After: Int64;
begin
  RoomWorkload;            { aquecimento: inicializacoes unicas da RTL }
  Before := AllocatedBytes;
  RoomWorkload;
  After := AllocatedBytes;
  Note(Format('memoria alocada antes %d bytes, depois %d bytes (diferenca %d)', [Before, After, After - Before]));
  Check(After - Before <= 1024, Format('200 salas criadas e liberadas deixaram %d bytes alocados', [After - Before]));
end;

procedure RunRoomTests;
begin
  RunCase('SL-01', 'Criar sala: codigo, token, X, aguardando, versao 1', SL01_CreateRoom);
  RunCase('SL-02', 'Codigos unicos (colisao forcada e 10.000 salas)', SL02_UniqueCodes);
  RunCase('SL-03', 'Entrar: O, sala cheia, reentrada, sala encerrada', SL03_Join);
  RunCase('SL-04', 'Validacao da jogada e ordem de precedencia (P-01 a P-09)', SL04_Validation);
  RunCase('SL-05', 'Jogada aceita usa o simbolo do lugar; versao +1', SL05_AcceptedMove);
  RunCase('SL-06', 'Salas isoladas', SL06_Isolation);
  RunCase('SL-07', 'Tokens invalidos e de outra sala', SL07_Tokens);
  RunCase('SL-08', 'Nova partida: so depois do fim, X comeca, numero +1', SL08_NewGame);
  RunCase('SL-09', 'Presenca, substituicao de canal e lugar reservado', SL09_Presence);
  RunCase('SL-10', 'Saida encerra a sala; sala lembrada', SL10_Leave);
  RunCase('SL-11', 'Abandono e periodo de lembranca (relogio manual)', SL11_Abandoned);
  RunCase('SL-12', 'Limite de salas abertas', SL12_Capacity);
  RunCase('MEM-01', 'Memoria devolvida depois de 200 salas', MEM01_NoLeaks);
end;

end.
