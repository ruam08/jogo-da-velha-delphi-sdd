import { test, expect } from '../support/fixtures';
import { INITIAL_JSON, INITIAL_STATE, describe, state, strictText } from '../support/api';
import { S_EMP, S_EMP_FINAL, S_L1, S_L1_FINAL } from '../support/sequences';

/* Grupo R: empate, bloqueio após o fim e reinício, pela API real. */

test('R-19 [CA-15] empate com tabuleiro cheio sem combinação', async ({ game }) => {
  const mid = await game.play(S_EMP.slice(0, 8));
  expect(mid.status, `terminou antes da 9ª jogada: ${describe(mid)}`).toBe('EM_ANDAMENTO');
  const res = await game.move(S_EMP[8]);
  expect(res.status()).toBe(200);
  expect(await res.json()).toEqual(S_EMP_FINAL);
});

test('R-20 [CA-18] após vitória, nenhuma célula aceita jogada (409 PARTIDA_ENCERRADA)', async ({ game }) => {
  await game.play(S_L1);
  for (const position of [5, 6, 7, 8, 0]) {
    const label = `posição ${position} após vitória`;
    const res = await game.expectUnchanged(label, () => game.move(position));
    await game.expectError(res, 409, 'PARTIDA_ENCERRADA', label);
  }
  expect(await game.state()).toEqual(S_L1_FINAL);
});

test('R-21 [CA-17] [CA-18] após empate, a resposta é PARTIDA_ENCERRADA (não CELULA_OCUPADA)', async ({ game }) => {
  await game.play(S_EMP);
  for (const position of [0, 4, 8]) {
    const label = `posição ${position} após empate`;
    const res = await game.expectUnchanged(label, () => game.move(position));
    await game.expectError(res, 409, 'PARTIDA_ENCERRADA', label);
  }
});

test('R-22 posição inválida tem precedência sobre partida encerrada (RN-15)', async ({ game }) => {
  await game.play(S_L1);
  const res = await game.expectUnchanged('posição 9 após vitória', () => game.move(9));
  await game.expectError(res, 400, 'POSICAO_INVALIDA', 'posição 9 após vitória');
});

for (const [id, ca, label, moves] of [
  ['R-23', 'CA-19', 'após vitória', S_L1],
  ['R-24', 'CA-19', 'após empate', S_EMP],
  ['R-25', 'CA-20', 'no meio da partida', [0, 4]],
] as Array<[string, string, string, number[]]>) {
  test(`${id} [${ca}] reiniciar ${label} devolve exatamente o estado inicial`, async ({ game, request }) => {
    await game.play(moves);
    const res = await request.post('/api/game/reset');
    expect(res.status()).toBe(200);
    expect(await strictText(res), 'JSON do reset').toBe(INITIAL_JSON);
    expect(await game.state(), 'GET depois do reset').toEqual(INITIAL_STATE);
  });
}

test('R-26 [CA-19] partida nova é jogável desde o início, inclusive nas células antes ocupadas', async ({ game }) => {
  await game.play(S_L1);
  await game.reset();
  const res = await game.move(0);
  expect(res.status()).toBe(200);
  expect(await res.json()).toEqual(state('X........', 'EM_ANDAMENTO', 'O'));
  expect(await game.play([3, 1, 4, 2])).toEqual(S_L1_FINAL);
});
