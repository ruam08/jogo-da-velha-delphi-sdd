import { APIRequestContext, request as playwrightRequest } from '@playwright/test';
import { test, expect } from '@playwright/test';
import { ONLINE_MESSAGES, Pair, Room, RoomApi, waitingRoom } from '../../support/online/rooms';
import { DedicatedServer, startServer } from '../../support/online/server-process';
import { ServerMessage, WsClient } from '../../support/online/ws-client';
import { ONLINE_TEXT, Players } from '../../support/online/online-ui';
import { coherenceProblem } from '../../support/api';
import { S_EMP } from '../../support/sequences';

/*
 * Entrega O5: ciclo de vida das salas contra o TicTacToeServer.exe real, com
 * servidores dedicados e prazos curtos (DTO-15; docs/plan-online.md, 11.2 e
 * 11.3; docs/test-plan-online.md, OV-01 a OV-03, OV-11, OV-12, OU-28).
 *
 * Regra (plan-online 11.2, v0.7): uma sala é encerrada por abandono quando
 * nenhum lugar está conectado e a última mudança aceita (criação, entrada,
 * jogada, nova partida, conexão, desconexão) tem mais de --room-ttl-seconds;
 * o faxineiro varre a cada --sweep-ms, então o encerramento acontece entre o
 * prazo e o prazo + um intervalo. A sala encerrada responde 410 durante
 * --remember-seconds (contados da varredura que a encerrou) e 404 depois.
 */

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const TOKEN_LIKE = /\b[0-9a-f]{32}\b/;

/** Servidor dedicado + cliente HTTP + clientes WS, liberados no fim. */
async function withServer(name: string, port: number, args: string[],
  body: (s: { server: DedicatedServer; api: RoomApi; ctx: APIRequestContext; clients: WsClient[] }) => Promise<void>): Promise<void> {
  const server = await startServer(name, port, ['--bind', '127.0.0.1', ...args]);
  const ctx = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const clients: WsClient[] = [];
  try {
    await body({ server, api: new RoomApi(ctx), ctx, clients });
  } finally {
    for (const c of clients) c.close();
    await ctx.dispose();
    await server.stop();
  }
}

/** Espera o GET da sala responder `status`; devolve o instante (Date.now) em que respondeu. */
async function waitStatus(api: RoomApi, code: string, status: number, maxMs: number): Promise<number> {
  const deadline = Date.now() + maxMs;
  for (;;) {
    const r = await api.get(code);
    if (r.status() === status) return Date.now();
    if (Date.now() > deadline) throw new Error(`a sala ${code} não respondeu ${status} em ${maxMs} ms (última: ${r.status()})`);
    await sleep(40);
  }
}

/** Ninguém conectado na sala (o servidor já processou os fechamentos). */
async function waitNobodyConnected(api: RoomApi, code: string): Promise<void> {
  await expect.poll(async () => {
    const r = await api.room(code);
    return r.jogadores.X.conectado || r.jogadores.O.conectado;
  }, { message: `sala ${code}: todos desconectados`, timeout: 5000, intervals: [20] }).toBe(false);
}

/** O canal só recebeu pong e estados da própria sala, nunca erro ou sala_encerrada. */
function channelProblems(label: string, code: string, c: WsClient): string[] {
  const out: string[] = [];
  const msgs = c.received.map((r) => r.msg);
  if (!c.isOpen) out.push(`${label}: canal fechado`);
  for (const m of msgs) {
    if (m.tipo === 'erro' || m.tipo === 'sala_encerrada') out.push(`${label}: recebeu ${m.tipo} ${m.codigo ?? ''}`);
    if (m.sala && m.sala.codigo !== code) out.push(`${label}: mensagem da sala ${m.sala.codigo}`);
  }
  const v = msgs.filter((m) => m.sala).map((m) => m.sala!.versao);
  if (!v.every((x, i) => i === 0 || x > v[i - 1])) out.push(`${label}: versões fora de ordem (${v.join(',')})`);
  return out;
}

test('OV-01 [CAO-48] reinício: as salas deixam de existir; tokens antigos não valem; salas novas funcionam', async () => {
  test.setTimeout(60_000);
  const port = 8785;
  let server: DedicatedServer | null = await startServer('ov-01', port, ['--bind', '127.0.0.1']);
  const ctx = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const api = new RoomApi(ctx);
  try {
    const old = await api.pair();
    await api.moveOk(old.code, old.tx, 4);
    const { client } = await WsClient.entered(port, old.code, old.tx);
    await server.stop();
    server = null;
    expect([1006, 1001, 1000]).toContain((await client.waitClosed()).code);

    server = await startServer('ov-01-reiniciado', port, ['--bind', '127.0.0.1']);
    await api.expectError(await api.get(old.code), 404, 'SALA_INEXISTENTE', 'GET depois do reinício');
    await api.expectError(await api.move(old.code, old.tx, 0), 404, 'SALA_INEXISTENTE', 'jogada com token antigo');
    await api.expectError(await api.join(old.code), 404, 'SALA_INEXISTENTE', 'entrar');
    await api.expectError(await api.join(old.code, old.to), 404, 'SALA_INEXISTENTE', 'reentrada com token antigo');
    await api.expectError(await api.reset(old.code, old.tx), 404, 'SALA_INEXISTENTE', 'nova partida');
    await api.expectError(await api.leave(old.code, old.tx), 404, 'SALA_INEXISTENTE', 'sair');
    const late = await WsClient.open(port);
    late.enter(old.code, old.tx);
    expect(await late.next()).toEqual({ tipo: 'erro', codigo: 'SALA_INEXISTENTE', mensagem: ONLINE_MESSAGES.SALA_INEXISTENTE });
    expect((await late.waitClosed()).code).toBe(4404);

    // Depois do reinício, salas novas funcionam, com credenciais novas.
    const fresh = await api.pair();
    expect([fresh.tx, fresh.to]).not.toContain(old.tx);
    expect([fresh.tx, fresh.to]).not.toContain(old.to);
    await api.expectError(await api.move(fresh.code, old.tx, 0), 401, 'TOKEN_INVALIDO', 'token antigo na sala nova');
    await api.moveOk(fresh.code, fresh.tx, 0);
    expect(server.output(), 'nenhum token no log').not.toMatch(TOKEN_LIKE);
  } finally {
    await ctx.dispose();
    if (server) await server.stop();
  }
});

test('OV-02 [CAO-38, CAO-31] abandono: aberta antes do prazo, 410 depois, 404 depois da lembrança; encerrada recusa tudo', async () => {
  test.setTimeout(60_000);
  const port = 8786;
  await withServer('ov-02', port, ['--room-ttl-seconds', '2', '--remember-seconds', '3', '--sweep-ms', '200'], async ({ server, api, clients }) => {
    const a = await api.pair();
    await api.moveOk(a.code, a.tx, 4);
    const x = await WsClient.entered(port, a.code, a.tx);
    const o = await WsClient.entered(port, a.code, a.to);
    clients.push(x.client, o.client);
    x.client.close();
    o.client.close();
    await waitNobodyConnected(api, a.code);
    const t0 = Date.now();   // a última desconexão (mudança aceita) aconteceu um pouco antes

    await sleep(1500);
    expect((await api.get(a.code)).status(), '1,5 s depois da última desconexão: continua aberta').toBe(200);
    const closedAt = await waitStatus(api, a.code, 410, 5000);
    const toClose = closedAt - t0;
    test.info().annotations.push({ type: 'encerramento', description: `${toClose} ms depois da última desconexão (prazo 2.000 ms, varredura 200 ms)` });
    expect(toClose, 'não antes do prazo').toBeGreaterThanOrEqual(1900);
    expect(toClose, 'até o prazo + uma varredura (+ folga)').toBeLessThanOrEqual(2000 + 200 + 800);

    // A sala encerrada recusa tudo, inclusive com os tokens certos.
    await api.expectError(await api.get(a.code), 410, 'SALA_ENCERRADA', 'GET');
    await api.expectError(await api.move(a.code, a.to, 0), 410, 'SALA_ENCERRADA', 'jogada');
    await api.expectError(await api.join(a.code), 410, 'SALA_ENCERRADA', 'entrar');
    await api.expectError(await api.join(a.code, a.tx), 410, 'SALA_ENCERRADA', 'reentrada com o token');
    await api.expectError(await api.reset(a.code, a.tx), 410, 'SALA_ENCERRADA', 'nova partida');
    await api.expectError(await api.leave(a.code, a.tx), 410, 'SALA_ENCERRADA', 'sair');
    const late = await WsClient.open(port);
    clients.push(late);
    late.enter(a.code, a.to);
    expect(await late.next()).toEqual({ tipo: 'erro', codigo: 'SALA_ENCERRADA', mensagem: ONLINE_MESSAGES.SALA_ENCERRADA });
    expect((await late.waitClosed()).code).toBe(4410);

    const forgottenAt = await waitStatus(api, a.code, 404, 6000);
    const remembered = forgottenAt - closedAt;
    test.info().annotations.push({ type: 'lembrança', description: `${remembered} ms com 410 (período 3.000 ms)` });
    expect(remembered, 'lembrada por pelo menos o período').toBeGreaterThanOrEqual(2900);
    expect(remembered, 'esquecida até o período + uma varredura (+ folga)').toBeLessThanOrEqual(3000 + 200 + 800);
    await api.expectError(await api.get(a.code), 404, 'SALA_INEXISTENTE', 'GET depois da lembrança');
    await api.expectError(await api.move(a.code, a.tx, 0), 404, 'SALA_INEXISTENTE', 'jogada depois da lembrança');

    const log = server.output();
    expect(log).toContain(`Sala ${a.code} encerrada por abandono`);
    expect(log).not.toMatch(/ERRO|AVISO|-> 5\d\d/);
    expect(log).not.toMatch(TOKEN_LIKE);
  });
});

test('OV-03 [CAO-38, CAO-37] salas ativas não são encerradas: conectada com ping, um lugar conectado, jogadas só pela API', async () => {
  test.setTimeout(60_000);
  const port = 8787;
  await withServer('ov-03', port, ['--room-ttl-seconds', '2', '--remember-seconds', '3', '--sweep-ms', '200'], async ({ server, api, clients }) => {
    // B: X conectado, sozinho, com ping a cada 1 s.
    const bRoom = await api.create();
    const b = await WsClient.entered(port, bRoom.code, bRoom.token);
    // D: X conectado e O desconectado (entrou pela API, sem canal).
    const d = await api.pair();
    const dx = await WsClient.entered(port, d.code, d.tx);
    clients.push(b.client, dx.client);
    let id = 0;
    const pings = [b.client, dx.client].map((c) => setInterval(() => c.send({ tipo: 'ping', id: ++id }), 1000));
    // C: ninguém conectado, mas com jogadas pela API a cada 600 ms (cada uma é uma mudança aceita).
    const c = await api.pair();
    try {
      for (const [n, pos] of S_EMP.entries()) {
        await api.moveOk(c.code, n % 2 === 0 ? c.tx : c.to, pos);
        for (const code of [bRoom.code, c.code, d.code]) {
          expect((await api.get(code)).status(), `${code} ativa depois de ${n + 1} jogadas de C`).toBe(200);
        }
        await sleep(600);
      }
      const lastMove = Date.now();   // 9 jogadas, 5,4 s: mais que o prazo de 2 s desde a criação
      // Sem mais atividade, C é encerrada cerca de 2 s depois da última jogada; B e D nunca.
      const closedAt = await waitStatus(api, c.code, 410, 5000);
      expect(closedAt - lastMove, 'C: prazo contado da última jogada').toBeGreaterThanOrEqual(1300);
      await sleep(1500);
      expect((await api.get(bRoom.code)).status(), 'B (conectada) continua aberta').toBe(200);
      expect((await api.get(d.code)).status(), 'D (um lugar conectado) continua aberta').toBe(200);
      expect(channelProblems('B', bRoom.code, b.client)).toEqual([]);
      expect(channelProblems('D', d.code, dx.client)).toEqual([]);
      expect(b.client.received.some((r) => r.msg.tipo === 'pong'), 'B recebeu pong').toBe(true);
      // D: O, ausente, ainda pode voltar e jogar (lugar reservado).
      await api.moveOk(d.code, d.tx, 0);
      const back = await WsClient.entered(port, d.code, d.to);
      clients.push(back.client);
      await api.moveOk(d.code, d.to, 4);
    } finally {
      for (const t of pings) clearInterval(t);
    }
    const log = server.output();
    expect(log).toContain(`Sala ${c.code} encerrada por abandono`);
    expect(log).not.toContain(`Sala ${bRoom.code} encerrada`);
    expect(log).not.toContain(`Sala ${d.code} encerrada`);
  });
});

test('OV-11 [CAO-01, CAO-11] sala nova depois de salas encerradas: código, tokens e estado novos; tokens antigos recusados', async () => {
  test.setTimeout(60_000);
  const port = 8788;
  await withServer('ov-11', port, ['--room-ttl-seconds', '1', '--remember-seconds', '30', '--sweep-ms', '100'], async ({ api, clients }) => {
    const left = await api.pair();
    await api.moveOk(left.code, left.tx, 0);
    expect((await api.leave(left.code, left.to)).status()).toBe(200);
    const abandoned = await api.pair();
    await api.moveOk(abandoned.code, abandoned.tx, 8);
    await waitStatus(api, abandoned.code, 410, 4000);
    const oldTokens = [left.tx, left.to, abandoned.tx, abandoned.to];

    for (let i = 0; i < 5; i++) {
      const fresh = await api.create();
      expect([left.code, abandoned.code], 'código novo').not.toContain(fresh.code);
      expect(oldTokens, 'token de X novo').not.toContain(fresh.token);
      expect(fresh.room, 'estado inicial, sem nada da sala anterior').toEqual(waitingRoom(fresh.code));
      // Token de outra sala não identifica ninguém: entra como um O novo, com outro token.
      const joined = await api.join(fresh.code, abandoned.to);
      expect(joined.status()).toBe(201);
      const o = (await joined.json()) as { jogador: { simbolo: string; token: string } };
      expect(o.jogador.simbolo).toBe('O');
      expect(oldTokens).not.toContain(o.jogador.token);
      await api.expectError(await api.move(fresh.code, left.tx, 0), 401, 'TOKEN_INVALIDO', 'token da sala encerrada por saída');
      await api.expectError(await api.move(fresh.code, abandoned.tx, 0), 401, 'TOKEN_INVALIDO', 'token da sala abandonada');
      const ws = await WsClient.open(port);
      clients.push(ws);
      ws.enter(fresh.code, abandoned.tx);
      expect((await ws.next()).codigo).toBe('TOKEN_INVALIDO');
      expect((await ws.waitClosed()).code).toBe(4401);
      expect((await api.room(fresh.code)).versao, 'nenhuma tentativa mudou a sala nova').toBe(2);
    }
    // As antigas continuam encerradas (lembradas): nenhuma voltou a abrir.
    await api.expectError(await api.get(left.code), 410, 'SALA_ENCERRADA', 'sala encerrada por saída');
    await api.expectError(await api.get(abandoned.code), 410, 'SALA_ENCERRADA', 'sala abandonada');
  });
});

test('OV-12 [CAO-25, CAO-38] limpeza concorrente: faxineiro a cada 20 ms com jogadas, canais e entradas na hora do prazo', async () => {
  test.setTimeout(120_000);
  const port = 8792;
  await withServer('ov-12', port, ['--room-ttl-seconds', '1', '--remember-seconds', '1', '--sweep-ms', '20'], async ({ server, api, clients }) => {
    const problems: string[] = [];
    // 8 salas ativas: X e O conectados com ping, jogadas pela API o tempo todo.
    const active: Array<{ pair: Pair; x: WsClient; o: WsClient }> = [];
    for (let i = 0; i < 8; i++) {
      const pair = await api.pair();
      const x = await WsClient.entered(port, pair.code, pair.tx);
      const o = await WsClient.entered(port, pair.code, pair.to);
      clients.push(x.client, o.client);
      active.push({ pair, x: x.client, o: o.client });
    }
    let pingId = 0;
    const pings = active.flatMap((a) => [a.x, a.o]).map((c) => setInterval(() => c.send({ tipo: 'ping', id: ++pingId }), 300));
    const deadline = Date.now() + 10_000;
    let moves = 0;
    const play = async (a: { pair: Pair }) => {
      while (Date.now() < deadline) {
        const room = await api.room(a.pair.code);
        const r = room.partida.status !== 'EM_ANDAMENTO'
          ? await api.reset(a.pair.code, a.pair.tx)
          : await api.move(a.pair.code, room.partida.jogadorDaVez === 'X' ? a.pair.tx : a.pair.to,
            room.partida.tabuleiro.findIndex((c) => c === ''));
        if (r.status() !== 200) problems.push(`${a.pair.code}: ${r.status()} ${await r.text()}`);
        else moves++;
        await sleep(80);
      }
    };
    // Salas abandonadas criadas sem parar; um terço recebe uma tentativa de entrar perto do prazo.
    const abandoned: Array<{ code: string; token: string; createdAt: number; attached: boolean }> = [];
    const races: Promise<void>[] = [];
    let attachedOk = 0;
    let refused = 0;
    const race = async (r: { code: string; token: string; attached: boolean }) => {
      const c = await WsClient.open(port);
      clients.push(c);
      c.enter(r.code, r.token);
      let m: ServerMessage;
      try {
        m = await c.next((x) => x.tipo === 'bem_vindo' || x.tipo === 'erro', 3000);
      } catch (e) {
        problems.push(`${r.code}: entrar sem resposta (${(e as Error).message.slice(0, 80)})`);
        return;
      }
      if (m.tipo === 'bem_vindo') {
        // Conectou antes do encerramento: enquanto conectado, a sala não pode ser encerrada.
        r.attached = true;
        attachedOk++;
        const ping = setInterval(() => c.send({ tipo: 'ping', id: 1 }), 300);
        await sleep(1800);
        clearInterval(ping);
        const st = (await api.get(r.code)).status();
        if (st !== 200) problems.push(`${r.code}: conectada e mesmo assim ${st}`);
        problems.push(...channelProblems(`conectada ${r.code}`, r.code, c));
        c.close();
      } else {
        refused++;
        if (m.codigo !== 'SALA_ENCERRADA') problems.push(`${r.code}: recusa inesperada ${m.codigo}`);
        const info = await c.waitClosed();
        if (info.code !== 4410) problems.push(`${r.code}: fechamento ${info.code}`);
        const st = (await api.get(r.code)).status();
        if (st !== 410 && st !== 404) problems.push(`${r.code}: recusada pelo canal, mas GET ${st}`);
      }
    };
    const churn = async () => {
      let n = 0;
      while (Date.now() < deadline - 2000) {
        const created = await api.create(false);
        const r = { code: created.code, token: created.token, createdAt: Date.now(), attached: false };
        abandoned.push(r);
        if (n++ % 3 === 0) {
          const wait = 850 + Math.floor(Math.random() * 400);   // 0,85 a 1,25 s depois de criar (prazo: 1 s)
          races.push(sleep(wait).then(() => race(r)));
        }
        await sleep(40);
      }
    };
    await Promise.all([...active.map(play), churn()]);
    await Promise.all(races);
    for (const t of pings) clearInterval(t);

    // Salas ativas: abertas, canais vivos, só mensagens da própria sala, em ordem, último estado = GET.
    for (const a of active) {
      const final: Room = await api.room(a.pair.code);
      for (const [label, c] of [['X', a.x], ['O', a.o]] as const) {
        await expect.poll(() => c.lastRoom()?.versao, { message: `${a.pair.code}/${label}: versão final`, timeout: 3000 }).toBe(final.versao);
        problems.push(...channelProblems(`${a.pair.code}/${label}`, a.pair.code, c));
        for (const m of c.received.map((r) => r.msg).filter((m) => m.sala)) {
          const p = coherenceProblem(m.sala!.partida);
          if (p) problems.push(`${a.pair.code}/${label}: estado incoerente ${p}`);
        }
      }
    }
    // Salas abandonadas (sem conexão), criadas há mais de 1,5 s: encerradas ou já esquecidas.
    const end = Date.now();
    let checked = 0;
    for (const r of abandoned.filter((x) => !x.attached && end - x.createdAt > 1500)) {
      const st = (await api.get(r.code)).status();
      if (st !== 410 && st !== 404) problems.push(`${r.code}: abandonada há ${end - r.createdAt} ms e ${st}`);
      checked++;
    }
    const log = server.output();
    const closedLines = (log.match(/encerrada por abandono/g) ?? []).length;
    for (const a of active) if (log.includes(`Sala ${a.pair.code} encerrada`)) problems.push(`${a.pair.code}: ativa encerrada no log`);
    if (/ERRO|AVISO|-> 5\d\d/.test(log)) problems.push('log do servidor com erro, aviso ou 5xx');
    if (TOKEN_LIKE.test(log)) problems.push('token no log do servidor');
    test.info().annotations.push({ type: 'limpeza concorrente',
      description: `${moves} jogadas em 8 salas ativas; ${abandoned.length} salas abandonadas (${checked} conferidas); ` +
        `${races.length} entradas no prazo: ${attachedOk} conectaram, ${refused} recusadas (4410); ${closedLines} encerramentos no log` });
    expect(problems, 'problemas').toEqual([]);
    expect(moves, 'houve jogadas nas salas ativas').toBeGreaterThan(200);
    expect(closedLines, 'o faxineiro encerrou salas durante o teste').toBeGreaterThan(50);
  });
});

test('OU-28 [CAO-38, CAO-31] interface: os dois saem, a sala é encerrada por abandono; o link mostra "encerrada" e "Criar nova sala" gera credenciais novas', async ({ browser }) => {
  test.setTimeout(90_000);
  const port = 8789;
  const server = await startServer('ou-28', port, ['--bind', '127.0.0.1', '--room-ttl-seconds', '2', '--remember-seconds', '60', '--sweep-ms', '200']);
  const ctx = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const api = new RoomApi(ctx);
  const players = new Players(browser, server.baseURL, api);
  try {
    const { a, b, code, link } = await players.pair();
    expect((await a.click(4)).status()).toBe(200);
    const oldA = (await a.storedToken(code))!;
    const oldB = (await b.storedToken(code))!;
    // Enquanto as páginas estão abertas (conectadas), a sala não expira.
    await sleep(3000);
    expect((await api.get(code)).status(), 'páginas abertas: sala aberta').toBe(200);
    await expect(a.connection).toHaveText(ONLINE_TEXT.connected);
    // Os dois fecham as abas.
    await a.page.close();
    await b.page.close();
    await waitNobodyConnected(api, code);
    await waitStatus(api, code, 410, 6000);

    // A reabre o link no mesmo navegador: a página informa e para.
    const a2 = await players.newTab(a, 'A2');
    await a2.openLink(link);
    await a2.expectState('encerrada');
    await expect(a2.error).toHaveText(ONLINE_MESSAGES.SALA_ENCERRADA);
    await expect(a2.createNewRoom).toBeVisible();
    await a2.expectConnection('parado');
    expect(await a2.storedToken(code), 'token da sala encerrada apagado').toBeNull();
    // "Criar nova sala": sala e credenciais novas.
    const created = a2.page.waitForResponse((r) => new URL(r.url()).pathname === '/api/rooms');
    await a2.createNewRoom.click();
    expect((await created).status()).toBe(201);
    await a2.expectState('aguardando');
    await a2.expectConnection('conectado');
    const newCode = (await a2.roomCode.textContent())!;
    expect(newCode).not.toBe(code);
    const newToken = await a2.storedToken(newCode);
    expect(newToken).toMatch(/^[0-9a-f]{32}$/);
    expect([oldA, oldB]).not.toContain(newToken);
    a2.code = newCode;
    a2.seat = 'X';
    // B reabre o link antigo: também vê a sala encerrada.
    const b2 = await players.newTab(b, 'B2');
    await b2.openLink(link);
    await b2.expectState('encerrada');
    expect(await b2.storedToken(code)).toBeNull();
    await players.finish();
    expect(server.output()).toContain(`Sala ${code} encerrada por abandono`);
  } finally {
    await players.closeAll();
    await ctx.dispose();
    await server.stop();
  }
});
