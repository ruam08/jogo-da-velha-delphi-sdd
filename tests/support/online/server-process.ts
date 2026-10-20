import { ChildProcess, spawn } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';

/*
 * Servidor dedicado (docs/plan-online.md, DTO-15): outro processo do
 * TicTacToeServer.exe real, numa porta própria e com opções próprias, para
 * testes que precisam de uma configuração diferente da do servidor da suíte
 * (por exemplo, --max-rooms pequeno). A saída do console fica em
 * test-results/servers/<nome>.log.
 */

// PW_SERVER_EXE: outro executável (cópia sabotada, na validação da entrega).
const EXE = process.env.PW_SERVER_EXE || path.resolve(__dirname, '..', '..', '..', 'server', 'bin', 'TicTacToeServer.exe');
const WWW = path.resolve(__dirname, '..', '..', '..', 'web');

export interface DedicatedServer {
  port: number;
  baseURL: string;
  logFile: string;
  /** Saída do console até agora (UTF-8). */
  output(): string;
  stop(): Promise<number | null>;
}

async function healthy(baseURL: string): Promise<boolean> {
  try {
    const res = await fetch(`${baseURL}/health`);
    return res.status === 200;
  } catch {
    return false;
  }
}

/** Executa o servidor com opções que devem ser recusadas; devolve o código de saída e a saída do console. */
export async function runServerExpectingExit(name: string, args: string[], timeoutMs = 10_000): Promise<{ code: number | null; output: string }> {
  const logDir = path.resolve(__dirname, '..', '..', 'test-results', 'servers');
  fs.mkdirSync(logDir, { recursive: true });
  const logFile = path.join(logDir, `${name}.log`);
  const out = fs.openSync(logFile, 'w');
  const proc = spawn(EXE, args, { stdio: ['ignore', out, out], windowsHide: true });
  const code = await new Promise<number | null>((resolve, reject) => {
    const timer = setTimeout(() => { proc.kill(); reject(new Error(`o servidor ${name} não terminou em ${timeoutMs} ms`)); }, timeoutMs);
    proc.on('exit', (c) => { clearTimeout(timer); resolve(c); });
  });
  fs.closeSync(out);
  return { code, output: fs.readFileSync(logFile, 'utf8') };
}

export async function startServer(name: string, port: number, args: string[] = []): Promise<DedicatedServer> {
  const baseURL = `http://127.0.0.1:${port}`;
  if (await healthy(baseURL)) throw new Error(`a porta ${port} já tem um servidor respondendo`);
  const logDir = path.resolve(__dirname, '..', '..', 'test-results', 'servers');
  fs.mkdirSync(logDir, { recursive: true });
  const logFile = path.join(logDir, `${name}.log`);
  const out = fs.openSync(logFile, 'w');
  const proc: ChildProcess = spawn(EXE, ['--port', String(port), '--www', WWW, ...args], {
    stdio: ['ignore', out, out],
    windowsHide: true,
  });
  let exitCode: number | null | undefined;
  const exited = new Promise<number | null>((resolve) => proc.on('exit', (code) => { exitCode = code; resolve(code); }));

  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    if (exitCode !== undefined) {
      fs.closeSync(out);
      throw new Error(`o servidor dedicado ${name} terminou com código ${exitCode}; ver ${logFile}`);
    }
    if (await healthy(baseURL)) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  if (!(await healthy(baseURL))) {
    proc.kill();
    fs.closeSync(out);
    throw new Error(`o servidor dedicado ${name} não respondeu em 10 s; ver ${logFile}`);
  }

  return {
    port,
    baseURL,
    logFile,
    output() {
      return fs.readFileSync(logFile, 'utf8');
    },
    async stop() {
      if (exitCode === undefined) proc.kill();
      const code = await exited;
      fs.closeSync(out);
      return code;
    },
  };
}
