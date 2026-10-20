program EngineCheck;

{ Testes sem HTTP e sem interface (docs/test-plan.md, seções 9.1 e 9.3, e
  docs/test-plan-online.md, seção 5):
  - M:  motor do jogo (uGameEngine)
  - SV: serviço de jogo (uGameService), incluindo várias threads
  - J:  conversões JSON (uGameJson)
  - SL, MEM: domínio das salas do modo online (uRoom, uRoomRegistry)
  - SC: salas sob acesso simultâneo
  - RJ: JSON do modo online (uRoomJson)
  - OP: opções da linha de comando (uServerOptions)
  - WS: protocolo WebSocket (uWebSocket) e política de origem (uOriginPolicy)
  - HB: hub e caixas de saída (uRoomHub)
  - JN: faxineiro das salas (uRoomJanitor)
  - RL, OP-03: limites da O6 (uRateLimiter, uRequestLimits, opções novas)
  Código de saída: 0 = todos os casos passaram; 1 = houve falha. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  uGameEngine in 'src\uGameEngine.pas',
  uGameService in 'src\uGameService.pas',
  uGameJson in 'src\uGameJson.pas',
  uClock in 'src\uClock.pas',
  uSecureRandom in 'src\uSecureRandom.pas',
  uRoom in 'src\uRoom.pas',
  uRoomRegistry in 'src\uRoomRegistry.pas',
  uRoomJson in 'src\uRoomJson.pas',
  uOriginPolicy in 'src\uOriginPolicy.pas',
  uRoomHub in 'src\uRoomHub.pas',
  uWebSocket in 'src\uWebSocket.pas',
  uServerOptions in 'src\uServerOptions.pas',
  uRoomJanitor in 'src\uRoomJanitor.pas',
  uRateLimiter in 'src\uRateLimiter.pas',
  uRequestLimits in 'src\uRequestLimits.pas',
  uMiniTest in 'tests\uMiniTest.pas',
  uEngineTests in 'tests\uEngineTests.pas',
  uServiceTests in 'tests\uServiceTests.pas',
  uJsonTests in 'tests\uJsonTests.pas',
  uRoomTests in 'tests\uRoomTests.pas',
  uRoomConcurrencyTests in 'tests\uRoomConcurrencyTests.pas',
  uRoomJsonTests in 'tests\uRoomJsonTests.pas',
  uOptionsTests in 'tests\uOptionsTests.pas',
  uWebSocketTests in 'tests\uWebSocketTests.pas',
  uRoomHubTests in 'tests\uRoomHubTests.pas',
  uRoomJanitorTests in 'tests\uRoomJanitorTests.pas',
  uLimitTests in 'tests\uLimitTests.pas';

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
    RunRoomTests;
    RunRoomConcurrencyTests;
    RunRoomJsonTests;
    RunOptionsTests;
    RunWebSocketTests;
    RunRoomHubTests;
    RunRoomJanitorTests;
    RunLimitTests;
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
