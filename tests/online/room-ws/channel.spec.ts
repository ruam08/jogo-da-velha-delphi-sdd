import { test, expect } from '../../support/online/fixtures';
import { ONLINE_MESSAGES, Room } from '../../support/online/rooms';
import { RFC_ACCEPT, RFC_KEY, ServerMessage } from '../../support/online/ws-client';

/*
 * Grupo OW: protocolo do canal em tempo real contra o servidor real
 * (docs/plan-online.md, seção 7). Sem navegador: WebSocket nativo do Node e
 * socket cru. O token só vai na mensagem "entrar", nunca na URL.
 */

function errorBody(code: keyof typeof ONLINE_MESSAGES) {
  return { erro: { codigo: code, mensagem: ONLINE_MESSAGES[code] } };
}

test('OW-01 [CAO-45] abertura válida por socket cru com a chave da RFC 6455', async ({ ws }) => {
  const raw = await ws.raw({ key: RFC_KEY });
  expect(raw.statusLine).toBe('HTTP/1.1 101 Switching Protocols');
  expect(raw.headers['upgrade']).toBe('websocket');
  expect(raw.headers['connection']).toBe('Upgrade');
  expect(raw.headers['sec-websocket-accept']).toBe(RFC_ACCEPT);
  expect(raw.headers['content-length'], 'sem Content-Length').toBeUndefined();
  expect(raw.headers['sec-websocket-protocol'], 'sem subprotocolo').toBeUndefined();
  expect(raw.headers['sec-websocket-extensions'], 'sem extensões').toBeUndefined();
  expect(raw.rawHeaders.split('\r\n'), 'exatamente 4 linhas de cabeçalho').toHaveLength(4);
  // Nada além dos cabeçalhos: o servidor espera o "entrar".
  await new Promise((r) => setTimeout(r, 300));
  expect(raw.frames, 'nenhum quadro antes do entrar').toEqual([]);
  expect(raw.body.length, 'nenhum corpo HTTP depois dos cabeçalhos').toBe(0);
  raw.sendFrame(0x8, Buffer.from([0x03, 0xe8]));
  expect(await raw.waitClose()).toBe(1000);
});

test('OW-02 [CAO-45] aberturas inválidas: 400, 426, 405 e GET comum', async ({ ws, request }) => {
  const noUpgrade = await ws.raw({ upgrade: null });
  await noUpgrade.waitEnd();
  expect(noUpgrade.status, 'sem Upgrade').toBe(400);
  expect(JSON.parse(noUpgrade.bodyText())).toEqual(errorBody('HANDSHAKE_INVALIDO'));

  const shortKey = await ws.raw({ key: 'abc' });
  await shortKey.waitEnd();
  expect(shortKey.status, 'chave curta').toBe(400);
  expect(JSON.parse(shortKey.bodyText())).toEqual(errorBody('HANDSHAKE_INVALIDO'));

  const v8 = await ws.raw({ version: '8' });
  await v8.waitEnd();
  expect(v8.status, 'versão 8').toBe(426);
  expect(v8.headers['sec-websocket-version']).toBe('13');
  expect(JSON.parse(v8.bodyText())).toEqual(errorBody('VERSAO_WEBSOCKET'));

  const post = await request.post('/ws', { data: '' });
  expect(post.status(), 'POST /ws').toBe(405);
  expect(post.headers()['allow']).toBe('GET');
  expect(await post.json()).toEqual(errorBody('METODO_NAO_PERMITIDO'));

  const plain = await request.get('/ws');
  expect(plain.status(), 'GET /ws comum (navegador)').toBe(400);
  expect(plain.headers()['content-type']).toBe('application/json; charset=utf-8');
  expect(await plain.json()).toEqual(errorBody('HANDSHAKE_INVALIDO'));
});

test('OW-03 [CAO-15] entrar: bem_vindo é a primeira mensagem, com o lugar do token e a sala atual', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const client = await ws.open();
  client.enter(pair.code, pair.tx);
  const first = await client.next();
  expect(first.tipo, 'primeira mensagem').toBe('bem_vindo');
  expect(first.protocolo).toBe(1);
  expect(first.voce).toBe('X');
  expect(first.intervaloPingMs, 'um terço de --ws-idle-seconds (60 s)').toBe(20000);
  expect(first.sala, 'sala do bem_vindo = GET logo depois').toEqual(await rooms.room(pair.code));
  expect(first.sala!.jogadores.X.conectado, 'X conectado').toBe(true);
  expect(JSON.stringify(first), 'o bem_vindo não contém tokens').not.toContain(pair.tx);
  expect(JSON.stringify(first)).not.toContain(pair.to);

  // O lugar sai do token: um campo "voce" no entrar não muda nada.
  const other = await ws.open();
  other.send({ tipo: 'entrar', protocolo: 1, sala: pair.code.toLowerCase(), token: pair.to, voce: 'X' });
  const welcomeO = await other.next();
  expect(welcomeO.tipo).toBe('bem_vindo');
  expect(welcomeO.voce, 'token de O entra como O').toBe('O');
});

test('OW-08 [CAO-20, CAO-30, CAO-31] entrar com token inválido, de outra sala, sala inexistente ou encerrada', async ({ rooms, ws }) => {
  const s1 = await rooms.pair();
  const s2 = await rooms.pair();
  const closed = await rooms.pair();
  expect((await rooms.leave(closed.code, closed.to)).status()).toBe(200);

  const cases: Array<[string, string, string, keyof typeof ONLINE_MESSAGES, number]> = [
    ['token inexistente', s1.code, '0123456789abcdef0123456789abcdef', 'TOKEN_INVALIDO', 4401],
    ['token de X da sala S2', s1.code, s2.tx, 'TOKEN_INVALIDO', 4401],
    ['token vazio', s1.code, '', 'TOKEN_INVALIDO', 4401],
    ['token em maiúsculas', s1.code, s1.tx.toUpperCase(), 'TOKEN_INVALIDO', 4401],
    ['código inexistente', 'ZZZZZY', s1.tx, 'SALA_INEXISTENTE', 4404],
    ['código malformado', 'abc', s1.tx, 'SALA_INEXISTENTE', 4404],
    ['sala encerrada', closed.code, closed.tx, 'SALA_ENCERRADA', 4410],
  ];
  for (const [label, code, token, error, closeCode] of cases) {
    const before = await rooms.snapshotText(s1.code);
    const client = await ws.open();
    client.enter(code, token);
    const msg = await client.next();
    expect(msg, label).toEqual({ tipo: 'erro', codigo: error, mensagem: ONLINE_MESSAGES[error] });
    const info = await client.waitClosed();
    expect(info.code, `${label}: código de fechamento`).toBe(closeCode);
    expect(await rooms.snapshotText(s1.code), `${label}: S1 inalterada`).toBe(before);
  }
});

test('OW-09 [CAO-28] mensagens do cliente que não são entrar/ping: MENSAGEM_INVALIDA e 4400, partida inalterada', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const forged: Array<[string, (c: Awaited<ReturnType<typeof ws.open>>) => void]> = [
    ['jogada pelo canal', (c) => c.send({ tipo: 'jogada', posicao: 0 })],
    ['estado imposto pelo cliente', (c) => c.send({ tipo: 'estado', sala: { partida: { status: 'VITORIA', vencedor: 'X' } } })],
    ['texto que não é JSON', (c) => c.send('nao-json')],
    ['quadro binário', (c) => c.sendBinary(new Uint8Array([1, 2, 3]).buffer)],
    ['entrar repetido', (c) => c.enter(pair.code, pair.tx)],
  ];
  for (const [label, act] of forged) {
    const before = (await rooms.room(pair.code)).partida;
    const { client } = await ws.entered(pair.code, pair.tx);
    act(client);
    const msg = await client.next((m) => m.tipo === 'erro');
    expect(msg, label).toEqual({ tipo: 'erro', codigo: 'MENSAGEM_INVALIDA', mensagem: ONLINE_MESSAGES.MENSAGEM_INVALIDA });
    expect((await client.waitClosed()).code, `${label}: fechamento`).toBe(4400);
    expect((await rooms.room(pair.code)).partida, `${label}: partida inalterada`).toEqual(before);
  }
  // ping antes de entrar
  const early = await ws.open();
  early.send({ tipo: 'ping', id: 1 });
  expect(await early.next()).toEqual({ tipo: 'erro', codigo: 'MENSAGEM_INVALIDA', mensagem: ONLINE_MESSAGES.MENSAGEM_INVALIDA });
  expect((await early.waitClosed()).code, 'ping antes de entrar').toBe(4400);
  expect((await rooms.room(pair.code)).partida.tabuleiro.join(''), 'nenhuma jogada').toBe('');
});

test('OW-11 [CAO-33] ping devolve pong com o mesmo id e nenhuma outra mensagem', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const { client } = await ws.entered(pair.code, pair.tx);
  const start = client.count;
  client.send({ tipo: 'ping', id: 7 });
  expect(await client.next()).toEqual({ tipo: 'pong', id: 7 });
  client.send({ tipo: 'ping', id: 2147483647 });
  expect(await client.next()).toEqual({ tipo: 'pong', id: 2147483647 });
  const extra = await client.expectSilence(400);
  expect(extra, 'nenhuma outra mensagem').toEqual([]);
  expect(client.since(start).map((m: ServerMessage) => m.tipo)).toEqual(['pong', 'pong']);
});

test('OW-16 [CAO-52] limites: 4.097 bytes (1009), quadro sem máscara (1002), UTF-8 inválido (1007)', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const before: Room = await rooms.room(pair.code);

  const big = await ws.raw();
  big.sendText('x'.repeat(4097));
  expect(await big.waitClose(), 'mensagem de 4.097 bytes').toBe(1009);

  const okSize = await ws.raw();
  okSize.sendText(JSON.stringify({ tipo: 'ping', id: 1, x: 'y'.repeat(4000) }).slice(0, 4096));
  // 4.096 bytes passam pelo limite; o conteúdo é inválido (ping antes de entrar) -> 4400, não 1009.
  expect(await okSize.waitClose(), 'mensagem de 4.096 bytes não é recusada pelo tamanho').toBe(4400);

  const unmasked = await ws.raw();
  unmasked.sendFrame(0x1, '{"tipo":"ping","id":1}', { mask: false });
  expect(await unmasked.waitClose(), 'quadro sem máscara').toBe(1002);

  const badUtf8 = await ws.raw();
  badUtf8.sendFrame(0x1, Buffer.from([0x7b, 0xff, 0xfe, 0x7d]));
  expect(await badUtf8.waitClose(), 'UTF-8 inválido').toBe(1007);

  const after = await rooms.room(pair.code);
  expect(after, 'sala inalterada').toEqual(before);
});
