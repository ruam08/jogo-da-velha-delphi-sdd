import { APIRequestContext, APIResponse, expect } from '@playwright/test';
import { GameState, MESSAGES, strictText } from '../api';

/*
 * Acesso às rotas de sala do modo online (docs/plan-online.md, seção 6) e
 * verificações reutilizáveis. Nenhuma resposta é simulada: tudo vai ao
 * TicTacToeServer.exe real.
 *
 * O token só viaja no cabeçalho Authorization (DTO-07), nunca na URL.
 */

export type Mark = 'X' | 'O';
export type Situation = 'AGUARDANDO_OPONENTE' | 'EM_JOGO' | 'ENCERRADA';

export interface SeatView {
  ocupado: boolean;
  conectado: boolean;
}

export interface Room {
  codigo: string;
  situacao: Situation;
  versao: number;
  numeroDaPartida: number;
  jogadores: { X: SeatView; O: SeatView };
  partida: GameState;
  motivoEncerramento: null | 'SAIDA' | 'ABANDONO';
}

export interface PlayerInfo {
  simbolo: Mark;
  token: string;
}

/** Campos do objeto sala, na ordem do contrato (6.2). */
export const ROOM_FIELDS = ['codigo', 'situacao', 'versao', 'numeroDaPartida', 'jogadores', 'partida', 'motivoEncerramento'];

export const CODE_RE = /^[2-9A-HJKMNP-Z]{6}$/;
export const TOKEN_RE = /^[0-9a-f]{32}$/;

/** Mensagens exatas (plan-online 6.6 e as reutilizadas do modo local). */
export const ONLINE_MESSAGES = {
  ...MESSAGES,
  SALA_INEXISTENTE: 'Sala não encontrada. Confira o código.',
  SALA_ENCERRADA: 'Esta sala foi encerrada.',
  SALA_CHEIA: 'Esta sala já tem dois jogadores.',
  TOKEN_INVALIDO: 'Jogador não identificado nesta sala.',
  AGUARDANDO_OPONENTE: 'Aguarde o segundo jogador entrar na sala.',
  VEZ_DO_OPONENTE: 'Não é a sua vez.',
  PARTIDA_EM_ANDAMENTO: 'A partida ainda está em andamento.',
  CORPO_MUITO_GRANDE: 'O corpo da requisição é grande demais.',
  CAPACIDADE_ESGOTADA: 'O servidor está sem vagas para novas salas. Tente mais tarde.',
  // Canal em tempo real e origem (Entrega O3).
  HANDSHAKE_INVALIDO: 'Requisição de WebSocket inválida.',
  VERSAO_WEBSOCKET: 'Versão de WebSocket não suportada.',
  ORIGEM_NAO_PERMITIDA: 'Origem não permitida.',
  MENSAGEM_INVALIDA: 'Mensagem inválida.',
  TEMPO_ESGOTADO: 'Tempo esgotado.',
  SUBSTITUIDA: 'Esta sala foi aberta em outra aba.',
} as const;
export type OnlineErrorCode = keyof typeof ONLINE_MESSAGES;

export const INITIAL_GAME: GameState = {
  tabuleiro: ['', '', '', '', '', '', '', '', ''],
  status: 'EM_ANDAMENTO',
  jogadorDaVez: 'X',
  vencedor: null,
  celulasVencedoras: [],
};

/** Sala recém-criada com o código informado (modelo de 6.3). */
export function waitingRoom(code: string): Room {
  return {
    codigo: code,
    situacao: 'AGUARDANDO_OPONENTE',
    versao: 1,
    numeroDaPartida: 1,
    jogadores: { X: { ocupado: true, conectado: false }, O: { ocupado: false, conectado: false } },
    partida: INITIAL_GAME,
    motivoEncerramento: null,
  };
}

export function bearer(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

/** Corpo JSON {"posicao":N} completado com espaços até exatamente `size` bytes. */
export function paddedMoveBody(position: number, size: number): string {
  const head = `{"posicao":${position}`;
  const pad = size - head.length - 1;
  if (pad < 0) throw new Error(`corpo de ${size} bytes é pequeno demais`);
  return head + ' '.repeat(pad) + '}';
}

export interface Pair {
  code: string;
  tx: string;
  to: string;
  room: Room;
}

export class RoomApi {
  /** Salas criadas pelo teste (código e token de X), saídas no fim. */
  private readonly owned: Array<{ code: string; token: string }> = [];

  constructor(readonly request: APIRequestContext) {}

  /** Registra uma sala criada fora de create() para a saída no fim do teste. */
  track(code: string, token: string): void {
    this.owned.push({ code, token });
  }

  /** POST /api/rooms exigindo 201; devolve a sala, o código e o token de X. */
  async create(track = true): Promise<{ code: string; token: string; room: Room; res: APIResponse }> {
    const res = await this.request.post('/api/rooms');
    expect(res.status(), `POST /api/rooms deveria responder 201; corpo: ${await res.text()}`).toBe(201);
    const body = (await res.json()) as { sala: Room; jogador: PlayerInfo };
    if (track) this.owned.push({ code: body.sala.codigo, token: body.jogador.token });
    return { code: body.sala.codigo, token: body.jogador.token, room: body.sala, res };
  }

  get(code: string): Promise<APIResponse> {
    return this.request.get(`/api/rooms/${code}`);
  }

  /** GET exigindo 200; devolve {sala}. */
  async room(code: string): Promise<Room> {
    const res = await this.get(code);
    expect(res.status(), `GET /api/rooms/${code} deveria responder 200; corpo: ${await res.text()}`).toBe(200);
    return ((await res.json()) as { sala: Room }).sala;
  }

  join(code: string, token?: string): Promise<APIResponse> {
    return this.request.post(`/api/rooms/${code}/players`, token ? { headers: bearer(token) } : {});
  }

  /** Entrada nova exigindo 201; devolve o token de O e a sala. */
  async joinOk(code: string): Promise<{ token: string; room: Room }> {
    const res = await this.join(code);
    expect(res.status(), `POST /api/rooms/${code}/players deveria responder 201; corpo: ${await res.text()}`).toBe(201);
    const body = (await res.json()) as { sala: Room; jogador: PlayerInfo };
    return { token: body.jogador.token, room: body.sala };
  }

  /** Sala criada por X, com O dentro. */
  async pair(): Promise<Pair> {
    const created = await this.create();
    const joined = await this.joinOk(created.code);
    return { code: created.code, tx: created.token, to: joined.token, room: joined.room };
  }

  move(code: string, token: string | undefined, position: number): Promise<APIResponse> {
    return this.request.post(`/api/rooms/${code}/moves`, {
      headers: token ? bearer(token) : {},
      data: { posicao: position },
    });
  }

  /** Jogada com corpo e cabeçalhos exatamente como informados. */
  moveRaw(code: string, headers: Record<string, string>, body?: string | Buffer): Promise<APIResponse> {
    return this.request.post(`/api/rooms/${code}/moves`, {
      headers: { 'Content-Type': 'application/json', ...headers },
      ...(body === undefined ? {} : { data: body }),
    });
  }

  reset(code: string, token?: string): Promise<APIResponse> {
    return this.request.post(`/api/rooms/${code}/reset`, token ? { headers: bearer(token) } : {});
  }

  leave(code: string, token?: string): Promise<APIResponse> {
    return this.request.post(`/api/rooms/${code}/leave`, token ? { headers: bearer(token) } : {});
  }

  raw(method: string, path: string, options: { data?: string | Buffer; headers?: Record<string, string> } = {}): Promise<APIResponse> {
    return this.request.fetch(path, { method, ...options });
  }

  /** Jogada que precisa ser aceita (200); devolve a sala da resposta. */
  async moveOk(code: string, token: string, position: number): Promise<Room> {
    const res = await this.move(code, token, position);
    expect(res.status(), `jogada na posição ${position} da sala ${code} deveria ser aceita; ` +
      `resposta: ${res.status()} ${await res.text()}`).toBe(200);
    return ((await res.json()) as { sala: Room }).sala;
  }

  /** Joga a sequência alternando X e O (X começa); devolve a última sala. */
  async playSequence(pair: Pair, moves: number[]): Promise<Room> {
    let last = pair.room;
    for (const [i, position] of moves.entries()) {
      last = await this.moveOk(pair.code, i % 2 === 0 ? pair.tx : pair.to, position);
    }
    return last;
  }

  /** Estado público da sala como texto (status + corpo), inclusive quando encerrada. */
  async snapshotText(code: string): Promise<string> {
    const res = await this.get(code);
    return `${res.status()} ${await strictText(res)}`;
  }

  /** Executa a ação e exige que a sala não mude (versão incluída). */
  async expectUnchanged(code: string, label: string, action: () => Promise<APIResponse>): Promise<APIResponse> {
    const before = await this.snapshotText(code);
    const res = await action();
    const after = await this.snapshotText(code);
    expect(after, `${label}: a sala ${code} não deveria mudar`).toBe(before);
    return res;
  }

  /** Erro do contrato: status, Content-Type, JSON, código e mensagem exata, UTF-8 estrito. */
  async expectError(res: APIResponse, status: number, code: OnlineErrorCode, label: string): Promise<void> {
    const text = await strictText(res);
    expect(res.status(), `${label}: status HTTP (corpo: ${text})`).toBe(status);
    expect(res.headers()['content-type'], `${label}: Content-Type`).toBe('application/json; charset=utf-8');
    expect(res.headers()['cache-control'], `${label}: Cache-Control`).toBe('no-store');
    expect(JSON.parse(text), `${label}: corpo de erro`).toEqual({ erro: { codigo: code, mensagem: ONLINE_MESSAGES[code] } });
  }

  /** Sai das salas criadas pelo teste (salas abertas contam no limite --max-rooms). */
  async cleanup(): Promise<void> {
    for (const { code, token } of this.owned.splice(0)) {
      await this.leave(code, token);
    }
  }
}
