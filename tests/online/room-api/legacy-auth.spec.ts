import { test, expect } from '../../support/online/fixtures';
import { portOf, rawHead } from '../../support/raw-http';
import { rawRequest } from '../../support/online/raw-request';

/*
 * OA-11 (novo na O3, ressalva da O2): cabeçalho Authorization nas rotas
 * antigas. Desde a O2 o servidor trata OnParseAuthentication do Indy; antes,
 * qualquer Authorization que não fosse Basic derrubava a conexão. As rotas
 * /health e /api/game* precisam responder exatamente como sem o cabeçalho.
 */

const VARIANTS: Array<[string, string]> = [
  ['Bearer com 32 hex', 'Bearer 0123456789abcdef0123456789abcdef'],
  ['Bearer curto', 'Bearer abc'],
  ['Bearer sem valor', 'Bearer'],
  ['Basic', 'Basic dXN1YXJpbzpzZW5oYQ=='],
  ['Basic inválido', 'Basic %%%'],
  ['esquema desconhecido', 'Negotiate YIIBhgYGKwYBBQUCoIIBejCCAXagMDAuBgkqhkiC9xIBAgIGCSqGSIb3EgECAgYKKwYBBAGCNwICHgYKKwYBBAGCNwICCg=='],
  ['só texto', 'qualquer coisa'],
];

test('OA-11 [CAO-44] Authorization em /health e /api/game*: mesma resposta que sem o cabeçalho', async ({ request, baseURL }) => {
  const port = portOf(baseURL);
  const baseline = async (auth: string | null) => {
    const h: Array<[string, string]> = [['Host', `127.0.0.1:${port}`]];
    if (auth !== null) h.push(['Authorization', auth]);
    const json: Array<[string, string]> = [...h, ['Content-Type', 'application/json']];
    const out: string[] = [];
    const health = await rawRequest(port, 'GET', '/health', h);
    out.push(`health ${health.status} ${health.body}`);
    const reset = await rawRequest(port, 'POST', '/api/game/reset', json);
    out.push(`reset ${reset.status} ${reset.body}`);
    const move = await rawRequest(port, 'POST', '/api/game/moves', json, '{"posicao":4}');
    out.push(`move ${move.status} ${move.body}`);
    const occupied = await rawRequest(port, 'POST', '/api/game/moves', json, '{"posicao":4}');
    out.push(`occupied ${occupied.status} ${occupied.body}`);
    const invalid = await rawRequest(port, 'POST', '/api/game/moves', json, '{"posicao":9}');
    out.push(`invalid ${invalid.status} ${invalid.body}`);
    const state = await rawRequest(port, 'GET', '/api/game', h);
    out.push(`state ${state.status} ${state.body}`);
    const wrongMethod = await rawRequest(port, 'DELETE', '/api/game', h);
    out.push(`delete ${wrongMethod.status} ${wrongMethod.headers['allow']} ${wrongMethod.body}`);
    return out;
  };

  const without = await baseline(null);
  expect(without[0]).toBe('health 200 {"status":"ok"}');
  expect(without[2]).toMatch(/^move 200 /);
  for (const [label, value] of VARIANTS) {
    expect(await baseline(value), `Authorization: ${label}`).toEqual(without);
  }
  // HEAD também responde, sem corpo.
  const head = await rawHead(port, '/api/game');
  expect(head.statusLine).toMatch(/^HTTP\/1\.1 200 /);
  // Pelo cliente HTTP do Playwright, com Bearer: idem.
  const res = await request.get('/api/game', { headers: { Authorization: 'Bearer 0123456789abcdef0123456789abcdef' } });
  expect(res.status()).toBe(200);
  await request.post('/api/game/reset');
});
