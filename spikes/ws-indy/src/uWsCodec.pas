unit uWsCodec;

{ Prova de conceito da Entrega O0 (descartavel).
  Protocolo WebSocket (RFC 6455) sem Indy e sem rede: handshake e quadros
  sobre TBytes, para poder ser testado isoladamente (--selftest).
  A versao de producao (uWebSocket) sera escrita na Entrega O3. }

interface

uses
  System.SysUtils;

const
  WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  OP_CONTINUATION = $0;
  OP_TEXT = $1;
  OP_BINARY = $2;
  OP_CLOSE = $8;
  OP_PING = $9;
  OP_PONG = $A;

  CLOSE_NORMAL = 1000;
  CLOSE_GOING_AWAY = 1001;
  CLOSE_PROTOCOL_ERROR = 1002;
  CLOSE_UNSUPPORTED = 1003;
  CLOSE_NO_STATUS = 1005;
  CLOSE_INVALID_DATA = 1007;
  CLOSE_TOO_BIG = 1009;
  CLOSE_INTERNAL = 1011;
  CLOSE_IDLE = 4408;

  MAX_MESSAGE_SIZE = 4096;
  MAX_CONTROL_SIZE = 125;

type
  TWsFrame = record
    Fin: Boolean;
    Opcode: Byte;
    Payload: TBytes;
  end;

  TWsDecodeStatus = (dsNeedMore, dsFrame, dsError);

  { Acumula os bytes recebidos e devolve quadros completos (cliente -> servidor,
    sempre com mascara). }
  TWsDecoder = class
  private
    FBuffer: TBytes;
    FCount: Integer;
  public
    procedure Append(const AData: TBytes);
    function Next(out AFrame: TWsFrame; out ACloseCode: Word): TWsDecodeStatus;
    property Buffered: Integer read FCount;
  end;

  TWsEvent = (weNone, weText, weBinary, wePing, wePong, weClose, weError);

  { Remonta mensagens fragmentadas e aplica o limite de tamanho e o UTF-8. }
  TWsAssembler = class
  private
    FInMessage: Boolean;
    FOpcode: Byte;
    FData: TBytes;
    function Finish(AOpcode: Byte; const AData: TBytes; out APayload: TBytes;
      out ACloseCode: Word): TWsEvent;
  public
    function Feed(const AFrame: TWsFrame; out APayload: TBytes; out ACloseCode: Word): TWsEvent;
  end;

function ComputeAcceptKey(const AKey: string): string;
function IsValidHandshakeKey(const AKey: string): Boolean;
function HeaderHasToken(const AValue, AToken: string): Boolean;
function EncodeFrame(AOpcode: Byte; const APayload: TBytes): TBytes;
function EncodeMaskedFrame(AOpcode: Byte; const APayload: TBytes; AFin: Boolean): TBytes;
function EncodeText(const AText: string): TBytes;
function EncodeClose(ACode: Word; const AReason: string): TBytes;
function ParseClosePayload(const APayload: TBytes; out ACode: Word; out AReason: string): Boolean;
function IsValidUtf8(const ABytes: TBytes): Boolean;
function Utf8Text(const ABytes: TBytes): string;

implementation

uses
  System.Hash, System.NetEncoding;

const
  TEST_MASK: array[0..3] of Byte = ($11, $22, $33, $44);

{ ---- Handshake ----------------------------------------------------------- }

function ComputeAcceptKey(const AKey: string): string;
var
  Digest: TBytes;
begin
  Digest := THashSHA1.GetHashBytes(AKey + WS_GUID);
  Result := TNetEncoding.Base64.EncodeBytesToString(Digest);
end;

function IsValidHandshakeKey(const AKey: string): Boolean;
var
  I: Integer;
  Raw: TBytes;
begin
  Result := False;
  { 16 bytes em Base64 = 22 caracteres + "==". }
  if Length(AKey) <> 24 then
    Exit;
  if (AKey[23] <> '=') or (AKey[24] <> '=') then
    Exit;
  for I := 1 to 22 do
    if not CharInSet(AKey[I], ['A'..'Z', 'a'..'z', '0'..'9', '+', '/']) then
      Exit;
  try
    Raw := TNetEncoding.Base64.DecodeStringToBytes(AKey);
  except
    Exit;
  end;
  Result := Length(Raw) = 16;
end;

function HeaderHasToken(const AValue, AToken: string): Boolean;
var
  Parts: TArray<string>;
  Part: string;
begin
  Result := False;
  Parts := AValue.Split([',']);
  for Part in Parts do
    if SameText(Trim(Part), AToken) then
      Exit(True);
end;

{ ---- Codificacao ---------------------------------------------------------- }

function EncodeHeader(AFirst: Byte; ALength: Int64; AMasked: Boolean): TBytes;
var
  MaskBit: Byte;
  I: Integer;
begin
  if AMasked then
    MaskBit := $80
  else
    MaskBit := 0;
  if ALength < 126 then
  begin
    SetLength(Result, 2);
    Result[0] := AFirst;
    Result[1] := MaskBit or Byte(ALength);
  end
  else if ALength <= $FFFF then
  begin
    SetLength(Result, 4);
    Result[0] := AFirst;
    Result[1] := MaskBit or 126;
    Result[2] := Byte(ALength shr 8);
    Result[3] := Byte(ALength);
  end
  else
  begin
    SetLength(Result, 10);
    Result[0] := AFirst;
    Result[1] := MaskBit or 127;
    for I := 0 to 7 do
      Result[2 + I] := Byte(ALength shr (8 * (7 - I)));
  end;
end;

function Concat2(const A, B: TBytes): TBytes;
begin
  SetLength(Result, Length(A) + Length(B));
  if Length(A) > 0 then
    Move(A[0], Result[0], Length(A));
  if Length(B) > 0 then
    Move(B[0], Result[Length(A)], Length(B));
end;

function EncodeFrame(AOpcode: Byte; const APayload: TBytes): TBytes;
begin
  Result := Concat2(EncodeHeader($80 or AOpcode, Length(APayload), False), APayload);
end;

function EncodeMaskedFrame(AOpcode: Byte; const APayload: TBytes; AFin: Boolean): TBytes;
var
  First: Byte;
  Header, Body: TBytes;
  I: Integer;
begin
  First := AOpcode;
  if AFin then
    First := First or $80;
  Header := EncodeHeader(First, Length(APayload), True);
  SetLength(Body, 4 + Length(APayload));
  for I := 0 to 3 do
    Body[I] := TEST_MASK[I];
  for I := 0 to Length(APayload) - 1 do
    Body[4 + I] := APayload[I] xor TEST_MASK[I and 3];
  Result := Concat2(Header, Body);
end;

function EncodeText(const AText: string): TBytes;
begin
  Result := EncodeFrame(OP_TEXT, TEncoding.UTF8.GetBytes(AText));
end;

function EncodeClose(ACode: Word; const AReason: string): TBytes;
var
  Payload, Reason: TBytes;
begin
  Reason := TEncoding.UTF8.GetBytes(AReason);
  SetLength(Payload, 2 + Length(Reason));
  Payload[0] := Byte(ACode shr 8);
  Payload[1] := Byte(ACode);
  if Length(Reason) > 0 then
    Move(Reason[0], Payload[2], Length(Reason));
  Result := EncodeFrame(OP_CLOSE, Payload);
end;

function ParseClosePayload(const APayload: TBytes; out ACode: Word; out AReason: string): Boolean;
begin
  AReason := '';
  if Length(APayload) = 0 then
  begin
    ACode := CLOSE_NO_STATUS;
    Exit(True);
  end;
  ACode := 0;
  if Length(APayload) = 1 then
    Exit(False);
  ACode := (Word(APayload[0]) shl 8) or APayload[1];
  if Length(APayload) > 2 then
  begin
    if not IsValidUtf8(Copy(APayload, 2, MaxInt)) then
      Exit(False);
    AReason := TEncoding.UTF8.GetString(APayload, 2, Length(APayload) - 2);
  end;
  Result := True;
end;

{ ---- UTF-8 ---------------------------------------------------------------- }

function IsValidUtf8(const ABytes: TBytes): Boolean;
var
  I, J, Count, Need: Integer;
  Lead: Byte;
  CodePoint, MinCodePoint: Cardinal;
begin
  I := 0;
  Count := Length(ABytes);
  while I < Count do
  begin
    Lead := ABytes[I];
    if Lead < $80 then
    begin
      Inc(I);
      Continue;
    end;
    if (Lead and $E0) = $C0 then
    begin
      Need := 1;
      CodePoint := Lead and $1F;
      MinCodePoint := $80;
    end
    else if (Lead and $F0) = $E0 then
    begin
      Need := 2;
      CodePoint := Lead and $0F;
      MinCodePoint := $800;
    end
    else if (Lead and $F8) = $F0 then
    begin
      Need := 3;
      CodePoint := Lead and $07;
      MinCodePoint := $10000;
    end
    else
      Exit(False);

    if I + Need >= Count then
      Exit(False);
    for J := 1 to Need do
    begin
      if (ABytes[I + J] and $C0) <> $80 then
        Exit(False);
      CodePoint := (CodePoint shl 6) or Cardinal(ABytes[I + J] and $3F);
    end;
    if (CodePoint < MinCodePoint) or (CodePoint > $10FFFF) or
       ((CodePoint >= $D800) and (CodePoint <= $DFFF)) then
      Exit(False);
    Inc(I, Need + 1);
  end;
  Result := True;
end;

function Utf8Text(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := TEncoding.UTF8.GetString(ABytes);
end;

{ ---- TWsDecoder ----------------------------------------------------------- }

procedure TWsDecoder.Append(const AData: TBytes);
begin
  if Length(AData) = 0 then
    Exit;
  if FCount + Length(AData) > Length(FBuffer) then
    SetLength(FBuffer, (FCount + Length(AData)) * 2);
  Move(AData[0], FBuffer[FCount], Length(AData));
  Inc(FCount, Length(AData));
end;

function TWsDecoder.Next(out AFrame: TWsFrame; out ACloseCode: Word): TWsDecodeStatus;
var
  B0, B1: Byte;
  Len: Int64;
  HeaderLen, Total, I: Integer;
  Mask: array[0..3] of Byte;
begin
  ACloseCode := 0;
  AFrame.Fin := False;
  AFrame.Opcode := 0;
  AFrame.Payload := nil;
  if FCount < 2 then
    Exit(dsNeedMore);

  B0 := FBuffer[0];
  B1 := FBuffer[1];
  { Bits RSV1-3: nenhuma extensao foi negociada. }
  if (B0 and $70) <> 0 then
  begin
    ACloseCode := CLOSE_PROTOCOL_ERROR;
    Exit(dsError);
  end;
  AFrame.Fin := (B0 and $80) <> 0;
  AFrame.Opcode := B0 and $0F;
  if not (AFrame.Opcode in [OP_CONTINUATION, OP_TEXT, OP_BINARY, OP_CLOSE, OP_PING, OP_PONG]) then
  begin
    ACloseCode := CLOSE_PROTOCOL_ERROR;
    Exit(dsError);
  end;
  { Quadros do cliente precisam de mascara (RFC 6455, 5.1). }
  if (B1 and $80) = 0 then
  begin
    ACloseCode := CLOSE_PROTOCOL_ERROR;
    Exit(dsError);
  end;

  Len := B1 and $7F;
  HeaderLen := 2;
  if Len = 126 then
  begin
    if FCount < 4 then
      Exit(dsNeedMore);
    Len := (Int64(FBuffer[2]) shl 8) or FBuffer[3];
    HeaderLen := 4;
  end
  else if Len = 127 then
  begin
    if FCount < 10 then
      Exit(dsNeedMore);
    if (FBuffer[2] and $80) <> 0 then
    begin
      ACloseCode := CLOSE_PROTOCOL_ERROR;
      Exit(dsError);
    end;
    Len := 0;
    for I := 2 to 9 do
      Len := (Len shl 8) or FBuffer[I];
    HeaderLen := 10;
  end;

  if AFrame.Opcode >= $8 then
  begin
    if (Len > MAX_CONTROL_SIZE) or not AFrame.Fin then
    begin
      ACloseCode := CLOSE_PROTOCOL_ERROR;
      Exit(dsError);
    end;
  end
  else if Len > MAX_MESSAGE_SIZE then
  begin
    { Recusado pelo cabecalho, antes de receber o conteudo. }
    ACloseCode := CLOSE_TOO_BIG;
    Exit(dsError);
  end;

  Inc(HeaderLen, 4);
  Total := HeaderLen + Integer(Len);
  if FCount < Total then
    Exit(dsNeedMore);

  for I := 0 to 3 do
    Mask[I] := FBuffer[HeaderLen - 4 + I];
  SetLength(AFrame.Payload, Integer(Len));
  for I := 0 to Integer(Len) - 1 do
    AFrame.Payload[I] := FBuffer[HeaderLen + I] xor Mask[I and 3];

  if FCount > Total then
    Move(FBuffer[Total], FBuffer[0], FCount - Total);
  FCount := FCount - Total;
  Result := dsFrame;
end;

{ ---- TWsAssembler --------------------------------------------------------- }

function TWsAssembler.Finish(AOpcode: Byte; const AData: TBytes; out APayload: TBytes;
  out ACloseCode: Word): TWsEvent;
begin
  APayload := AData;
  ACloseCode := 0;
  if AOpcode = OP_TEXT then
  begin
    if not IsValidUtf8(AData) then
    begin
      ACloseCode := CLOSE_INVALID_DATA;
      Exit(weError);
    end;
    Exit(weText);
  end;
  Result := weBinary;
end;

function TWsAssembler.Feed(const AFrame: TWsFrame; out APayload: TBytes; out ACloseCode: Word): TWsEvent;
var
  Old: Integer;
begin
  APayload := nil;
  ACloseCode := 0;
  case AFrame.Opcode of
    OP_PING:
      begin
        APayload := AFrame.Payload;
        Result := wePing;
      end;
    OP_PONG:
      begin
        APayload := AFrame.Payload;
        Result := wePong;
      end;
    OP_CLOSE:
      begin
        APayload := AFrame.Payload;
        Result := weClose;
      end;
    OP_TEXT, OP_BINARY:
      begin
        if FInMessage then
        begin
          ACloseCode := CLOSE_PROTOCOL_ERROR;
          Exit(weError);
        end;
        if AFrame.Fin then
          Exit(Finish(AFrame.Opcode, AFrame.Payload, APayload, ACloseCode));
        FInMessage := True;
        FOpcode := AFrame.Opcode;
        FData := Copy(AFrame.Payload);
        Result := weNone;
      end;
    OP_CONTINUATION:
      begin
        if not FInMessage then
        begin
          ACloseCode := CLOSE_PROTOCOL_ERROR;
          Exit(weError);
        end;
        if Length(FData) + Length(AFrame.Payload) > MAX_MESSAGE_SIZE then
        begin
          ACloseCode := CLOSE_TOO_BIG;
          Exit(weError);
        end;
        Old := Length(FData);
        SetLength(FData, Old + Length(AFrame.Payload));
        if Length(AFrame.Payload) > 0 then
          Move(AFrame.Payload[0], FData[Old], Length(AFrame.Payload));
        if not AFrame.Fin then
          Exit(weNone);
        FInMessage := False;
        Result := Finish(FOpcode, FData, APayload, ACloseCode);
        FData := nil;
      end;
  else
    ACloseCode := CLOSE_PROTOCOL_ERROR;
    Result := weError;
  end;
end;

end.
