// Gera capturas de tela da interface real para o registro da entrega.
// Uso: node tools/capture.cjs <baseURL> <pasta-de-saída>
// O servidor precisa estar em execução. Não é um teste: só registra a aparência.
const { chromium } = require('@playwright/test');
const path = require('node:path');

async function api(base, method, route, body) {
  const res = await fetch(base + route, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${method} ${route}: ${res.status}`);
}

async function shot(browser, base, out, name, viewport, moves) {
  await api(base, 'POST', '/api/game/reset');
  for (const p of moves) await api(base, 'POST', '/api/game/moves', { posicao: p });
  const page = await browser.newPage({ viewport });
  await page.goto(base + '/');
  await page.getByTestId('board').and(page.locator('[aria-busy="false"]')).waitFor();
  const file = path.join(out, name);
  // animations: 'disabled' conclui transições e animações antes da captura.
  await page.screenshot({ path: file, fullPage: true, animations: 'disabled' });
  await page.close();
  console.log('captura: ' + file);
}

(async () => {
  const [base, out] = process.argv.slice(2);
  const browser = await chromium.launch();
  try {
    await shot(browser, base, out, 'ui-desktop-jogando.png', { width: 1280, height: 800 }, [0, 4, 8]);
    await shot(browser, base, out, 'ui-desktop-vitoria.png', { width: 1280, height: 800 }, [0, 1, 2, 3, 6, 5, 8, 7, 4]);
    await shot(browser, base, out, 'ui-celular-vitoria.png', { width: 360, height: 640 }, [0, 3, 1, 4, 2]);
    await shot(browser, base, out, 'ui-celular-empate.png', { width: 360, height: 640 }, [0, 1, 2, 4, 3, 5, 7, 6, 8]);
    await api(base, 'POST', '/api/game/reset');
  } finally {
    await browser.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
