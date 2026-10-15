import { Locator, Page, Response, expect } from '@playwright/test';
import { GameApi, GameState } from './api';

/* Interface do jogo vista pelos testes (docs/plan.md, seção 5.2). */

export const STATUS_TEXT = {
  loading: 'Carregando partida…',
  turnX: 'Vez do jogador X',
  turnO: 'Vez do jogador O',
  winX: 'Jogador X venceu!',
  winO: 'Jogador O venceu!',
  draw: 'Empate!',
} as const;

export const NETWORK_ERROR = 'Não foi possível comunicar com o servidor.';

/** Texto que a interface deve mostrar para um estado do backend. */
export function expectedStatus(s: GameState): string {
  if (s.status === 'VITORIA') return s.vencedor === 'X' ? STATUS_TEXT.winX : STATUS_TEXT.winO;
  if (s.status === 'EMPATE') return STATUS_TEXT.draw;
  return s.jogadorDaVez === 'X' ? STATUS_TEXT.turnX : STATUS_TEXT.turnO;
}

/** Nome acessível esperado de uma célula (CI-14). */
export function cellName(index: number, content: '' | 'X' | 'O', winning = false): string {
  const row = Math.floor(index / 3) + 1;
  const col = (index % 3) + 1;
  return `Linha ${row}, coluna ${col}: ${content === '' ? 'vazia' : content}${winning ? ', vencedora' : ''}`;
}

export class GameUi {
  /** Problemas observados no navegador durante o teste. */
  readonly problems: string[] = [];
  /** Falhas de rede provocadas de propósito pelo teste (U-13, U-19). */
  networkFailuresExpected = false;
  opened = false;

  constructor(readonly page: Page, readonly game: GameApi) {
    page.on('console', (msg) => {
      // O Chrome registra "Failed to load resource" para respostas 4xx; elas
      // são esperadas (409, 400) e checadas pelo controle de respostas abaixo.
      if (msg.type() === 'error' && !msg.text().startsWith('Failed to load resource')) {
        this.problems.push(`erro de console: ${msg.text()}`);
      }
    });
    page.on('pageerror', (err) => this.problems.push(`exceção na página: ${err.message}`));
    page.on('requestfailed', (req) => {
      if (!this.networkFailuresExpected) {
        this.problems.push(`requisição falhou: ${req.method()} ${req.url()} (${req.failure()?.errorText})`);
      }
    });
    page.on('response', (res) => {
      if (res.status() === 404 || res.status() >= 500) {
        this.problems.push(`resposta ${res.status()}: ${res.request().method()} ${res.url()}`);
      }
    });
  }

  get app(): Locator { return this.page.getByTestId('app'); }
  get board(): Locator { return this.page.getByTestId('board'); }
  get status(): Locator { return this.page.getByTestId('status'); }
  get error(): Locator { return this.page.getByTestId('error-message'); }
  get newGame(): Locator { return this.page.getByTestId('new-game'); }
  get retry(): Locator { return this.page.getByTestId('retry'); }
  cell(index: number): Locator { return this.page.getByTestId(`cell-${index}`); }

  /** Abre a página e espera o estado inicial ser carregado do backend. */
  async open(): Promise<void> {
    await this.page.goto('/');
    this.opened = true;
    await this.waitIdle();
  }

  /** Espera não haver requisição pendente (CI-12). */
  async waitIdle(): Promise<void> {
    await expect(this.board, 'o tabuleiro deveria terminar a requisição (aria-busy="false")')
      .toHaveAttribute('aria-busy', 'false');
  }

  waitForMove(): Promise<Response> {
    return this.page.waitForResponse((r) =>
      r.url().endsWith('/api/game/moves') && r.request().method() === 'POST');
  }

  /**
   * Clica como um usuário real: com aria-disabled="true" (partida encerrada,
   * CI-07) o botão continua clicável no navegador, mas o Playwright, por
   * padrão, espera elementos aria-disabled ficarem habilitados. Nesses casos o
   * clique é forçado, para que a jogada chegue ao servidor e seja recusada por
   * ele (DT-09).
   */
  async clickCell(index: number): Promise<void> {
    const inactive = (await this.cell(index).getAttribute('aria-disabled')) === 'true';
    await this.cell(index).click({ force: inactive });
  }

  /** Clica na célula, aguarda a resposta do servidor e a tela ser atualizada. */
  async click(index: number): Promise<Response> {
    const response = this.waitForMove();
    await this.clickCell(index);
    const res = await response;
    await this.waitIdle();
    return res;
  }

  /** Joga a sequência pela interface, exigindo 200 em todas as jogadas. */
  async play(moves: number[]): Promise<void> {
    for (const [i, position] of moves.entries()) {
      const res = await this.click(position);
      expect(res.status(), `jogada ${i + 1} (célula ${position}) pela interface: ${await res.text()}`).toBe(200);
    }
  }

  async clickNewGame(): Promise<void> {
    const response = this.page.waitForResponse((r) => r.url().endsWith('/api/game/reset'));
    await this.newGame.click();
    expect((await response).status()).toBe(200);
    await this.waitIdle();
  }

  /** Confere as 9 células na notação 'X', 'O' ou '.'. */
  async expectBoard(board: string): Promise<void> {
    for (let i = 0; i < 9; i++) {
      const symbol = board[i] === '.' ? '' : board[i];
      await expect(this.cell(i), `célula ${i}`).toHaveText(symbol);
    }
  }

  /** Exatamente estas células com data-winning="true". */
  async expectWinning(cells: number[]): Promise<void> {
    for (let i = 0; i < 9; i++) {
      if (cells.includes(i)) {
        await expect(this.cell(i), `célula ${i} deveria estar destacada`).toHaveAttribute('data-winning', 'true');
      } else {
        await expect(this.cell(i), `célula ${i} não deveria estar destacada`).not.toHaveAttribute('data-winning', 'true');
      }
    }
  }

  /** Todas as células com (ou sem) aria-disabled="true". */
  async expectCellsDisabled(disabled: boolean): Promise<void> {
    for (let i = 0; i < 9; i++) {
      if (disabled) await expect(this.cell(i), `célula ${i}`).toHaveAttribute('aria-disabled', 'true');
      else await expect(this.cell(i), `célula ${i}`).not.toHaveAttribute('aria-disabled', 'true');
    }
  }

  async expectNoError(): Promise<void> {
    await expect(this.error, 'mensagem de erro deveria estar oculta').toBeHidden();
    await expect(this.retry, 'botão "Tentar novamente" deveria estar oculto').toBeHidden();
  }

  /** Verificação cruzada: a tela é um reflexo exato do estado no backend. */
  async expectMatchesServer(): Promise<void> {
    await this.waitIdle();
    const s = await this.game.state();
    for (let i = 0; i < 9; i++) {
      await expect(this.cell(i), `célula ${i} na tela x backend`).toHaveText(s.tabuleiro[i]);
    }
    await this.expectWinning(s.celulasVencedoras);
    await expect(this.status, 'status na tela x backend').toHaveText(expectedStatus(s));
  }
}
