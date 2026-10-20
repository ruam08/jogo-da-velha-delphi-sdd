import { test as base, expect } from '@playwright/test';
import { portOf } from '../raw-http';
import { RoomApi } from './rooms';
import { RawOpening, RawWs, ServerMessage, WsClient } from './ws-client';

/**
 * Fixture `rooms` dos testes do modo online: acesso às rotas de sala. No fim
 * de cada teste, X sai de todas as salas que o teste criou, para que salas
 * abertas não se acumulem no limite de salas do servidor da suíte.
 *
 * Fixture `ws` (Entrega O3): abre canais no servidor da suíte e fecha, no fim
 * do teste, todos os que ainda estiverem abertos.
 *
 * Os testes de sala não tocam na partida global do modo local.
 */
export class WsFactory {
  private readonly clients: WsClient[] = [];
  private readonly raws: RawWs[] = [];

  constructor(readonly port: number) {}

  async open(): Promise<WsClient> {
    const c = await WsClient.open(this.port);
    this.clients.push(c);
    return c;
  }

  /** Abre, envia "entrar" e devolve o cliente e o bem_vindo. */
  async entered(code: string, token: string): Promise<{ client: WsClient; welcome: ServerMessage }> {
    const r = await WsClient.entered(this.port, code, token);
    this.clients.push(r.client);
    return r;
  }

  async raw(o: RawOpening = {}): Promise<RawWs> {
    const r = await RawWs.open(this.port, o);
    this.raws.push(r);
    return r;
  }

  closeAll(): void {
    for (const c of this.clients) c.close();
    for (const r of this.raws) r.destroy();
  }
}

export const test = base.extend<{ rooms: RoomApi; ws: WsFactory }>({
  rooms: async ({ request }, use) => {
    const rooms = new RoomApi(request);
    await use(rooms);
    await rooms.cleanup();
  },
  ws: async ({ baseURL }, use) => {
    const ws = new WsFactory(portOf(baseURL));
    await use(ws);
    ws.closeAll();
  },
});

export { expect };
