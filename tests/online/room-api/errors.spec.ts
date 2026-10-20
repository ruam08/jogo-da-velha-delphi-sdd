import { request as playwrightRequest } from '@playwright/test';
import { test, expect } from '../../support/online/fixtures';
import { RoomApi, bearer, paddedMoveBody } from '../../support/online/rooms';
import { startServer } from '../../support/online/server-process';
import { S_L1 } from '../../support/sequences';

/* Grupo OA: erros novos de 6.6 e limite de corpo (CAO-45, CAO-52). */

test('OA-08 [CAO-45] cada erro novo alcançável pela API: status, código e mensagem exata em UTF-8', async ({ rooms }) => {
  // SALA_INEXISTENTE
  await rooms.expectError(await rooms.get('ZZZZZY'), 404, 'SALA_INEXISTENTE', 'sala inexistente');

  // AGUARDANDO_OPONENTE (jogada e nova partida sem O)
  const waiting = await rooms.create();
  await rooms.expectError(await rooms.move(waiting.code, waiting.token, 0), 409, 'AGUARDANDO_OPONENTE', 'jogada sem oponente');
  await rooms.expectError(await rooms.reset(waiting.code, waiting.token), 409, 'AGUARDANDO_OPONENTE', 'nova partida sem oponente');

  const pair = await rooms.pair();
  // SALA_CHEIA
  await rooms.expectError(await rooms.join(pair.code), 409, 'SALA_CHEIA', 'sala cheia');
  // TOKEN_INVALIDO
  await rooms.expectError(await rooms.move(pair.code, undefined, 0), 401, 'TOKEN_INVALIDO', 'jogada sem token');
  // VEZ_DO_OPONENTE
  await rooms.expectError(await rooms.move(pair.code, pair.to, 0), 409, 'VEZ_DO_OPONENTE', 'fora da vez');
  // PARTIDA_EM_ANDAMENTO
  await rooms.expectError(await rooms.reset(pair.code, pair.tx), 409, 'PARTIDA_EM_ANDAMENTO', 'nova partida no meio');
  // CORPO_MUITO_GRANDE
  await rooms.expectError(await rooms.moveRaw(pair.code, bearer(pair.tx), paddedMoveBody(0, 1025)), 413, 'CORPO_MUITO_GRANDE', 'corpo grande');
  // Erros do modo local reutilizados, com as mesmas mensagens
  await rooms.playSequence(pair, S_L1);
  await rooms.expectError(await rooms.move(pair.code, pair.to, 5), 409, 'PARTIDA_ENCERRADA', 'partida encerrada');
  // SALA_ENCERRADA
  expect((await rooms.leave(pair.code, pair.tx)).status()).toBe(200);
  await rooms.expectError(await rooms.get(pair.code), 410, 'SALA_ENCERRADA', 'sala encerrada');
});

test('OA-08 [CAO-45, CAO-53] CAPACIDADE_ESGOTADA com --max-rooms 2 (servidor dedicado)', async () => {
  const server = await startServer('oa-08-capacidade', 8770, ['--max-rooms', '2', '--bind', '127.0.0.1']);
  const context = await playwrightRequest.newContext({ baseURL: server.baseURL });
  try {
    const api = new RoomApi(context);
    const first = await api.create(false);
    await api.create(false);
    await api.expectError(await context.post('/api/rooms'), 503, 'CAPACIDADE_ESGOTADA', 'terceira sala');
    // Uma sala encerrada deixa de contar no limite.
    expect((await api.leave(first.code, first.token)).status()).toBe(200);
    const again = await context.post('/api/rooms');
    expect(again.status(), `criação depois de encerrar uma sala: ${await again.text()}`).toBe(201);
    // As outras rotas continuam iguais no servidor dedicado.
    expect((await context.get('/health')).status()).toBe(200);
    expect((await context.get('/api/game')).status()).toBe(200);
  } finally {
    await context.dispose();
    await server.stop();
  }
});

test('OA-09 [CAO-52] corpo acima de 1.024 bytes: 413 e sala inalterada; com 1.024 bytes, aceito', async ({ rooms }) => {
  const pair = await rooms.pair();
  const big = paddedMoveBody(0, 1025);
  expect(Buffer.byteLength(big)).toBe(1025);
  const res = await rooms.expectUnchanged(pair.code, 'jogada com 1.025 bytes',
    () => rooms.moveRaw(pair.code, bearer(pair.tx), big));
  await rooms.expectError(res, 413, 'CORPO_MUITO_GRANDE', 'jogada com 1.025 bytes');

  // 413 vem antes de token e de sala (passo 2 da seção 6.5).
  await rooms.expectError(await rooms.moveRaw(pair.code, {}, big), 413, 'CORPO_MUITO_GRANDE', '1.025 bytes sem token');
  await rooms.expectError(await rooms.moveRaw('ZZZZZY', {}, big), 413, 'CORPO_MUITO_GRANDE', '1.025 bytes em sala inexistente');

  const create = await rooms.request.post('/api/rooms', { data: 'x'.repeat(2048), headers: { 'Content-Type': 'text/plain' } });
  await rooms.expectError(create, 413, 'CORPO_MUITO_GRANDE', 'criação com 2 KB');

  const exact = paddedMoveBody(0, 1024);
  expect(Buffer.byteLength(exact)).toBe(1024);
  const ok = await rooms.moveRaw(pair.code, bearer(pair.tx), exact);
  expect(ok.status(), `jogada com 1.024 bytes: ${await ok.text()}`).toBe(200);
  expect((await rooms.room(pair.code)).partida.tabuleiro[0]).toBe('X');
});
