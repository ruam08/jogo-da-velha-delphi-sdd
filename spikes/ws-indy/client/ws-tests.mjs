// Prova de conceito da Entrega O0 (descartável).
// Testes do canal WebSocket do WsSpike.exe sem navegador: WebSocket nativo do
// Node (sem pacotes) e socket cru (node:net) para pedidos e quadros inválidos.
//
// Uso:
//   node ws-tests.mjs basic --port 8790
//   node ws-tests.mjs idle  --port 8791            (servidor com --idle-seconds 3)
//   node ws-tests.mjs load  --port 8790 --clients 50 --seconds 30
//   node ws-tests.mjs hold  --port 8792 --clients 20 --ready <arq> --out <arq>
//
// Saída: uma linha [PASSOU]/[FALHOU] por verificação e um RESUMO no fim.
// Código de saída: 0 = tudo passou; 1 = alguma falha.

import net from 'node:net';
import crypto from 'node:crypto';
import fs from 'node:fs';

const args = process.argv.slice(2);
const suite = args[0];
const opt = (name, def) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
};
const PORT = Number(opt('port', '8790'));
const BASE = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}/ws`;
const RFC_KEY = 'dGhlIHNhbXBsZSBub25jZQ==';
const RFC_ACCEPT = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=';

const results = [];
function check(id, description, ok, detail = '') {
  results.push({ id, description, ok: !!ok, detail });
  console.log(`[${ok ? 'PASSOU' : 'FALHOU'}] ${id} ${description}${detail ? ' | ' + detail : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function stats() {
  const res = await fetch(BASE + '/stats');
  return res.json();
}

async function waitFor(fn, timeoutMs, stepMs = 25) {
  const start = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - start > timeoutMs) return null;
    await sleep(stepMs);
  }
}

// ---------------------------------------------------------------------------
// Cliente WebSocket nativo (o mesmo objeto que o navegador oferece)

class Client {
  constructor(url = WS_URL) {
    this.messages = [];
    this.closeInfo = null;
    this.errors = 0;
    this.ws = new WebSocket(url);
    this.ws.binaryType = 'arraybuffer';
    this.opened = new Promise((resolve, reject) => {
      this.ws.addEventListener('open', () => resolve(true));
      this.ws.addEventListener('error', () => { this.errors++; reject(new Error('erro ao abrir')); });
    });
    this.opened.catch(() => {});
    this.closed = new Promise((resolve) => {
      this.ws.addEventListener('close', (e) => {
        this.closeInfo = { code: e.code, reason: e.reason, at: Date.now() };
        resolve(this.closeInfo);
      });
    });
    this.ws.addEventListener('message', (e) => this.messages.push({ data: e.data, at: Date.now() }));
  }
  send(data) { this.ws.send(data); }
  close(code, reason) { this.ws.close(code, reason); }
  async next(pred, timeoutMs = 2000) {
    return waitFor(() => this.messages.find((m) => typeof m.data === 'string' && pred(m.data)), timeoutMs, 5);
  }
  welcomeId() {
    const m = this.messages.find((x) => typeof x.data === 'string' && x.data.startsWith('ola:'));
    return m ? m.data.slice(4) : null;
  }
}

async function openClient(timeoutMs = 3000) {
  const c = new Client();
  await Promise.race([c.opened, sleep(timeoutMs).then(() => { throw new Error('tempo esgotado abrindo o canal'); })]);
  await c.next((d) => d.startsWith('ola:'), timeoutMs);
  return c;
}

// ---------------------------------------------------------------------------
// Socket cru

function maskedFrame(opcode, payload, fin = true) {
  const data = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8');
  const mask = crypto.randomBytes(4);
  let header;
  if (data.length < 126) {
    header = Buffer.from([(fin ? 0x80 : 0) | opcode, 0x80 | data.length]);
  } else if (data.length <= 0xffff) {
    header = Buffer.from([(fin ? 0x80 : 0) | opcode, 0x80 | 126, data.length >> 8, data.length & 255]);
  } else {
    header = Buffer.alloc(10);
    header[0] = (fin ? 0x80 : 0) | opcode;
    header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(data.length), 2);
  }
  const body = Buffer.alloc(data.length);
  for (let i = 0; i < data.length; i++) body[i] = data[i] ^ mask[i & 3];
  return Buffer.concat([header, mask, body]);
}

function unmaskedFrame(opcode, payload) {
  const data = Buffer.from(payload, 'utf8');
  return Buffer.concat([Buffer.from([0x80 | opcode, data.length]), data]);
}

// Lê quadros do servidor (sem máscara) a partir de um buffer acumulado.
function parseServerFrames(buf) {
  const frames = [];
  let off = 0;
  for (;;) {
    if (buf.length - off < 2) break;
    const b0 = buf[off];
    const b1 = buf[off + 1];
    let len = b1 & 0x7f;
    let h = 2;
    if (len === 126) { if (buf.length - off < 4) break; len = buf.readUInt16BE(off + 2); h = 4; }
    else if (len === 127) { if (buf.length - off < 10) break; len = Number(buf.readBigUInt64BE(off + 2)); h = 10; }
    const masked = (b1 & 0x80) !== 0;
    if (masked) h += 4;
    if (buf.length - off < h + len) break;
    const payload = buf.subarray(off + h, off + h + len);
    const frame = { fin: (b0 & 0x80) !== 0, opcode: b0 & 0x0f, masked, payload };
    if (frame.opcode === 8) {
      frame.code = payload.length >= 2 ? payload.readUInt16BE(0) : 1005;
      frame.reason = payload.length > 2 ? payload.subarray(2).toString('utf8') : '';
    } else {
      frame.text = payload.toString('utf8');
    }
    frames.push(frame);
    off += h + len;
  }
  return { frames, rest: buf.subarray(off) };
}

// Abre um socket, envia o pedido HTTP e separa a resposta do que vier depois.
function rawRequest(requestText, { keepOpen = false, timeoutMs = 3000 } = {}) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port: PORT });
    let buf = Buffer.alloc(0);
    let done = false;
    const state = { socket, frames: [], ended: false, endedAt: null, statusLine: '', headers: {}, rawHeaders: '' };
    const timer = setTimeout(() => {
      if (!done) { done = true; socket.destroy(); reject(new Error('tempo esgotado esperando a resposta HTTP')); }
    }, timeoutMs);
    socket.on('connect', () => socket.write(requestText));
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      if (!done) {
        const sep = buf.indexOf('\r\n\r\n');
        if (sep < 0) return;
        const head = buf.subarray(0, sep).toString('latin1');
        state.rawHeaders = head;
        const lines = head.split('\r\n');
        state.statusLine = lines[0];
        for (const line of lines.slice(1)) {
          const i = line.indexOf(':');
          if (i > 0) state.headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
        }
        buf = buf.subarray(sep + 4);
        done = true;
        clearTimeout(timer);
        if (!keepOpen) socket.end();
        resolve(state);
      }
      if (state.statusLine.includes(' 101 ')) {
        const { frames, rest } = parseServerFrames(buf);
        state.frames.push(...frames.map((f) => ({ ...f, at: Date.now() })));
        buf = rest;
      } else {
        state.body = (state.body ?? '') + buf.toString('utf8');
        buf = Buffer.alloc(0);
      }
    });
    socket.on('error', (e) => { if (!done) { done = true; clearTimeout(timer); reject(e); } });
    socket.on('close', () => { state.ended = true; state.endedAt = Date.now(); });
  });
}

function upgradeRequest({ key = RFC_KEY, version = '13', upgrade = 'websocket', connection = 'Upgrade', origin, method = 'GET' } = {}) {
  let r = `${method} /ws HTTP/1.1\r\nHost: 127.0.0.1:${PORT}\r\n`;
  if (upgrade !== null) r += `Upgrade: ${upgrade}\r\n`;
  if (connection !== null) r += `Connection: ${connection}\r\n`;
  if (key !== null) r += `Sec-WebSocket-Key: ${key}\r\n`;
  if (version !== null) r += `Sec-WebSocket-Version: ${version}\r\n`;
  if (origin) r += `Origin: ${origin}\r\n`;
  if (method !== 'GET') r += 'Content-Length: 0\r\n';
  return r + '\r\n';
}

async function rawOpen(extra = {}) {
  const s = await rawRequest(upgradeRequest(extra), { keepOpen: true });
  await waitFor(() => s.frames.find((f) => f.text && f.text.startsWith('ola:')), 2000, 5);
  return s;
}

async function closeFrameOf(s, timeoutMs = 3000) {
  return waitFor(() => s.frames.find((f) => f.opcode === 8), timeoutMs, 5);
}

// ---------------------------------------------------------------------------
// Suítes

async function suiteBasic() {
  const before = await stats();
  check('T-00', 'Servidor sem canais abertos no início', before.ativas === 0, JSON.stringify(before));

  // T-01: handshake por socket cru com a chave do exemplo da RFC 6455.
  const s1 = await rawRequest(upgradeRequest(), { keepOpen: true });
  await waitFor(() => s1.frames.length > 0, 2000, 5);
  const hello = s1.frames[0];
  check('T-01', 'Handshake: 101, Upgrade/Connection/Accept corretos, sem Content-Length nem "Connection: close"; primeira mensagem "ola:<id>" sem máscara',
    s1.statusLine === 'HTTP/1.1 101 Switching Protocols' &&
    s1.headers['upgrade'] === 'websocket' && s1.headers['connection'] === 'Upgrade' &&
    s1.headers['sec-websocket-accept'] === RFC_ACCEPT && !('content-length' in s1.headers) &&
    !!hello && hello.opcode === 1 && !hello.masked && /^ola:\d+$/.test(hello.text),
    `${s1.statusLine} | cabeçalhos: ${s1.rawHeaders.split('\r\n').slice(1).join('; ')} | 1ª msg: ${hello ? hello.text : '(nenhuma)'}`);
  s1.socket.write(maskedFrame(8, Buffer.from([0x03, 0xe8])));
  await closeFrameOf(s1);
  s1.socket.destroy();

  // T-02/T-03: dois clientes simultâneos.
  const a = await openClient();
  const b = await openClient();
  const text = 'eco de teste com acentos: ação, coração, ✓';
  a.send(text);
  const echo = await a.next((d) => d.startsWith('eco:'));
  check('T-02', 'Dois clientes WebSocket nativos do Node abertos ao mesmo tempo; eco com acentos (UTF-8) correto',
    !!a.welcomeId() && !!b.welcomeId() && a.welcomeId() !== b.welcomeId() && echo && echo.data === 'eco:' + text,
    `ids ${a.welcomeId()} e ${b.welcomeId()}; eco: ${echo ? echo.data : '(nenhum)'}`);

  a.send('todos:olá, B');
  const toB = await b.next((d) => d.startsWith('de:'));
  const ack = await a.next((d) => d.startsWith('enviado:'));
  check('T-03', 'Mensagem de A chega a B ("de:<idA>:...") e A recebe a confirmação',
    toB && toB.data === `de:${a.welcomeId()}:olá, B` && ack && Number(ack.data.slice(8)) >= 1,
    `B recebeu: ${toB ? toB.data : '(nada)'}; A recebeu: ${ack ? ack.data : '(nada)'}`);

  // T-04: envio a partir de outra thread do servidor (requisição HTTP).
  const t0 = Date.now();
  const pushRes = await fetch(BASE + '/push', { method: 'POST', body: 'notícia de outra thread' });
  const pushJson = await pushRes.json();
  const pa = await a.next((d) => d === 'push:notícia de outra thread');
  const pb = await b.next((d) => d === 'push:notícia de outra thread');
  const lat = pa && pb ? Math.max(pa.at, pb.at) - t0 : null;
  check('T-04', 'POST /push (outra thread) chega aos dois canais em menos de 200 ms',
    pushRes.status === 200 && pa && pb && lat < 200, `resposta ${JSON.stringify(pushJson)}; latência ${lat} ms`);

  // T-05: fragmentação com ping no meio (socket cru).
  const s5 = await rawOpen();
  s5.socket.write(Buffer.concat([
    maskedFrame(1, 'ab', false), maskedFrame(9, 'p'), maskedFrame(0, 'cd', false), maskedFrame(0, 'ef', true)]));
  const pong5 = await waitFor(() => s5.frames.find((f) => f.opcode === 10), 2000, 5);
  const eco5 = await waitFor(() => s5.frames.find((f) => f.text === 'eco:abcdef'), 2000, 5);
  check('T-05', 'Mensagem em 3 fragmentos com ping no meio: pong com o mesmo conteúdo e eco da mensagem montada',
    pong5 && pong5.payload.toString() === 'p' && !!eco5, `pong: ${pong5 ? pong5.payload.toString() : '-'}; eco: ${eco5 ? eco5.text : '-'}`);
  s5.socket.destroy();

  // T-06: UTF-8 inválido.
  const s6 = await rawOpen();
  s6.socket.write(maskedFrame(1, Buffer.from([0xc3, 0x28])));
  const c6 = await closeFrameOf(s6);
  check('T-06', 'Texto com UTF-8 inválido -> fechamento 1007', c6 && c6.code === 1007, c6 ? `${c6.code} ${c6.reason}` : 'sem fechamento');
  s6.socket.destroy();

  // T-07: quadro binário (cliente nativo).
  const c7 = await openClient();
  c7.send(new Uint8Array([1, 2, 3]));
  const cl7 = await Promise.race([c7.closed, sleep(3000).then(() => null)]);
  check('T-07', 'Quadro binário -> fechamento 1003', cl7 && cl7.code === 1003, cl7 ? `${cl7.code} ${cl7.reason}` : 'não fechou');

  // T-08: quadro sem máscara.
  const s8 = await rawOpen();
  s8.socket.write(unmaskedFrame(1, 'sem mascara'));
  const c8 = await closeFrameOf(s8);
  check('T-08', 'Quadro do cliente sem máscara -> fechamento 1002', c8 && c8.code === 1002, c8 ? `${c8.code} ${c8.reason}` : 'sem fechamento');
  s8.socket.destroy();

  // T-09: limite de 4096 bytes.
  const c9 = await openClient();
  c9.send('x'.repeat(4096));
  const e9 = await c9.next((d) => d.startsWith('eco:'));
  c9.send('y'.repeat(4097));
  const cl9 = await Promise.race([c9.closed, sleep(3000).then(() => null)]);
  check('T-09', 'Mensagem de 4096 bytes aceita; de 4097 bytes -> fechamento 1009',
    e9 && e9.data.length === 4100 && cl9 && cl9.code === 1009, `eco ${e9 ? e9.data.length : '-'} caracteres; fechamento ${cl9 ? cl9.code : '-'}`);

  // T-10: pedidos de abertura inválidos.
  const r1 = await rawRequest(upgradeRequest({ upgrade: null }));
  const r2 = await rawRequest(upgradeRequest({ version: '8' }));
  const r3 = await rawRequest(upgradeRequest({ key: 'curta==' }));
  const r4 = await rawRequest(upgradeRequest({ method: 'POST' }));
  const r5 = await rawRequest(upgradeRequest({ origin: 'http://atacante.test' }));
  const r6 = await rawRequest(upgradeRequest({ origin: `http://127.0.0.1:${PORT}` }), { keepOpen: true });
  const code = (r) => r.statusLine.split(' ')[1];
  check('T-10', 'Aberturas inválidas: sem Upgrade 400; versão 8 426 (+Sec-WebSocket-Version: 13); chave curta 400; POST 405 (Allow: GET); origem externa 403; origem local 101',
    code(r1) === '400' && code(r2) === '426' && r2.headers['sec-websocket-version'] === '13' &&
    code(r3) === '400' && code(r4) === '405' && r4.headers['allow'] === 'GET' && code(r5) === '403' && code(r6) === '101',
    [r1, r2, r3, r4, r5, r6].map(code).join(', '));
  r6.socket.destroy();

  // T-11: fechamento normal pelo cliente.
  const base11 = (await stats()).ativas;
  b.close(1000, 'tchau');
  const cl11 = await Promise.race([b.closed, sleep(3000).then(() => null)]);
  const gone11 = await waitFor(async () => (await stats()).ativas <= base11 - 1, 2000);
  check('T-11', 'Cliente fecha com 1000: servidor confirma e encerra a sessão em até 2 s',
    cl11 && cl11.code === 1000 && !!gone11, `fechamento ${cl11 ? cl11.code : '-'}; canais ${base11} -> ${(await stats()).ativas}`);

  // T-12: desconexão abrupta (sem quadro de fechamento).
  const s12 = await rawOpen();
  // Espera as sessões dos testes anteriores terminarem, para medir só esta.
  await waitFor(async () => (await stats()).ativas === 1, 3000);
  const closed12 = (await stats()).fechadas;
  const t12 = Date.now();
  s12.socket.destroy();
  const gone12 = await waitFor(async () => (await stats()).fechadas >= closed12 + 1, 3000);
  check('T-12', 'Cliente some sem fechar o canal: o servidor detecta e encerra a sessão em até 2 s',
    !!gone12 && Date.now() - t12 <= 2000, `detectado em ${Date.now() - t12} ms`);

  // T-13: fechamento pedido ao servidor.
  a.send('fechar');
  const cl13 = await Promise.race([a.closed, sleep(3000).then(() => null)]);
  check('T-13', 'Servidor inicia o fechamento (1000, "pedido do cliente")',
    cl13 && cl13.code === 1000 && cl13.reason === 'pedido do cliente', cl13 ? `${cl13.code} ${cl13.reason}` : 'não fechou');

  // T-14: ping de controle.
  const s14 = await rawOpen();
  s14.socket.write(maskedFrame(9, 'abc'));
  const p14 = await waitFor(() => s14.frames.find((f) => f.opcode === 10), 2000, 5);
  check('T-14', 'Ping de controle -> pong com o mesmo conteúdo', p14 && p14.payload.toString() === 'abc', p14 ? p14.payload.toString() : '-');
  s14.socket.write(maskedFrame(8, Buffer.from([0x03, 0xe8])));
  await closeFrameOf(s14);
  s14.socket.destroy();

  const end = await waitFor(async () => { const s = await stats(); return s.ativas === 0 ? s : null; }, 3000);
  const final = end ?? (await stats());
  check('T-15', 'No fim: nenhum canal aberto e nenhum erro inesperado no servidor', final.ativas === 0 && final.erros === 0, JSON.stringify(final));
}

async function suiteIdle() {
  const s = await rawOpen();
  const t0 = Date.now();
  const c = await closeFrameOf(s, 8000);
  const elapsed = Date.now() - t0;
  check('I-01', 'Cliente calado (servidor com 3 s de inatividade) -> fechamento 4408 entre 2,5 e 5,5 s',
    c && c.code === 4408 && elapsed >= 2500 && elapsed <= 5500, c ? `${c.code} "${c.reason}" em ${elapsed} ms` : 'sem fechamento');
  s.socket.destroy();

  const k = await openClient();
  let ok = true;
  for (let i = 0; i < 7; i++) {
    k.send('vivo ' + i);
    const e = await k.next((d) => d === 'eco:vivo ' + i, 2000);
    if (!e) ok = false;
    await sleep(1000);
  }
  check('I-02', 'Cliente ativo (1 mensagem por segundo durante 7 s) continua conectado', ok && !k.closeInfo,
    k.closeInfo ? `fechado com ${k.closeInfo.code}` : 'aberto');
  k.close(1000, 'fim');
  await k.closed;
}

async function suiteLoad() {
  const n = Number(opt('clients', '50'));
  const seconds = Number(opt('seconds', '30'));
  const clients = [];
  let openFail = 0;
  await Promise.all(Array.from({ length: n }, async () => {
    try { clients.push(await openClient(5000)); } catch { openFail++; }
  }));
  const st = await stats();
  check('L-01', `${n} canais abertos ao mesmo tempo`, clients.length === n && openFail === 0 && st.ativas === n, `abertos ${clients.length}; falhas ${openFail}; servidor: ${JSON.stringify(st)}`);

  let sent = 0;
  let pushes = 0;
  const startedAt = Date.now();
  const timers = clients.map((c, idx) => setInterval(() => {
    if (c.ws.readyState === 1) { c.send(`m:${idx}:${c.seq = (c.seq ?? 0) + 1}`); sent++; }
  }, 200));
  const pushTimer = setInterval(async () => {
    pushes++;
    await fetch(BASE + '/push', { method: 'POST', body: 'carga ' + pushes }).catch(() => {});
  }, 1000);
  await sleep(seconds * 1000);
  timers.forEach(clearInterval);
  clearInterval(pushTimer);
  await sleep(1500);

  let missing = 0;
  let disorder = 0;
  let pushMissing = 0;
  for (const [idx, c] of clients.entries()) {
    const echoes = c.messages.filter((m) => typeof m.data === 'string' && m.data.startsWith(`eco:m:${idx}:`)).map((m) => Number(m.data.split(':')[3]));
    missing += (c.seq ?? 0) - echoes.length;
    for (let i = 1; i < echoes.length; i++) if (echoes[i] !== echoes[i - 1] + 1) disorder++;
    const got = c.messages.filter((m) => typeof m.data === 'string' && m.data.startsWith('push:carga ')).length;
    pushMissing += Math.max(0, pushes - got);
  }
  const closedEarly = clients.filter((c) => c.closeInfo).length;
  check('L-02', `${seconds} s de tráfego: todas as respostas chegam, em ordem, e todos os envios de outra thread chegam a todos`,
    missing === 0 && disorder === 0 && pushMissing === 0 && closedEarly === 0,
    `mensagens enviadas ${sent}, sem resposta ${missing}, fora de ordem ${disorder}; envios por /push ${pushes} x ${n}, perdidos ${pushMissing}; fechados antes da hora ${closedEarly}; duração ${Date.now() - startedAt} ms`);

  clients.forEach((c) => c.close(1000, 'fim da carga'));
  await Promise.all(clients.map((c) => Promise.race([c.closed, sleep(3000)])));
  const end = await waitFor(async () => { const s = await stats(); return s.ativas === 0 ? s : null; }, 3000);
  const final = end ?? (await stats());
  check('L-03', 'Todos os canais fechados no fim e nenhum erro no servidor', final.ativas === 0 && final.erros === 0, JSON.stringify(final));
}

// Mantém N canais abertos até o servidor fechá-los (teste do Ctrl+C).
async function suiteHold() {
  const n = Number(opt('clients', '20'));
  const readyFile = opt('ready');
  const outFile = opt('out');
  const clients = [];
  await Promise.all(Array.from({ length: n }, async () => { clients.push(await openClient(5000)); }));
  fs.writeFileSync(readyFile, String(clients.length));
  console.log(`hold: ${clients.length} canais abertos; aguardando o servidor fechar`);
  await Promise.race([Promise.all(clients.map((c) => c.closed)), sleep(20000)]);
  const codes = clients.map((c) => (c.closeInfo ? c.closeInfo.code : null));
  const reasons = [...new Set(clients.map((c) => (c.closeInfo ? c.closeInfo.reason : '(aberto)')))];
  const times = clients.filter((c) => c.closeInfo).map((c) => c.closeInfo.at);
  fs.writeFileSync(outFile, JSON.stringify({ clients: n, codes, reasons, firstCloseAt: Math.min(...times), lastCloseAt: Math.max(...times) }));
  const ok = codes.every((c) => c === 1001);
  check('H-01', `Os ${n} canais recebem o fechamento 1001 do servidor`, ok, `códigos: ${[...new Set(codes)].join(', ')}; motivos: ${reasons.join(', ')}`);
}

// ---------------------------------------------------------------------------

const suites = { basic: suiteBasic, idle: suiteIdle, load: suiteLoad, hold: suiteHold };
if (!suites[suite]) {
  console.log('Uso: node ws-tests.mjs basic|idle|load|hold --port N [...]');
  process.exit(2);
}
console.log(`Node ${process.version}; WebSocket nativo: ${typeof WebSocket === 'function' ? 'sim' : 'NÃO'}; suíte ${suite}; porta ${PORT}`);
try {
  if (typeof WebSocket !== 'function') throw new Error('WebSocket global ausente nesta versão do Node');
  await suites[suite]();
} catch (e) {
  check('X-01', 'Suíte terminou sem exceção', false, e && e.stack ? e.stack.split('\n').slice(0, 3).join(' / ') : String(e));
}
const failed = results.filter((r) => !r.ok).length;
console.log(`RESUMO: ${results.length - failed} passaram, ${failed} falharam`);
const outJson = opt('json');
if (outJson) fs.writeFileSync(outJson, JSON.stringify(results, null, 2));
process.exit(failed === 0 ? 0 : 1);
