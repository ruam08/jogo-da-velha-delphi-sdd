// Prova de conceito da Entrega O0 (descartável).
// Teste do canal WebSocket do WsSpike.exe no Chromium do Playwright já
// instalado em tests/ (nenhum pacote novo).
//
// Uso: node browser-test.cjs --port 8790 [--tests-dir <pasta tests>]

const path = require('node:path');
const { createRequire } = require('node:module');

const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : def;
};
const PORT = Number(opt('port', '8790'));
const BASE = `http://127.0.0.1:${PORT}`;
const testsDir = opt('tests-dir', path.join(__dirname, '..', '..', '..', 'tests'));
const requireFromTests = createRequire(path.join(testsDir, 'package.json'));
let pw;
try { pw = requireFromTests('@playwright/test'); } catch { pw = requireFromTests('playwright'); }
const { chromium } = pw;

const results = [];
function check(id, description, ok, detail = '') {
  results.push({ id, ok: !!ok });
  console.log(`[${ok ? 'PASSOU' : 'FALHOU'}] ${id} ${description}${detail ? ' | ' + detail : ''}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const stats = async () => (await fetch(BASE + '/stats')).json();

async function waitFor(fn, timeoutMs, stepMs = 25) {
  const start = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - start > timeoutMs) return null;
    await sleep(stepMs);
  }
}

async function openPage(browser, problems, label) {
  const context = await browser.newContext();
  const page = await context.newPage();
  page.on('console', (m) => { if (m.type() === 'error') problems.push(`${label}: console: ${m.text()}`); });
  page.on('pageerror', (e) => problems.push(`${label}: exceção: ${e.message}`));
  return { context, page };
}

async function received(page, pred, timeoutMs = 2000) {
  const start = Date.now();
  for (;;) {
    const list = await page.evaluate(() => window.spike.received.slice());
    const hit = list.find(pred);
    if (hit !== undefined) return hit;
    if (Date.now() - start > timeoutMs) return null;
    await sleep(10);
  }
}

async function welcome(page) {
  await page.waitForFunction(() => window.spike && window.spike.opened, null, { timeout: 5000 });
  const ola = await received(page, (m) => m.startsWith('ola:'), 3000);
  return ola ? ola.slice(4) : null;
}

(async () => {
  const problems = [];
  const browser = await chromium.launch();
  console.log(`Chromium ${browser.version()}; porta ${PORT}`);
  try {
    // B-01: dois navegadores isolados (contextos separados) no mesmo servidor.
    const A = await openPage(browser, problems, 'A');
    const B = await openPage(browser, problems, 'B');
    await A.page.goto(BASE + '/page');
    await B.page.goto(BASE + '/page');
    const idA = await welcome(A.page);
    const idB = await welcome(B.page);
    const msg = 'olá do navegador ✓ ação';
    await A.page.evaluate((m) => window.ws.send('todos:' + m), msg);
    const atB = await received(B.page, (m) => m.startsWith('de:'));
    const ack = await received(A.page, (m) => m.startsWith('enviado:'));
    await A.page.evaluate(() => window.ws.send('eco coração'));
    const echo = await received(A.page, (m) => m.startsWith('eco:'));
    check('B-01', 'Dois navegadores Chromium abrem o canal; mensagem com acentos de A chega a B; eco correto',
      idA && idB && idA !== idB && atB === `de:${idA}:${msg}` && !!ack && echo === 'eco:eco coração',
      `ids ${idA}/${idB}; B recebeu "${atB}"; eco "${echo}"`);

    // B-02: envio a partir de outra thread do servidor.
    const t0 = Date.now();
    await fetch(BASE + '/push', { method: 'POST', body: 'aviso do servidor' });
    const pa = await received(A.page, (m) => m === 'push:aviso do servidor');
    const pb = await received(B.page, (m) => m === 'push:aviso do servidor');
    const lat = Date.now() - t0;
    check('B-02', 'POST /push chega às duas páginas em menos de 200 ms (inclui o tempo de consulta do teste)', pa && pb && lat < 200, `${lat} ms`);

    // B-03: fechar a página encerra a sessão no servidor.
    const before3 = (await stats()).fechadas;
    const t3 = Date.now();
    await B.context.close();
    const done3 = await waitFor(async () => (await stats()).fechadas >= before3 + 1, 3000);
    check('B-03', 'Fechar a página de B encerra a sessão no servidor em até 2 s', !!done3 && Date.now() - t3 <= 2000, `${Date.now() - t3} ms`);

    // B-04: queda do canal simulada no navegador (routeWebSocket ligado ao servidor real).
    const C = await openPage(browser, problems, 'C');
    const routes = [];
    await C.page.routeWebSocket(/\/ws$/, (ws) => {
      const server = ws.connectToServer();
      routes.push({ ws, server });
    });
    await C.page.goto(BASE + '/page');
    const idC = await welcome(C.page);
    await C.page.evaluate(() => window.ws.send('eco pela rota'));
    const echoC = await received(C.page, (m) => m === 'eco:eco pela rota');
    const before4 = (await stats()).fechadas;
    await routes[0].server.close({ code: 1001, reason: 'queda simulada' });
    await routes[0].ws.close({ code: 4000, reason: 'queda simulada' });
    const pageClose = await waitFor(() => C.page.evaluate(() => window.spike.close), 3000);
    const done4 = await waitFor(async () => (await stats()).fechadas >= before4 + 1, 3000);
    check('B-04', 'routeWebSocket + connectToServer: mensagens passam pelo servidor real; a queda simulada fecha a página e a sessão do servidor',
      !!idC && !!echoC && pageClose && pageClose.code === 4000 && !!done4,
      `id ${idC}; eco ${echoC}; página fechada com ${pageClose ? pageClose.code : '-'}`);

    await A.context.close();
    await C.context.close();
    const end = await waitFor(async () => { const s = await stats(); return s.ativas === 0 ? s : null; }, 3000);
    check('B-05', 'Sem erros de console nas páginas; nenhum canal aberto e nenhum erro no servidor no fim',
      problems.length === 0 && !!end && end.erros === 0, `${problems.join(' ; ') || 'sem problemas'}; servidor ${JSON.stringify(end ?? (await stats()))}`);
  } catch (e) {
    check('X-01', 'Teste terminou sem exceção', false, e && e.message ? e.message.split('\n')[0] : String(e));
  } finally {
    await browser.close();
  }
  const failed = results.filter((r) => !r.ok).length;
  console.log(`RESUMO: ${results.length - failed} passaram, ${failed} falharam`);
  process.exit(failed === 0 ? 0 : 1);
})();
