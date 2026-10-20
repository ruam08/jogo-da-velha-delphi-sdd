unit uSpikeLog;

{ Prova de conceito da Entrega O0 (descartavel).
  Log no console em UTF-8, seguro para varias threads, e relogio monotonico. }

interface

procedure InitLog;
procedure Log(const AMessage: string); overload;
procedure Log(const AFormat: string; const AArgs: array of const); overload;
{ Milissegundos desde o inicio do processo (monotonico). }
function NowMs: Int64;

implementation

uses
  Winapi.Windows, System.SysUtils, System.SyncObjs, System.Diagnostics;

var
  LogLock: TCriticalSection;
  Watch: TStopwatch;

procedure InitLog;
begin
  SetConsoleOutputCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
end;

procedure Log(const AMessage: string);
begin
  LogLock.Enter;
  try
    Writeln(FormatDateTime('hh:nn:ss.zzz', Now), '  ', AMessage);
    Flush(Output);
  finally
    LogLock.Leave;
  end;
end;

procedure Log(const AFormat: string; const AArgs: array of const);
begin
  Log(Format(AFormat, AArgs));
end;

function NowMs: Int64;
begin
  Result := Watch.ElapsedMilliseconds;
end;

initialization
  LogLock := TCriticalSection.Create;
  Watch := TStopwatch.StartNew;

finalization
  LogLock.Free;

end.
