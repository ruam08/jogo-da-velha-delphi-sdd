import { defineConfig } from '@playwright/test';
import base from './playwright.config';

/*
 * Demonstração visual (fora da validação): a mesma suíte, com o Chromium
 * visível e os passos mais lentos, só nos projetos de interface.
 * Não substitui a validação oficial (scripts\validate-online-o6.cmd), que
 * roda sem janela: com janelas e passos lentos, os testes que medem tempo
 * podem falhar sem defeito. Por isso o script de demonstração escolhe só
 * testes sem medição de tempo.
 *
 * Uso: scripts\demo-playwright-headed.cmd (resultado em logs\demo-playwright-headed.log)
 *   DEMO_SLOWMO=400   pausa (ms) antes de cada ação do navegador
 */
const SLOW_MO = Number(process.env.DEMO_SLOWMO ?? 400);

export default defineConfig({
  ...base,
  timeout: 180_000,
  reporter: [['list']],
  // Dentro de test-results/ (ignorada pelo .gitignore). Na O6 era tests/demo-results,
  // que o Git via como arquivo novo (corrigido na O7).
  outputDir: 'test-results/demo',
  projects: (base.projects ?? [])
    .filter((p) => p.name === 'chromium' || p.name === 'online-ui')
    .map((p) => ({
      ...p,
      use: {
        ...p.use,
        headless: false,
        launchOptions: { slowMo: SLOW_MO },
        screenshot: 'off',
        trace: 'off',
        // Vídeo de cada teste (test-results/demo), para registrar o que a tela mostrou (O7).
        video: 'on',
      },
    })),
});
