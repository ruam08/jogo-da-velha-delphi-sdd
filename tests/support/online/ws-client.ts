import * as crypto from 'node:crypto';
import * as net from 'node:net';
import { Room } from './rooms';

/*
 * Clientes do canal em tempo real (docs/test-plan-online.md, seção 4), sem
 * pacotes npm novos (DTO-14):
 *  - WsClient: o WebSocket nativo do Node 24 (o mesmo objeto do navegador);
 *  - RawWs: socket cru (node:net), para aberturas inválidas, cabeçalhos
 *    forjados (Origin, Host), quadros malformados e um cliente que para de
 *    ler sem fechar.
 * Os tokens só viajam dentro da mensagem "entrar", nunca na URL.
 */

export interface ServerMessage {
  tipo: 'bem_vindo' | 'estado' | 'pong' | 'sala_encerrada' | 'erro';
  protocolo?: number;
  voce?: 'X' | 'O';
  intervaloPingMs?: number;
  motivo?: string;
  sala?: Room;
  id?: number;
  codigo?: string;
  mensagem?: string;
}

export interface Received {
  msg: ServerMessage;
  raw: string;
  at: number;
}

export interface CloseInfo {
  code: number;
  reason: string;
  at: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class WsClient {
  readonly received: Received[] = [];
  private cursor = 0;
  private closeInfo: CloseInfo | null = null;
  readonly openedAt = Date.now();
  readonly closed: Promise<CloseInfo>;

  private constructor(private readonly ws: WebSocket) {
    this.closed = new Promise<CloseInfo>((resolve) => {
      ws.addEventListener('close', (ev) => {
        this.closeInfo = { code: ev.code, reason: ev.reason, at: Date.now() };
        resolve(this.closeInfo);
      });
    });
    ws.addEventListener('message', (ev) => {
      const raw = typeof ev.data === 'string' ? ev.data : '<binário>';
      let msg: ServerMessage;
      try {
        msg = JSON.parse(raw) as ServerMessage;
      } catch {
        msg = { tipo: 'erro', codigo: 'NAO_JSON', mensagem: raw };
      }
      this.received.push({ msg, raw, at: Date.now() });
    });
  }

  static open(port: number): Promise<WsClient> {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    const client = new WsClient(ws);
    return new Promise((resolve, reject) => {
      ws.addEventListener('open', () => resolve(client), { once: true });
      ws.addEventListener('error', () => reject(new Error('o canal não abriu')), { once: true });
    });
  }

  send(data: unknown): void {
    this.ws.send(typeof data === 'string' ? data : JSON.stringify(data));
  }

  sendBinary(bytes: ArrayBuffer): void {
    this.ws.send(bytes);
  }

  enter(code: string, token: string): void {
    this.send({ tipo: 'entrar', protocolo: 1, sala: code, token });
  }

  /** Abre, entra e devolve o bem_vindo. */
  static async entered(port: number, code: string, token: string): Promise<{ client: WsClient; welcome: ServerMessage }> {
    const client = await WsClient.open(port);
    client.enter(code, token);
    const welcome = await client.next((m) => m.tipo === 'bem_vindo' || m.tipo === 'erro');
    if (welcome.tipo !== 'bem_vindo') throw new Error(`entrar recusado: ${JSON.stringify(welcome)}`);
    return { client, welcome };
  }

  /** Próxima mensagem (depois das já consumidas) que satisfaz o predicado. */
  async next(pred: (m: ServerMessage) => boolean = () => true, timeoutMs = 3000): Promise<ServerMessage> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      while (this.cursor < this.received.length) {
        const r = this.received[this.cursor++];
        if (pred(r.msg)) return r.msg;
      }
      if (Date.now() > deadline) {
        throw new Error(`nenhuma mensagem esperada em ${timeoutMs} ms; recebidas: ${this.received.map((r) => r.raw.slice(0, 120)).join(' | ')}`);
      }
      if (this.closeInfo && this.cursor >= this.received.length) {
        throw new Error(`canal fechado (${this.closeInfo.code}) sem a mensagem esperada; recebidas: ${this.received.map((r) => r.raw.slice(0, 120)).join(' | ')}`);
      }
      await sleep(10);
    }
  }

  /** Exige que nenhuma mensagem nova chegue durante ms. */
  async expectSilence(ms: number): Promise<ServerMessage[]> {
    const start = this.received.length;
    await sleep(ms);
    return this.received.slice(start).map((r) => r.msg);
  }

  /** Mensagens recebidas a partir do índice. */
  since(index: number): ServerMessage[] {
    return this.received.slice(index).map((r) => r.msg);
  }

  get count(): number {
    return this.received.length;
  }

  close(code = 1000): void {
    if (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING) this.ws.close(code);
  }

  get isOpen(): boolean {
    return this.ws.readyState === WebSocket.OPEN;
  }

  /** Estados recebidos (mensagens "estado"), na ordem. */
  states(): ServerMessage[] {
    return this.received.map((r) => r.msg).filter((m) => m.tipo === 'estado');
  }

  /** Último objeto sala recebido (bem_vindo, estado ou sala_encerrada). */
  lastRoom(): Room | undefined {
    for (let i = this.received.length - 1; i >= 0; i--) {
      const m = this.received[i].msg;
      if (m.sala) return m.sala;
    }
    return undefined;
  }

  async waitClosed(timeoutMs = 5000): Promise<CloseInfo> {
    return Promise.race([
      this.closed,
      sleep(timeoutMs).then(() => { throw new Error(`o canal não fechou em ${timeoutMs} ms`); }),
    ]);
  }
}

/* ---------------------------------------------------------------------------
 * Socket cru
 */

export const RFC_KEY = 'dGhlIHNhbXBsZSBub25jZQ==';
export const RFC_ACCEPT = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=';

export interface RawOpening {
  method?: string;
  host?: string;
  origin?: string | string[];
  key?: string;
  version?: string;
  upgrade?: string | null;
  connection?: string | null;
}

export interface ServerFrame {
  opcode: number;
  payload: Buffer;
}

export class RawWs {
  statusLine = '';
  headers: Record<string, string> = {};
  rawHeaders = '';
  body = Buffer.alloc(0);
  frames: ServerFrame[] = [];
  ended = false;
  private buffer = Buffer.alloc(0);
  private headerDone = false;

  private constructor(private readonly socket: net.Socket) {}

  /** Abre a conexão e envia o pedido de abertura; espera os cabeçalhos da resposta. */
  static async open(port: number, o: RawOpening = {}): Promise<RawWs> {
    const socket = net.connect({ host: '127.0.0.1', port });
    const raw = new RawWs(socket);
    await new Promise<void>((resolve, reject) => {
      socket.once('connect', () => resolve());
      socket.once('error', reject);
    });
    socket.on('data', (chunk: Buffer) => raw.onData(chunk));
    socket.on('close', () => { raw.ended = true; });
    socket.on('error', () => { raw.ended = true; });
    let req = `${o.method ?? 'GET'} /ws HTTP/1.1\r\nHost: ${o.host ?? `127.0.0.1:${port}`}\r\n`;
    if (o.upgrade !== null) req += `Upgrade: ${o.upgrade ?? 'websocket'}\r\n`;
    if (o.connection !== null) req += `Connection: ${o.connection ?? 'Upgrade'}\r\n`;
    if (o.key !== '') req += `Sec-WebSocket-Key: ${o.key ?? RFC_KEY}\r\n`;
    req += `Sec-WebSocket-Version: ${o.version ?? '13'}\r\n`;
    for (const origin of o.origin === undefined ? [] : Array.isArray(o.origin) ? o.origin : [o.origin]) {
      req += `Origin: ${origin}\r\n`;
    }
    socket.write(req + '\r\n');
    const deadline = Date.now() + 5000;
    while (!raw.headerDone && !raw.ended && Date.now() < deadline) await sleep(5);
    if (!raw.headerDone) throw new Error('resposta da abertura não chegou');
    return raw;
  }

  get status(): number {
    return Number(this.statusLine.split(' ')[1] ?? 0);
  }

  private onData(chunk: Buffer): void {
    if (!this.headerDone) {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      const sep = this.buffer.indexOf('\r\n\r\n');
      if (sep < 0) return;
      this.rawHeaders = this.buffer.subarray(0, sep).toString('latin1');
      const lines = this.rawHeaders.split('\r\n');
      this.statusLine = lines[0];
      for (const line of lines.slice(1)) {
        const i = line.indexOf(':');
        if (i > 0) this.headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
      }
      const rest = this.buffer.subarray(sep + 4);
      this.buffer = Buffer.alloc(0);
      this.headerDone = true;
      if (this.status !== 101) {
        this.body = Buffer.concat([this.body, rest]);
        return;
      }
      if (rest.length) this.onFrames(rest);
      return;
    }
    if (this.status !== 101) this.body = Buffer.concat([this.body, chunk]);
    else this.onFrames(chunk);
  }

  private onFrames(chunk: Buffer): void {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    for (;;) {
      if (this.buffer.length < 2) return;
      const b1 = this.buffer[1];
      let len = b1 & 0x7f;
      let off = 2;
      if (len === 126) {
        if (this.buffer.length < 4) return;
        len = this.buffer.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (this.buffer.length < 10) return;
        len = Number(this.buffer.readBigUInt64BE(2));
        off = 10;
      }
      if (this.buffer.length < off + len) return;
      this.frames.push({ opcode: this.buffer[0] & 0x0f, payload: this.buffer.subarray(off, off + len) });
      this.buffer = this.buffer.subarray(off + len);
    }
  }

  /** Quadro do cliente; mascarado por padrão (RFC 6455, 5.1). */
  sendFrame(opcode: number, payload: Buffer | string, opts: { mask?: boolean; fin?: boolean } = {}): void {
    const data = typeof payload === 'string' ? Buffer.from(payload, 'utf8') : payload;
    const mask = opts.mask ?? true;
    const fin = opts.fin ?? true;
    const head: number[] = [(fin ? 0x80 : 0) | opcode];
    const m = mask ? 0x80 : 0;
    if (data.length < 126) head.push(m | data.length);
    else if (data.length <= 0xffff) head.push(m | 126, data.length >> 8, data.length & 0xff);
    else {
      head.push(m | 127);
      const b = Buffer.alloc(8);
      b.writeBigUInt64BE(BigInt(data.length));
      head.push(...b);
    }
    let body = data;
    let key = Buffer.alloc(0);
    if (mask) {
      key = crypto.randomBytes(4);
      body = Buffer.from(data.map((v, i) => v ^ key[i & 3]));
    }
    this.socket.write(Buffer.concat([Buffer.from(head), key, body]));
  }

  sendText(text: string): void {
    this.sendFrame(0x1, text);
  }

  sendJson(obj: unknown): void {
    this.sendText(JSON.stringify(obj));
  }

  /** Mensagens de texto do servidor, decodificadas. */
  texts(): ServerMessage[] {
    return this.frames.filter((f) => f.opcode === 0x1).map((f) => JSON.parse(f.payload.toString('utf8')) as ServerMessage);
  }

  bodyText(): string {
    return this.body.toString('utf8');
  }

  /** Espera a resposta HTTP de erro terminar (o servidor fecha a conexão). */
  async waitEnd(timeoutMs = 3000): Promise<void> {
    await this.waitFor(() => this.ended, timeoutMs, 'fim da resposta');
  }

  /** Código do quadro de fechamento recebido, ou null. */
  closeCode(): number | null {
    const f = this.frames.find((x) => x.opcode === 0x8);
    return f && f.payload.length >= 2 ? f.payload.readUInt16BE(0) : null;
  }

  async waitFor(pred: () => boolean, timeoutMs = 3000, what = 'condição'): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (!pred()) {
      if (Date.now() > deadline) {
        throw new Error(`${what} não ocorreu em ${timeoutMs} ms; quadros: ${this.frames.map((f) => `${f.opcode}:${f.payload.toString('utf8').slice(0, 80)}`).join(' | ')}`);
      }
      await sleep(10);
    }
  }

  async waitClose(timeoutMs = 3000): Promise<number | null> {
    await this.waitFor(() => this.closeCode() !== null || this.ended, timeoutMs, 'fechamento');
    return this.closeCode();
  }

  /** Para de ler (o servidor deixa de receber confirmações TCP de leitura da aplicação) e não envia nada. */
  stopReading(): void {
    this.socket.pause();
  }

  destroy(): void {
    this.socket.destroy();
  }
}
