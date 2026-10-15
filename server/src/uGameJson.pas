unit uGameJson;

{ Conversões entre o estado do jogo e o JSON do contrato HTTP
  (docs/plan.md, seções 3.2 a 3.4). Não conhece Indy nem HTTP. }

interface

uses
  System.SysUtils, uGameEngine;

type
  TMoveBodyResult = (mbOk, mbInvalidBody, mbInvalidPosition);

const
  ERR_INVALID_BODY = 'CORPO_INVALIDO';
  ERR_INVALID_POSITION = 'POSICAO_INVALIDA';
  ERR_GAME_OVER = 'PARTIDA_ENCERRADA';
  ERR_CELL_OCCUPIED = 'CELULA_OCUPADA';
  ERR_ROUTE_NOT_FOUND = 'ROTA_NAO_ENCONTRADA';
  ERR_METHOD_NOT_ALLOWED = 'METODO_NAO_PERMITIDO';
  ERR_INTERNAL = 'ERRO_INTERNO';

  MSG_INVALID_BODY = 'O corpo da requisição deve ser um objeto JSON válido.';
  MSG_INVALID_POSITION = 'A posição deve ser um número inteiro de 0 a 8.';
  MSG_GAME_OVER = 'A partida já terminou. Clique em "Nova partida" para jogar novamente.';
  MSG_CELL_OCCUPIED = 'Esta célula já está ocupada.';
  MSG_ROUTE_NOT_FOUND = 'Rota não encontrada.';
  MSG_METHOD_NOT_ALLOWED = 'Método não permitido para esta rota.';
  MSG_INTERNAL = 'Erro interno no servidor.';

(* Estado -> {"tabuleiro":[...],"status":...,"jogadorDaVez":...,
   "vencedor":...,"celulasVencedoras":[...]}
   Este comentário usa parênteses com asterisco porque, entre chaves, o
   primeiro fecha-chaves do JSON encerraria o comentário. *)
function SnapshotToJson(const AState: TGameSnapshot): string;

(* {"erro":{"codigo":...,"mensagem":...}} *)
function ErrorToJson(const ACode, AMessage: string): string;

{ Lê o corpo de POST /api/game/moves. mbOk só quando o corpo é um objeto JSON
  em UTF-8 válido e "posicao" é um número de valor inteiro que cabe em
  Integer. O intervalo 0..8 é verificado pelo motor (RN-15). }
function ParseMoveBody(const ABody: TBytes; out APosition: Integer): TMoveBodyResult;

{ True se os bytes formam UTF-8 válido (sem sequências truncadas, longas
  demais, substitutos UTF-16 ou valores acima de U+10FFFF). }
function IsValidUtf8(const ABytes: TBytes): Boolean;

implementation

uses
  System.JSON;

function CellText(ACell: TCell): string;
begin
  case ACell of
    ceX: Result := 'X';
    ceO: Result := 'O';
  else
    Result := '';
  end;
end;

function StatusText(AStatus: TGameStatus): string;
begin
  case AStatus of
    gsInProgress: Result := 'EM_ANDAMENTO';
    gsWin: Result := 'VITORIA';
  else
    Result := 'EMPATE';
  end;
end;

{ "X"/"O" ou null. }
function PlayerValue(ACell: TCell): TJSONValue;
begin
  if ACell = ceEmpty then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(CellText(ACell));
end;

function SnapshotToJson(const AState: TGameSnapshot): string;
var
  Root: TJSONObject;
  Board, Cells: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Board := TJSONArray.Create;
    Root.AddPair('tabuleiro', Board);
    for I := Low(AState.Board) to High(AState.Board) do
      Board.AddElement(TJSONString.Create(CellText(AState.Board[I])));
    Root.AddPair('status', StatusText(AState.Status));
    Root.AddPair('jogadorDaVez', PlayerValue(AState.CurrentPlayer));
    Root.AddPair('vencedor', PlayerValue(AState.Winner));
    Cells := TJSONArray.Create;
    Root.AddPair('celulasVencedoras', Cells);
    for I := 0 to High(AState.WinningCells) do
      Cells.AddElement(TJSONNumber.Create(AState.WinningCells[I]));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function ErrorToJson(const ACode, AMessage: string): string;
var
  Root, Error: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Error := TJSONObject.Create;
    Root.AddPair('erro', Error);
    Error.AddPair('codigo', ACode);
    Error.AddPair('mensagem', AMessage);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function IsValidUtf8(const ABytes: TBytes): Boolean;
var
  I, J, Count, Need: Integer;
  Lead: Byte;
  CodePoint, MinCodePoint: Cardinal;
begin
  I := 0;
  Count := Length(ABytes);
  while I < Count do
  begin
    Lead := ABytes[I];
    if Lead < $80 then
    begin
      Inc(I);
      Continue;
    end;
    if (Lead and $E0) = $C0 then
    begin
      Need := 1;
      CodePoint := Lead and $1F;
      MinCodePoint := $80;
    end
    else if (Lead and $F0) = $E0 then
    begin
      Need := 2;
      CodePoint := Lead and $0F;
      MinCodePoint := $800;
    end
    else if (Lead and $F8) = $F0 then
    begin
      Need := 3;
      CodePoint := Lead and $07;
      MinCodePoint := $10000;
    end
    else
      Exit(False);

    if I + Need >= Count then
      Exit(False);
    for J := 1 to Need do
    begin
      if (ABytes[I + J] and $C0) <> $80 then
        Exit(False);
      CodePoint := (CodePoint shl 6) or Cardinal(ABytes[I + J] and $3F);
    end;
    if (CodePoint < MinCodePoint) or (CodePoint > $10FFFF) or
       ((CodePoint >= $D800) and (CodePoint <= $DFFF)) then
      Exit(False);
    Inc(I, Need + 1);
  end;
  Result := True;
end;

function ParseMoveBody(const ABody: TBytes; out APosition: Integer): TMoveBodyResult;
var
  Value, Field: TJSONValue;
  Obj: TJSONObject;
  I: Integer;
begin
  APosition := 0;
  if (Length(ABody) = 0) or not IsValidUtf8(ABody) then
    Exit(mbInvalidBody);

  try
    Value := TJSONObject.ParseJSONValue(ABody, 0, True);
  except
    { O parser do Berlin devolve nil para JSON inválido; a captura é só
      para qualquer exceção inesperada não virar erro 500. }
    Value := nil;
  end;
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    Exit(mbInvalidBody);
  end;

  try
    Obj := TJSONObject(Value);
    { Busca com comparação exata do nome: "Posicao" não vale (plano 3.3). }
    Field := nil;
    for I := 0 to Obj.Count - 1 do
      if Obj.Pairs[I].JsonString.Value = 'posicao' then
      begin
        Field := Obj.Pairs[I].JsonValue;
        Break;
      end;

    { Só TJSONNumber vale: TJSONString ('"4"'), TJSONNull e TJSONTrue não são.
      O parser do Berlin normaliza o texto do número (4.0 vira '4', 1e0 vira
      '1', 4.5 continua '4.5'), então TryStrToInt aceita exatamente os números
      de valor inteiro que cabem em Integer (verificado na Entrega 3, J-02/J-03). }
    if (Field is TJSONNumber) and TryStrToInt(TJSONNumber(Field).Value, APosition) then
      Result := mbOk
    else
    begin
      APosition := 0;
      Result := mbInvalidPosition;
    end;
  finally
    Value.Free;
  end;
end;

end.
