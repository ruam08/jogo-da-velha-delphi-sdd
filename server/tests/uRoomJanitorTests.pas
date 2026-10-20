unit uRoomJanitorTests;

(* Casos JN-01 e JN-02 (novos na O5; docs/test-plan-online.md, secao 5):
  o faxineiro (uRoomJanitor) numa thread propria, sem rede.
  - JN-01: relogio manual; prazos exatos de abandono e de lembranca, sala
    conectada nunca encerrada, contagem a partir da ultima desconexao, sala
    encerrada recusa tudo, sala nova sem reaproveitar codigo nem token, parada
    imediata e nenhuma notificacao depois da parada.
  - JN-02: faxineiro a cada 1 ms com prazo de 5 ms enquanto 8 threads criam,
    entram, conectam, jogam e desconectam: nenhuma sala e encerrada com alguem
    conectado, cada sala e notificada no maximo uma vez, nada depois da
    parada, nenhuma excecao. *)

interface

procedure RunRoomJanitorTests;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Diagnostics,
  System.Generics.Collections, uMiniTest, uClock, uSecureRandom, uRoom,
  uRoomRegistry, uRoomJanitor;

function ResultName(R: TRoomResult): string;
begin
  case R of
    rrOk: Result := 'rrOk';
    rrNotFound: Result := 'rrNotFound';
    rrClosed: Result := 'rrClosed';
    rrInvalidToken: Result := 'rrInvalidToken';
    rrFull: Result := 'rrFull';
  else
    Result := 'outro(' + IntToStr(Ord(R)) + ')';
  end;
end;

{ Coleta, sob trava, as salas que o faxineiro informou. }
type
  TCollector = class
  private
    FLock: TCriticalSection;
    FCodes: TList<string>;
    FBad: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AClosed: TArray<TRoomSnapshot>);
    function Text: string;
    function Count: Integer;
    property Bad: Integer read FBad;
  end;

constructor TCollector.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FCodes := TList<string>.Create;
end;

destructor TCollector.Destroy;
begin
  FCodes.Free;
  FLock.Free;
  inherited;
end;

procedure TCollector.Add(const AClosed: TArray<TRoomSnapshot>);
var
  S: TRoomSnapshot;
begin
  FLock.Enter;
  try
    for S in AClosed do
    begin
      { Toda sala informada esta encerrada por abandono e sem ninguem conectado. }
      if (S.Situation <> rsClosed) or (S.CloseReason <> crAbandoned) or
         S.Seats[seX].Connected or S.Seats[seO].Connected then
        Inc(FBad);
      FCodes.Add(S.Code);
    end;
  finally
    FLock.Leave;
  end;
end;

function TCollector.Text: string;
var
  C: string;
begin
  FLock.Enter;
  try
    Result := '';
    for C in FCodes do
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + C;
    end;
  finally
    FLock.Leave;
  end;
end;

function TCollector.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FCodes.Count;
  finally
    FLock.Leave;
  end;
end;

{ Espera pelo menos duas varreduras completas depois de agora (o relogio
  manual so muda entre elas). }
procedure WaitSweeps(AJanitor: TRoomJanitor);
var
  Target: Int64;
  W: TStopwatch;
begin
  Target := AJanitor.Sweeps + 2;
  W := TStopwatch.StartNew;
  while (AJanitor.Sweeps < Target) and (W.ElapsedMilliseconds < 3000) do
    Sleep(2);
end;

procedure JN01_Deterministic;
var
  Clock: TManualClock;
  ClockRef: IClock;
  Rng: IRandomSource;
  Reg: TRoomRegistry;
  Col: TCollector;
  J, J2: TRoomJanitor;
  A, B, D, N: IRoom;
  TA, TB, TD, TN, TokenO, Issued: string;
  Room: IRoom;
  Seat: TSeat;
  Replaced: Int64;
  Outcome: TRoomOutcome;
  W: TStopwatch;
  Before: Integer;
begin
  Clock := TManualClock.Create(1000);
  ClockRef := Clock;
  Rng := TSystemRandom.Create;
  Reg := TRoomRegistry.Create(ClockRef, Rng, 100, 3000);
  Col := TCollector.Create;
  J := TRoomJanitor.Create(Reg, 2000, 10,
    procedure(const AClosed: TArray<TRoomSnapshot>) begin Col.Add(AClosed); end, nil);
  try
    Reg.CreateRoom(A, TA);                       { nunca conectada }
    Reg.CreateRoom(B, TB);
    B.Attach(TB, 1, Seat, Replaced);              { X conectado o tempo todo }
    Reg.CreateRoom(D, TD);
    D.Attach(TD, 2, Seat, Replaced);              { conectada e depois desconectada }
    J.Start;

    Clock.Advance(1500);                          { t = 2500 }
    D.Detach(seX, 2);
    WaitSweeps(J);
    CheckEqualsStr('', Col.Text, 't=2500: nenhuma sala encerrada antes do prazo');

    Clock.Advance(600);                           { t = 3100: A tem 2100 ms sem ninguem }
    WaitSweeps(J);
    CheckEqualsStr(A.Code, Col.Text, 't=3100: so A (D foi desconectada ha 600 ms; B conectada)');
    CheckEqualsStr('rrClosed', ResultName(Reg.Find(A.Code, Room)), 'A encerrada: 410');
    CheckEqualsStr('rrOk', ResultName(Reg.Find(D.Code, Room)), 'D continua aberta');
    CheckEqualsStr('rrOk', ResultName(Reg.Find(B.Code, Room)), 'B continua aberta');

    { Sala encerrada recusa tudo, inclusive com o token certo. }
    Outcome := A.Attach(TA, 9, Seat, Replaced);
    CheckEqualsStr('rrClosed', ResultName(Outcome.Result), 'A: reconexao recusada');
    CheckEqualsStr('rrClosed', ResultName(A.Play(TA, 4).Result), 'A: jogada recusada');
    CheckEqualsStr('rrClosed', ResultName(A.Join('', Seat, Issued).Result), 'A: entrada recusada');
    CheckEqualsStr('rrClosed', ResultName(A.NewGame(TA).Result), 'A: nova partida recusada');
    CheckEqualsStr('rrClosed', ResultName(A.Leave(TA).Result), 'A: saida recusada');

    Clock.Advance(1500);                          { t = 4600: D tem 2100 ms desde a desconexao }
    WaitSweeps(J);
    CheckEqualsStr(A.Code + ',' + D.Code, Col.Text, 't=4600: D encerrada, contada da desconexao');
    CheckEqualsStr('rrClosed', ResultName(Reg.Find(A.Code, Room)), 't=4600: A lembrada (1500 ms)');

    Clock.Advance(3000);                          { t = 7600 }
    WaitSweeps(J);
    CheckEqualsStr('rrNotFound', ResultName(Reg.Find(A.Code, Room)), 't=7600: A esquecida (4500 ms > 3000)');
    CheckEqualsStr('rrClosed', ResultName(Reg.Find(D.Code, Room)), 't=7600: D ainda lembrada (3000 ms, nao mais que 3000)');
    CheckEqualsStr('rrOk', ResultName(Reg.Find(B.Code, Room)), 't=7600: B conectada nunca expira');
    Clock.Advance(1);
    WaitSweeps(J);
    CheckEqualsStr('rrNotFound', ResultName(Reg.Find(D.Code, Room)), 't=7601: D esquecida');
    CheckEqualsInt(2, Col.Count, 'cada sala informada uma unica vez');
    CheckEqualsInt(0, Col.Bad, 'toda sala informada: encerrada por abandono, sem conexao');

    { Sala nova: codigo e tokens novos; os tokens antigos nao valem nela. }
    Reg.CreateRoom(N, TN);
    Check((N.Code <> A.Code) and (N.Code <> D.Code) and (N.Code <> B.Code), 'codigo novo');
    Check((TN <> TA) and (TN <> TD) and (TN <> TB), 'token novo');
    CheckEqualsStr('rrInvalidToken', ResultName(N.Play(TA, 0).Result), 'token de A nao vale na sala nova');
    CheckEqualsStr('rrInvalidToken', ResultName(N.Attach(TD, 5, Seat, Replaced).Result), 'token de D nao vale na sala nova');
    N.Join('', Seat, TokenO);
    Check((TokenO <> TA) and (TokenO <> TB) and (TokenO <> TD) and (TokenO <> TN), 'token de O novo');

    { Parada: depois de Stop, nada mais e varrido nem informado. }
    J.Stop;
    Before := Col.Count;
    B.Detach(seX, 1);
    Clock.Advance(100000);
    Sleep(60);
    CheckEqualsInt(Before, Col.Count, 'nenhuma notificacao depois de Stop');
    CheckEqualsStr('rrOk', ResultName(Reg.Find(B.Code, Room)), 'sem faxineiro, nada e encerrado');
    J.Stop;                                       { segunda parada: sem efeito }

    { Parada imediata mesmo com intervalo longo (60 s). }
    J2 := TRoomJanitor.Create(Reg, 2000, 60000, nil, nil);
    try
      J2.Start;
      W := TStopwatch.StartNew;
      J2.Stop;
      Check(W.ElapsedMilliseconds < 1000, Format('Stop com intervalo de 60 s levou %d ms', [W.ElapsedMilliseconds]));
      Check(not J2.Running, 'thread terminada');
    finally
      J2.Free;
    end;
    CheckEqualsInt(0, J.Errors, 'nenhuma excecao no faxineiro');
  finally
    J.Free;
    Col.Free;
    A := nil; B := nil; D := nil; N := nil; Room := nil;
    Reg.Free;
  end;
end;

type
  TWorker = class(TThread)
  private
    FReg: TRoomRegistry;
    FId: Integer;
    FViolations: Integer;
    FOps: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AReg: TRoomRegistry; AId: Integer);
    property Violations: Integer read FViolations;
    property Ops: Integer read FOps;
  end;

constructor TWorker.Create(AReg: TRoomRegistry; AId: Integer);
begin
  FReg := AReg;
  FId := AId;
  inherited Create(True);
end;

{ Cada volta: cria uma sala, X conecta, O entra e conecta, jogam com os dois
  conectados (nada pode voltar rrClosed), desconectam, esperam o prazo e
  tentam de novo (agora rrClosed e permitido). }
procedure TWorker.Execute;
var
  I, K: Integer;
  Room: IRoom;
  TX, TO_: string;
  Seat: TSeat;
  Replaced, ConnX, ConnO: Int64;
  R: TRoomResult;
begin
  for I := 1 to 150 do
  begin
    if FReg.CreateRoom(Room, TX) <> rrOk then
      Continue;
    ConnX := Int64(FId) * 100000 + I * 2;
    ConnO := ConnX + 1;
    { Entre criar e conectar a sala pode ser encerrada (prazo de 5 ms): permitido. }
    if Room.Attach(TX, ConnX, Seat, Replaced).Result <> rrOk then
      Continue;
    R := Room.Join('', Seat, TO_).Result;
    if R = rrClosed then Inc(FViolations);
    if Room.Attach(TO_, ConnO, Seat, Replaced).Result = rrClosed then Inc(FViolations);
    for K := 0 to 8 do
    begin
      if K mod 2 = 0 then R := Room.Play(TX, K).Result else R := Room.Play(TO_, K).Result;
      if R = rrClosed then Inc(FViolations);   { conectados: nunca encerrada }
      Inc(FOps);
    end;
    Sleep(1);
    if Room.NewGame(TX).Result = rrClosed then Inc(FViolations);
    Room.Detach(seX, ConnX);
    if Room.Play(TO_, 0).Result = rrClosed then Inc(FViolations);  { O ainda conectado }
    Room.Detach(seO, ConnO);
    Sleep(I mod 7);                       { as vezes passa do prazo, as vezes nao }
    Room.Play(TX, 0);                     { rrClosed ou outra recusa: os dois sao validos }
    Room := nil;
  end;
end;

procedure JN02_Concurrent;
const
  N = 8;
var
  Rng: IRandomSource;
  Clock: IClock;
  Reg: TRoomRegistry;
  Col: TCollector;
  J: TRoomJanitor;
  Workers: array[0..N - 1] of TWorker;
  I, Violations, Ops, Dups, AfterStop: Integer;
  Stopped: Boolean;
  Codes: TStringList;
  Text: string;
begin
  Rng := TSystemRandom.Create;
  Clock := TSystemClock.Create;
  Reg := TRoomRegistry.Create(Clock, Rng, 100000, 50);
  Col := TCollector.Create;
  Stopped := False;
  AfterStop := 0;
  J := TRoomJanitor.Create(Reg, 5, 1,
    procedure(const AClosed: TArray<TRoomSnapshot>)
    begin
      if Stopped then
        TInterlocked.Increment(AfterStop);
      Col.Add(AClosed);
    end, nil);
  try
    J.Start;
    for I := 0 to N - 1 do
      Workers[I] := TWorker.Create(Reg, I + 1);
    for I := 0 to N - 1 do
      Workers[I].Start;
    Violations := 0;
    Ops := 0;
    for I := 0 to N - 1 do
    begin
      Workers[I].WaitFor;
      Inc(Violations, Workers[I].Violations);
      Inc(Ops, Workers[I].Ops);
      Workers[I].Free;
    end;
    Sleep(50);
    J.Stop;
    Stopped := True;
    Sleep(20);
    CheckEqualsInt(0, Violations, 'operacao recusada como encerrada com alguem conectado');
    CheckEqualsInt(0, Col.Bad, 'sala informada com alguem conectado ou motivo errado');
    CheckEqualsInt(0, AfterStop, 'notificacao depois de Stop');
    CheckEqualsInt(0, J.Errors, 'excecoes no faxineiro');
    { Cada sala informada no maximo uma vez. }
    Codes := TStringList.Create;
    try
      Codes.Sorted := True;
      Codes.Duplicates := dupIgnore;
      Text := Col.Text;
      if Text <> '' then
        Codes.CommaText := Text;
      Dups := Col.Count - Codes.Count;
    finally
      Codes.Free;
    end;
    CheckEqualsInt(0, Dups, 'sala informada mais de uma vez');
    Check(Col.Count > 0, 'o faxineiro encerrou salas durante o teste');
    Note(Format('%d threads x 150 salas; %d jogadas; %d varreduras; %d salas encerradas por abandono; lembradas no fim %d',
      [N, Ops, J.Sweeps, Col.Count, Reg.RememberedCount]));
  finally
    J.Free;
    Col.Free;
    Reg.Free;
  end;
end;

procedure RunRoomJanitorTests;
begin
  RunCase('JN-01', 'Faxineiro: prazos de abandono e lembranca, sala conectada, sala nova, parada', JN01_Deterministic);
  RunCase('JN-02', 'Faxineiro a cada 1 ms com 8 threads: nada encerrado com alguem conectado', JN02_Concurrent);
end;

end.
