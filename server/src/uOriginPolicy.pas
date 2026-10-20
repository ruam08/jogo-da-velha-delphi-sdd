unit uOriginPolicy;

{ Política de origem do modo online (docs/plan-online.md, seção 7.7; RNO-22;
  DTO-22). Sem Indy e sem rede: a lista de IPv4 locais vem de fora
  (uHttpApp, com GStack.GetLocalAddressList), o que permite testar tudo no
  EngineCheck (caso WS-07).

  Princípio: a decisão usa SOMENTE os cabeçalhos Origin do pedido e a lista
  montada a partir da configuração do servidor. O cabeçalho Host, ou qualquer
  cabeçalho de proxy, nunca entra na decisão (DNS rebinding).

  Normalização (RFC 6454): exatamente um Origin, até 255 caracteres; "null"
  recusado; esquema://host[:porta] sem usuário, caminho, consulta ou
  fragmento; esquema http ou https; host IPv4 decimal sem zeros à esquerda ou
  nome DNS, em minúsculas; IPv6 recusado; porta 1..65535, 80/443 implícitas.
  Comparação: igualdade exata da forma canônica "esquema://host:porta". }

interface

uses
  System.SysUtils, System.SyncObjs, System.Generics.Collections;

type
  TOriginPolicy = class
  private
    FLock: TCriticalSection;
    FPublicMode: Boolean;
    FBindIP: string;
    FPort: Integer;
    FConfigured: TArray<string>;
    FLocalIPs: TArray<string>;
    FAllowed: TList<string>;
    procedure Rebuild;
  public
    { AConfigured: origens de --allowed-origin, já validadas (forma canônica). }
    constructor Create(APublicMode: Boolean; const ABindIP: string; APort: Integer;
      const AConfigured: array of string);
    destructor Destroy; override;
    { IPv4 das interfaces da máquina. Devolve True se a lista de origens mudou. }
    function SetLocalAddresses(const AIPs: array of string): Boolean;
    { AOrigins: todos os valores do cabeçalho Origin do pedido (vazio = ausente).
      AForChannel: abertura de /ws (no modo público, Origin ausente é recusado). }
    function Allowed(const AOrigins: array of string; AForChannel: Boolean): Boolean;
    function AllowedList: TArray<string>;
    function AllowedText: string;
    property PublicMode: Boolean read FPublicMode;
  end;

{ Forma canônica "esquema://host:porta" de um valor de Origin, ou False. }
function NormalizeOrigin(const AValue: string; out ACanonical: string): Boolean;

{ 10.0.0.0/8, 172.16.0.0/12 e 192.168.0.0/16. }
function IsPrivateIPv4(const AIP: string): Boolean;

{ Valida um valor de --allowed-origin (pode ter vários separados por vírgula).
  Com APublicMode, todos precisam ser https. }
function ParseAllowedOrigins(const AValue: string; APublicMode: Boolean;
  var AList: TArray<string>; out AError: string): Boolean;

{ Texto seguro para o log: até 100 caracteres, só imprimíveis ASCII. }
function OriginForLog(const AValue: string): string;

implementation

const
  MAX_ORIGIN_LENGTH = 255;

function ParseIPv4(const AText: string; out AOctets: array of Integer): Boolean;
var
  Parts: TArray<string>;
  I, J: Integer;
begin
  Result := False;
  Parts := AText.Split(['.']);
  if (Length(Parts) <> 4) or (Length(AOctets) < 4) then
    Exit;
  for I := 0 to 3 do
  begin
    if (Length(Parts[I]) < 1) or (Length(Parts[I]) > 3) then
      Exit;
    for J := 1 to Length(Parts[I]) do
      if not CharInSet(Parts[I][J], ['0'..'9']) then
        Exit;
    if (Length(Parts[I]) > 1) and (Parts[I][1] = '0') then
      Exit;
    AOctets[I] := StrToInt(Parts[I]);
    if AOctets[I] > 255 then
      Exit;
  end;
  Result := True;
end;

function IsPrivateIPv4(const AIP: string): Boolean;
var
  O: array[0..3] of Integer;
begin
  Result := False;
  if not ParseIPv4(AIP, O) then
    Exit;
  Result := (O[0] = 10) or ((O[0] = 172) and (O[1] >= 16) and (O[1] <= 31)) or
    ((O[0] = 192) and (O[1] = 168));
end;

function IsDnsName(const AHost: string): Boolean;
var
  I: Integer;
  Labels: TArray<string>;
  L: string;
begin
  Result := False;
  if (AHost = '') or (Length(AHost) > 253) or AHost.EndsWith('.') or AHost.StartsWith('.') then
    Exit;
  for I := 1 to Length(AHost) do
    if not CharInSet(AHost[I], ['a'..'z', '0'..'9', '-', '.']) then
      Exit;
  Labels := AHost.Split(['.']);
  for L in Labels do
    if (L = '') or (Length(L) > 63) or L.StartsWith('-') or L.EndsWith('-') then
      Exit;
  Result := True;
end;

function OnlyDigitsAndDots(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := AText <> '';
  for I := 1 to Length(AText) do
    if not CharInSet(AText[I], ['0'..'9', '.']) then
      Exit(False);
end;

function NormalizeOrigin(const AValue: string; out ACanonical: string): Boolean;
var
  SchemeEnd, Colon, I, Port: Integer;
  Scheme, Rest, Host, PortText: string;
  O: array[0..3] of Integer;
begin
  ACanonical := '';
  Result := False;
  if (AValue = '') or (Length(AValue) > MAX_ORIGIN_LENGTH) then
    Exit;
  if SameText(AValue, 'null') then
    Exit;
  for I := 1 to Length(AValue) do
    if (Ord(AValue[I]) <= 32) or (Ord(AValue[I]) >= 127) then
      Exit;
  SchemeEnd := Pos('://', AValue);
  if SchemeEnd < 2 then
    Exit;
  Scheme := LowerCase(Copy(AValue, 1, SchemeEnd - 1));
  if (Scheme <> 'http') and (Scheme <> 'https') then
    Exit;
  Rest := Copy(AValue, SchemeEnd + 3, MaxInt);
  if Rest = '' then
    Exit;
  { Sem usuário, caminho (nem "/" final), consulta ou fragmento; sem IPv6. }
  for I := 1 to Length(Rest) do
    if CharInSet(Rest[I], ['/', '?', '#', '@', '[', ']', '\']) then
      Exit;
  Colon := Pos(':', Rest);
  if Colon > 0 then
  begin
    Host := LowerCase(Copy(Rest, 1, Colon - 1));
    PortText := Copy(Rest, Colon + 1, MaxInt);
    if (PortText = '') or (Length(PortText) > 5) or (PortText[1] = '0') then
      Exit;
    for I := 1 to Length(PortText) do
      if not CharInSet(PortText[I], ['0'..'9']) then
        Exit;
    Port := StrToInt(PortText);
    if (Port < 1) or (Port > 65535) then
      Exit;
  end
  else
  begin
    Host := LowerCase(Rest);
    if Scheme = 'https' then
      Port := 443
    else
      Port := 80;
  end;
  if OnlyDigitsAndDots(Host) then
  begin
    if not ParseIPv4(Host, O) then   { 192.168.000.010, 256.1.1.1, 1.2.3 ... }
      Exit;
  end
  else if not IsDnsName(Host) then
    Exit;
  ACanonical := Format('%s://%s:%d', [Scheme, Host, Port]);
  Result := True;
end;

function ParseAllowedOrigins(const AValue: string; APublicMode: Boolean;
  var AList: TArray<string>; out AError: string): Boolean;
var
  Parts: TArray<string>;
  Part, Canonical: string;
begin
  Result := False;
  AError := '';
  Parts := AValue.Split([',']);
  if Length(Parts) = 0 then
  begin
    AError := 'a opção --allowed-origin precisa de uma origem';
    Exit;
  end;
  for Part in Parts do
  begin
    if not NormalizeOrigin(Trim(Part), Canonical) then
    begin
      AError := Format('origem inválida em --allowed-origin: "%s" (use esquema://host[:porta], sem caminho)',
        [OriginForLog(Trim(Part))]);
      Exit;
    end;
    if APublicMode and not Canonical.StartsWith('https://') then
    begin
      AError := Format('com --public, --allowed-origin precisa ser https: "%s"', [OriginForLog(Trim(Part))]);
      Exit;
    end;
    AList := AList + [Canonical];
  end;
  Result := True;
end;

function OriginForLog(const AValue: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AValue) do
  begin
    if Length(Result) >= 100 then
      Break;
    if (Ord(AValue[I]) >= 32) and (Ord(AValue[I]) < 127) then
      Result := Result + AValue[I]
    else
      Result := Result + '?';
  end;
end;

{ ---- TOriginPolicy -------------------------------------------------------- }

constructor TOriginPolicy.Create(APublicMode: Boolean; const ABindIP: string; APort: Integer;
  const AConfigured: array of string);
var
  I: Integer;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FAllowed := TList<string>.Create;
  FPublicMode := APublicMode;
  FBindIP := ABindIP;
  FPort := APort;
  SetLength(FConfigured, Length(AConfigured));
  for I := 0 to High(AConfigured) do
    FConfigured[I] := AConfigured[I];
  FLocalIPs := nil;
  Rebuild;
end;

destructor TOriginPolicy.Destroy;
begin
  FAllowed.Free;
  FLock.Free;
  inherited;
end;

procedure TOriginPolicy.Rebuild;

  procedure Add(const AOrigin: string);
  begin
    if not FAllowed.Contains(AOrigin) then
      FAllowed.Add(AOrigin);
  end;

var
  IP, Origin: string;
begin
  FAllowed.Clear;
  if not FPublicMode then
  begin
    { Loopback, se o bind o abrange. }
    if (FBindIP = '0.0.0.0') or (FBindIP = '127.0.0.1') then
    begin
      Add(Format('http://127.0.0.1:%d', [FPort]));
      Add(Format('http://localhost:%d', [FPort]));
    end;
    { IPv4 privados das interfaces abrangidas pelo bind. }
    if FBindIP = '0.0.0.0' then
    begin
      for IP in FLocalIPs do
        if IsPrivateIPv4(IP) then
          Add(Format('http://%s:%d', [IP, FPort]));
    end
    else if (FBindIP <> '127.0.0.1') and IsPrivateIPv4(FBindIP) then
      Add(Format('http://%s:%d', [FBindIP, FPort]));
  end;
  for Origin in FConfigured do
    Add(Origin);
end;

function TOriginPolicy.SetLocalAddresses(const AIPs: array of string): Boolean;
var
  Before: string;
  I: Integer;
begin
  FLock.Enter;
  try
    Before := string.Join(', ', FAllowed.ToArray);
    SetLength(FLocalIPs, Length(AIPs));
    for I := 0 to High(AIPs) do
      FLocalIPs[I] := AIPs[I];
    Rebuild;
    Result := string.Join(', ', FAllowed.ToArray) <> Before;
  finally
    FLock.Leave;
  end;
end;

function TOriginPolicy.Allowed(const AOrigins: array of string; AForChannel: Boolean): Boolean;
var
  Canonical: string;
begin
  if Length(AOrigins) = 0 then
    { Sem Origin: cliente que não é navegador. Aceito, exceto no canal do modo público. }
    Exit(not (FPublicMode and AForChannel));
  if Length(AOrigins) > 1 then
    Exit(False);   { dois cabeçalhos Origin: ambíguo }
  if not NormalizeOrigin(AOrigins[0], Canonical) then
    Exit(False);
  FLock.Enter;
  try
    Result := FAllowed.Contains(Canonical);
  finally
    FLock.Leave;
  end;
end;

function TOriginPolicy.AllowedList: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FAllowed.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TOriginPolicy.AllowedText: string;
var
  List: TArray<string>;
begin
  List := AllowedList;
  if Length(List) = 0 then
    Result := '(nenhuma)'
  else
    Result := string.Join(', ', List);
end;

end.
