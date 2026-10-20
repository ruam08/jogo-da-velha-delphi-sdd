import * as os from 'node:os';
import { request as playwrightRequest } from '@playwright/test';
import { test, expect } from '@playwright/test';
import { ONLINE_MESSAGES } from '../../support/online/rooms';
import { rawRequest } from '../../support/online/raw-request';
import { runServerExpectingExit, startServer } from '../../support/online/server-process';
import { RawWs } from '../../support/online/ws-client';

/*
 * OV-05: política de origem do canal no servidor real, com servidores
 * dedicados (DTO-15), por socket cru (docs/plan-online.md 7.7, casos OG).
 * (a) modo local padrão (bind 0.0.0.0) com o IPv4 privado real da máquina;
 * (b) --allowed-origin com o nome do computador;
 * (c) modo público com https configurado (e as configurações recusadas).
 */

const ORIGIN_ERROR = { erro: { codigo: 'ORIGEM_NAO_PERMITIDA', mensagem: ONLINE_MESSAGES.ORIGEM_NAO_PERMITIDA } };

/** IPv4 privado de uma interface desta máquina (10/8, 172.16/12, 192.168/16), ou null. */
function privateIPv4(): string | null {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family !== 'IPv4' || a.internal) continue;
      const [p0, p1] = a.address.split('.').map(Number);
      if (p0 === 10 || (p0 === 172 && p1 >= 16 && p1 <= 31) || (p0 === 192 && p1 === 168)) return a.address;
    }
  }
  return null;
}

async function opening(port: number, origin: string | string[] | undefined, host?: string): Promise<{ status: number; body: string }> {
  const raw = await RawWs.open(port, { origin, host });
  const status = raw.status;
  if (status === 101) {
    raw.destroy();
    return { status, body: '' };
  }
  await raw.waitEnd();
  return { status, body: raw.bodyText() };
}

async function expectOrigins(port: number, accepted: Array<[string, string | string[] | undefined, string?]>,
  refused: Array<[string, string | string[] | undefined, string?]>): Promise<void> {
  for (const [id, origin, host] of accepted) {
    const r = await opening(port, origin, host);
    expect(r.status, `${id} ${JSON.stringify(origin)} deveria abrir (101); corpo: ${r.body}`).toBe(101);
  }
  for (const [id, origin, host] of refused) {
    const r = await opening(port, origin, host);
    expect(r.status, `${id} ${JSON.stringify(origin)} deveria ser recusada (403)`).toBe(403);
    expect(JSON.parse(r.body), `${id}: corpo`).toEqual(ORIGIN_ERROR);
  }
}

test('OV-05a [CAO-51] modo local: loopback, IP privado real e ausência abrem; outras origens 403', async () => {
  const port = 8775;
  const server = await startServer('ov-05a', port);
  try {
    const ip = privateIPv4();
    test.info().annotations.push({ type: 'IPv4 privado', description: ip ?? '(nenhum)' });
    const accepted: Array<[string, string | undefined, string?]> = [
      ['OG-01', `http://127.0.0.1:${port}`],
      ['OG-02', `http://localhost:${port}`],
      ['OG-18', undefined],
    ];
    const other = ip ? ip.replace(/\.\d+$/, (m) => (m === '.20' ? '.21' : '.20')) : '192.168.0.20';
    const target = ip ?? '192.168.0.10';
    if (ip) accepted.push(['OG-03', `http://${ip}:${port}`], ['OG-04', `HTTP://${ip}:${port}`]);
    await expectOrigins(port, accepted, [
      ['OG-05', `http://${other}:${port}`],
      ['OG-06', `http://${target}:9000`],
      ['OG-07', `http://${target}`],
      ['OG-08', `https://${target}:${port}`],
      ['OG-09', `http://desktop-ruan:${port}`],
      ['OG-10', 'https://exemplo.com'],
      ['OG-11', `http://atacante.test:${port}`, `atacante.test:${port}`],
      ['OG-12', `http://${target}:${port}.atacante.test`],
      ['OG-13', 'null'],
      ['OG-14', `http://127.0.0.1:${port}/`],
      ['OG-14', `http://127.0.0.1:${port}/x`],
      ['OG-15', [`http://127.0.0.1:${port}`, `http://127.0.0.1:${port}`]],
      ['OG-16', `http://[::1]:${port}`],
      ['OG-17', `http://127.000.000.001:${port}`],
    ]);
    // Rotas de sala: o celular na rede local cria sala; o site de DNS rebinding não.
    if (ip) {
      const phone = await rawRequest(port, 'POST', '/api/rooms', [['Host', `${ip}:${port}`], ['Origin', `http://${ip}:${port}`]]);
      expect(phone.status, 'POST /api/rooms com Origin do IP da rede local').toBe(201);
    }
    const rebinding = await rawRequest(port, 'POST', '/api/rooms', [['Host', `atacante.test:${port}`], ['Origin', `http://atacante.test:${port}`]]);
    expect(rebinding.status, 'POST /api/rooms por DNS rebinding').toBe(403);

    const log = server.output();
    expect(log, 'lista de origens no console').toMatch(new RegExp(`Origens permitidas: http://127\\.0\\.0\\.1:${port}, http://localhost:${port}`));
    if (ip) expect(log).toContain(`http://${ip}:${port}`);
    expect(log, 'recusa registrada com a origem').toContain(`"http://atacante.test:${port}"`);
    expect(log).toMatch(/Origem recusada em \/ws de 127\.0\.0\.1/);
    expect(log, 'nenhum token no log').not.toMatch(/\b[0-9a-f]{32}\b/);
  } finally {
    await server.stop();
  }
});

test('OV-05b [CAO-51] --allowed-origin com o nome do computador', async () => {
  const port = 8776;
  const server = await startServer('ov-05b', port, ['--allowed-origin', `http://desktop-ruan:${port}`]);
  try {
    await expectOrigins(port, [
      ['OG-09', `http://desktop-ruan:${port}`],
      ['OG-09 maiúsculas', `HTTP://DESKTOP-RUAN:${port}`],
    ], [
      ['outra porta', `http://desktop-ruan:${port + 1}`],
      ['outro nome', `http://desktop-ruan2:${port}`],
      ['sufixo', `http://desktop-ruan:${port}.atacante.test`],
    ]);
    expect(server.output()).toContain(`http://desktop-ruan:${port}`);
  } finally {
    await server.stop();
  }
});

test('OV-05c [CAO-51] modo público: só a origem https configurada; canal sem Origin recusado; configuração http não inicia', async () => {
  const port = 8777;
  const server = await startServer('ov-05c', port, ['--public', '--allowed-origin', 'https://jogo.test']);
  const context = await playwrightRequest.newContext({ baseURL: server.baseURL });
  try {
    await expectOrigins(port, [
      ['https configurada', 'https://jogo.test'],
      ['https:443', 'https://jogo.test:443'],
    ], [
      ['loopback', `http://127.0.0.1:${port}`],
      ['http', 'http://jogo.test'],
      ['subdomínio', 'https://www.jogo.test'],
      ['ausente (canal)', undefined],
    ]);
    // Rotas de sala no modo público: sem Origin aceito (cliente que não é navegador); outra origem 403.
    expect((await context.post('/api/rooms')).status(), 'POST sem Origin').toBe(201);
    expect((await context.post('/api/rooms', { headers: { Origin: 'https://jogo.test' } })).status(), 'POST da origem configurada').toBe(201);
    expect((await context.post('/api/rooms', { headers: { Origin: `http://127.0.0.1:${port}` } })).status(), 'POST do loopback').toBe(403);
    expect(server.output(), 'lista só com a origem configurada').toContain('Origens permitidas: https://jogo.test:443');
  } finally {
    await context.dispose();
    await server.stop();
  }

  for (const [label, args] of [
    ['--public com origem http', ['--port', '8778', '--public', '--allowed-origin', 'http://jogo.test']],
    ['--public sem --allowed-origin', ['--port', '8778', '--public']],
    ['--allowed-origin com caminho', ['--port', '8778', '--allowed-origin', 'http://jogo.test/x']],
  ] as const) {
    const r = await runServerExpectingExit('ov-05c-recusado', [...args]);
    expect(r.code, `${label}: código de saída`).toBe(2);
    expect(r.output, `${label}: mensagem`).toContain('Parâmetros inválidos');
  }
});
