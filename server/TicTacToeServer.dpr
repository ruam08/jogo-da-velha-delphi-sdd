program TicTacToeServer;

{ Servidor do Jogo da Velha - Delphi 10.1 Berlin + Indy 10.
  Uso: TicTacToeServer.exe [--port 8765] [--www <pasta>]
    --www: pasta com index.html, style.css e app.js. Padrão: a pasta "web"
           do repositório (<pasta do exe>\..\..\web).
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
  uHttpApp in 'src\uHttpApp.pas';

const
  DEFAULT_PORT = 8765;

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

{ Lê --port N e --www <pasta> da linha de comando.
  Retorna False se algum valor for inválido. }
function ReadOptions(out APort: Integer; out AWebRoot: string): Boolean;
var
  I: Integer;
begin
  APort := DEFAULT_PORT;
  AWebRoot := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\web');
  Result := True;
  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--port') then
    begin
      if (I = ParamCount) or not TryStrToInt(ParamStr(I + 1), APort)
        or (APort < 1) or (APort > 65535) then
        Exit(False);
      Inc(I);
    end
    else if SameText(ParamStr(I), '--www') then
    begin
      if I = ParamCount then
        Exit(False);
      AWebRoot := ParamStr(I + 1);
      Inc(I);
    end;
    Inc(I);
  end;
  AWebRoot := TPath.GetFullPath(AWebRoot);
end;

procedure Run;
var
  Port: Integer;
  WebRoot: string;
  Server: TGameHttpServer;
begin
  if not ReadOptions(Port, WebRoot) then
  begin
    Log('Parâmetros inválidos. Uso: TicTacToeServer.exe [--port 1-65535] [--www <pasta>]');
    ExitCode := 2;
    Exit;
  end;

  StopEvent := TEvent.Create(nil, True, False, '');
  try
    SetConsoleCtrlHandler(@ConsoleCtrlHandler, True);
    try
      Server := TGameHttpServer.Create(Port, WebRoot);
      try
        try
          Server.Start;
        except
          on E: Exception do
          begin
            Log('Não foi possível iniciar o servidor na porta %d ' +
              '(a porta pode estar em uso): %s', [Port, E.Message]);
            ExitCode := 1;
            Exit;
          end;
        end;

        Log('Servidor iniciado em http://127.0.0.1:%d', [Port]);
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
