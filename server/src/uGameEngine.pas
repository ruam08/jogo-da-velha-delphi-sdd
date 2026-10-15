unit uGameEngine;

{ Motor do Jogo da Velha: estado da partida e regras de negócio.

  Independente de Indy, HTTP, JSON e interface (RNF-07): nenhuma unit externa.
  Não é thread-safe por si; quem compartilha uma instância entre threads
  precisa serializar o acesso (uGameService, Entrega 3).

  Células numeradas de 0 a 8:
    0 | 1 | 2
    3 | 4 | 5
    6 | 7 | 8

  Regras: docs/spec.md, seções 4 e 5. Contrato verificado pelos testes:
  docs/test-plan.md, seção 9.1. }

interface

type
  TCell = (ceEmpty, ceX, ceO);
  TGameStatus = (gsInProgress, gsWin, gsDraw);
  TMoveResult = (mrAccepted, mrInvalidPosition, mrGameOver, mrCellOccupied);
  TBoard = array[0..8] of TCell;

  { Fotografia do estado. WinningCells vem em ordem crescente (3 ou 5
    células) quando Status = gsWin e vazio nos demais casos.
    CurrentPlayer e Winner usam ceEmpty para "nenhum". }
  TGameSnapshot = record
    Board: TBoard;
    Status: TGameStatus;
    CurrentPlayer: TCell;
    Winner: TCell;
    WinningCells: TArray<Integer>;
  end;

  TGameEngine = class
  private
    FBoard: TBoard;
    FStatus: TGameStatus;
    FCurrentPlayer: TCell;
    FWinner: TCell;
    FWinningCells: TArray<Integer>;
    procedure UpdateAfterMove(APlayer: TCell);
    function IsBoardFull: Boolean;
  public
    constructor Create;
    { Volta ao estado inicial (RN-01, RN-02, RN-11). }
    procedure Reset;
    { Tenta jogar na posição. Só mrAccepted altera o estado (RN-12).
      Ordem das verificações (RN-15): posição -> partida -> célula. }
    function Play(APosition: Integer): TMoveResult;
    { Cópia independente do estado: alterá-la não afeta o motor. }
    function GetSnapshot: TGameSnapshot;
  end;

const
  BOARD_FIRST = 0;
  BOARD_LAST = 8;

  { As 8 combinações vencedoras (spec, seção 4.3). }
  WIN_LINES: array[0..7, 0..2] of Integer = (
    (0, 1, 2), (3, 4, 5), (6, 7, 8),   { linhas }
    (0, 3, 6), (1, 4, 7), (2, 5, 8),   { colunas }
    (0, 4, 8), (2, 4, 6));             { diagonais }

function OtherPlayer(APlayer: TCell): TCell;

implementation

function OtherPlayer(APlayer: TCell): TCell;
begin
  if APlayer = ceX then
    Result := ceO
  else
    Result := ceX;
end;

{ TGameEngine }

constructor TGameEngine.Create;
begin
  inherited Create;
  Reset;
end;

procedure TGameEngine.Reset;
var
  I: Integer;
begin
  for I := BOARD_FIRST to BOARD_LAST do
    FBoard[I] := ceEmpty;
  FStatus := gsInProgress;
  FCurrentPlayer := ceX;
  FWinner := ceEmpty;
  FWinningCells := nil;
end;

function TGameEngine.Play(APosition: Integer): TMoveResult;
begin
  if (APosition < BOARD_FIRST) or (APosition > BOARD_LAST) then
    Exit(mrInvalidPosition);
  if FStatus <> gsInProgress then
    Exit(mrGameOver);
  if FBoard[APosition] <> ceEmpty then
    Exit(mrCellOccupied);

  FBoard[APosition] := FCurrentPlayer;
  UpdateAfterMove(FCurrentPlayer);
  Result := mrAccepted;
end;

procedure TGameEngine.UpdateAfterMove(APlayer: TCell);
var
  Line, I, Count: Integer;
  Marked: array[BOARD_FIRST..BOARD_LAST] of Boolean;
  HasWin: Boolean;
begin
  { Marca as células de todas as combinações completadas pelo jogador.
    Uma jogada pode fechar duas combinações ao mesmo tempo (RN-08). }
  for I := BOARD_FIRST to BOARD_LAST do
    Marked[I] := False;
  HasWin := False;
  for Line := Low(WIN_LINES) to High(WIN_LINES) do
    if (FBoard[WIN_LINES[Line, 0]] = APlayer) and
       (FBoard[WIN_LINES[Line, 1]] = APlayer) and
       (FBoard[WIN_LINES[Line, 2]] = APlayer) then
    begin
      HasWin := True;
      for I := 0 to 2 do
        Marked[WIN_LINES[Line, I]] := True;
    end;

  if HasWin then
  begin
    { Percorrer 0..8 já deixa as células em ordem crescente. }
    Count := 0;
    SetLength(FWinningCells, BOARD_LAST - BOARD_FIRST + 1);
    for I := BOARD_FIRST to BOARD_LAST do
      if Marked[I] then
      begin
        FWinningCells[Count] := I;
        Inc(Count);
      end;
    SetLength(FWinningCells, Count);
    FStatus := gsWin;
    FWinner := APlayer;
    FCurrentPlayer := ceEmpty;
  end
  else if IsBoardFull then
  begin
    { Vitória tem precedência: só chega aqui sem combinação completa (RN-09). }
    FStatus := gsDraw;
    FCurrentPlayer := ceEmpty;
  end
  else
    FCurrentPlayer := OtherPlayer(FCurrentPlayer);
end;

function TGameEngine.IsBoardFull: Boolean;
var
  I: Integer;
begin
  for I := BOARD_FIRST to BOARD_LAST do
    if FBoard[I] = ceEmpty then
      Exit(False);
  Result := True;
end;

function TGameEngine.GetSnapshot: TGameSnapshot;
begin
  Result.Board := FBoard;   { array estático: copiado por valor }
  Result.Status := FStatus;
  Result.CurrentPlayer := FCurrentPlayer;
  Result.Winner := FWinner;
  { Array dinâmico é compartilhado por referência: Copy cria um novo (DT-18). }
  Result.WinningCells := Copy(FWinningCells);
end;

end.
