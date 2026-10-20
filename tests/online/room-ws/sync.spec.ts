import { test, expect } from '../../support/online/fixtures';
import { coherenceProblem } from '../../support/api';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { ServerMessage, WsClient } from '../../support/online/ws-client';
import { S_L1, WINS } from '../../support/sequences';

/*
 * Grupo OW: notificações em tempo real. Toda mudança é feita por REST
 * (DTO-02); os clientes só observam o canal, sem consultar a sala, e o
 * resultado é comparado com GET /api/rooms/{código}.
 */

const S_9A = WINS.find((w) => w.id === 'R-17')!.moves;   // 9 jogadas, vitória na última

function versions(msgs: ServerMessage[]): number[] {
  return msgs.map((m) => m.sala!.versao);
}

function strictlyIncreasing(v: number[]): boolean {
  return v.every((x, i) => i === 0 || x > v[i - 1]);
}

test('OW-04 [CAO-12, CAO-15] X joga por REST: X e O recebem estado JOGADA com a versão seguinte', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const x = await ws.entered(pair.code, pair.tx);
  const o = await ws.entered(pair.code, pair.to);
  await x.client.next((m) => m.tipo === 'estado' && m.motivo === 'CONEXAO');   // O conectou
  const before = await rooms.room(pair.code);
  const t0 = Date.now();
  const after = await rooms.moveOk(pair.code, pair.tx, 4);
  for (const [label, c] of [['X', x.client], ['O', o.client]] as const) {
    const msg = await c.next((m) => m.tipo === 'estado' && m.motivo === 'JOGADA', 2000);
    expect(msg.sala!.versao, `${label}: versão`).toBe(before.versao + 1);
    expect(msg.sala, `${label}: sala igual à resposta da jogada`).toEqual(after);
  }
  expect(Date.now() - t0, 'notificação em até 2 s').toBeLessThan(2000);
  expect(await rooms.room(pair.code)).toEqual(after);
});

test('OW-05 [CAO-15] 9 jogadas por REST: versões estritamente crescentes; o último estado é igual ao GET', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const x = await ws.entered(pair.code, pair.tx);
  const o = await ws.entered(pair.code, pair.to);
  const final = await rooms.playSequence(pair, S_9A);
  expect(final.partida.status).toBe('VITORIA');
  for (const [label, c] of [['X', x.client], ['O', o.client]] as const) {
    await expect.poll(() => c.lastRoom()?.versao, { message: `${label}: último estado`, timeout: 3000 }).toBe(final.versao);
    const states = c.states();
    expect(strictlyIncreasing(versions(states)), `${label}: versões ${versions(states).join(',')}`).toBe(true);
    expect(c.lastRoom(), `${label}: último estado = GET`).toEqual(await rooms.room(pair.code));
    for (const s of states) expect(coherenceProblem(s.sala!.partida), `${label}: estado coerente`).toBeNull();
  }
});

test('OW-06 [CAO-14] X conectado numa sala sem O: a entrada de O chega como estado ENTRADA', async ({ rooms, ws }) => {
  const created = await rooms.create();
  const x = await ws.entered(created.code, created.token);
  const v = x.welcome.sala!.versao;
  const joined = await rooms.joinOk(created.code);
  const msg = await x.client.next((m) => m.tipo === 'estado', 2000);
  expect(msg.motivo).toBe('ENTRADA');
  expect(msg.sala!.situacao).toBe('EM_JOGO');
  expect(msg.sala!.versao).toBe(v + 1);
  expect(msg.sala).toEqual(joined.room);
  expect(JSON.stringify(msg), 'a notificação não contém o token de O').not.toContain(joined.token);
});

test('OW-07 [CAO-10] clientes de S2 não recebem nada do que acontece em S1', async ({ rooms, ws }) => {
  const s1 = await rooms.create();
  const x1 = await ws.entered(s1.code, s1.token);
  const s2 = await rooms.pair();
  const x2 = await ws.entered(s2.code, s2.tx);
  const o2 = await ws.entered(s2.code, s2.to);
  await x2.client.next((m) => m.tipo === 'estado' && m.motivo === 'CONEXAO');
  const startX2 = x2.client.count;
  const startO2 = o2.client.count;

  const o1 = await rooms.joinOk(s1.code);
  const pairS1 = { code: s1.code, tx: s1.token, to: o1.token, room: o1.room };
  await rooms.playSequence(pairS1, S_L1);
  expect((await rooms.reset(s1.code, s1.token)).status()).toBe(200);
  expect((await rooms.leave(s1.code, o1.token)).status()).toBe(200);
  await x1.client.next((m) => m.tipo === 'sala_encerrada', 2000);

  await new Promise((r) => setTimeout(r, 300));
  expect(x2.client.since(startX2), 'X de S2 não recebeu nada').toEqual([]);
  expect(o2.client.since(startO2), 'O de S2 não recebeu nada').toEqual([]);
  // S1 recebeu o roteiro (estados intermediários podem ser aglutinados, nunca fora de ordem)
  // e terminou com sala_encerrada e o fechamento 4410.
  const msgs = x1.client.received.map((r) => r.msg);
  expect(msgs[0].tipo).toBe('bem_vindo');
  expect(msgs[msgs.length - 1].tipo).toBe('sala_encerrada');
  expect(msgs[msgs.length - 1].sala!.motivoEncerramento).toBe('SAIDA');
  const v = msgs.map((m) => m.sala!.versao);
  expect(strictlyIncreasing(v), `versões em S1: ${v.join(',')}`).toBe(true);
  expect(msgs.every((m) => m.sala!.codigo === s1.code), 'só mensagens de S1').toBe(true);
  expect((await x1.client.waitClosed()).code).toBe(4410);
});

test('OW-12 [CAO-32] O fecha o canal (normal ou queda): X recebe DESCONEXAO; o lugar continua ocupado', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const x = await ws.entered(pair.code, pair.tx);
  const o = await ws.entered(pair.code, pair.to);
  await x.client.next((m) => m.motivo === 'CONEXAO');
  o.client.close(1000);
  const msg = await x.client.next((m) => m.tipo === 'estado', 2000);
  expect(msg.motivo).toBe('DESCONEXAO');
  expect(msg.sala!.jogadores.O).toEqual({ ocupado: true, conectado: false });
  expect(msg.sala).toEqual(await rooms.room(pair.code));

  // Queda sem quadro de fechamento (socket cru destruído).
  const raw = await ws.raw();
  raw.sendJson({ tipo: 'entrar', protocolo: 1, sala: pair.code, token: pair.to });
  await raw.waitFor(() => raw.texts().some((m) => m.tipo === 'bem_vindo'), 3000, 'bem_vindo');
  expect((await x.client.next((m) => m.tipo === 'estado', 2000)).motivo).toBe('CONEXAO');
  raw.destroy();
  const drop = await x.client.next((m) => m.tipo === 'estado', 3000);
  expect(drop.motivo, 'queda abrupta detectada').toBe('DESCONEXAO');
  expect(drop.sala!.jogadores.O.ocupado).toBe(true);
});

test('OW-14 [CAO-36] O abre outro canal: o primeiro recebe SUBSTITUIDA (4000); X não vê desconexão', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const x = await ws.entered(pair.code, pair.tx);
  const o1 = await ws.entered(pair.code, pair.to);
  await x.client.next((m) => m.motivo === 'CONEXAO');
  const startX = x.client.count;
  const o2 = await ws.entered(pair.code, pair.to);
  expect(await o1.client.next((m) => m.tipo === 'erro')).toEqual({ tipo: 'erro', codigo: 'SUBSTITUIDA', mensagem: ONLINE_MESSAGES.SUBSTITUIDA });
  expect((await o1.client.waitClosed()).code).toBe(4000);
  await new Promise((r) => setTimeout(r, 400));
  expect(x.client.since(startX), 'X não recebe DESCONEXAO nem CONEXAO').toEqual([]);
  expect((await rooms.room(pair.code)).jogadores.O.conectado).toBe(true);

  await rooms.moveOk(pair.code, pair.tx, 0);
  const moved = await o2.client.next((m) => m.motivo === 'JOGADA', 2000);
  expect(moved.sala!.partida.tabuleiro[0]).toBe('X');
  expect(o1.client.received.some((r) => r.msg.motivo === 'JOGADA'), 'o canal substituído não recebe a jogada').toBe(false);
});

test('OW-15 [CAO-34] O fecha; há jogadas; O volta e o bem_vindo traz tudo; X vê DESCONEXAO e CONEXAO', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const x = await ws.entered(pair.code, pair.tx);
  const o = await ws.entered(pair.code, pair.to);
  await x.client.next((m) => m.motivo === 'CONEXAO');
  o.client.close(1000);
  expect((await x.client.next((m) => m.tipo === 'estado', 2000)).motivo).toBe('DESCONEXAO');
  await rooms.moveOk(pair.code, pair.tx, 0);
  await rooms.moveOk(pair.code, pair.to, 4);      // REST continua valendo sem canal
  await rooms.moveOk(pair.code, pair.tx, 8);
  const back = await ws.entered(pair.code, pair.to);
  expect(back.welcome.sala!.partida.tabuleiro.join(','), 'bem_vindo com as jogadas da queda').toBe('X,,,,O,,,,X');
  expect(back.welcome.sala).toEqual(await rooms.room(pair.code));
  const conn = await x.client.next((m) => m.motivo === 'CONEXAO', 2000);
  expect(conn.sala!.jogadores.O.conectado).toBe(true);
});

test('OW-17 [CAO-37] O cai na vez dele: X não joga, ninguém ocupa o lugar, O volta e joga', async ({ rooms, ws }) => {
  const pair = await rooms.pair();
  const o = await ws.entered(pair.code, pair.to);
  await rooms.moveOk(pair.code, pair.tx, 0);     // vez de O
  o.client.close(1000);
  await expect.poll(async () => (await rooms.room(pair.code)).jogadores.O.conectado, { timeout: 3000 }).toBe(false);
  await rooms.expectError(await rooms.move(pair.code, pair.tx, 1), 409, 'VEZ_DO_OPONENTE', 'X na vez de O desconectado');
  await rooms.expectError(await rooms.join(pair.code), 409, 'SALA_CHEIA', 'terceiro tenta entrar');
  await ws.entered(pair.code, pair.to);
  const after = await rooms.moveOk(pair.code, pair.to, 4);
  expect(after.partida.tabuleiro[4]).toBe('O');
});

test('OW-18 [CAO-15, CAO-23] rajada de 18 jogadas simultâneas: cada canal vê versões crescentes e termina igual ao GET', async ({ rooms, ws }) => {
  for (let rep = 1; rep <= 5; rep++) {
    const pair = await rooms.pair();
    const x = await ws.entered(pair.code, pair.tx);
    const o = await ws.entered(pair.code, pair.to);
    await x.client.next((m) => m.motivo === 'CONEXAO');
    const positions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8];
    await Promise.all(positions.map((p, i) => rooms.move(pair.code, (p % 2 === 0) === (i < 9) ? pair.tx : pair.to, p)));
    const final = await rooms.room(pair.code);
    for (const [label, c] of [['X', x.client], ['O', o.client]] as const) {
      await expect.poll(() => c.lastRoom()?.versao, { message: `repetição ${rep}, ${label}: chega a versão final`, timeout: 3000 }).toBe(final.versao);
      const v = versions(c.states());
      expect(strictlyIncreasing(v), `repetição ${rep}, ${label}: versões ${v.join(',')}`).toBe(true);
      expect(c.lastRoom(), `repetição ${rep}, ${label}: último estado = GET`).toEqual(final);
      expect(c.states().every((s) => s.sala!.codigo === pair.code), `repetição ${rep}, ${label}: só a própria sala`).toBe(true);
    }
    x.client.close();
    o.client.close();
  }
});

export type { WsClient };
