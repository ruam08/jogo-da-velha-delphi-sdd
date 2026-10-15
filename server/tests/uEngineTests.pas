unit uEngineTests;

{ Casos de teste do motor do jogo (grupo M do docs/test-plan.md, seção 9.1).
  Testam uGameEngine diretamente: sem Indy, sem HTTP, sem JSON, sem interface.

  Notação do tabuleiro: 9 caracteres, células 0 a 8 da esquerda para a
  direita e de cima para baixo; 'X', 'O' ou '.' (vazia).
    0 | 1 | 2
    3 | 4 | 5
    6 | 7 | 8 }

interface

uses
  uGameEngine;

procedure RunEngineTests;

{ Texto com o estado completo, usado também pelos testes do serviço. }
function SnapshotStr(const ASnapshot: TGameSnapshot): string;

implementation

uses
  System.SysUtils, uMiniTest;

{ ---- Conversões para texto (mensagens legíveis) -------------------------- }

function CellChar(ACell: TCell): Char;
begin
  case ACell of
    ceX: Result := 'X';
    ceO: Result := 'O';
  else
    Result := '.';
  end;
end;

function PlayerStr(ACell: TCell): string;
begin
  if ACell = ceEmpty then
    Result := '-'
  else
    Result := CellChar(ACell);
end;

function StatusStr(AStatus: TGameStatus): string;
begin
  case AStatus of
    gsInProgress: Result := 'EM_ANDAMENTO';
    gsWin: Result := 'VITORIA';
  else
    Result := 'EMPATE';
  end;
end;

function MoveResultStr(AResult: TMoveResult): string;
begin
  case AResult of
    mrAccepted: Result := 'mrAccepted';
    mrInvalidPosition: Result := 'mrInvalidPosition';
    mrGameOver: Result := 'mrGameOver';
  else
    Result := 'mrCellOccupied';
  end;
end;

function CellsStr(const ACells: array of Integer): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to High(ACells) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(ACells[I]);
  end;
  Result := Result + ']';
end;

function BoardStr(const ASnapshot: TGameSnapshot): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to 8 do
    Result := Result + CellChar(ASnapshot.Board[I]);
end;

{ Representação completa do estado. Comparar estes textos compara todos os
  campos de uma vez (tabuleiro, status, vez, vencedor e células vencedoras). }
function StateStr(const ABoard: string; AStatus: TGameStatus;
  ACurrent, AWinner: TCell; const ACells: array of Integer): string;
begin
  Result := Format('tab=%s status=%s vez=%s venc=%s cel=%s',
    [ABoard, StatusStr(AStatus), PlayerStr(ACurrent), PlayerStr(AWinner),
     CellsStr(ACells)]);
end;

function SnapshotStr(const ASnapshot: TGameSnapshot): string;
begin
  Result := StateStr(BoardStr(ASnapshot), ASnapshot.Status,
    ASnapshot.CurrentPlayer, ASnapshot.Winner, ASnapshot.WinningCells);
end;

function EngineStr(AEngine: TGameEngine): string;
begin
  Result := SnapshotStr(AEngine.GetSnapshot);
end;

{ ---- Ações e verificações reutilizáveis ---------------------------------- }

const
  INITIAL_STATE = 'tab=......... status=EM_ANDAMENTO vez=X venc=- cel=[]';
  OUT_OF_RANGE: array[0..5] of Integer = (-1, 9, 10, 100, MaxInt, Low(Integer));

procedure ExpectState(AEngine: TGameEngine; const ABoard: string;
  AStatus: TGameStatus; ACurrent, AWinner: TCell;
  const ACells: array of Integer; const AContext: string);
begin
  CheckEqualsStr(StateStr(ABoard, AStatus, ACurrent, AWinner, ACells),
    EngineStr(AEngine), AContext);
end;

procedure ExpectInitial(AEngine: TGameEngine; const AContext: string);
begin
  CheckEqualsStr(INITIAL_STATE, EngineStr(AEngine), AContext);
end;

{ Faz as jogadas e exige que todas sejam aceitas. }
procedure PlayAll(AEngine: TGameEngine; const AMoves: array of Integer;
  const AContext: string);
var
  I: Integer;
  R: TMoveResult;
begin
  for I := 0 to High(AMoves) do
  begin
    R := AEngine.Play(AMoves[I]);
    CheckEqualsStr(MoveResultStr(mrAccepted), MoveResultStr(R),
      Format('%s: jogada %d (posição %d)', [AContext, I + 1, AMoves[I]]));
  end;
end;

{ Exige que a jogada seja recusada com AExpected e que o estado não mude. }
procedure ExpectRejected(AEngine: TGameEngine; APosition: Integer;
  AExpected: TMoveResult; const AContext: string);
var
  Before: string;
  R: TMoveResult;
begin
  Before := EngineStr(AEngine);
  R := AEngine.Play(APosition);
  CheckEqualsStr(MoveResultStr(AExpected), MoveResultStr(R),
    Format('%s: resultado da jogada na posição %d', [AContext, APosition]));
  CheckEqualsStr(Before, EngineStr(AEngine),
    Format('%s: estado após jogada recusada na posição %d', [AContext, APosition]));
end;

{ Joga a sequência; antes da última jogada a partida deve estar em
  andamento; no fim o estado deve ser exatamente o esperado. }
procedure CheckWin(const AMoves: array of Integer; const ABoard: string;
  AWinner: TCell; const ACells: array of Integer);
var
  E: TGameEngine;
  I: Integer;
begin
  E := TGameEngine.Create;
  try
    for I := 0 to High(AMoves) - 1 do
      PlayAll(E, [AMoves[I]], Format('jogada %d antes da última', [I + 1]));
    Check(E.GetSnapshot.Status = gsInProgress,
      'a partida terminou antes da última jogada: ' + EngineStr(E));
    PlayAll(E, [AMoves[High(AMoves)]], 'última jogada');
    ExpectState(E, ABoard, gsWin, ceEmpty, AWinner, ACells, 'estado final');
  finally
    E.Free;
  end;
end;

{ ---- Casos --------------------------------------------------------------- }

procedure M01_InitialState;
var
  E: TGameEngine;
begin
  E := TGameEngine.Create;
  try
    ExpectInitial(E, 'após Create');
    PlayAll(E, [0, 4], 'preparação');
    E.Reset;
    ExpectInitial(E, 'após Reset');
  finally
    E.Free;
  end;
end;

procedure M02_Alternation;
const
  MOVES: array[0..7] of Integer = (0, 1, 2, 4, 3, 5, 7, 6);
var
  E: TGameEngine;
  I: Integer;
  S: TGameSnapshot;
  Expected, NextPlayer: TCell;
begin
  E := TGameEngine.Create;
  try
    for I := 0 to High(MOVES) do
    begin
      if I mod 2 = 0 then
      begin
        Expected := ceX;
        NextPlayer := ceO;
      end
      else
      begin
        Expected := ceO;
        NextPlayer := ceX;
      end;
      CheckEqualsStr(PlayerStr(Expected), PlayerStr(E.GetSnapshot.CurrentPlayer),
        Format('vez antes da jogada %d', [I + 1]));
      PlayAll(E, [MOVES[I]], Format('jogada %d', [I + 1]));
      S := E.GetSnapshot;
      CheckEqualsStr(PlayerStr(Expected), CellChar(S.Board[MOVES[I]]),
        Format('símbolo gravado na jogada %d', [I + 1]));
      CheckEqualsStr(PlayerStr(NextPlayer), PlayerStr(S.CurrentPlayer),
        Format('vez depois da jogada %d', [I + 1]));
      CheckEqualsStr(StatusStr(gsInProgress), StatusStr(S.Status),
        Format('status depois da jogada %d', [I + 1]));
    end;
    ExpectState(E, 'XOXXOOOX.', gsInProgress, ceX, ceEmpty, [], 'estado final');
  finally
    E.Free;
  end;
end;

procedure M03_OccupiedCell;
var
  E: TGameEngine;
begin
  E := TGameEngine.Create;
  try
    PlayAll(E, [0], 'X joga em 0');
    ExpectRejected(E, 0, mrCellOccupied, 'O na célula de X');
    PlayAll(E, [4], 'O joga em 4 depois da recusa');
    ExpectState(E, 'X...O....', gsInProgress, ceX, ceEmpty, [], 'após O jogar em 4');
    ExpectRejected(E, 0, mrCellOccupied, 'X na própria célula');
    ExpectRejected(E, 4, mrCellOccupied, 'X na célula de O');
    PlayAll(E, [8], 'X joga em 8 depois das recusas');
    ExpectState(E, 'X...O...X', gsInProgress, ceO, ceEmpty, [], 'após X jogar em 8');
  finally
    E.Free;
  end;
end;

procedure M04_OutOfRange;
var
  E: TGameEngine;
  I: Integer;
begin
  E := TGameEngine.Create;
  try
    for I := 0 to High(OUT_OF_RANGE) do
      ExpectRejected(E, OUT_OF_RANGE[I], mrInvalidPosition, 'início da partida');
    ExpectInitial(E, 'depois das recusas no início');
    PlayAll(E, [0, 4], 'preparação');
    for I := 0 to High(OUT_OF_RANGE) do
      ExpectRejected(E, OUT_OF_RANGE[I], mrInvalidPosition, 'meio da partida');
    ExpectState(E, 'X...O....', gsInProgress, ceX, ceEmpty, [],
      'depois das recusas no meio');
  finally
    E.Free;
  end;
end;

procedure M06_LastMoveAndDoubleWin;
begin
  { S-9A: a 9ª jogada completa 2-5-8 e enche o tabuleiro: vitória, não empate. }
  CheckWin([0, 1, 2, 4, 5, 3, 7, 6, 8], 'XOXOOXOXX', ceX, [2, 5, 8]);
  { S-DUP: a última jogada completa as duas diagonais: 5 células. }
  CheckWin([0, 1, 2, 3, 6, 5, 8, 7, 4], 'XOXOXOXOX', ceX, [0, 2, 4, 6, 8]);
end;

procedure M07_Draw;
var
  E: TGameEngine;
begin
  E := TGameEngine.Create;
  try
    PlayAll(E, [0, 1, 2, 4, 3, 5, 7, 6], 'oito primeiras jogadas');
    Check(E.GetSnapshot.Status = gsInProgress,
      'a partida terminou antes da 9ª jogada: ' + EngineStr(E));
    PlayAll(E, [8], '9ª jogada');
    ExpectState(E, 'XOXXOOOXX', gsDraw, ceEmpty, ceEmpty, [], 'estado final');
  finally
    E.Free;
  end;
end;

procedure M08_LockedAfterEnd;
var
  E: TGameEngine;
  P: Integer;
begin
  E := TGameEngine.Create;
  try
    PlayAll(E, [0, 3, 1, 4, 2], 'vitória S-L1');
    for P := 0 to 8 do
      ExpectRejected(E, P, mrGameOver, 'após vitória');
    ExpectState(E, 'XXXOO....', gsWin, ceEmpty, ceX, [0, 1, 2],
      'vitória preservada');

    E.Reset;
    PlayAll(E, [0, 1, 2, 4, 3, 5, 7, 6, 8], 'empate S-EMP');
    for P := 0 to 8 do
      ExpectRejected(E, P, mrGameOver, 'após empate');
    ExpectState(E, 'XOXXOOOXX', gsDraw, ceEmpty, ceEmpty, [], 'empate preservado');
  finally
    E.Free;
  end;
end;

procedure M09_InvalidPositionFirst;
var
  E: TGameEngine;
begin
  E := TGameEngine.Create;
  try
    PlayAll(E, [0, 3, 1, 4, 2], 'vitória S-L1');
    ExpectRejected(E, 9, mrInvalidPosition, 'posição 9 após vitória');
    ExpectRejected(E, -1, mrInvalidPosition, 'posição -1 após vitória');
  finally
    E.Free;
  end;
end;

procedure M10_Reset;
var
  E: TGameEngine;
begin
  E := TGameEngine.Create;
  try
    PlayAll(E, [0, 1, 2, 3, 6, 5, 8, 7, 4], 'vitória dupla S-DUP');
    E.Reset;
    ExpectInitial(E, 'Reset após vitória dupla (5 células vencedoras)');

    PlayAll(E, [0, 1, 2, 4, 3, 5, 7, 6, 8], 'empate S-EMP');
    E.Reset;
    ExpectInitial(E, 'Reset após empate');

    PlayAll(E, [0, 4], 'meio de partida');
    E.Reset;
    ExpectInitial(E, 'Reset no meio da partida');

    PlayAll(E, [0], 'antes da recusa');
    ExpectRejected(E, 0, mrCellOccupied, 'recusa antes do Reset');
    E.Reset;
    ExpectInitial(E, 'Reset após jogada recusada');

    { A partida nova precisa funcionar do zero, inclusive nas células que
      estavam ocupadas e com X começando. }
    PlayAll(E, [0, 3, 1, 4, 2], 'nova partida após Reset');
    ExpectState(E, 'XXXOO....', gsWin, ceEmpty, ceX, [0, 1, 2],
      'vitória na partida nova');
  finally
    E.Free;
  end;
end;

procedure M11_SnapshotIsCopy;
var
  E: TGameEngine;
  S: TGameSnapshot;
begin
  E := TGameEngine.Create;
  try
    PlayAll(E, [0, 3, 1, 4, 2], 'vitória S-L1');
    S := E.GetSnapshot;
    Check(Length(S.WinningCells) = 3, 'a cópia deveria ter 3 células vencedoras');
    if Length(S.WinningCells) = 3 then
      S.WinningCells[0] := 7;
    S.Board[5] := ceO;
    S.Status := gsDraw;
    ExpectState(E, 'XXXOO....', gsWin, ceEmpty, ceX, [0, 1, 2],
      'motor depois de alterar a cópia do estado');
  finally
    E.Free;
  end;
end;

{ ---- M-12: teste exaustivo com oráculo independente ---------------------- }

type
  TMoveList = array[0..8] of Integer;

  TExploreStats = record
    Nodes: Integer;
    Games: Integer;
    XWins: Integer;
    OWins: Integer;
    Draws: Integer;
    FiveCellWins: Integer;
  end;

{ Oráculo: calcula o estado esperado só a partir da lista de jogadas,
  procurando linhas, colunas e diagonais com laços (sem usar WIN_LINES). }
function OracleState(const AMoves: TMoveList; ADepth: Integer;
  out AFinished: Boolean; out AWinner: TCell; out ACellCount: Integer): string;
var
  Board: array[0..8] of TCell;
  Marked: array[0..8] of Boolean;
  I, R, C: Integer;
  Cells: TArray<Integer>;
  BoardText: string;
  Status: TGameStatus;
  Current: TCell;

  procedure TryLine(A, B, D: Integer);
  begin
    if (Board[A] <> ceEmpty) and (Board[A] = Board[B]) and (Board[A] = Board[D]) then
    begin
      AWinner := Board[A];
      Marked[A] := True;
      Marked[B] := True;
      Marked[D] := True;
    end;
  end;

begin
  for I := 0 to 8 do
  begin
    Board[I] := ceEmpty;
    Marked[I] := False;
  end;
  for I := 0 to ADepth - 1 do
    if I mod 2 = 0 then
      Board[AMoves[I]] := ceX
    else
      Board[AMoves[I]] := ceO;

  AWinner := ceEmpty;
  for R := 0 to 2 do
    TryLine(3 * R, 3 * R + 1, 3 * R + 2);
  for C := 0 to 2 do
    TryLine(C, C + 3, C + 6);
  TryLine(0, 4, 8);
  TryLine(2, 4, 6);

  SetLength(Cells, 0);
  for I := 0 to 8 do
    if Marked[I] then
    begin
      SetLength(Cells, Length(Cells) + 1);
      Cells[High(Cells)] := I;
    end;
  ACellCount := Length(Cells);

  if AWinner <> ceEmpty then
    Status := gsWin
  else if ADepth = 9 then
    Status := gsDraw
  else
    Status := gsInProgress;
  AFinished := Status <> gsInProgress;

  if AFinished then
    Current := ceEmpty
  else if ADepth mod 2 = 0 then
    Current := ceX
  else
    Current := ceO;

  BoardText := '';
  for I := 0 to 8 do
    BoardText := BoardText + CellChar(Board[I]);
  Result := StateStr(BoardText, Status, Current, AWinner, Cells);
end;

procedure Explore(AEngine: TGameEngine; var AMoves: TMoveList; ADepth: Integer;
  var AStats: TExploreStats);
var
  I, P, CellCount: Integer;
  Finished, Used: Boolean;
  Winner: TCell;
  Expected, Actual: string;
  Path: string;
begin
  Inc(AStats.Nodes);

  { Reconstrói a posição jogando a sequência desde o início. }
  AEngine.Reset;
  for I := 0 to ADepth - 1 do
    if AEngine.Play(AMoves[I]) <> mrAccepted then
    begin
      Check(False, Format('jogada %d recusada no caminho', [I + 1]));
      Exit;
    end;

  Path := '';
  for I := 0 to ADepth - 1 do
    Path := Path + IntToStr(AMoves[I]);

  Expected := OracleState(AMoves, ADepth, Finished, Winner, CellCount);
  Actual := EngineStr(AEngine);
  if Actual <> Expected then
    Check(False, Format('jogadas "%s": esperado %s, obtido %s',
      [Path, Expected, Actual]));

  { Toda jogada inválida nesta posição é recusada com o motivo certo. }
  if AEngine.Play(-1) <> mrInvalidPosition then
    Check(False, Format('jogadas "%s": posição -1 não foi recusada como inválida', [Path]));
  if AEngine.Play(9) <> mrInvalidPosition then
    Check(False, Format('jogadas "%s": posição 9 não foi recusada como inválida', [Path]));
  for P := 0 to 8 do
  begin
    Used := False;
    for I := 0 to ADepth - 1 do
      if AMoves[I] = P then
        Used := True;
    if Finished then
    begin
      if AEngine.Play(P) <> mrGameOver then
        Check(False, Format('jogadas "%s": posição %d deveria dar mrGameOver', [Path, P]));
    end
    else if Used then
    begin
      if AEngine.Play(P) <> mrCellOccupied then
        Check(False, Format('jogadas "%s": posição %d deveria dar mrCellOccupied', [Path, P]));
    end;
  end;
  { ...e nenhuma delas alterou o estado. }
  if EngineStr(AEngine) <> Actual then
    Check(False, Format('jogadas "%s": jogadas recusadas alteraram o estado', [Path]));

  if Finished then
  begin
    Inc(AStats.Games);
    if Winner = ceX then
      Inc(AStats.XWins)
    else if Winner = ceO then
      Inc(AStats.OWins)
    else
      Inc(AStats.Draws);
    if CellCount = 5 then
      Inc(AStats.FiveCellWins);
    Exit;
  end;

  for P := 0 to 8 do
  begin
    Used := False;
    for I := 0 to ADepth - 1 do
      if AMoves[I] = P then
        Used := True;
    if not Used then
    begin
      AMoves[ADepth] := P;
      Explore(AEngine, AMoves, ADepth + 1, AStats);
    end;
  end;
end;

procedure M12_Exhaustive;
var
  E: TGameEngine;
  Moves: TMoveList;
  Stats: TExploreStats;
  I: Integer;
begin
  for I := 0 to 8 do
    Moves[I] := -1;
  Stats.Nodes := 0;
  Stats.Games := 0;
  Stats.XWins := 0;
  Stats.OWins := 0;
  Stats.Draws := 0;
  Stats.FiveCellWins := 0;

  E := TGameEngine.Create;
  try
    Explore(E, Moves, 0, Stats);
  finally
    E.Free;
  end;

  Note(Format('posições=%d partidas=%d vitórias X=%d vitórias O=%d empates=%d vitórias com 5 células=%d',
    [Stats.Nodes, Stats.Games, Stats.XWins, Stats.OWins, Stats.Draws,
     Stats.FiveCellWins]));
  CheckEqualsInt(549946, Stats.Nodes, 'posições visitadas');
  CheckEqualsInt(255168, Stats.Games, 'partidas possíveis');
  CheckEqualsInt(131184, Stats.XWins, 'vitórias de X');
  CheckEqualsInt(77904, Stats.OWins, 'vitórias de O');
  CheckEqualsInt(46080, Stats.Draws, 'empates');
  CheckEqualsInt(12672, Stats.FiveCellWins, 'vitórias com 5 células');
end;

{ ---- Registro dos casos -------------------------------------------------- }

procedure RunEngineTests;
begin
  RunCase('M-01', 'Estado inicial após Create e após Reset', M01_InitialState);
  RunCase('M-02', 'Alternância X/O e símbolo gravado em 8 jogadas', M02_Alternation);
  RunCase('M-03', 'Célula ocupada é recusada sem alterar o estado', M03_OccupiedCell);
  RunCase('M-04', 'Posição fora de 0..8 é recusada sem alterar o estado', M04_OutOfRange);

  RunCase('M-05-L1', 'Vitória na linha 0-1-2',
    procedure begin CheckWin([0, 3, 1, 4, 2], 'XXXOO....', ceX, [0, 1, 2]); end);
  RunCase('M-05-L2', 'Vitória na linha 3-4-5',
    procedure begin CheckWin([3, 0, 4, 1, 5], 'OO.XXX...', ceX, [3, 4, 5]); end);
  RunCase('M-05-L3', 'Vitória de O na linha 6-7-8',
    procedure begin CheckWin([0, 6, 1, 7, 4, 8], 'XX..X.OOO', ceO, [6, 7, 8]); end);
  RunCase('M-05-C1', 'Vitória na coluna 0-3-6',
    procedure begin CheckWin([0, 1, 3, 2, 6], 'XOOX..X..', ceX, [0, 3, 6]); end);
  RunCase('M-05-C2', 'Vitória de O na coluna 1-4-7',
    procedure begin CheckWin([0, 1, 3, 4, 8, 7], 'XO.XO..OX', ceO, [1, 4, 7]); end);
  RunCase('M-05-C3', 'Vitória na coluna 2-5-8',
    procedure begin CheckWin([2, 0, 5, 1, 8], 'OOX..X..X', ceX, [2, 5, 8]); end);
  RunCase('M-05-D1', 'Vitória na diagonal 0-4-8',
    procedure begin CheckWin([0, 1, 4, 2, 8], 'XOO.X...X', ceX, [0, 4, 8]); end);
  RunCase('M-05-D2', 'Vitória na diagonal 2-4-6',
    procedure begin CheckWin([2, 0, 4, 1, 6], 'OOX.X.X..', ceX, [2, 4, 6]); end);

  RunCase('M-06', 'Vitória na 9ª jogada e vitória com duas combinações', M06_LastMoveAndDoubleWin);
  RunCase('M-07', 'Empate com tabuleiro cheio', M07_Draw);
  RunCase('M-08', 'Nenhuma jogada é aceita após vitória ou empate', M08_LockedAfterEnd);
  RunCase('M-09', 'Posição inválida tem precedência sobre partida encerrada', M09_InvalidPositionFirst);
  RunCase('M-10', 'Reset limpa completamente o estado anterior', M10_Reset);
  RunCase('M-11', 'GetSnapshot devolve uma cópia independente', M11_SnapshotIsCopy);
  RunCase('M-12', 'Exaustivo: todas as partidas comparadas com um oráculo independente', M12_Exhaustive);
end;

end.
