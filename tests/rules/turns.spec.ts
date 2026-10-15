import { test, expect } from '../support/fixtures';
import { GameState, INITIAL_STATE, describe, state } from '../support/api';

/* Grupo R: inicialização, alternância e células ocupadas, pela API real. */

test('R-01 [CA-01] estado inicial de uma partida', async ({ game }) => {
  expect(await game.state()).toEqual(INITIAL_STATE);
});

test('R-02 [CA-02] primeira jogada é de X e passa a vez para O', async ({ game }) => {
  const res = await game.move(0);
  expect(res.status()).toBe(200);
  expect(await res.json()).toEqual(state('X........', 'EM_ANDAMENTO', 'O'));
});

test('R-03 [CA-03] segunda jogada é de O e devolve a vez para X', async ({ game }) => {
  await game.play([0]);
  const res = await game.move(4);
  expect(res.status()).toBe(200);
  expect(await res.json()).toEqual(state('X...O....', 'EM_ANDAMENTO', 'X'));
});

test('R-04 [CA-03] alternância X/O ao longo de 8 jogadas', async ({ game }) => {
  const moves = [0, 1, 2, 4, 3, 5, 7, 6];
  for (const [i, position] of moves.entries()) {
    const symbol = i % 2 === 0 ? 'X' : 'O';
    const res = await game.move(position);
    expect(res.status(), `jogada ${i + 1} (posição ${position})`).toBe(200);
    const s = (await res.json()) as GameState;
    const where = `após a jogada ${i + 1} (posição ${position}): ${describe(s)}`;
    expect(s.tabuleiro[position], `símbolo gravado ${where}`).toBe(symbol);
    expect(s.jogadorDaVez, `jogador da vez ${where}`).toBe(symbol === 'X' ? 'O' : 'X');
    expect(s.status, `status ${where}`).toBe('EM_ANDAMENTO');
  }
});

test('R-05 [CA-07] o cliente não escolhe o símbolo (campos extras são ignorados)', async ({ game }) => {
  const res = await game.postMoveRaw('{"posicao":0,"simbolo":"O","jogador":"O"}');
  expect(res.status()).toBe(200);
  expect(await res.json()).toEqual(state('X........', 'EM_ANDAMENTO', 'O'));
});

test('R-06 [CA-04] jogada na célula do adversário: 409 CELULA_OCUPADA, estado inalterado', async ({ game }) => {
  await game.play([0]);
  const res = await game.expectUnchanged('O na célula 0', () => game.move(0));
  await game.expectError(res, 409, 'CELULA_OCUPADA', 'O na célula 0');
  expect(await game.state()).toEqual(state('X........', 'EM_ANDAMENTO', 'O'));
});

test('R-07 [CA-04] jogada na própria célula também é recusada e a vez não muda', async ({ game }) => {
  await game.play([0, 4]);
  const res = await game.expectUnchanged('X na célula 0', () => game.move(0));
  await game.expectError(res, 409, 'CELULA_OCUPADA', 'X na célula 0');
  expect((await game.state()).jogadorDaVez).toBe('X');
});

test('R-08 [CA-04] após uma recusa, a partida segue normalmente', async ({ game }) => {
  await game.play([0]);
  expect((await game.move(0)).status()).toBe(409);
  const res = await game.move(4);
  expect(res.status()).toBe(200);
  expect(await res.json()).toEqual(state('X...O....', 'EM_ANDAMENTO', 'X'));
});
