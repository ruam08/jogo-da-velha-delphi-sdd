unit uRoomHubTests;

{ Casos HB-01 e HB-02 do docs/test-plan-online.md (secao 5): caixa de saida
  e hub de inscricoes (uRoomHub), sem rede. HB-03 (novo na O3): varias
  threads publicando em salas diferentes ao mesmo tempo. }

interface

procedure RunRoomHubTests;

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, uMiniTest, uRoom, uRoomHub;

function Kinds(const AItems: TArray<TOutboxItem>): string;
var
  Item: TOutboxItem;
begin
  Result := '';
  for Item in AItems do
  begin
    if Result <> '' then
      Result := Result + ',';
    case Item.Kind of
      okState: Result := Result + 'S' + IntToStr(Item.Version);
      okMessage: Result := Result + 'M:' + Item.Text;
      okTerminal: Result := Result + 'T' + IntToStr(Item.CloseCode);
    end;
  end;
end;

procedure HB01_Outbox;
var
  B: TOutbox;
  I: Integer;
begin
  B := TOutbox.Create;
  try
    B.EnqueueState('e5', 5);
    B.EnqueueState('e6', 6);
    B.EnqueueState('e7', 7);
    CheckEqualsStr('S7', Kinds(B.TakeAll), 'tres estados seguidos: so o ultimo');
    Check(not B.EnqueueState('e6', 6), 'estado mais antigo que o ultimo e descartado');
    Check(not B.EnqueueState('e7', 7), 'estado repetido e descartado');
    CheckEqualsStr('', Kinds(B.TakeAll), 'nada pendente');

    B.EnqueueState('e8', 8);
    B.EnqueueMessage('pong1');
    B.EnqueueState('e9', 9);
    B.EnqueueMessage('pong2');
    CheckEqualsStr('M:pong1,S9,M:pong2', Kinds(B.TakeAll), 'pong nao e descartado nem reordenado');

    B.SetBaseline(12);
    Check(not B.EnqueueState('e11', 11), 'estado anterior ao bem_vindo e descartado');
    B.EnqueueState('e13', 13);
    B.EnqueueTerminal('encerrada', 4410);
    B.EnqueueState('e14', 14);
    B.EnqueueMessage('depois');
    CheckEqualsStr('S13,T4410', Kinds(B.TakeAll), 'terminal fecha a caixa: nada entra depois');
  finally
    B.Free;
  end;

  B := TOutbox.Create;
  try
    B.EnqueueState('e1', 1);
    B.EnqueueState('e2', 2);
    B.SetBaseline(1);
    CheckEqualsStr('S2', Kinds(B.TakeAll), 'SetBaseline mantem estados mais novos');
  finally
    B.Free;
  end;

  B := TOutbox.Create(4);
  try
    for I := 1 to 4 do
      B.EnqueueMessage('m' + IntToStr(I));
    Check(not B.Overflowed, '4 de 4: ainda nao estourou');
    B.EnqueueMessage('m5');
    Check(B.Overflowed, 'fila cheia: sinal de fechamento 1008');
    B.EnqueueTerminal('erro', 4000);
    CheckEqualsInt(5, B.Pending, 'terminal entra mesmo com a fila cheia');
  finally
    B.Free;
  end;
end;

procedure HB02_Hub;
var
  Hub: TRoomHub;
  X1, O1, X2, X1b: TOutbox;
begin
  Hub := TRoomHub.Create;
  X1 := TOutbox.Create;
  O1 := TOutbox.Create;
  X2 := TOutbox.Create;
  X1b := TOutbox.Create;
  try
    CheckEqualsInt(0, Hub.Subscribe('AAAAAA', seX, 1, X1, 'subst'), 'X de S1: sem anterior');
    CheckEqualsInt(0, Hub.Subscribe('AAAAAA', seO, 2, O1, 'subst'), 'O de S1: sem anterior');
    CheckEqualsInt(0, Hub.Subscribe('BBBBBB', seX, 3, X2, 'subst'), 'X de S2: sem anterior');
    CheckEqualsInt(2, Hub.PublishState('AAAAAA', 's1v3', 3), 'publicacao em S1 chega a 2 canais');
    CheckEqualsStr('', Kinds(X2.TakeAll), 'assinante de S2 nao recebe publicacoes de S1');
    CheckEqualsStr('S3', Kinds(X1.TakeAll), 'X de S1 recebe');
    CheckEqualsStr('S3', Kinds(O1.TakeAll), 'O de S1 recebe');
    CheckEqualsInt(0, Hub.PublishState('CCCCCC', 'x', 1), 'sala sem inscritos');

    { Mesmo lugar em outro canal: o anterior recebe a mensagem terminal 4000. }
    CheckEqualsInt(1, Hub.Subscribe('AAAAAA', seX, 4, X1b, 'subst'), 'inscricao do mesmo lugar devolve o anterior');
    CheckEqualsStr('T4000', Kinds(X1.TakeAll), 'anterior recebe SUBSTITUIDA (4000)');
    CheckEqualsInt(2, Hub.SubscriberCount('AAAAAA'), 'S1 continua com 2 inscritos');
    Hub.Unsubscribe('AAAAAA', X1);   { o substituido sai depois: nao remove o atual }
    CheckEqualsInt(2, Hub.SubscriberCount('AAAAAA'), 'cancelar o substituido nao remove o atual');
    CheckEqualsInt(2, Hub.PublishState('AAAAAA', 's1v4', 4), 'publicacao depois da substituicao');
    CheckEqualsStr('S4', Kinds(X1b.TakeAll), 'o canal novo recebe');
    CheckEqualsStr('S4', Kinds(O1.TakeAll), 'O tambem recebe');
    CheckEqualsStr('', Kinds(X1.TakeAll), 'o substituido nao recebe mais');

    CheckEqualsInt(2, Hub.PublishTerminal('AAAAAA', 'encerrada', 4410), 'sala_encerrada para os 2');
    CheckEqualsStr('T4410', Kinds(O1.TakeAll), 'O recebe sala_encerrada');
    Hub.Unsubscribe('AAAAAA', X1b);
    Hub.Unsubscribe('AAAAAA', O1);
    CheckEqualsInt(0, Hub.SubscriberCount('AAAAAA'), 'S1 sem inscritos');
    CheckEqualsInt(1, Hub.SubscriberCount('BBBBBB'), 'S2 intacta');
  finally
    Hub.Free;
    X1.Free;
    O1.Free;
    X2.Free;
    X1b.Free;
  end;
end;

type
  TPublisher = class(TThread)
  private
    FHub: TRoomHub;
    FCode: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AHub: TRoomHub; const ACode: string);
  end;

constructor TPublisher.Create(AHub: TRoomHub; const ACode: string);
begin
  FHub := AHub;
  FCode := ACode;
  inherited Create(True);
end;

procedure TPublisher.Execute;
var
  V: Integer;
begin
  for V := 1 to 2000 do
    FHub.PublishState(FCode, FCode, V);
end;

procedure HB03_Concurrent;
const
  N = 8;
var
  Hub: TRoomHub;
  Boxes: array[0..N - 1] of TOutbox;
  Threads: array[0..N - 1] of TPublisher;
  Codes: array[0..N - 1] of string;
  I, Wrong, LastVersion: Integer;
  Items: TArray<TOutboxItem>;
  Item: TOutboxItem;
  Seen: array[0..N - 1] of Integer;
  Pass: Integer;
begin
  Hub := TRoomHub.Create;
  try
    for I := 0 to N - 1 do
    begin
      Codes[I] := 'SALA' + IntToStr(I) + 'X';
      Boxes[I] := TOutbox.Create(16);
      Hub.Subscribe(Codes[I], seX, I + 1, Boxes[I], 'subst');
      Seen[I] := 0;
    end;
    for I := 0 to N - 1 do
      Threads[I] := TPublisher.Create(Hub, Codes[I]);
    for I := 0 to N - 1 do
      Threads[I].Start;
    Wrong := 0;
    { Enquanto publicam, cada "canal" retira o que chegou e confere a sala e a ordem. }
    for Pass := 1 to 200 do
      for I := 0 to N - 1 do
      begin
        Items := Boxes[I].TakeAll;
        for Item in Items do
        begin
          if Item.Text <> Codes[I] then
            Inc(Wrong);
          if Item.Version <= Seen[I] then
            Inc(Wrong);
          Seen[I] := Item.Version;
        end;
      end;
    for I := 0 to N - 1 do
    begin
      Threads[I].WaitFor;
      Threads[I].Free;
    end;
    for I := 0 to N - 1 do
    begin
      Items := Boxes[I].TakeAll;
      LastVersion := Seen[I];
      for Item in Items do
      begin
        if (Item.Text <> Codes[I]) or (Item.Version <= LastVersion) then
          Inc(Wrong);
        LastVersion := Item.Version;
      end;
      CheckEqualsInt(2000, LastVersion, Format('sala %d: ultima versao entregue', [I]));
      Check(not Boxes[I].Overflowed, Format('sala %d: sem estouro (estados aglutinados)', [I]));
    end;
    CheckEqualsInt(0, Wrong, 'mensagens de outra sala ou fora de ordem');
    Note(Format('%d threads x 2000 publicacoes em %d salas; problemas: %d', [N, N, Wrong]));
    for I := 0 to N - 1 do
      Hub.Unsubscribe(Codes[I], Boxes[I]);
  finally
    Hub.Free;
    for I := 0 to N - 1 do
      Boxes[I].Free;
  end;
end;

procedure RunRoomHubTests;
begin
  RunCase('HB-01', 'Caixa de saida: aglutinacao, versoes, pong em ordem, terminal, estouro', HB01_Outbox);
  RunCase('HB-02', 'Hub: isolamento entre salas, substituicao e cancelamento', HB02_Hub);
  RunCase('HB-03', 'Hub com 8 threads publicando em 8 salas: sem mistura e em ordem', HB03_Concurrent);
end;

end.
