import { test as base, expect } from './fixtures';
import { Players } from './online-ui';

/**
 * Fixture `players` (Entrega O4): jogadores em contextos isolados do Chromium
 * contra o servidor da suíte. No fim de cada teste:
 *  - cada página ainda aberta numa sala ativa é comparada com GET da sala
 *    (verificação cruzada);
 *  - nenhum token emitido no teste pode aparecer em URL de página, de
 *    requisição ou de canal (OU-24);
 *  - nenhum erro de console, exceção, requisição falha (salvo as provocadas)
 *    ou resposta 404/5xx inesperada.
 * Depois, os contextos são fechados e a fixture `rooms` sai das salas criadas.
 */
export const test = base.extend<{ players: Players }>({
  players: async ({ browser, baseURL, rooms }, use) => {
    const players = new Players(browser, baseURL!, rooms);
    await use(players);
    try {
      await players.finish();
    } finally {
      await players.closeAll();
    }
  },
});

export { expect };
