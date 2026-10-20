unit uServerOptions;

{ Leitura e validação da linha de comando do servidor (docs/plan-online.md,
  seção 11.4, e DTO-16). Sem Indy e sem acesso a disco: testável no
  EngineCheck (caso OP-01).

  Opções desta entrega (O2):
    --port N                 1..65535 (padrão 8765)
    --www <pasta>            pasta da interface (padrão: a recebida em ADefaultWebRoot)
    --bind <IPv4>            endereço de escuta (padrão 0.0.0.0; 127.0.0.1 com --public)
    --public                 modo público: bind padrão 127.0.0.1 e política de origem
                             só com as origens configuradas (pelo menos uma, https,
                             verificado por ValidateServerOptions). As demais
                             proteções do modo público entraram na O6 (abaixo).
    --allowed-origin <url>[,<url>...]  origens aceitas além das automáticas (seção 7.7);
                             pode ser repetida
    --ws-hello-seconds N     prazo para o "entrar" do canal, 1..300 (padrão 5)
    --ws-idle-seconds N      canal sem mensagens recebidas, 2..3600 (padrão 60)
    --room-ttl-seconds N     abandono de sala, 1..604800 (padrão 600; usado a partir da O5)
    --remember-seconds N     período de lembrança, 0..604800 (padrão 3600)
    --sweep-ms N             intervalo do faxineiro, 10..3600000 (padrão 5000; O5)
    --max-rooms N            salas abertas, 1..100000 (padrão 500)
    --max-connections N      conexões simultâneas, 1..10000 (padrão 256)
  Entrega O6 (docs/plan-online.md, seção 13.1, B14). Sem valor explícito, o
  padrão depende do modo (local / --public):
    --rate-create N          criações de sala por janela e cliente, 0..10000 (0 / 10)
    --rate-join N            consultas e entradas de sala por janela e cliente, 0..10000 (0 / 30)
    --rate-ws N              aberturas de canal por janela e cliente, 0..10000 (0 / 30)
    --rate-window-seconds N  janela das taxas, 1..3600 (60)
    --ws-per-client N        canais simultâneos por cliente, 0..10000 (0 / 8)
    --ws-msg-rate N          mensagens por canal a cada 10 s, 0..10000 (0 / 30)
    --http-timeout-seconds N prazo de cada leitura até a requisição chegar, 1..3600 (30)
    --trust-proxy            com conexão de 127.0.0.1, o cliente é o último
                             endereço de X-Forwarded-For
  0 = sem limite.
  As demais opções da seção 11.4 entram nas entregas que as usam.
  Opção desconhecida, sem valor ou com valor inválido -> False (o servidor
  sai com código 2). Repetir uma opção vale a última ocorrência. }

interface

uses
  System.SysUtils, uOriginPolicy;

const
  DEFAULT_PORT = 8765;
  DEFAULT_BIND = '0.0.0.0';
  PUBLIC_DEFAULT_BIND = '127.0.0.1';
  DEFAULT_ROOM_TTL_SECONDS = 600;
  DEFAULT_REMEMBER_SECONDS = 3600;
  DEFAULT_SWEEP_MS = 5000;
  DEFAULT_MAX_ROOMS = 500;
  DEFAULT_MAX_CONNECTIONS = 256;
  DEFAULT_WS_HELLO_SECONDS = 5;
  DEFAULT_WS_IDLE_SECONDS = 60;
  { O6 (seção 13.1, B14): padrões do modo local e do modo público. }
  LOCAL_RATE_CREATE = 0;
  PUBLIC_RATE_CREATE = 10;
  LOCAL_RATE_JOIN = 0;
  PUBLIC_RATE_JOIN = 30;
  LOCAL_RATE_WS = 0;
  PUBLIC_RATE_WS = 30;
  DEFAULT_RATE_WINDOW_SECONDS = 60;
  LOCAL_WS_PER_CLIENT = 0;
  PUBLIC_WS_PER_CLIENT = 8;
  LOCAL_WS_MSG_RATE = 0;
  PUBLIC_WS_MSG_RATE = 30;
  DEFAULT_HTTP_TIMEOUT_SECONDS = 30;

  SERVER_USAGE = 'Uso: TicTacToeServer.exe [--port 1-65535] [--www <pasta>] ' +
    '[--bind <IPv4>] [--public] [--room-ttl-seconds N] [--remember-seconds N] ' +
    '[--sweep-ms N] [--max-rooms N] [--max-connections N] ' +
    '[--allowed-origin <url>[,<url>...]] [--ws-hello-seconds N] [--ws-idle-seconds N] ' +
    '[--rate-create N] [--rate-join N] [--rate-ws N] [--rate-window-seconds N] ' +
    '[--ws-per-client N] [--ws-msg-rate N] [--http-timeout-seconds N] [--trust-proxy]';

type
  TServerOptions = record
    Port: Integer;
    WebRoot: string;
    BindIP: string;
    BindExplicit: Boolean;      { --bind informado }
    PublicMode: Boolean;
    RoomTtlSeconds: Integer;
    RememberSeconds: Integer;
    SweepMs: Integer;
    MaxRooms: Integer;
    MaxConnections: Integer;
    AllowedOrigins: TArray<string>;   { forma canônica, esquema://host:porta }
    WsHelloSeconds: Integer;
    WsIdleSeconds: Integer;
    { O6 }
    RateCreate: Integer;
    RateJoin: Integer;
    RateWs: Integer;
    RateWindowSeconds: Integer;
    WsPerClient: Integer;
    WsMsgRate: Integer;
    HttpTimeoutSeconds: Integer;
    TrustProxy: Boolean;
  end;

function DefaultServerOptions(const ADefaultWebRoot: string): TServerOptions;

{ AArgs: os argumentos sem o nome do programa. Em caso de erro, AError diz
  qual opção falhou e AOptions fica com os padrões. }
function ParseServerOptions(const AArgs: array of string; const ADefaultWebRoot: string;
  out AOptions: TServerOptions; out AError: string): Boolean;

{ Regras entre opções, depois da leitura (seção 7.7 e DTO-17): com --public,
  pelo menos um --allowed-origin e todos https. O servidor chama as duas
  funções; um erro em qualquer uma encerra com o código 2. }
function ValidateServerOptions(const AOptions: TServerOptions; out AError: string): Boolean;

{ Quatro números decimais de 0 a 255 separados por ponto, sem zeros à esquerda. }
function IsValidIPv4(const AText: string): Boolean;

implementation

function DefaultServerOptions(const ADefaultWebRoot: string): TServerOptions;
begin
  Result.Port := DEFAULT_PORT;
  Result.WebRoot := ADefaultWebRoot;
  Result.BindIP := DEFAULT_BIND;
  Result.BindExplicit := False;
  Result.PublicMode := False;
  Result.RoomTtlSeconds := DEFAULT_ROOM_TTL_SECONDS;
  Result.RememberSeconds := DEFAULT_REMEMBER_SECONDS;
  Result.SweepMs := DEFAULT_SWEEP_MS;
  Result.MaxRooms := DEFAULT_MAX_ROOMS;
  Result.MaxConnections := DEFAULT_MAX_CONNECTIONS;
  Result.AllowedOrigins := nil;
  Result.WsHelloSeconds := DEFAULT_WS_HELLO_SECONDS;
  Result.WsIdleSeconds := DEFAULT_WS_IDLE_SECONDS;
  Result.RateCreate := LOCAL_RATE_CREATE;
  Result.RateJoin := LOCAL_RATE_JOIN;
  Result.RateWs := LOCAL_RATE_WS;
  Result.RateWindowSeconds := DEFAULT_RATE_WINDOW_SECONDS;
  Result.WsPerClient := LOCAL_WS_PER_CLIENT;
  Result.WsMsgRate := LOCAL_WS_MSG_RATE;
  Result.HttpTimeoutSeconds := DEFAULT_HTTP_TIMEOUT_SECONDS;
  Result.TrustProxy := False;
end;

function IsValidIPv4(const AText: string): Boolean;
var
  Parts: TArray<string>;
  Part: string;
  I, Value: Integer;
begin
  Result := False;
  Parts := AText.Split(['.']);
  if Length(Parts) <> 4 then
    Exit;
  for Part in Parts do
  begin
    if (Length(Part) < 1) or (Length(Part) > 3) then
      Exit;
    for I := 1 to Length(Part) do
      if not CharInSet(Part[I], ['0'..'9']) then
        Exit;
    if (Length(Part) > 1) and (Part[1] = '0') then
      Exit;
    Value := StrToInt(Part);
    if Value > 255 then
      Exit;
  end;
  Result := True;
end;

{ Só dígitos decimais (sem sinal, sem espaços) e dentro do intervalo. }
function ParseBounded(const AText: string; AMin, AMax: Integer; out AValue: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  AValue := 0;
  if (AText = '') or (Length(AText) > 9) then
    Exit;
  for I := 1 to Length(AText) do
    if not CharInSet(AText[I], ['0'..'9']) then
      Exit;
  AValue := StrToInt(AText);
  Result := (AValue >= AMin) and (AValue <= AMax);
end;

function ParseServerOptions(const AArgs: array of string; const ADefaultWebRoot: string;
  out AOptions: TServerOptions; out AError: string): Boolean;
var
  Args: TArray<string>;   { cópia: rotinas aninhadas não usam o parâmetro de array aberto }
  I: Integer;
  Name, Value: string;
  Parsed: TServerOptions;
  OriginValues: TArray<string>;
  OriginList: TArray<string>;
  OriginText: string;
  { O6: -1 = não informado; o padrão do modo é aplicado depois do laço. }
  RateCreate, RateJoin, RateWs, WsPerClient, WsMsgRate: Integer;

  function TakeValue: Boolean;
  begin
    Result := (I < High(Args)) and not Args[I + 1].StartsWith('--');
    if Result then
    begin
      Inc(I);
      Value := Args[I];
    end
    else
      AError := Format('a opção %s precisa de um valor', [Name]);
  end;

  function TakeNumber(AMin, AMax: Integer; out ATarget: Integer): Boolean;
  begin
    Result := TakeValue;
    if not Result then
      Exit;
    Result := ParseBounded(Value, AMin, AMax, ATarget);
    if not Result then
      AError := Format('valor inválido para %s: "%s" (aceito: %d a %d)', [Name, Value, AMin, AMax]);
  end;

begin
  SetLength(Args, Length(AArgs));
  for I := 0 to High(AArgs) do
    Args[I] := AArgs[I];
  AOptions := DefaultServerOptions(ADefaultWebRoot);
  AError := '';
  Parsed := AOptions;
  Result := False;
  RateCreate := -1;
  RateJoin := -1;
  RateWs := -1;
  WsPerClient := -1;
  WsMsgRate := -1;
  I := 0;
  while I <= High(Args) do
  begin
    Name := LowerCase(Args[I]);
    if Name = '--port' then
    begin
      if not TakeNumber(1, 65535, Parsed.Port) then
        Exit;
    end
    else if Name = '--www' then
    begin
      if not TakeValue then
        Exit;
      if Trim(Value) = '' then
      begin
        AError := 'a opção --www precisa de uma pasta';
        Exit;
      end;
      Parsed.WebRoot := Value;
    end
    else if Name = '--bind' then
    begin
      if not TakeValue then
        Exit;
      if not IsValidIPv4(Value) then
      begin
        AError := Format('endereço inválido para --bind: "%s" (use um IPv4, como 127.0.0.1 ou 0.0.0.0)', [Value]);
        Exit;
      end;
      Parsed.BindIP := Value;
      Parsed.BindExplicit := True;
    end
    else if Name = '--public' then
      Parsed.PublicMode := True
    else if Name = '--room-ttl-seconds' then
    begin
      if not TakeNumber(1, 604800, Parsed.RoomTtlSeconds) then
        Exit;
    end
    else if Name = '--remember-seconds' then
    begin
      if not TakeNumber(0, 604800, Parsed.RememberSeconds) then
        Exit;
    end
    else if Name = '--sweep-ms' then
    begin
      if not TakeNumber(10, 3600000, Parsed.SweepMs) then
        Exit;
    end
    else if Name = '--max-rooms' then
    begin
      if not TakeNumber(1, 100000, Parsed.MaxRooms) then
        Exit;
    end
    else if Name = '--max-connections' then
    begin
      if not TakeNumber(1, 10000, Parsed.MaxConnections) then
        Exit;
    end
    else if Name = '--allowed-origin' then
    begin
      if not TakeValue then
        Exit;
      { Validada depois do laço, quando se sabe se --public foi informado. }
      OriginValues := OriginValues + [Value];
    end
    else if Name = '--ws-hello-seconds' then
    begin
      if not TakeNumber(1, 300, Parsed.WsHelloSeconds) then
        Exit;
    end
    else if Name = '--ws-idle-seconds' then
    begin
      if not TakeNumber(2, 3600, Parsed.WsIdleSeconds) then
        Exit;
    end
    else if Name = '--rate-create' then
    begin
      if not TakeNumber(0, 10000, RateCreate) then
        Exit;
    end
    else if Name = '--rate-join' then
    begin
      if not TakeNumber(0, 10000, RateJoin) then
        Exit;
    end
    else if Name = '--rate-ws' then
    begin
      if not TakeNumber(0, 10000, RateWs) then
        Exit;
    end
    else if Name = '--rate-window-seconds' then
    begin
      if not TakeNumber(1, 3600, Parsed.RateWindowSeconds) then
        Exit;
    end
    else if Name = '--ws-per-client' then
    begin
      if not TakeNumber(0, 10000, WsPerClient) then
        Exit;
    end
    else if Name = '--ws-msg-rate' then
    begin
      if not TakeNumber(0, 10000, WsMsgRate) then
        Exit;
    end
    else if Name = '--http-timeout-seconds' then
    begin
      if not TakeNumber(1, 3600, Parsed.HttpTimeoutSeconds) then
        Exit;
    end
    else if Name = '--trust-proxy' then
      Parsed.TrustProxy := True
    else
    begin
      AError := Format('opção desconhecida: "%s"', [Args[I]]);
      Exit;
    end;
    Inc(I);
  end;
  { DTO-16: com --public e sem --bind, escuta só no próprio computador. }
  if Parsed.PublicMode and not Parsed.BindExplicit then
    Parsed.BindIP := PUBLIC_DEFAULT_BIND;
  { O6 (B14): sem valor explícito, o padrão do modo. }
  if Parsed.PublicMode then
  begin
    if RateCreate < 0 then RateCreate := PUBLIC_RATE_CREATE;
    if RateJoin < 0 then RateJoin := PUBLIC_RATE_JOIN;
    if RateWs < 0 then RateWs := PUBLIC_RATE_WS;
    if WsPerClient < 0 then WsPerClient := PUBLIC_WS_PER_CLIENT;
    if WsMsgRate < 0 then WsMsgRate := PUBLIC_WS_MSG_RATE;
  end
  else
  begin
    if RateCreate < 0 then RateCreate := LOCAL_RATE_CREATE;
    if RateJoin < 0 then RateJoin := LOCAL_RATE_JOIN;
    if RateWs < 0 then RateWs := LOCAL_RATE_WS;
    if WsPerClient < 0 then WsPerClient := LOCAL_WS_PER_CLIENT;
    if WsMsgRate < 0 then WsMsgRate := LOCAL_WS_MSG_RATE;
  end;
  Parsed.RateCreate := RateCreate;
  Parsed.RateJoin := RateJoin;
  Parsed.RateWs := RateWs;
  Parsed.WsPerClient := WsPerClient;
  Parsed.WsMsgRate := WsMsgRate;
  { Seção 7.7: cada --allowed-origin precisa ser uma origem válida. A regra do
    modo público (pelo menos uma, todas https) é de ValidateServerOptions. }
  OriginList := nil;
  for OriginText in OriginValues do
    if not ParseAllowedOrigins(OriginText, False, OriginList, AError) then
      Exit;
  Parsed.AllowedOrigins := OriginList;
  AOptions := Parsed;
  Result := True;
end;

function ValidateServerOptions(const AOptions: TServerOptions; out AError: string): Boolean;
var
  Origin: string;
begin
  AError := '';
  Result := False;
  if AOptions.PublicMode then
  begin
    if Length(AOptions.AllowedOrigins) = 0 then
    begin
      AError := 'com --public, informe pelo menos um --allowed-origin https://<domínio>';
      Exit;
    end;
    for Origin in AOptions.AllowedOrigins do
      if not Origin.StartsWith('https://') then
      begin
        AError := Format('com --public, --allowed-origin precisa ser https: "%s"', [Origin]);
        Exit;
      end;
  end;
  Result := True;
end;

end.
