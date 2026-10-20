unit uRoomHub;

{ Inscrições por sala e caixas de saída dos canais (docs/plan-online.md,
  seções 5, 8.1 e 8.3; DTO-06). Sem Indy e sem JSON: o hub só entrega textos
  prontos às caixas de saída; quem escreve no socket é a thread do canal.

  Seções críticas: hub (nível 3) e caixa de saída (nível 4). O hub só
  adquire a caixa de saída com a sua seção aberta (3 -> 4), nunca o
  contrário, e nenhuma das duas chama a sala ou o registro.

  Caixa de saída (TOutbox):
  - "estado": versões estritamente crescentes; um estado novo substitui o
    estado ainda não enviado; um estado com versão menor ou igual à última
    aceita (ou à do bem_vindo, SetBaseline) é descartado;
  - mensagens comuns (pong, por exemplo) nunca são descartadas nem
    reordenadas;
  - terminal (sala_encerrada, erro SUBSTITUIDA): nunca descartado; depois
    dele nada mais entra, e o canal fecha com o código informado;
  - mais de ACapacity itens pendentes: Overflowed (o canal fecha com 1008). }

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections, uRoom;

const
  DEFAULT_OUTBOX_CAPACITY = 16;

type
  TOutboxKind = (okState, okMessage, okTerminal);

  TOutboxItem = record
    Kind: TOutboxKind;
    Text: string;
    Version: Int64;
    CloseCode: Word;
  end;

  TOutbox = class
  private
    FLock: TCriticalSection;
    FItems: TList<TOutboxItem>;
    FCapacity: Integer;
    FLastStateVersion: Int64;
    FTerminal: Boolean;
    FOverflowed: Boolean;
    procedure Append(const AItem: TOutboxItem);
  public
    constructor Create(ACapacity: Integer = DEFAULT_OUTBOX_CAPACITY);
    destructor Destroy; override;
    { Devolve True se o estado foi aceito (não descartado pela versão). }
    function EnqueueState(const AText: string; AVersion: Int64): Boolean;
    procedure EnqueueMessage(const AText: string);
    procedure EnqueueTerminal(const AText: string; ACloseCode: Word);
    { Estados com versão <= AVersion (já entregues no bem_vindo) são descartados. }
    procedure SetBaseline(AVersion: Int64);
    { Retira tudo o que está pendente, na ordem. }
    function TakeAll: TArray<TOutboxItem>;
    function Overflowed: Boolean;
    function Pending: Integer;
  end;

  THubSubscriber = record
    Seat: TSeat;
    ConnectionId: Int64;
    Outbox: TOutbox;
  end;

  TRoomHub = class
  private
    FLock: TCriticalSection;
    FRooms: TObjectDictionary<string, TList<THubSubscriber>>;
  public
    constructor Create;
    destructor Destroy; override;
    { Inscreve o canal no lugar ASeat da sala. Se o lugar já tinha um canal,
      ele recebe AReplacedText como mensagem terminal (fechamento 4000) e sai
      da lista; devolve o identificador desse canal (0 se não havia). }
    function Subscribe(const ACode: string; ASeat: TSeat; AConnectionId: Int64;
      AOutbox: TOutbox; const AReplacedText: string): Int64;
    { Retira a caixa de saída da sala (se ainda estiver lá). }
    procedure Unsubscribe(const ACode: string; AOutbox: TOutbox);
    { Entrega o estado aos inscritos da sala ACode; devolve quantos receberam. }
    function PublishState(const ACode, AText: string; AVersion: Int64): Integer;
    { Mensagem terminal para todos os inscritos da sala (sala_encerrada). }
    function PublishTerminal(const ACode, AText: string; ACloseCode: Word): Integer;
    function SubscriberCount(const ACode: string): Integer;
  end;

implementation

const
  CLOSE_REPLACED = 4000;

{ ---- TOutbox -------------------------------------------------------------- }

constructor TOutbox.Create(ACapacity: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TList<TOutboxItem>.Create;
  FCapacity := ACapacity;
  FLastStateVersion := 0;
end;

destructor TOutbox.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited;
end;

procedure TOutbox.Append(const AItem: TOutboxItem);
begin
  if FItems.Count >= FCapacity then
  begin
    FOverflowed := True;
    Exit;
  end;
  FItems.Add(AItem);
end;

function TOutbox.EnqueueState(const AText: string; AVersion: Int64): Boolean;
var
  Item: TOutboxItem;
  I: Integer;
begin
  FLock.Enter;
  try
    Result := False;
    if FTerminal or FOverflowed or (AVersion <= FLastStateVersion) then
      Exit;
    { Aglutinação: fica só o estado mais recente. }
    for I := FItems.Count - 1 downto 0 do
      if FItems[I].Kind = okState then
        FItems.Delete(I);
    Item.Kind := okState;
    Item.Text := AText;
    Item.Version := AVersion;
    Item.CloseCode := 0;
    Append(Item);
    FLastStateVersion := AVersion;
    Result := not FOverflowed;
  finally
    FLock.Leave;
  end;
end;

procedure TOutbox.EnqueueMessage(const AText: string);
var
  Item: TOutboxItem;
begin
  FLock.Enter;
  try
    if FTerminal or FOverflowed then
      Exit;
    Item.Kind := okMessage;
    Item.Text := AText;
    Item.Version := 0;
    Item.CloseCode := 0;
    Append(Item);
  finally
    FLock.Leave;
  end;
end;

procedure TOutbox.EnqueueTerminal(const AText: string; ACloseCode: Word);
var
  Item: TOutboxItem;
begin
  FLock.Enter;
  try
    if FTerminal then
      Exit;
    FTerminal := True;
    Item.Kind := okTerminal;
    Item.Text := AText;
    Item.Version := 0;
    Item.CloseCode := ACloseCode;
    { A mensagem terminal entra mesmo com a fila cheia: o canal vai fechar. }
    FItems.Add(Item);
  finally
    FLock.Leave;
  end;
end;

procedure TOutbox.SetBaseline(AVersion: Int64);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := FItems.Count - 1 downto 0 do
      if (FItems[I].Kind = okState) and (FItems[I].Version <= AVersion) then
        FItems.Delete(I);
    if AVersion > FLastStateVersion then
      FLastStateVersion := AVersion;
  finally
    FLock.Leave;
  end;
end;

function TOutbox.TakeAll: TArray<TOutboxItem>;
begin
  FLock.Enter;
  try
    Result := FItems.ToArray;
    FItems.Clear;
  finally
    FLock.Leave;
  end;
end;

function TOutbox.Overflowed: Boolean;
begin
  FLock.Enter;
  try
    Result := FOverflowed;
  finally
    FLock.Leave;
  end;
end;

function TOutbox.Pending: Integer;
begin
  FLock.Enter;
  try
    Result := FItems.Count;
  finally
    FLock.Leave;
  end;
end;

{ ---- TRoomHub ------------------------------------------------------------- }

constructor TRoomHub.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRooms := TObjectDictionary<string, TList<THubSubscriber>>.Create([doOwnsValues]);
end;

destructor TRoomHub.Destroy;
begin
  FRooms.Free;
  FLock.Free;
  inherited;
end;

function TRoomHub.Subscribe(const ACode: string; ASeat: TSeat; AConnectionId: Int64;
  AOutbox: TOutbox; const AReplacedText: string): Int64;
var
  List: TList<THubSubscriber>;
  Sub: THubSubscriber;
  I: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    if not FRooms.TryGetValue(ACode, List) then
    begin
      List := TList<THubSubscriber>.Create;
      FRooms.Add(ACode, List);
    end;
    for I := List.Count - 1 downto 0 do
      if List[I].Seat = ASeat then
      begin
        Result := List[I].ConnectionId;
        List[I].Outbox.EnqueueTerminal(AReplacedText, CLOSE_REPLACED);
        List.Delete(I);
      end;
    Sub.Seat := ASeat;
    Sub.ConnectionId := AConnectionId;
    Sub.Outbox := AOutbox;
    List.Add(Sub);
  finally
    FLock.Leave;
  end;
end;

procedure TRoomHub.Unsubscribe(const ACode: string; AOutbox: TOutbox);
var
  List: TList<THubSubscriber>;
  I: Integer;
begin
  FLock.Enter;
  try
    if not FRooms.TryGetValue(ACode, List) then
      Exit;
    for I := List.Count - 1 downto 0 do
      if List[I].Outbox = AOutbox then
        List.Delete(I);
    if List.Count = 0 then
      FRooms.Remove(ACode);
  finally
    FLock.Leave;
  end;
end;

function TRoomHub.PublishState(const ACode, AText: string; AVersion: Int64): Integer;
var
  List: TList<THubSubscriber>;
  Sub: THubSubscriber;
begin
  Result := 0;
  FLock.Enter;
  try
    if not FRooms.TryGetValue(ACode, List) then
      Exit;
    for Sub in List do
      if Sub.Outbox.EnqueueState(AText, AVersion) then
        Inc(Result);
  finally
    FLock.Leave;
  end;
end;

function TRoomHub.PublishTerminal(const ACode, AText: string; ACloseCode: Word): Integer;
var
  List: TList<THubSubscriber>;
  Sub: THubSubscriber;
begin
  Result := 0;
  FLock.Enter;
  try
    if not FRooms.TryGetValue(ACode, List) then
      Exit;
    for Sub in List do
    begin
      Sub.Outbox.EnqueueTerminal(AText, ACloseCode);
      Inc(Result);
    end;
  finally
    FLock.Leave;
  end;
end;

function TRoomHub.SubscriberCount(const ACode: string): Integer;
var
  List: TList<THubSubscriber>;
begin
  FLock.Enter;
  try
    if FRooms.TryGetValue(ACode, List) then
      Result := List.Count
    else
      Result := 0;
  finally
    FLock.Leave;
  end;
end;

end.
