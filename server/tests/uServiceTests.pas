unit uServiceTests;

{ Casos SV do docs/test-plan.md (seção 9.3): testam uGameService
  diretamente, sem HTTP, incluindo acesso simultâneo por várias threads. }

{$Q-}  { O gerador pseudoaleatório abaixo depende de estouro aritmético. }
{$R-}

interface

procedure RunServiceTests;

implementation

uses
  System.SysUtils, System.Classes, uMiniTest, uGameEngine, uGameService,
  uEngineTests;

const
  INITIAL_STATE = 'tab=......... status=EM_ANDAMENTO vez=X venc=- cel=[]';

{ Devolve '' se o estado é coerente com as regras, ou o motivo se não é. }
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
          Exit('em andamento com X=O, mas a vez não é de X');
        if (Xs > Os) and (S.CurrentPlayer <> ceO) then
          Exit('em andamento com X>O, mas a vez não é de O');
        if (S.Winner <> ceEmpty) or (Length(S.WinningCells) <> 0) then
          Exit('em andamento com vencedor ou células vencedoras');
        if Empty = 0 then
          Exit('em andamento com tabuleiro cheio');
      end;
    gsWin:
      begin
        if S.CurrentPlayer <> ceEmpty then
          Exit('vitória com jogador da vez');
        if S.Winner = ceEmpty then
          Exit('vitória sem vencedor');
        if (Length(S.WinningCells) <> 3) and (Length(S.WinningCells) <> 5) then
          Exit(Format('vitória com %d células vencedoras', [Length(S.WinningCells)]));
        for I := 0 to High(S.WinningCells) do
          if S.Board[S.WinningCells[I]] <> S.Winner then
            Exit('célula vencedora sem o símbolo do vencedor');
      end;
  else
    begin
      if (S.CurrentPlayer <> ceEmpty) or (S.Winner <> ceEmpty) or
         (Length(S.WinningCells) <> 0) then
        Exit('empate com vez, vencedor ou células vencedoras');
      if Empty <> 0 then
        Exit('empate com células vazias');
    end;
  end;
  Result := '';
end;

{ ---- SV-01 / SV-02 ------------------------------------------------------- }

procedure SV01_StateIsCopy;
var
  Svc: TGameService;
  S, Outcome: TGameSnapshot;
  O: TPlayOutcome;
  Expected: string;
begin
  Svc := TGameService.Create;
  try
    Svc.Play(0); Svc.Play(3); Svc.Play(1); Svc.Play(4);
    O := Svc.Play(2);
    Expected := 'tab=XXXOO.... status=VITORIA vez=- venc=X cel=[0,1,2]';
    CheckEqualsStr(Expected, SnapshotStr(O.State), 'estado devolvido pela jogada vencedora');

    { Alterar o estado devolvido por Play não muda o serviço. }
    if Length(O.State.WinningCells) > 0 then
      O.State.WinningCells[0] := 8;
    O.State.Board[5] := ceO;
    CheckEqualsStr(Expected, SnapshotStr(Svc.GetState), 'após alterar o retorno de Play');

    { Alterar o estado devolvido por GetState também não. }
    S := Svc.GetState;
    if Length(S.WinningCells) > 0 then
      S.WinningCells[1] := 7;
    S.Board[6] := ceX;
    CheckEqualsStr(Expected, SnapshotStr(Svc.GetState), 'após alterar o retorno de GetState');

    { Nem o devolvido por Reset. }
    Outcome := Svc.Reset;
    CheckEqualsStr(INITIAL_STATE, SnapshotStr(Outcome), 'retorno de Reset');
    Outcome.Board[0] := ceO;
    CheckEqualsStr(INITIAL_STATE, SnapshotStr(Svc.GetState), 'após alterar o retorno de Reset');
  finally
    Svc.Free;
  end;
end;

procedure SV02_PlayReturnsItsOwnState;
var
  Svc: TGameService;
  O1, O2: TPlayOutcome;
begin
  Svc := TGameService.Create;
  try
    O1 := Svc.Play(0);
    Check(O1.MoveResult = mrAccepted, 'a primeira jogada deveria ser aceita');
    CheckEqualsStr('tab=X........ status=EM_ANDAMENTO vez=O venc=- cel=[]',
      SnapshotStr(O1.State), 'estado devolvido pela jogada aceita');
    CheckEqualsStr(SnapshotStr(O1.State), SnapshotStr(Svc.GetState),
      'GetState depois da jogada aceita');

    O2 := Svc.Play(0);
    Check(O2.MoveResult = mrCellOccupied, 'a segunda jogada em 0 deveria ser recusada');
    CheckEqualsStr(SnapshotStr(O1.State), SnapshotStr(O2.State),
      'estado devolvido pela jogada recusada');

    O2 := Svc.Play(42);
    Check(O2.MoveResult = mrInvalidPosition, 'posição 42 deveria ser inválida');
    CheckEqualsStr(SnapshotStr(O1.State), SnapshotStr(Svc.GetState),
      'estado depois da posição inválida');
  finally
    Svc.Free;
  end;
end;

{ ---- SV-03: várias threads no mesmo serviço ------------------------------ }

type
  TStressThread = class(TThread)
  private
    FService: TGameService;
    FSeed: Cardinal;
    FOperations: Integer;
    FProblems: Integer;
    FFirstProblem: string;
    function NextRandom: Cardinal;
    procedure Report(const AProblem: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AService: TGameService; ASeed: Cardinal);
    property Operations: Integer read FOperations;
    property Problems: Integer read FProblems;
    property FirstProblem: string read FFirstProblem;
  end;

const
  STRESS_THREADS = 8;
  STRESS_OPERATIONS = 2000;

constructor TStressThread.Create(AService: TGameService; ASeed: Cardinal);
begin
  { A thread só começa a rodar depois do construtor (AfterConstruction). }
  inherited Create(False);
  FreeOnTerminate := False;
  FService := AService;
  FSeed := ASeed;
end;

function TStressThread.NextRandom: Cardinal;
begin
  { Gerador próprio por thread: o Random do Delphi usa estado global. }
  FSeed := FSeed * 1103515245 + 12345;
  Result := (FSeed shr 8) and $FFFFFF;
end;

procedure TStressThread.Report(const AProblem: string);
begin
  Inc(FProblems);
  if FFirstProblem = '' then
    FFirstProblem := AProblem;
end;

procedure TStressThread.Execute;
var
  I, Kind, Position: Integer;
  S: TGameSnapshot;
  O: TPlayOutcome;
  Problem: string;
begin
  for I := 1 to STRESS_OPERATIONS do
  begin
    try
      Kind := NextRandom mod 100;
      if Kind < 3 then
      begin
        S := FService.Reset;
        Problem := CoherenceProblem(S);
      end
      else if Kind < 20 then
      begin
        S := FService.GetState;
        Problem := CoherenceProblem(S);
      end
      else
      begin
        Position := Integer(NextRandom mod 11) - 1;   { -1 a 9 }
        O := FService.Play(Position);
        Problem := CoherenceProblem(O.State);
        if (Problem = '') and (O.MoveResult = mrAccepted) and
           (O.State.Board[Position] = ceEmpty) then
          Problem := Format('jogada aceita em %d, mas a célula está vazia no estado devolvido', [Position]);
      end;
      if Problem <> '' then
        Report(Format('operação %d: %s', [I, Problem]));
    except
      on E: Exception do
        Report(Format('operação %d: exceção %s: %s', [I, E.ClassName, E.Message]));
    end;
    Inc(FOperations);
  end;
end;

procedure SV03_ConcurrentAccess;
var
  Svc: TGameService;
  Threads: array[0..STRESS_THREADS - 1] of TStressThread;
  I, TotalOps, TotalProblems: Integer;
begin
  Svc := TGameService.Create;
  try
    for I := 0 to STRESS_THREADS - 1 do
      Threads[I] := TStressThread.Create(Svc, Cardinal(I * 7919 + 17));
    TotalOps := 0;
    TotalProblems := 0;
    for I := 0 to STRESS_THREADS - 1 do
    begin
      Threads[I].WaitFor;
      Inc(TotalOps, Threads[I].Operations);
      Inc(TotalProblems, Threads[I].Problems);
      if Threads[I].Problems > 0 then
        Check(False, Format('thread %d: %d problema(s); primeiro: %s',
          [I, Threads[I].Problems, Threads[I].FirstProblem]));
      Threads[I].Free;
    end;
    CheckEqualsInt(STRESS_THREADS * STRESS_OPERATIONS, TotalOps, 'operações executadas');
    CheckEqualsInt(0, TotalProblems, 'problemas encontrados');
    Check(CoherenceProblem(Svc.GetState) = '', 'estado final incoerente: ' +
      CoherenceProblem(Svc.GetState));
    Note(Format('%d threads x %d operações = %d operações; problemas: %d',
      [STRESS_THREADS, STRESS_OPERATIONS, TotalOps, TotalProblems]));
  finally
    Svc.Free;
  end;
end;

procedure RunServiceTests;
begin
  RunCase('SV-01', 'Serviço devolve cópias do estado', SV01_StateIsCopy);
  RunCase('SV-02', 'Play devolve o resultado e o estado da mesma jogada', SV02_PlayReturnsItsOwnState);
  RunCase('SV-03', 'Acesso simultâneo por várias threads mantém o estado coerente', SV03_ConcurrentAccess);
end;

end.
