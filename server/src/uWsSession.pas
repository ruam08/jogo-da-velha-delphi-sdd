unit uWsSession;

(* Sessão do canal em tempo real sobre o TIdHTTPServer (docs/plan-online.md,
  seções 7.2 a 7.5, 8.3 e 8.4; DTO-01, DTO-02 e DTO-06).

  Origem: o laço da prova de conceito O0 (spikes/ws-indy/src/uWsSpikeServer.pas,
  RunSession), validado contra clientes Node, Chromium e 50 canais. Nesta
  versão o laço fala o protocolo das salas em vez do eco da prova de conceito.

  Regras desta unit:
  - roda dentro do OnCommandGet, na thread do Indy daquela conexão, até o
    canal fechar; só ESTA thread escreve no socket (as outras só enfileiram
    na caixa de saída, via hub);
  - o cliente só pode mandar "entrar" (uma vez, primeira mensagem, dentro de
    --ws-hello-seconds) e "ping" (depois de entrar). Nada do que chega pelo
    canal muda a sala (RNO-12): jogadas são só por REST;
  - "entrar" valida a sala e o token NA SALA (Attach), nunca confia em lugar
    informado pelo cliente; token inválido -> erro TOKEN_INVALIDO e 4401;
  - antes de todo fechamento 4xxx vai a mensagem "erro" (ou sala_encerrada);
  - o token nunca é escrito no log;
  - O6 (seção 13.1, B4 e B14): com MsgRateLimit > 0, mais de MsgRateLimit
    quadros do cliente em 10 s -> erro LIMITE_DE_MENSAGENS e fechamento 1008.

  A abertura (101) é escrita por uHttpApp; esta unit recebe a conexão já
  trocada para WebSocket. *)

interface

uses
  System.SysUtils, IdContext, uRoomRegistry, uRoomHub;

type
  TWsSessionConfig = record
    Registry: TRoomRegistry;
    Hub: TRoomHub;
    HelloMs: Int64;
    IdleMs: Int64;
    PingIntervalMs: Integer;
    IsStopping: TFunc<Boolean>;
    { O6: quadros do cliente por 10 s; 0 = sem limite. }
    MsgRateLimit: Integer;
  end;

{ Executa a sessão até o canal fechar. ASummary: motivo do fim, para o log. }
procedure RunWsSession(AContext: TIdContext; ASessionId: Int64; const AConfig: TWsSessionConfig;
  out ASummary: string);

{ Novo identificador de canal (único no processo). }
function NextWsSessionId: Int64;
{ Canais abertos neste momento. }
function ActiveWsSessions: Integer;

implementation

uses
  System.SyncObjs, System.Diagnostics, IdGlobal, IdIOHandler, IdException,
  uRoom, uRoomJson, uWebSocket, uConsoleLog, uRateLimiter, uRequestLimits;

const
  LOOP_WAIT_MS = 50;
  CLOSE_WAIT_MS = 1000;

var
  GNextSessionId: Int64 = 0;
  GActiveSessions: Integer = 0;
  GWatch: TStopwatch;

function NextWsSessionId: Int64;
begin
  Result := TInterlocked.Increment(GNextSessionId);
end;

function ActiveWsSessions: Integer;
begin
  Result := TInterlocked.CompareExchange(GActiveSessions, 0, 0);
end;

{ Relógio monotônico da sessão (prazos de entrar e de inatividade). }
function NowMs: Int64;
begin
  Result := GWatch.ElapsedMilliseconds;
end;

procedure RunWsSession(AContext: TIdContext; ASessionId: Int64; const AConfig: TWsSessionConfig;
  out ASummary: string);
var
  IO: TIdIOHandler;
  Decoder: TWsDecoder;
  Assembler: TWsAssembler;
  Outbox: TOutbox;
  Chunk: TIdBytes;
  Frame: TWsFrame;
  Payload: TBytes;
  Pending: TArray<TOutboxItem>;
  Status: TWsDecodeStatus;
  Event: TWsEvent;
  Code: Word;
  CloseReason: string;
  StartedAt, LastReceived, CloseSentAt: Int64;
  Done, Entered: Boolean;
  Room: IRoom;
  RoomCode: string;
  Seat: TSeat;
  I: Integer;
  Outcome: TRoomOutcome;
  MsgWindow: TMessageWindow;

  procedure SendRaw(const AFrame: TBytes);
  begin
    IO.Write(TIdBytes(AFrame));
  end;

  procedure SendText(const AText: string);
  begin
    SendRaw(EncodeText(AText));
  end;

  procedure StartClose(ACode: Word; const AReason: string);
  begin
    if CloseSentAt < 0 then
    begin
      SendRaw(EncodeClose(ACode, AReason));
      CloseSentAt := NowMs;
      if ASummary = '' then
        ASummary := Format('servidor fechou com %d (%s)', [ACode, AReason]);
    end;
  end;

  { Mensagem "erro" seguida do fechamento correspondente (seção 7.4). }
  procedure Fail(const AErrorCode, AMessage: string; ACloseCode: Word);
  begin
    if CloseSentAt >= 0 then
      Exit;
    SendText(ErrorEventJson(AErrorCode, AMessage));
    StartClose(ACloseCode, AErrorCode);
  end;

  procedure HandleEnter(const AMsg: TClientMessage);
  var
    FindResult: TRoomResult;
    Replaced: Int64;
    State: TRoomSnapshot;
  begin
    FindResult := AConfig.Registry.Find(AMsg.Room, Room);
    if FindResult = rrNotFound then
      begin Fail(ERR_ROOM_NOT_FOUND, MSG_ROOM_NOT_FOUND, CLOSE_ROOM_NOT_FOUND); Exit; end;
    if FindResult <> rrOk then
      begin Fail(ERR_ROOM_CLOSED, MSG_ROOM_CLOSED, CLOSE_ROOM_CLOSED); Exit; end;
    { O lugar sai do token, validado pela sala na sua seção crítica. }
    Outcome := Room.Attach(AMsg.Token, ASessionId, Seat, Replaced);
    case Outcome.Result of
      rrOk: ;
      rrInvalidToken:
        begin Fail(ERR_INVALID_TOKEN, MSG_INVALID_TOKEN, CLOSE_INVALID_TOKEN); Exit; end;
      rrClosed:
        begin Fail(ERR_ROOM_CLOSED, MSG_ROOM_CLOSED, CLOSE_ROOM_CLOSED); Exit; end;
    else
      begin Fail(ERR_INVALID_MESSAGE, MSG_INVALID_MESSAGE, CLOSE_INVALID_MESSAGE); Exit; end;
    end;
    Entered := True;
    RoomCode := Room.Code;
    { 8.3: inscreve antes de ler o estado do bem_vindo, para não perder nada. }
    AConfig.Hub.Subscribe(RoomCode, Seat, ASessionId, Outbox, ErrorEventJson(ERR_REPLACED, MSG_REPLACED));
    if Outcome.Changed then
      AConfig.Hub.PublishState(RoomCode, StateEventJson(Outcome.Snapshot, srConnect), Outcome.Snapshot.Version);
    State := Room.Snapshot;
    Outbox.SetBaseline(State.Version);
    SendText(WelcomeJson(State, Seat, AConfig.PingIntervalMs));
    Log('WS %d entrou na sala %s como %s', [ASessionId, RoomCode, SeatName(Seat)]);
  end;

  procedure HandleText(const ABytes: TBytes);
  var
    Msg: TClientMessage;
  begin
    if not ParseClientMessage(ABytes, Msg) then
      begin Fail(ERR_INVALID_MESSAGE, MSG_INVALID_MESSAGE, CLOSE_INVALID_MESSAGE); Exit; end;
    case Msg.Kind of
      cmEnter:
        if Entered then
          Fail(ERR_INVALID_MESSAGE, MSG_INVALID_MESSAGE, CLOSE_INVALID_MESSAGE)
        else
          HandleEnter(Msg);
      cmPing:
        if not Entered then
          Fail(ERR_INVALID_MESSAGE, MSG_INVALID_MESSAGE, CLOSE_INVALID_MESSAGE)
        else
          SendText(PongJson(Msg.PingId));
    end;
  end;

  procedure HandleClose(const APayload: TBytes);
  begin
    if CloseSentAt < 0 then
    begin
      if ParseClosePayload(APayload, Code, CloseReason) then
      begin
        if Code = CLOSE_NO_STATUS then
          SendRaw(EncodeFrame(OP_CLOSE, nil))
        else
          SendRaw(EncodeClose(Code, ''));
        ASummary := Format('cliente fechou com %d', [Code]);
      end
      else
      begin
        SendRaw(EncodeClose(CLOSE_PROTOCOL_ERROR, 'fechamento invalido'));
        ASummary := 'cliente enviou fechamento invalido; servidor fechou com 1002';
      end;
    end
    else
      ASummary := ASummary + '; cliente confirmou';
    Done := True;
  end;

begin
  ASummary := '';
  TInterlocked.Increment(GActiveSessions);
  IO := AContext.Connection.IOHandler;
  Decoder := TWsDecoder.Create;
  Assembler := TWsAssembler.Create;
  Outbox := TOutbox.Create;
  CloseSentAt := -1;
  Done := False;
  Entered := False;
  Room := nil;
  RoomCode := '';
  Seat := seX;
  StartedAt := NowMs;
  LastReceived := StartedAt;
  MsgWindow.Init(AConfig.MsgRateLimit);
  try
    try
      while not Done do
      begin
        { 1. Servidor encerrando: avisa com 1001. }
        if (CloseSentAt < 0) and AConfig.IsStopping() then
          StartClose(CLOSE_GOING_AWAY, 'servidor encerrando');

        { 2. Caixa de saída (mensagens enfileiradas pelo hub, de outras threads). }
        if Entered and (CloseSentAt < 0) then
        begin
          if Outbox.Overflowed then
            StartClose(CLOSE_POLICY, 'caixa de saida cheia')
          else
          begin
            Pending := Outbox.TakeAll;
            for I := 0 to High(Pending) do
            begin
              SendText(Pending[I].Text);
              if Pending[I].Kind = okTerminal then
              begin
                StartClose(Pending[I].CloseCode, 'mensagem terminal');
                Break;
              end;
            end;
          end;
        end;

        { 3. Leitura, com espera curta (seção 8.4). }
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
              { O6: taxa de quadros do cliente (todos os tipos). }
              if (CloseSentAt < 0) and not MsgWindow.Hit(NowMs) then
                Fail(ERR_MESSAGE_RATE, MSG_MESSAGE_RATE, CLOSE_POLICY);
              Event := Assembler.Feed(Frame, Payload, Code);
              case Event of
                weText:
                  if CloseSentAt < 0 then
                    HandleText(Payload);
                weBinary:
                  Fail(ERR_INVALID_MESSAGE, MSG_INVALID_MESSAGE, CLOSE_INVALID_MESSAGE);
                wePing:
                  SendRaw(EncodeFrame(OP_PONG, Payload));
                weClose:
                  HandleClose(Payload);
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
          if ASummary = '' then
            ASummary := 'cliente desconectou sem quadro de fechamento';
          Done := True;
        end;

        { 4. Depois de pedir o fechamento, espera a confirmação por pouco tempo. }
        if (CloseSentAt >= 0) and (NowMs - CloseSentAt > CLOSE_WAIT_MS) then
          Done := True;

        { 5. Prazos: "entrar" e inatividade. }
        if (not Done) and (CloseSentAt < 0) then
        begin
          if (not Entered) and (NowMs - StartedAt > AConfig.HelloMs) then
            Fail(ERR_TIMEOUT, MSG_TIMEOUT, CLOSE_TIMEOUT)
          else if NowMs - LastReceived > AConfig.IdleMs then
            Fail(ERR_TIMEOUT, MSG_TIMEOUT, CLOSE_TIMEOUT);
        end;
      end;
    except
      on E: EIdException do
        if ASummary = '' then
          ASummary := 'conexao interrompida (' + E.ClassName + ')';
      on E: Exception do
      begin
        ASummary := 'ERRO inesperado na sessao: ' + E.ClassName + ': ' + E.Message;
        try
          StartClose(CLOSE_INTERNAL, 'erro interno');
        except
          { o socket pode já estar fechado }
        end;
      end;
    end;
  finally
    { 8.3: cancela a inscrição e solta o lugar (só se este for o canal atual). }
    try
      if Entered then
      begin
        AConfig.Hub.Unsubscribe(RoomCode, Outbox);
        Outcome := Room.Detach(Seat, ASessionId);
        if Outcome.Changed then
          AConfig.Hub.PublishState(RoomCode, StateEventJson(Outcome.Snapshot, srDisconnect),
            Outcome.Snapshot.Version);
      end;
    finally
      Room := nil;
      Outbox.Free;
      Assembler.Free;
      Decoder.Free;
      TInterlocked.Decrement(GActiveSessions);
    end;
  end;
end;

initialization
  GWatch := TStopwatch.StartNew;

end.
