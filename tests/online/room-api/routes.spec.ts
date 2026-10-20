import { test, expect } from '../../support/online/fixtures';
import { bearer } from '../../support/online/rooms';

/* Grupo OA: rotas, métodos e códigos de sala inválidos (plan-online 6.1). */

test('OA-06 [CAO-45] métodos não permitidos (405 com Allow) e sub-rotas inexistentes (404)', async ({ rooms }) => {
  const pair = await rooms.pair();
  const c = pair.code;
  const notAllowed: Array<[string, string, string]> = [
    ['GET', '/api/rooms', 'POST'],
    ['PUT', '/api/rooms', 'POST'],
    ['DELETE', '/api/rooms', 'POST'],
    ['POST', `/api/rooms/${c}`, 'GET, HEAD'],
    ['DELETE', `/api/rooms/${c}`, 'GET, HEAD'],
    ['PUT', `/api/rooms/${c}`, 'GET, HEAD'],
    ['GET', `/api/rooms/${c}/moves`, 'POST'],
    ['GET', `/api/rooms/${c}/reset`, 'POST'],
    ['GET', `/api/rooms/${c}/leave`, 'POST'],
    ['GET', `/api/rooms/${c}/players`, 'POST'],
    ['DELETE', `/api/rooms/${c}/players`, 'POST'],
    // 405 vem antes de "sala inexistente" (passo 0 da seção 6.5).
    ['GET', '/api/rooms/abc/moves', 'POST'],
  ];
  for (const [method, path, allow] of notAllowed) {
    const label = `${method} ${path}`;
    const res = await rooms.expectUnchanged(c, label,
      () => rooms.raw(method, path, { headers: bearer(pair.tx), ...(method === 'GET' ? {} : { data: '{"posicao":0}' }) }));
    await rooms.expectError(res, 405, 'METODO_NAO_PERMITIDO', label);
    expect(res.headers()['allow'], `${label}: Allow`).toBe(allow);
  }

  const notFound: Array<[string, string]> = [
    ['GET', `/api/rooms/${c}/x`],
    ['POST', `/api/rooms/${c}/x`],
    ['GET', '/api/rooms/'],
    ['POST', '/api/rooms/'],
    ['GET', `/api/rooms/${c}/`],
    ['POST', `/api/rooms/${c}/moves/`],
    ['POST', `/api/rooms/${c}/moves/extra`],
    ['POST', '/api/rooms//moves'],
    ['POST', `/api/rooms/${c}/Moves`],
  ];
  for (const [method, path] of notFound) {
    const label = `${method} ${path}`;
    const res = await rooms.expectUnchanged(c, label,
      () => rooms.raw(method, path, { headers: bearer(pair.tx), ...(method === 'GET' ? {} : { data: '{"posicao":0}' }) }));
    await rooms.expectError(res, 404, 'ROTA_NAO_ENCONTRADA', label);
  }
});

test('OA-07 [CAO-30] códigos inválidos ou desconhecidos: 404 SALA_INEXISTENTE em todas as rotas', async ({ rooms }) => {
  const other = await rooms.pair();   // token válido de outra sala, para as rotas que exigem um
  const codes = ['abc', 'K7PM2', 'K7PM2Q0', 'K7PM2I', 'K7PM2L', 'K7PM2O', '..%2Fx', '%4B7PM2Q', 'ZZZZZZ', 'zzzzzz'];
  for (const code of codes) {
    const attempts: Array<[string, () => ReturnType<typeof rooms.get>]> = [
      [`GET /api/rooms/${code}`, () => rooms.get(code)],
      [`HEAD /api/rooms/${code}`, () => rooms.raw('HEAD', `/api/rooms/${code}`)],
      [`POST /api/rooms/${code}/players`, () => rooms.join(code)],
      [`POST /api/rooms/${code}/moves`, () => rooms.move(code, other.tx, 0)],
      [`POST /api/rooms/${code}/reset`, () => rooms.reset(code, other.tx)],
      [`POST /api/rooms/${code}/leave`, () => rooms.leave(code, other.tx)],
    ];
    for (const [label, action] of attempts) {
      const res = await rooms.expectUnchanged(other.code, label, action);
      if (label.startsWith('HEAD')) {
        expect(res.status(), label).toBe(404);
      } else {
        await rooms.expectError(res, 404, 'SALA_INEXISTENTE', label);
      }
    }
  }
});
