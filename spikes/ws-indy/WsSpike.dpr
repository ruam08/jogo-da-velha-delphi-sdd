program WsSpike;

{ Prova de conceito da Entrega O0 (descartavel): WebSocket sobre o
  TIdHTTPServer do Indy que acompanha o Delphi 10.1 Berlin.
  Nao faz parte do servidor do jogo e nao e compilado pelo scripts\build.cmd.

  Uso:
    WsSpike.exe --selftest                 autoteste do protocolo, sem rede
    WsSpike.exe [--port 8790] [--idle-seconds 60]
  Encerrar: Ctrl+C, ou o evento nomeado Local\WsSpikeStop_<porta>. }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.SyncObjs,
  System.Diagnostics,
  IdGlobal,
  uSpikeLog in 'src\uSpikeLog.pas',
  uWsCodec in 'src\uWsCodec.pas',
  uWsSelfTest in 'src\uWsSelfTest.pas',
  uWsSpikeServer in 'src\uWsSpikeServer.pas';

var
  StopEvent: TEvent;
  CtrlSignal: Integer = -1;

function ConsoleCtrlHandler(ACtrlType: DWORD): BOOL; stdcall;
begin
  case ACtrlType of
    CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT:
      begin
        CtrlSignal := Integer(ACtrlType);
        if Assigned(StopEvent) then
          StopEvent.SetEvent;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

function ReadOptions(out APort, AIdleSeconds: Integer; out ASelfTest: Boolean): Boolean;
var
  I: Integer;
begin
  APort := 8790;
  AIdleSeconds := 60;
  ASelfTest := False;
  Result := True;
  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--selftest') then
      ASelfTest := True
    else if SameText(ParamStr(I), '--port') then
    begin
      if (I = ParamCount) or not TryStrToInt(ParamStr(I + 1), APort) or (APort < 1) or (APort > 65535) then
        Exit(False);
      Inc(I);
    end
    else if SameText(ParamStr(I), '--idle-seconds') then
    begin
      if (I = ParamCount) or not TryStrToInt(ParamStr(I + 1), AIdleSeconds) or (AIdleSeconds < 1) then
        Exit(False);
      Inc(I);
    end
    else
      Exit(False);
    Inc(I);
  end;
end;

function SignalName: string;
begin
  case CtrlSignal of
    CTRL_C_EVENT: Result := 'Ctrl+C';
    CTRL_BREAK_EVENT: Result := 'Ctrl+Break';
    CTRL_CLOSE_EVENT: Result := 'fechamento do console';
  else
    Result := 'evento nomeado';
  end;
end;

procedure Run;
var
  Port, IdleSeconds, Remaining: Integer;
  SelfTest: Boolean;
  Server: TSpikeServer;
  Watch: TStopwatch;
begin
  Watch := TStopwatch.Create;
  if not ReadOptions(Port, IdleSeconds, SelfTest) then
  begin
    Log('Parametros invalidos. Uso: WsSpike.exe [--selftest] [--port N] [--idle-seconds N]');
    ExitCode := 2;
    Exit;
  end;

  Log('WsSpike - prova de conceito WebSocket (Entrega O0)');
  Log('Delphi CompilerVersion %.1f | Indy compilado: %s', [CompilerVersion, gsIdVersion]);

  if SelfTest then
  begin
    ExitCode := RunSelfTest;
    Exit;
  end;

  StopEvent := TEvent.Create(nil, True, False, 'Local\WsSpikeStop_' + IntToStr(Port));
  try
    SetConsoleCtrlHandler(@ConsoleCtrlHandler, True);
    try
      Server := TSpikeServer.Create(Port, IdleSeconds,
        ExtractFilePath(ParamStr(0)) + '..\page.html');
      try
        try
          Server.Start;
        except
          on E: Exception do
          begin
            Log('Nao foi possivel iniciar na porta %d: %s', [Port, E.Message]);
            ExitCode := 1;
            Exit;
          end;
        end;
        Log('PRONTO em http://127.0.0.1:%d (inatividade: %d s)', [Port, IdleSeconds]);

        StopEvent.WaitFor(INFINITE);

        Watch := TStopwatch.StartNew;
        Log('Encerramento solicitado por %s. Canais abertos: %d', [SignalName, Server.ActiveSessions]);
        Server.BeginShutdown;
        Remaining := Server.WaitSessions(2000);
        Log('Canais restantes depois do aviso 1001: %d (%d ms)', [Remaining, Watch.ElapsedMilliseconds]);
        Server.Stop;
      finally
        Server.Free;
      end;
      Log('ENCERRADO em %d ms', [Watch.ElapsedMilliseconds]);
      ExitCode := 0;
    finally
      SetConsoleCtrlHandler(@ConsoleCtrlHandler, False);
    end;
  finally
    FreeAndNil(StopEvent);
  end;
end;

begin
  InitLog;
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
