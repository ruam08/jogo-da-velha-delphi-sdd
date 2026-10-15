unit uGameService;

{ Serviço de jogo: guarda a única partida do servidor (RN-13) e serializa
  todo acesso ao motor com uma seção crítica (RNF-06). O TIdHTTPServer atende
  cada conexão em uma thread, então várias requisições podem chegar aqui ao
  mesmo tempo.

  - Cada operação executa inteira dentro da seção crítica.
  - Play devolve o resultado e o estado da MESMA jogada, lidos sem que outra
    thread possa intervir entre um e outro.
  - Todo estado devolvido é uma cópia (TGameEngine.GetSnapshot); quem o recebe
    não tem acesso às estruturas internas do motor.

  Sem dependência de Indy, HTTP ou JSON. }

interface

uses
  System.SyncObjs, uGameEngine;

type
  TPlayOutcome = record
    MoveResult: TMoveResult;
    State: TGameSnapshot;
  end;

  TGameService = class
  private
    FLock: TCriticalSection;
    FEngine: TGameEngine;
  public
    constructor Create;
    destructor Destroy; override;
    function GetState: TGameSnapshot;
    function Play(APosition: Integer): TPlayOutcome;
    function Reset: TGameSnapshot;
  end;

implementation

constructor TGameService.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FEngine := TGameEngine.Create;
end;

destructor TGameService.Destroy;
begin
  FEngine.Free;
  FLock.Free;
  inherited;
end;

function TGameService.GetState: TGameSnapshot;
begin
  FLock.Enter;
  try
    Result := FEngine.GetSnapshot;
  finally
    FLock.Leave;
  end;
end;

function TGameService.Play(APosition: Integer): TPlayOutcome;
begin
  FLock.Enter;
  try
    Result.MoveResult := FEngine.Play(APosition);
    Result.State := FEngine.GetSnapshot;
  finally
    FLock.Leave;
  end;
end;

function TGameService.Reset: TGameSnapshot;
begin
  FLock.Enter;
  try
    FEngine.Reset;
    Result := FEngine.GetSnapshot;
  finally
    FLock.Leave;
  end;
end;

end.
