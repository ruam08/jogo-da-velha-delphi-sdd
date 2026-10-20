import * as crypto from 'node:crypto';
import { ChildProcess, execFileSync, spawn } from 'node:child_process';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';
import type { DedicatedServer } from './server-process';

/*
 * Auxiliares dos testes de endurecimento (Entrega O6; docs/plan-online.md,
 * seção 13.1; docs/test-plan-online.md, OV-06 a OV-17). Tudo por socket
 * cru, para poder escolher o endereço de origem da conexão, mandar
 * X-Forwarded-For, corpos declarados maiores que o enviado, corpos em
 * blocos e conexões paradas, e ler a resposta exatamente como o servidor a
 * escreveu.
 */

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
export const TOKEN_LIKE = /\b[0-9a-f]{32}\b/;

/** IPv4 privado de uma interface desta máquina (10/8, 172.16/12, 192.168/16), ou null. */
export function privateIPv4(): string | null {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family !== 'IPv4' || a.internal) continue;
      const [p0, p1] = a.address.split('.').map(Number);
      if (p0 === 10 || (p0 === 172 && p1 >= 16 && p1 <= 31) || (p0 === 192 && p1 === 168)) return a.address;
    }
  }
  return null;
}

export interface HttpReply {
  status: number;
  headers: Record<string, string>;
  body: string;
  /** JSON do corpo, ou undefined. */
  json?: any;
  /** Erro de rede (conexão recusada, reiniciada) em vez de resposta. */
  networkError?: string;
}

export interface HttpOptions {
  host?: string;
  method?: string;
  path: string;
  headers?: Array<[string, string]>;
  body?: string | Buffer;
  /** Content-Length a declarar (padrão: o tamanho do corpo; null = não enviar). */
  contentLength?: number | null;
  /** Envia o corpo em blocos (Transfer-Encoding: chunked), neste tamanho. */
  chunkSize?: number;
  timeoutMs?: number;
}

function parseReply(raw: Buffer): HttpReply {
  const sep = raw.indexOf('\r\n\r\n');
  const head = (sep < 0 ? raw : raw.subarray(0, sep)).toString('latin1');
  const lines = head.split('\r\n');
  const reply: HttpReply = { status: Number(lines[0]?.split(' ')[1] ?? 0), headers: {}, body: '' };
  for (const line of lines.slice(1)) {
    const i = line.indexOf(':');
    if (i > 0) reply.headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
  }
  reply.body = sep < 0 ? '' : raw.subarray(sep + 4).toString('utf8');
  try { reply.json = reply.body ? JSON.parse(reply.body) : undefined; } catch { reply.json = undefined; }
  return reply;
}

/** Uma requisição HTTP/1.1 crua; lê a resposta até o servidor fechar (KeepAlive desligado). */
export function http(port: number, o: HttpOptions): Promise<HttpReply> {
  return new Promise((resolve) => {
    const host = o.host ?? '127.0.0.1';
    const socket = net.connect({ host, port });
    const chunks: Buffer[] = [];
    let settled = false;
    const done = (r: HttpReply) => { if (!settled) { settled = true; resolve(r); } };
    socket.setTimeout(o.timeoutMs ?? 10_000, () => {
      socket.destroy();
      done({ status: 0, headers: {}, body: '', networkError: 'tempo esgotado' });
    });
    socket.on('connect', () => {
      const method = o.method ?? 'GET';
      const body = o.body === undefined ? Buffer.alloc(0) : Buffer.isBuffer(o.body) ? o.body : Buffer.from(o.body, 'utf8');
      let req = `${method} ${o.path} HTTP/1.1\r\nHost: ${host}:${port}\r\n`;
      for (const [k, v] of o.headers ?? []) req += `${k}: ${v}\r\n`;
      if (o.chunkSize) {
        req += 'Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n';
        socket.write(req, 'latin1');
        for (let i = 0; i < body.length; i += o.chunkSize) {
          const part = body.subarray(i, i + o.chunkSize);
          socket.write(part.length.toString(16) + '\r\n');
          socket.write(part);
          socket.write('\r\n');
        }
        socket.write('0\r\n\r\n');
        return;
      }
      const declared = o.contentLength === undefined ? (body.length > 0 || method === 'POST' ? body.length : null) : o.contentLength;
      if (declared !== null) req += `Content-Length: ${declared}\r\n`;
      req += 'Connection: close\r\n\r\n';
      socket.write(Buffer.concat([Buffer.from(req, 'latin1'), body]));
    });
    socket.on('data', (c: Buffer) => chunks.push(c));
    socket.on('error', (e: NodeJS.ErrnoException) => {
      if (chunks.length) done(parseReply(Buffer.concat(chunks)));
      else done({ status: 0, headers: {}, body: '', networkError: e.code ?? e.message });
    });
    socket.on('close', () => done(parseReply(Buffer.concat(chunks))));
  });
}

/** Conexão TCP aberta que não envia nada (ou só AText); informa quando o servidor fechou. */
export class IdleSocket {
  closedAt: number | null = null;
  readonly openedAt = Date.now();
  received = Buffer.alloc(0);
  private constructor(readonly socket: net.Socket) {}

  static async open(port: number, host = '127.0.0.1', text?: string): Promise<IdleSocket> {
    const socket = net.connect({ host, port });
    const s = new IdleSocket(socket);
    await new Promise<void>((resolve, reject) => { socket.once('connect', () => resolve()); socket.once('error', reject); });
    socket.on('data', (c: Buffer) => { s.received = Buffer.concat([s.received, c]); });
    socket.on('close', () => { s.closedAt = Date.now(); });
    socket.on('error', () => { /* o servidor pode derrubar a conexão */ });
    if (text) socket.write(text, 'latin1');
    return s;
  }

  write(text: string): void {
    this.socket.write(text, 'latin1');
  }

  async waitClosed(timeoutMs: number): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (this.closedAt === null) {
      if (Date.now() > deadline) throw new Error(`a conexão não foi fechada pelo servidor em ${timeoutMs} ms`);
      await sleep(20);
    }
    return this.closedAt - this.openedAt;
  }

  destroy(): void {
    this.socket.destroy();
  }
}

export interface WsOptions {
  host?: string;
  origin?: string;
  headers?: Array<[string, string]>;
}

/** Canal WebSocket por socket cru: escolhe Origin e cabeçalhos; quadros mascarados. */
export class Ws {
  status = 0;
  headers: Record<string, string> = {};
  body = '';
  frames: Array<{ opcode: number; payload: Buffer }> = [];
  ended = false;
  private buffer = Buffer.alloc(0);
  private headerDone = false;
  private constructor(private readonly socket: net.Socket) {}

  static async open(port: number, o: WsOptions = {}): Promise<Ws> {
    const host = o.host ?? '127.0.0.1';
    const socket = net.connect({ host, port });
    const ws = new Ws(socket);
    await new Promise<void>((resolve, reject) => { socket.once('connect', () => resolve()); socket.once('error', reject); });
    socket.on('data', (c: Buffer) => ws.onData(c));
    socket.on('close', () => { ws.ended = true; });
    socket.on('error', () => { ws.ended = true; });
    let req = `GET /ws HTTP/1.1\r\nHost: ${host}:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
      `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString('base64')}\r\nSec-WebSocket-Version: 13\r\n`;
    if (o.origin !== undefined) req += `Origin: ${o.origin}\r\n`;
    for (const [k, v] of o.headers ?? []) req += `${k}: ${v}\r\n`;
    socket.write(req + '\r\n', 'latin1');
    const deadline = Date.now() + 5000;
    while (!ws.headerDone && !ws.ended && Date.now() < deadline) await sleep(5);
    if (!ws.headerDone && ws.ended) return ws;   // fechada sem resposta
    if (!ws.headerDone) throw new Error('resposta da abertura não chegou');
    if (ws.status !== 101) await ws.waitFor(() => ws.ended, 3000, 'fim da resposta de recusa');
    return ws;
  }

  private onData(chunk: Buffer): void {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    if (!this.headerDone) {
      const sep = this.buffer.indexOf('\r\n\r\n');
      if (sep < 0) return;
      const head = this.buffer.subarray(0, sep).toString('latin1').split('\r\n');
      this.status = Number(head[0].split(' ')[1] ?? 0);
      for (const line of head.slice(1)) {
        const i = line.indexOf(':');
        if (i > 0) this.headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
      }
      this.buffer = this.buffer.subarray(sep + 4);
      this.headerDone = true;
    }
    if (this.status !== 101) {
      this.body += this.buffer.toString('utf8');
      this.buffer = Buffer.alloc(0);
      return;
    }
    for (;;) {
      if (this.buffer.length < 2) return;
      let len = this.buffer[1] & 0x7f;
      let off = 2;
      if (len === 126) { if (this.buffer.length < 4) return; len = this.buffer.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (this.buffer.length < 10) return; len = Number(this.buffer.readBigUInt64BE(2)); off = 10; }
      if (this.buffer.length < off + len) return;
      this.frames.push({ opcode: this.buffer[0] & 0x0f, payload: Buffer.from(this.buffer.subarray(off, off + len)) });
      this.buffer = this.buffer.subarray(off + len);
    }
  }

  get json(): any {
    try { return JSON.parse(this.body); } catch { return undefined; }
  }

  sendText(text: string): void {
    const data = Buffer.from(text, 'utf8');
    const key = crypto.randomBytes(4);
    const head = data.length < 126 ? Buffer.from([0x81, 0x80 | data.length])
      : Buffer.from([0x81, 0x80 | 126, data.length >> 8, data.length & 0xff]);
    this.socket.write(Buffer.concat([head, key, Buffer.from(data.map((v, i) => v ^ key[i & 3]))]));
  }

  send(obj: unknown): void {
    this.sendText(JSON.stringify(obj));
  }

  /** Fecha com 1000 (como uma aba fechada). */
  close(): void {
    if (this.ended) return;
    const key = crypto.randomBytes(4);
    const payload = Buffer.from([0x03, 0xe8]);
    try {
      this.socket.write(Buffer.concat([Buffer.from([0x88, 0x82]), key, Buffer.from(payload.map((v, i) => v ^ key[i & 3]))]));
      this.socket.end();
    } catch { /* já fechado */ }
  }

  destroy(): void {
    this.socket.destroy();
  }

  texts(): any[] {
    return this.frames.filter((f) => f.opcode === 1).map((f) => JSON.parse(f.payload.toString('utf8')));
  }

  closeCode(): number | null {
    const f = this.frames.find((x) => x.opcode === 8);
    return f && f.payload.length >= 2 ? f.payload.readUInt16BE(0) : null;
  }

  async waitFor(pred: () => boolean, timeoutMs = 3000, what = 'condição'): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (!pred()) {
      if (Date.now() > deadline) {
        throw new Error(`${what} não ocorreu em ${timeoutMs} ms; recebido: ${this.texts().map((t) => JSON.stringify(t).slice(0, 120)).join(' | ')}`);
      }
      await sleep(10);
    }
  }

  /** Entra na sala e espera o bem_vindo. */
  async enter(code: string, token: string): Promise<any> {
    this.send({ tipo: 'entrar', protocolo: 1, sala: code, token });
    await this.waitFor(() => this.texts().some((m) => m.tipo === 'bem_vindo' || m.tipo === 'erro'), 3000, 'bem_vindo');
    return this.texts().find((m) => m.tipo === 'bem_vindo' || m.tipo === 'erro');
  }
}

/** Memória privada comprometida (bytes) do servidor que escuta em APort, lida pelo Windows. */
export function serverPrivateBytes(port: number): number {
  const script = `$p = Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe'" | ` +
    `Where-Object { $_.CommandLine -match '--port ${port}\\b' } | Select-Object -First 1; ` +
    `if ($p) { [string](Get-Process -Id $p.ProcessId).PrivateMemorySize64 } else { '-1' }`;
  const out = execFileSync('powershell.exe', ['-NoProfile', '-Command', script], { encoding: 'utf8', windowsHide: true });
  return Number(out.trim());
}

/** Códigos de sala válidos e (quase certamente) inexistentes. */
export function randomCode(): string {
  const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  let s = '';
  for (const b of crypto.randomBytes(6)) s += alphabet[b % alphabet.length];
  return s;
}

/** Cabeçalhos de segurança de toda resposta (B11). */
export function securityHeaderProblems(label: string, r: HttpReply | { headers: Record<string, string>; status: number }, page = false): string[] {
  const out: string[] = [];
  if (r.headers['x-content-type-options'] !== 'nosniff') out.push(`${label} (${r.status}): sem X-Content-Type-Options: nosniff`);
  if (r.headers['referrer-policy'] !== 'no-referrer') out.push(`${label} (${r.status}): sem Referrer-Policy: no-referrer`);
  const csp = r.headers['content-security-policy'] ?? '';
  if (page) {
    if (!csp.includes("default-src 'self'")) out.push(`${label}: CSP sem default-src 'self' (${csp})`);
    if (!csp.includes("frame-ancestors 'none'")) out.push(`${label}: CSP sem frame-ancestors 'none' (${csp})`);
    if (r.headers['x-frame-options'] !== 'DENY') out.push(`${label}: sem X-Frame-Options: DENY`);
  }
  return out;
}

const EXE = process.env.PW_SERVER_EXE || path.resolve(__dirname, '..', '..', '..', 'server', 'bin', 'TicTacToeServer.exe');
const WWW = path.resolve(__dirname, '..', '..', '..', 'web');

/**
 * Servidor dedicado que espera o /health em AHost (o startServer de
 * server-process.ts só olha 127.0.0.1, o que não serve para --bind <IP privado>).
 */
export async function startServerOn(host: string, name: string, port: number, args: string[]): Promise<DedicatedServer> {
  const logDir = path.resolve(__dirname, '..', '..', 'test-results', 'servers');
  fs.mkdirSync(logDir, { recursive: true });
  const logFile = path.join(logDir, `${name}.log`);
  const out = fs.openSync(logFile, 'w');
  const proc: ChildProcess = spawn(EXE, ['--port', String(port), '--www', WWW, ...args], { stdio: ['ignore', out, out], windowsHide: true });
  let exitCode: number | null | undefined;
  const exited = new Promise<number | null>((resolve) => proc.on('exit', (code) => { exitCode = code; resolve(code); }));
  const deadline = Date.now() + 10_000;
  for (;;) {
    if (exitCode !== undefined) { fs.closeSync(out); throw new Error(`o servidor ${name} terminou com código ${exitCode}; ver ${logFile}`); }
    if ((await http(port, { host, path: '/health', timeoutMs: 1000 })).status === 200) break;
    if (Date.now() > deadline) { proc.kill(); fs.closeSync(out); throw new Error(`o servidor ${name} não respondeu em ${host}:${port}`); }
    await sleep(100);
  }
  return {
    port,
    baseURL: `http://${host}:${port}`,
    logFile,
    output: () => fs.readFileSync(logFile, 'utf8'),
    async stop() {
      if (exitCode === undefined) proc.kill();
      const code = await exited;
      fs.closeSync(out);
      return code;
    },
  };
}
