import { test, expect } from '../support/fixtures';
import { S_L1 } from '../support/sequences';
import { STATUS_TEXT, cellName } from '../support/ui';

/* Grupo U: teclado, acessibilidade básica e tela pequena. */

test('U-20 [CA-29] teclado: Enter e Espaço jogam, setas movem o foco', async ({ ui, page }) => {
  await ui.open();
  await ui.cell(0).focus();

  let move = ui.waitForMove();
  await page.keyboard.press('Enter');
  await move;
  await ui.waitIdle();
  await expect(ui.cell(0)).toHaveText('X');

  await page.keyboard.press('ArrowRight');
  await expect(ui.cell(1)).toBeFocused();
  move = ui.waitForMove();
  await page.keyboard.press('Space');
  await move;
  await ui.waitIdle();
  await expect(ui.cell(1)).toHaveText('O');

  await page.keyboard.press('ArrowDown');
  await expect(ui.cell(4)).toBeFocused();
  await page.keyboard.press('ArrowLeft');
  await expect(ui.cell(3)).toBeFocused();
  await page.keyboard.press('ArrowUp');
  await expect(ui.cell(0)).toBeFocused();
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
});

test('U-21 [CA-30] tela pequena (360 x 640): sem rolagem horizontal e células tocáveis', async ({ ui, page }) => {
  await page.setViewportSize({ width: 360, height: 640 });
  await ui.open();

  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow, 'a página não deveria rolar na horizontal').toBeLessThanOrEqual(0);

  const board = await ui.board.boundingBox();
  expect(board, 'tabuleiro visível').not.toBeNull();
  expect(board!.x, 'tabuleiro começa dentro da tela').toBeGreaterThanOrEqual(0);
  expect(board!.x + board!.width, 'tabuleiro termina dentro da tela').toBeLessThanOrEqual(360);

  for (let i = 0; i < 9; i++) {
    const box = await ui.cell(i).boundingBox();
    expect(box!.width, `largura da célula ${i}`).toBeGreaterThanOrEqual(44);
    expect(box!.height, `altura da célula ${i}`).toBeGreaterThanOrEqual(44);
  }

  await ui.play([8]);
  await expect(ui.cell(8)).toHaveText('X');
});

test('U-22 [CA-29] acessibilidade básica: idioma, marcos, nomes e anúncios', async ({ ui, page }) => {
  await ui.open();
  await expect(page.locator('html')).toHaveAttribute('lang', 'pt-BR');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Jogo da Velha');
  await expect(page.getByRole('main')).toBeVisible();
  await expect(page.getByRole('group', { name: 'Tabuleiro' })).toBeVisible();
  await expect(page.getByRole('status')).toHaveText(STATUS_TEXT.turnX);
  await expect(page.getByRole('button', { name: 'Nova partida' })).toBeVisible();

  for (let i = 0; i < 9; i++) {
    await expect(ui.cell(i), `nome acessível da célula ${i}`).toHaveAccessibleName(cellName(i, ''));
  }

  await ui.play(S_L1);
  await expect(page.getByRole('button', { name: cellName(0, 'X', true) })).toBeVisible();
  await expect(ui.cell(3)).toHaveAccessibleName(cellName(3, 'O'));
  await expect(ui.cell(5)).toHaveAccessibleName(cellName(5, ''));

  await ui.click(5);
  await expect(page.getByRole('alert')).toHaveText('A partida já terminou. Clique em "Nova partida" para jogar novamente.');
});
