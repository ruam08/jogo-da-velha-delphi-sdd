// Gera capturas de tela da interface online real para o registro da entrega.
// Uso: node tools/capture-online.cjs <baseURL> <pasta-de-saída>
// O servidor precisa estar em execução. Não é um teste: só registra a aparência.
// Cada jogador é um contexto isolado do Chromium (outro "navegador").
const { chromium } = require('@playwright/test');
const path = require('node:path');

const DESKTOP = { width: 1280, height: 800 };
const PHONE = { width: 360, height: 640 };

async function shot(page, out, name) {
  const file = path.join(out, name);
  await page.screenshot({ path: file, fullPage: true, animations: 'disabled' });
  console.log('captura: ' + file);
}

async function state(page, value) {
  await page.locator(`[data-testid="online-app"][data-state="${value}"]`).waitFor();
}

async function connected(page) {
  await page.locator('[data-testid="online-app"][data-connection="conectado"]').waitFor();
}

async function click(page, i) {
  const res = page.waitForResponse((r) => /\/moves$/.test(new URL(r.url()).pathname));
  await page.getByTestId(`cell-${i}`).click({ force: true });
  await res;
  await page.locator('[data-testid="board"][aria-busy="false"]').waitFor();
}

/** A cria a sala e B entra pelo link; devolve as duas páginas. */
async function pair(browser, base, viewport) {
  const a = await (await browser.newContext({ viewport, baseURL: base })).newPage();
  await a.goto('/online.html');
  await state(a, 'inicio');
  await a.getByTestId('create-room').click();
  await state(a, 'aguardando');
  await connected(a);
  const link = await a.getByTestId('room-link').textContent();
  const b = await (await browser.newContext({ viewport, baseURL: base })).newPage();
  await b.goto(link);
  await state(b, 'convite');
  await b.getByTestId('join-this-room').click();
  await state(b, 'jogando');
  await connected(b);
  await state(a, 'jogando');
  return { a, b };
}

(async () => {
  const [base, out] = process.argv.slice(2);
  const browser = await chromium.launch();
  try {
    // Desktop: tela inicial, sala criada, jogo nas duas páginas e vitória.
    const start = await (await browser.newContext({ viewport: DESKTOP, baseURL: base })).newPage();
    await start.goto('/online.html');
    await state(start, 'inicio');
    await shot(start, out, 'online-desktop-inicio.png');
    await start.getByTestId('create-room').click();
    await state(start, 'aguardando');
    await connected(start);
    await shot(start, out, 'online-desktop-sala-criada.png');
    await start.context().close();

    const d = await pair(browser, base, DESKTOP);
    await click(d.a, 0);
    await click(d.b, 4);
    await d.a.getByTestId('cell-4').filter({ hasText: 'O' }).waitFor();
    await shot(d.a, out, 'online-desktop-jogando-a.png');
    await shot(d.b, out, 'online-desktop-jogando-b.png');
    for (const [n, pos] of [[2, 8], [3, 2], [4, 6], [5, 3], [6, 7]]) {
      await click(n % 2 === 0 ? d.a : d.b, pos);
    }
    await state(d.a, 'finalizada');
    await state(d.b, 'finalizada');
    await shot(d.a, out, 'online-desktop-vitoria-a.png');
    await shot(d.b, out, 'online-desktop-vitoria-b.png');

    // Celular (360 x 640): jogo e sala encerrada pela saída do oponente.
    const m = await pair(browser, base, PHONE);
    await click(m.a, 0);
    await m.b.getByTestId('cell-0').filter({ hasText: 'X' }).waitFor();
    await shot(m.b, out, 'online-celular-jogando.png');
    m.b.once('dialog', (dialog) => dialog.accept());
    await m.b.getByTestId('leave-room').click();
    await state(m.a, 'encerrada');
    await shot(m.a, out, 'online-celular-encerrada.png');

    // A sala do desktop também é encerrada (não fica aberta no servidor).
    d.a.once('dialog', (dialog) => dialog.accept());
    await d.a.getByTestId('leave-room').click();
    await state(d.a, 'encerrada');
  } finally {
    await browser.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
