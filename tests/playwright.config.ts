import { defineConfig, devices } from '@playwright/test';

/*
 * Configuração da suíte Playwright (docs/plan.md, seção 6).
 *
 * - Os testes falam com o TicTacToeServer.exe REAL, compilado com o Delphi
 *   Berlin (scripts\build.cmd). Nenhuma resposta do backend é simulada.
 * - O Playwright inicia o servidor (webServer) e o finaliza ao terminar.
 * - Sempre 127.0.0.1, nunca "localhost": o Node pode resolver "localhost"
 *   como IPv6 (::1), e o servidor escuta só em IPv4.
 * - Um único worker, sem paralelismo e sem retries: a partida é global no
 *   servidor (RN-13), e retries esconderiam testes instáveis (RNF-10).
 *
 * Variáveis de ambiente (usadas pelos scripts de validação):
 *   PW_PORT=8766            porta do servidor (padrão 8765)
 *   PW_EXTERNAL_SERVER=1    não inicia o servidor; usa um já em execução
 */
const PORT = Number(process.env.PW_PORT ?? 8765);
const BASE_URL = `http://127.0.0.1:${PORT}`;
const EXTERNAL_SERVER = process.env.PW_EXTERNAL_SERVER === '1';

export default defineConfig({
  testDir: '.',
  testMatch: ['api/**/*.spec.ts', 'rules/**/*.spec.ts', 'ui/**/*.spec.ts'],
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: true,
  timeout: 30_000,
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'playwright-report' }],
    ['json', { outputFile: 'test-results/results.json' }],
  ],
  use: {
    baseURL: BASE_URL,
  },
  projects: [
    // API e regras: só o cliente HTTP do Playwright, sem navegador.
    { name: 'api', testMatch: ['api/**/*.spec.ts', 'rules/**/*.spec.ts'] },
    // Interface: Chromium do Playwright, sem janela (headless).
    {
      name: 'chromium',
      testMatch: ['ui/**/*.spec.ts'],
      use: {
        ...devices['Desktop Chrome'],
        screenshot: 'only-on-failure',
        trace: 'retain-on-failure',
      },
    },
  ],
  webServer: EXTERNAL_SERVER
    ? undefined
    : {
        // Caminho relativo à pasta tests/ (onde está este arquivo).
        command: `"..\\server\\bin\\TicTacToeServer.exe" --port ${PORT}`,
        url: `${BASE_URL}/health`,
        // Nunca reaproveitar um servidor já aberto: garante que a suíte
        // testa o executável recém-compilado. Porta ocupada = erro claro.
        reuseExistingServer: false,
        timeout: 15_000,
        stdout: 'ignore',
        stderr: 'pipe',
      },
});
