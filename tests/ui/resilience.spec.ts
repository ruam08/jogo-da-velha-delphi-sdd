import { test, expect } from '../support/fixtures';
import { NETWORK_ERROR, STATUS_TEXT } from '../support/ui';

/*
 * Grupo U: falhas de comunicação, carregamento e cliques rápidos.
 * page.route só ABORTA ou ATRASA requisições reais (route.continue()):
 * nenhuma resposta do backend é fabricada.
 */

test('U-13 [CA-22] falha de comunicação: mensagem clara e recuperação com "Tentar novamente"', async ({ ui, page }) => {
  await ui.open();
  await ui.play([0]);

  ui.networkFailuresExpected = true;
  await page.route('**/api/**', (route) => route.abort('connectionrefused'));
  await ui.clickCell(4);
  await expect(ui.error).toHaveText(NETWORK_ERROR);
  await expect(ui.retry).toBeVisible();
  await expect(ui.app).toHaveAttribute('data-state', 'offline');
  await ui.expectBoard('X........');
  await ui.waitIdle();

  await page.unroute('**/api/**');
  const reload = page.waitForResponse((r) => r.url().endsWith('/api/game') && r.request().method() === 'GET');
  await ui.retry.click();
  expect((await reload).status()).toBe(200);
  await ui.waitIdle();
  await ui.expectNoError();
  await ui.expectBoard('X........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnO);

  // Depois de recuperada, a interface volta a jogar normalmente.
  await ui.play([4]);
  await ui.expectBoard('X...O....');
});

test('U-17 [CA-31] cliques rápidos: só uma jogada é enviada enquanto a anterior está pendente', async ({ ui, page }) => {
  await ui.open();
  const posts: string[] = [];
  page.on('request', (req) => {
    if (req.method() === 'POST' && req.url().endsWith('/api/game/moves')) posts.push(req.postData() ?? '');
  });
  // Atrasa a resposta real do servidor para abrir uma janela de requisição pendente.
  await page.route('**/api/game/moves', async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 400));
    await route.continue();
  });

  const response = ui.waitForMove();
  await ui.clickCell(0);
  await expect(ui.board).toHaveAttribute('aria-busy', 'true');
  await ui.clickCell(1);
  await response;
  await ui.waitIdle();

  expect(posts, 'apenas a primeira jogada deveria ser enviada').toEqual(['{"posicao":0}']);
  await ui.expectBoard('X........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnO);
  await ui.expectNoError();
  await page.unroute('**/api/game/moves');
});

test('U-18 [CA-28] carregamento: status, aria-busy e cliques ignorados até a resposta', async ({ ui, page }) => {
  const posts: string[] = [];
  page.on('request', (req) => {
    if (req.method() === 'POST') posts.push(req.url());
  });
  let releaseLoad: () => void = () => {};
  const loadHeld = new Promise<void>((resolve) => { releaseLoad = resolve; });
  await page.route('**/api/game', async (route) => {
    await loadHeld;
    await route.continue();
  });

  await page.goto('/');
  ui.opened = true;
  await expect(ui.status).toHaveText(STATUS_TEXT.loading);
  await expect(ui.board).toHaveAttribute('aria-busy', 'true');
  await expect(ui.app).toHaveAttribute('data-state', 'loading');
  // A célula está marcada como inativa durante o carregamento; o clique é
  // forçado para provar que, mesmo chegando ao botão, não gera requisição.
  await ui.cell(0).click({ force: true });
  expect(posts, 'clique durante o carregamento não deveria gerar requisição').toEqual([]);

  releaseLoad();
  await ui.waitIdle();
  await ui.expectBoard('.........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
  expect(posts).toEqual([]);
  await page.unroute('**/api/game');
});

test('U-19 [CA-32] falha no carregamento inicial e recuperação', async ({ ui, page }) => {
  ui.networkFailuresExpected = true;
  await page.route('**/api/game', (route) => route.abort('connectionrefused'));
  await page.goto('/');
  ui.opened = true;
  await expect(ui.error).toHaveText(NETWORK_ERROR);
  await expect(ui.retry).toBeVisible();
  await ui.expectCellsDisabled(true);
  await ui.waitIdle();

  await page.unroute('**/api/game');
  await ui.retry.click();
  await ui.waitIdle();
  await ui.expectNoError();
  await ui.expectBoard('.........');
  await expect(ui.status).toHaveText(STATUS_TEXT.turnX);
  await ui.expectCellsDisabled(false);
});
