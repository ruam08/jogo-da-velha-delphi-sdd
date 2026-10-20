import { request as playwrightRequest } from '@playwright/test';
import { test, expect } from '@playwright/test';
import { ONLINE_MESSAGES, RoomApi } from '../../support/online/rooms';
import { startServer } from '../../support/online/server-process';
import { RawWs, WsClient } from '../../support/online/ws-client';

/*
 * Grupo OW com prazos curtos: servidor dedicado (DTO-15) com
 * --ws-hello-seconds 2 e --ws-idle-seconds 3, só em 127.0.0.1.
 */

const OPTIONS = ['--ws-hello-seconds', '2', '--ws-idle-seconds', '3', '--bind', '127.0.0.1'];

test('OW-10 [CAO-33] canal aberto sem entrar: TEMPO_ESGOTADO e 4408 entre 2 e 4 s', async () => {
  const server = await startServer('ow-10', 8771, OPTIONS);
  try {
    const raw = await RawWs.open(server.port);
    const t0 = Date.now();
    expect(raw.status).toBe(101);
    await raw.waitFor(() => raw.closeCode() !== null, 6000, 'fechamento por prazo');
    const elapsed = Date.now() - t0;
    expect(raw.texts()).toEqual([{ tipo: 'erro', codigo: 'TEMPO_ESGOTADO', mensagem: ONLINE_MESSAGES.TEMPO_ESGOTADO }]);
    expect(raw.closeCode()).toBe(4408);
    expect(elapsed, `fechou em ${elapsed} ms`).toBeGreaterThanOrEqual(1900);
    expect(elapsed, `fechou em ${elapsed} ms`).toBeLessThanOrEqual(4000);
    raw.destroy();
  } finally {
    await server.stop();
  }
});

test('OW-13 [CAO-33] O para de ler e de enviar: X recebe DESCONEXAO entre 3 e 6 s; quem manda ping continua', async () => {
  const server = await startServer('ow-13', 8772, OPTIONS);
  const context = await playwrightRequest.newContext({ baseURL: server.baseURL });
  const clients: WsClient[] = [];
  const timers: NodeJS.Timeout[] = [];
  try {
    const api = new RoomApi(context);
    const pair = await api.pair();
    const other = await api.pair();

    // X e um terceiro cliente (outra sala) mandam ping a cada 1 s.
    const x = await WsClient.entered(server.port, pair.code, pair.tx);
    const third = await WsClient.entered(server.port, other.code, other.tx);
    clients.push(x.client, third.client);
    expect(x.welcome.intervaloPingMs, 'um terço de 3 s').toBe(1000);
    let id = 0;
    for (const c of [x.client, third.client]) timers.push(setInterval(() => c.send({ tipo: 'ping', id: ++id }), 1000));

    // O se identifica por socket cru e depois fica calado, sem fechar.
    const o = await RawWs.open(server.port);
    o.sendJson({ tipo: 'entrar', protocolo: 1, sala: pair.code, token: pair.to });
    await o.waitFor(() => o.texts().some((m) => m.tipo === 'bem_vindo'), 3000, 'bem_vindo de O');
    await x.client.next((m) => m.motivo === 'CONEXAO', 2000);
    const t0 = Date.now();
    o.stopReading();

    const msg = await x.client.next((m) => m.tipo === 'estado', 7000);
    const elapsed = Date.now() - t0;
    expect(msg.motivo).toBe('DESCONEXAO');
    expect(msg.sala!.jogadores.O).toEqual({ ocupado: true, conectado: false });
    expect(elapsed, `DESCONEXAO em ${elapsed} ms`).toBeGreaterThanOrEqual(2900);
    expect(elapsed, `DESCONEXAO em ${elapsed} ms`).toBeLessThanOrEqual(6000);

    // Quem manda ping continuou conectado durante todo o teste.
    await new Promise((r) => setTimeout(r, 1500));
    expect(x.client.isOpen, 'X continua conectado').toBe(true);
    expect(third.client.isOpen, 'o terceiro continua conectado').toBe(true);
    expect(third.client.received.filter((r) => r.msg.tipo === 'pong').length, 'pongs do terceiro').toBeGreaterThanOrEqual(4);
    o.destroy();
  } finally {
    for (const t of timers) clearInterval(t);
    for (const c of clients) c.close();
    await context.dispose();
    await server.stop();
  }
});
