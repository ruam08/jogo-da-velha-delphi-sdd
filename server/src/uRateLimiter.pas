unit uRateLimiter;

(* Limites por cliente da Entrega O6 (docs/plan-online.md, DTO-20 e
  seção 13.1, B5, B6, B14 e B15). Sem Indy e sem rede: testável no
  EngineCheck com relógio manual (casos RL).

  - TRateLimiter: janela fixa por cliente. Até ALimit tentativas por
    janela; a seguinte é recusada, com os segundos que faltam para a janela
    acabar (Retry-After, de 1 s até a duração da janela).
    Limite 0 = sem limite (nada é guardado). No máximo AMaxKeys clientes em memória:
    as janelas vencidas são descartadas a cada janela; se mesmo assim não
    houver espaço, um cliente novo é recusado (B15).
  - TConnectionCounter: canais simultâneos por cliente (TryAcquire/Release).
  - TMessageWindow: mensagens por canal numa janela fixa (uso de uma única
    thread, a da sessão).

  Thread-safe: TRateLimiter e TConnectionCounter usam uma seção crítica
  própria, que nunca chama nada de fora. *)

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections, uClock;

const
  DEFAULT_RATE_MAX_KEYS = 100000;
  WS_MESSAGE_WINDOW_MS = 10000;

type
  TRateDecision = record
    Allowed: Boolean;
    Count: Integer;              { tentativas na janela, contando esta }
    RetryAfterSeconds: Integer;  { só quando recusada }
  end;

  TRateLimiter = class
  private type
    TWindow = record
      StartMs: Int64;
      Count: Integer;
    end;
  private
    FLock: TCriticalSection;
    FClock: IClock;
    FLimit: Integer;
    FWindowMs: Int64;
    FMaxKeys: Integer;
    FWindows: TDictionary<string, TWindow>;
    FLastPruneMs: Int64;
    procedure PruneLocked(ANowMs: Int64);
  public
    constructor Create(const AClock: IClock; ALimit: Integer; AWindowMs: Int64;
      AMaxKeys: Integer = DEFAULT_RATE_MAX_KEYS);
    destructor Destroy; override;
    function Hit(const AKey: string): TRateDecision;
    function Enabled: Boolean;
    function KeyCount: Integer;
    property Limit: Integer read FLimit;
  end;

  TConnectionCounter = class
  private
    FLock: TCriticalSection;
    FLimit: Integer;
    FCounts: TDictionary<string, Integer>;
  public
    constructor Create(ALimit: Integer);
    destructor Destroy; override;
    { Limite 0: sempre True (e nada é guardado). }
    function TryAcquire(const AKey: string): Boolean;
    procedure Release(const AKey: string);
    function CountOf(const AKey: string): Integer;
    function KeyCount: Integer;
    property Limit: Integer read FLimit;
  end;

  TMessageWindow = record
  private
    FLimit: Integer;
    FWindowMs: Int64;
    FStartMs: Int64;
    FCount: Integer;
  public
    procedure Init(ALimit: Integer; AWindowMs: Int64 = WS_MESSAGE_WINDOW_MS);
    { False quando esta mensagem passa do limite da janela. }
    function Hit(ANowMs: Int64): Boolean;
  end;

implementation

{ ---- TRateLimiter -------------------------------------------------------- }

constructor TRateLimiter.Create(const AClock: IClock; ALimit: Integer; AWindowMs: Int64;
  AMaxKeys: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
  FLimit := ALimit;
  if AWindowMs < 1 then
    AWindowMs := 1;
  FWindowMs := AWindowMs;
  if AMaxKeys < 1 then
    AMaxKeys := 1;
  FMaxKeys := AMaxKeys;
  FWindows := TDictionary<string, TWindow>.Create;
  FLastPruneMs := FClock.NowMs;
end;

destructor TRateLimiter.Destroy;
begin
  FWindows.Free;
  FLock.Free;
  inherited;
end;

function TRateLimiter.Enabled: Boolean;
begin
  Result := FLimit > 0;
end;

procedure TRateLimiter.PruneLocked(ANowMs: Int64);
var
  Old: TList<string>;
  Pair: TPair<string, TWindow>;
  Key: string;
begin
  Old := TList<string>.Create;
  try
    for Pair in FWindows do
      if ANowMs - Pair.Value.StartMs >= FWindowMs then
        Old.Add(Pair.Key);
    for Key in Old do
      FWindows.Remove(Key);
  finally
    Old.Free;
  end;
  FLastPruneMs := ANowMs;
end;

function TRateLimiter.Hit(const AKey: string): TRateDecision;
var
  NowMs, Remaining: Int64;
  W: TWindow;
begin
  Result.Allowed := True;
  Result.Count := 0;
  Result.RetryAfterSeconds := 0;
  if FLimit <= 0 then
    Exit;
  NowMs := FClock.NowMs;
  FLock.Enter;
  try
    if NowMs - FLastPruneMs >= FWindowMs then
      PruneLocked(NowMs);
    if FWindows.TryGetValue(AKey, W) and (NowMs - W.StartMs < FWindowMs) then
      Inc(W.Count)
    else
    begin
      if (not FWindows.ContainsKey(AKey)) and (FWindows.Count >= FMaxKeys) then
      begin
        PruneLocked(NowMs);
        if FWindows.Count >= FMaxKeys then
        begin
          { B15: sem espaço para um cliente novo; recusa sem guardar nada. }
          Result.Allowed := False;
          Result.RetryAfterSeconds := (FWindowMs + 999) div 1000;
          Exit;
        end;
      end;
      W.StartMs := NowMs;
      W.Count := 1;
    end;
    FWindows.AddOrSetValue(AKey, W);
    Result.Count := W.Count;
    if W.Count > FLimit then
    begin
      Result.Allowed := False;
      Remaining := FWindowMs - (NowMs - W.StartMs);
      Result.RetryAfterSeconds := (Remaining + 999) div 1000;
      if Result.RetryAfterSeconds < 1 then
        Result.RetryAfterSeconds := 1;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRateLimiter.KeyCount: Integer;
begin
  FLock.Enter;
  try
    Result := FWindows.Count;
  finally
    FLock.Leave;
  end;
end;

{ ---- TConnectionCounter -------------------------------------------------- }

constructor TConnectionCounter.Create(ALimit: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FLimit := ALimit;
  FCounts := TDictionary<string, Integer>.Create;
end;

destructor TConnectionCounter.Destroy;
begin
  FCounts.Free;
  FLock.Free;
  inherited;
end;

function TConnectionCounter.TryAcquire(const AKey: string): Boolean;
var
  N: Integer;
begin
  Result := True;
  if FLimit <= 0 then
    Exit;
  FLock.Enter;
  try
    if not FCounts.TryGetValue(AKey, N) then
      N := 0;
    if N >= FLimit then
      Exit(False);
    FCounts.AddOrSetValue(AKey, N + 1);
  finally
    FLock.Leave;
  end;
end;

procedure TConnectionCounter.Release(const AKey: string);
var
  N: Integer;
begin
  if FLimit <= 0 then
    Exit;
  FLock.Enter;
  try
    if FCounts.TryGetValue(AKey, N) then
    begin
      if N <= 1 then
        FCounts.Remove(AKey)
      else
        FCounts.AddOrSetValue(AKey, N - 1);
    end;
  finally
    FLock.Leave;
  end;
end;

function TConnectionCounter.CountOf(const AKey: string): Integer;
begin
  FLock.Enter;
  try
    if not FCounts.TryGetValue(AKey, Result) then
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

function TConnectionCounter.KeyCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCounts.Count;
  finally
    FLock.Leave;
  end;
end;

{ ---- TMessageWindow ------------------------------------------------------ }

procedure TMessageWindow.Init(ALimit: Integer; AWindowMs: Int64);
begin
  FLimit := ALimit;
  if AWindowMs < 1 then
    AWindowMs := 1;
  FWindowMs := AWindowMs;
  FStartMs := -1;
  FCount := 0;
end;

function TMessageWindow.Hit(ANowMs: Int64): Boolean;
begin
  Result := True;
  if FLimit <= 0 then
    Exit;
  if (FStartMs < 0) or (ANowMs - FStartMs >= FWindowMs) then
  begin
    FStartMs := ANowMs;
    FCount := 0;
  end;
  Inc(FCount);
  Result := FCount <= FLimit;
end;

end.
