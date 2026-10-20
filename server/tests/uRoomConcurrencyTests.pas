unit uRoomConcurrencyTests;

{ Casos SC do docs/test-plan-online.md (secao 5): secoes criticas da sala e do
  registro sob acesso simultaneo, sem HTTP. }

{$Q-}  { O gerador pseudoaleatorio abaixo depende de estouro aritmetico. }
{$R-}

interface

procedure RunRoomConcurrencyTests;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs, System.Math,
  uMiniTest, uGameEngine, uClock, uSecureRandom, uRoom, uRoomRegistry;

{ Devolve '' se a partida e coerente com as regras, ou o motivo. }
function CoherenceProblem(const S: TGameSnapshot): string;
var
  I, Xs, Os, Empty: Integer;
begin
  Xs := 0;
  Os := 0;
  Empty := 0;
  for I := 0 to 8 do
    case S.Board[I] of
      ceX: Inc(Xs);
      ceO: Inc(Os);
    else
      Inc(Empty);
    end;
  if (Xs - Os < 0) or (Xs - Os > 1) then
    Exit(Format('X=%d e O=%d', [Xs, Os]));
  case S.Status of
    gsInProgress:
      begin
        if (Xs = Os) and (S.CurrentPlayer <> ceX) then
          Exit('em andamento com X=O, mas a vez nao e de X');
        if (Xs > Os) and (S.CurrentPlayer <> ceO) then
          Exit('em andamento com X>O, mas a vez nao e de O');
        if (S.Winner <> ceEmpty) or (Length(S.WinningCells) <> 0) then
          Exit('em andamento com vencedor');
        if Empty = 0 then
          Exit('em andamento com tabuleiro cheio');
      end;
    gsWin:
      begin
        if (S.CurrentPlayer <> ceEmpty) or (S.Winner = ceEmpty) then
          Exit('vitoria com vez ou sem vencedor');
        if (Length(S.WinningCells) <> 3) and (Length(S.WinningCells) <> 5) then
          Exit('vitoria com celulas vencedoras erradas');
        for I := 0 to High(S.WinningCells) do
          if S.Board[S.WinningCells[I]] <> S.Winner then
            Exit('celula vencedora sem o simbolo do vencedor');
      end;
  else
    if (S.CurrentPlayer <> ceEmpty) or (S.Winner <> ceEmpty) or (Empty <> 0) then
      Exit('empate incoerente');
  end;
  Result := '';
end;

type
  { Base: gerador proprio por thread e registro de problemas. }
  TWorker = class(TThread)
  protected
    FSeed: Cardinal;
    FOperations: Integer;
    FChanges: Integer;
    FProblems: Integer;
    FFirstProblem: string;
    function NextRandom: Cardinal;
    procedure Report(const AProblem: string);
  public
    constructor Create(ASeed: Cardinal);
    property Operations: Integer read FOperations;
    property Changes: Integer read FChanges;
    property Problems: Integer read FProblems;
    property FirstProblem: string read FFirstProblem;
  end;

constructor TWorker.Create(ASeed: Cardinal);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSeed := ASeed;
end;

function TWorker.NextRandom: Cardinal;
begin
  FSeed := FSeed * 1103515245 + 12345;
  Result := (FSeed shr 8) and $FFFFFF;
end;

procedure TWorker.Report(const AProblem: string);
begin
  Inc(FProblems);
  if FFirstProblem = '' then
    FFirstProblem := AProblem;
end;

{ Verifica uma resposta de jogada: estado coerente e, se aceita, a celula com
  o simbolo de quem jogou (detecta jogada fora da vez e corrida). }
function CheckPlay(const AOutcome: TRoomOutcome; APosition: Integer;
  AExpected: TCell; const ACode: string; ALastVersion: Int64): string;
begin
  Result := '';
  if AOutcome.Snapshot.Code <> ACode then
    Exit(Format('resposta com o codigo %s em vez de %s', [AOutcome.Snapshot.Code, ACode]));
  Result := CoherenceProblem(AOutcome.Snapshot.Game);
  if Result <> '' then
    Exit;
  if AOutcome.Snapshot.Version < ALastVersion then
    Exit(Format('versao voltou de %d para %d', [ALastVersion, AOutcome.Snapshot.Version]));
  if AOutcome.Changed and (AOutcome.Snapshot.Version <= ALastVersion) then
    Exit(Format('mudanca sem versao nova (%d)', [AOutcome.Snapshot.Version]));
  if (AOutcome.Result = rrOk) and AOutcome.Changed and (APosition >= 0) then
  begin
    if AExpected = ceEmpty then
      Exit('jogada aceita com token invalido');
    if (APosition <= 8) and (AOutcome.Snapshot.Game.Board[APosition] <> AExpected) then
      Exit(Format('jogada aceita em %d, mas a celula nao tem o simbolo de quem jogou', [APosition]));
  end;
end;

{ ---- SC-01: oito threads na mesma sala -------------------------------------- }

type
  TSameRoomWorker = class(TWorker)
  private
    FRoom: IRoom;
    FTokenX, FTokenO: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoom: IRoom; const ATokenX, ATokenO: string; ASeed: Cardinal);
  end;

const
  SC01_THREADS = 8;
  SC01_OPERATIONS = 2000;

constructor TSameRoomWorker.Create(const ARoom: IRoom; const ATokenX, ATokenO: string; ASeed: Cardinal);
begin
  inherited Create(ASeed);
  FRoom := ARoom;
  FTokenX := ATokenX;
  FTokenO := ATokenO;
end;

procedure TSameRoomWorker.Execute;
var
  I, Kind, Position, Who: Integer;
  Token, Problem, IssuedToken: string;
  Expected: TCell;
  Outcome: TRoomOutcome;
  LastVersion: Int64;
  Seat: TSeat;
begin
  LastVersion := 0;
  for I := 1 to SC01_OPERATIONS do
  begin
    try
      Kind := NextRandom mod 100;
      Who := NextRandom mod 10;
      if Who < 5 then
      begin
        Token := FTokenX;
        Expected := ceX;
      end
      else if Who < 9 then
      begin
        Token := FTokenO;
        Expected := ceO;
      end
      else
      begin
        Token := 'ffffffffffffffffffffffffffffffff';
        Expected := ceEmpty;
      end;
      Position := -1;
      if Kind < 70 then
      begin
        Position := Integer(NextRandom mod 11) - 1;   { -1 a 9 }
        Outcome := FRoom.Play(Token, Position);
      end
      else if Kind < 85 then
      begin
        Outcome.Snapshot := FRoom.Snapshot;
        Outcome.Changed := False;
        Outcome.Result := rrOk;
      end
      else if Kind < 97 then
        Outcome := FRoom.NewGame(Token)
      else
        Outcome := FRoom.Join(Token, Seat, IssuedToken);
      if Kind >= 70 then
        Position := -1;
      Problem := CheckPlay(Outcome, Position, Expected, FRoom.Code, LastVersion);
      if (Kind >= 97) and Outcome.Changed then
        Problem := 'entrada mudou uma sala cheia';
      if Problem <> '' then
        Report(Format('operacao %d: %s', [I, Problem]));
      if Outcome.Changed then
        Inc(FChanges);
      if Outcome.Snapshot.Version > LastVersion then
        LastVersion := Outcome.Snapshot.Version;
    except
      on E: Exception do
        Report(Format('operacao %d: excecao %s: %s', [I, E.ClassName, E.Message]));
    end;
    Inc(FOperations);
  end;
end;

procedure SC01_SameRoom;
var
  Reg: TRoomRegistry;
  Room: IRoom;
  TokenX, TokenO: string;
  Seat: TSeat;
  Threads: array[0..SC01_THREADS - 1] of TSameRoomWorker;
  I, Ops, Changes, Problems: Integer;
  StartVersion, FinalVersion: Int64;
begin
  Reg := TRoomRegistry.Create(TSystemClock.Create, TSystemRandom.Create, 100, 3600000);
  try
    Reg.CreateRoom(Room, TokenX);
    Room.Join('', Seat, TokenO);
    StartVersion := Room.Snapshot.Version;
    for I := 0 to SC01_THREADS - 1 do
      Threads[I] := TSameRoomWorker.Create(Room, TokenX, TokenO, Cardinal(I * 7919 + 17));
    for I := 0 to SC01_THREADS - 1 do
      Threads[I].Start;
    Ops := 0;
    Changes := 0;
    Problems := 0;
    for I := 0 to SC01_THREADS - 1 do
    begin
      Threads[I].WaitFor;
      Inc(Ops, Threads[I].Operations);
      Inc(Changes, Threads[I].Changes);
      Inc(Problems, Threads[I].Problems);
      if Threads[I].Problems > 0 then
        Check(False, Format('thread %d: %d problema(s); primeiro: %s', [I, Threads[I].Problems, Threads[I].FirstProblem]));
      Threads[I].Free;
    end;
    FinalVersion := Room.Snapshot.Version;
    CheckEqualsInt(SC01_THREADS * SC01_OPERATIONS, Ops, 'operacoes executadas');
    CheckEqualsInt(0, Problems, 'problemas encontrados');
    { Cada mudanca aceita sobe a versao em exatamente 1: nenhuma se perdeu. }
    CheckEqualsInt(Changes, Integer(FinalVersion - StartVersion), 'mudancas aceitas = versao final - versao inicial');
    Check(CoherenceProblem(Room.Snapshot.Game) = '', 'estado final incoerente');
    Note(Format('%d threads x %d operacoes; %d mudancas aceitas; versao %d -> %d; problemas %d',
      [SC01_THREADS, SC01_OPERATIONS, Changes, StartVersion, FinalVersion, Problems]));
  finally
    Room := nil;
    Reg.Free;
  end;
end;

{ ---- SC-02: dezesseis threads em cinquenta salas, com o faxineiro ------------- }

const
  SC02_THREADS = 16;
  SC02_ROOMS = 50;
  SC02_OPERATIONS = 1500;
  SC02_TIMEOUT_MS = 30000;

type
  TRoomEntry = record
    Room: IRoom;
    TokenX, TokenO: string;
    StartVersion: Int64;
  end;

var
  SC02Rooms: array[0..SC02_ROOMS - 1] of TRoomEntry;
  SC02Changes: array[0..SC02_ROOMS - 1] of Integer;

type
  TManyRoomsWorker = class(TWorker)
  private
    FRegistry: TRoomRegistry;
  protected
    procedure Execute; override;
  public
    constructor Create(ARegistry: TRoomRegistry; ASeed: Cardinal);
  end;

  TSweeper = class(TThread)
  private
    FRegistry: TRoomRegistry;
    FStop: TEvent;
    FSweeps: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(ARegistry: TRoomRegistry; AStop: TEvent);
    property Sweeps: Integer read FSweeps;
  end;

constructor TManyRoomsWorker.Create(ARegistry: TRoomRegistry; ASeed: Cardinal);
begin
  inherited Create(ASeed);
  FRegistry := ARegistry;
end;

procedure TManyRoomsWorker.Execute;
var
  I, Index, Kind, Position: Integer;
  Token, Problem, FreshToken, OToken: string;
  Expected: TCell;
  Outcome: TRoomOutcome;
  Found, Fresh: IRoom;
  Seat: TSeat;
begin
  for I := 1 to SC02_OPERATIONS do
  begin
    try
      Index := NextRandom mod SC02_ROOMS;
      Kind := NextRandom mod 100;
      if NextRandom mod 2 = 0 then
      begin
        Token := SC02Rooms[Index].TokenX;
        Expected := ceX;
      end
      else
      begin
        Token := SC02Rooms[Index].TokenO;
        Expected := ceO;
      end;
      if Kind < 80 then
      begin
        Position := Integer(NextRandom mod 9);
        Outcome := SC02Rooms[Index].Room.Play(Token, Position);
        Problem := CheckPlay(Outcome, Position, Expected, SC02Rooms[Index].Room.Code, 0);
        if Outcome.Changed then
          TInterlocked.Increment(SC02Changes[Index]);
      end
      else if Kind < 88 then
      begin
        Outcome := SC02Rooms[Index].Room.NewGame(Token);
        Problem := CheckPlay(Outcome, -1, Expected, SC02Rooms[Index].Room.Code, 0);
        if Outcome.Changed then
          TInterlocked.Increment(SC02Changes[Index]);
      end
      else if Kind < 96 then
      begin
        if FRegistry.Find(SC02Rooms[Index].Room.Code, Found) <> rrOk then
          Problem := 'Find nao encontrou uma sala aberta'
        else if Found.Code <> SC02Rooms[Index].Room.Code then
          Problem := 'Find devolveu outra sala'
        else
          Problem := '';
      end
      else
      begin
        { Sala nova, criada, ocupada e encerrada enquanto as outras jogam. }
        Problem := '';
        if FRegistry.CreateRoom(Fresh, FreshToken) = rrOk then
        begin
          Fresh.Join('', Seat, OToken);
          Outcome := Fresh.Play(FreshToken, 4);
          if (Outcome.Result <> rrOk) or (Outcome.Snapshot.Game.Board[4] <> ceX) then
            Problem := 'sala nova nao aceitou a primeira jogada';
          Fresh.Leave(OToken);
        end
        else
          Problem := 'CreateRoom recusou uma sala nova';
        Fresh := nil;
      end;
      if Problem <> '' then
        Report(Format('operacao %d (sala %d): %s', [I, Index, Problem]));
    except
      on E: Exception do
        Report(Format('operacao %d: excecao %s: %s', [I, E.ClassName, E.Message]));
    end;
    Inc(FOperations);
  end;
end;

constructor TSweeper.Create(ARegistry: TRoomRegistry; AStop: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FRegistry := ARegistry;
  FStop := AStop;
end;

procedure TSweeper.Execute;
begin
  { TTL enorme: nenhuma sala do teste e abandonada, mas as encerradas sao movidas. }
  while FStop.WaitFor(1) = wrTimeout do
  begin
    FRegistry.Sweep(High(Int64) div 2);
    Inc(FSweeps);
  end;
end;

procedure SC02_ManyRooms;
var
  Reg: TRoomRegistry;
  Workers: array[0..SC02_THREADS - 1] of TManyRoomsWorker;
  Sweeper: TSweeper;
  Stop: TEvent;
  I, Ops, Problems, Hung: Integer;
  Seat: TSeat;
  FinalState: TRoomSnapshot;
  Deadline: Cardinal;
begin
  Reg := TRoomRegistry.Create(TSystemClock.Create, TSystemRandom.Create, 10000, 3600000);
  Stop := TEvent.Create(nil, True, False, '');
  try
    for I := 0 to SC02_ROOMS - 1 do
    begin
      Reg.CreateRoom(SC02Rooms[I].Room, SC02Rooms[I].TokenX);
      SC02Rooms[I].Room.Join('', Seat, SC02Rooms[I].TokenO);
      SC02Rooms[I].StartVersion := SC02Rooms[I].Room.Snapshot.Version;
      SC02Changes[I] := 0;
    end;
    Sweeper := TSweeper.Create(Reg, Stop);
    for I := 0 to SC02_THREADS - 1 do
      Workers[I] := TManyRoomsWorker.Create(Reg, Cardinal(I * 104729 + 31));
    Sweeper.Start;
    for I := 0 to SC02_THREADS - 1 do
      Workers[I].Start;

    { Espera com prazo: um impasse (deadlock) faz o caso falhar em vez de travar. }
    Hung := 0;
    Deadline := GetTickCount + SC02_TIMEOUT_MS;
    for I := 0 to SC02_THREADS - 1 do
      if WaitForSingleObject(Workers[I].Handle, Cardinal(Max(1, Integer(Deadline - GetTickCount)))) <> WAIT_OBJECT_0 then
        Inc(Hung);
    Stop.SetEvent;
    if WaitForSingleObject(Sweeper.Handle, 5000) <> WAIT_OBJECT_0 then
      Inc(Hung);
    if Hung > 0 then
    begin
      { RunCase nao chega ao fim: a linha de falha e escrita aqui para o script. }
      Writeln(Format('[FALHOU] %-9s %d thread(s) nao terminaram em %d ms (impasse?); EngineCheck interrompido',
        ['SC-02', Hung, SC02_TIMEOUT_MS]));
      Flush(Output);
      PrintSummary;
      Halt(1);
    end;

    Ops := 0;
    Problems := 0;
    for I := 0 to SC02_THREADS - 1 do
    begin
      Inc(Ops, Workers[I].Operations);
      Inc(Problems, Workers[I].Problems);
      if Workers[I].Problems > 0 then
        Check(False, Format('thread %d: %d problema(s); primeiro: %s', [I, Workers[I].Problems, Workers[I].FirstProblem]));
      Workers[I].Free;
    end;
    CheckEqualsInt(SC02_THREADS * SC02_OPERATIONS, Ops, 'operacoes executadas');
    CheckEqualsInt(0, Problems, 'problemas encontrados');
    for I := 0 to SC02_ROOMS - 1 do
    begin
      FinalState := SC02Rooms[I].Room.Snapshot;
      if CoherenceProblem(FinalState.Game) <> '' then
        Check(False, Format('sala %d incoerente: %s', [I, CoherenceProblem(FinalState.Game)]));
      if FinalState.Version - SC02Rooms[I].StartVersion <> SC02Changes[I] then
        Check(False, Format('sala %d: %d mudancas, mas a versao andou %d', [I, SC02Changes[I], FinalState.Version - SC02Rooms[I].StartVersion]));
    end;
    Note(Format('%d threads x %d operacoes em %d salas; faxineiro rodou %d vezes; salas abertas no fim %d, lembradas %d; problemas %d',
      [SC02_THREADS, SC02_OPERATIONS, SC02_ROOMS, Sweeper.Sweeps, Reg.OpenCount, Reg.RememberedCount, Problems]));
    Sweeper.Free;
  finally
    for I := 0 to SC02_ROOMS - 1 do
      SC02Rooms[I].Room := nil;
    Stop.Free;
    Reg.Free;
  end;
end;

procedure RunRoomConcurrencyTests;
begin
  RunCase('SC-01', 'Oito threads na mesma sala: sem jogada invalida aceita, sem mudanca perdida', SC01_SameRoom);
  RunCase('SC-02', 'Dezesseis threads em 50 salas com o faxineiro: isolamento e sem impasse', SC02_ManyRooms);
end;

end.
