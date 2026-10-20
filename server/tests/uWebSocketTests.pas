unit uWebSocketTests;

{ Casos WS-01 a WS-07 do docs/test-plan-online.md (secao 5): protocolo
  WebSocket (uWebSocket) e politica de origem (uOriginPolicy), sem rede.
  As chaves de aceite esperadas foram conferidas por script (Python,
  hashlib + base64) antes de escrever os testes. }

interface

procedure RunWebSocketTests;

implementation

uses
  System.SysUtils, uMiniTest, uWebSocket, uOriginPolicy, uServerOptions;

const
  RFC_KEY = 'dGhlIHNhbXBsZSBub25jZQ==';
  RFC_ACCEPT = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=';

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

function Join(const A, B: TBytes): TBytes;
begin
  SetLength(Result, Length(A) + Length(B));
  if Length(A) > 0 then
    Move(A[0], Result[0], Length(A));
  if Length(B) > 0 then
    Move(B[0], Result[Length(A)], Length(B));
end;

function Filled(ACount: Integer; AValue: Byte): TBytes;
begin
  SetLength(Result, ACount);
  if ACount > 0 then
    FillChar(Result[0], ACount, AValue);
end;

function HexOf(const ABytes: TBytes): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ABytes) do
    Result := Result + IntToHex(ABytes[I], 2);
end;

{ Decodifica um unico quadro de ABytes. }
function DecodeOne(const ABytes: TBytes; out AFrame: TWsFrame; out ACode: Word): TWsDecodeStatus;
var
  D: TWsDecoder;
begin
  D := TWsDecoder.Create;
  try
    D.Append(ABytes);
    Result := D.Next(AFrame, ACode);
  finally
    D.Free;
  end;
end;

{ ---- WS-01 ---------------------------------------------------------------- }

procedure WS01_AcceptKey;
begin
  CheckEqualsStr(RFC_ACCEPT, ComputeAcceptKey(RFC_KEY), 'exemplo da RFC 6455');
  CheckEqualsStr('C/0nmHhBztSRGR1CwL6Tf4ZjwpY=', ComputeAcceptKey('AQIDBAUGBwgJCgsMDQ4PEA=='), 'chave 01..10');
  CheckEqualsStr('HSmrc0sMlYUkAGmm5OPpG2HaGWk=', ComputeAcceptKey('x3JJHMbDL1EzLkh9GBhXDw=='), 'chave aleatoria');
end;

{ ---- WS-02 ---------------------------------------------------------------- }

procedure WS02_Opening;
var
  O: TWsOpening;
begin
  O := EvaluateOpening('GET', 'websocket', 'Upgrade', RFC_KEY, '13', True);
  CheckEqualsInt(101, O.Status, 'pedido valido');
  CheckEqualsStr(RFC_ACCEPT, O.AcceptKey, 'chave de aceite');

  O := EvaluateOpening('GET', 'WebSocket', 'keep-alive, Upgrade', RFC_KEY, '13', True);
  CheckEqualsInt(101, O.Status, 'Connection: keep-alive, Upgrade e Upgrade com maiusculas');

  O := EvaluateOpening('POST', 'websocket', 'Upgrade', RFC_KEY, '13', True);
  CheckEqualsInt(405, O.Status, 'POST');
  CheckEqualsStr('Allow', O.HeaderName, 'POST: cabecalho');
  CheckEqualsStr('GET', O.HeaderValue, 'POST: Allow');
  CheckEqualsStr('METODO_NAO_PERMITIDO', O.ErrorCode, 'POST: codigo');

  O := EvaluateOpening('GET', '', 'Upgrade', RFC_KEY, '13', True);
  CheckEqualsInt(400, O.Status, 'sem Upgrade');
  CheckEqualsStr('HANDSHAKE_INVALIDO', O.ErrorCode, 'sem Upgrade: codigo');
  CheckEqualsInt(400, EvaluateOpening('GET', 'websocket', 'keep-alive', RFC_KEY, '13', True).Status, 'Connection sem Upgrade');
  CheckEqualsInt(400, EvaluateOpening('GET', 'websocket', 'Upgrade', 'AAAAAAAAAAAAAAAAAAAA', '13', True).Status, 'chave com 15 bytes');
  CheckEqualsInt(400, EvaluateOpening('GET', 'websocket', 'Upgrade', '', '13', True).Status, 'sem chave');
  CheckEqualsInt(400, EvaluateOpening('GET', '', '', '', '', True).Status, 'GET /ws comum (navegador)');

  O := EvaluateOpening('GET', 'websocket', 'Upgrade', RFC_KEY, '8', True);
  CheckEqualsInt(426, O.Status, 'versao 8');
  CheckEqualsStr('Sec-WebSocket-Version', O.HeaderName, 'versao 8: cabecalho');
  CheckEqualsStr('13', O.HeaderValue, 'versao 8: valor');
  CheckEqualsStr('VERSAO_WEBSOCKET', O.ErrorCode, 'versao 8: codigo');

  O := EvaluateOpening('GET', 'websocket', 'Upgrade', RFC_KEY, '13', False);
  CheckEqualsInt(403, O.Status, 'origem recusada pela politica');
  CheckEqualsStr('ORIGEM_NAO_PERMITIDA', O.ErrorCode, 'origem: codigo');
  { Ordem da 7.1: metodo antes de origem; versao antes de origem. }
  CheckEqualsInt(405, EvaluateOpening('POST', '', '', '', '', False).Status, 'metodo vem antes de tudo');
  CheckEqualsInt(426, EvaluateOpening('GET', 'websocket', 'Upgrade', RFC_KEY, '8', False).Status, 'versao antes de origem');
end;

{ ---- WS-03 ---------------------------------------------------------------- }

procedure WS03_Decode;
var
  F: TWsFrame;
  Code: Word;
  D: TWsDecoder;
  Raw: TBytes;
  I: Integer;
  Status: TWsDecodeStatus;
begin
  Check(DecodeOne(EncodeMaskedFrame(OP_TEXT, Bytes('Hello'), True), F, Code) = dsFrame, 'texto de 5 bytes');
  CheckEqualsStr('Hello', Utf8Text(F.Payload), 'texto de 5 bytes: conteudo');
  Check(F.Fin and (F.Opcode = OP_TEXT), 'texto de 5 bytes: FIN e opcode');
  { Exemplo "Hello" mascarado da RFC 6455, 5.7. }
  Raw := TBytes.Create($81, $85, $37, $FA, $21, $3D, $7F, $9F, $4D, $51, $58);
  Check(DecodeOne(Raw, F, Code) = dsFrame, 'exemplo mascarado da RFC');
  CheckEqualsStr('Hello', Utf8Text(F.Payload), 'exemplo da RFC: conteudo');

  Check(DecodeOne(EncodeMaskedFrame(OP_TEXT, Filled(126, Ord('a')), True), F, Code) = dsFrame, '126 bytes (16 bits)');
  CheckEqualsInt(126, Length(F.Payload), '126 bytes: tamanho');

  Check(DecodeOne(EncodeMaskedFrame(OP_TEXT, Filled(70000, Ord('a')), True), F, Code) = dsError, '70.000 bytes (64 bits)');
  CheckEqualsInt(CLOSE_TOO_BIG, Code, '70.000 bytes: 1009 pelo cabecalho');

  { Entrega em pedacos de 1 byte. }
  Raw := EncodeMaskedFrame(OP_TEXT, Bytes('pedaços'), True);
  D := TWsDecoder.Create;
  try
    Status := dsNeedMore;
    for I := 0 to High(Raw) do
    begin
      D.Append(TBytes.Create(Raw[I]));
      Status := D.Next(F, Code);
      if (I < High(Raw)) and (Status <> dsNeedMore) then
        Check(False, Format('byte %d: deveria pedir mais bytes', [I]));
    end;
    Check(Status = dsFrame, '1 byte por vez: quadro completo no ultimo byte');
    CheckEqualsStr('pedaços', Utf8Text(F.Payload), '1 byte por vez: conteudo');
  finally
    D.Free;
  end;

  Check(DecodeOne(EncodeFrame(OP_TEXT, Bytes('sem mascara')), F, Code) = dsError, 'sem mascara');
  CheckEqualsInt(CLOSE_PROTOCOL_ERROR, Code, 'sem mascara: 1002');
  Check(DecodeOne(EncodeMaskedFrame(3, Bytes('x'), True), F, Code) = dsError, 'opcode 3');
  CheckEqualsInt(CLOSE_PROTOCOL_ERROR, Code, 'opcode 3: 1002');
  Raw := EncodeMaskedFrame(OP_TEXT, Bytes('x'), True);
  Raw[0] := Raw[0] or $40;
  Check(DecodeOne(Raw, F, Code) = dsError, 'RSV1');
  CheckEqualsInt(CLOSE_PROTOCOL_ERROR, Code, 'RSV1: 1002');
end;

{ ---- WS-04 ---------------------------------------------------------------- }

procedure WS04_Fragments;
var
  D: TWsDecoder;
  A: TWsAssembler;
  F: TWsFrame;
  Code: Word;
  Payload: TBytes;
  Events: string;
  Text: string;
  Ev: TWsEvent;
begin
  D := TWsDecoder.Create;
  A := TWsAssembler.Create;
  try
    D.Append(EncodeMaskedFrame(OP_TEXT, Bytes('um '), False));
    D.Append(EncodeMaskedFrame(OP_CONTINUATION, Bytes('dois '), False));
    D.Append(EncodeMaskedFrame(OP_PING, Bytes('p'), True));
    D.Append(EncodeMaskedFrame(OP_CONTINUATION, Bytes('três'), True));
    Events := '';
    Text := '';
    while D.Next(F, Code) = dsFrame do
    begin
      Ev := A.Feed(F, Payload, Code);
      case Ev of
        weNone: Events := Events + '-';
        weText: begin Events := Events + 'T'; Text := Utf8Text(Payload); end;
        wePing: Events := Events + 'P';
      else
        Events := Events + '?';
      end;
    end;
    CheckEqualsStr('--PT', Events, 'tres fragmentos com ping no meio: eventos');
    CheckEqualsStr('um dois três', Text, 'mensagem remontada');
  finally
    A.Free;
    D.Free;
  end;

  A := TWsAssembler.Create;
  try
    F.Fin := True; F.Opcode := OP_CONTINUATION; F.Payload := Bytes('x');
    Check(A.Feed(F, Payload, Code) = weError, 'continuacao sem inicio');
    CheckEqualsInt(CLOSE_PROTOCOL_ERROR, Code, 'continuacao sem inicio: 1002');
  finally
    A.Free;
  end;

  A := TWsAssembler.Create;
  try
    F.Fin := False; F.Opcode := OP_TEXT; F.Payload := Bytes('a');
    A.Feed(F, Payload, Code);
    F.Fin := True; F.Opcode := OP_TEXT; F.Payload := Bytes('b');
    Check(A.Feed(F, Payload, Code) = weError, 'novo inicio antes do fim');
    CheckEqualsInt(CLOSE_PROTOCOL_ERROR, Code, 'novo inicio antes do fim: 1002');
  finally
    A.Free;
  end;
end;

{ ---- WS-05 ---------------------------------------------------------------- }

procedure WS05_Limits;
var
  A: TWsAssembler;
  F: TWsFrame;
  Code: Word;
  Payload: TBytes;
begin
  A := TWsAssembler.Create;
  try
    F.Fin := False; F.Opcode := OP_TEXT; F.Payload := Filled(4000, Ord('a'));
    Check(A.Feed(F, Payload, Code) = weNone, 'primeiro fragmento de 4.000 bytes');
    F.Fin := True; F.Opcode := OP_CONTINUATION; F.Payload := Filled(97, Ord('a'));
    Check(A.Feed(F, Payload, Code) = weError, 'mensagem remontada de 4.097 bytes');
    CheckEqualsInt(CLOSE_TOO_BIG, Code, '4.097 bytes: 1009');
  finally
    A.Free;
  end;

  A := TWsAssembler.Create;
  try
    F.Fin := False; F.Opcode := OP_TEXT; F.Payload := Filled(4000, Ord('a'));
    A.Feed(F, Payload, Code);
    F.Fin := True; F.Opcode := OP_CONTINUATION; F.Payload := Filled(96, Ord('a'));
    Check(A.Feed(F, Payload, Code) = weText, 'mensagem remontada de 4.096 bytes e aceita');
  finally
    A.Free;
  end;

  Check(DecodeOne(EncodeMaskedFrame(OP_PING, Filled(126, 1), True), F, Code) = dsError, 'controle com 126 bytes');
  CheckEqualsInt(CLOSE_PROTOCOL_ERROR, Code, 'controle com 126 bytes: 1002');
  Check(DecodeOne(EncodeMaskedFrame(OP_TEXT, Filled(4097, Ord('a')), True), F, Code) = dsError, 'quadro unico de 4.097 bytes');
  CheckEqualsInt(CLOSE_TOO_BIG, Code, 'quadro unico de 4.097 bytes: 1009');

  A := TWsAssembler.Create;
  try
    F.Fin := True; F.Opcode := OP_TEXT; F.Payload := TBytes.Create($7B, $FF, $FE, $7D);
    Check(A.Feed(F, Payload, Code) = weError, 'UTF-8 invalido');
    CheckEqualsInt(CLOSE_INVALID_DATA, Code, 'UTF-8 invalido: 1007');
    F.Fin := True; F.Opcode := OP_BINARY; F.Payload := TBytes.Create(1, 2, 3);
    Check(A.Feed(F, Payload, Code) = weBinary, 'quadro binario reportado como weBinary');
  finally
    A.Free;
  end;
end;

{ ---- WS-06 ---------------------------------------------------------------- }

procedure WS06_Encode;
var
  B: TBytes;
  Code: Word;
  Reason: string;
begin
  B := EncodeText('Hello');
  CheckEqualsStr('810548656C6C6F', HexOf(B), 'texto curto, sem mascara, com FIN');
  B := EncodeFrame(OP_TEXT, Filled(200, Ord('a')));
  CheckEqualsStr('817E00C8', HexOf(Copy(B, 0, 4)), 'texto de 200 bytes: cabecalho de 16 bits');
  CheckEqualsInt(204, Length(B), 'texto de 200 bytes: tamanho');
  B := EncodeFrame(OP_TEXT, Filled(70000, Ord('a')));
  CheckEqualsStr('817F0000000000011170', HexOf(Copy(B, 0, 10)), 'texto de 70.000 bytes: cabecalho de 64 bits');
  B := EncodeClose(4410, 'Sala encerrada à força');
  CheckEqualsStr('88', HexOf(Copy(B, 0, 1)), 'close: opcode e FIN');
  Check(ParseClosePayload(Copy(B, 2, MaxInt), Code, Reason), 'close: carga valida');
  CheckEqualsInt(4410, Code, 'close: codigo');
  CheckEqualsStr('Sala encerrada à força', Reason, 'close: motivo acentuado');
  B := EncodeFrame(OP_PONG, Bytes('eco'));
  CheckEqualsStr('8A03' + HexOf(Bytes('eco')), HexOf(B), 'pong ecoa o conteudo do ping');
end;

{ ---- WS-07 ---------------------------------------------------------------- }

const
  TEST_IPS: array[0..4] of string = ('127.0.0.1', '192.168.0.10', '10.1.2.3', '8.8.8.8', '169.254.1.1');

function LocalPolicy(const AConfigured: array of string): TOriginPolicy;
begin
  Result := TOriginPolicy.Create(False, '0.0.0.0', 8765, AConfigured);
  Result.SetLocalAddresses(TEST_IPS);
end;

procedure ExpectOrigin(APolicy: TOriginPolicy; const AOrigins: array of string; AChannel, AExpected: Boolean;
  const AId: string);
begin
  Check(APolicy.Allowed(AOrigins, AChannel) = AExpected,
    Format('%s: esperado %s', [AId, BoolToStr(AExpected, True)]));
end;

procedure WS07_OriginPolicy;
var
  P: TOriginPolicy;
  O: TServerOptions;
  Err, Canonical: string;
  Ch: Boolean;
begin
  P := LocalPolicy([]);
  try
    CheckEqualsStr('http://127.0.0.1:8765, http://localhost:8765, http://192.168.0.10:8765, http://10.1.2.3:8765',
      P.AllowedText, 'lista automatica (sem 8.8.8.8 nem 169.254.1.1)');
    for Ch in [True, False] do
    begin
      ExpectOrigin(P, ['http://127.0.0.1:8765'], Ch, True, 'OG-01');
      ExpectOrigin(P, ['http://localhost:8765'], Ch, True, 'OG-02');
      ExpectOrigin(P, ['http://192.168.0.10:8765'], Ch, True, 'OG-03');
      ExpectOrigin(P, ['HTTP://192.168.0.10:8765'], Ch, True, 'OG-04');
      ExpectOrigin(P, ['http://192.168.0.20:8765'], Ch, False, 'OG-05');
      ExpectOrigin(P, ['http://192.168.0.10:9000'], Ch, False, 'OG-06');
      ExpectOrigin(P, ['http://192.168.0.10'], Ch, False, 'OG-07');
      ExpectOrigin(P, ['https://192.168.0.10:8765'], Ch, False, 'OG-08');
      ExpectOrigin(P, ['http://desktop-ruan:8765'], Ch, False, 'OG-09');
      ExpectOrigin(P, ['https://exemplo.com'], Ch, False, 'OG-10');
      ExpectOrigin(P, ['http://atacante.test:8765'], Ch, False, 'OG-11 (o Host nao entra na decisao)');
      ExpectOrigin(P, ['http://192.168.0.10:8765.atacante.test'], Ch, False, 'OG-12');
      ExpectOrigin(P, ['null'], Ch, False, 'OG-13');
      ExpectOrigin(P, ['http://192.168.0.10:8765/'], Ch, False, 'OG-14 barra');
      ExpectOrigin(P, ['http://192.168.0.10:8765/x'], Ch, False, 'OG-14 caminho');
      ExpectOrigin(P, ['http://127.0.0.1:8765', 'http://127.0.0.1:8765'], Ch, False, 'OG-15');
      ExpectOrigin(P, ['http://[::1]:8765'], Ch, False, 'OG-16');
      ExpectOrigin(P, ['http://192.168.000.010:8765'], Ch, False, 'OG-17');
      ExpectOrigin(P, [], Ch, True, 'OG-18');
      ExpectOrigin(P, ['http://8.8.8.8:8765'], Ch, False, 'OG-19');
      ExpectOrigin(P, ['http://169.254.1.1:8765'], Ch, False, 'link-local');
      ExpectOrigin(P, ['http://10.1.2.3:8765'], Ch, True, 'outro IP privado da maquina');
      ExpectOrigin(P, ['http://user@127.0.0.1:8765'], Ch, False, 'com usuario');
      ExpectOrigin(P, ['http://127.0.0.1:8765?x=1'], Ch, False, 'com consulta');
      ExpectOrigin(P, ['http://127.0.0.1:8765#x'], Ch, False, 'com fragmento');
      ExpectOrigin(P, [''], Ch, False, 'Origin vazio');
      ExpectOrigin(P, ['http://127.0.0.1:08765'], Ch, False, 'porta com zero a esquerda');
      ExpectOrigin(P, ['ws://127.0.0.1:8765'], Ch, False, 'esquema ws');
      ExpectOrigin(P, ['http://LOCALHOST:8765'], Ch, True, 'host em maiusculas');
    end;
  finally
    P.Free;
  end;

  P := LocalPolicy(['http://desktop-ruan:8765', 'http://8.8.8.8:8765']);
  try
    ExpectOrigin(P, ['http://desktop-ruan:8765'], True, True, 'OG-09 com --allowed-origin');
    ExpectOrigin(P, ['http://8.8.8.8:8765'], True, True, 'OG-19 com --allowed-origin');
  finally
    P.Free;
  end;

  { Bind especifico gera so esse IP; bind 127.0.0.1 so o loopback. }
  P := TOriginPolicy.Create(False, '192.168.0.10', 8765, []);
  try
    P.SetLocalAddresses(TEST_IPS);
    CheckEqualsStr('http://192.168.0.10:8765', P.AllowedText, 'bind 192.168.0.10');
  finally
    P.Free;
  end;
  P := TOriginPolicy.Create(False, '127.0.0.1', 8765, []);
  try
    P.SetLocalAddresses(TEST_IPS);
    CheckEqualsStr('http://127.0.0.1:8765, http://localhost:8765', P.AllowedText, 'bind 127.0.0.1');
  finally
    P.Free;
  end;

  { Mudanca de IP (DHCP): SetLocalAddresses avisa quando a lista muda. }
  P := LocalPolicy([]);
  try
    Check(not P.SetLocalAddresses(TEST_IPS), 'mesmos IPs: lista inalterada');
    Check(P.SetLocalAddresses(['127.0.0.1', '192.168.0.11']), 'IP novo: lista alterada');
    ExpectOrigin(P, ['http://192.168.0.11:8765'], True, True, 'novo IP aceito');
    ExpectOrigin(P, ['http://192.168.0.10:8765'], True, False, 'IP antigo recusado');
  finally
    P.Free;
  end;

  { Modo publico. }
  P := TOriginPolicy.Create(True, '127.0.0.1', 8765, ['https://jogo.exemplo.com.br:443']);
  try
    P.SetLocalAddresses(TEST_IPS);
    CheckEqualsStr('https://jogo.exemplo.com.br:443', P.AllowedText, 'publico: so as configuradas');
    ExpectOrigin(P, ['https://jogo.exemplo.com.br'], True, True, 'publico: https sem porta');
    ExpectOrigin(P, ['https://jogo.exemplo.com.br:443'], True, True, 'publico: https:443');
    ExpectOrigin(P, ['http://jogo.exemplo.com.br'], True, False, 'publico: http');
    ExpectOrigin(P, ['https://www.jogo.exemplo.com.br'], True, False, 'publico: subdominio');
    ExpectOrigin(P, ['http://127.0.0.1:8765'], True, False, 'publico: loopback');
    ExpectOrigin(P, [], True, False, 'publico: canal sem Origin');
    ExpectOrigin(P, [], False, True, 'publico: POST sem Origin');
  finally
    P.Free;
  end;

  { Normalizacao e validacao de --allowed-origin. }
  Check(NormalizeOrigin('HTTPS://Jogo.Test', Canonical) and (Canonical = 'https://jogo.test:443'), 'normalizacao');
  Check(IsPrivateIPv4('172.16.0.1') and IsPrivateIPv4('172.31.255.255') and not IsPrivateIPv4('172.32.0.1'),
    'faixa 172.16.0.0/12');
  Check(not ParseServerOptions(['--allowed-origin', 'http://jogo.test/x'], 'w', O, Err), '--allowed-origin com caminho');
  Check(not ParseServerOptions(['--allowed-origin', 'jogo.test:8765'], 'w', O, Err), '--allowed-origin sem esquema');
  Check(not ParseServerOptions(['--allowed-origin', 'ftp://jogo.test'], 'w', O, Err), '--allowed-origin ftp');
  Check(not ParseServerOptions(['--allowed-origin', 'http://jogo.test:0'], 'w', O, Err), '--allowed-origin porta 0');
  Check(ParseServerOptions(['--public', '--allowed-origin', 'http://jogo.test'], 'w', O, Err) and
    not ValidateServerOptions(O, Err), '--public com http: recusado pela validacao');
  Check(ParseServerOptions(['--public', '--allowed-origin', 'https://jogo.test'], 'w', O, Err) and
    ValidateServerOptions(O, Err), '--public com https: ' + Err);
  Check(OriginForLog('http://x'#10'y' + StringOfChar('a', 200)).Length = 100, 'origem no log: 100 caracteres');
  Check(Pos(#10, OriginForLog('a'#10'b')) = 0, 'origem no log: so imprimiveis');
end;

procedure RunWebSocketTests;
begin
  RunCase('WS-01', 'Chave de aceite (exemplo da RFC 6455 e mais duas)', WS01_AcceptKey);
  RunCase('WS-02', 'Abertura: valida, sem Upgrade, chave curta, versao 8, metodo, origem', WS02_Opening);
  RunCase('WS-03', 'Quadros com mascara: 7, 16 e 64 bits, 1 byte por vez, erros 1002/1009', WS03_Decode);
  RunCase('WS-04', 'Fragmentacao com ping no meio e continuacoes invalidas', WS04_Fragments);
  RunCase('WS-05', 'Limites: 4.096/4.097 bytes, controle de 126 bytes, UTF-8 invalido', WS05_Limits);
  RunCase('WS-06', 'Codificacao: texto nos tres tamanhos, close acentuado, pong', WS06_Encode);
  RunCase('WS-07', 'Politica de origem: OG-01 a OG-19, binds, modo publico, --allowed-origin', WS07_OriginPolicy);
end;

end.
