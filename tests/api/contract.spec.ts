import { test, expect } from '../support/fixtures';
import { INITIAL_JSON, INITIAL_STATE, GameState, state, strictText } from '../support/api';
import { portOf, rawHead } from '../support/raw-http';

/* Grupo A: códigos HTTP, cabeçalhos e estrutura JSON (docs/test-plan.md, seção 7). */

test.describe('Contrato da API', () => {
  test('A-01 [CA-01] GET /api/game: 200, cabeçalhos e JSON exato do estado inicial', async ({ game, request }) => {
    const res = await request.get('/api/game');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'], 'Content-Type').toBe('application/json; charset=utf-8');
    expect(res.headers()['cache-control'], 'Cache-Control').toBe('no-store');
    const text = await strictText(res);
    expect(text, 'JSON do estado inicial (campos, ordem, null e [])').toBe(INITIAL_JSON);

    const body = JSON.parse(text) as GameState;
    expect(Object.keys(body), 'campos do estado').toEqual(
      ['tabuleiro', 'status', 'jogadorDaVez', 'vencedor', 'celulasVencedoras']);
    expect(body).toEqual(INITIAL_STATE);
    void game;
  });

  test('A-02 [CA-19] POST /api/game/reset devolve o estado inicial, com ou sem corpo', async ({ game, request }) => {
    await game.play([0, 4]);
    const semCorpo = await request.post('/api/game/reset');
    expect(semCorpo.status()).toBe(200);
    expect(await strictText(semCorpo), 'reset sem corpo').toBe(INITIAL_JSON);

    await game.play([0]);
    const comCorpo = await request.post('/api/game/reset', { data: { qualquer: 1 } });
    expect(comCorpo.status()).toBe(200);
    expect(await strictText(comCorpo), 'reset com corpo (ignorado)').toBe(INITIAL_JSON);
    expect(comCorpo.headers()['cache-control']).toBe('no-store');
  });

  test('A-03 [CA-02] resposta da jogada é igual ao estado consultado em seguida', async ({ game, request }) => {
    const res = await game.move(4);
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type']).toBe('application/json; charset=utf-8');
    expect(res.headers()['cache-control']).toBe('no-store');
    const fromMove = await strictText(res);
    const fromGet = await strictText(await request.get('/api/game'));
    expect(fromMove, 'corpo da jogada x GET /api/game').toBe(fromGet);
    expect(JSON.parse(fromMove)).toEqual(state('....X....', 'EM_ANDAMENTO', 'O'));
  });

  test('A-11 HEAD /api/game: 200, mesmo Content-Type e nenhum byte de corpo', async ({ game, baseURL }) => {
    const head = await rawHead(portOf(baseURL), '/api/game');
    expect(head.statusLine, 'linha de status').toBe('HTTP/1.1 200 OK');
    expect(head.headers, 'Content-Type').toMatch(/^Content-Type: application\/json; charset=utf-8$/im);
    expect(head.bodyBytes, 'bytes de corpo no HEAD').toBe(0);
    void game;
  });

  test('A-12 [CA-27] /health: 200 {"status":"ok"}, HEAD sem corpo e partida inalterada', async ({ game, request, baseURL }) => {
    await game.play([0]);
    const res = await game.expectUnchanged('GET /health', () => request.get('/health'));
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type']).toBe('application/json; charset=utf-8');
    expect(await strictText(res)).toBe('{"status":"ok"}');

    const head = await rawHead(portOf(baseURL), '/health');
    expect(head.statusLine).toBe('HTTP/1.1 200 OK');
    expect(head.bodyBytes, 'bytes de corpo no HEAD /health').toBe(0);
  });
});
