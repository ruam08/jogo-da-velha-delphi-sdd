// Validação da Entrega O6 (D-06): como tools/ws-hold.mjs (O3), mas com a
// origem escolhida (--origin), para o Ctrl+C no modo público, em que o canal
// sem Origin é recusado. O WebSocket nativo do Node não deixa escolher o
// Origin; aqui o canal é feito por socket cru (quadros mascarados).
// Sem pacotes npm.
//
// Uso: node ws-hold-origin.mjs --port 8809 --rooms 5 --origin https://jogo.test --ready <arquivo> --out <arquivo.json>
import crypto from 'node:crypto';
import fs from 'node:fs';
import net from 'node:net';

const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
};
const port = Number(opt('port', '8809'));
const roomsCount = Number(opt('rooms', '5'));
const origin = opt('origin', 'https://jogo.test');
const readyFile = opt('ready');
const outFile = opt('out');
const base = `http://127.0.0.1:${port}`;

async function post(path, token) {
  const headers = { Origin: origin };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(base + path, { method: 'POST', headers });
  if (res.status !== 201) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

function enter(code, token) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    const info = { welcome: false, close: null };
    let buf = Buffer.alloc(0);
    let upgraded = false;
    const send = (text) => {
      const data = Buffer.from(text, 'utf8');
      const key = crypto.randomBytes(4);
      const head = data.length < 126 ? Buffer.from([0x81, 0x80 | data.length]) : Buffer.from([0x81, 0x80 | 126, data.length >> 8, data.length & 0xff]);
      socket.write(Buffer.concat([head, key, Buffer.from(data.map((v, i) => v ^ key[i & 3]))]));
    };
    socket.on('connect', () => {
      socket.write(`GET /ws HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
        `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString('base64')}\r\nSec-WebSocket-Version: 13\r\nOrigin: ${origin}\r\n\r\n`);
    });
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      if (!upgraded) {
        const sep = buf.indexOf('\r\n\r\n');
        if (sep < 0) return;
        const status = buf.subarray(0, sep).toString('latin1').split(' ')[1];
        if (status !== '101') { reject(new Error(`abertura recusada: ${status}`)); socket.destroy(); return; }
        upgraded = true;
        buf = buf.subarray(sep + 4);
        send(JSON.stringify({ tipo: 'entrar', protocolo: 1, sala: code, token }));
      }
      for (;;) {
        if (buf.length < 2) return;
        let len = buf[1] & 0x7f;
        let off = 2;
        if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
        if (buf.length < off + len) return;
        const opcode = buf[0] & 0x0f;
        const payload = buf.subarray(off, off + len);
        buf = buf.subarray(off + len);
        if (opcode === 1) {
          const m = JSON.parse(payload.toString('utf8'));
          if (m.tipo === 'bem_vindo' && !info.welcome) { info.welcome = true; resolve(info); }
        } else if (opcode === 8 && !info.close) {
          info.close = { codigo: payload.length >= 2 ? payload.readUInt16BE(0) : null, motivo: payload.subarray(2).toString('utf8'), em: Date.now() };
          const key = crypto.randomBytes(4);
          socket.write(Buffer.concat([Buffer.from([0x88, 0x80 | payload.length]), key, Buffer.from(payload.map((v, i) => v ^ key[i & 3]))]));
          socket.end();
        }
      }
    });
    socket.on('close', () => { if (!info.close) info.close = { codigo: 1006, motivo: 'conexão caiu', em: Date.now() }; if (!info.welcome) reject(new Error('fechou antes do bem_vindo')); });
    socket.on('error', () => {});
  });
}

const channels = [];
for (let i = 0; i < roomsCount; i++) {
  const created = await post('/api/rooms');
  const code = created.sala.codigo;
  const joined = await post(`/api/rooms/${code}/players`);
  channels.push(await enter(code, created.jogador.token));
  channels.push(await enter(code, joined.jogador.token));
}
console.log(`${channels.length} canais identificados (origem ${origin})`);
fs.writeFileSync(readyFile, String(Date.now()));
const start = Date.now();
const deadline = start + 20000;
while (Date.now() < deadline && channels.some((c) => !c.close)) {
  await new Promise((r) => setTimeout(r, 20));
}
const result = {
  canais: channels.length,
  fechamentos: channels.map((c) => c.close ?? { codigo: null, motivo: 'não fechou em 20 s' }),
  duracaoMs: Date.now() - start,
};
fs.writeFileSync(outFile, JSON.stringify(result));
console.log(JSON.stringify(result));
process.exit(0);
