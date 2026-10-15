unit uConsoleLog;

{ Log simples no console, em UTF-8 e seguro para várias threads.
  O TIdHTTPServer atende cada conexão em uma thread, então duas requisições
  podem tentar escrever ao mesmo tempo; a seção crítica evita linhas misturadas. }

interface

procedure InitConsoleLog;
procedure Log(const AMessage: string); overload;
procedure Log(const AFormat: string; const AArgs: array of const); overload;

implementation

uses
  Winapi.Windows, System.SysUtils, System.SyncObjs;

var
  LogLock: TCriticalSection;

procedure InitConsoleLog;
begin
  { Mensagens acentuadas aparecem corretas no console e nos arquivos de log. }
  SetConsoleOutputCP(CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
end;

procedure Log(const AMessage: string);
begin
  LogLock.Enter;
  try
    Writeln(FormatDateTime('hh:nn:ss.zzz', Now), '  ', AMessage);
    { Sem Flush, a saída redirecionada para arquivo só apareceria no fim. }
    Flush(Output);
  finally
    LogLock.Leave;
  end;
end;

procedure Log(const AFormat: string; const AArgs: array of const);
begin
  Log(Format(AFormat, AArgs));
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  LogLock.Free;

end.
