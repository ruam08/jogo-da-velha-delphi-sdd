unit uRoom;

{ Sala do modo online (docs/spec-online.md, secoes 5 e 7; docs/plan-online.md,
  secoes 5, 6.5 e 8).

  - Cada sala tem o seu proprio TGameEngine (DTO-04): as regras do jogo sao
    as do motor, sem alteracao.
  - Toda operacao executa inteira dentro da secao critica da sala e devolve o
    resultado e o estado lidos na mesma secao (RNO-11).
  - Toda mudanca aceita incrementa a versao em exatamente 1; recusas nao
    mudam nada (RNO-07).
  - O lugar de quem joga e sempre derivado do token; nenhum dado do cliente
    escolhe o simbolo (RNO-09, RN-07).
  - Acesso por interface (IRoom) com contagem de referencia (DTO-05).

  Sem dependencia de Indy, HTTP ou JSON. }

interface

uses
  System.SysUtils, System.SyncObjs, uGameEngine, uClock, uSecureRandom;

type
  TSeat = (seX, seO);
  TRoomSituation = (rsWaiting, rsPlaying, rsClosed);
  TCloseReason = (crNone, crLeave, crAbandoned);

  TSeatView = record
    Occupied: Boolean;
    Connected: Boolean;
  end;

  { Copia independente do estado da sala, sem tokens. }
  TRoomSnapshot = record
    Code: string;
    Situation: TRoomSituation;
    Version: Int64;
    GameNumber: Integer;
    Seats: array[TSeat] of TSeatView;
    Game: TGameSnapshot;
    CloseReason: TCloseReason;
  end;

  TRoomResult = (rrOk, rrNotFound, rrClosed, rrInvalidToken, rrFull,
    rrWaitingOpponent, rrInvalidPosition, rrGameOver, rrNotYourTurn,
    rrCellOccupied, rrGameInProgress, rrCapacity);

  TRoomOutcome = record
    Result: TRoomResult;
    { True quando a versao foi incrementada (e uma notificacao e devida). }
    Changed: Boolean;
    Snapshot: TRoomSnapshot;
  end;

  IRoom = interface
    ['{3C5B8E74-91A2-4D6F-8B0C-7E1F2A9D4B63}']
    function Code: string;
    { Entrada: com o token de um lugar, devolve o mesmo lugar (RNO-05);
      sem token valido, ocupa o lugar O se estiver livre (RNO-03). }
    function Join(const AToken: string; out ASeat: TSeat; out AIssuedToken: string): TRoomOutcome;
    function Play(const AToken: string; APosition: Integer): TRoomOutcome;
    function NewGame(const AToken: string): TRoomOutcome;
    function Leave(const AToken: string): TRoomOutcome;
    { Canal em tempo real identificado (O3). AReplacedId: canal anterior do
      mesmo lugar, ou 0. }
    function Attach(const AToken: string; AConnectionId: Int64; out ASeat: TSeat;
      out AReplacedId: Int64): TRoomOutcome;
    { Ignorado se AConnectionId nao for o canal atual do lugar (RNO-15). }
    function Detach(ASeat: TSeat; AConnectionId: Int64): TRoomOutcome;
    { Encerra por abandono se ninguem estiver conectado ha mais de ATtlMs. }
    function CloseAbandoned(ANowMs, ATtlMs: Int64): TRoomOutcome;
    function Snapshot: TRoomSnapshot;
    function IsClosed: Boolean;
    function AnyConnected: Boolean;
    function LastActivityMs: Int64;
  end;

  TSeatState = record
    Occupied: Boolean;
    Token: string;
    Connected: Boolean;
    ConnectionId: Int64;
  end;

  TRoom = class(TInterfacedObject, IRoom)
  private
    FLock: TCriticalSection;
    FCode: string;
    FClock: IClock;
    FRandom: IRandomSource;
    FEngine: TGameEngine;
    FSeats: array[TSeat] of TSeatState;
    FSituation: TRoomSituation;
    FCloseReason: TCloseReason;
    FVersion: Int64;
    FGameNumber: Integer;
    FLastActivity: Int64;
    function SeatOfToken(const AToken: string; out ASeat: TSeat): Boolean;
    function AnyConnectedLocked: Boolean;
    function SnapshotLocked: TRoomSnapshot;
    function Unchanged(AResult: TRoomResult): TRoomOutcome;
    function Accepted: TRoomOutcome;
    function DoJoin(const AToken: string; out ASeat: TSeat; out AIssuedToken: string): TRoomOutcome;
    function DoPlay(const AToken: string; APosition: Integer): TRoomOutcome;
    function DoNewGame(const AToken: string): TRoomOutcome;
    function DoLeave(const AToken: string): TRoomOutcome;
    function DoAttach(const AToken: string; AConnectionId: Int64; out ASeat: TSeat;
      out AReplacedId: Int64): TRoomOutcome;
    function DoDetach(ASeat: TSeat; AConnectionId: Int64): TRoomOutcome;
    function DoCloseAbandoned(ANowMs, ATtlMs: Int64): TRoomOutcome;
  public
    { O criador ocupa o lugar X com ACreatorToken (RNO-01). }
    constructor Create(const ACode, ACreatorToken: string; const AClock: IClock;
      const ARandom: IRandomSource);
    destructor Destroy; override;
    function Code: string;
    function Join(const AToken: string; out ASeat: TSeat; out AIssuedToken: string): TRoomOutcome;
    function Play(const AToken: string; APosition: Integer): TRoomOutcome;
    function NewGame(const AToken: string): TRoomOutcome;
    function Leave(const AToken: string): TRoomOutcome;
    function Attach(const AToken: string; AConnectionId: Int64; out ASeat: TSeat;
      out AReplacedId: Int64): TRoomOutcome;
    function Detach(ASeat: TSeat; AConnectionId: Int64): TRoomOutcome;
    function CloseAbandoned(ANowMs, ATtlMs: Int64): TRoomOutcome;
    function Snapshot: TRoomSnapshot;
    function IsClosed: Boolean;
    function AnyConnected: Boolean;
    function LastActivityMs: Int64;
  end;

function SeatToCell(ASeat: TSeat): TCell;
function SeatName(ASeat: TSeat): string;

implementation

function SeatToCell(ASeat: TSeat): TCell;
begin
  if ASeat = seX then
    Result := ceX
  else
    Result := ceO;
end;

function SeatName(ASeat: TSeat): string;
begin
  if ASeat = seX then
    Result := 'X'
  else
    Result := 'O';
end;

{ ---- TRoom ---------------------------------------------------------------- }

constructor TRoom.Create(const ACode, ACreatorToken: string; const AClock: IClock;
  const ARandom: IRandomSource);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FCode := ACode;
  FClock := AClock;
  FRandom := ARandom;
  FEngine := TGameEngine.Create;
  FSeats[seX].Occupied := True;
  FSeats[seX].Token := ACreatorToken;
  FSituation := rsWaiting;
  FCloseReason := crNone;
  FVersion := 1;
  FGameNumber := 1;
  FLastActivity := FClock.NowMs;
end;

destructor TRoom.Destroy;
begin
  FEngine.Free;
  FLock.Free;
  inherited;
end;

function TRoom.Code: string;
begin
  Result := FCode;
end;

{ ---- Auxiliares (chamados com a secao critica ja adquirida) -------------- }

function TRoom.SeatOfToken(const AToken: string; out ASeat: TSeat): Boolean;
begin
  ASeat := seX;
  Result := False;
  if AToken = '' then
    Exit;
  if FSeats[seX].Occupied and (AToken = FSeats[seX].Token) then
  begin
    ASeat := seX;
    Exit(True);
  end;
  if FSeats[seO].Occupied and (AToken = FSeats[seO].Token) then
  begin
    ASeat := seO;
    Exit(True);
  end;
end;

function TRoom.AnyConnectedLocked: Boolean;
begin
  Result := FSeats[seX].Connected or FSeats[seO].Connected;
end;

function TRoom.SnapshotLocked: TRoomSnapshot;
var
  Seat: TSeat;
begin
  Result.Code := FCode;
  Result.Situation := FSituation;
  Result.Version := FVersion;
  Result.GameNumber := FGameNumber;
  for Seat := Low(TSeat) to High(TSeat) do
  begin
    Result.Seats[Seat].Occupied := FSeats[Seat].Occupied;
    Result.Seats[Seat].Connected := FSeats[Seat].Connected;
  end;
  Result.Game := FEngine.GetSnapshot;   { copia (DT-18) }
  Result.CloseReason := FCloseReason;
end;

function TRoom.Unchanged(AResult: TRoomResult): TRoomOutcome;
begin
  Result.Result := AResult;
  Result.Changed := False;
  Result.Snapshot := SnapshotLocked;
end;

{ Registra uma mudanca aceita: versao +1 e atividade agora. }
function TRoom.Accepted: TRoomOutcome;
begin
  Inc(FVersion);
  FLastActivity := FClock.NowMs;
  Result.Result := rrOk;
  Result.Changed := True;
  Result.Snapshot := SnapshotLocked;
end;

{ ---- Operacoes (com a secao critica ja adquirida) ------------------------ }

function TRoom.DoJoin(const AToken: string; out ASeat: TSeat; out AIssuedToken: string): TRoomOutcome;
begin
  ASeat := seO;
  AIssuedToken := '';
  if FSituation = rsClosed then
    Exit(Unchanged(rrClosed));
  { Reentrada com o proprio token: mesmo lugar, nada muda (RNO-05). }
  if SeatOfToken(AToken, ASeat) then
  begin
    AIssuedToken := FSeats[ASeat].Token;
    Exit(Unchanged(rrOk));
  end;
  ASeat := seO;
  if FSeats[seO].Occupied then
    Exit(Unchanged(rrFull));
  repeat
    AIssuedToken := NewToken(FRandom);
  until AIssuedToken <> FSeats[seX].Token;
  FSeats[seO].Occupied := True;
  FSeats[seO].Token := AIssuedToken;
  FSituation := rsPlaying;
  Result := Accepted;
end;

{ Ordem da RNO-10 dentro da sala (os passos de corpo JSON ficam na API):
  encerrada -> token -> posicao -> dois jogadores -> partida em andamento ->
  vez do jogador -> celula vazia (no motor). }
function TRoom.DoPlay(const AToken: string; APosition: Integer): TRoomOutcome;
var
  Seat: TSeat;
  Game: TGameSnapshot;
  MoveResult: TMoveResult;
begin
  if FSituation = rsClosed then
    Exit(Unchanged(rrClosed));
  if not SeatOfToken(AToken, Seat) then
    Exit(Unchanged(rrInvalidToken));
  if (APosition < BOARD_FIRST) or (APosition > BOARD_LAST) then
    Exit(Unchanged(rrInvalidPosition));
  if FSituation <> rsPlaying then
    Exit(Unchanged(rrWaitingOpponent));
  Game := FEngine.GetSnapshot;
  if Game.Status <> gsInProgress then
    Exit(Unchanged(rrGameOver));
  if Game.CurrentPlayer <> SeatToCell(Seat) then
    Exit(Unchanged(rrNotYourTurn));
  MoveResult := FEngine.Play(APosition);
  case MoveResult of
    mrAccepted:
      Result := Accepted;
    mrCellOccupied:
      Result := Unchanged(rrCellOccupied);
    mrGameOver:
      Result := Unchanged(rrGameOver);
  else
    Result := Unchanged(rrInvalidPosition);
  end;
end;

function TRoom.DoNewGame(const AToken: string): TRoomOutcome;
var
  Seat: TSeat;
begin
  if FSituation = rsClosed then
    Exit(Unchanged(rrClosed));
  if not SeatOfToken(AToken, Seat) then
    Exit(Unchanged(rrInvalidToken));
  if FSituation <> rsPlaying then
    Exit(Unchanged(rrWaitingOpponent));
  if FEngine.GetSnapshot.Status = gsInProgress then
    Exit(Unchanged(rrGameInProgress));
  FEngine.Reset;
  Inc(FGameNumber);
  Result := Accepted;
end;

function TRoom.DoLeave(const AToken: string): TRoomOutcome;
var
  Seat: TSeat;
begin
  if FSituation = rsClosed then
    Exit(Unchanged(rrClosed));
  if not SeatOfToken(AToken, Seat) then
    Exit(Unchanged(rrInvalidToken));
  FSituation := rsClosed;
  FCloseReason := crLeave;
  Result := Accepted;
end;

function TRoom.DoAttach(const AToken: string; AConnectionId: Int64; out ASeat: TSeat;
  out AReplacedId: Int64): TRoomOutcome;
var
  WasConnected: Boolean;
begin
  AReplacedId := 0;
  ASeat := seX;
  if FSituation = rsClosed then
    Exit(Unchanged(rrClosed));
  if not SeatOfToken(AToken, ASeat) then
    Exit(Unchanged(rrInvalidToken));
  AReplacedId := FSeats[ASeat].ConnectionId;
  WasConnected := FSeats[ASeat].Connected;
  FSeats[ASeat].ConnectionId := AConnectionId;
  FSeats[ASeat].Connected := True;
  if WasConnected then
  begin
    { Substituicao (outra aba): o lugar continua conectado; nada a notificar. }
    FLastActivity := FClock.NowMs;
    Exit(Unchanged(rrOk));
  end;
  Result := Accepted;
end;

function TRoom.DoDetach(ASeat: TSeat; AConnectionId: Int64): TRoomOutcome;
begin
  if (AConnectionId = 0) or (FSeats[ASeat].ConnectionId <> AConnectionId) then
    Exit(Unchanged(rrOk));
  FSeats[ASeat].ConnectionId := 0;
  FSeats[ASeat].Connected := False;
  if FSituation = rsClosed then
  begin
    FLastActivity := FClock.NowMs;
    Exit(Unchanged(rrOk));
  end;
  Result := Accepted;
end;

function TRoom.DoCloseAbandoned(ANowMs, ATtlMs: Int64): TRoomOutcome;
begin
  if FSituation = rsClosed then
    Exit(Unchanged(rrClosed));
  if (not AnyConnectedLocked) and (ANowMs - FLastActivity > ATtlMs) then
  begin
    FSituation := rsClosed;
    FCloseReason := crAbandoned;
    Exit(Accepted);
  end;
  Result := Unchanged(rrOk);
end;

{ ---- Interface publica: cada chamada inteira na secao critica ------------- }

function TRoom.Join(const AToken: string; out ASeat: TSeat; out AIssuedToken: string): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoJoin(AToken, ASeat, AIssuedToken);
  finally
    FLock.Leave;
  end;
end;

function TRoom.Play(const AToken: string; APosition: Integer): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoPlay(AToken, APosition);
  finally
    FLock.Leave;
  end;
end;

function TRoom.NewGame(const AToken: string): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoNewGame(AToken);
  finally
    FLock.Leave;
  end;
end;

function TRoom.Leave(const AToken: string): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoLeave(AToken);
  finally
    FLock.Leave;
  end;
end;

function TRoom.Attach(const AToken: string; AConnectionId: Int64; out ASeat: TSeat;
  out AReplacedId: Int64): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoAttach(AToken, AConnectionId, ASeat, AReplacedId);
  finally
    FLock.Leave;
  end;
end;

function TRoom.Detach(ASeat: TSeat; AConnectionId: Int64): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoDetach(ASeat, AConnectionId);
  finally
    FLock.Leave;
  end;
end;

function TRoom.CloseAbandoned(ANowMs, ATtlMs: Int64): TRoomOutcome;
begin
  FLock.Enter;
  try
    Result := DoCloseAbandoned(ANowMs, ATtlMs);
  finally
    FLock.Leave;
  end;
end;

function TRoom.Snapshot: TRoomSnapshot;
begin
  FLock.Enter;
  try
    Result := SnapshotLocked;
  finally
    FLock.Leave;
  end;
end;

function TRoom.IsClosed: Boolean;
begin
  FLock.Enter;
  try
    Result := FSituation = rsClosed;
  finally
    FLock.Leave;
  end;
end;

function TRoom.AnyConnected: Boolean;
begin
  FLock.Enter;
  try
    Result := AnyConnectedLocked;
  finally
    FLock.Leave;
  end;
end;

function TRoom.LastActivityMs: Int64;
begin
  FLock.Enter;
  try
    Result := FLastActivity;
  finally
    FLock.Leave;
  end;
end;

end.
