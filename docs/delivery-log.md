# Registro de entregas

Resumo versionado de cada entrega: o que foi feito, comandos executados, resultados reais e limitações. As saídas completas ficam em `logs\` (fora do Git) e podem ser regeradas pelos scripts de validação.

Ambiente das execuções: Windows 10 Pro (build 19045), Delphi 10.1 Berlin (`compiler version 31.0`, `C:\Program Files (x86)\Embarcadero\Studio\18.0`), PowerShell 5.1, curl 8.13.0, Node 24.11.1, Git 2.50.0.

---

## Entrega 1 — Estrutura do servidor e `GET /health`

| Item | Valor |
|---|---|
| Data | 2026-10-15 |
| Comando | `scripts\validate-step1.cmd` |
| Log | `logs\step1-validation.log` |
| Resultado | **APROVADO** — 15 de 15 verificações (execução das 17:52) |

- Compilação com dcc32 sem erros; servidor responde `GET /health` com 200, `application/json; charset=utf-8`, `Cache-Control: no-store` e `{"status":"ok"}`.
- `HEAD` sem corpo; `POST`/`DELETE` → 405 com `Allow: GET, HEAD`; rota inexistente → 404 JSON; escuta só em `127.0.0.1`; porta liberada e reutilizável.
- A primeira execução reprovou o H-05 por defeito do script (o `curl -I` grava os cabeçalhos na saída); o script passou a ler o socket diretamente.

Limitações: encerramento por Ctrl+C verificado só manualmente (pendente de registro).

---

## Entrega 2 — Motor do jogo

| Item | Valor |
|---|---|
| Data | 2026-10-15 |
| Fase vermelha | `scripts\validate-step2-red.cmd` → `logs\step2-red.log` (18:01) |
| Validação | `scripts\validate-step2.cmd` → `logs\step2-validation.log` (18:03) |
| Resultado | **APROVADO** — 13 de 13 verificações |

### Ciclo de testes

1. **Fase vermelha (18:01).** `EngineCheck` compilado contra um esqueleto de `uGameEngine` (interface definitiva, sem regras): compilou sem erros nem warnings e **os 19 casos falharam**, cada um apontando a regra ausente. Código de saída 1.
2. **Implementação** de `uGameEngine.pas`.
3. **Fase verde (18:03).** Os 19 casos passaram; código de saída 0.

### Resultados da validação

| Verificação | Resultado |
|---|---|
| Compilação (servidor + EngineCheck) | OK, `compiler version 31.0`, **0 warnings, 0 hints** |
| Independência | `uGameEngine` não declara nenhuma unit (sem Indy, HTTP, JSON ou interface) |
| EngineCheck | 19/19 casos OK: M-01 a M-04, M-05 (L1, L2, L3, C1, C2, C3, D1, D2), M-06 a M-12 |
| M-12 exaustivo | 549.946 posições comparadas com o oráculo em 3,3 s; 255.168 partidas, 131.184 vitórias de X, 77.904 de O, 46.080 empates, 12.672 vitórias com 5 células |
| SB-01 — trocar (2,4,6) em `WIN_LINES` | Detectada: falharam M-05-D2, M-06, M-12 |
| SB-02 — desligar célula ocupada | Detectada: falharam M-03, M-10, M-12 |
| SB-03 — inverter a ordem encerrada × ocupada | Detectada: falharam M-08, M-12 |
| SB-05 — não trocar o turno | Detectada: falharam M-02 e outros 15 casos, incluindo M-12 |
| Regressão `GET /health` | 200, `{"status":"ok"}` |

### Limitações e observações

- Os totais do M-12 validam o **oráculo**; o motor é validado pela comparação posição a posição (ver `docs/test-plan.md`, 9.1). Isso ficou visível na fase vermelha, quando os totais bateram mesmo sem motor.
- A contagem de "verificações" do EngineCheck (282) não inclui as comparações do M-12, que só registram uma verificação quando falham.
- `TGameEngine` não é thread-safe por si; a serialização entra com `uGameService` na Entrega 3.
- As validações foram executadas abrindo os scripts pelo Explorador de Arquivos do Windows; os logs foram lidos diretamente da pasta do projeto.
- O repositório Git ainda não foi inicializado.

---

## Entrega 3 — Serviço de jogo e API HTTP

| Item | Valor |
|---|---|
| Data | 2026-10-15 |
| Fase vermelha | `scripts\validate-step3-red.cmd` → `logs\step3-red.log` (18:14) |
| Validação | `scripts\validate-step3.cmd` → `logs\step3-validation.log` (18:20) |
| Regressão da Entrega 2 | `scripts\validate-step2.cmd` → `logs\step2-validation.log` (18:22): 13/13 |
| Resultado | **APROVADO** — 48 de 48 verificações; EngineCheck 27/27 casos |

### Ciclo de testes

1. **Contrato HTTP** fechado no plano (v0.5, seção 3) antes do código.
2. **Fase vermelha (18:14).** Testes novos (SV, J no EngineCheck; A e R por HTTP real) contra esqueletos de `uGameService`/`uGameJson` e o servidor da Entrega 2: os 19 casos M passaram, 7 dos 8 casos SV/J falharam (o J-04 passou por acaso, pois o esqueleto recusava tudo) e todos os cenários A e R falharam.
3. **Primeira execução real (18:16) — erro de compilação.** Comentários `{ ... }` com exemplos de JSON: o primeiro `}` do JSON encerrava o comentário (`E2038 Illegal character`). Corrigido usando `(* ... *)` nesses comentários.
4. **Segunda execução (18:18) — 5 falhas em 48:**
   - J-03 e A-04: o parser JSON do Delphi Berlin **normaliza o texto do número** (`4.0` → `4`, `1e0` → `1`), então o servidor aceitava essas jogadas, ao contrário do contrato v0.5. Decisão: contrato ajustado para exigir **valor** inteiro (plano v0.6, test-plan v0.6), mantendo a RN-04 da spec; comentário incorreto no código corrigido.
   - A-05, A-08, A-09: defeitos do script de teste (o PowerShell convertia um corpo vazio em `$null`; o `HttpClient` do .NET Framework não envia corpo em `GET`). Corrigidos no script.
5. **Terceira execução (18:20): 48/48.**

### Resultados da validação final

| Verificação | Resultado |
|---|---|
| Compilação | OK, `compiler version 31.0`, 0 warnings, 0 hints |
| Independência | motor, serviço e JSON sem Indy nem interface |
| EngineCheck | 27/27: M-01 a M-12 (19 casos), SV-01 a SV-03, J-01 a J-05 |
| SV-03 | 8 threads × 2.000 operações = 16.000 operações no serviço, 0 problemas |
| Grupo A (HTTP real) | A-01 a A-09, A-11, A-12: todos aprovados |
| Grupo R (HTTP real) | R-01 a R-28: todos aprovados (8 vitórias, 9ª jogada, vitória dupla, empate, bloqueios, reinícios, concorrência) |
| R-27 | 20 repetições de 2 jogadas simultâneas na mesma célula: sempre uma 200 e uma 409 |
| R-28 | 10 rajadas de 18 jogadas simultâneas: estado sempre coerente, nenhuma resposta 500 |
| SB-04 | Servidor sem trava + 50 ms de atraso: o R-27 detectou 39 problemas (as duas jogadas aceitas) |
| Erros internos | nenhum 500 no log do servidor |

### Limitações e observações

- Os cenários A e R foram executados por um script PowerShell (`HttpClient`); na Entrega 4 passam para o Playwright com os mesmos IDs.
- A-10 (arquivos estáticos) e o `POST /` do A-09 ficam para a Entrega 5.
- O teste de concorrência por HTTP depende de as requisições realmente se sobreporem; a sabotagem SB-04 mostrou que, sem a trava, o R-27 detecta o defeito.
- Corpo de requisição sem limite de tamanho (fora do escopo; servidor só local).
- Encerramento por Ctrl+C continua com verificação manual pendente; repositório Git inicializado depois, na publicação.

---

## Entrega 4 — Automação da API com Playwright

| Item | Valor |
|---|---|
| Data | 2026-10-15 |
| Validação | `scripts\validate-step4.cmd` → `logs\step4-validation.log` (18:31) |
| Comando da suíte completa | `cd tests` e `npx playwright test` (equivale a `npm test`) |
| Relatório HTML | `tests\playwright-report\index.html` (`npx playwright show-report`) |
| Resultado | **APROVADO** — 12 de 12 verificações; suíte 65/65 em duas execuções |

### Versões

| Componente | Versão | Onde |
|---|---|---|
| Node.js | 24.11.1 (já instalado; não alterado) | global |
| npm | 11.6.2 (já instalado; o aviso de nova versão foi ignorado) | global |
| @playwright/test / playwright / playwright-core | 1.64.1 | `tests\node_modules` |
| TypeScript | 5.9.3 | `tests\node_modules` |
| @types/node | 24.10.1 | `tests\node_modules` |

Compatibilidade: o Playwright 1.64.1 exige Node ≥ 20 (atendido). A documentação oficial lista Windows 11/Server 2019+ e não cita o Windows 10; como esta entrega não usa navegador, apenas o executor Node, a suíte rodou normalmente no Windows 10 Pro build 19045. A compatibilidade do Chromium com o Windows 10 fica para a Entrega 5.

### Resultados

| Verificação | Resultado |
|---|---|
| V-01 Node.js compatível | v24.11.1 |
| B-01 Compilação Delphi Berlin | OK, `compiler version 31.0`, 0 warnings/hints |
| B-02 EngineCheck | 27/27 casos |
| D-01 / D-02 Instalação local | `npm install`: 6 pacotes em 24 s; Playwright 1.64.1, TypeScript 5.9.3; `package-lock.json` gerado |
| T-01 Tipos | `tsc --noEmit` sem erros |
| P-01 Suíte completa, execução 1 | 65 aprovados, 0 falhas, 0 instáveis, 0 pulados (8,9 s) |
| P-02 Suíte completa, execução 2 | 65 aprovados, 0 falhas, 0 instáveis, 0 pulados (7,2 s) |
| P-03 Relatório HTML | gerado |
| P-04 Cada arquivo sozinho, em ordem inversa | 7/7 arquivos aprovados (10 + 8 + 8 + 2 + 20 + 12 + 5 testes) |
| P-05 Executável renomeado | a suíte falhou ao iniciar o servidor (`Process from config.webServer was not able to start`) |
| P-06 SB-04 (servidor sem trava + atraso) | o R-27 do Playwright falhou já na 1ª repetição (códigos `[200,200]` em vez de `[200,409]`) |

### Testes da suíte (65)

- `api/contract.spec.ts` (5): A-01, A-02, A-03, A-11, A-12.
- `api/validation.spec.ts` (20): A-04 (10 posições inválidas), A-05 (8 corpos inválidos), A-06, A-07.
- `api/routes.spec.ts` (12): A-08 (4 rotas), A-09 (8 combinações método/rota).
- `rules/turns.spec.ts` (8): R-01 a R-08.
- `rules/wins.spec.ts` (10): R-09 a R-18.
- `rules/end-and-reset.spec.ts` (8): R-19 a R-26.
- `rules/concurrency.spec.ts` (2): R-27, R-28.

### Limitações e observações

- Nenhum defeito foi encontrado nesta execução, então não houve ciclo de correção; as provas de que a suíte não passa por acaso são o P-05 (sem servidor real, falha) e o P-06 (sem trava, falha).
- O teste exaustivo de todas as partidas (M-12) não foi repetido por HTTP (ver `docs/test-plan.md`, cobertura por camada).
- O Playwright finaliza o servidor à força no fim da suíte (sem passar pelo Ctrl+C); a porta é liberada. A verificação manual do Ctrl+C continua pendente.
- `scripts\validate-step3.ps1` continua funcional, mas a referência para os cenários A e R passa a ser a suíte Playwright.
- O repositório Git ainda não foi inicializado.

---

## Entrega 5 — Interface web e testes E2E no Chromium

| Item | Valor |
|---|---|
| Data | 2026-10-15 |
| Fase vermelha | `scripts\validate-step5-red.cmd` → `logs\step5-red.log` (18:50) |
| Validação | `scripts\validate-step5.cmd` → `logs\step5-validation.log` (19:07–19:12) |
| Comando da suíte completa | `cd tests` e `npx playwright test` |
| Resultado | **APROVADO** — 13 de 13 verificações; suíte 109/109 (80 API + 29 Chromium) em duas execuções; aguardando aprovação |

### O que foi entregue

- `web/index.html`, `web/style.css`, `web/app.js`: a interface só exibe o estado devolvido pelo backend; não há regra de vitória, empate ou turno no JavaScript (CI-01 a CI-16).
- O servidor Delphi serve os três arquivos de uma lista fixa (DT-04), com `--www <pasta>` para trocar a pasta.
- Uma requisição por vez (DT-22), tempo-limite de 8 s e botão "Tentar novamente" (CI-10), navegação por teclado e nomes acessíveis (CI-14), layout de 360 px (CI-15).
- Testes: `api/static.spec.ts` (A-10, 15 testes) e `ui/*.spec.ts` (U-01 a U-22, 29 testes no Chromium).

### Ciclo de testes

1. **Fase vermelha** (interface vazia): 71 aprovados, 38 falharam — exatamente os testes de interface e de arquivos estáticos. Um item do script (R-02) acusou falha por defeito na própria verificação; corrigido no script, sem mudar os testes.
2. **Primeira execução verde**: 104/109. U-08, U-09, U-10, U-18 e U-22 esgotaram o tempo porque o Playwright espera elementos com `aria-disabled="true"` ficarem habilitados. Não era defeito da interface: com a partida encerrada, o clique precisa chegar ao servidor para ser recusado (DT-09). Correção em `tests/support/ui.ts` (`clickCell` força o clique só em célula inativa). A SB-06 dessa execução foi descartada, porque o U-08 já falhava sem a sabotagem.
3. **Segunda execução**: tudo aprovado; a SB-06 passou a valer.

### Resultados

| Verificação | Resultado |
|---|---|
| B-01 Compilação Delphi Berlin | OK, `compiler version 31.0`, 0 warnings/hints |
| B-02 EngineCheck | 27/27 casos, 359 verificações |
| D-01 `npm ci` | 6 pacotes |
| C-01 Chromium do Playwright 1.64.1 | instalado e funcionando no Windows 10 Pro 19045 |
| T-01 Tipos | `tsc --noEmit` sem erros |
| P-01 Suíte completa (servidor iniciado pelo Playwright) | 109 aprovados, 0 falhas, 0 instáveis, 0 pulados (84,3 s) |
| P-02 Relatório HTML | gerado |
| P-03 Suíte completa (servidor externo) | 109 aprovados, 0 falhas, 0 instáveis, 0 pulados (46,7 s) |
| S-01 Log do servidor | 1053 requisições, nenhum 500, exceção ou aviso; 102 estáticos com 200 |
| P-04 Cada arquivo sozinho, ordem inversa | 13/13 arquivos aprovados |
| P-05 SB-06 (interface desenha antes do servidor) | U-08 falhou: esperado `""`, recebido `"X"` |
| P-06 SB-04 (servidor sem trava) | R-27 falhou |
| P-07 Capturas de tela | `docs/screenshots/*.png` geradas da interface real |

### Limitações e observações

- Só o Chromium foi testado (DT-23); Firefox e WebKit estão fora do escopo.
- Os testes de falha de rede (U-13, U-17, U-18, U-19) apenas abortam ou atrasam requisições reais com `page.route`; nenhuma resposta do servidor é fabricada.
- Verificação manual do Ctrl+C continua pendente.
