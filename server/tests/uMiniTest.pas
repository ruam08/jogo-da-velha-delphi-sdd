unit uMiniTest;

{ Mini-framework de testes para programas console (sem DUnitX).
  - Cada caso é uma procedure registrada com RunCase.
  - Asserções "suaves": o caso continua depois de uma falha e lista todas.
  - Uma exceção dentro do caso conta como falha, sem derrubar a suíte.
  - TotalFailedCases > 0 indica que o programa deve sair com código 1. }

interface

uses
  System.SysUtils;

procedure RunCase(const AId, ADescription: string; ACase: TProc);
procedure Check(ACondition: Boolean; const AMessage: string);
procedure CheckEqualsInt(AExpected, AActual: Integer; const AWhat: string);
procedure CheckEqualsStr(const AExpected, AActual, AWhat: string);
procedure Note(const AMessage: string);

function TotalCases: Integer;
function TotalFailedCases: Integer;
function TotalChecks: Integer;
procedure PrintSummary;

implementation

uses
  Winapi.Windows;

var
  { Variáveis globais começam zeradas/vazias no Delphi. }
  GCaseCount: Integer;
  GFailedCases: Integer;
  GCheckCount: Integer;
  GCurrentFailures: Integer;
  GCurrentMessages: string;
  GFailedIds: string;

const
  MAX_MESSAGES_PER_CASE = 20;

procedure AddFailure(const AMessage: string);
begin
  Inc(GCurrentFailures);
  { Limita a saída: o teste exaustivo poderia gerar milhares de mensagens. }
  if GCurrentFailures <= MAX_MESSAGES_PER_CASE then
    GCurrentMessages := GCurrentMessages + '         - ' + AMessage + sLineBreak
  else if GCurrentFailures = MAX_MESSAGES_PER_CASE + 1 then
    GCurrentMessages := GCurrentMessages +
      '         - (demais falhas omitidas)' + sLineBreak;
end;

procedure RunCase(const AId, ADescription: string; ACase: TProc);
var
  StartTick: Cardinal;
  Elapsed: Cardinal;
begin
  Inc(GCaseCount);
  GCurrentFailures := 0;
  GCurrentMessages := '';
  StartTick := GetTickCount;
  try
    ACase();
  except
    on E: Exception do
      AddFailure(Format('Exceção %s: %s', [E.ClassName, E.Message]));
  end;
  Elapsed := GetTickCount - StartTick;
  if GCurrentFailures = 0 then
    Writeln(Format('[OK]     %-9s %s (%d ms)', [AId, ADescription, Integer(Elapsed)]))
  else
  begin
    Inc(GFailedCases);
    GFailedIds := GFailedIds + ' ' + AId;
    Writeln(Format('[FALHOU] %-9s %s (%d falha(s))', [AId, ADescription,
      GCurrentFailures]));
  end;
  { Notas (Note) aparecem sempre; mensagens de falha só existem se o caso falhou. }
  Write(GCurrentMessages);
  Flush(Output);
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  Inc(GCheckCount);
  if not ACondition then
    AddFailure(AMessage);
end;

procedure CheckEqualsInt(AExpected, AActual: Integer; const AWhat: string);
begin
  Check(AExpected = AActual,
    Format('%s: esperado %d, obtido %d', [AWhat, AExpected, AActual]));
end;

procedure CheckEqualsStr(const AExpected, AActual, AWhat: string);
begin
  Check(AExpected = AActual,
    Format('%s: esperado "%s", obtido "%s"', [AWhat, AExpected, AActual]));
end;

procedure Note(const AMessage: string);
begin
  GCurrentMessages := GCurrentMessages + '         · ' + AMessage + sLineBreak;
end;

function TotalCases: Integer;
begin
  Result := GCaseCount;
end;

function TotalFailedCases: Integer;
begin
  Result := GFailedCases;
end;

function TotalChecks: Integer;
begin
  Result := GCheckCount;
end;

procedure PrintSummary;
begin
  Writeln;
  Writeln(Format('Casos: %d | Aprovados: %d | Falharam: %d | Verificações: %d',
    [GCaseCount, GCaseCount - GFailedCases, GFailedCases, GCheckCount]));
  if GFailedCases > 0 then
    Writeln('Casos com falha:' + GFailedIds);
  if (GFailedCases = 0) and (GCaseCount > 0) then
    Writeln('RESULTADO: APROVADO')
  else
    Writeln('RESULTADO: REPROVADO');
  Flush(Output);
end;

end.
