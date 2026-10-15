import { APIRequestContext, APIResponse, expect } from '@playwright/test';

/* Contrato da API: docs/plan.md, seção 3. */

export type Cell = 'X' | 'O' | '';
export type Player = 'X' | 'O';
export type Status = 'EM_ANDAMENTO' | 'VITORIA' | 'EMPATE';

export interface GameState {
  tabuleiro: Cell[];
  status: Status;
  jogadorDaVez: Player | null;
  vencedor: Player | null;
  celulasVencedoras: number[];
}

export const MESSAGES = {
  CORPO_INVALIDO: 'O corpo da requisição deve ser um objeto JSON válido.',
  POSICAO_INVALIDA: 'A posição deve ser um número inteiro de 0 a 8.',
  PARTIDA_ENCERRADA: 'A partida já terminou. Clique em "Nova partida" para jogar novamente.',
  CELULA_OCUPADA: 'Esta célula já está ocupada.',
  ROTA_NAO_ENCONTRADA: 'Rota não encontrada.',
  METODO_NAO_PERMITIDO: 'Método não permitido para esta rota.',
} as const;
export type ErrorCode = keyof typeof MESSAGES;

/** JSON exato do estado inicial (campos e ordem do contrato). */
export const INITIAL_JSON =
  '{"tabuleiro":["","","","","","","","",""],"status":"EM_ANDAMENTO",' +
  '"jogadorDaVez":"X","vencedor":null,"celulasVencedoras":[]}';

/**
 * Monta um estado a partir da notação de 9 caracteres usada no plano de
 * testes ('X', 'O' ou '.' para vazia, células 0 a 8).
 */
export function state(
  board: string,
  status: Status,
  jogadorDaVez: Player | null,
  vencedor: Player | null = null,
  celulasVencedoras: number[] = [],
): GameState {
  if (board.length !== 9) throw new Error(`Tabuleiro "${board}" não tem 9 células`);
  const tabuleiro = [...board].map((c) => (c === '.' ? '' : c)) as Cell[];
  return { tabuleiro, status, jogadorDaVez, vencedor, celulasVencedoras };
}

export const INITIAL_STATE = state('.........', 'EM_ANDAMENTO', 'X');

/** Texto curto do estado, para mensagens de erro legíveis. */
export function describe(s: GameState): string {
  const board = s.tabuleiro.map((c) => (c === '' ? '.' : c)).join('');
  return `tab=${board} status=${s.status} vez=${s.jogadorDaVez ?? '-'} ` +
    `venc=${s.vencedor ?? '-'} cel=[${s.celulasVencedoras.join(',')}]`;
}

/** null se o estado é coerente com as regras; senão, o motivo. */
export function coherenceProblem(s: GameState): string | null {
  if (!Array.isArray(s.tabuleiro) || s.tabuleiro.length !== 9) return 'tabuleiro sem 9 células';
  const xs = s.tabuleiro.filter((c) => c === 'X').length;
  const os = s.tabuleiro.filter((c) => c === 'O').length;
  const empty = s.tabuleiro.filter((c) => c === '').length;
  if (xs - os < 0 || xs - os > 1) return `X=${xs} e O=${os}`;
  const cells = s.celulasVencedoras;
  switch (s.status) {
    case 'EM_ANDAMENTO': {
      const expected: Player = xs === os ? 'X' : 'O';
      if (s.jogadorDaVez !== expected) return `vez ${s.jogadorDaVez}, esperado ${expected}`;
      if (s.vencedor !== null || cells.length) return 'em andamento com vencedor';
      if (empty === 0) return 'em andamento com tabuleiro cheio';
      return null;
    }
    case 'VITORIA':
      if (s.jogadorDaVez !== null) return 'vitória com jogador da vez';
      if (s.vencedor === null) return 'vitória sem vencedor';
      if (cells.length !== 3 && cells.length !== 5) return `vitória com ${cells.length} células`;
      if (cells.some((c) => s.tabuleiro[c] !== s.vencedor)) return 'célula vencedora sem o símbolo do vencedor';
      return null;
    case 'EMPATE':
      if (s.jogadorDaVez !== null || s.vencedor !== null || cells.length) return 'empate com vez/vencedor';
      if (empty !== 0) return 'empate com células vazias';
      return null;
    default:
      return `status desconhecido ${String(s.status)}`;
  }
}

/** Decodifica o corpo exigindo UTF-8 válido (lança se os bytes forem inválidos). */
export async function strictText(res: APIResponse): Promise<string> {
  return new TextDecoder('utf-8', { fatal: true }).decode(await res.body());
}

/**
 * Acesso à API do jogo com verificações reutilizáveis. Cada método que
 * exige sucesso falha com uma mensagem que inclui a resposta recebida.
 */
export class GameApi {
  constructor(readonly request: APIRequestContext) {}

  async reset(): Promise<GameState> {
    const res = await this.request.post('/api/game/reset');
    expect(res.status(), `POST /api/game/reset deveria responder 200; corpo: ${await res.text()}`).toBe(200);
    return (await res.json()) as GameState;
  }

  async state(): Promise<GameState> {
    const res = await this.request.get('/api/game');
    expect(res.status(), `GET /api/game deveria responder 200; corpo: ${await res.text()}`).toBe(200);
    return (await res.json()) as GameState;
  }

  move(position: number): Promise<APIResponse> {
    return this.request.post('/api/game/moves', { data: { posicao: position } });
  }

  /** Envia o corpo exatamente como recebido (texto ou bytes), sem converter em JSON. */
  postMoveRaw(body?: string | Buffer, contentType = 'application/json'): Promise<APIResponse> {
    return this.request.post('/api/game/moves', {
      headers: { 'Content-Type': contentType },
      ...(body === undefined ? {} : { data: body }),
    });
  }

  /** Joga a sequência exigindo 200 em todas as jogadas; devolve o último estado. */
  async play(moves: number[]): Promise<GameState> {
    let last: GameState | undefined;
    for (const [i, position] of moves.entries()) {
      const res = await this.move(position);
      expect(res.status(),
        `jogada ${i + 1} da sequência [${moves.join(',')}] (posição ${position}) deveria ser aceita; ` +
        `resposta: ${res.status()} ${await res.text()}`).toBe(200);
      last = (await res.json()) as GameState;
    }
    return last ?? (await this.state());
  }

  /** Executa a ação e exige que o estado da partida não mude. */
  async expectUnchanged(label: string, action: () => Promise<APIResponse>): Promise<APIResponse> {
    const before = await this.state();
    const res = await action();
    const after = await this.state();
    expect(after, `${label}: o estado não deveria mudar (antes: ${describe(before)})`).toEqual(before);
    return res;
  }

  /** Exige resposta de erro do contrato: status, JSON, código e mensagem exata. */
  async expectError(res: APIResponse, status: number, code: ErrorCode, label: string): Promise<void> {
    const text = await strictText(res);
    expect(res.status(), `${label}: status HTTP (corpo: ${text})`).toBe(status);
    expect(res.headers()['content-type'], `${label}: Content-Type`).toBe('application/json; charset=utf-8');
    expect(JSON.parse(text), `${label}: corpo de erro`).toEqual({ erro: { codigo: code, mensagem: MESSAGES[code] } });
  }
}
