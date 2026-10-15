import { test, expect } from '../support/fixtures';
import { STATUS_TEXT } from '../support/ui';

/* Grupo U: abertura da página, alternância e célula ocupada (docs/test-plan.md, seção 8). */

test('U-01 [CA-01] página inicial: tabuleiro vazio, vez de X, CSS e JS carregados', async ({ ui, page }) => {
  await ui.open();
  await expect(page).toHaveTitle('Jogo da Velha');
  await ui.expectBoard('.........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
  await ui.expectWinning([]);
  await ui.expectCellsDisabled(false);
  await ui.expectNoError();
  await expect(ui.newGame).toBeVisible();

  // CSS aplicado: o tabuleiro é uma grade; JS executado: estado "playing".
  const display = await ui.board.evaluate((el) => getComputedStyle(el).display);
  expect(display, 'style.css deveria definir o tabuleiro como grid').toBe('grid');
  await expect(ui.app).toHaveAttribute('data-state', 'playing');
});

test('U-02 [CA-02] [CA-03] jogadas alternadas entre X e O', async ({ ui }) => {
  await ui.open();
  expect((await ui.click(0)).status()).toBe(200);
  await expect(ui.cell(0)).toHaveText('X');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnO);

  expect((await ui.click(4)).status()).toBe(200);
  await expect(ui.cell(4)).toHaveText('O');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
  await ui.expectBoard('X...O....');
});

test('U-03 [CA-04] célula ocupada: o servidor recusa e a interface mostra a mensagem', async ({ ui }) => {
  await ui.open();
  await ui.play([0]);

  // O clique precisa chegar ao backend: a recusa é do servidor, não do JavaScript.
  const res = await ui.click(0);
  expect(res.status(), 'o POST da célula ocupada deveria ser enviado e recusado com 409').toBe(409);
  await expect(ui.cell(0)).toHaveText('X');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnO);
  await expect(ui.error).toHaveText('Esta célula já está ocupada.');
});

test('U-14 [CA-23] o estado sobrevive ao recarregamento da página', async ({ ui, page }) => {
  await ui.open();
  await ui.play([0, 4]);
  await page.reload();
  await ui.waitIdle();
  await ui.expectBoard('X...O....');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
});

test('U-15 [CA-24] duas abas compartilham a mesma partida', async ({ ui, context }) => {
  await ui.open();
  const second = await context.newPage();
  await second.goto('/');
  await expect(second.getByTestId('board')).toHaveAttribute('aria-busy', 'false');

  await ui.play([0]);
  await second.reload();
  await expect(second.getByTestId('board')).toHaveAttribute('aria-busy', 'false');
  await expect(second.getByTestId('cell-0')).toHaveText('X');
  await expect(second.getByTestId('status')).toHaveText(STATUS_TEXT.turnO);
  await second.close();
});

test('U-16 [RN-14] a interface exibe o estado montado só pelo backend', async ({ ui, game }) => {
  await game.play([0, 3, 1, 4]);
  await ui.open();
  await ui.expectBoard('XX.OO....');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);

  await ui.play([2]);
  await expect(ui.status).toHaveText(STATUS_TEXT.winX);
  await ui.expectWinning([0, 1, 2]);
});
