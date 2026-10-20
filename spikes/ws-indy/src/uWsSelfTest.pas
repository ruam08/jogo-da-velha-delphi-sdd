unit uWsSelfTest;

{ Prova de conceito da Entrega O0 (descartavel).
  Autoteste do protocolo, sem rede: WsSpike.exe --selftest
  Codigo de saida 0 = todos os casos passaram; 1 = houve falha. }

interface

function RunSelfTest: Integer;

implementation

uses
  System.SysUtils, System.NetEncoding, System.Generics.Collections,
  IdGlobal, IdHashSHA, IdCoderMIME,
  uWsCodec, uSpikeLog;

const
  RFC_KEY = 'dGhlIHNhbXBsZSBub25jZQ==';
  RFC_ACCEPT = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=';

var
  Passes, Failures: Integer;

procedure Check(const AId, ADescription: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then
  begin
    Inc(Passes);
    Log('[OK]    %s %s', [AId, ADescription]);
  end
  else
  begin
    Inc(Failures);
    Log('[FALHA] %s %s %s', [AId, ADescription, ADetail]);
  end;
end;

function IndyAcceptKey(const AKey: string): string;
var
  Hash: TIdHashSHA1;
begin
  Hash := TIdHashSHA1.Create;
  try
    Result := TIdEncoderMIME.EncodeBytes(Hash.HashString(AKey + WS_GUID, IndyTextEncoding_UTF8));
  finally
    Hash.Free;
  end;
end;

function B(const AValues: array of Byte): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(AValues));
  for I := 0 to High(AValues) do
    Result[I] := AValues[I];
end;

function Filled(AValue: Byte; ACount: Integer): TBytes;
begin
  SetLength(Result, ACount);
  if ACount > 0 then
    FillChar(Result[0], ACount, AValue);
end;

function Join(const AParts: array of TBytes): TBytes;
var
  I, Pos: Integer;
  Total: Integer;
begin
  Total := 0;
  for I := 0 to High(AParts) do
    Inc(Total, Length(AParts[I]));
  SetLength(Result, Total);
  Pos := 0;
  for I := 0 to High(AParts) do
    if Length(AParts[I]) > 0 then
    begin
      Move(AParts[I][0], Result[Pos], Length(AParts[I]));
      Inc(Pos, Length(AParts[I]));
    end;
end;

function SameBytes(const A, AB: TBytes): Boolean;
begin
  Result := (Length(A) = Length(AB)) and ((Length(A) = 0) or CompareMem(@A[0], @AB[0], Length(A)));
end;

function Hex(const A: TBytes; AMax: Integer = 12): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(A) - 1 do
  begin
    if I >= AMax then
    begin
      Result := Result + '...';
      Break;
    end;
    Result := Result + IntToHex(A[I], 2) + ' ';
  end;
end;

{ Decodifica tudo o que estiver em AData; devolve o status final, os quadros e o codigo de erro. }
function DecodeAll(const AData: TBytes; AFrames: TList<TWsFrame>; out ACode: Word): TWsDecodeStatus;
var
  Decoder: TWsDecoder;
  Frame: TWsFrame;
begin
  Decoder := TWsDecoder.Create;
  try
    Decoder.Append(AData);
    repeat
      Result := Decoder.Next(Frame, ACode);
      if Result = dsFrame then
        AFrames.Add(Frame);
    until Result <> dsFrame;
  finally
    Decoder.Free;
  end;
end;

function DecodeError(const AData: TBytes): Word;
var
  Frames: TList<TWsFrame>;
  Code: Word;
begin
  Frames := TList<TWsFrame>.Create;
  try
    if DecodeAll(AData, Frames, Code) = dsError then
      Result := Code
    else
      Result := 0;
  finally
    Frames.Free;
  end;
end;

procedure TestHandshake;
var
  I, Mismatch: Integer;
  Raw: TBytes;
  Key, Rtl, Indy: string;
begin
  Rtl := ComputeAcceptKey(RFC_KEY);
  Check('ST-01', 'Aceite do exemplo da RFC 6455 pela RTL (System.Hash + System.NetEncoding)', Rtl = RFC_ACCEPT, 'obtido ' + Rtl);
  Indy := IndyAcceptKey(RFC_KEY);
  Check('ST-02', 'Aceite do exemplo da RFC 6455 pelo Indy (TIdHashSHA1 + TIdEncoderMIME)', Indy = RFC_ACCEPT, 'obtido ' + Indy);

  Randomize;
  Mismatch := 0;
  for I := 1 to 1000 do
  begin
    Raw := Filled(0, 16);
    Raw[0] := Random(256); Raw[1] := Random(256); Raw[2] := Random(256); Raw[3] := Random(256);
    Raw[4] := Random(256); Raw[5] := Random(256); Raw[6] := Random(256); Raw[7] := Random(256);
    Raw[8] := Random(256); Raw[9] := Random(256); Raw[10] := Random(256); Raw[11] := Random(256);
    Raw[12] := Random(256); Raw[13] := Random(256); Raw[14] := Random(256); Raw[15] := Random(256);
    Key := TNetEncoding.Base64.EncodeBytesToString(Raw);
    if (not IsValidHandshakeKey(Key)) or (ComputeAcceptKey(Key) <> IndyAcceptKey(Key)) then
      Inc(Mismatch);
  end;
  Check('ST-03', 'RTL e Indy geram o mesmo aceite para 1000 chaves aleatorias', Mismatch = 0, IntToStr(Mismatch) + ' divergencias');

  Check('ST-04', 'Validacao da chave: valida, curta, caractere invalido, 15 bytes',
    IsValidHandshakeKey(RFC_KEY) and not IsValidHandshakeKey('abc') and
    not IsValidHandshakeKey('dGhlIHNhbXBsZSBub25jZ*==') and
    not IsValidHandshakeKey(TNetEncoding.Base64.EncodeBytesToString(Filled(65, 15))));
  Check('ST-05', 'Cabecalho Connection com lista de tokens',
    HeaderHasToken('keep-alive, Upgrade', 'upgrade') and not HeaderHasToken('keep-alive', 'Upgrade'));
end;

procedure TestDecoding;
var
  Frames: TList<TWsFrame>;
  Code: Word;
  Status: TWsDecodeStatus;
  Decoder: TWsDecoder;
  Frame: TWsFrame;
  Data, Big: TBytes;
  I, NeedMore: Integer;
  Ok: Boolean;
begin
  Frames := TList<TWsFrame>.Create;
  try
    { Exemplo da RFC 6455, secao 5.7: "Hello" com mascara. }
    Status := DecodeAll(B([$81, $85, $37, $FA, $21, $3D, $7F, $9F, $4D, $51, $58]), Frames, Code);
    Check('ST-06', 'Quadro de texto com mascara do exemplo da RFC ("Hello")',
      (Status = dsNeedMore) and (Frames.Count = 1) and Frames[0].Fin and (Frames[0].Opcode = OP_TEXT) and
      (Utf8Text(Frames[0].Payload) = 'Hello'));

    Check('ST-07', 'Quadro sem mascara -> 1002', DecodeError(B([$81, $05, $48, $65, $6C, $6C, $6F])) = CLOSE_PROTOCOL_ERROR);

    Frames.Clear;
    Big := Filled(Ord('a'), 126);
    Status := DecodeAll(EncodeMaskedFrame(OP_TEXT, Big, True), Frames, Code);
    Check('ST-08', 'Tamanho de 16 bits (126 bytes)', (Status = dsNeedMore) and (Frames.Count = 1) and SameBytes(Frames[0].Payload, Big));

    { Cabecalho anunciando 70000 bytes: recusado antes de receber o conteudo. }
    Data := B([$81, $FF, 0, 0, 0, 0, 0, 1, $11, $70, $11, $22, $33, $44]);
    Check('ST-09', 'Tamanho de 64 bits acima do limite -> 1009 so pelo cabecalho', DecodeError(Data) = CLOSE_TOO_BIG);

    { Entrega byte a byte: "Ola" com acento (O l a-agudo em UTF-8). }
    Data := EncodeMaskedFrame(OP_TEXT, B([$4F, $6C, $C3, $A1]), True);
    Decoder := TWsDecoder.Create;
    try
      NeedMore := 0;
      Ok := False;
      for I := 0 to Length(Data) - 1 do
      begin
        Decoder.Append(B([Data[I]]));
        Status := Decoder.Next(Frame, Code);
        if Status = dsNeedMore then
          Inc(NeedMore)
        else if Status = dsFrame then
          Ok := (I = Length(Data) - 1) and (Utf8Text(Frame.Payload) = 'Ol' + Char($00E1));
      end;
      Check('ST-10', 'Quadro recebido byte a byte e texto UTF-8 com acento', Ok and (NeedMore = Length(Data) - 1));
    finally
      Decoder.Free;
    end;

    Frames.Clear;
    Status := DecodeAll(Join([EncodeMaskedFrame(OP_TEXT, B([$61]), True), EncodeMaskedFrame(OP_TEXT, B([$62]), True)]), Frames, Code);
    Check('ST-11', 'Dois quadros no mesmo bloco de bytes', (Status = dsNeedMore) and (Frames.Count = 2) and (Utf8Text(Frames[1].Payload) = 'b'));

    Check('ST-12', 'Bit RSV1 ligado -> 1002', DecodeError(B([$C1, $80, 1, 2, 3, 4])) = CLOSE_PROTOCOL_ERROR);
    Check('ST-13', 'Opcode reservado (3) -> 1002', DecodeError(B([$83, $80, 1, 2, 3, 4])) = CLOSE_PROTOCOL_ERROR);
    Check('ST-14', 'Controle com 126 bytes -> 1002', DecodeError(EncodeMaskedFrame(OP_PING, Filled(1, 126), True)) = CLOSE_PROTOCOL_ERROR);
    Check('ST-15', 'Controle fragmentado (sem FIN) -> 1002', DecodeError(EncodeMaskedFrame(OP_PING, B([1]), False)) = CLOSE_PROTOCOL_ERROR);
  finally
    Frames.Free;
  end;
end;

{ Passa os quadros pelo decodificador e pelo montador; devolve os eventos em texto. }
function Events(const AData: TBytes): string;
var
  Frames: TList<TWsFrame>;
  Assembler: TWsAssembler;
  Code: Word;
  Payload: TBytes;
  Ev: TWsEvent;
  I: Integer;
begin
  Result := '';
  Frames := TList<TWsFrame>.Create;
  Assembler := TWsAssembler.Create;
  try
    if DecodeAll(AData, Frames, Code) = dsError then
      Exit('decoder:' + IntToStr(Code));
    for I := 0 to Frames.Count - 1 do
    begin
      Ev := Assembler.Feed(Frames[I], Payload, Code);
      case Ev of
        weNone: Result := Result + '-;';
        weText: Result := Result + 'text:' + Utf8Text(Payload) + ';';
        weBinary: Result := Result + 'bin:' + IntToStr(Length(Payload)) + ';';
        wePing: Result := Result + 'ping:' + Utf8Text(Payload) + ';';
        wePong: Result := Result + 'pong;';
        weClose: Result := Result + 'close;';
        weError:
          begin
            Result := Result + 'erro:' + IntToStr(Code) + ';';
            Exit;
          end;
      end;
    end;
  finally
    Assembler.Free;
    Frames.Free;
  end;
end;

procedure TestAssembling;
var
  Got: string;
begin
  Got := Events(Join([
    EncodeMaskedFrame(OP_TEXT, B([$61, $62]), False),
    EncodeMaskedFrame(OP_PING, B([$70]), True),
    EncodeMaskedFrame(OP_CONTINUATION, B([$63, $64]), False),
    EncodeMaskedFrame(OP_CONTINUATION, B([$65, $66]), True)]));
  Check('ST-16', 'Fragmentos com ping no meio -> uma mensagem "abcdef"', Got = '-;ping:p;-;text:abcdef;', Got);

  Got := Events(EncodeMaskedFrame(OP_CONTINUATION, B([$61]), True));
  Check('ST-17', 'Continuacao sem inicio -> 1002', Got = 'erro:1002;', Got);

  Got := Events(Join([EncodeMaskedFrame(OP_TEXT, B([$61]), False), EncodeMaskedFrame(OP_TEXT, B([$62]), True)]));
  Check('ST-18', 'Nova mensagem antes do fim da anterior -> 1002', Got = '-;erro:1002;', Got);

  Got := Events(EncodeMaskedFrame(OP_TEXT, B([$C3, $28]), True));
  Check('ST-19', 'Texto com UTF-8 invalido -> 1007', Got = 'erro:1007;', Got);

  Got := Events(Join([EncodeMaskedFrame(OP_TEXT, Filled(Ord('x'), 2048), False),
    EncodeMaskedFrame(OP_CONTINUATION, Filled(Ord('y'), 2048), True)]));
  Check('ST-20', 'Mensagem fragmentada de 4096 bytes e aceita', Copy(Got, 1, 7) = '-;text:', Copy(Got, 1, 20));

  Got := Events(Join([EncodeMaskedFrame(OP_TEXT, Filled(Ord('x'), 2049), False),
    EncodeMaskedFrame(OP_CONTINUATION, Filled(Ord('y'), 2048), True)]));
  Check('ST-21', 'Mensagem fragmentada de 4097 bytes -> 1009', Got = '-;erro:1009;', Got);

  Got := Events(EncodeMaskedFrame(OP_BINARY, B([1, 2, 3]), True));
  Check('ST-22', 'Quadro binario e reconhecido como binario', Got = 'bin:3;', Got);
end;

procedure TestEncoding;
var
  Frame, Expected: TBytes;
  Code: Word;
  Reason: string;
begin
  Frame := EncodeText('Hello');
  Check('ST-23', 'Texto de 5 bytes do servidor: FIN, sem mascara', SameBytes(Copy(Frame, 0, 2), B([$81, $05])), Hex(Frame));
  Frame := EncodeFrame(OP_TEXT, Filled(1, 126));
  Check('ST-24', 'Texto de 126 bytes: tamanho de 16 bits', SameBytes(Copy(Frame, 0, 4), B([$81, 126, 0, 126])), Hex(Frame));
  Frame := EncodeFrame(OP_TEXT, Filled(1, 70000));
  Expected := B([$81, 127, 0, 0, 0, 0, 0, 1, $11, $70]);
  Check('ST-25', 'Texto de 70000 bytes: tamanho de 64 bits', SameBytes(Copy(Frame, 0, 10), Expected) and (Length(Frame) = 70010), Hex(Frame));
  Frame := EncodeClose(1001, 'x');
  Check('ST-26', 'Fechamento 1001 com motivo', SameBytes(Frame, B([$88, $03, $03, $E9, $78])), Hex(Frame));
  Check('ST-27', 'Leitura do fechamento: com codigo, vazio (1005) e com 1 byte (invalido)',
    ParseClosePayload(B([$03, $E9, $78]), Code, Reason) and (Code = 1001) and (Reason = 'x') and
    ParseClosePayload(nil, Code, Reason) and (Code = CLOSE_NO_STATUS) and
    not ParseClosePayload(B([$03]), Code, Reason));
end;

function RunSelfTest: Integer;
begin
  Passes := 0;
  Failures := 0;
  Log('===== Autoteste do protocolo (sem rede)');
  try
    TestHandshake;
    TestDecoding;
    TestAssembling;
    TestEncoding;
  except
    on E: Exception do
    begin
      Inc(Failures);
      Log('[FALHA] excecao no autoteste: %s: %s', [E.ClassName, E.Message]);
    end;
  end;
  Log('Autoteste: %d aprovados, %d falharam', [Passes, Failures]);
  if Failures = 0 then
    Result := 0
  else
    Result := 1;
end;

end.
