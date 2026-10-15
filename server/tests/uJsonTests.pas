unit uJsonTests;

{ Casos J do docs/test-plan.md (seção 9.3): testam uGameJson diretamente,
  sem HTTP. }

interface

procedure RunJsonTests;

implementation

uses
  System.SysUtils, System.JSON, uMiniTest, uGameEngine, uGameJson;

function Utf8(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

function MoveBodyResultStr(AResult: TMoveBodyResult): string;
begin
  case AResult of
    mbOk: Result := 'mbOk';
    mbInvalidBody: Result := 'mbInvalidBody';
  else
    Result := 'mbInvalidPosition';
  end;
end;

procedure ExpectParse(const ABody: TBytes; AExpected: TMoveBodyResult;
  AExpectedPosition: Integer; const ALabel: string);
var
  R: TMoveBodyResult;
  Position: Integer;
begin
  Position := -999;
  try
    R := ParseMoveBody(ABody, Position);
  except
    on E: Exception do
    begin
      Check(False, Format('%s: exceção %s: %s', [ALabel, E.ClassName, E.Message]));
      Exit;
    end;
  end;
  CheckEqualsStr(MoveBodyResultStr(AExpected), MoveBodyResultStr(R), ALabel);
  if (AExpected = mbOk) and (R = mbOk) then
    CheckEqualsInt(AExpectedPosition, Position, ALabel + ' (posição)');
end;

{ ---- J-01 ---------------------------------------------------------------- }

procedure J01_SnapshotToJson;
var
  E: TGameEngine;
begin
  E := TGameEngine.Create;
  try
    CheckEqualsStr(
      '{"tabuleiro":["","","","","","","","",""],"status":"EM_ANDAMENTO",' +
      '"jogadorDaVez":"X","vencedor":null,"celulasVencedoras":[]}',
      SnapshotToJson(E.GetSnapshot), 'estado inicial');

    E.Play(0); E.Play(4);
    CheckEqualsStr(
      '{"tabuleiro":["X","","","","O","","","",""],"status":"EM_ANDAMENTO",' +
      '"jogadorDaVez":"X","vencedor":null,"celulasVencedoras":[]}',
      SnapshotToJson(E.GetSnapshot), 'meio da partida');

    E.Reset;
    E.Play(0); E.Play(1); E.Play(2); E.Play(3); E.Play(6);
    E.Play(5); E.Play(8); E.Play(7); E.Play(4);
    CheckEqualsStr(
      '{"tabuleiro":["X","O","X","O","X","O","X","O","X"],"status":"VITORIA",' +
      '"jogadorDaVez":null,"vencedor":"X","celulasVencedoras":[0,2,4,6,8]}',
      SnapshotToJson(E.GetSnapshot), 'vitória dupla');

    E.Reset;
    E.Play(0); E.Play(1); E.Play(2); E.Play(4); E.Play(3);
    E.Play(5); E.Play(7); E.Play(6); E.Play(8);
    CheckEqualsStr(
      '{"tabuleiro":["X","O","X","X","O","O","O","X","X"],"status":"EMPATE",' +
      '"jogadorDaVez":null,"vencedor":null,"celulasVencedoras":[]}',
      SnapshotToJson(E.GetSnapshot), 'empate');
  finally
    E.Free;
  end;
end;

{ ---- J-02 a J-04 --------------------------------------------------------- }

procedure J02_ValidBodies;
var
  P: Integer;
begin
  for P := 0 to 8 do
    ExpectParse(Utf8(Format('{"posicao":%d}', [P])), mbOk, P, Format('posicao %d', [P]));
  ExpectParse(Utf8('{"posicao":4,"simbolo":"O"}'), mbOk, 4, 'campo extra ignorado');
  ExpectParse(Utf8('  { "posicao" : 7 }  '), mbOk, 7, 'espaços em volta');
  ExpectParse(Utf8('{"posicao":-1}'), mbOk, -1, 'inteiro negativo (o intervalo é do motor)');
  ExpectParse(Utf8('{"posicao":9}'), mbOk, 9, 'inteiro 9 (o intervalo é do motor)');
  { O parser do Berlin normaliza o número: valores inteiros escritos com
    fração ou expoente valem como inteiros (plano 3.3, v0.6). }
  ExpectParse(Utf8('{"posicao":4.0}'), mbOk, 4, '4.0 vale 4');
  ExpectParse(Utf8('{"posicao":1e0}'), mbOk, 1, '1e0 vale 1');
end;

procedure J03_InvalidPositions;
begin
  ExpectParse(Utf8('{"posicao":4.5}'), mbInvalidPosition, 0, '4.5');
  ExpectParse(Utf8('{"posicao":0.5}'), mbInvalidPosition, 0, '0.5');
  ExpectParse(Utf8('{"posicao":4e-1}'), mbInvalidPosition, 0, '4e-1');
  ExpectParse(Utf8('{"posicao":"4"}'), mbInvalidPosition, 0, 'texto "4"');
  ExpectParse(Utf8('{"posicao":null}'), mbInvalidPosition, 0, 'null');
  ExpectParse(Utf8('{"posicao":true}'), mbInvalidPosition, 0, 'true');
  ExpectParse(Utf8('{"posicao":99999999999}'), mbInvalidPosition, 0, '99999999999');
  ExpectParse(Utf8('{}'), mbInvalidPosition, 0, 'objeto vazio');
  ExpectParse(Utf8('{"Posicao":4}'), mbInvalidPosition, 0, 'nome com maiúscula');
  ExpectParse(Utf8('{"posicao":[4]}'), mbInvalidPosition, 0, 'array');
end;

procedure J04_InvalidBodies;
var
  Bad: TBytes;
begin
  ExpectParse(nil, mbInvalidBody, 0, 'sem corpo');
  ExpectParse(Utf8(''), mbInvalidBody, 0, 'corpo vazio');
  ExpectParse(Utf8('abc'), mbInvalidBody, 0, 'abc');
  ExpectParse(Utf8('{"posicao":'), mbInvalidBody, 0, 'JSON incompleto');
  ExpectParse(Utf8('[4]'), mbInvalidBody, 0, 'array no topo');
  ExpectParse(Utf8('4'), mbInvalidBody, 0, 'número no topo');
  ExpectParse(Utf8('"x"'), mbInvalidBody, 0, 'texto no topo');

  { JSON válido se os bytes fossem ignorados, mas com UTF-8 inválido. }
  Bad := Utf8('{"posicao":4,"x":"__"}');
  Bad[18] := $FF;   { os dois '_' viram bytes inválidos }
  Bad[19] := $FE;
  ExpectParse(Bad, mbInvalidBody, 0, 'UTF-8 inválido dentro de um texto');

  Bad := Utf8('{"posicao":4}_');
  Bad[13] := $C3;   { início de sequência de 2 bytes sem continuação }
  ExpectParse(Bad, mbInvalidBody, 0, 'sequência UTF-8 incompleta no fim');
end;

{ ---- J-05 ---------------------------------------------------------------- }

procedure J05_ErrorToJson;
var
  Json: string;
  Value: TJSONValue;
  Root, Error: TJSONObject;
begin
  Json := ErrorToJson(ERR_CELL_OCCUPIED, MSG_CELL_OCCUPIED);
  Value := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetBytes(Json), 0, True);
  try
    Check(Value is TJSONObject, 'o erro não é um objeto JSON: ' + Json);
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    CheckEqualsInt(1, Root.Count, 'campos no topo');
    Check(Root.GetValue('erro') is TJSONObject, 'campo "erro" ausente: ' + Json);
    if not (Root.GetValue('erro') is TJSONObject) then
      Exit;
    Error := TJSONObject(Root.GetValue('erro'));
    CheckEqualsInt(2, Error.Count, 'campos em "erro"');
    CheckEqualsStr('CELULA_OCUPADA', Error.GetValue('codigo').Value, 'codigo');
    CheckEqualsStr('Esta célula já está ocupada.', Error.GetValue('mensagem').Value,
      'mensagem com acentos');
  finally
    Value.Free;
  end;

  CheckEqualsStr('A partida já terminou. Clique em "Nova partida" para jogar novamente.',
    MSG_GAME_OVER, 'mensagem de partida encerrada');
  CheckEqualsStr('A posição deve ser um número inteiro de 0 a 8.',
    MSG_INVALID_POSITION, 'mensagem de posição inválida');
  CheckEqualsStr('O corpo da requisição deve ser um objeto JSON válido.',
    MSG_INVALID_BODY, 'mensagem de corpo inválido');
end;

procedure RunJsonTests;
begin
  RunCase('J-01', 'SnapshotToJson segue o contrato (campos, ordem, null, [])', J01_SnapshotToJson);
  RunCase('J-02', 'ParseMoveBody aceita corpos válidos', J02_ValidBodies);
  RunCase('J-03', 'ParseMoveBody recusa posições de valor não inteiro ou que não são números', J03_InvalidPositions);
  RunCase('J-04', 'ParseMoveBody recusa corpos inválidos (incluindo UTF-8 inválido)', J04_InvalidBodies);
  RunCase('J-05', 'ErrorToJson gera o formato de erro com acentos preservados', J05_ErrorToJson);
end;

end.
