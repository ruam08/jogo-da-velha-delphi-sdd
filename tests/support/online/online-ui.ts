import { Browser, BrowserContext, BrowserContextOptions, Locator, Page, Response, expect } from '@playwright/test';
import { Mark, Room, RoomApi } from './rooms';

/*
 * Interface online vista pelos testes (docs/plan-online.md, seção 9;
 * docs/test-plan-online.md, seção 4: OnlineUi e Players).
 *
 * Cada jogador é um contexto isolado do Chromium (browser.newContext()), com
 * o próprio localStorage: dois contextos são dois navegadores diferentes.
 * Nenhuma resposta do servidor é simulada; os testes só atrasam ou derrubam
 * conexões reais.
 */

/** Textos exatos da interface (docs/spec-online.md, CIO-02 a CIO-13). */
export const ONLINE_TEXT = {
  waiting: 'Aguardando o oponente…',
  yourTurn: 'Sua vez',
  opponentTurn: 'Vez do oponente',
  youWon: 'Você venceu!',
  opponentWon: 'O oponente venceu.',
  draw: 'Empate!',
  roomClosedStatus: 'Sala encerrada.',
  opponentMissing: 'Aguardando oponente',
  opponentOnline: 'Oponente conectado',
  opponentOffline: 'Oponente desconectado. Aguardando reconexão…',
  connecting: 'Conectando…',
  connected: 'Conectado',
  reconnecting: 'Reconectando…',
  offline: 'Sem conexão com o servidor.',
  copied: 'Link copiado.',
  restartHint: 'Se o servidor foi reiniciado, as salas anteriores deixam de existir.',
  leaveConfirm: 'Sair da sala encerra a partida para os dois jogadores.',
  network: 'Não foi possível comunicar com o servidor.',
  emptyCode: 'Informe o código da sala.',
} as const;

/**
 * Guarda do token no navegador (DO-05, RNO-16): localStorage, uma entrada por
 * sala, chave `${STORAGE_PREFIX}<CÓDIGO>`, valor JSON
 * {codigo, simbolo, token, salvoEm}, válida por 24 h desde o último uso.
 */
export const STORAGE_PREFIX = 'jogo-da-velha:sala:';
export const STORAGE_TTL_MS = 24 * 60 * 60 * 1000;

export function youAre(mark: Mark): string {
  return `Você joga com ${mark}`;
}

/** Status da partida esperado para o lugar `seat` (CIO-05). */
export function expectedStatus(room: Room, seat: Mark): string {
  if (room.situacao === 'ENCERRADA') return ONLINE_TEXT.roomClosedStatus;
  if (room.situacao === 'AGUARDANDO_OPONENTE') return ONLINE_TEXT.waiting;
  const g = room.partida;
  if (g.status === 'VITORIA') return g.vencedor === seat ? ONLINE_TEXT.youWon : ONLINE_TEXT.opponentWon;
  if (g.status === 'EMPATE') return ONLINE_TEXT.draw;
  return g.jogadorDaVez === seat ? ONLINE_TEXT.yourTurn : ONLINE_TEXT.opponentTurn;
}

/** Presença do oponente esperada para o lugar `seat` (CIO-06). */
export function expectedOpponent(room: Room, seat: Mark): string {
  const other = room.jogadores[seat === 'X' ? 'O' : 'X'];
  if (!other.ocupado) return ONLINE_TEXT.opponentMissing;
  return other.conectado ? ONLINE_TEXT.opponentOnline : ONLINE_TEXT.opponentOffline;
}

/** Nome acessível de uma célula, igual ao do modo local (CI-14). */
export function cellName(index: number, content: '' | 'X' | 'O', winning = false): string {
  const row = Math.floor(index / 3) + 1;
  const col = (index % 3) + 1;
  return `Linha ${row}, coluna ${col}: ${content === '' ? 'vazia' : content}${winning ? ', vencedora' : ''}`;
}

const ACTIVE_STATES = ['aguardando', 'jogando', 'finalizada'];

export class OnlineUi {
  /** Problemas observados no navegador (erros de console, exceções, falhas, 404/5xx). */
  readonly problems: string[] = [];
  /** Todas as URLs de página, de requisição e de canal (OU-24). */
  readonly urls: string[] = [];
  /** Tokens vistos nas respostas de criação e entrada (OU-24). */
  readonly tokens: string[] = [];
  /** Horário de cada abertura de canal desta página. */
  readonly wsOpens: number[] = [];
  /** Requisições GET /api/rooms/... desta página (seção 3, item 5). */
  readonly roomGets: number[] = [];
  /** Falhas de rede provocadas de propósito pelo teste. */
  networkFailuresExpected = false;
  /** Código da sala em que este jogador está, quando conhecido. */
  code = '';
  seat: Mark | null = null;

  constructor(readonly page: Page, readonly name: string, readonly rooms: RoomApi) {
    page.on('console', (msg) => {
      if (msg.type() !== 'error') return;
      const text = msg.text();
      // Respostas 4xx são recusas esperadas do servidor (409, 404, 410...).
      if (text.startsWith('Failed to load resource')) return;
      // Canal recusado ou derrubado de propósito (servidor parado, queda simulada).
      if (this.networkFailuresExpected && /WebSocket|ERR_CONNECTION|net::/.test(text)) return;
      this.problems.push(`${name}: erro de console: ${text}`);
    });
    page.on('pageerror', (err) => this.problems.push(`${name}: exceção na página: ${err.message}`));
    page.on('requestfailed', (req) => {
      if (!this.networkFailuresExpected) {
        this.problems.push(`${name}: requisição falhou: ${req.method()} ${req.url()} (${req.failure()?.errorText})`);
      }
    });
    page.on('request', (req) => {
      this.urls.push(req.url());
      if (req.method() === 'GET' && /\/api\/rooms\//.test(new URL(req.url()).pathname)) this.roomGets.push(Date.now());
    });
    page.on('framenavigated', (frame) => this.urls.push(frame.url()));
    page.on('websocket', (ws) => {
      this.urls.push(ws.url());
      this.wsOpens.push(Date.now());
    });
    page.on('response', async (res) => {
      const url = new URL(res.url());
      // 404 e 410 de /api/rooms são respostas de sala inexistente ou encerrada (esperadas).
      const roomAnswer = url.pathname.startsWith('/api/rooms') && (res.status() === 404 || res.status() === 410);
      if ((res.status() === 404 && !roomAnswer) || res.status() >= 500) {
        this.problems.push(`${name}: resposta ${res.status()}: ${res.request().method()} ${res.url()}`);
      }
      // Guarda os tokens emitidos (para OU-24) e as salas criadas (para a limpeza).
      if (res.request().method() === 'POST' && /^\/api\/rooms(\/[^/]+\/players)?$/.test(url.pathname) &&
          (res.status() === 201 || res.status() === 200)) {
        try {
          const body = (await res.json()) as { sala: Room; jogador: { simbolo: Mark; token: string } };
          this.tokens.push(body.jogador.token);
          if (url.pathname === '/api/rooms') rooms.track(body.sala.codigo, body.jogador.token);
        } catch {
          // página fechada antes de ler o corpo
        }
      }
    });
  }

  // ---- Elementos (docs/plan-online.md, 9.2) ---------------------------------
  get app(): Locator { return this.page.getByTestId('online-app'); }
  get createRoom(): Locator { return this.page.getByTestId('create-room'); }
  get codeInput(): Locator { return this.page.getByTestId('room-code-input'); }
  get joinRoom(): Locator { return this.page.getByTestId('join-room'); }
  get joinThisRoom(): Locator { return this.page.getByTestId('join-this-room'); }
  get roomCode(): Locator { return this.page.getByTestId('room-code'); }
  get roomLink(): Locator { return this.page.getByTestId('room-link'); }
  get copyLink(): Locator { return this.page.getByTestId('copy-link'); }
  get copyFeedback(): Locator { return this.page.getByTestId('copy-feedback'); }
  get youAre(): Locator { return this.page.getByTestId('you-are'); }
  get gameNumber(): Locator { return this.page.getByTestId('game-number'); }
  get status(): Locator { return this.page.getByTestId('status'); }
  get opponent(): Locator { return this.page.getByTestId('opponent-status'); }
  get connection(): Locator { return this.page.getByTestId('connection-status'); }
  get board(): Locator { return this.page.getByTestId('board'); }
  get error(): Locator { return this.page.getByTestId('error-message'); }
  get hint(): Locator { return this.page.getByTestId('room-hint'); }
  get newGame(): Locator { return this.page.getByTestId('new-game'); }
  get leave(): Locator { return this.page.getByTestId('leave-room'); }
  get reconnect(): Locator { return this.page.getByTestId('reconnect'); }
  get useHere(): Locator { return this.page.getByTestId('use-here'); }
  get createNewRoom(): Locator { return this.page.getByTestId('create-new-room'); }
  cell(i: number): Locator { return this.page.getByTestId(`cell-${i}`); }

  async state(): Promise<string> { return (await this.app.getAttribute('data-state')) ?? ''; }

  async expectState(state: string, timeout?: number): Promise<void> {
    await expect(this.app, `${this.name}: data-state`).toHaveAttribute('data-state', state, timeout ? { timeout } : undefined);
  }

  async expectConnection(value: string, timeout?: number): Promise<void> {
    await expect(this.app, `${this.name}: data-connection`).toHaveAttribute('data-connection', value, timeout ? { timeout } : undefined);
  }

  async version(): Promise<number> { return Number(await this.app.getAttribute('data-version')); }

  /** Espera não haver ação pendente (aria-busy="false" no tabuleiro). */
  async waitIdle(): Promise<void> {
    await expect(this.board, `${this.name}: ação pendente`).toHaveAttribute('aria-busy', 'false');
  }

  // ---- Ações -------------------------------------------------------------------
  async open(path = '/online.html'): Promise<void> {
    await this.page.goto(path);
  }

  /** "Criar sala" na tela inicial; devolve o código. */
  async create(): Promise<string> {
    const created = this.page.waitForResponse((r) => new URL(r.url()).pathname === '/api/rooms' && r.request().method() === 'POST');
    await this.createRoom.click();
    expect((await created).status(), `${this.name}: POST /api/rooms`).toBe(201);
    await this.expectState('aguardando');
    await this.expectConnection('conectado');
    this.code = (await this.roomCode.textContent()) ?? '';
    this.seat = 'X';
    return this.code;
  }

  /** Digita o código (como informado) e aciona "Entrar". */
  async joinByCode(typed: string, expectedCode?: string): Promise<Response> {
    await this.codeInput.fill(typed);
    const joined = this.page.waitForResponse((r) => /\/api\/rooms\/[^/]+\/players$/.test(new URL(r.url()).pathname));
    await this.joinRoom.click();
    const res = await joined;
    if (res.status() === 201 || res.status() === 200) {
      this.code = expectedCode ?? typed.trim().toUpperCase();
      this.seat = ((await res.json()) as { jogador: { simbolo: Mark } }).jogador.simbolo;
    }
    return res;
  }

  /** Abre o link da sala; sem token guardado, espera o convite ("Entrar na sala"). */
  async openLink(link: string): Promise<void> {
    await this.page.goto(link);
  }

  /** "Entrar na sala" (link aberto sem token). */
  async acceptInvite(code: string): Promise<void> {
    const joined = this.page.waitForResponse((r) => /\/api\/rooms\/[^/]+\/players$/.test(new URL(r.url()).pathname));
    await this.joinThisRoom.click();
    expect((await joined).status(), `${this.name}: entrar na sala`).toBe(201);
    await this.expectConnection('conectado');
    this.code = code;
    this.seat = 'O';
  }

  waitForMove(): Promise<Response> {
    return this.page.waitForResponse((r) => /\/api\/rooms\/[^/]+\/moves$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
  }

  /** Clica como um usuário: célula com aria-disabled continua clicável (CIO-08/09). */
  async clickCell(i: number): Promise<void> {
    const inactive = (await this.cell(i).getAttribute('aria-disabled')) === 'true';
    await this.cell(i).click({ force: inactive });
  }

  /** Clica na célula e espera a resposta do servidor e o fim da ação. */
  async click(i: number): Promise<Response> {
    const res = this.waitForMove();
    await this.clickCell(i);
    const r = await res;
    await this.waitIdle();
    return r;
  }

  async clickNewGame(): Promise<Response> {
    const res = this.page.waitForResponse((r) => /\/api\/rooms\/[^/]+\/reset$/.test(new URL(r.url()).pathname));
    await this.newGame.click();
    const r = await res;
    await this.waitIdle();
    return r;
  }

  /** "Sair da sala", aceitando a confirmação nativa do navegador. */
  async leaveRoom(): Promise<void> {
    let confirmText = '';
    this.page.once('dialog', async (d) => {
      confirmText = d.message();
      await d.accept();
    });
    const res = this.page.waitForResponse((r) => /\/api\/rooms\/[^/]+\/leave$/.test(new URL(r.url()).pathname));
    await this.leave.click();
    expect((await res).status(), `${this.name}: sair da sala`).toBe(200);
    expect(confirmText, 'texto da confirmação').toBe(ONLINE_TEXT.leaveConfirm);
  }

  /** Entradas do localStorage desta página que guardam tokens de sala. */
  async storage(): Promise<Record<string, string>> {
    return this.page.evaluate(() => {
      const out: Record<string, string> = {};
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i)!;
        out[k] = localStorage.getItem(k) ?? '';
      }
      return out;
    });
  }

  /** Token guardado no navegador para a sala (ou null). */
  async storedToken(code: string): Promise<string | null> {
    const all = await this.storage();
    for (const v of Object.values(all)) {
      try {
        const entry = JSON.parse(v) as { codigo?: string; token?: string };
        if (entry.codigo === code && entry.token) return entry.token;
      } catch {
        // valor que não é da interface online
      }
    }
    return null;
  }

  // ---- Verificações -----------------------------------------------------------
  /** Confere as 9 células na notação 'X', 'O' ou '.'. */
  async expectBoard(board: string, timeout?: number): Promise<void> {
    for (let i = 0; i < 9; i++) {
      const symbol = board[i] === '.' ? '' : board[i];
      await expect(this.cell(i), `${this.name}: célula ${i}`).toHaveText(symbol, timeout ? { timeout } : undefined);
    }
  }

  async expectWinning(cells: number[]): Promise<void> {
    for (let i = 0; i < 9; i++) {
      if (cells.includes(i)) await expect(this.cell(i), `${this.name}: célula ${i} destacada`).toHaveAttribute('data-winning', 'true');
      else await expect(this.cell(i), `${this.name}: célula ${i} sem destaque`).not.toHaveAttribute('data-winning', 'true');
    }
  }

  async expectCellsDisabled(disabled: boolean): Promise<void> {
    for (let i = 0; i < 9; i++) {
      if (disabled) await expect(this.cell(i), `${this.name}: célula ${i}`).toHaveAttribute('aria-disabled', 'true');
      else await expect(this.cell(i), `${this.name}: célula ${i}`).not.toHaveAttribute('aria-disabled', 'true');
    }
  }

  /** Verificação cruzada (seção 3, item 6): a página é um reflexo exato da sala no servidor. */
  async expectMatchesServer(): Promise<void> {
    if (!this.code || !this.seat || this.page.isClosed()) return;
    if (!ACTIVE_STATES.includes(await this.state())) return;
    await this.waitIdle();
    const room = await this.rooms.room(this.code);
    await expect(this.app, `${this.name}: data-version x servidor`).toHaveAttribute('data-version', String(room.versao));
    for (let i = 0; i < 9; i++) {
      await expect(this.cell(i), `${this.name}: célula ${i} x servidor`).toHaveText(room.partida.tabuleiro[i]);
    }
    await this.expectWinning(room.partida.celulasVencedoras);
    await expect(this.status, `${this.name}: status x servidor`).toHaveText(expectedStatus(room, this.seat));
    await expect(this.opponent, `${this.name}: presença x servidor`).toHaveText(expectedOpponent(room, this.seat));
    await expect(this.gameNumber).toHaveText(`Partida ${room.numeroDaPartida}`);
    await expect(this.youAre).toHaveText(youAre(this.seat));
  }
}

/** Jogadores em contextos isolados do Chromium (Players, seção 4). */
export class Players {
  private readonly contexts: BrowserContext[] = [];
  readonly uis: OnlineUi[] = [];

  constructor(readonly browser: Browser, readonly baseURL: string, readonly rooms: RoomApi) {}

  /** Novo "navegador" (contexto isolado) com uma página. */
  async open(name: string, options: BrowserContextOptions = {}): Promise<OnlineUi> {
    const context = await this.browser.newContext({ baseURL: this.baseURL, ...options });
    this.contexts.push(context);
    const page = await context.newPage();
    const ui = new OnlineUi(page, name, this.rooms);
    this.uis.push(ui);
    return ui;
  }

  /** Outra página no mesmo contexto (mesmo navegador, outra aba). */
  async newTab(of: OnlineUi, name: string): Promise<OnlineUi> {
    const page = await of.page.context().newPage();
    const ui = new OnlineUi(page, name, this.rooms);
    this.uis.push(ui);
    return ui;
  }

  /** A cria a sala; B abre o link e entra. As duas páginas ficam em "jogando". */
  async pair(): Promise<{ a: OnlineUi; b: OnlineUi; code: string; link: string }> {
    const a = await this.open('A');
    await a.open();
    const code = await a.create();
    const link = (await a.roomLink.textContent()) ?? '';
    const b = await this.open('B');
    await b.openLink(link);
    await b.expectState('convite');
    await b.acceptInvite(code);
    await a.expectState('jogando');
    await b.expectState('jogando');
    await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
    await expect(b.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
    return { a, b, code, link };
  }

  /** Controles do fim de cada teste: verificação cruzada, problemas e tokens fora das URLs (OU-24). */
  async finish(): Promise<void> {
    const tokens = new Set<string>();
    for (const ui of this.uis) {
      for (const t of ui.tokens) tokens.add(t);
      if (!ui.page.isClosed()) {
        for (const v of Object.values(await ui.storage().catch(() => ({})))) {
          const m = /[0-9a-f]{32}/.exec(v);
          if (m) tokens.add(m[0]);
        }
      }
    }
    for (const ui of this.uis) await ui.expectMatchesServer();
    const leaks: string[] = [];
    for (const ui of this.uis) {
      for (const url of ui.urls) {
        for (const t of tokens) if (url.includes(t)) leaks.push(`${ui.name}: ${url}`);
      }
    }
    expect(leaks, 'OU-24 [CAO-54]: nenhum token em URL de página, requisição ou canal').toEqual([]);
    expect(this.uis.flatMap((u) => u.problems), 'problemas no navegador durante o teste').toEqual([]);
  }

  async closeAll(): Promise<void> {
    for (const c of this.contexts.splice(0)) await c.close().catch(() => undefined);
  }
}
