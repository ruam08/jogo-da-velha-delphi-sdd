import { test as base, expect } from '@playwright/test';
import { GameApi } from './api';
import { GameUi } from './ui';

/**
 * Fixture `game`: acesso à API com a partida já reiniciada. Todo teste
 * começa do estado inicial, então a ordem de execução não altera o
 * resultado (RNF-10).
 *
 * Fixture `ui`: a página do jogo vista pelos testes. No fim de cada teste:
 *  - falha se houve erro de console, exceção na página, requisição que
 *    falhou (salvo as provocadas de propósito) ou resposta 404/5xx;
 *  - compara a tela com GET /api/game (verificação cruzada).
 */
export const test = base.extend<{ game: GameApi; ui: GameUi }>({
  game: async ({ request }, use) => {
    const game = new GameApi(request);
    await game.reset();
    await use(game);
  },
  ui: async ({ page, game }, use) => {
    const ui = new GameUi(page, game);
    await use(ui);
    if (ui.opened && !page.isClosed()) {
      await ui.expectMatchesServer();
    }
    expect(ui.problems, 'problemas no navegador durante o teste').toEqual([]);
  },
});

export { expect };
