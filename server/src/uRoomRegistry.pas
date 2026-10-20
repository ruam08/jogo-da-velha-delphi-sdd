unit uRoomRegistry;

{ Registro das salas ativas e das encerradas lembradas (docs/plan-online.md,
  secoes 5, 8.1 e 11.2).

  Secao critica propria (nivel 1 da secao 8.1 do plano). A unica chamada a uma
  sala feita com ela adquirida e IsClosed (nivel 2), na ordem permitida; as
  operacoes de jogo das salas nunca sao chamadas com a secao do registro
  adquirida. Sweep consulta as salas fora dela.

  Sem dependencia de Indy, HTTP ou JSON. }

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections,
  uClock, uSecureRandom, uRoom;

type
  TRoomRegistry = class
  private
    FLock: TCriticalSection;
    FClock: IClock;
    FRandom: IRandomSource;
    FMaxRooms: Integer;
    FRememberMs: Int64;
    FRooms: TDictionary<string, IRoom>;
    FRemembered: TDictionary<string, Int64>;   { codigo -> instante do encerramento }
    function OpenCountLocked: Integer;
  public
    { AMaxRooms: limite de salas abertas (nao encerradas).
      ARememberMs: periodo de lembranca das salas encerradas (RNO-17). }
    constructor Create(const AClock: IClock; const ARandom: IRandomSource;
      AMaxRooms: Integer; ARememberMs: Int64);
    destructor Destroy; override;
    { rrOk (com a sala e o token do criador, lugar X) ou rrCapacity. }
    function CreateRoom(out ARoom: IRoom; out ACreatorToken: string): TRoomResult;
    { rrOk, rrClosed (encerrada, ativa ou lembrada) ou rrNotFound. O codigo e
      normalizado (RNO-03); codigo malformado = rrNotFound. }
    function Find(const ACode: string; out ARoom: IRoom): TRoomResult;
    { Encerra as salas abandonadas (ninguem conectado ha mais de ATtlMs),
      passa as encerradas para "lembradas" e esquece as lembradas ha mais do
      periodo de lembranca. Devolve o estado das salas encerradas agora. }
    function Sweep(ATtlMs: Int64): TArray<TRoomSnapshot>;
    function OpenCount: Integer;
    function RememberedCount: Integer;
  end;

implementation

const
  MAX_CODE_ATTEMPTS = 100;

constructor TRoomRegistry.Create(const AClock: IClock; const ARandom: IRandomSource;
  AMaxRooms: Integer; ARememberMs: Int64);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
  FRandom := ARandom;
  FMaxRooms := AMaxRooms;
  FRememberMs := ARememberMs;
  FRooms := TDictionary<string, IRoom>.Create;
  FRemembered := TDictionary<string, Int64>.Create;
end;

destructor TRoomRegistry.Destroy;
begin
  FRooms.Free;        { solta as referencias; cada sala e liberada quando a ultima referencia some }
  FRemembered.Free;
  FLock.Free;
  inherited;
end;

function TRoomRegistry.OpenCountLocked: Integer;
var
  Room: IRoom;
begin
  Result := 0;
  for Room in FRooms.Values do
    if not Room.IsClosed then
      Inc(Result);
end;

function TRoomRegistry.CreateRoom(out ARoom: IRoom; out ACreatorToken: string): TRoomResult;
var
  NewCode: string;
  Attempt: Integer;
begin
  Result := rrCapacity;
  ARoom := nil;
  ACreatorToken := '';
  FLock.Enter;
  try
    if OpenCountLocked >= FMaxRooms then
      Exit(rrCapacity);
    { Codigo unico entre as salas ativas e as lembradas (RNO-01). }
    Attempt := 0;
    repeat
      Inc(Attempt);
      if Attempt > MAX_CODE_ATTEMPTS then
        raise Exception.Create('Nao foi possivel gerar um codigo de sala unico.');
      NewCode := NewRoomCode(FRandom);
    until not FRooms.ContainsKey(NewCode) and not FRemembered.ContainsKey(NewCode);
    ACreatorToken := NewToken(FRandom);
    ARoom := TRoom.Create(NewCode, ACreatorToken, FClock, FRandom);
    FRooms.Add(NewCode, ARoom);
    Result := rrOk;
  finally
    FLock.Leave;
  end;
end;

function TRoomRegistry.Find(const ACode: string; out ARoom: IRoom): TRoomResult;
var
  Normalized: string;
begin
  ARoom := nil;
  Normalized := NormalizeRoomCode(ACode);
  if not IsValidRoomCode(Normalized) then
    Exit(rrNotFound);
  FLock.Enter;
  try
    if FRooms.TryGetValue(Normalized, ARoom) then
    begin
      if ARoom.IsClosed then
        Result := rrClosed
      else
        Result := rrOk;
    end
    else if FRemembered.ContainsKey(Normalized) then
      Result := rrClosed
    else
      Result := rrNotFound;
  finally
    FLock.Leave;
  end;
end;

function TRoomRegistry.Sweep(ATtlMs: Int64): TArray<TRoomSnapshot>;
var
  Rooms: TArray<IRoom>;
  Room: IRoom;
  Outcome: TRoomOutcome;
  Closed: TList<TRoomSnapshot>;
  Pair: TPair<string, Int64>;
  ToRemove: TList<string>;
  NowMs: Int64;
  Code: string;
begin
  NowMs := FClock.NowMs;
  { 1. Copia a lista de salas e solta a secao do registro. }
  FLock.Enter;
  try
    Rooms := FRooms.Values.ToArray;
  finally
    FLock.Leave;
  end;

  { 2. Cada sala decide sozinha, na sua secao critica. }
  Closed := TList<TRoomSnapshot>.Create;
  ToRemove := TList<string>.Create;
  try
    for Room in Rooms do
    begin
      Outcome := Room.CloseAbandoned(NowMs, ATtlMs);
      if Outcome.Changed then
        Closed.Add(Outcome.Snapshot);
    end;

    { 3. Encerradas -> lembradas; lembradas antigas -> esquecidas. }
    FLock.Enter;
    try
      for Room in Rooms do
        if Room.IsClosed and FRooms.ContainsKey(Room.Code) then
        begin
          FRooms.Remove(Room.Code);
          FRemembered.AddOrSetValue(Room.Code, NowMs);
        end;
      for Pair in FRemembered do
        if NowMs - Pair.Value > FRememberMs then
          ToRemove.Add(Pair.Key);
      for Code in ToRemove do
        FRemembered.Remove(Code);
    finally
      FLock.Leave;
    end;
    Result := Closed.ToArray;
  finally
    ToRemove.Free;
    Closed.Free;
  end;
end;

function TRoomRegistry.OpenCount: Integer;
begin
  FLock.Enter;
  try
    Result := OpenCountLocked;
  finally
    FLock.Leave;
  end;
end;

function TRoomRegistry.RememberedCount: Integer;
begin
  FLock.Enter;
  try
    Result := FRemembered.Count;
  finally
    FLock.Leave;
  end;
end;

end.
