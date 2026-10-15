program EngineCheck;

{ Testes sem HTTP e sem interface (docs/test-plan.md, seções 9.1 e 9.3):
  - M:  motor do jogo (uGameEngine)
  - SV: serviço de jogo (uGameService), incluindo várias threads
  - J:  conversões JSON (uGameJson)
  Código de saída: 0 = todos os casos passaram; 1 = houve falha. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  uGameEngine in 'src\uGameEngine.pas',
  uGameService in 'src\uGameService.pas',
  uGameJson in 'src\uGameJson.pas',
  uMiniTest in 'tests\uMiniTest.pas',
  uEngineTests in 'tests\uEngineTests.pas',
  uServiceTests in 'tests\uServiceTests.pas',
  uJsonTests in 'tests\uJsonTests.pas';

begin
  SetConsoleOutputCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  Writeln('EngineCheck - testes do motor, do serviço e do JSON do Jogo da Velha');
  Writeln('Compilador: Delphi CompilerVersion ', CompilerVersion:0:1);
  Writeln;
  try
    RunEngineTests;
    RunServiceTests;
    RunJsonTests;
    PrintSummary;
    if TotalFailedCases > 0 then
      ExitCode := 1
    else
      ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('Erro fatal: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
