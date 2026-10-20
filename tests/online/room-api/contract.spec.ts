import { test, expect } from '../../support/online/fixtures';
import { portOf, rawHead } from '../../support/raw-http';
import { CODE_RE, PlayerInfo, ROOM_FIELDS, Room, TOKEN_RE, waitingRoom } from '../../support/online/rooms';

/* Grupo OA: contrato REST das salas (docs/plan-online.md 6.1 a 6.4). */

test('OA-01 [CAO-01] criar sala: 201, Location, cabeçalhos e corpo {sala, jogador}', async ({ rooms, request }) => {
  for (const [label, options] of [
    ['sem corpo', {}],
    ['com corpo {"x":1} (ignorado)', { data: '{"x":1}', headers: { 'Content-Type': 'application/json' } }],
  ] as const) {
    const res = await request.post('/api/rooms', options);
    const text = await res.text();
    expect(res.status(), `${label}: status (corpo: ${text})`).toBe(201);
    const body = JSON.parse(text) as { sala: Room; jogador: PlayerInfo };
    rooms.track(body.sala.codigo, body.jogador.token);

    expect(res.headers()['content-type'], `${label}: Content-Type`).toBe('application/json; charset=utf-8');
    expect(res.headers()['cache-control'], `${label}: Cache-Control`).toBe('no-store');
    expect(res.headers()['location'], `${label}: Location`).toBe(`/api/rooms/${body.sala.codigo}`);
    expect(Object.keys(body), `${label}: campos do corpo`).toEqual(['sala', 'jogador']);
    expect(Object.keys(body.sala), `${label}: campos e ordem de sala`).toEqual(ROOM_FIELDS);
    expect(body.sala.codigo, `${label}: código`).toMatch(CODE_RE);
    expect(body.sala, `${label}: sala`).toEqual(waitingRoom(body.sala.codigo));
    expect(Object.keys(body.jogador), `${label}: campos de jogador`).toEqual(['simbolo', 'token']);
    expect(body.jogador.simbolo, `${label}: símbolo`).toBe('X');
    expect(body.jogador.token, `${label}: token`).toMatch(TOKEN_RE);
  }
});

test('OA-02 [CAO-02] mil criações: mil códigos distintos, todos do alfabeto', async ({ rooms }) => {
  const codes = new Set<string>();
  for (let i = 0; i < 1000; i++) {
    // Sai em seguida: salas abertas contam no limite --max-rooms (500 por padrão).
    const created = await rooms.create(false);
    expect(created.code, `criação ${i + 1}`).toMatch(CODE_RE);
    codes.add(created.code);
    expect((await rooms.leave(created.code, created.token)).status(), `saída ${i + 1}`).toBe(200);
  }
  expect(codes.size, 'códigos distintos').toBe(1000);
});

test('OA-03 [CAO-45, CAO-54] consultar: GET e HEAD, aguardando e em jogo, sem tokens', async ({ rooms, baseURL }) => {
  const created = await rooms.create();
  const port = portOf(baseURL);

  const waiting = await rooms.get(created.code);
  const waitingText = await waiting.text();
  expect(waiting.status(), `GET aguardando: ${waitingText}`).toBe(200);
  expect(waiting.headers()['content-type']).toBe('application/json; charset=utf-8');
  expect(waiting.headers()['cache-control']).toBe('no-store');
  expect(JSON.parse(waitingText), 'GET aguardando = sala da criação').toEqual({ sala: created.room });
  expect(waitingText, 'GET não contém o token de X').not.toContain(created.token);

  const joined = await rooms.joinOk(created.code.toLowerCase());
  const playing = await rooms.get(created.code);
  const playingText = await playing.text();
  expect(playing.status()).toBe(200);
  expect(JSON.parse(playingText), 'GET em jogo = sala da entrada').toEqual({ sala: joined.room });
  expect(playingText, 'GET não contém o token de X').not.toContain(created.token);
  expect(playingText, 'GET não contém o token de O').not.toContain(joined.token);

  for (const code of [created.code, created.code.toLowerCase()]) {
    const head = await rawHead(port, `/api/rooms/${code}`);
    expect(head.statusLine, `HEAD ${code}`).toMatch(/^HTTP\/1\.1 200 /);
    expect(head.headers.toLowerCase(), `HEAD ${code}: Content-Type`).toContain('content-type: application/json; charset=utf-8');
    expect(head.bodyBytes, `HEAD ${code}: bytes de corpo`).toBe(0);
  }
});

test('OA-04 [CAO-04] entrar pelo código (minúsculo): 201, O, token novo, EM_JOGO, versão 2', async ({ rooms }) => {
  const created = await rooms.create();
  const res = await rooms.join(created.code.toLowerCase());
  const text = await res.text();
  expect(res.status(), text).toBe(201);
  expect(res.headers()['content-type']).toBe('application/json; charset=utf-8');
  expect(res.headers()['cache-control']).toBe('no-store');
  const body = JSON.parse(text) as { sala: Room; jogador: PlayerInfo };
  expect(Object.keys(body)).toEqual(['sala', 'jogador']);
  expect(body.jogador.simbolo).toBe('O');
  expect(body.jogador.token).toMatch(TOKEN_RE);
  expect(body.jogador.token, 'token de O diferente do de X').not.toBe(created.token);
  expect(body.sala).toEqual({
    ...waitingRoom(created.code),
    situacao: 'EM_JOGO',
    versao: 2,
    jogadores: { X: { ocupado: true, conectado: false }, O: { ocupado: true, conectado: false } },
  });
  expect(await rooms.room(created.code), 'GET depois da entrada').toEqual(body.sala);
});

test('OA-05 [CAO-06] reentrada com o próprio token: 200, mesmo lugar e token, sala inalterada', async ({ rooms }) => {
  const pair = await rooms.pair();
  for (const [mark, token] of [['O', pair.to], ['X', pair.tx]] as const) {
    const res = await rooms.expectUnchanged(pair.code, `reentrada de ${mark}`, () => rooms.join(pair.code, token));
    const text = await res.text();
    expect(res.status(), `reentrada de ${mark}: ${text}`).toBe(200);
    const body = JSON.parse(text) as { sala: Room; jogador: PlayerInfo };
    expect(body.jogador, `reentrada de ${mark}`).toEqual({ simbolo: mark, token });
    expect(body.sala, `reentrada de ${mark}: sala`).toEqual(pair.room);
  }
  // Esquema Bearer sem distinção de maiúsculas (6.4).
  const lower = await rooms.request.post(`/api/rooms/${pair.code}/players`, { headers: { Authorization: `bearer ${pair.to}` } });
  expect(lower.status(), 'reentrada com "bearer" minúsculo').toBe(200);
  expect(((await lower.json()) as { jogador: PlayerInfo }).jogador.simbolo).toBe('O');
});
