program TicTacToeServer;

{ Servidor do Jogo da Velha - Delphi 10.1 Berlin + Indy 10.
  Uso: TicTacToeServer.exe [--port 8765] [--www <pasta>] [--bind <IPv4>] [--public]
       [--room-ttl-seconds N] [--remember-seconds N] [--sweep-ms N]
       [--max-rooms N] [--max-connections N] [--allowed-origin <url>[,<url>...]]
       [--ws-hello-seconds N] [--ws-idle-seconds N]
       [--rate-create N] [--rate-join N] [--rate-ws N] [--rate-window-seconds N]
       [--ws-per-client N] [--ws-msg-rate N] [--http-timeout-seconds N] [--trust-proxy]
    --www:  pasta com index.html, style.css e app.js. Padrão: a pasta "web"
            do repositório (<pasta do exe>\..\..\web).
    --bind: endereço de escuta. Padrão 0.0.0.0 (rede local); 127.0.0.1 só
            neste computador. Detalhes em uServerOptions.
  Encerrar: Ctrl+C. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.SyncObjs,
  System.IOUtils,
  uConsoleLog in 'src\uConsoleLog.pas',
  uGameEngine in 'src\uGameEngine.pas',
  uGameService in 'src\uGameService.pas',
  uGameJson in 'src\uGameJson.pas',
  uClock in 'src\uClock.pas',
  uSecureRandom in 'src\uSecureRandom.pas',
  uRoom in 'src\uRoom.pas',
  uRoomRegistry in 'src\uRoomRegistry.pas',
  uRoomJson in 'src\uRoomJson.pas',
  uRoomHttp in 'src\uRoomHttp.pas',
  uOriginPolicy in 'src\uOriginPolicy.pas',
  uRoomHub in 'src\uRoomHub.pas',
  uWebSocket in 'src\uWebSocket.pas',
  uWsSession in 'src\uWsSession.pas',
  uRoomJanitor in 'src\uRoomJanitor.pas',
  uRateLimiter in 'src\uRateLimiter.pas',
  uRequestLimits in 'src\uRequestLimits.pas',
  uServerOptions in 'src\uServerOptions.pas',
  uHttpApp in 'src\uHttpApp.pas';

var
  StopEvent: TEvent;

{ Chamado pelo Windows em uma thread própria quando o usuário pressiona
  Ctrl+C ou fecha a janela. Apenas sinaliza; o desligamento acontece na
  thread principal. }
function ConsoleCtrlHandler(ACtrlType: DWORD): BOOL; stdcall;
begin
  case ACtrlType of
    CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT:
      begin
        StopEvent.SetEvent;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

{ "sem limite" para 0 (O6). }
function LimitText(AValue: Integer): string;
begin
  if AValue <= 0 then
    Result := 'sem limite'
  else
    Result := IntToStr(AValue);
end;

{ Argumentos da linha de comando, sem o nome do programa. }
function CommandLineArgs: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, ParamCount);
  for I := 1 to ParamCount do
    Result[I - 1] := ParamStr(I);
end;

procedure Run;
var
  Options: TServerOptions;
  OptionsError: string;
  Port: Integer;
  WebRoot: string;
  Server: TGameHttpServer;
begin
  if not ParseServerOptions(CommandLineArgs,
    TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\web'), Options, OptionsError) or
    not ValidateServerOptions(Options, OptionsError) then
  begin
    Log('Parâmetros inválidos: %s. %s', [OptionsError, SERVER_USAGE]);
    ExitCode := 2;
    Exit;
  end;
  Options.WebRoot := TPath.GetFullPath(Options.WebRoot);
  Port := Options.Port;
  WebRoot := Options.WebRoot;

  StopEvent := TEvent.Create(nil, True, False, '');
  try
    SetConsoleCtrlHandler(@ConsoleCtrlHandler, True);
    try
      Server := TGameHttpServer.Create(Options);
      try
        try
          Server.Start;
        except
          on E: Exception do
          begin
            Log('Não foi possível iniciar o servidor em %s:%d ' +
              '(a porta pode estar em uso ou o endereço não existe neste computador): %s',
              [Options.BindIP, Port, E.Message]);
            ExitCode := 1;
            Exit;
          end;
        end;

        Log('Servidor iniciado em http://127.0.0.1:%d', [Port]);
        if Options.BindIP = '0.0.0.0' then
          Log('Escutando em %s:%d (todas as interfaces IPv4: este computador e a rede local)', [Options.BindIP, Port])
        else
          Log('Escutando em %s:%d', [Options.BindIP, Port]);
        if Options.PublicMode then
          Log('Modo --public: escuta padrão em 127.0.0.1; canal e salas só com as origens https configuradas; ' +
            'canal sem Origin recusado; /api/game* desativadas (404); / leva a /online.html.');
        { O6 (docs/plan-online.md, seção 13.1). }
        Log('Limites: %d conexões simultâneas; %d salas abertas; corpo até %d KB; leitura em até %d s; ' +
          'por cliente, a cada %d s: criação de salas %s, consulta/entrada %s, abertura de canal %s; ' +
          'canais simultâneos por cliente %s; mensagens por canal a cada 10 s %s',
          [Options.MaxConnections, Options.MaxRooms, MAX_REQUEST_BODY_BYTES div 1024,
          Options.HttpTimeoutSeconds, Options.RateWindowSeconds, LimitText(Options.RateCreate),
          LimitText(Options.RateJoin), LimitText(Options.RateWs), LimitText(Options.WsPerClient),
          LimitText(Options.WsMsgRate)]);
        if Options.TrustProxy then
          Log('--trust-proxy: com conexões de 127.0.0.1, o cliente é o último endereço de X-Forwarded-For.');
        Log('Canal em tempo real: ws://<endereço>:%d/ws (entrar em até %d s; inatividade %d s)',
          [Port, Options.WsHelloSeconds, Options.WsIdleSeconds]);
        Log('Salas: encerradas por abandono após %d s sem ninguém conectado (varredura a cada %d ms); ' +
          'lembradas por %d s depois de encerradas',
          [Options.RoomTtlSeconds, Options.SweepMs, Options.RememberSeconds]);
        Log('Verificação de saúde: http://127.0.0.1:%d/health', [Port]);
        Log('Interface: pasta %s', [WebRoot]);
        if not TFile.Exists(TPath.Combine(WebRoot, 'index.html')) then
          Log('AVISO: index.html não encontrado em %s; use --www <pasta>.', [WebRoot]);
        Log('Pressione Ctrl+C para encerrar.');

        StopEvent.WaitFor(INFINITE);

        Log('Encerrando o servidor...');
        Server.Stop;
      finally
        Server.Free;
      end;
      Log('Servidor encerrado.');
    finally
      SetConsoleCtrlHandler(@ConsoleCtrlHandler, False);
    end;
  finally
    FreeAndNil(StopEvent);
  end;
end;

begin
  InitConsoleLog;
  try
    Run;
  except
    on E: Exception do
    begin
      Log('Erro fatal: %s: %s', [E.ClassName, E.Message]);
      ExitCode := 1;
    end;
  end;
end.
