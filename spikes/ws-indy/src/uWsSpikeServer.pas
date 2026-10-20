unit uWsSpikeServer;

(* Prova de conceito da Entrega O0 (descartavel).
  WebSocket sobre o TIdHTTPServer do Indy 10.6.2.5341, com a mesma
  configuracao do servidor de producao (KeepAlive = False, OnCommandGet e
  OnCommandOther no mesmo roteador). Nao tem salas nem regras de jogo.

  Rotas:
    GET  /health  -> {"status":"ok"}
    GET  /stats   -> contadores de canais
    GET  /page    -> pagina de teste (page.html) para o Chromium
    POST /push    -> envia "push:<corpo>" a todos os canais (de outra thread)
    GET  /ws      -> troca de protocolo (101) e sessao WebSocket

  Mensagens de texto da sessao:
    servidor envia "ola:<id>" ao abrir
    "todos:<t>"  -> os outros canais recebem "de:<id>:<t>"; quem enviou recebe "enviado:<n>"
    "fechar"     -> o servidor fecha com 1000
    outro texto  -> "eco:<texto>"

  A troca de protocolo segue docs/plan-online.md, secao 3.1: a resposta 101 e
  escrita diretamente no IOHandler e HeaderHasBeenWritten = True; a sessao
  roda dentro do OnCommandGet ate o canal fechar. Somente a thread da sessao
  escreve no seu socket; as outras threads so enfileiram (DTO-06). *)

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  IdGlobal, IdContext, IdCustomHTTPServer, IdHTTPServer, IdIOHandler;

type
  TWsSession = class
  private
    FId: Integer;
    FPeer: string;
    FLock: TCriticalSection;
    FOutbox: TQueue<TBytes>;
  public
    constructor Create(AId: Integer; const APeer: string);
    destructor Destroy; override;
    procedure Enqueue(const AFrame: TBytes);
    function TakeAll: TArray<TBytes>;
    property Id: Integer read FId;
    property Peer: string read FPeer;
  end;

  TSpikeServer = class
  private
    FServer: TIdHTTPServer;
    FPort: Word;
    FIdleMs: Int64;
    FPagePath: string;
    FSessionsLock: TCriticalSection;
    FSessions: TList<TWsSession>;
    FNextId: Integer;
    FOpened: Integer;
    FClosed: Integer;
    FErrors: Integer;
    FStopping: Boolean;
    procedure HandleCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleUpgrade(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
    procedure RunSession(AContext: TIdContext; ASession: TWsSession);
    function AllowedOrigin(const AOrigin: string): Boolean;
    function Broadcast(const AFrame: TBytes; AExceptId: Integer): Integer;
    function StatsJson: string;
  public
    constructor Create(APort: Word; AIdleSeconds: Integer; const APagePath: string);
    destructor Destroy; override;
    procedure Start;
    { Pede as sessoes que fechem com 1001; elas fazem isso na proxima volta do laco. }
    procedure BeginShutdown;
    { Espera as sessoes terminarem; devolve quantas restaram. }
    function WaitSessions(ATimeoutMs: Integer): Integer;
    procedure Stop;
    function ActiveSessions: Integer;
  end;

implementation

uses
  System.IOUtils, IdSocketHandle, IdException, uWsCodec, uSpikeLog;

const
  LOOP_WAIT_MS = 50;
  CLOSE_WAIT_MS = 1000;

{ ---- Respostas HTTP comuns ------------------------------------------------ }

procedure WriteBody(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const AContentType: string; const ABytes: TBytes);
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
    Stream.Position := 0;
  except
    Stream.Free;
    raise;
  end;
  AResponseInfo.ResponseNo := AStatus;
  AResponseInfo.ContentType := AContentType;
  AResponseInfo.CharSet := 'utf-8';
  AResponseInfo.CustomHeaders.Values['Cache-Control'] := 'no-store';
  AResponseInfo.ContentStream := Stream;
  AResponseInfo.ContentLength := Stream.Size;
end;

procedure WriteJson(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer; const AJson: string);
begin
  WriteBody(AResponseInfo, AStatus, 'application/json', TEncoding.UTF8.GetBytes(AJson));
end;

procedure WriteError(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer; const ACode: string);
begin
  WriteJson(AResponseInfo, AStatus, '{"erro":{"codigo":"' + ACode + '"}}');
end;

function ReadBody(ARequestInfo: TIdHTTPRequestInfo): TBytes;
var
  Stream: TStream;
begin
  Result := nil;
  Stream := ARequestInfo.PostStream;
  if (Stream = nil) or (Stream.Size = 0) then
    Exit;
  Stream.Position := 0;
  SetLength(Result, Stream.Size);
  Stream.ReadBuffer(Result[0], Length(Result));
end;

{ ---- TWsSession ----------------------------------------------------------- }

constructor TWsSession.Create(AId: Integer; const APeer: string);
begin
  inherited Create;
  FId := AId;
  FPeer := APeer;
  FLock := TCriticalSection.Create;
  FOutbox := TQueue<TBytes>.Create;
end;

destructor TWsSession.Destroy;
begin
  FOutbox.Free;
  FLock.Free;
  inherited;
end;

procedure TWsSession.Enqueue(const AFrame: TBytes);
begin
  FLock.Enter;
  try
    FOutbox.Enqueue(AFrame);
  finally
    FLock.Leave;
  end;
end;

function TWsSession.TakeAll: TArray<TBytes>;
begin
  FLock.Enter;
  try
    Result := FOutbox.ToArray;
    FOutbox.Clear;
  finally
    FLock.Leave;
  end;
end;

{ ---- TSpikeServer --------------------------------------------------------- }

constructor TSpikeServer.Create(APort: Word; AIdleSeconds: Integer; const APagePath: string);
var
  Binding: TIdSocketHandle;
begin
  inherited Create;
  FPort := APort;
  FIdleMs := Int64(AIdleSeconds) * 1000;
  FPagePath := APagePath;
  FSessionsLock := TCriticalSection.Create;
  FSessions := TList<TWsSession>.Create;
  FServer := TIdHTTPServer.Create(nil);
  FServer.DefaultPort := APort;
  { A prova de conceito escuta so no endereco local: nada e exposto a rede. }
  FServer.Bindings.Clear;
  Binding := FServer.Bindings.Add;
  Binding.IP := '127.0.0.1';
  Binding.Port := APort;
  Binding.IPVersion := Id_IPv4;
  FServer.KeepAlive := False;
  FServer.MaxConnections := 200;
  FServer.ServerSoftware := 'WsSpike';
  FServer.OnCommandGet := HandleCommand;
  FServer.OnCommandOther := HandleCommand;
end;

destructor TSpikeServer.Destroy;
begin
  Stop;
  FServer.Free;
  FSessions.Free;
  FSessionsLock.Free;
  inherited;
end;

procedure TSpikeServer.Start;
begin
  FServer.Active := True;
end;

procedure TSpikeServer.BeginShutdown;
begin
  FStopping := True;
end;

function TSpikeServer.ActiveSessions: Integer;
begin
  FSessionsLock.Enter;
  try
    Result := FSessions.Count;
  finally
    FSessionsLock.Leave;
  end;
end;

function TSpikeServer.WaitSessions(ATimeoutMs: Integer): Integer;
var
  Deadline: Int64;
begin
  Deadline := NowMs + ATimeoutMs;
  repeat
    Result := ActiveSessions;
    if Result = 0 then
      Exit;
    Sleep(20);
  until NowMs > Deadline;
  Result := ActiveSessions;
end;

procedure TSpikeServer.Stop;
begin
  { Chamado na thread principal, nunca dentro de um evento do Indy. }
  if FServer.Active then
    FServer.Active := False;
end;

function TSpikeServer.StatsJson: string;
begin
  Result := Format('{"ativas":%d,"abertas":%d,"fechadas":%d,"erros":%d}',
    [ActiveSessions, FOpened, FClosed, FErrors]);
end;

function TSpikeServer.AllowedOrigin(const AOrigin: string): Boolean;
begin
  { Regra provisoria da prova de conceito (a politica completa e a da secao 7.7
    do plano, Entrega O3): sem Origin, ou a propria origem local. }
  Result := (AOrigin = '') or
    SameText(AOrigin, 'http://127.0.0.1:' + IntToStr(FPort)) or
    SameText(AOrigin, 'http://localhost:' + IntToStr(FPort));
end;

function TSpikeServer.Broadcast(const AFrame: TBytes; AExceptId: Integer): Integer;
var
  Session: TWsSession;
begin
  Result := 0;
  FSessionsLock.Enter;
  try
    for Session in FSessions do
      if Session.Id <> AExceptId then
      begin
        Session.Enqueue(AFrame);
        Inc(Result);
      end;
  finally
    FSessionsLock.Leave;
  end;
end;

procedure TSpikeServer.HandleCommand(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo);
var
  Method, Path: string;
  Sent: Integer;
begin
  Method := UpperCase(ARequestInfo.Command);
  Path := ARequestInfo.Document;
  try
    if Path = '/ws' then
    begin
      HandleUpgrade(AContext, ARequestInfo, AResponseInfo);
      Exit;
    end;
    if Path = '/health' then
      WriteJson(AResponseInfo, 200, '{"status":"ok"}')
    else if Path = '/stats' then
      WriteJson(AResponseInfo, 200, StatsJson)
    else if Path = '/page' then
    begin
      if TFile.Exists(FPagePath) then
        WriteBody(AResponseInfo, 200, 'text/html', TFile.ReadAllBytes(FPagePath))
      else
        WriteError(AResponseInfo, 404, 'PAGINA_AUSENTE');
    end
    else if (Path = '/push') and (Method = 'POST') then
    begin
      Sent := Broadcast(EncodeText('push:' + Utf8Text(ReadBody(ARequestInfo))), 0);
      WriteJson(AResponseInfo, 200, '{"enviados":' + IntToStr(Sent) + '}');
    end
    else
      WriteError(AResponseInfo, 404, 'ROTA_NAO_ENCONTRADA');
    Log('%s %s -> %d', [Method, Path, AResponseInfo.ResponseNo]);
  except
    on E: Exception do
    begin
      TInterlocked.Increment(FErrors);
      Log('ERRO em %s %s: %s: %s', [Method, Path, E.ClassName, E.Message]);
      if not AResponseInfo.HeaderHasBeenWritten then
      begin
        AResponseInfo.CustomHeaders.Clear;
        WriteError(AResponseInfo, 500, 'ERRO_INTERNO');
      end;
    end;
  end;
end;

procedure TSpikeServer.HandleUpgrade(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo);
var
  Key, Origin, Response: string;
  Session: TWsSession;
begin
  if UpperCase(ARequestInfo.Command) <> 'GET' then
  begin
    WriteError(AResponseInfo, 405, 'METODO_NAO_PERMITIDO');
    AResponseInfo.CustomHeaders.Values['Allow'] := 'GET';
    Log('%s /ws -> 405', [ARequestInfo.Command]);
    Exit;
  end;
  if not HeaderHasToken(ARequestInfo.RawHeaders.Values['Upgrade'], 'websocket') or
     not HeaderHasToken(ARequestInfo.RawHeaders.Values['Connection'], 'Upgrade') then
  begin
    WriteError(AResponseInfo, 400, 'HANDSHAKE_INVALIDO');
    Log('GET /ws -> 400 (sem Upgrade/Connection)');
    Exit;
  end;
  Key := Trim(ARequestInfo.RawHeaders.Values['Sec-WebSocket-Key']);
  if not IsValidHandshakeKey(Key) then
  begin
    WriteError(AResponseInfo, 400, 'HANDSHAKE_INVALIDO');
    Log('GET /ws -> 400 (chave invalida)');
    Exit;
  end;
  if Trim(ARequestInfo.RawHeaders.Values['Sec-WebSocket-Version']) <> '13' then
  begin
    WriteError(AResponseInfo, 426, 'VERSAO_WEBSOCKET');
    AResponseInfo.CustomHeaders.Values['Sec-WebSocket-Version'] := '13';
    Log('GET /ws -> 426 (versao)');
    Exit;
  end;
  Origin := ARequestInfo.RawHeaders.Values['Origin'];
  if not AllowedOrigin(Origin) then
  begin
    WriteError(AResponseInfo, 403, 'ORIGEM_NAO_PERMITIDA');
    Log('GET /ws -> 403 (origem "%s")', [Copy(Origin, 1, 100)]);
    Exit;
  end;

  { Resposta 101 escrita diretamente: WriteHeader do Indy acrescentaria
    "Connection: close" (KeepAlive = False) e nao tem texto para o 101. }
  Response := 'HTTP/1.1 101 Switching Protocols'#13#10 +
    'Upgrade: websocket'#13#10 +
    'Connection: Upgrade'#13#10 +
    'Sec-WebSocket-Accept: ' + ComputeAcceptKey(Key) + #13#10#13#10;
  AContext.Connection.IOHandler.Write(ToBytes(Response, IndyTextEncoding_ASCII));
  AResponseInfo.HeaderHasBeenWritten := True;

  Session := TWsSession.Create(TInterlocked.Increment(FNextId),
    AContext.Binding.PeerIP + ':' + IntToStr(AContext.Binding.PeerPort));
  FSessionsLock.Enter;
  try
    FSessions.Add(Session);
  finally
    FSessionsLock.Leave;
  end;
  TInterlocked.Increment(FOpened);
  if Origin = '' then
    Origin := '(sem Origin)';
  Log('WS %d aberta: %s, origem %s', [Session.Id, Session.Peer, Origin]);
  try
    RunSession(AContext, Session);
  finally
    FSessionsLock.Enter;
    try
      FSessions.Remove(Session);
    finally
      FSessionsLock.Leave;
    end;
    TInterlocked.Increment(FClosed);
    Session.Free;
  end;
end;

procedure TSpikeServer.RunSession(AContext: TIdContext; ASession: TWsSession);
var
  IO: TIdIOHandler;
  Decoder: TWsDecoder;
  Assembler: TWsAssembler;
  Chunk: TIdBytes;
  Frame: TWsFrame;
  Payload: TBytes;
  Pending: TArray<TBytes>;
  Status: TWsDecodeStatus;
  Event: TWsEvent;
  Code: Word;
  CloseReason, Reason: string;
  LastReceived, CloseSentAt: Int64;
  Done: Boolean;
  I, Sent: Integer;

  procedure SendRaw(const AFrame: TBytes);
  begin
    IO.Write(TIdBytes(AFrame));
  end;

  procedure StartClose(ACode: Word; const AReason: string);
  begin
    if CloseSentAt < 0 then
    begin
      SendRaw(EncodeClose(ACode, AReason));
      CloseSentAt := NowMs;
      if Reason = '' then
        Reason := Format('servidor fechou com %d (%s)', [ACode, AReason]);
    end;
  end;

  procedure HandleText(const AText: string);
  begin
    if AText = 'fechar' then
      StartClose(CLOSE_NORMAL, 'pedido do cliente')
    else if Copy(AText, 1, 6) = 'todos:' then
    begin
      Sent := Broadcast(EncodeText('de:' + IntToStr(ASession.Id) + ':' + Copy(AText, 7, MaxInt)), ASession.Id);
      SendRaw(EncodeText('enviado:' + IntToStr(Sent)));
    end
    else
      SendRaw(EncodeText('eco:' + AText));
  end;

begin
  IO := AContext.Connection.IOHandler;
  Decoder := TWsDecoder.Create;
  Assembler := TWsAssembler.Create;
  CloseSentAt := -1;
  Reason := '';
  Done := False;
  LastReceived := NowMs;
  try
    try
      SendRaw(EncodeText('ola:' + IntToStr(ASession.Id)));
      while not Done do
      begin
        { 1. Servidor encerrando: avisa com 1001. }
        if FStopping and (CloseSentAt < 0) then
          StartClose(CLOSE_GOING_AWAY, 'servidor encerrando');

        { 2. Caixa de saida (mensagens enfileiradas por outras threads). }
        if CloseSentAt < 0 then
        begin
          Pending := ASession.TakeAll;
          for I := 0 to High(Pending) do
            SendRaw(Pending[I]);
        end;

        { 3. Leitura, com espera curta. }
        if IO.InputBufferIsEmpty then
          IO.CheckForDataOnSource(LOOP_WAIT_MS);
        if not IO.InputBufferIsEmpty then
        begin
          SetLength(Chunk, 0);
          IO.InputBuffer.ExtractToBytes(Chunk);
          Decoder.Append(TBytes(Chunk));
          LastReceived := NowMs;
          repeat
            Status := Decoder.Next(Frame, Code);
            if Status = dsError then
            begin
              StartClose(Code, 'quadro invalido');
              Done := True;
            end
            else if Status = dsFrame then
            begin
              Event := Assembler.Feed(Frame, Payload, Code);
              case Event of
                weText:
                  if CloseSentAt < 0 then
                    HandleText(Utf8Text(Payload));
                weBinary:
                  begin
                    StartClose(CLOSE_UNSUPPORTED, 'binario nao suportado');
                    Done := True;
                  end;
                wePing:
                  SendRaw(EncodeFrame(OP_PONG, Payload));
                weClose:
                  begin
                    if CloseSentAt < 0 then
                    begin
                      if ParseClosePayload(Payload, Code, CloseReason) then
                      begin
                        if Code = CLOSE_NO_STATUS then
                          SendRaw(EncodeFrame(OP_CLOSE, nil))
                        else
                          SendRaw(EncodeClose(Code, ''));
                        Reason := Format('cliente fechou com %d (%s)', [Code, CloseReason]);
                      end
                      else
                      begin
                        SendRaw(EncodeClose(CLOSE_PROTOCOL_ERROR, 'fechamento invalido'));
                        Reason := 'cliente enviou fechamento invalido; servidor fechou com 1002';
                      end;
                    end
                    else if Reason <> '' then
                      Reason := Reason + '; cliente confirmou';
                    Done := True;
                  end;
                weError:
                  begin
                    StartClose(Code, 'mensagem invalida');
                    Done := True;
                  end;
              end;
            end;
          until (Status <> dsFrame) or Done;
        end
        else if not IO.Connected then
        begin
          if Reason = '' then
            Reason := 'cliente desconectou sem quadro de fechamento';
          Done := True;
        end;

        { 4. Depois de pedir o fechamento, espera a confirmacao por pouco tempo. }
        if (CloseSentAt >= 0) and (NowMs - CloseSentAt > CLOSE_WAIT_MS) then
          Done := True;

        { 5. Inatividade. }
        if (not Done) and (CloseSentAt < 0) and (NowMs - LastReceived > FIdleMs) then
          StartClose(CLOSE_IDLE, 'tempo esgotado');
      end;
    except
      on E: EIdException do
        if Reason = '' then
          Reason := 'conexao interrompida (' + E.ClassName + ': ' + E.Message + ')';
      on E: Exception do
      begin
        TInterlocked.Increment(FErrors);
        Reason := 'ERRO inesperado na sessao: ' + E.ClassName + ': ' + E.Message;
      end;
    end;
  finally
    Assembler.Free;
    Decoder.Free;
    Log('WS %d fechada: %s', [ASession.Id, Reason]);
  end;
end;

end.
