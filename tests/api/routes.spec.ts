import { test, expect } from '../support/fixtures';

/* Grupo A: rotas inexistentes (404) e métodos não permitidos (405). */

const NOT_FOUND: Array<[string, string]> = [
  ['GET', '/api/inexistente'],
  ['POST', '/api/game/movimento'],
  ['GET', '/api/game/'],
  ['GET', '/qualquer'],
];

const NOT_ALLOWED: Array<[string, string, string]> = [
  ['POST', '/api/game', 'GET, HEAD'],
  ['DELETE', '/api/game', 'GET, HEAD'],
  ['GET', '/api/game/moves', 'POST'],
  ['PUT', '/api/game/moves', 'POST'],
  ['GET', '/api/game/reset', 'POST'],
  ['DELETE', '/api/game/reset', 'POST'],
  ['POST', '/health', 'GET, HEAD'],
  ['DELETE', '/health', 'GET, HEAD'],
];

function bodyFor(method: string) {
  return method === 'GET' ? {} : { data: '{"posicao":1}', headers: { 'Content-Type': 'application/json' } };
}

for (const [method, path] of NOT_FOUND) {
  test(`A-08 [CA-26] ${method} ${path} -> 404 ROTA_NAO_ENCONTRADA, estado inalterado`, async ({ game, request }) => {
    await game.play([0]);
    const res = await game.expectUnchanged(`${method} ${path}`,
      () => request.fetch(path, { method, ...bodyFor(method) }));
    await game.expectError(res, 404, 'ROTA_NAO_ENCONTRADA', `${method} ${path}`);
  });
}

for (const [method, path, allow] of NOT_ALLOWED) {
  test(`A-09 [CA-26] ${method} ${path} -> 405 com Allow: ${allow}, estado inalterado`, async ({ game, request }) => {
    await game.play([0]);
    const res = await game.expectUnchanged(`${method} ${path}`,
      () => request.fetch(path, { method, ...bodyFor(method) }));
    await game.expectError(res, 405, 'METODO_NAO_PERMITIDO', `${method} ${path}`);
    expect(res.headers()['allow'], 'cabeçalho Allow').toBe(allow);
  });
}
