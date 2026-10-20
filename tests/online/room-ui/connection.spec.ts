import { WebSocketRoute } from '@playwright/test';
import { test, expect } from '../../support/online/ui-fixtures';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { ONLINE_TEXT, youAre } from '../../support/online/online-ui';

/*
 * Grupo OU: saída, desconexão, reconexão, atualização da página e outra aba.
 * As únicas intervenções de rede atuam sobre conexões reais: fechar a página,
 * recarregar e derrubar o canal com page.routeWebSocket + connectToServer
 * (docs/test-plan-online.md, seção 3).
 */

test('OU-14 [CAO-31] o oponente sai: A mostra "Esta sala foi encerrada.", para de reconectar e pode criar outra sala', async ({ players }) => {
  const { a, b, code } = await players.pair();
  await b.leaveRoom();
  for (const ui of [a, b]) {
    await ui.expectState('encerrada');
    await expect(ui.error).toHaveText(ONLINE_MESSAGES.SALA_ENCERRADA);
    await expect(ui.createNewRoom).toBeVisible();
    await ui.expectConnection('parado');
    await ui.expectCellsDisabled(true);
    await expect(ui.newGame).toBeHidden();
    await expect(ui.leave).toBeHidden();
    expect(await ui.storedToken(code), `${ui.name}: token da sala encerrada apagado`).toBeNull();
  }
  const opens = a.wsOpens.length;
  await a.page.waitForTimeout(5000);
  expect(a.wsOpens.length, 'nenhuma tentativa de reconexão em 5 s').toBe(opens);
  const res = await players.rooms.get(code);
  expect(res.status(), 'a sala está encerrada no servidor').toBe(410);

  // "Criar nova sala" cria outra sala, com outro código.
  const created = a.page.waitForResponse((r) => new URL(r.url()).pathname === '/api/rooms');
  await a.createNewRoom.click();
  expect((await created).status()).toBe(201);
  await a.expectState('aguardando');
  await a.expectConnection('conectado');
  const newCode = (await a.roomCode.textContent())!;
  expect(newCode).not.toBe(code);
  await expect(a.error).toBeHidden();
  a.code = newCode;
  b.code = '';
});

test('OU-15 [CAO-32] fechar a aba e voltar pelo link no mesmo navegador', async ({ players }) => {
  const { a, b, code, link } = await players.pair();
  expect((await a.click(0)).status()).toBe(200);
  await b.page.close();
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOffline, { timeout: 2000 });

  const b2 = await players.newTab(b, 'B2');
  await b2.openLink(link);
  await b2.expectState('jogando');
  await b2.expectConnection('conectado');
  await expect(b2.youAre).toHaveText(youAre('O'));
  await b2.expectBoard('X........');
  await expect(b2.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  b2.code = code;
  b2.seat = 'O';
  expect((await b2.click(4)).status()).toBe(200);
  await expect(a.cell(4)).toHaveText('O');
});

test('OU-16 [CAO-34] queda do canal: "Reconectando…", reconexão sozinha e a jogada feita durante a queda', async ({ players }) => {
  const a = await players.open('A');
  await a.open();
  const code = await a.create();
  const link = (await a.roomLink.textContent())!;

  const b = await players.open('B');
  b.networkFailuresExpected = true;
  let down = false;
  const live: Array<{ page: WebSocketRoute; server: WebSocketRoute }> = [];
  await b.page.routeWebSocket(/\/ws$/, (ws) => {
    if (down) {
      // Servidor "fora de alcance" para esta página: a tentativa é recusada.
      ws.close({ code: 1011, reason: 'queda simulada' });
      return;
    }
    const server = ws.connectToServer();
    live.push({ page: ws, server });
  });
  await b.openLink(link);
  await b.acceptInvite(code);
  await a.expectState('jogando');
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  const navigations = b.urls.filter((u) => u.includes('/online.html')).length;
  const gets = b.roomGets.length;

  // Derruba o canal real de B e recusa as novas tentativas.
  down = true;
  for (const c of live.splice(0)) {
    await c.server.close();
    await c.page.close({ code: 1011, reason: 'queda simulada' });
  }
  await expect(b.connection).toHaveText(ONLINE_TEXT.reconnecting);
  await b.expectConnection('reconectando');
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOffline);
  expect((await a.click(4)).status(), 'A joga durante a queda').toBe(200);
  await b.page.waitForTimeout(1500);
  await expect(b.cell(4), 'B ainda não viu a jogada').toHaveText('');

  // Libera: B reconecta sozinho e recebe o estado com a jogada.
  down = false;
  await b.expectConnection('conectado', 15_000);
  await expect(b.connection).toHaveText(ONLINE_TEXT.connected);
  await expect(b.cell(4)).toHaveText('X');
  await expect(b.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  expect(b.urls.filter((u) => u.includes('/online.html')).length, 'sem recarregar a página').toBe(navigations);
  expect(b.roomGets.length, 'o estado veio pelo canal (bem_vindo)').toBe(gets);
  expect((await b.click(0)).status()).toBe(200);
});

test('OU-17 [CAO-35] atualizar a página: B continua O, mesmo tabuleiro, nenhum lugar novo', async ({ players }) => {
  const { a, b, code } = await players.pair();
  expect((await a.click(0)).status()).toBe(200);
  expect((await b.click(4)).status()).toBe(200);
  const token = await b.storedToken(code);
  await b.page.reload();
  await b.expectState('jogando');
  await b.expectConnection('conectado');
  await expect(b.youAre).toHaveText(youAre('O'));
  await b.expectBoard('X...O....');
  await expect(b.status).toHaveText(ONLINE_TEXT.opponentTurn);
  expect(await b.storedToken(code), 'mesmo token').toBe(token);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  const room = await players.rooms.room(code);
  expect(room.situacao).toBe('EM_JOGO');
  expect(room.jogadores.X.ocupado && room.jogadores.O.ocupado).toBe(true);
  expect((await a.click(8)).status()).toBe(200);
  await expect(b.cell(8)).toHaveText('X');
});

test('OU-18 [CAO-36] segunda aba assume o lugar; a primeira oferece "Usar nesta aba", sem reconectar em laço', async ({ players }) => {
  const { a, b, code, link } = await players.pair();
  const startedAt = Date.now();
  const b2 = await players.newTab(b, 'B2');
  await b2.openLink(link);
  await b2.expectState('jogando');
  b2.code = code;
  b2.seat = 'O';
  await b.expectState('substituida');
  await expect(b.error).toHaveText(ONLINE_MESSAGES.SUBSTITUIDA);
  await expect(b.useHere).toBeVisible();
  await b.expectConnection('parado');
  await expect(a.opponent, 'X não vê desconexão').toHaveText(ONLINE_TEXT.opponentOnline);

  // A segunda aba joga normalmente.
  expect((await a.click(0)).status()).toBe(200);
  await expect(b2.cell(0)).toHaveText('X');
  expect((await b2.click(4)).status()).toBe(200);
  await expect(a.cell(4)).toHaveText('O');

  await b.page.waitForTimeout(Math.max(0, 10_000 - (Date.now() - startedAt)));
  const opens = [...b.wsOpens, ...b2.wsOpens].filter((t) => t >= startedAt).length;
  expect(opens, 'aberturas de canal nas duas abas em 10 s').toBeLessThanOrEqual(3);

  // "Usar nesta aba" retoma o lugar na primeira aba; a segunda passa a ser a substituída.
  await b.useHere.click();
  await b.expectState('jogando');
  await b.expectConnection('conectado');
  await b.expectBoard('X...O....');
  await b2.expectState('substituida');
  expect((await a.click(8)).status()).toBe(200);
  await expect(b.cell(8)).toHaveText('X');
});
