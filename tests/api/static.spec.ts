import { test, expect } from '../support/fixtures';
import { portOf, rawHead } from '../support/raw-http';
import { strictText } from '../support/api';

/* A-10: arquivos estáticos servidos pelo próprio servidor Delphi (plano 3.1, DT-04, DT-21). */

const FILES: Array<[string, string, string]> = [
  ['/', 'text/html; charset=utf-8', 'data-testid="board"'],
  ['/index.html', 'text/html; charset=utf-8', 'data-testid="board"'],
  ['/style.css', 'text/css; charset=utf-8', '.board'],
  ['/app.js', 'text/javascript; charset=utf-8', '/api/game'],
];

for (const [path, type, marker] of FILES) {
  test(`A-10 [CA-26] GET ${path}: 200, ${type}`, async ({ game, request }) => {
    const res = await game.expectUnchanged(`GET ${path}`, () => request.get(path));
    expect(res.status(), `GET ${path}`).toBe(200);
    expect(res.headers()['content-type']).toBe(type);
    expect(res.headers()['cache-control']).toBe('no-cache');
    expect(await strictText(res), `conteúdo de ${path}`).toContain(marker);
  });
}

test('A-10 [CA-26] / e /index.html entregam o mesmo arquivo; HEAD / sem corpo', async ({ request, baseURL }) => {
  const root = await (await request.get('/')).text();
  const index = await (await request.get('/index.html')).text();
  expect(root).toBe(index);
  const head = await rawHead(portOf(baseURL), '/');
  expect(head.statusLine).toBe('HTTP/1.1 200 OK');
  expect(head.headers).toMatch(/^Content-Type: text\/html; charset=utf-8$/im);
  expect(head.bodyBytes).toBe(0);
});

for (const path of ['/inexistente.js', '/docs/spec.md', '/..%2Fdocs%2Fspec.md', '/server/bin/TicTacToeServer.exe', '/web/index.html', '/app.js/']) {
  test(`A-10 [CA-26] GET ${path} -> 404 JSON (nada fora da lista fixa é servido)`, async ({ game, request }) => {
    const res = await game.expectUnchanged(`GET ${path}`, () => request.get(path));
    await game.expectError(res, 404, 'ROTA_NAO_ENCONTRADA', `GET ${path}`);
  });
}

for (const [method, path] of [['POST', '/'], ['DELETE', '/app.js'], ['PUT', '/style.css'], ['POST', '/index.html']]) {
  test(`A-10 [CA-26] ${method} ${path} -> 405 com Allow: GET, HEAD`, async ({ game, request }) => {
    const res = await game.expectUnchanged(`${method} ${path}`,
      () => request.fetch(path, { method, data: '{}', headers: { 'Content-Type': 'application/json' } }));
    await game.expectError(res, 405, 'METODO_NAO_PERMITIDO', `${method} ${path}`);
    expect(res.headers()['allow']).toBe('GET, HEAD');
  });
}
