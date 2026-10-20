import { test, expect } from '@playwright/test';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { DedicatedServer, startServer } from '../../support/online/server-process';
import { HttpReply, TOKEN_LIKE, http, securityHeaderProblems } from '../../support/online/hardening';

/*
 * Entrega O7 (pendência registrada na O6): o teto de 64 KB do corpo HTTP
 * exatamente no limite. docs/plan-online.md, seção 13.1 (H-07, B3) e
 * docs/test-plan-online.md, OV-18.
 *
 * Semântica (B3, implementada na O6): nenhum corpo ocupa mais de 65.536 bytes
 * de memória; a rota antiga /api/game/moves, a única que aceita corpos maiores
 * que 1 KB, processa um corpo de até 65.536 bytes e responde 413
 * CORPO_MUITO_GRANDE a partir de 65.537 bytes, sem mudar o estado, com
 * Content-Length ou em blocos (chunked). As rotas de sala continuam com o
 * limite de 1 KB da especificação (CAO-52).
 *
 * Para provar que o corpo do limite foi lido inteiro (e não truncado), cada
 * corpo é um JSON válido cujo fim só existe no último byte: {"posicao":N,"x":"aaa…"}.
 * Truncado em qualquer ponto, ele deixaria de ser JSON e a resposta seria 400.
 */

const LIMIT = 64 * 1024;   // 65.536 bytes (MAX_REQUEST_BODY_BYTES, uRequestLimits)
const PORT = 8810;
const BODY_ERROR = { erro: { codigo: 'CORPO_MUITO_GRANDE', mensagem: ONLINE_MESSAGES.CORPO_MUITO_GRANDE } };
const JSON_HEADERS: Array<[string, string]> = [['Content-Type', 'application/json']];

/** Corpo de jogada com exatamente `size` bytes, JSON válido só se lido até o fim. */
function moveBody(position: number, size: number): Buffer {
  const head = `{"posicao":${position},"x":"`;
  const tail = '"}';
  const pad = size - Buffer.byteLength(head) - Buffer.byteLength(tail);
  const body = Buffer.from(head + 'a'.repeat(pad) + tail, 'utf8');
  expect(body.length, 'tamanho do corpo montado').toBe(size);
  return body;
}

function move(position: number, size: number, chunkSize?: number): Promise<HttpReply> {
  return http(PORT, { method: 'POST', path: '/api/game/moves', headers: JSON_HEADERS, body: moveBody(position, size), chunkSize });
}

async function state(): Promise<any> {
  const r = await http(PORT, { path: '/api/game' });
  expect(r.status).toBe(200);
  return r.json;
}

function logProblems(server: DedicatedServer): string[] {
  const out: string[] = [];
  for (const line of server.output().split(/\r?\n/)) {
    if (/-> 5\d\d|ERRO|AVISO|Erro fatal/.test(line)) out.push(`log: ${line}`);
    if (TOKEN_LIKE.test(line)) out.push('log com token');
  }
  return out;
}

test('OV-18 [CAO-52] corpo de 64 KB exatamente no limite: 65.535 e 65.536 bytes processados inteiros; 65.537 bytes → 413 sem mudar o estado (Content-Length e em blocos)', async () => {
  const server = await startServer('ov-18', PORT, ['--bind', '127.0.0.1']);
  const problems: string[] = [];
  try {
    expect((await http(PORT, { method: 'POST', path: '/api/game/reset' })).status).toBe(200);

    // Abaixo do limite (65.535 bytes): X joga na casa 0.
    const below = await move(0, LIMIT - 1);
    expect(below.status, `65.535 bytes: ${below.body.slice(0, 200)}`).toBe(200);
    expect(below.json.tabuleiro[0], '65.535 bytes: a jogada valeu').toBe('X');

    // No limite (65.536 bytes): o corpo é lido inteiro (o JSON só fecha no último byte); O joga na 4.
    const at = await move(4, LIMIT);
    expect(at.status, `65.536 bytes: ${at.body.slice(0, 200)}`).toBe(200);
    expect(at.json.tabuleiro[4], '65.536 bytes: a jogada valeu').toBe('O');
    problems.push(...securityHeaderProblems('200 no limite', at));

    // Acima (65.537 bytes): 413 CORPO_MUITO_GRANDE e o estado não muda.
    const before = await state();
    const above = await move(8, LIMIT + 1);
    expect(above.status, '65.537 bytes').toBe(413);
    expect(above.json).toEqual(BODY_ERROR);
    problems.push(...securityHeaderProblems('413 acima do limite', above));
    expect(await state(), '65.537 bytes: estado inalterado').toEqual(before);

    // Os mesmos limites com o corpo em blocos (Transfer-Encoding: chunked, blocos de 4.096 bytes,
    // o último menor): 65.537 recusado sem mudar o estado; 65.536 processado inteiro.
    const chunkedAbove = await move(8, LIMIT + 1, 4096);
    expect(chunkedAbove.status, '65.537 bytes em blocos').toBe(413);
    expect(chunkedAbove.json).toEqual(BODY_ERROR);
    expect(await state(), '65.537 bytes em blocos: estado inalterado').toEqual(before);
    const chunkedAt = await move(8, LIMIT, 4096);
    expect(chunkedAt.status, `65.536 bytes em blocos: ${chunkedAt.body.slice(0, 200)}`).toBe(200);
    expect(chunkedAt.json.tabuleiro[8], '65.536 bytes em blocos: a jogada valeu').toBe('X');

    // Bem acima (1 MB): continua 413, e o servidor segue respondendo.
    const far = await move(2, 1024 * 1024, 64 * 1024);
    expect(far.status, '1 MB em blocos').toBe(413);
    expect((await http(PORT, { path: '/health' })).status).toBe(200);

    // As rotas de sala mantêm o limite de 1 KB da especificação: 65.536 bytes → 413, nenhuma sala criada.
    const room = await http(PORT, { method: 'POST', path: '/api/rooms', headers: JSON_HEADERS, body: Buffer.alloc(LIMIT, 0x20) });
    expect(room.status, 'sala com 65.536 bytes').toBe(413);
    expect(room.json).toEqual(BODY_ERROR);
    expect(server.output(), 'nenhuma sala criada').not.toMatch(/POST \/api\/rooms -> 201/);

    problems.push(...logProblems(server));
    expect(problems).toEqual([]);
  } finally {
    await server.stop();
  }
});
