import { request as playwrightRequest } from '@playwright/test';
import { test, expect } from '@playwright/test';
import { coherenceProblem } from '../../support/api';
import { Pair, Room, RoomApi } from '../../support/online/rooms';
import { startServer } from '../../support/online/server-process';
import { WsClient } from '../../support/online/ws-client';

/*
 * OW-19 (novo na O3; critério de conclusão da O3 no plano: repete o E0-06 da
 * prova de conceito com o servidor real): 50 canais (25 salas, X e O
 * conectados) por 30 s, com jogadas por REST em todas as salas e ping a cada
 * 5 s. Nenhum canal pode cair, nenhuma mensagem pode ser de outra sala, as
 * versões chegam em ordem e o último estado de cada canal é igual ao GET.
 */

test('OW-19 [CAO-25] 50 canais por 30 s com jogadas em 25 salas: sem quedas, sem mistura, em ordem', async () => {
  test.setTimeout(120_000);
  const server = await startServer('ow-19', 8779, ['--bind', '127.0.0.1']);
  const context = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const clients: WsClient[] = [];
  const timers: NodeJS.Timeout[] = [];
  try {
    const api = new RoomApi(context);
    const pairs: Pair[] = [];
    const channels: Array<{ pair: Pair; mark: 'X' | 'O'; client: WsClient }> = [];
    for (let i = 0; i < 25; i++) {
      const pair = await api.pair();
      pairs.push(pair);
      for (const mark of ['X', 'O'] as const) {
        const { client } = await WsClient.entered(server.port, pair.code, mark === 'X' ? pair.tx : pair.to);
        clients.push(client);
        channels.push({ pair, mark, client });
      }
    }
    expect(clients.length).toBe(50);
    let pingId = 0;
    for (const c of clients) timers.push(setInterval(() => c.send({ tipo: 'ping', id: ++pingId }), 5000));

    // 30 s de jogadas: em cada sala, quem está na vez joga numa célula livre; no fim da partida, nova partida.
    const deadline = Date.now() + 30_000;
    let moves = 0;
    let resets = 0;
    const problems: string[] = [];
    while (Date.now() < deadline) {
      await Promise.all(pairs.map(async (pair) => {
        const room = await api.room(pair.code);
        if (room.partida.status !== 'EM_ANDAMENTO') {
          const r = await api.reset(pair.code, pair.tx);
          if (r.status() !== 200) problems.push(`${pair.code}: nova partida ${r.status()}`);
          else resets++;
          return;
        }
        const free = room.partida.tabuleiro.map((c, i) => (c === '' ? i : -1)).filter((i) => i >= 0);
        const pos = free[Math.floor(Math.random() * free.length)];
        const token = room.partida.jogadorDaVez === 'X' ? pair.tx : pair.to;
        const r = await api.move(pair.code, token, pos);
        if (r.status() !== 200) problems.push(`${pair.code}: jogada ${r.status()} ${await r.text()}`);
        else moves++;
      }));
      await new Promise((r) => setTimeout(r, 300));
    }
    for (const t of timers) clearInterval(t);

    // Cada canal termina com o estado atual da sua sala, sem mensagens de outra sala.
    for (const ch of channels) {
      const final: Room = await api.room(ch.pair.code);
      await expect.poll(() => ch.client.lastRoom()?.versao, { message: `${ch.pair.code}/${ch.mark}: versão final`, timeout: 3000 }).toBe(final.versao);
      const msgs = ch.client.received.map((r) => r.msg);
      if (!ch.client.isOpen) problems.push(`${ch.pair.code}/${ch.mark}: canal caiu`);
      if (msgs.some((m) => m.tipo === 'erro' || m.tipo === 'sala_encerrada')) problems.push(`${ch.pair.code}/${ch.mark}: erro ou encerramento`);
      const withRoom = msgs.filter((m) => m.sala);
      if (withRoom.some((m) => m.sala!.codigo !== ch.pair.code)) problems.push(`${ch.pair.code}/${ch.mark}: mensagem de outra sala`);
      const v = withRoom.map((m) => m.sala!.versao);
      if (!v.every((x, i) => i === 0 || x > v[i - 1])) problems.push(`${ch.pair.code}/${ch.mark}: versões fora de ordem`);
      for (const m of withRoom) {
        const p = coherenceProblem(m.sala!.partida);
        if (p) problems.push(`${ch.pair.code}/${ch.mark}: estado incoerente (${p})`);
      }
      if (JSON.stringify(ch.client.lastRoom()) !== JSON.stringify(final)) problems.push(`${ch.pair.code}/${ch.mark}: último estado diferente do GET`);
      if (!msgs.some((m) => m.tipo === 'pong')) problems.push(`${ch.pair.code}/${ch.mark}: nenhum pong`);
    }
    const received = clients.reduce((n, c) => n + c.count, 0);
    test.info().annotations.push({ type: 'carga', description: `50 canais, ${moves} jogadas, ${resets} novas partidas, ${received} mensagens recebidas` });
    expect(moves, 'houve jogadas').toBeGreaterThan(500);
    expect(problems, 'problemas').toEqual([]);
    const log = server.output();
    expect(log, 'nenhum erro no log do servidor').not.toMatch(/ERRO|-> 5\d\d/);
    expect((log.match(/WS \d+ aberta/g) ?? []).length, 'canais abertos no log').toBe(50);
  } finally {
    for (const t of timers) clearInterval(t);
    for (const c of clients) c.close();
    await context.dispose();
    await server.stop();
  }
});
