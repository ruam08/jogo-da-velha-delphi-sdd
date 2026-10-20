import { test, expect } from '@playwright/test';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { DedicatedServer, runServerExpectingExit, startServer } from '../../support/online/server-process';
import {
  HttpReply, IdleSocket, TOKEN_LIKE, Ws, http, privateIPv4, randomCode, securityHeaderProblems,
  serverPrivateBytes, sleep, startServerOn,
} from '../../support/online/hardening';

/*
 * Entrega O6: endurecimento contra o TicTacToeServer.exe real, com servidores
 * dedicados (DTO-15). docs/plan-online.md, seção 13.1 (requisitos H-01 a
 * H-16 e decisões B1 a B15); docs/test-plan-online.md, OV-06, OV-07 e OV-13
 * a OV-17. Clientes diferentes são simulados com X-Forwarded-For e
 * --trust-proxy (B8) ou pelo IPv4 privado da máquina.
 */

const RATE_ERROR = { erro: { codigo: 'LIMITE_DE_REQUISICOES', mensagem: 'Muitas requisições. Tente novamente em instantes.' } };
const CONN_ERROR = { erro: { codigo: 'LIMITE_DE_CONEXOES', mensagem: 'Muitas conexões abertas a partir deste endereço.' } };
const BUSY_ERROR = { erro: { codigo: 'SERVIDOR_OCUPADO', mensagem: 'O servidor está com muitas conexões. Tente novamente em instantes.' } };
const NOT_FOUND = { erro: { codigo: 'ROTA_NAO_ENCONTRADA', mensagem: 'Rota não encontrada.' } };
const BODY_ERROR = { erro: { codigo: 'CORPO_MUITO_GRANDE', mensagem: ONLINE_MESSAGES.CORPO_MUITO_GRANDE } };
const ORIGIN = 'https://jogo.test';

const xff = (ip: string): Array<[string, string]> => [['X-Forwarded-For', ip]];
const bearer = (t: string): [string, string] => ['Authorization', `Bearer ${t}`];

/** Log do servidor sem 5xx, exceção, aviso ou token. */
function logProblems(server: DedicatedServer): string[] {
  const log = server.output();
  const out: string[] = [];
  for (const line of log.split(/\r?\n/)) {
    if (/-> 5\d\d|ERRO|AVISO|Erro fatal/.test(line) && !/-> 503 \(|limite de \d+ conexões simultâneas \(503\)/.test(line)) out.push(`log: ${line}`);
    if (TOKEN_LIKE.test(line)) out.push('log com token');
  }
  return out;
}

async function create(port: number, headers: Array<[string, string]> = [], host?: string): Promise<HttpReply & { code?: string; token?: string }> {
  const r = await http(port, { method: 'POST', path: '/api/rooms', headers, host });
  return { ...r, code: r.json?.sala?.codigo, token: r.json?.jogador?.token };
}

async function join(port: number, code: string, headers: Array<[string, string]> = []): Promise<HttpReply & { token?: string }> {
  const r = await http(port, { method: 'POST', path: `/api/rooms/${code}/players`, headers });
  return { ...r, token: r.json?.jogador?.token };
}

function move(port: number, code: string, token: string, pos: number, headers: Array<[string, string]> = []): Promise<HttpReply> {
  return http(port, { method: 'POST', path: `/api/rooms/${code}/moves`, headers: [...headers, bearer(token), ['Content-Type', 'application/json']], body: JSON.stringify({ posicao: pos }) });
}

async function withServer(name: string, port: number, args: string[], body: (s: DedicatedServer) => Promise<void>): Promise<void> {
  const server = await startServer(name, port, args);
  try {
    await body(server);
  } finally {
    await server.stop();
  }
}

test('OV-06a [CAO-53] taxas por cliente: abaixo, no limite e acima; Retry-After; clientes isolados; jogadas sem taxa; janela reabre', async () => {
  test.setTimeout(60_000);
  const port = 8793;
  await withServer('ov-06a', port, ['--trust-proxy', '--rate-create', '3', '--rate-join', '4', '--rate-ws', '2', '--rate-window-seconds', '3'], async (server) => {
    const problems: string[] = [];
    // Criação: 3 aceitas (abaixo e no limite), a 4a recusada.
    const A = xff('203.0.113.10');
    for (let i = 1; i <= 3; i++) expect((await create(port, A)).status, `criação ${i} de 3`).toBe(201);
    const over = await create(port, A);
    expect(over.status, 'criação acima do limite').toBe(429);
    expect(over.json).toEqual(RATE_ERROR);
    const retry = Number(over.headers['retry-after']);
    expect(retry, 'Retry-After entre 1 e a janela (3 s)').toBeGreaterThanOrEqual(1);
    expect(retry).toBeLessThanOrEqual(3);
    expect(over.headers['cache-control']).toBe('no-store');
    problems.push(...securityHeaderProblems('429', over));
    // Outro cliente não é afetado; só o último endereço de X-Forwarded-For conta.
    const b = await create(port, xff('203.0.113.11'));
    expect(b.status, 'outro cliente').toBe(201);
    expect((await create(port, xff('203.0.113.11, 203.0.113.10'))).status, 'último endereço = A').toBe(429);
    expect((await create(port, xff('203.0.113.10, 203.0.113.12'))).status, 'último endereço = cliente novo').toBe(201);

    // Consulta e entrada (4): GET, HEAD, GET de código inexistente (404 conta), entrada; a 5a recusada.
    const C = xff('203.0.113.20');
    expect((await http(port, { path: `/api/rooms/${b.code}`, headers: C })).status).toBe(200);
    expect((await http(port, { method: 'HEAD', path: `/api/rooms/${b.code}`, headers: C })).status).toBe(200);
    expect((await http(port, { path: `/api/rooms/${randomCode()}`, headers: C })).status).toBe(404);
    const o = await join(port, b.code!, C);
    expect(o.status, '4a consulta/entrada: no limite').toBe(201);
    const o5 = await http(port, { path: `/api/rooms/${b.code}`, headers: C });
    expect(o5.status, '5a consulta: acima').toBe(429);
    expect(o5.json).toEqual(RATE_ERROR);
    // Jogadas não têm taxa (exigem token): o mesmo cliente C joga normalmente.
    for (const [token, pos] of [[b.token!, 0], [o.token!, 1], [b.token!, 3], [o.token!, 4], [b.token!, 6]] as const) {
      expect((await move(port, b.code!, token, pos, C)).status, `jogada ${pos} do cliente C`).toBe(200);
    }

    // Abertura de canal (2): a 3a é recusada antes do 101.
    const D = xff('203.0.113.30');
    const w1 = await Ws.open(port, { headers: D });
    const w2 = await Ws.open(port, { headers: D });
    expect([w1.status, w2.status], 'duas aberturas').toEqual([101, 101]);
    w1.close();
    w2.close();
    const w3 = await Ws.open(port, { headers: D });
    expect(w3.status, '3a abertura acima do limite').toBe(429);
    expect(w3.json).toEqual(RATE_ERROR);
    expect(Number(w3.headers['retry-after'])).toBeGreaterThanOrEqual(1);
    problems.push(...securityHeaderProblems('429 do canal', w3));

    // A janela reabre depois do Retry-After.
    await sleep(3200);
    expect((await create(port, A)).status, 'A cria de novo na janela seguinte').toBe(201);
    const w4 = await Ws.open(port, { headers: D });
    expect(w4.status, 'D abre canal de novo').toBe(101);
    w4.close();

    const log = server.output();
    expect(log).toContain('limite de criação de salas: 3 por 3 s, cliente 203.0.113.10');
    expect(log).toContain('limite de consulta e entrada em salas: 4 por 3 s, cliente 203.0.113.20');
    expect(log).toContain('limite de abertura de canal: 2 por 3 s, cliente 203.0.113.30');
    problems.push(...logProblems(server));
    expect(problems).toEqual([]);
  });
});

test('OV-06b [CAO-53] capacidade de salas: no limite 503 CAPACIDADE_ESGOTADA; volta a aceitar quando uma sala fecha; outras salas não são afetadas', async () => {
  test.setTimeout(30_000);
  const port = 8794;
  await withServer('ov-06b', port, ['--max-rooms', '5'], async (server) => {
    const rooms: Array<{ code: string; token: string }> = [];
    for (let i = 1; i <= 5; i++) {
      const r = await create(port);
      expect(r.status, `sala ${i} de 5`).toBe(201);
      rooms.push({ code: r.code!, token: r.token! });
    }
    const full = await create(port);
    expect(full.status, '6a sala').toBe(503);
    expect(full.json?.erro?.codigo).toBe('CAPACIDADE_ESGOTADA');
    expect(securityHeaderProblems('503', full)).toEqual([]);
    // As salas existentes continuam funcionando: entrar e jogar.
    const o = await join(port, rooms[0].code);
    expect(o.status, 'entrar numa sala existente no limite').toBe(201);
    expect((await move(port, rooms[0].code, rooms[0].token, 4)).status).toBe(200);
    // Uma sala sai: a criação volta (de novo no limite), e a seguinte é recusada.
    expect((await http(port, { method: 'POST', path: `/api/rooms/${rooms[1].code}/leave`, headers: [bearer(rooms[1].token)] })).status).toBe(200);
    expect((await create(port)).status, 'depois de uma sala encerrada').toBe(201);
    expect((await create(port)).status, 'de novo acima do limite').toBe(503);
    expect(logProblems(server).filter((p) => !p.includes('-> 503'))).toEqual([]);
  });
});

test('OV-06c [CAO-53] cliente atrás de proxy: X-Forwarded-For só com --trust-proxy e conexão de 127.0.0.1', async () => {
  test.setTimeout(30_000);
  const ip = privateIPv4();
  if (!ip) throw new Error('sem rede local: esta máquina não tem IPv4 privado');
  await withServer('ov-06c-trust', 8806, ['--trust-proxy', '--rate-create', '2'], async (server) => {
    // Pelo IP privado (não é o proxy local): X-Forwarded-For ignorado; os três contam como o mesmo cliente.
    const s = [];
    for (const f of ['198.51.100.1', '198.51.100.2', '198.51.100.3']) s.push((await create(8806, xff(f), ip)).status);
    expect(s, 'pelo IP privado, cabeçalho ignorado').toEqual([201, 201, 429]);
    // Por 127.0.0.1, com --trust-proxy: cada endereço é um cliente.
    const t = [];
    for (const f of ['198.51.100.1', '198.51.100.2', '198.51.100.3']) t.push((await create(8806, xff(f))).status);
    expect(t, 'pelo proxy local, um cliente por endereço').toEqual([201, 201, 201]);
    expect(server.output()).toContain(`cliente ${ip}`);
  });
  await withServer('ov-06c-sem-trust', 8807, ['--rate-create', '2'], async () => {
    const s = [];
    for (const f of ['198.51.100.1', '198.51.100.2', '198.51.100.3']) s.push((await create(8807, xff(f))).status);
    expect(s, 'sem --trust-proxy, cabeçalho ignorado').toEqual([201, 201, 429]);
  });
});

test('OV-07 [CAO-55, CAO-51] modo público: /api/game* 404, cabeçalhos, / leva à página online, partida completa com a origem https; origem não substitui o token', async () => {
  test.setTimeout(60_000);
  const port = 8795;
  await withServer('ov-07', port, ['--public', '--allowed-origin', ORIGIN], async (server) => {
    const problems: string[] = [];
    const O: Array<[string, string]> = [['Origin', ORIGIN]];
    // Rotas locais desativadas, em qualquer método.
    for (const [method, path, body] of [['GET', '/api/game', ''], ['HEAD', '/api/game', ''], ['POST', '/api/game/moves', '{"posicao":0}'],
      ['POST', '/api/game/reset', ''], ['DELETE', '/api/game', ''], ['OPTIONS', '/api/game', ''], ['GET', '/api/game/moves', '']] as const) {
      const r = await http(port, { method, path, body: body || undefined, headers: body ? [['Content-Type', 'application/json']] : [] });
      expect(r.status, `${method} ${path}`).toBe(404);
      if (method !== 'HEAD') expect(r.json, `${method} ${path}: corpo`).toEqual(NOT_FOUND);
      problems.push(...securityHeaderProblems(`${method} ${path}`, r));
    }
    const health = await http(port, { path: '/health' });
    expect(health.status).toBe(200);
    problems.push(...securityHeaderProblems('/health', health));
    for (const p of ['/', '/index.html']) {
      const r = await http(port, { path: p });
      expect(r.status, `${p} redireciona`).toBe(302);
      expect(r.headers.location).toBe('/online.html');
      problems.push(...securityHeaderProblems(p, r));
    }
    const page = await http(port, { path: '/online.html' });
    expect(page.status).toBe(200);
    problems.push(...securityHeaderProblems('/online.html', page, true));
    for (const p of ['/online.js', '/online.css', '/style.css']) {
      const r = await http(port, { path: p });
      expect(r.status, p).toBe(200);
      problems.push(...securityHeaderProblems(p, r));
    }

    // Partida completa, como faria a página servida pelo proxy em https://jogo.test (B1).
    const x = await create(port, O);
    expect(x.status, 'criar com a origem configurada').toBe(201);
    const view = await http(port, { path: `/api/rooms/${x.code}` });
    expect(view.body, 'GET da sala sem token').not.toMatch(TOKEN_LIKE);
    const o = await join(port, x.code!, O);
    expect(o.status).toBe(201);
    const wx = await Ws.open(port, { origin: ORIGIN });
    const wo = await Ws.open(port, { origin: ORIGIN });
    expect([wx.status, wo.status]).toEqual([101, 101]);
    expect((await wx.enter(x.code!, x.token!)).tipo).toBe('bem_vindo');
    expect((await wo.enter(x.code!, o.token!)).tipo).toBe('bem_vindo');
    for (const [token, pos] of [[x.token!, 0], [o.token!, 3], [x.token!, 1], [o.token!, 4], [x.token!, 2]] as const) {
      const r = await move(port, x.code!, token, pos, O);
      expect(r.status, `jogada ${pos}`).toBe(200);
      problems.push(...securityHeaderProblems(`jogada ${pos}`, r));
    }
    const final = (await http(port, { path: `/api/rooms/${x.code}` })).json.sala;
    expect(final.partida.status).toBe('VITORIA');
    for (const [label, w] of [['X', wx], ['O', wo]] as const) {
      await w.waitFor(() => w.texts().some((m) => m.sala?.versao === final.versao), 3000, `${label}: estado final`);
      const msgs = w.texts().filter((m) => m.sala);
      if (msgs.some((m) => m.sala.codigo !== x.code)) problems.push(`${label}: mensagem de outra sala`);
    }
    // A origem certa não substitui o token.
    const noToken = await http(port, { method: 'POST', path: `/api/rooms/${x.code}/reset`, headers: O });
    expect(noToken.status, 'nova partida sem token').toBe(401);
    const other = await create(port, O);
    expect((await move(port, x.code!, other.token!, 5, O)).status, 'token de outra sala').toBe(401);
    const wrong = await Ws.open(port, { origin: ORIGIN });
    const answer = await wrong.enter(x.code!, other.token!);
    expect(answer.codigo, 'canal com a origem certa e token de outra sala').toBe('TOKEN_INVALIDO');
    await wrong.waitFor(() => wrong.closeCode() !== null);
    expect(wrong.closeCode()).toBe(4401);
    // Nova partida e saída com o token certo.
    expect((await http(port, { method: 'POST', path: `/api/rooms/${x.code}/reset`, headers: [...O, bearer(o.token!)] })).status).toBe(200);
    expect((await http(port, { method: 'POST', path: `/api/rooms/${x.code}/leave`, headers: [...O, bearer(x.token!)] })).status).toBe(200);
    for (const w of [wx, wo]) {
      await w.waitFor(() => w.closeCode() !== null, 3000, 'fechamento 4410');
      expect(w.closeCode()).toBe(4410);
    }
    // Origens recusadas (H-01) e POST sem Origin aceito (B2).
    const loop = await create(port, [['Origin', `http://127.0.0.1:${port}`]]);
    expect(loop.status, 'POST com a origem do loopback').toBe(403);
    problems.push(...securityHeaderProblems('403', loop));
    expect((await Ws.open(port)).status, 'canal sem Origin').toBe(403);
    expect((await Ws.open(port, { origin: 'http://jogo.test' })).status, 'canal com http').toBe(403);
    expect((await create(port)).status, 'POST sem Origin (cliente que não é navegador)').toBe(201);

    const log = server.output();
    expect(log).toContain('Modo --public');
    expect(log).toContain('criação de salas 10, consulta/entrada 30, abertura de canal 30; canais simultâneos por cliente 8; mensagens por canal a cada 10 s 30');
    problems.push(...logProblems(server));
    expect(problems).toEqual([]);
  });
});

test('OV-13 [CAO-44, CAO-55] modo local preservado: rotas antigas iguais, cabeçalhos de segurança, nenhum limite novo por padrão', async () => {
  test.setTimeout(60_000);
  const port = 8796;
  await withServer('ov-13', port, [], async (server) => {
    const problems: string[] = [];
    const reset = await http(port, { method: 'POST', path: '/api/game/reset' });
    expect(reset.status).toBe(200);
    problems.push(...securityHeaderProblems('reset', reset));
    const state = await http(port, { path: '/api/game' });
    expect(state.status).toBe(200);
    expect(state.json.status).toBe('EM_ANDAMENTO');
    expect((await http(port, { method: 'HEAD', path: '/api/game' })).status).toBe(200);
    for (const p of ['/', '/index.html', '/online.html']) {
      const r = await http(port, { path: p });
      expect(r.status, p).toBe(200);
      problems.push(...securityHeaderProblems(p, r, true));
    }
    // Corpo nas rotas antigas: abaixo do teto de 64 KB, como antes (processado); acima, 413 (B3).
    const padded = (size: number, pos: number) => { const head = `{"posicao":${pos}`; return head + ' '.repeat(size - head.length - 1) + '}'; };
    const big = await http(port, { method: 'POST', path: '/api/game/moves', headers: [['Content-Type', 'application/json']], body: padded(10_000, 0) });
    expect(big.status, 'jogada local com 10 KB').toBe(200);
    const atCap = await http(port, { method: 'POST', path: '/api/game/moves', headers: [['Content-Type', 'application/json']], body: padded(65_536, 4) });
    expect(atCap.status, 'jogada local com 64 KB exatos').toBe(200);
    const overCap = await http(port, { method: 'POST', path: '/api/game/moves', headers: [['Content-Type', 'application/json']], body: padded(65_537, 8) });
    expect(overCap.status, 'jogada local com 64 KB + 1').toBe(413);
    expect(overCap.json).toEqual(BODY_ERROR);
    expect((await http(port, { path: '/api/game' })).json.tabuleiro.join(','), 'a jogada recusada não mudou nada').toBe('X,,,,O,,,,');
    // Sem taxas, sem limite de canais por cliente e de mensagens (padrão local).
    const statuses = await Promise.all(Array.from({ length: 40 }, () => create(port).then((r) => r.status)));
    expect(statuses.every((s) => s === 201), `40 criações seguidas: ${[...new Set(statuses)]}`).toBe(true);
    const channels = await Promise.all(Array.from({ length: 12 }, () => Ws.open(port)));
    expect(channels.map((c) => c.status).every((s) => s === 101), '12 canais do mesmo cliente').toBe(true);
    const room = await create(port);
    expect((await channels[0].enter(room.code!, room.token!)).tipo).toBe('bem_vindo');
    for (let i = 1; i <= 50; i++) channels[0].send({ tipo: 'ping', id: i });
    await channels[0].waitFor(() => channels[0].texts().filter((m) => m.tipo === 'pong').length === 50, 5000, '50 pongs');
    expect(channels[0].closeCode(), 'canal continua aberto').toBeNull();
    for (const c of channels) c.close();
    expect(server.output()).toContain('criação de salas sem limite, consulta/entrada sem limite, abertura de canal sem limite');
    problems.push(...logProblems(server));
    expect(problems).toEqual([]);
  });
});

test('OV-14a [CAO-46, CAO-51] configurações inválidas não iniciam (código 2)', async () => {
  test.setTimeout(60_000);
  for (const [label, args] of [
    ['--public sem origem', ['--public']],
    ['--public com http', ['--public', '--allowed-origin', 'http://jogo.test']],
    ['--public com uma http entre https', ['--public', '--allowed-origin', 'https://a.test,http://b.test']],
    ['origem com caminho', ['--public', '--allowed-origin', 'https://jogo.test/x']],
    ['origem ftp', ['--allowed-origin', 'ftp://jogo.test']],
    ['--bind inválido', ['--bind', '999.1.1.1']],
    ['taxa negativa', ['--rate-create', '-1']],
    ['taxa acima do máximo', ['--rate-join', '10001']],
    ['janela 0', ['--rate-window-seconds', '0']],
    ['prazo de leitura 0', ['--http-timeout-seconds', '0']],
    ['canais por cliente sem valor', ['--ws-per-client']],
    ['--trust-proxy com valor', ['--trust-proxy', 'sim']],
    ['opção desconhecida', ['--rate-create-all', '1']],
  ] as const) {
    const r = await runServerExpectingExit('ov-14a', ['--port', '8797', ...args]);
    expect(r.code, `${label}: código de saída`).toBe(2);
    expect(r.output, `${label}: mensagem`).toContain('Parâmetros inválidos');
  }
});

test('OV-14b [CAO-46, CAO-51] combinações válidas de --public, --bind, --allowed-origin e --trust-proxy', async () => {
  test.setTimeout(90_000);
  const ip = privateIPv4();
  if (!ip) throw new Error('sem rede local: esta máquina não tem IPv4 privado');
  // 1. --public: só em 127.0.0.1; limites públicos ativos por padrão.
  await withServer('ov-14b-1', 8797, ['--public', '--allowed-origin', ORIGIN], async (server) => {
    expect((await http(8797, { path: '/health' })).status).toBe(200);
    expect((await http(8797, { path: '/health', host: ip })).networkError, 'pelo IP privado: recusado').toBeTruthy();
    const s = [];
    for (let i = 0; i < 11; i++) s.push((await create(8797, [['Origin', ORIGIN]])).status);
    expect(s, 'limite público de criação: 10 por minuto').toEqual([...Array(10).fill(201), 429]);
    expect(server.output()).toContain('Escutando em 127.0.0.1:8797');
  });
  // 2. --public --bind 0.0.0.0 com duas origens: pelo IP privado responde; só as https configuradas.
  await withServer('ov-14b-2', 8798, ['--public', '--bind', '0.0.0.0', '--allowed-origin', 'https://a.test,https://b.test'], async () => {
    expect((await http(8798, { path: '/health', host: ip })).status).toBe(200);
    expect((await http(8798, { path: '/api/game', host: ip })).status, '/api/game no público').toBe(404);
    for (const [origin, status] of [['https://a.test', 101], ['https://b.test', 101], ['https://c.test', 403], [`http://${ip}:8798`, 403], ['http://127.0.0.1:8798', 403]] as const) {
      const w = await Ws.open(8798, { host: ip, origin });
      expect(w.status, origin).toBe(status);
      w.close();
    }
  });
  // 3. Local com --bind 127.0.0.1: só o loopback; a origem do IP privado não é automática.
  await withServer('ov-14b-3', 8799, ['--bind', '127.0.0.1'], async () => {
    expect((await http(8799, { path: '/health', host: ip })).networkError).toBeTruthy();
    expect((await http(8799, { path: '/api/game' })).status, 'rotas locais').toBe(200);
    expect((await Ws.open(8799, { origin: 'http://127.0.0.1:8799' })).status).toBe(101);
    expect((await Ws.open(8799, { origin: `http://${ip}:8799` })).status).toBe(403);
  });
  // 4. Local com --bind <IP privado>: só esse endereço; o loopback não está na lista.
  const s4 = await startServerOn(ip, 'ov-14b-4', 8800, ['--bind', ip]);
  try {
    expect((await http(8800, { path: '/health' })).networkError, 'loopback recusado').toBeTruthy();
    expect((await http(8800, { path: '/health', host: ip })).status).toBe(200);
    expect((await Ws.open(8800, { host: ip, origin: `http://${ip}:8800` })).status).toBe(101);
    expect((await Ws.open(8800, { host: ip, origin: 'http://127.0.0.1:8800' })).status).toBe(403);
  } finally {
    await s4.stop();
  }
  // 5. --trust-proxy no modo público aparece no log.
  await withServer('ov-14b-5', 8801, ['--public', '--allowed-origin', ORIGIN, '--trust-proxy'], async (server) => {
    expect(server.output()).toContain('--trust-proxy');
  });
});

test('OV-15a [CAO-53, CAO-52] canais por cliente e mensagens por canal: limite, liberação, isolamento entre clientes e salas', async () => {
  test.setTimeout(60_000);
  const port = 8802;
  await withServer('ov-15a', port, ['--trust-proxy', '--ws-per-client', '2', '--ws-msg-rate', '5'], async (server) => {
    const A = xff('203.0.113.40');
    const B = xff('203.0.113.41');
    const r1 = await create(port);
    const r1o = await join(port, r1.code!);
    const r2 = await create(port);
    const r2o = await join(port, r2.code!);
    // Cliente A: dois canais (no limite) e o terceiro recusado.
    const a1 = await Ws.open(port, { headers: A });
    const a2 = await Ws.open(port, { headers: A });
    expect([a1.status, a2.status]).toEqual([101, 101]);
    const a3 = await Ws.open(port, { headers: A });
    expect(a3.status, '3o canal de A').toBe(429);
    expect(a3.json).toEqual(CONN_ERROR);
    expect(a3.headers['retry-after'], 'sem Retry-After (B4)').toBeUndefined();
    expect(securityHeaderProblems('429 do canal', a3)).toEqual([]);
    // Cliente B não é afetado.
    const b1 = await Ws.open(port, { headers: B });
    const b2 = await Ws.open(port, { headers: B });
    expect([b1.status, b2.status], 'B abre os seus dois').toEqual([101, 101]);
    // A solta um canal e volta a abrir (nada fica preso).
    a2.close();
    let a4: Ws | null = null;
    for (const deadline = Date.now() + 3000; Date.now() < deadline;) {
      const w = await Ws.open(port, { headers: A });
      if (w.status === 101) { a4 = w; break; }
      await sleep(100);
    }
    expect(a4, 'A reabre depois de fechar um canal').not.toBeNull();
    // Mensagens: 5 por 10 s no canal (no limite); a 6a fecha com 1008, e só aquele canal.
    expect((await a1.enter(r1.code!, r1.token!)).tipo).toBe('bem_vindo');
    expect((await a4!.enter(r1.code!, r1o.token!)).tipo).toBe('bem_vindo');
    expect((await b1.enter(r2.code!, r2.token!)).tipo).toBe('bem_vindo');
    expect((await b2.enter(r2.code!, r2o.token!)).tipo).toBe('bem_vindo');
    // "entrar" já foi a 1a mensagem de a1: mais 4 pings = 5 no limite.
    for (let i = 1; i <= 4; i++) a1.send({ tipo: 'ping', id: i });
    await a1.waitFor(() => a1.texts().filter((m) => m.tipo === 'pong').length === 4, 3000, '4 pongs');
    expect(a1.closeCode(), 'no limite, o canal continua').toBeNull();
    a1.send({ tipo: 'ping', id: 5 });
    await a1.waitFor(() => a1.closeCode() !== null, 3000, 'fechamento por excesso');
    expect(a1.texts().find((m) => m.tipo === 'erro')).toEqual({ tipo: 'erro', codigo: 'LIMITE_DE_MENSAGENS', mensagem: 'Muitas mensagens neste canal.' });
    expect(a1.closeCode()).toBe(1008);
    // O outro lugar da mesma sala é avisado da desconexão; a outra sala segue normal.
    await a4!.waitFor(() => a4!.texts().some((m) => m.tipo === 'estado' && m.motivo === 'DESCONEXAO'), 3000, 'DESCONEXAO');
    b1.send({ tipo: 'ping', id: 99 });
    await b1.waitFor(() => b1.texts().some((m) => m.tipo === 'pong' && m.id === 99), 3000, 'pong em outra sala');
    expect((await move(port, r2.code!, r2.token!, 4)).status).toBe(200);
    await b2.waitFor(() => b2.texts().some((m) => m.tipo === 'estado' && m.motivo === 'JOGADA'), 3000, 'jogada na sala 2');
    expect(b2.texts().filter((m) => m.sala).every((m) => m.sala.codigo === r2.code), 'só mensagens da própria sala').toBe(true);
    for (const w of [a4!, b1, b2]) w.close();
    const log = server.output();
    expect(log).toContain('Canal recusado de 203.0.113.40: limite de 2 canais por cliente');
    expect(log).toMatch(/servidor fechou com 1008 \(LIMITE_DE_MENSAGENS\)/);
    expect(logProblems(server)).toEqual([]);
  });
});

test('OV-15b [CAO-53] conexões do servidor e prazo de leitura: 503 SERVIDOR_OCUPADO, conexões paradas fechadas, nada preso', async () => {
  test.setTimeout(60_000);
  const port = 8803;
  await withServer('ov-15b', port, ['--max-connections', '4', '--http-timeout-seconds', '2'], async (server) => {
    const idle = await Promise.all(Array.from({ length: 4 }, () => IdleSocket.open(port)));
    await sleep(100);
    const busy = await http(port, { path: '/health' });
    expect(busy.status, '5a conexão com 4 paradas').toBe(503);
    expect(busy.json).toEqual(BUSY_ERROR);
    expect(busy.headers['retry-after']).toBe('5');
    expect(busy.headers['content-type']).toBe('application/json; charset=utf-8');
    expect(securityHeaderProblems('503', busy)).toEqual([]);
    // As paradas são fechadas pelo servidor depois do prazo (2 s por leitura).
    const times = await Promise.all(idle.map((s) => s.waitClosed(6000)));
    test.info().annotations.push({ type: 'conexões paradas', description: `fechadas em ${times.join(', ')} ms (prazo 2.000 ms)` });
    for (const t of times) {
      expect(t, 'não antes do prazo').toBeGreaterThanOrEqual(1800);
      expect(t, 'pouco depois do prazo').toBeLessThanOrEqual(4500);
    }
    expect((await http(port, { path: '/health' })).status, 'vagas liberadas').toBe(200);
    // Cabeçalhos incompletos: no prazo o Indy dá os cabeçalhos por terminados (B13), responde e fecha.
    const partial = await IdleSocket.open(port, '127.0.0.1', 'GET /health HTTP/1.1\r\nHost: x\r\n');
    const pt = await partial.waitClosed(6000);
    expect(pt, 'liberada só depois do prazo').toBeGreaterThanOrEqual(1800);
    expect(pt, 'e logo depois dele').toBeLessThanOrEqual(4500);
    // Lenta mas constante (cada pedaço antes do prazo): atendida (B13: o prazo é por leitura).
    const slow = await IdleSocket.open(port, '127.0.0.1', 'GET /hea');
    for (const piece of ['lth HT', 'TP/1.1\r\n', 'Host: x\r\n', 'Connection: close\r\n', '\r\n']) {
      await sleep(1000);
      slow.write(piece);
    }
    await slow.waitClosed(5000);
    expect(slow.received.toString('latin1'), 'pedido lento atendido').toMatch(/^HTTP\/1\.1 200/);
    // O canal tem prazos próprios: parado 3 s depois de entrar, continua aberto.
    const r = await create(port);
    const w = await Ws.open(port);
    expect((await w.enter(r.code!, r.token!)).tipo).toBe('bem_vindo');
    await sleep(3000);
    w.send({ tipo: 'ping', id: 7 });
    await w.waitFor(() => w.texts().some((m) => m.tipo === 'pong'), 3000, 'pong depois de 3 s parado');
    expect(w.closeCode()).toBeNull();
    w.close();
    expect(server.output()).toContain('Conexão recusada de 127.0.0.1: limite de 4 conexões simultâneas (503)');
    expect(logProblems(server)).toEqual([]);
  });
});

test('OV-16 [CAO-52] tamanho das requisições: teto de 64 KB em memória, corpo em blocos, tamanho declarado enorme, cabeçalhos demais', async () => {
  test.setTimeout(60_000);
  const port = 8804;
  await withServer('ov-16', port, ['--http-timeout-seconds', '3'], async (server) => {
    const problems: string[] = [];
    // Corpo em blocos de 5 MB numa rota de sala e de 70 KB na rota antiga: 413, sem 500.
    const chunkedRoom = await http(port, { method: 'POST', path: '/api/rooms', body: Buffer.alloc(5 * 1024 * 1024, 0x20), chunkSize: 64 * 1024, timeoutMs: 30_000 });
    expect(chunkedRoom.status, 'sala, 5 MB em blocos').toBe(413);
    expect(chunkedRoom.json).toEqual(BODY_ERROR);
    const chunkedGame = await http(port, { method: 'POST', path: '/api/game/moves', body: Buffer.alloc(70 * 1024, 0x20), chunkSize: 8 * 1024 });
    expect(chunkedGame.status, 'rota antiga, 70 KB em blocos').toBe(413);
    problems.push(...securityHeaderProblems('413', chunkedGame));
    // Tamanho declarado enorme: nada é alocado (o Indy pré-alocava o tamanho declarado).
    const before = serverPrivateBytes(port);
    const huge = await IdleSocket.open(port, '127.0.0.1',
      'POST /api/rooms HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 800000000\r\n\r\n{"x":');
    await sleep(800);
    const during = serverPrivateBytes(port);
    test.info().annotations.push({ type: 'memória', description: `antes ${Math.round(before / 1048576)} MB; com 800 MB declarados ${Math.round(during / 1048576)} MB` });
    expect(before, 'memória do servidor lida').toBeGreaterThan(0);
    expect(during - before, 'nenhuma alocação do tamanho declarado').toBeLessThan(50 * 1024 * 1024);
    await huge.waitClosed(8000);   // fechada pelo prazo de leitura
    // Cabeçalhos demais (1.100 linhas) e uma linha de 20 KB: a conexão é encerrada; o servidor segue.
    const many = await http(port, { path: '/health', headers: Array.from({ length: 1100 }, (_, i) => [`X-H${i}`, 'v'] as [string, string]) });
    expect(many.status, '1.100 linhas de cabeçalho').not.toBe(200);
    const longLine = await http(port, { path: '/health', headers: [['X-Long', 'a'.repeat(20 * 1024)]] });
    expect(longLine.status, 'linha de 20 KB').not.toBe(200);
    expect((await http(port, { path: '/health' })).status, 'servidor segue respondendo').toBe(200);
    problems.push(...logProblems(server));
    expect(problems).toEqual([]);
  });
});

test('OV-17 [CAO-25, CAO-53] rajada de 20 clientes com limites: só respostas previstas, partida de outra sala intacta, recursos liberados', async () => {
  test.setTimeout(120_000);
  const port = 8805;
  await withServer('ov-17', port, ['--trust-proxy', '--rate-create', '5', '--rate-join', '20', '--rate-ws', '10', '--rate-window-seconds', '2',
    '--max-connections', '40', '--ws-per-client', '3', '--ws-msg-rate', '20'], async (server) => {
    const problems: string[] = [];
    // A partida "boa": X e O de dois clientes, com canal, na sala G.
    const GX = xff('198.51.100.1');
    const GO = xff('198.51.100.2');
    const g = await create(port, GX);
    const go = await join(port, g.code!, GO);
    const wx = await Ws.open(port, { headers: GX });
    const wo = await Ws.open(port, { headers: GO });
    expect((await wx.enter(g.code!, g.token!)).tipo).toBe('bem_vindo');
    expect((await wo.enter(g.code!, go.token!)).tipo).toBe('bem_vindo');

    // Rajada: 20 clientes, cada um com 8 criações, 25 consultas e 5 aberturas de canal, 60 por vez.
    const tasks: Array<() => Promise<{ client: number; kind: string; status: number; err?: string }>> = [];
    for (let c = 0; c < 20; c++) {
      const H = xff(`203.0.113.${100 + c}`);
      for (let i = 0; i < 8; i++) tasks.push(async () => { const r = await create(port, H); return { client: c, kind: 'criar', status: r.status, err: r.networkError }; });
      for (let i = 0; i < 25; i++) tasks.push(async () => { const r = await http(port, { path: `/api/rooms/${randomCode()}`, headers: H }); return { client: c, kind: 'consultar', status: r.status, err: r.networkError }; });
      for (let i = 0; i < 5; i++) tasks.push(async () => { const w = await Ws.open(port, { headers: H }); w.close(); return { client: c, kind: 'canal', status: w.status }; });
    }
    tasks.sort(() => Math.random() - 0.5);
    const results: Array<{ client: number; kind: string; status: number; err?: string }> = [];
    let next = 0;
    const workers = Array.from({ length: 60 }, async () => {
      while (next < tasks.length) results.push(await tasks[next++]());
    });
    // Enquanto isso, a partida boa: jogadas com nova tentativa quando o servidor está cheio (503).
    let good503 = 0;
    const play = async () => {
      for (const [token, pos] of [[g.token!, 0], [go.token!, 4], [g.token!, 8], [go.token!, 2], [g.token!, 6], [go.token!, 3], [g.token!, 7]] as const) {
        for (;;) {
          const r = await move(port, g.code!, token, pos, token === g.token ? GX : GO);
          if (r.status === 503) { good503++; await sleep(50); continue; }
          if (r.status !== 200) problems.push(`jogada ${pos}: ${r.status} ${r.body}`);
          break;
        }
      }
    };
    const burstStart = Date.now();
    await Promise.all([...workers, play()]);
    const burstMs = Date.now() - burstStart;

    const allowed: Record<string, number[]> = { criar: [201, 429, 503], consultar: [404, 429, 503], canal: [101, 429, 503] };
    for (const r of results) {
      if (r.err) problems.push(`cliente ${r.client} ${r.kind}: erro de rede ${r.err}`);
      else if (!allowed[r.kind].includes(r.status)) problems.push(`cliente ${r.client} ${r.kind}: ${r.status}`);
    }
    // Ninguém passou do próprio limite: 5 criações por janela de 2 s, quantas janelas a rajada durou.
    const windows = Math.ceil(burstMs / 2000) + 1;
    for (let c = 0; c < 20; c++) {
      const mine = results.filter((r) => r.client === c);
      const created = mine.filter((r) => r.kind === 'criar' && r.status === 201).length;
      if (created > 5 * windows) problems.push(`cliente ${c}: ${created} criações aceitas em ${windows} janelas`);
    }
    // E o limite agiu de fato: com 20 clientes x 8 criações numa rajada curta, alguma é recusada
    // (sem isso, o teto acima, folgado para rajadas longas, não pegaria um limitador que nunca limita: SB-18).
    const create429 = results.filter((r) => r.kind === 'criar' && r.status === 429).length;
    if (create429 === 0) problems.push(`nenhuma criação recusada com 429 (rajada de ${burstMs} ms)`);
    const final = (await http(port, { path: `/api/rooms/${g.code}` })).json.sala;
    expect(final.partida.status, 'a partida boa terminou').toBe('VITORIA');
    for (const [label, w] of [['X', wx], ['O', wo]] as const) {
      await w.waitFor(() => w.texts().some((m) => m.sala?.versao === final.versao), 5000, `${label}: estado final`);
      const v = w.texts().filter((m) => m.sala).map((m) => m.sala.versao);
      if (!v.every((x, i) => i === 0 || x > v[i - 1])) problems.push(`${label}: versões fora de ordem`);
      if (w.texts().some((m) => m.sala && m.sala.codigo !== g.code)) problems.push(`${label}: mensagem de outra sala`);
      if (w.closeCode() !== null) problems.push(`${label}: canal caiu (${w.closeCode()})`);
    }
    // Recursos liberados: cada 503 tem a sua linha no log, as vagas voltaram e os canais por cliente também.
    const count = (s: number) => results.filter((r) => r.status === s).length;
    const busyLines = (server.output().match(/limite de 40 conexões simultâneas \(503\)/g) ?? []).length;
    expect(busyLines, 'uma linha no log para cada 503').toBe(count(503) + good503);
    await sleep(2200);
    expect((await http(port, { path: '/health' })).status).toBe(200);
    const again = await Promise.all([0, 1, 2].map(() => Ws.open(port, { headers: xff('203.0.113.100') })));
    expect(again.map((w) => w.status), 'o cliente 0 abre 3 canais de novo (contagem liberada)').toEqual([101, 101, 101]);
    // ...e o limite continua valendo: o 4º canal simultâneo do mesmo cliente é recusado (SB-22).
    const fourth = await Ws.open(port, { headers: xff('203.0.113.100') });
    expect(fourth.status, 'o 4º canal simultâneo do cliente 0 é recusado').toBe(429);
    fourth.close();
    for (const w of [...again, wx, wo]) w.close();
    test.info().annotations.push({ type: 'rajada', description:
      `${results.length} pedidos em ${burstMs} ms: 201=${count(201)}, 404=${count(404)}, 101=${count(101)}, 429=${count(429)} (criações ${create429}), 503=${count(503)}; ` +
      `partida boa com ${good503} novas tentativas por 503` });
    problems.push(...logProblems(server));
    expect(problems).toEqual([]);
  });
});
