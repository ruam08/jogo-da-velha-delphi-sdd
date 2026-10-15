import { test, expect } from '../support/fixtures';
import { S_EMP, S_L1 } from '../support/sequences';
import { STATUS_TEXT } from '../support/ui';

/* Grupo U: empate, bloqueio após o fim, nova partida e mensagens. */

const GAME_OVER = 'A partida já terminou. Clique em "Nova partida" para jogar novamente.';

test('U-07 [CA-15] empate: mensagem, nenhum destaque e células inativas', async ({ ui }) => {
  await ui.open();
  await ui.play(S_EMP);
  await ui.expectBoard('XOXXOOOXX');
  await expect(ui.status).toHaveText(STATUS_TEXT.draw);
  await ui.expectWinning([]);
  await ui.expectCellsDisabled(true);
});

test('U-08 [CA-16] clique em célula vazia após vitória: o servidor recusa e nada muda', async ({ ui }) => {
  await ui.open();
  await ui.play(S_L1);
  const res = await ui.click(5);
  expect(res.status(), 'o clique deveria chegar ao backend e ser recusado').toBe(409);
  await expect(ui.cell(5)).toHaveText('');
  await expect(ui.status).toHaveText(STATUS_TEXT.winX);
  await expect(ui.error).toHaveText(GAME_OVER);
});

test('U-09 [CA-17] clique após empate: mensagem de partida encerrada, não de célula ocupada', async ({ ui }) => {
  await ui.open();
  await ui.play(S_EMP);
  expect((await ui.click(4)).status()).toBe(409);
  await ui.expectBoard('XOXXOOOXX');
  await expect(ui.status).toHaveText(STATUS_TEXT.draw);
  await expect(ui.error).toHaveText(GAME_OVER);
});

test('U-10 [CA-19] nova partida após o fim limpa tudo', async ({ ui }) => {
  await ui.open();
  await ui.play(S_L1);
  await ui.click(5);
  await expect(ui.error).toBeVisible();

  await ui.clickNewGame();
  await ui.expectBoard('.........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
  await ui.expectWinning([]);
  await ui.expectCellsDisabled(false);
  await ui.expectNoError();
  await expect(ui.app).toHaveAttribute('data-state', 'playing');
});

test('U-11 [CA-20] nova partida no meio do jogo', async ({ ui }) => {
  await ui.open();
  await ui.play([0, 4]);
  await ui.clickNewGame();
  await ui.expectBoard('.........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
  await ui.expectNoError();
});

test('U-12 [CA-21] a mensagem de erro some após jogada aceita e após nova partida', async ({ ui }) => {
  await ui.open();
  await ui.play([0]);
  await ui.click(0);
  await expect(ui.error).toHaveText('Esta célula já está ocupada.');
  await ui.play([4]);
  await expect(ui.error).toBeHidden();

  await ui.click(4);
  await expect(ui.error).toBeVisible();
  await ui.clickNewGame();
  await expect(ui.error).toBeHidden();
});
