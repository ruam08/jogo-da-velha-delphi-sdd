import * as os from 'node:os';
import { request as playwrightRequest } from '@playwright/test';
import { test, expect } from '@playwright/test';
import { ONLINE_MESSAGES, RoomApi } from '../../support/online/rooms';
import { DedicatedServer, startServer } from '../../support/online/server-process';
import { ONLINE_TEXT, Players, youAre } from '../../support/online/online-ui';
import { S_L1 } from '../../support/sequences';

/*
 * Interface online com servidores dedicados (DTO-15), no Chromium:
 *  - OU-23: servidor parado e reiniciado durante a partida (falha de
 *    comunicação prolongada e salas que deixam de existir);
 *  - OV-10: partida entre um navegador pelo IP da rede local e outro por
 *    127.0.0.1, com o servidor no bind padrão (0.0.0.0).
 */

/** IPv4 privado de uma interface desta máquina (10/8, 172.16/12, 192.168/16), ou null. */
function privateIPv4(): string | null {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family !== 'IPv4' || a.internal) continue;
      const [p0, p1] = a.address.split('.').map(Number);
      if (p0 === 10 || (p0 === 172 && p1 >= 16 && p1 <= 31) || (p0 === 192 && p1 === 168)) return a.address;
    }
  }
  return null;
}

test('OU-23 [CAO-49] servidor parado e reiniciado: "Reconectando…", "Sem conexão com o servidor." e depois "Sala não encontrada"', async ({ browser }) => {
  test.setTimeout(150_000);
  const port = 8783;
  let server: DedicatedServer | null = await startServer('ou-23', port);
  const api = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const players = new Players(browser, server.baseURL, new RoomApi(api));
  try {
    const { a, b, code } = await players.pair();
    expect((await a.click(0)).status()).toBe(200);
    for (const ui of [a, b]) ui.networkFailuresExpected = true;

    await server.stop();
    server = null;
    for (const ui of [a, b]) {
      await expect(ui.connection, `${ui.name}: reconectando`).toHaveText(ONLINE_TEXT.reconnecting);
      await ui.expectConnection('reconectando');
    }
    // Depois de 30 s sem conseguir: aviso e botão "Reconectar agora"; as tentativas continuam.
    for (const ui of [a, b]) {
      await expect(ui.connection, `${ui.name}: sem conexão`).toHaveText(ONLINE_TEXT.offline, { timeout: 40_000 });
      await ui.expectConnection('offline');
      await expect(ui.reconnect).toBeVisible();
    }
    await expect(a.status, 'o último estado continua na tela').toHaveText(ONLINE_TEXT.opponentTurn);

    server = await startServer('ou-23-reiniciado', port);
    await a.reconnect.click();   // A tenta na hora; B espera a próxima tentativa (até ~12 s)
    for (const ui of [a, b]) {
      await ui.expectState('inexistente', 20_000);
      await expect(ui.error).toHaveText(ONLINE_MESSAGES.SALA_INEXISTENTE);
      await expect(ui.hint).toHaveText(ONLINE_TEXT.restartHint);
      await expect(ui.createNewRoom).toBeVisible();
      await ui.expectConnection('parado');
      expect(await ui.storedToken(code), `${ui.name}: a sala saiu do navegador`).toBeNull();
    }
    const opens = [a.wsOpens.length, b.wsOpens.length];
    await a.page.waitForTimeout(15_000);
    expect([a.wsOpens.length, b.wsOpens.length], 'nenhuma abertura de canal nos 15 s seguintes').toEqual(opens);
    a.code = '';
    b.code = '';
    await players.finish();
    expect(server.output(), 'nenhum token no log do servidor').not.toMatch(/\b[0-9a-f]{32}\b/);
  } finally {
    await players.closeAll();
    await api.dispose();
    if (server) await server.stop();
  }
});

test('OV-10 [CAO-56] partida pelo IP da rede local: A pelo IP privado, B por 127.0.0.1', async ({ browser }) => {
  test.setTimeout(60_000);
  const ip = privateIPv4();
  expect(ip, 'sem rede local: esta máquina não tem IPv4 privado').not.toBeNull();
  test.info().annotations.push({ type: 'IPv4 privado', description: ip! });
  const port = 8784;
  const server = await startServer('ov-10', port);   // bind padrão: 0.0.0.0
  const api = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const rooms = new RoomApi(api);
  const lan = new Players(browser, `http://${ip}:${port}`, rooms);
  const local = new Players(browser, server.baseURL, rooms);
  try {
    const a = await lan.open('A (rede local)');
    await a.open();
    const code = await a.create();
    const link = (await a.roomLink.textContent())!;
    expect(link, 'o link usa o endereço por onde a página foi aberta').toBe(`http://${ip}:${port}/online.html?sala=${code}`);

    const b = await local.open('B (127.0.0.1)');
    await b.open(`/online.html?sala=${code}`);
    await b.expectState('convite');
    await b.acceptInvite(code);
    await expect(b.youAre).toHaveText(youAre('O'));
    await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
    for (const [n, pos] of S_L1.entries()) {
      const [mover, other] = n % 2 === 0 ? [a, b] : [b, a];
      expect((await mover.click(pos)).status()).toBe(200);
      await expect(other.cell(pos)).toHaveText(n % 2 === 0 ? 'X' : 'O', { timeout: 2000 });
    }
    await expect(a.status).toHaveText(ONLINE_TEXT.youWon);
    await expect(b.status).toHaveText(ONLINE_TEXT.opponentWon);
    await lan.finish();
    await local.finish();
    const log = server.output();
    expect(log, 'nenhuma recusa de origem').not.toContain('Origem recusada');
    expect(log).toContain(`http://${ip}:${port}`);
  } finally {
    await lan.closeAll();
    await local.closeAll();
    await rooms.cleanup();
    await api.dispose();
    await server.stop();
  }
});
