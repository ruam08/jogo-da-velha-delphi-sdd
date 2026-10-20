unit uRequestLimits;

(* Limites e proteções de requisição da Entrega O6 (docs/plan-online.md,
  seção 13.1). Sem Indy e sem rede: testável no EngineCheck (casos RL).

  - TCappedStream: corpo da requisição com teto em memória. O Indy chama
    Size := Content-Length antes de ler (AdjustStreamSize, em IdIOHandler);
    com um TMemoryStream isso alocaria o tamanho declarado, qualquer que
    fosse. Aqui Size só é anotado; os bytes acima do teto são contados e
    descartados.
  - ClientKey: quem é "o cliente" para os limites (B8): o IP da conexão;
    com --trust-proxy e conexão vinda de 127.0.0.1, o último IPv4 válido de
    X-Forwarded-For. Host e X-Forwarded-Host nunca são usados.
  - ClassifyRateKind: qual taxa uma requisição consome (B5).
  - Constantes dos cabeçalhos de segurança (B11) e dos erros novos (B4). *)

interface

uses
  System.SysUtils, System.Classes;

const
  { Teto em memória para o corpo de qualquer requisição (B3). }
  MAX_REQUEST_BODY_BYTES = 64 * 1024;

  ERR_CONNECTION_LIMIT = 'LIMITE_DE_CONEXOES';
  MSG_CONNECTION_LIMIT = 'Muitas conexões abertas a partir deste endereço.';
  ERR_SERVER_BUSY = 'SERVIDOR_OCUPADO';
  MSG_SERVER_BUSY = 'O servidor está com muitas conexões. Tente novamente em instantes.';
  ERR_MESSAGE_RATE = 'LIMITE_DE_MENSAGENS';
  MSG_MESSAGE_RATE = 'Muitas mensagens neste canal.';
  SERVER_BUSY_RETRY_SECONDS = 5;

  HEADER_NOSNIFF = 'nosniff';
  HEADER_REFERRER_POLICY = 'no-referrer';
  { img-src data: as duas páginas usam <link rel="icon" href="data:,"> (O4) para
    não pedir /favicon.ico. }
  PAGE_CSP = 'default-src ''self''; base-uri ''none''; object-src ''none''; ' +
    'form-action ''self''; frame-ancestors ''none''; img-src ''self'' data:';
  PAGE_FRAME_OPTIONS = 'DENY';

type
  TRateKind = (rtNone, rtCreate, rtJoin, rtWs);

  TCappedStream = class(TStream)
  private
    FData: TBytes;
    FStored: Integer;
    FTotal: Int64;
    FDeclared: Int64;
    FPosition: Int64;
    FCapacity: Integer;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(ACapacity: Integer = MAX_REQUEST_BODY_BYTES);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    procedure SetSize(const NewSize: Int64); override;
    { Bytes guardados (no máximo ACapacity). }
    function StoredBytes: TBytes;
    { Total recebido, inclusive o descartado. }
    property Total: Int64 read FTotal;
    { Tamanho anotado pelo Indy (Content-Length), ou -1. }
    property Declared: Int64 read FDeclared;
    function Overflowed: Boolean;
  end;

{ Quem é o cliente para os limites (B8). AForwardedFor: todos os valores do
  cabeçalho X-Forwarded-For, na ordem em que chegaram. }
function ClientKey(const APeerIP: string; const AForwardedFor: array of string;
  ATrustProxy: Boolean): string;

{ Qual taxa uma requisição consome (B5). ARawPath: caminho cru, com ou sem
  query string. }
function ClassifyRateKind(const AMethod, ARawPath: string): TRateKind;

{ Texto seguro para o log: só caracteres imprimíveis ASCII, até AMax. }
function SafeForLog(const AText: string; AMax: Integer = 64): string;

implementation

uses
  uServerOptions;

{ ---- TCappedStream ------------------------------------------------------- }

constructor TCappedStream.Create(ACapacity: Integer);
begin
  inherited Create;
  if ACapacity < 0 then
    ACapacity := 0;
  FCapacity := ACapacity;
  FDeclared := -1;
end;

function TCappedStream.GetSize: Int64;
begin
  Result := FStored;
end;

procedure TCappedStream.SetSize(const NewSize: Int64);
begin
  { Só anota: nunca aloca o tamanho pedido. }
  FDeclared := NewSize;
end;

function TCappedStream.Write(const Buffer; Count: Longint): Longint;
var
  Keep: Integer;
begin
  Result := 0;
  if Count <= 0 then
    Exit;
  Keep := FCapacity - FStored;
  if Keep > Count then
    Keep := Count;
  if Keep > 0 then
  begin
    if Length(FData) < FStored + Keep then
      SetLength(FData, FStored + Keep);
    Move(Buffer, FData[FStored], Keep);
    Inc(FStored, Keep);
  end;
  Inc(FTotal, Count);
  FPosition := FStored;
  Result := Count;
end;

function TCappedStream.Read(var Buffer; Count: Longint): Longint;
var
  Available: Int64;
begin
  Result := 0;
  if (Count <= 0) or (FPosition >= FStored) then
    Exit;
  Available := FStored - FPosition;
  if Available < Count then
    Result := Longint(Available)
  else
    Result := Count;
  Move(FData[FPosition], Buffer, Result);
  Inc(FPosition, Result);
end;

function TCappedStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  NewPos: Int64;
begin
  case Origin of
    soBeginning: NewPos := Offset;
    soCurrent: NewPos := FPosition + Offset;
  else
    NewPos := FStored + Offset;
  end;
  if NewPos < 0 then
    NewPos := 0;
  if NewPos > FStored then
    NewPos := FStored;
  FPosition := NewPos;
  Result := FPosition;
end;

function TCappedStream.StoredBytes: TBytes;
begin
  Result := Copy(FData, 0, FStored);
end;

function TCappedStream.Overflowed: Boolean;
begin
  Result := FTotal > FCapacity;
end;

{ ---- Cliente, taxa e log --------------------------------------------------- }

function ClientKey(const APeerIP: string; const AForwardedFor: array of string;
  ATrustProxy: Boolean): string;
var
  All, Item: string;
  Parts: TArray<string>;
  I: Integer;
begin
  Result := APeerIP;
  if (not ATrustProxy) or (APeerIP <> '127.0.0.1') or (Length(AForwardedFor) = 0) then
    Exit;
  All := '';
  for Item in AForwardedFor do
  begin
    if All <> '' then
      All := All + ',';
    All := All + Item;
  end;
  Parts := All.Split([',']);
  { O proxy acrescenta o endereço de quem falou com ele no fim da lista;
    o resto pode ter sido escrito pelo próprio cliente. }
  for I := High(Parts) downto 0 do
  begin
    Item := Trim(Parts[I]);
    if Item = '' then
      Continue;
    if IsValidIPv4(Item) then
      Result := Item;
    Exit;
  end;
end;

function ClassifyRateKind(const AMethod, ARawPath: string): TRateKind;
var
  Path, Rest: string;
  Q, Slash: Integer;
const
  PREFIX = '/api/rooms/';
begin
  Result := rtNone;
  Path := ARawPath;
  Q := Pos('?', Path);
  if Q > 0 then
    Path := Copy(Path, 1, Q - 1);
  if Path = '/ws' then
    Exit(rtWs);
  if Path = '/api/rooms' then
  begin
    if AMethod = 'POST' then
      Result := rtCreate;
    Exit;
  end;
  if Copy(Path, 1, Length(PREFIX)) <> PREFIX then
    Exit;
  Rest := Copy(Path, Length(PREFIX) + 1, MaxInt);
  if Rest = '' then
    Exit;
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    if (AMethod = 'GET') or (AMethod = 'HEAD') then
      Result := rtJoin;
  end
  else if (Copy(Rest, Slash, MaxInt) = '/players') and (Slash > 1) and (AMethod = 'POST') then
    Result := rtJoin;
end;

function SafeForLog(const AText: string; AMax: Integer): string;
var
  C: Char;
begin
  Result := '';
  for C in AText do
  begin
    if Length(Result) >= AMax then
      Break;
    if (C >= ' ') and (C <= '~') then
      Result := Result + C
    else
      Result := Result + '?';
  end;
end;

end.
