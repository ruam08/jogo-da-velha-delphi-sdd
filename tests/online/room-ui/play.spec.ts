import { test, expect } from '../../support/online/ui-fixtures';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { ONLINE_TEXT, OnlineUi } from '../../support/online/online-ui';
import { S_EMP, S_L1, WINS } from '../../support/sequences';

/*
 * Grupo OU: jogadas, sincronização e autoridade do servidor.
 * Prova de que a sincronização é por notificação (seção 3, item 5): a página
 * de quem não jogou não é clicada nem recarregada, e não faz GET da sala.
 */

const S_DUP = WINS.find((w) => w.id === 'R-18')!.moves; // X vence com as duas diagonais
const S_L3 = WINS.find((w) => w.id === 'R-11')!.moves;  // O vence na linha 6-7-8

/** Marca, na página `ui`, o horário (Date.now) em que a célula `i` ganha conteúdo. */
async function watchCell(ui: OnlineUi, i: number): Promise<void> {
  await ui.page.evaluate((i) => {
    const w = window as unknown as { __seenAt: number };
    const el = document.querySelector(`[data-testid="cell-${i}"]`)!;
    w.__seenAt = 0;
    new MutationObserver((_, obs) => {
      if (el.textContent) {
        w.__seenAt = Date.now();
        obs.disconnect();
      }
    }).observe(el, { childList: true, characterData: true, subtree: true });
  }, i);
}

test('OU-06 [CAO-12] cada jogada aparece no outro navegador em até 2 s, sem GET de sala e sem clique', async ({ players }) => {
  const { a, b } = await players.pair();
  const latencies: number[] = [];
  for (const [n, pos] of S_EMP.entries()) {
    const [mover, other] = n % 2 === 0 ? [a, b] : [b, a];
    const symbol = n % 2 === 0 ? 'X' : 'O';
    const getsBefore = other.roomGets.length;
    await watchCell(other, pos);
    const res = mover.waitForMove();
    await mover.clickCell(pos);
    const r = await res;
    const answeredAt = Date.now();
    expect(r.status(), `jogada ${n + 1}`).toBe(200);
    await expect(other.cell(pos), `jogada ${n + 1} na outra página`).toHaveText(symbol, { timeout: 2000 });
    const seenAt = await other.page.evaluate(() => (window as unknown as { __seenAt: number }).__seenAt);
    latencies.push(Math.max(0, seenAt - answeredAt));
    expect(other.roomGets.length, `jogada ${n + 1}: a outra página não consultou a sala`).toBe(getsBefore);
    await mover.waitIdle();
  }
  await a.expectBoard('XOXXOOOXX');
  await b.expectBoard('XOXXOOOXX');
  await expect(a.status).toHaveText(ONLINE_TEXT.draw);
  await expect(b.status).toHaveText(ONLINE_TEXT.draw);
  const sorted = [...latencies].sort((x, y) => x - y);
  const p95 = sorted[Math.ceil(0.95 * sorted.length) - 1];
  test.info().annotations.push({ type: 'latência (ms)', description: `${latencies.join(', ')}; p95 ${p95}` });
});

test('OU-07 [CAO-13] resultado idêntico: vitória com duas diagonais e, em outra sala, empate', async ({ players }) => {
  const first = await players.pair();
  for (const [n, pos] of S_DUP.entries()) {
    const mover = n % 2 === 0 ? first.a : first.b;
    expect((await mover.click(pos)).status(), `jogada ${n + 1}`).toBe(200);
  }
  for (const ui of [first.a, first.b]) {
    await ui.expectBoard('XOXOXOXOX');
    await ui.expectWinning([0, 2, 4, 6, 8]);
    await ui.expectCellsDisabled(true);
    await ui.expectState('finalizada');
  }
  await expect(first.a.status).toHaveText(ONLINE_TEXT.youWon);
  await expect(first.b.status).toHaveText(ONLINE_TEXT.opponentWon);

  const second = await players.pair();
  for (const [n, pos] of S_EMP.entries()) {
    const mover = n % 2 === 0 ? second.a : second.b;
    expect((await mover.click(pos)).status()).toBe(200);
  }
  for (const ui of [second.a, second.b]) {
    await ui.expectBoard('XOXXOOOXX');
    await ui.expectWinning([]);
    await expect(ui.status).toHaveText(ONLINE_TEXT.draw);
  }
});

test('OU-08 [CAO-14] o oponente entra pela API e conecta pelo canal: A atualiza sem recarregar nem consultar', async ({ players, ws }) => {
  const a = await players.open('A');
  await a.open();
  const code = await a.create();
  const getsBefore = a.roomGets.length;
  const joined = await players.rooms.joinOk(code);
  await a.expectState('jogando');
  await expect(a.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(a.opponent, 'O ocupado, ainda sem canal').toHaveText(ONLINE_TEXT.opponentOffline);
  await ws.entered(code, joined.token);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  expect(a.roomGets.length, 'nenhum GET de sala na página de A').toBe(getsBefore);
});

test('OU-09 [CAO-26] a interface espera o servidor: com a resposta atrasada em 1 s, a célula continua vazia', async ({ players }) => {
  const { a, b } = await players.pair();
  await a.page.route('**/api/rooms/*/moves', async (route) => {
    await new Promise((r) => setTimeout(r, 1000));
    await route.continue();
  });
  const res = a.waitForMove();
  await a.clickCell(0);
  await expect(a.board).toHaveAttribute('aria-busy', 'true');
  await expect(a.cell(0)).toHaveText('');
  await a.page.waitForTimeout(500);
  await expect(a.cell(0), 'meio segundo depois do clique, ainda vazia').toHaveText('');
  await expect(b.cell(0)).toHaveText('');
  expect((await res).status()).toBe(200);
  await expect(a.cell(0)).toHaveText('X');
  await expect(b.cell(0)).toHaveText('X');
  await a.waitIdle();
  await a.page.unroute('**/api/rooms/*/moves');
});

test('OU-10 [CAO-16, CAO-26] clique fora da vez vai ao servidor; a recusa aparece e some no próximo estado', async ({ players }) => {
  const { a, b } = await players.pair();
  const r = await b.click(4);
  expect(r.status(), 'o POST acontece e o servidor recusa').toBe(409);
  await expect(b.error).toHaveText(ONLINE_MESSAGES.VEZ_DO_OPONENTE);
  await a.expectBoard('.........');
  await b.expectBoard('.........');
  expect((await a.click(0)).status()).toBe(200);
  await expect(b.cell(0)).toHaveText('X');
  await expect(b.error, 'a mensagem some com o estado novo').toBeHidden();

  // Célula ocupada e partida encerrada também são decididas pelo servidor.
  const occupied = await b.click(0);
  expect(occupied.status()).toBe(409);
  await expect(b.error).toHaveText(ONLINE_MESSAGES.CELULA_OCUPADA);
  expect((await b.click(3)).status()).toBe(200);
  await expect(b.error).toBeHidden();
});

test('OU-11 [CAO-27] estado montado pelo servidor: partida inteira pela API, as páginas só mostram', async ({ players }) => {
  const { a, b, code } = await players.pair();
  const tx = (await a.storedToken(code))!;
  const to = (await b.storedToken(code))!;
  const gets = [a.roomGets.length, b.roomGets.length];
  await players.rooms.playSequence({ code, tx, to, room: await players.rooms.room(code) }, S_L3);
  for (const ui of [a, b]) {
    await ui.expectBoard('XX..X.OOO');
    await ui.expectWinning([6, 7, 8]);
  }
  await expect(a.status).toHaveText(ONLINE_TEXT.opponentWon);
  await expect(b.status).toHaveText(ONLINE_TEXT.youWon);
  expect([a.roomGets.length, b.roomGets.length], 'nenhum GET de sala').toEqual(gets);
});

test('OU-19 [CAO-39, CAO-40] nova partida depois do fim; recusada com a partida em andamento', async ({ players }) => {
  const { a, b } = await players.pair();
  for (const [n, pos] of S_L1.entries()) {
    expect((await (n % 2 === 0 ? a : b).click(pos)).status()).toBe(200);
  }
  await expect(a.status).toHaveText(ONLINE_TEXT.youWon);
  expect((await b.clickNewGame()).status()).toBe(200);
  for (const ui of [a, b]) {
    await ui.expectBoard('.........');
    await expect(ui.gameNumber).toHaveText('Partida 2');
    await ui.expectWinning([]);
  }
  await expect(a.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(b.status).toHaveText(ONLINE_TEXT.opponentTurn);

  expect((await a.click(0)).status()).toBe(200);
  const refused = await a.clickNewGame();
  expect(refused.status()).toBe(409);
  await expect(a.error).toHaveText(ONLINE_MESSAGES.PARTIDA_EM_ANDAMENTO);
  await a.expectBoard('X........');
  await b.expectBoard('X........');
});

test('OU-27 [CAO-12] falha de comunicação: mensagem clara, nada muda e a próxima ação funciona', async ({ players }) => {
  const { a, b } = await players.pair();
  a.networkFailuresExpected = true;
  await a.page.route('**/api/rooms/*/moves', (route) => route.abort('connectionrefused'));
  await a.clickCell(0);
  await expect(a.error).toHaveText(ONLINE_TEXT.network);
  await a.waitIdle();
  await a.expectBoard('.........');
  await b.expectBoard('.........');
  await expect(a.connection, 'o canal continua conectado').toHaveText(ONLINE_TEXT.connected);
  await a.page.unroute('**/api/rooms/*/moves');
  expect((await a.click(0)).status()).toBe(200);
  await expect(a.error).toBeHidden();
  await expect(b.cell(0)).toHaveText('X');

  // Criar sala sem servidor: mensagem e a tela inicial continua.
  const c = await players.open('C');
  c.networkFailuresExpected = true;
  await c.open();
  await c.page.route('**/api/rooms', (route) => route.abort('connectionrefused'));
  await c.createRoom.click();
  await expect(c.error).toHaveText(ONLINE_TEXT.network);
  await c.expectState('inicio');
  await c.page.unroute('**/api/rooms');
});
