unit uRoomJanitor;

(* Faxineiro das salas (docs/plan-online.md, secao 11.2; Entrega O5).

  Uma thread propria que, a cada AIntervalMs (--sweep-ms), chama
  Registry.Sweep(ATtlMs):
  - encerra com ABANDONO as salas sem nenhum lugar conectado ha mais de
    ATtlMs desde a ultima mudanca aceita (CloseAbandoned, na secao critica de
    cada sala: uma sala com alguem conectado nunca e encerrada);
  - passa as salas encerradas para "lembradas" e esquece as lembradas ha mais
    do periodo de lembranca.
  As salas encerradas agora sao entregues a AOnClosed (que publica
  sala_encerrada no hub e registra no console), fora de qualquer secao critica
  do registro ou das salas.

  Parada (Stop): sinaliza um evento e espera a thread terminar. Depois que
  Stop retorna, nenhuma varredura nem chamada de AOnClosed acontece; a ordem
  de desligamento (secao 11.3) para o faxineiro antes de liberar o hub e o
  registro.

  Sem dependencia de Indy, HTTP, JSON ou console. *)

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, uRoom, uRoomRegistry;

type
  TClosedRoomsProc = reference to procedure(const AClosed: TArray<TRoomSnapshot>);
  TJanitorErrorProc = reference to procedure(const AMessage: string);

  TRoomJanitor = class
  private
    FRegistry: TRoomRegistry;
    FTtlMs: Int64;
    FIntervalMs: Cardinal;
    FOnClosed: TClosedRoomsProc;
    FOnError: TJanitorErrorProc;
    FStopEvent: TEvent;
    FThread: TThread;
    FSweeps: Int64;
    FClosedTotal: Int64;
    FErrors: Int64;
    procedure Run;
  public
    constructor Create(ARegistry: TRoomRegistry; ATtlMs: Int64; AIntervalMs: Cardinal;
      const AOnClosed: TClosedRoomsProc; const AOnError: TJanitorErrorProc);
    destructor Destroy; override;
    { Inicia a thread (uma vez). }
    procedure Start;
    { Para a thread e espera o fim da varredura em andamento. Pode ser chamado
      mais de uma vez, e tambem sem Start. }
    procedure Stop;
    function Running: Boolean;
    function Sweeps: Int64;
    function ClosedTotal: Int64;
    function Errors: Int64;
  end;

implementation

constructor TRoomJanitor.Create(ARegistry: TRoomRegistry; ATtlMs: Int64; AIntervalMs: Cardinal;
  const AOnClosed: TClosedRoomsProc; const AOnError: TJanitorErrorProc);
begin
  inherited Create;
  FRegistry := ARegistry;
  FTtlMs := ATtlMs;
  FIntervalMs := AIntervalMs;
  FOnClosed := AOnClosed;
  FOnError := AOnError;
  FStopEvent := TEvent.Create(nil, True, False, '');
end;

destructor TRoomJanitor.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TRoomJanitor.Start;
begin
  if FThread <> nil then
    Exit;
  FStopEvent.ResetEvent;
  FThread := TThread.CreateAnonymousThread(Run);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TRoomJanitor.Stop;
begin
  if FThread = nil then
    Exit;
  FStopEvent.SetEvent;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

function TRoomJanitor.Running: Boolean;
begin
  Result := FThread <> nil;
end;

procedure TRoomJanitor.Run;
var
  Closed: TArray<TRoomSnapshot>;
begin
  { Espera o intervalo ou o pedido de parada; varre so quando o prazo vence. }
  while FStopEvent.WaitFor(FIntervalMs) = wrTimeout do
  begin
    try
      Closed := FRegistry.Sweep(FTtlMs);
      TInterlocked.Increment(FSweeps);
      if Length(Closed) > 0 then
      begin
        TInterlocked.Add(FClosedTotal, Int64(Length(Closed)));
        if Assigned(FOnClosed) then
          FOnClosed(Closed);
      end;
    except
      on E: Exception do
      begin
        TInterlocked.Increment(FErrors);
        if Assigned(FOnError) then
        try
          FOnError(E.ClassName + ': ' + E.Message);
        except
          { o relato do erro nunca derruba o faxineiro }
        end;
      end;
    end;
  end;
end;

function TRoomJanitor.Sweeps: Int64;
begin
  Result := TInterlocked.Read(FSweeps);
end;

function TRoomJanitor.ClosedTotal: Int64;
begin
  Result := TInterlocked.Read(FClosedTotal);
end;

function TRoomJanitor.Errors: Int64;
begin
  Result := TInterlocked.Read(FErrors);
end;

end.
