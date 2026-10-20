// Validação da Entrega O3: mantém canais identificados abertos num servidor
// dedicado até ele encerrar (Ctrl+C) e registra os códigos de fechamento.
// Sem pacotes npm: fetch e WebSocket nativos do Node.
//
// Uso: node ws-hold.mjs --port 8790 --rooms 5 --ready <arquivo> --out <arquivo.json>
// O arquivo --ready é criado quando todos os canais receberam o bem_vindo.
// O --out recebe {canais, fechamentos: [{codigo, motivo}], duracaoMs}.
import fs from 'node:fs';

const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
};
const port = Number(opt('port', '8790'));
const roomsCount = Number(opt('rooms', '5'));
const readyFile = opt('ready');
const outFile = opt('out');
const base = `http://127.0.0.1:${port}`;

async function post(path, token) {
  const res = await fetch(base + path, { method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {} });
  if (res.status !== 201) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

function enter(code, token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    const info = { ws, welcome: false, close: null };
    ws.addEventListener('open', () => ws.send(JSON.stringify({ tipo: 'entrar', protocolo: 1, sala: code, token })));
    ws.addEventListener('message', (e) => {
      const m = JSON.parse(e.data);
      if (m.tipo === 'bem_vindo' && !info.welcome) { info.welcome = true; resolve(info); }
    });
    ws.addEventListener('close', (e) => { info.close = { codigo: e.code, motivo: e.reason, em: Date.now() }; if (!info.welcome) reject(new Error('fechou antes do bem_vindo')); });
    ws.addEventListener('error', () => {});
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
console.log(`${channels.length} canais identificados`);
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
