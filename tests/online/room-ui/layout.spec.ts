import { Locator, chromium } from '@playwright/test';
import { test, expect } from '../../support/online/ui-fixtures';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { ONLINE_TEXT, OnlineUi, Players, cellName, youAre } from '../../support/online/online-ui';
import { S_L1 } from '../../support/sequences';

/* Grupo OU: tela pequena, teclado e acessibilidade, dois processos do navegador. */

async function expectFits(ui: OnlineUi, screen: string): Promise<void> {
  const overflow = await ui.page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow, `${ui.name}, tela ${screen}: sem rolagem horizontal`).toBeLessThanOrEqual(0);
  if (await ui.board.isVisible()) {
    const box = (await ui.board.boundingBox())!;
    expect(box.x, `${screen}: tabuleiro começa dentro da tela`).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width, `${screen}: tabuleiro termina dentro da tela`).toBeLessThanOrEqual(360);
    for (let i = 0; i < 9; i++) {
      const c = (await ui.cell(i).boundingBox())!;
      expect(c.width, `${screen}: largura da célula ${i}`).toBeGreaterThanOrEqual(44);
      expect(c.height, `${screen}: altura da célula ${i}`).toBeGreaterThanOrEqual(44);
    }
  }
}

test('OU-20 [CAO-42] tela pequena (360 x 640): inicial, sala criada, jogo, cheia e encerrada', async ({ players }) => {
  const viewport = { width: 360, height: 640 };
  const a = await players.open('A', { viewport });
  await a.open();
  await a.expectState('inicio');
  await expectFits(a, 'inicial');
  const code = await a.create();
  await expectFits(a, 'sala criada');
  const link = (await a.roomLink.textContent())!;

  const b = await players.open('B', { viewport });
  await b.openLink(link);
  await b.expectState('convite');
  await expectFits(b, 'convite');
  await b.acceptInvite(code);
  await a.expectState('jogando');
  await expectFits(a, 'jogo');
  await expectFits(b, 'jogo');
  expect((await a.click(8)).status()).toBe(200);
  await expect(b.cell(8)).toHaveText('X');

  const c = await players.open('C', { viewport });
  await c.openLink(link);
  await c.expectState('cheia');
  await expectFits(c, 'sala cheia');

  await b.leaveRoom();
  await a.expectState('encerrada');
  await expectFits(a, 'encerrada');
  a.code = '';
  b.code = '';
});

/** Pressiona Tab até `target` receber o foco. */
async function tabTo(ui: OnlineUi, target: Locator, max = 30): Promise<void> {
  for (let i = 0; i < max; i++) {
    if (await target.evaluate((el) => el === document.activeElement)) return;
    await ui.page.keyboard.press('Tab');
  }
  throw new Error(`${ui.name}: o foco não chegou ao elemento com Tab`);
}

test('OU-21 [CAO-43] só teclado: criar, copiar, entrar e jogar; marcos, nomes e anúncios', async ({ players }) => {
  const a = await players.open('A', { permissions: ['clipboard-read', 'clipboard-write'] });
  await a.open();
  const page = a.page;
  await expect(page.locator('html')).toHaveAttribute('lang', 'pt-BR');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await expect(page.getByRole('main')).toBeVisible();
  await expect(page.getByLabel('Código da sala')).toBeVisible();

  await tabTo(a, a.createRoom);
  const created = page.waitForResponse((r) => new URL(r.url()).pathname === '/api/rooms');
  await page.keyboard.press('Enter');
  expect((await created).status()).toBe(201);
  await a.expectState('aguardando');
  const code = (await a.roomCode.textContent())!;
  a.code = code;
  a.seat = 'X';
  await tabTo(a, a.copyLink);
  await page.keyboard.press('Space');
  await expect(a.copyFeedback).toHaveText(ONLINE_TEXT.copied);

  const b = await players.open('B');
  await b.open();
  await tabTo(b, b.codeInput);
  await b.page.keyboard.type(code.toLowerCase());
  const joined = b.page.waitForResponse((r) => /\/players$/.test(r.url()));
  await b.page.keyboard.press('Enter');
  expect((await joined).status()).toBe(201);
  await b.expectState('jogando');
  b.code = code;
  b.seat = 'O';
  await expect(b.youAre).toHaveText(youAre('O'));

  // Regiões de status, alerta e nomes acessíveis das células.
  await expect(a.status).toHaveAttribute('role', 'status');
  await expect(a.opponent).toHaveAttribute('role', 'status');
  await expect(a.error).toHaveAttribute('role', 'alert');
  for (let i = 0; i < 9; i++) await expect(a.cell(i)).toHaveAccessibleName(cellName(i, ''));
  await expect(page.getByRole('group', { name: 'Tabuleiro' })).toBeVisible();

  // A joga com Enter na célula 0; B navega pelas setas e joga com Espaço na 4.
  await tabTo(a, a.cell(0));
  let move = a.waitForMove();
  await page.keyboard.press('Enter');
  expect((await move).status()).toBe(200);
  await expect(b.cell(0)).toHaveText('X');
  await tabTo(b, b.cell(0));
  await b.page.keyboard.press('ArrowDown');
  await expect(b.cell(3)).toBeFocused();
  await b.page.keyboard.press('ArrowRight');
  await expect(b.cell(4)).toBeFocused();
  move = b.waitForMove();
  await b.page.keyboard.press('Space');
  expect((await move).status()).toBe(200);
  await expect(a.cell(4)).toHaveAccessibleName(cellName(4, 'O'));
  await expect(a.cell(0)).toHaveAccessibleName(cellName(0, 'X'));

  // Nova partida e sair são botões alcançáveis por Tab.
  await tabTo(a, a.newGame);
  await tabTo(a, a.leave);
  // O erro de uma recusa é anunciado como alerta.
  await tabTo(b, b.cell(4));
  move = b.waitForMove();
  await b.page.keyboard.press('Enter');
  expect((await move).status()).toBe(409);
  await expect(b.page.getByRole('alert')).toHaveText(ONLINE_MESSAGES.VEZ_DO_OPONENTE);
});

test('OU-22 [CAO-12] dois processos do navegador: partida curta em tempo real', async ({ rooms, baseURL }) => {
  test.setTimeout(60_000);
  const procA = await chromium.launch();
  const procB = await chromium.launch();
  const pa = new Players(procA, baseURL!, rooms);
  const pb = new Players(procB, baseURL!, rooms);
  try {
    const a = await pa.open('A (processo 1)');
    await a.open();
    const code = await a.create();
    const b = await pb.open('B (processo 2)');
    await b.openLink((await a.roomLink.textContent())!);
    await b.acceptInvite(code);
    for (const [n, pos] of S_L1.entries()) {
      const [mover, other] = n % 2 === 0 ? [a, b] : [b, a];
      expect((await mover.click(pos)).status()).toBe(200);
      await expect(other.cell(pos)).toHaveText(n % 2 === 0 ? 'X' : 'O', { timeout: 2000 });
    }
    for (const ui of [a, b]) {
      await ui.expectBoard('XXXOO....');
      await ui.expectWinning([0, 1, 2]);
    }
    await expect(a.status).toHaveText(ONLINE_TEXT.youWon);
    await expect(b.status).toHaveText(ONLINE_TEXT.opponentWon);
    await pa.finish();
    await pb.finish();
  } finally {
    await pa.closeAll();
    await pb.closeAll();
    await procA.close();
    await procB.close();
  }
});
