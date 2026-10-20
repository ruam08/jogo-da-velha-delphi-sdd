import { test, expect } from '../../support/online/fixtures';
import { portOf } from '../../support/raw-http';
import { ONLINE_MESSAGES, bearer } from '../../support/online/rooms';
import { rawRequest } from '../../support/online/raw-request';

/*
 * OA-10: origem nas rotas de sala (plan-online 6.5 passo 1 e 7.7). No modo
 * local, o servidor da suíte aceita http://127.0.0.1:<porta> e
 * http://localhost:<porta> (e os IPv4 privados da máquina). O Host nunca entra
 * na decisão: um site que usa DNS rebinding manda Origin e Host iguais.
 */

const ORIGIN_ERROR = { erro: { codigo: 'ORIGEM_NAO_PERMITIDA', mensagem: ONLINE_MESSAGES.ORIGEM_NAO_PERMITIDA } };

test('OA-10 [CAO-51, CAO-44] Origin nas rotas POST de sala; Host ignorado; rotas locais sem mudança', async ({ rooms, request, baseURL }) => {
  const port = portOf(baseURL);
  const attacker = `http://atacante.test:${port}`;
  const forged: Array<[string, string]> = [['Host', `atacante.test:${port}`], ['Origin', attacker]];

  // Criar sala a partir de outro site (DNS rebinding): 403, nenhuma sala criada.
  const create = await rawRequest(port, 'POST', '/api/rooms', forged);
  expect(create.status, `criar com Origin ${attacker}: ${create.body}`).toBe(403);
  expect(create.headers['content-type']).toBe('application/json; charset=utf-8');
  expect(JSON.parse(create.body)).toEqual(ORIGIN_ERROR);

  // Jogar a partir de outro site, mesmo com o token certo: 403 e sala inalterada.
  const pair = await rooms.pair();
  const before = await rooms.snapshotText(pair.code);
  for (const [path, body] of [
    [`/api/rooms/${pair.code}/moves`, '{"posicao":4}'],
    [`/api/rooms/${pair.code}/reset`, ''],
    [`/api/rooms/${pair.code}/leave`, ''],
    [`/api/rooms/${pair.code}/players`, ''],
  ] as const) {
    const res = await rawRequest(port, 'POST', path, [...forged, ['Authorization', `Bearer ${pair.tx}`]], body);
    expect(res.status, `POST ${path} com Origin ${attacker}`).toBe(403);
    expect(JSON.parse(res.body)).toEqual(ORIGIN_ERROR);
  }
  // Outras origens recusadas: null, porta errada, esquema errado, caminho, dois Origin.
  for (const origins of [['null'], [`http://127.0.0.1:${port + 1}`], [`https://127.0.0.1:${port}`],
    [`http://127.0.0.1:${port}/`], [`http://127.0.0.1:${port}`, `http://127.0.0.1:${port}`]]) {
    const headers: Array<[string, string]> = [['Host', `127.0.0.1:${port}`], ...origins.map((o) => ['Origin', o] as [string, string]),
      ['Authorization', `Bearer ${pair.tx}`]];
    const res = await rawRequest(port, 'POST', `/api/rooms/${pair.code}/moves`, headers, '{"posicao":4}');
    expect(res.status, `Origin ${origins.join(' + ')}`).toBe(403);
  }
  expect(await rooms.snapshotText(pair.code), 'sala inalterada').toBe(before);

  // GET de sala não verifica origem (só leitura, sem token).
  const get = await rawRequest(port, 'GET', `/api/rooms/${pair.code}`, forged);
  expect(get.status, 'GET com Origin de outro site').toBe(200);

  // A própria origem e a ausência de Origin são aceitas.
  const own = await request.post(`/api/rooms/${pair.code}/moves`, {
    headers: { ...bearer(pair.tx), Origin: `http://127.0.0.1:${port}` }, data: { posicao: 4 } });
  expect(own.status(), 'Origin da própria página').toBe(200);
  const local = await request.post(`/api/rooms/${pair.code}/moves`, {
    headers: { ...bearer(pair.to), Origin: `http://localhost:${port}` }, data: { posicao: 0 } });
  expect(local.status(), 'Origin http://localhost').toBe(200);
  const none = await request.post(`/api/rooms/${pair.code}/moves`, { headers: bearer(pair.tx), data: { posicao: 8 } });
  expect(none.status(), 'sem Origin').toBe(200);
  const created = await request.post('/api/rooms', { headers: { Origin: `http://127.0.0.1:${port}` } });
  expect(created.status()).toBe(201);
  const c = await created.json();
  rooms.track(c.sala.codigo, c.jogador.token);

  // A origem não substitui o token: Origin permitida sem token continua 401.
  const noToken = await request.post(`/api/rooms/${pair.code}/moves`, {
    headers: { Origin: `http://127.0.0.1:${port}` }, data: { posicao: 1 } });
  await rooms.expectError(noToken, 401, 'TOKEN_INVALIDO', 'origem permitida sem token');

  // Rota do modo local: responde como hoje, sem verificação de origem (CAO-44).
  await request.post('/api/game/reset');
  const game = await rawRequest(port, 'POST', '/api/game/moves', [...forged, ['Content-Type', 'application/json']], '{"posicao":4}');
  expect(game.status, 'POST /api/game/moves com Origin de outro site').toBe(200);
  expect(JSON.parse(game.body).tabuleiro[4]).toBe('X');
  await request.post('/api/game/reset');
});
