unit uClock;

{ Relogio monotonico do dominio de salas (docs/plan-online.md, DTO-13).
  - TSystemClock: milissegundos desde o inicio do processo (TStopwatch, que
    usa QueryPerformanceCounter e nao volta no tempo com ajustes do relogio).
  - TManualClock: relogio controlado pelos testes (EngineCheck).
  Sem dependencia de Indy, HTTP ou JSON. }

interface

uses
  System.SyncObjs;

type
  IClock = interface
    ['{6B0E2C7A-3F61-4C1E-9B6E-8D2A4F0C51A1}']
    function NowMs: Int64;
  end;

  TSystemClock = class(TInterfacedObject, IClock)
  public
    function NowMs: Int64;
  end;

  TManualClock = class(TInterfacedObject, IClock)
  private
    FLock: TCriticalSection;
    FNow: Int64;
  public
    constructor Create(AStartMs: Int64 = 1000);
    destructor Destroy; override;
    function NowMs: Int64;
    procedure Advance(AMs: Int64);
  end;

implementation

uses
  System.Diagnostics;

var
  Watch: TStopwatch;

{ TSystemClock }

function TSystemClock.NowMs: Int64;
begin
  Result := Watch.ElapsedMilliseconds;
end;

{ TManualClock }

constructor TManualClock.Create(AStartMs: Int64);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FNow := AStartMs;
end;

destructor TManualClock.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TManualClock.NowMs: Int64;
begin
  FLock.Enter;
  try
    Result := FNow;
  finally
    FLock.Leave;
  end;
end;

procedure TManualClock.Advance(AMs: Int64);
begin
  FLock.Enter;
  try
    Inc(FNow, AMs);
  finally
    FLock.Leave;
  end;
end;

initialization
  Watch := TStopwatch.StartNew;

end.
