# Plano de testes — Jogo da Velha (Delphi Berlin + Web)

| Campo | Valor |
|---|---|
| Versão | 0.9 |
| Data | 2026-10-15 |
| Etapa SDD | 3 — Testes (definição) |
| Base | `docs/spec.md` v0.5 e `docs/plan.md` v0.8 |
| Status | **Planejado. Nenhum teste foi escrito ou executado.** Aguardando aprovação. |

---

## 1. Objetivo

Definir, antes de qualquer implementação, os cenários que provam que a aplicação atende à especificação, e os critérios para considerar cada cenário e a suíte como aprovados.

Cada cenário indica pré-condições, ações, resultado esperado e a forma de verificação. Os IDs dos cenários aparecem no título de cada teste, junto com o critério de aceitação (CA) coberto, por exemplo: `R-08 [CA-12] vitória na linha 3-4-5`.

Toda sequência de jogadas usada neste documento foi conferida por um script de simulação das regras durante a escrita do plano. Isso valida os **dados** dos cenários, não a aplicação.

## 2. Organização em grupos

| Grupo | O que prova | Ferramenta | Contra o quê | Pasta / arquivo |
|---|---|---|---|---|
| **M — Motor** | As regras puras, sem HTTP | `EngineCheck.exe` (programa console Delphi) | Unit `uGameEngine` compilada | `server/EngineCheck.dpr` |
| **R — Regras de negócio** | As regras aplicadas **pelo backend em execução** | Playwright `request` (HTTP, sem navegador) | `TicTacToeServer.exe` real | `tests/rules/*.spec.ts` |
| **A — Endpoints** | O contrato HTTP: códigos, cabeçalhos, formato JSON, rotas, erros | Playwright `request` | `TicTacToeServer.exe` real | `tests/api/*.spec.ts` |
| **U — Interface** | O que o usuário vê e faz no navegador | Playwright + Chromium | Página servida pelo `TicTacToeServer.exe` real | `tests/ui/*.spec.ts` |

Por que separar R de A: R responde "as regras do jogo estão no backend e funcionam?"; A responde "a API se comporta como o contrato do plano?". Uma mudança no formato do JSON quebra A, não R; um erro numa combinação vencedora quebra R e M.

Ordem de execução recomendada: **M → A → R → U**. Se o motor falha, não adianta rodar o resto.

**Cobertura por camada (a partir da Entrega 4).** Cada regra é verificada onde é mais barato e mais forte, sem duplicar o que não acrescenta:

| Assunto | EngineCheck (Delphi, sem HTTP) | Playwright (HTTP real) |
|---|---|---|
| Estado inicial, alternância | M-01, M-02 | R-01 a R-04, A-01 |
| Célula ocupada | M-03 | R-06 a R-08 |
| Posição fora do intervalo | M-04 | A-04, R-22 |
| Tipos e formato do corpo (JSON, UTF-8) | J-02 a J-04 | A-04, A-05, A-06 |
| 8 vitórias, 9ª jogada, vitória dupla | M-05, M-06 | R-09 a R-18 |
| **Todas as 255.168 partidas** | **M-12 (só aqui)** | — (não repetido: custaria horas por HTTP e não acrescenta cobertura de API) |
| Empate e bloqueio após o fim | M-07 a M-09 | R-19 a R-22 |
| Reinício | M-10 | A-02, R-23 a R-26 |
| Cópia do estado | M-11, SV-01 | — (interno) |
| Concorrência | SV-03 (threads no serviço) | R-27, R-28 (requisições simultâneas) |
| Formato do JSON e erros | J-01, J-05 | A-01, A-03, A-07, `expectError` em todos os erros |
| Rotas, métodos, HEAD, `/health` | — | A-08, A-09, A-11, A-12 |

O script `scripts\validate-step3.ps1` (Entrega 3) cobre os mesmos cenários A e R por PowerShell; ele continua disponível, mas a referência passa a ser a suíte Playwright.

**Execução por entrega.** Na Entrega 3, os grupos A e R são executados por requisições HTTP reais no script `scripts\validate-step3.ps1` (PowerShell + `HttpClient`), com os mesmos IDs e verificações deste documento (plano, DT-19). Na Entrega 4 eles passam a ser testes Playwright, sem mudar os cenários. O A-10 (arquivos estáticos) e o `POST /` do A-09 ficam para a Entrega 5, quando os estáticos existirem.

## 3. Como verificar que as regras estão de fato no backend

Este é o ponto central pedido pela especificação (RN-14). A prova combina cinco evidências:

1. **Grupo R não usa navegador.** Todas as regras (alternância, célula ocupada, 8 vitórias, empate, bloqueio, reinício) são verificadas apenas por HTTP. Se o grupo R passa, as regras estão no servidor, independentemente do JavaScript da página.
2. **A interface não filtra cliques.** Nos cenários de UI com jogada inválida (U-03, U-08, U-09), o teste espera a requisição `POST /api/game/moves` acontecer com `page.waitForResponse` e confere que a resposta foi 409. Isso prova que a recusa veio do backend e não de uma validação local.
3. **Conferência cruzada UI × API.** Ao final dos cenários de UI, o teste chama `GET /api/game` e compara com o que está na tela (tabuleiro, status, células destacadas). A tela tem de ser um reflexo do backend.
4. **Estado preparado só pelo backend.** No U-16, a partida é montada via API antes de abrir a página; a interface nunca viu essas jogadas e mesmo assim tem de exibir o estado correto e, depois de um clique, a vitória decidida pelo servidor.
5. **Testes de sabotagem (Etapa 5).** Altera-se temporariamente o backend (por exemplo, remove-se uma combinação vencedora) e confirma-se que os testes correspondentes **falham**. Sem isso, um teste que sempre passa não prova nada. Ver seção 9.

Nenhum teste substitui respostas do backend por respostas falsas. A única intervenção de rede é o U-13 (servidor inacessível), que **aborta** requisições no navegador para simular a queda; ele não fabrica respostas.

## 4. Infraestrutura comum dos testes Playwright

| Item | Definição |
|---|---|
| Servidor | Iniciado pelo `webServer` do Playwright: `"..\server\bin\TicTacToeServer.exe" --port 8765`, considerado pronto quando `GET /health` responde; finalizado pelo Playwright ao fim da suíte |
| Endereço | Sempre `http://127.0.0.1:8765`. **Nunca `localhost`** (ver seção 10, item I-07). |
| Execução | `workers: 1`, `fullyParallel: false`, `retries: 0` |
| Isolamento | Fixture `game` (`support/fixtures.ts`): `POST /api/game/reset` com verificação de 200 antes de cada teste |
| Helpers de API (`support/api.ts`) | `resetGame()`, `getState()`, `postMove(pos)`, `postRaw(body, contentType?)`, `playMovesApi(seq)` (faz as jogadas e verifica 200 em cada uma) |
| Helpers de UI (`support/board.ts`) | `cell(page, i)` = `getByTestId('cell-' + i)`; `playMovesUi(page, seq)` (clica cada célula e espera a resposta do POST); `expectBoard(page, ['X','','O',...])`; `expectWinning(page, [0,1,2])` (as indicadas com `data-winning="true"` e as demais sem) |
| Estado esperado | `INITIAL_STATE` = `{ tabuleiro: 9 × "", status: "EM_ANDAMENTO", jogadorDaVez: "X", vencedor: null, celulasVencedoras: [] }` |
| Comparação de estado | `expect(await getState()).toEqual(esperado)`: igualdade profunda do JSON inteiro, não apenas de um campo |
| "Estado não muda" | `const antes = await getState()`, ação, `expect(await getState()).toEqual(antes)` |
| Asserções de UI | Só asserções que esperam automaticamente (`toHaveText`, `toHaveAttribute`, `toBeVisible`, `toBeHidden`); sem `waitForTimeout` |

Mensagens de erro (do `docs/plan.md`, seção 3.4), comparadas por igualdade exata, com acentos:

| Código | Mensagem |
|---|---|
| `CORPO_INVALIDO` | O corpo da requisição deve ser um objeto JSON válido. |
| `POSICAO_INVALIDA` | A posição deve ser um número inteiro de 0 a 8. |
| `PARTIDA_ENCERRADA` | A partida já terminou. Clique em "Nova partida" para jogar novamente. |
| `CELULA_OCUPADA` | Esta célula já está ocupada. |
| `ROTA_NAO_ENCONTRADA` | Rota não encontrada. |
| `METODO_NAO_PERMITIDO` | Método não permitido para esta rota. |

## 5. Sequências de jogadas de referência

Notação: lista de posições na ordem das jogadas; X sempre começa.

| ID | Sequência | Resultado | Células vencedoras |
|---|---|---|---|
| S-L1 | 0, 3, 1, 4, 2 | X vence | 0, 1, 2 |
| S-L2 | 3, 0, 4, 1, 5 | X vence | 3, 4, 5 |
| S-L3 | 0, 6, 1, 7, 4, 8 | O vence | 6, 7, 8 |
| S-C1 | 0, 1, 3, 2, 6 | X vence | 0, 3, 6 |
| S-C2 | 0, 1, 3, 4, 8, 7 | O vence | 1, 4, 7 |
| S-C3 | 2, 0, 5, 1, 8 | X vence | 2, 5, 8 |
| S-D1 | 0, 1, 4, 2, 8 | X vence | 0, 4, 8 |
| S-D2 | 2, 0, 4, 1, 6 | X vence | 2, 4, 6 |
| S-9A | 0, 1, 2, 4, 5, 3, 7, 6, 8 | X vence na 9ª jogada | 2, 5, 8 |
| S-DUP | 0, 1, 2, 3, 6, 5, 8, 7, 4 | X vence com duas diagonais | 0, 2, 4, 6, 8 |
| S-EMP | 0, 1, 2, 4, 3, 5, 7, 6, 8 | Empate | nenhuma |

As vitórias cobrem os dois jogadores (O vence em S-L3 e S-C2). Em todas, ninguém vence antes da última jogada.

---

## 6. Grupo R — Regras de negócio no backend (Playwright `request`)

Arquivos: `tests/rules/start-and-turns.spec.ts`, `occupied.spec.ts`, `wins.spec.ts`, `draw.spec.ts`, `lock.spec.ts`, `reset.spec.ts`, `concurrency.spec.ts`.

Pré-condição comum a todos: servidor iniciado e `POST /api/game/reset` executado no `beforeEach`.

### Inicialização e alternância

**R-01 — Estado inicial de uma partida** *(CA-01; RN-01, RN-02)*
- Pré-condição: nenhuma além da comum.
- Ações: `GET /api/game`.
- Esperado: 200; corpo igual a `INITIAL_STATE`.
- Verificação: `expect(await getState()).toEqual(INITIAL_STATE)`.

**R-02 — Primeira jogada é de X e passa a vez para O** *(CA-02; RN-03, RN-07)*
- Ações: `POST /api/game/moves {"posicao":0}`.
- Esperado: 200; `tabuleiro[0] = "X"`, demais vazias; `jogadorDaVez = "O"`; `status = "EM_ANDAMENTO"`.
- Verificação: `toEqual` do corpo da resposta com o estado esperado; `GET /api/game` igual ao corpo da resposta.

**R-03 — Segunda jogada é de O e devolve a vez para X** *(CA-03; RN-03)*
- Pré-condição: X jogou em 0.
- Ações: jogada em 4.
- Esperado: `tabuleiro[4] = "O"`; `jogadorDaVez = "X"`.
- Verificação: `toEqual` com o estado completo.

**R-04 — Alternância ao longo de 8 jogadas** *(RN-03, RN-07)*
- Ações: as 8 primeiras jogadas de S-EMP (0, 1, 2, 4, 3, 5, 7, 6), uma por vez.
- Esperado: na jogada *n* (1 a 8), a célula recebe X se *n* é ímpar e O se é par; após cada jogada, `jogadorDaVez` é o outro símbolo; `status` permanece `EM_ANDAMENTO`.
- Verificação: laço com `expect` após cada resposta, conferindo símbolo gravado e `jogadorDaVez`.

**R-05 — O cliente não escolhe o símbolo** *(CA-07; RN-07)*
- Ações: `POST /api/game/moves {"posicao":0,"simbolo":"O","jogador":"O"}`.
- Esperado: 200; `tabuleiro[0] = "X"`; `jogadorDaVez = "O"`.
- Verificação: `toEqual` com o estado esperado.

### Células ocupadas

**R-06 — Jogada na célula ocupada pelo adversário é rejeitada** *(CA-04; RN-05, RN-12)*
- Pré-condição: X jogou em 0 (vez de O).
- Ações: guardar o estado; jogada em 0.
- Esperado: 409, `erro.codigo = "CELULA_OCUPADA"` e mensagem exata; estado igual ao guardado (célula 0 com X, vez de O).
- Verificação: `response.status()`, `toEqual` do corpo de erro, `toEqual(antes)`.

**R-07 — Jogada na própria célula também é rejeitada** *(RN-05, RN-12)*
- Pré-condição: X:0, O:4 (vez de X).
- Ações: guardar o estado; X joga em 0.
- Esperado: 409 `CELULA_OCUPADA`; estado inalterado, vez continua de X.
- Verificação: como no R-06.

**R-08 — Após rejeição, a partida segue normalmente** *(RN-12)*
- Pré-condição: estado do R-06 após a rejeição.
- Ações: O joga em 4.
- Esperado: 200; `tabuleiro[4] = "O"`; vez de X.
- Verificação: `toEqual` com o estado esperado.

### Vitórias (as 8 combinações)

Um teste parametrizado: `for (const caso of VITORIAS) test(...)`. Cada caso:
- Pré-condição: partida reiniciada.
- Ações: `playMovesApi` com as jogadas da sequência, exceto a última; conferir que `status` ainda é `EM_ANDAMENTO`; fazer a última jogada.
- Esperado: 200; `status = "VITORIA"`; `vencedor` correto; `jogadorDaVez = null`; `celulasVencedoras` exatamente igual à lista esperada; tabuleiro com todas as jogadas.
- Verificação: `toEqual` com o estado completo esperado, montado a partir da sequência.

| ID | Combinação | Sequência | CA |
|---|---|---|---|
| R-09 | Linha 1 (0-1-2) | S-L1 | CA-08 |
| R-10 | Linha 2 (3-4-5) | S-L2 | CA-12 |
| R-11 | Linha 3 (6-7-8), vitória de O | S-L3 | CA-12 |
| R-12 | Coluna 1 (0-3-6) | S-C1 | CA-12 |
| R-13 | Coluna 2 (1-4-7), vitória de O | S-C2 | CA-09 |
| R-14 | Coluna 3 (2-5-8) | S-C3 | — (cobertura extra de RN-08) |
| R-15 | Diagonal principal (0-4-8) | S-D1 | CA-10 |
| R-16 | Diagonal secundária (2-4-6) | S-D2 | CA-11 |

**R-17 — Vitória na 9ª jogada prevalece sobre empate** *(CA-13; RN-09)*
- Ações: S-9A.
- Esperado: `status = "VITORIA"` (não `EMPATE`), vencedor X, células `[2,5,8]`, tabuleiro cheio.

**R-18 — Vitória com duas combinações** *(CA-14; RN-08)*
- Ações: S-DUP.
- Esperado: `status = "VITORIA"`, vencedor X, células `[0,2,4,6,8]` em ordem crescente.

### Empate

**R-19 — Empate com tabuleiro cheio sem combinação** *(CA-15; RN-09)*
- Ações: S-EMP, conferindo `EM_ANDAMENTO` após a 8ª jogada.
- Esperado: `status = "EMPATE"`; `vencedor = null`; `jogadorDaVez = null`; `celulasVencedoras = []`; 9 células preenchidas.
- Verificação: `toEqual` com o estado completo.

### Bloqueio após o fim

**R-20 — Nenhuma célula aceita jogada após vitória** *(CA-18; RN-06, RN-10, RN-12)*
- Pré-condição: S-L1 concluída (células vazias: 5, 6, 7, 8).
- Ações: guardar o estado; tentar jogar em cada célula vazia (5, 6, 7, 8) e numa ocupada (0).
- Esperado: todas 409 `PARTIDA_ENCERRADA` (inclusive a ocupada, por causa da RN-15); estado igual ao guardado após cada tentativa.

**R-21 — Jogada após empate responde "partida encerrada", não "célula ocupada"** *(CA-17, CA-18; RN-15)*
- Pré-condição: S-EMP concluída.
- Ações: jogada em 4.
- Esperado: 409 `PARTIDA_ENCERRADA`; estado inalterado.

**R-22 — Posição inválida tem precedência sobre partida encerrada** *(RN-15)*
- Pré-condição: S-L1 concluída.
- Ações: jogada com posição 9.
- Esperado: 400 `POSICAO_INVALIDA`; estado inalterado.

### Reinício

**R-23 — Reiniciar após vitória** *(CA-19; RN-11)*
- Pré-condição: S-L1 concluída.
- Ações: `POST /api/game/reset`.
- Esperado: 200; corpo e `GET /api/game` iguais a `INITIAL_STATE`.

**R-24 — Reiniciar após empate** *(RN-11)*
- Pré-condição: S-EMP concluída. Ações e esperado: como no R-23.

**R-25 — Reiniciar no meio da partida** *(CA-20; RN-11)*
- Pré-condição: X:0, O:4. Ações e esperado: como no R-23.

**R-26 — Partida nova é jogável desde o início** *(RN-11)*
- Pré-condição: R-23 executado.
- Ações: jogada em 0 (célula que era de X na partida anterior).
- Esperado: 200; `tabuleiro[0] = "X"`; vez de O.

### Concorrência

**R-27 — Duas jogadas simultâneas na mesma célula** *(CA-25; RNF-06)*
- Ações: repetir 20 vezes: reiniciar; disparar dois `postMove(0)` com `Promise.all`.
- Esperado: em cada repetição, exatamente uma resposta 200 e uma 409 `CELULA_OCUPADA`; estado final com só a célula 0 = X e vez de O.
- Verificação: contagem dos status e `toEqual` do estado final.
- Observação: um teste de concorrência pode passar por sorte mesmo com um erro; as 20 repetições reduzem esse risco, e o teste de sabotagem SB-04 (seção 9) confirma que ele detecta a ausência da trava.

**R-28 — Rajada de jogadas simultâneas mantém o estado coerente** *(CA-25; RNF-06)*
- Ações: repetir 10 vezes: reiniciar; disparar ao mesmo tempo 18 jogadas (cada posição de 0 a 8, duas vezes); depois `GET /api/game`.
- Esperado: toda resposta é 200 ou 409 (`CELULA_OCUPADA` ou `PARTIDA_ENCERRADA`), nunca 500; o número de respostas 200 é igual ao número de células preenchidas; nº de X − nº de O é 0 ou 1; o estado final é coerente (em andamento com a vez certa, vitória com células vencedoras do vencedor ou empate com tabuleiro cheio); cada resposta 200 traz um estado em que a célula jogada está preenchida.

## 7. Grupo A — Endpoints HTTP (Playwright `request`)

Arquivos: `tests/api/state.spec.ts`, `moves-validation.spec.ts`, `routes.spec.ts`, `static.spec.ts`.

Pré-condição comum: servidor iniciado e partida reiniciada.

**A-01 — `GET /api/game`: formato e cabeçalhos** *(RNF-08; DT-14)*
- Esperado: 200; `content-type` contém `application/json` e `charset=utf-8`; `cache-control` contém `no-store`; corpo tem exatamente os campos `tabuleiro` (9 strings), `status`, `jogadorDaVez`, `vencedor`, `celulasVencedoras` (array).
- Verificação: `response.headers()`, `Object.keys(body).sort()` e tipos.

**A-02 — `POST /api/game/reset`: com e sem corpo**
- Ações: reset sem corpo; reset com corpo `{"qualquer":1}`.
- Esperado: ambos 200 com corpo igual a `INITIAL_STATE`.

**A-03 — `POST /api/game/moves`: resposta igual ao estado persistido**
- Ações: jogada em 4; depois `GET /api/game`.
- Esperado: corpo da jogada igual ao do `GET`.

**A-04 — Posições inválidas** *(CA-05; RN-04, RN-12)*
- Ações: um teste por corpo, guardando o estado antes:

| Corpo enviado | Motivo |
|---|---|
| `{"posicao":9}` | acima do intervalo |
| `{"posicao":-1}` | abaixo do intervalo |
| `{"posicao":4.5}` | não inteiro |
| `{"posicao":"4"}` | texto |
| `{"posicao":null}` | nulo |
| `{"posicao":true}` | booleano |
| `{}` | campo ausente |
| `{"Posicao":4}` | nome com maiúscula (campo é sensível a maiúsculas) |
| `{"posicao":0.5}` | valor fracionário |
| `{"posicao":99999999999}` | não cabe em inteiro de 32 bits |

- Esperado: 400; `erro.codigo = "POSICAO_INVALIDA"` com mensagem exata; estado inalterado.

**A-05 — Corpo inválido** *(CA-06; CE-04; RN-15)*
- Ações: sem corpo; corpo vazio (`Content-Length: 0`); `abc`; `{"posicao":`; `[4]`; `4`; `"x"`; bytes que não são UTF-8 válido (`{"posicao":` + `0xFF` + `}`).
- Esperado: 400 `CORPO_INVALIDO` com mensagem exata; estado inalterado.
- Verificação: `postRaw` com `data` como string crua, para que o Playwright não converta em JSON.

**A-06 — `Content-Type` diferente e inteiros escritos com fração ou expoente são aceitos** *(plano 3.3)*
- Ações: `{"posicao":4}` com `Content-Type: text/plain`; depois, numa partida nova, `{"posicao":4.0}` e `{"posicao":1e0}`.
- Esperado: 200 em todas; X na célula 4 e O na célula 1.

**A-07 — Acentos chegam corretos em UTF-8** *(RNF-08)*
- Ações: provocar `CELULA_OCUPADA` e `PARTIDA_ENCERRADA`.
- Esperado: `erro.mensagem` exatamente igual ao texto da tabela da seção 4, com "é", "á" e aspas.
- Verificação: além do `toEqual`, decodificar `await response.body()` com `TextDecoder('utf-8', { fatal: true })`; se os bytes não forem UTF-8 válido, o teste falha.

**A-08 — Rota de API inexistente** *(CA-26; CE-05)*
- Ações: `GET /api/inexistente`; `POST /api/game/movimento`.
- Esperado: 404 `ROTA_NAO_ENCONTRADA`; estado inalterado.

**A-09 — Método não permitido** *(CA-26; CE-06)*

| Requisição | `Allow` esperado |
|---|---|
| `POST /api/game` | `GET, HEAD` |
| `DELETE /api/game` | `GET, HEAD` |
| `GET /api/game/moves` | `POST` |
| `PUT /api/game/moves` | `POST` |
| `GET /api/game/reset` | `POST` |
| `POST /` | `GET, HEAD` |

- Esperado: 405 `METODO_NAO_PERMITIDO` (na API) com o cabeçalho `Allow`; estado inalterado.
- Verificação: `request.fetch(url, { method })` para cobrir `PUT` e `DELETE`.

**A-10 — Arquivos estáticos** *(CA-26; CE-09; DT-04)*

| Requisição | Esperado |
|---|---|
| `GET /` e `GET /index.html` | 200, `text/html; charset=utf-8`, `Cache-Control: no-cache`, mesmo corpo, contém `data-testid="board"` |
| `GET /style.css` | 200, `text/css; charset=utf-8` |
| `GET /app.js` | 200, `text/javascript; charset=utf-8` |
| `HEAD /` | 200 sem corpo |
| `GET /inexistente.js`, `GET /docs/spec.md`, `GET /..%2Fdocs%2Fspec.md`, `GET /server/bin/TicTacToeServer.exe`, `GET /web/index.html` | 404 JSON `ROTA_NAO_ENCONTRADA` (nada fora da lista fixa é servido) |
| `POST /`, `DELETE /app.js`, `PUT /style.css` | 405 com `Allow: GET, HEAD` |

O `/health` e as rotas da API continuam com o mesmo comportamento (A-01 a A-12 inalterados).

**A-11 — `HEAD /api/game`** *(plano 3.1)*
- Esperado: 200, sem corpo, mesmo `content-type` do GET. É o método que o Playwright pode usar para saber se o servidor subiu.

**A-12 — Verificação de saúde** *(CA-27; RNF-14)*
- Ações: guardar o estado da partida; `GET /health`; `HEAD /health`; `POST /health`.
- Esperado: GET 200 com `application/json; charset=utf-8` e corpo exatamente `{"status":"ok"}`; HEAD 200 sem corpo; POST 405 com `Allow: GET, HEAD`; estado da partida inalterado.
- Verificação: `toEqual({ status: 'ok' })` e comparação do estado antes e depois.
- Também verificado, antes do Playwright, pelo script `scripts\validate-step1.cmd` (Entrega 1).

## 8. Grupo U — Interface (Playwright + Chromium)

Arquivos: `tests/ui/start-and-turns.spec.ts`, `wins.spec.ts`, `end-and-reset.spec.ts`, `resilience.spec.ts`, `accessibility.spec.ts`. Projeto Playwright `chromium` (Desktop Chrome, sem interface gráfica).

**Infraestrutura comum (fixture `ui`, `support/ui.ts`):**
- A partida é reiniciada pela API antes de cada teste (fixture `game`).
- Durante o teste são registrados: erros de console da página, requisições que falharam e respostas 404 ou 5xx. No fim, o teste falha se houver algum, exceto falhas de rede provocadas pelo próprio teste (U-13, U-19). As linhas "Failed to load resource" do Chrome para 400/409 são esperadas e cobertas pelo controle de respostas.
- **Verificação cruzada automática:** no fim de todo teste, o texto de cada célula, as células com `data-winning="true"` e o status exibido são comparados com `GET /api/game`. A tela tem de ser um reflexo do backend.
- Ações: `ui.click(i)` clica e aguarda a resposta do `POST /api/game/moves`. Em célula com `aria-disabled="true"` (partida encerrada ou carregamento) o clique é feito com `force: true`: no navegador o botão continua clicável (CI-07, DT-09), mas o Playwright, por padrão, espera elementos `aria-disabled` ficarem habilitados (constatado na Entrega 5); `ui.play([...])` exige 200 em cada jogada; esperas sempre por condições observáveis (`aria-busy="false"`, textos, atributos), nunca por tempo fixo.

| ID | Cenário | Ações | Esperado | CA |
|---|---|---|---|---|
| U-01 | Página inicial | abrir `/` | título "Jogo da Velha"; 9 células vazias; status "Vez do jogador X"; sem destaque; erro e "Tentar novamente" ocultos; CSS aplicado (tabuleiro em `grid`); JS executado (`data-state="playing"`) | CA-01 |
| U-02 | Alternância | clicar 0 e 4 | X em 0 e "Vez do jogador O"; depois O em 4 e "Vez do jogador X" | CA-02, CA-03 |
| U-03 | Célula ocupada | X:0; clicar 0 | o POST acontece e responde 409; célula 0 continua X; status "Vez do jogador O"; erro "Esta célula já está ocupada." | CA-04 |
| U-04-xx | 8 vitórias | sequências S-L1 … S-D2 | status do vencedor; exatamente as células da combinação com `data-winning="true"`; todas as células com `aria-disabled="true"` | CA-08 a CA-12 |
| U-05 | Vitória na 9ª jogada | S-9A | "Jogador X venceu!" (não "Empate!"); 2, 5, 8 destacadas | CA-13 |
| U-06 | Vitória dupla | S-DUP | 0, 2, 4, 6, 8 destacadas | CA-14 |
| U-07 | Empate | S-EMP | "Empate!"; nenhum destaque; células com `aria-disabled="true"` | CA-15 |
| U-08 | Clique após vitória | S-L1; clicar 5 | POST responde 409; célula 5 vazia; status mantido; erro de partida encerrada | CA-16 |
| U-09 | Clique após empate | S-EMP; clicar 4 | POST 409; erro de partida encerrada (não de célula ocupada) | CA-17 |
| U-10 | Nova partida após o fim | S-L1; clique extra (erro visível); "Nova partida" | tabuleiro vazio, "Vez do jogador X", sem destaque, sem `aria-disabled`, erro oculto | CA-19 |
| U-11 | Nova partida no meio | X:0, O:4; "Nova partida" | igual ao U-10 | CA-20 |
| U-12 | Mensagem some | provocar erro; jogada válida; provocar erro; "Nova partida" | o erro some nas duas situações | CA-21 |
| U-13 | Falha de comunicação e recuperação | X:0; abortar `/api/**` no navegador; clicar 4; liberar a rede; "Tentar novamente" | mensagem de falha e botão visíveis, tabuleiro sem mudança; depois da recuperação, mensagem e botão ocultos e a tela igual ao backend (célula 4 vazia, vez de O) | CA-22 |
| U-14 | Recarregar | X:0, O:4; recarregar | mesma tela | CA-23 |
| U-15 | Duas abas | jogar na aba 1; recarregar a aba 2 | aba 2 com X em 0 e vez de O | CA-24 |
| U-16 | Estado montado pelo backend | API: 0, 3, 1, 4; abrir a página; clicar 2 | a página mostra o estado do backend; depois, vitória decidida pelo servidor | RN-14 |
| U-17 | Cliques rápidos | atrasar as respostas de `POST /api/game/moves` em 400 ms (a resposta é a do servidor real, só atrasada); clicar 0 e logo depois 1 | exatamente 1 POST enviado; X só na célula 0; vez de O; nenhum erro | CA-31 |
| U-18 | Carregamento | atrasar a resposta de `GET /api/game` em 1 s; abrir a página; clicar 0 durante a espera | "Carregando partida…", `aria-busy="true"` e `data-state="loading"`; o clique não gera POST; quando a resposta chega, tabuleiro vazio e "Vez do jogador X" | CA-28 |
| U-19 | Falha no carregamento inicial | abortar `GET /api/game`; abrir a página; liberar; "Tentar novamente" | mensagem de falha e botão; células com `aria-disabled="true"`; depois, estado do backend | CA-32 |
| U-20 | Teclado | foco na célula 0; Enter; seta direita; Espaço | X em 0; foco na célula 1; O em 1 | CA-29 |
| U-21 | Tela pequena | viewport 360 × 640; abrir; jogar em 8 | sem rolagem horizontal; tabuleiro dentro da largura; células ≥ 44 × 44 px; a jogada funciona | CA-30 |
| U-22 | Acessibilidade básica | abrir; jogar S-L1 | `lang="pt-BR"`; um `h1`; região `main`; grupo "Tabuleiro"; botões "Linha 1, coluna 1: vazia" e, depois, "Linha 1, coluna 1: X, vencedora"; status `role="status"`; erro `role="alert"`; botão "Nova partida" | CA-29 |

Interceptações de rede: só U-13, U-17, U-18 e U-19 usam `page.route`, e apenas para **abortar** ou **atrasar** requisições reais (`route.continue()` depois da espera). Nenhum teste fabrica resposta do backend.

## 9. Grupo M — Motor (EngineCheck) e testes de sabotagem

### 9.1 Estratégia de testes unitários do motor

O motor (`uGameEngine`) é testado **sozinho**, sem Indy, sem HTTP, sem JSON e sem navegador, pelo programa console `EngineCheck.exe`.

| Decisão | Justificativa |
|---|---|
| Mini-framework próprio (`server/tests/uMiniTest.pas`, ~100 linhas) em vez de DUnitX | Nenhuma dependência nova; o relatório é um texto simples que vai para o log; código de saída 0/1 para scripts. |
| Cada caso roda isolado, com um motor novo, dentro de `try..except` | Uma exceção vira falha do caso, não derruba a suíte. |
| Asserções "suaves": um caso continua depois de uma falha e lista todas | Mostra o problema inteiro numa execução só. |
| Comparação do **estado inteiro** (`TGameSnapshot`) e não de campos soltos | Pega efeitos colaterais inesperados, por exemplo uma rejeição que muda o turno. |
| Tabuleiro escrito como texto de 9 caracteres (`'XXXOO....'`) | Casos legíveis e mensagens de falha fáceis de entender. |
| Toda rejeição é verificada com "estado antes = estado depois" | Garante que jogadas inválidas não corrompem a partida (RN-12). |
| Teste **exaustivo** com um **oráculo independente** (M-12) | Percorre todas as partidas possíveis e compara o motor com uma segunda implementação das regras, escrita de outra forma (laços por linha/coluna/diagonal, sem a tabela `WIN_LINES`). Os totais conhecidos do jogo da velha servem de conferência extra. |
| Sabotagens automáticas (seção 9.2) já nesta entrega | Prova que os testes do motor detectam defeitos reais. |

#### Contrato do motor que os testes verificam

- `Create` e `Reset` produzem o estado inicial: 9 células vazias, `gsInProgress`, jogador da vez X, sem vencedor, sem células vencedoras.
- `Play(Posição)` devolve exatamente um resultado, verificando nesta ordem (RN-15, sem a parte de JSON):
  1. posição fora de 0..8 → `mrInvalidPosition`;
  2. partida encerrada → `mrGameOver`;
  3. célula ocupada → `mrCellOccupied`;
  4. caso contrário → `mrAccepted`.
- Só `mrAccepted` altera o estado.
- Após uma jogada aceita:
  - vitória → `gsWin`, vencedor definido, células vencedoras em ordem crescente (3 ou 5), jogador da vez vazio;
  - senão, tabuleiro cheio → `gsDraw`, jogador da vez vazio;
  - senão, troca o jogador.
- `GetSnapshot` devolve uma **cópia independente**: alterar o resultado não altera o motor.

#### Casos

| ID | Caso | Espelha |
|---|---|---|
| M-01 | Estado inicial após `Create` e após `Reset` | R-01 |
| M-02 | Alternância e símbolo gravado nas 8 primeiras jogadas de S-EMP | R-02 a R-04 |
| M-03 | Célula ocupada (do adversário e a própria) → `mrCellOccupied`, estado inalterado, partida segue | R-06 a R-08 |
| M-04 | Posições −1, 9, 10, 100, `MaxInt` e `Low(Integer)` → `mrInvalidPosition`, estado inalterado (no início e no meio da partida) | A-04 (parte numérica) |
| M-05-xx | As 8 vitórias, um caso por combinação: L1, L2, L3, C1, C2, C3, D1, D2 | R-09 a R-16 |
| M-06 | S-9A (vitória na 9ª jogada) e S-DUP (duas combinações, 5 células) | R-17, R-18 |
| M-07 | S-EMP (empate) | R-19 |
| M-08 | Após vitória: todas as células (vazias e ocupadas) → `mrGameOver`; após empate: todas → `mrGameOver`; estado inalterado | R-20, R-21 |
| M-09 | Posição 9 e −1 após vitória → `mrInvalidPosition` (ordem RN-15) | R-22 |
| M-10 | `Reset` após vitória dupla, empate, meio de partida e jogada rejeitada → estado igual ao inicial, campo a campo; células antes ocupadas voltam a aceitar jogada e X recomeça | R-23 a R-26 |
| M-11 | `GetSnapshot` devolve cópia: alterar `Board` e `WinningCells` do resultado não muda o motor | — (proteção interna) |
| M-12 | Exaustivo: todas as 549.946 posições de todas as partidas possíveis comparadas com o oráculo; em cada posição, todas as jogadas inválidas são rejeitadas sem alterar o estado; totais esperados: 255.168 partidas, 131.184 vitórias de X, 77.904 de O, 46.080 empates, 12.672 vitórias com 5 células | RN-01 a RN-12, RN-15 |

No M-12, quem decide o caminho da exploração e conta os totais é o **oráculo**, não o motor. Os totais (conferidos por um script independente durante o planejamento) validam o próprio oráculo; o motor é validado pela comparação, posição a posição, entre o estado do motor e o estado do oráculo, e pela recusa das jogadas inválidas em cada posição. Isso ficou evidente na fase vermelha: com o motor vazio, os totais bateram, mas a comparação falhou em todas as posições.

Validação de JSON (texto, booleano, corpo malformado) não é responsabilidade do motor; fica nos grupos A e R.

### 9.2 Testes de sabotagem

As sabotagens do motor (SB-01, SB-02, SB-03 e SB-05) rodam automaticamente desde a Entrega 2 (`scripts\validate-step2.ps1`). A SB-04 roda desde a Entrega 3 (`scripts\validate-step3.ps1`): uma cópia do servidor sem a trava e com `Sleep(50)` entre a verificação e a gravação da célula é compilada, iniciada na porta 8766 e submetida ao R-27. A SB-06 roda desde a Entrega 5 (`scripts\validate-step5.ps1`): uma cópia de `web/` em que o `app.js` desenha "X" na célula clicada antes de ouvir o servidor é servida pelo executável real (`--www`) na porta 8766; o U-08 e a verificação cruzada precisam falhar.

Cada sabotagem é aplicada numa cópia temporária, compilada, testada e **descartada**; o código original nunca é alterado. O resultado esperado é que os testes listados **falhem**; se algum passar, ele não está testando o que diz testar e precisa ser corrigido.

| ID | Sabotagem no código | Testes que precisam falhar |
|---|---|---|
| SB-01 | Trocar (2,4,6) por (0,1,2) em `WIN_LINES` | M-05-D2, M-06, M-12, R-16, R-18, U-04-D2, U-06 |
| SB-02 | Desligar a verificação de célula ocupada | M-03, M-12, R-06, R-07, U-03 |
| SB-03 | Inverter a ordem "partida encerrada" × "célula ocupada" | M-08, M-12, R-21, U-09 |
| SB-04 | Remover o `TCriticalSection` e inserir um `Sleep(50)` entre ler e gravar a célula | R-27 |
| SB-05 | Não trocar o turno após a jogada | M-02, M-12, R-02 a R-04, U-02 |
| SB-06 | No `app.js`, ignorar a resposta do POST e desenhar o símbolo localmente | U-03, verificação cruzada dos cenários U |

### 9.3 Serviço e JSON sem HTTP (EngineCheck)

Desde a Entrega 3, o `EngineCheck` também testa `uGameService` e `uGameJson` diretamente, sem Indy.

| ID | Caso | Requisito |
|---|---|---|
| SV-01 | `GetState`, `Play` e `Reset` devolvem cópias: alterar o `WinningCells` ou o `Board` devolvido não muda o próximo `GetState` | DT-18 |
| SV-02 | `Play` devolve o resultado e o estado da mesma jogada (aceita → célula preenchida no estado devolvido; recusada → estado igual ao anterior) | RN-12, plano 4.1 |
| SV-03 | 8 threads fazem 2.000 operações cada (jogadas em posições aleatórias, consultas e reinícios ocasionais) no mesmo serviço; todo estado devolvido é coerente (nº de X − nº de O é 0 ou 1; vez, vencedor e células compatíveis com o status) e nenhuma exceção ocorre | RNF-06, CA-25 |
| J-01 | `SnapshotToJson` do estado inicial, de uma vitória dupla e de um empate gera exatamente o JSON do contrato (campos, ordem, `null`, `[]`) | plano 3.2 |
| J-02 | `ParseMoveBody` aceita `{"posicao":0}` a `{"posicao":8}`, `{"posicao":4,"simbolo":"O"}`, espaços em volta, `4.0` (vale 4) e `1e0` (vale 1) | plano 3.3 |
| J-03 | `ParseMoveBody` classifica como `mbInvalidPosition`: `4.5`, `0.5`, `4e-1`, `"4"`, `null`, `true`, `99999999999`, `{}`, `{"Posicao":4}` e `[4]` | RN-04 |
| J-04 | `ParseMoveBody` classifica como `mbInvalidBody`: vazio, `abc`, `{"posicao":`, `[4]`, `4`, `"x"` e bytes UTF-8 inválidos | CE-04 |
| J-05 | `ErrorToJson` gera `{"erro":{"codigo":...,"mensagem":...}}` com acentos preservados após decodificar o JSON | plano 3.4, RNF-08 |

## 10. Dependências e incompatibilidades identificadas

| ID | Componente | Ponto | Tratamento |
|---|---|---|---|
| I-01 | Indy (Berlin) | `TIdHTTPServer` envia GET, POST e HEAD para `OnCommandGet`, mas **PUT, DELETE, OPTIONS e outros vão para `OnCommandOther`**. Sem tratar esse evento, A-09 não teria 405. | Atribuir os dois eventos ao mesmo roteador (registrado no plano v0.2, 4.2). |
| I-02 | Indy | Por padrão, o servidor escuta em todas as interfaces (0.0.0.0), o que contraria a RNF-04 e pode abrir o aviso do Firewall do Windows. | Criar um `Binding` explícito com `IP = '127.0.0.1'`. |
| I-03 | Indy | Com `Content-Length: 0`, `ARequestInfo.PostStream` pode ser `nil`. | Tratar `nil` como corpo vazio → `CORPO_INVALIDO` (A-05). |
| I-04 | Indy | `ContentText` sem `CharSet` explícito pode corromper acentos. | Bytes UTF-8 em `ContentStream` (DT-08); A-07 detecta a falha. |
| I-05 | Indy | O `ContentStream` atribuído é liberado pelo Indy (`FreeContentStream`). | Não liberar manualmente. |
| I-06 | Indy | Comportamento de `HEAD` (enviar cabeçalhos sem corpo) depende da versão do Indy distribuída com o Berlin. | A confirmar na Entrega 1 (`HEAD /health`); A-11 verifica. |
| I-07 | Node.js 17+ | `localhost` pode ser resolvido primeiro para IPv6 (`::1`), e o servidor só escuta em IPv4. O `webServer` esperaria para sempre. | Usar sempre `127.0.0.1` em `baseURL`, `webServer.url` e no README. |
| I-08 | `System.JSON` (Berlin) | `posicao` só é aceita se o valor for `TJSONNumber` e o texto passar em `TryStrToInt`; `4.5`, `"4"`, `true` e `null` chegam como outras classes ou falham na conversão. | A-04 cobre todos. Um caso não exigido pela spec, e portanto não testado: lixo depois de um JSON válido (`{"posicao":1}xyz`), cujo tratamento pelo parser do Berlin precisa ser observado. |
| I-09 | Playwright | A versão atual exige **Node.js 22, 24 ou 26** e **Windows 11 ou Windows Server 2019+**. | Confirmar a versão do Windows e do Node instalado no sistema (o desktop do Claude traz um Node próprio, que não conta). Se for Windows 10, fixar uma versão mais antiga do Playwright na Entrega 4. |
| I-10 | Playwright | `npx playwright install chromium` baixa o navegador da internet; proxies corporativos podem bloquear. | Fazer o download uma vez na Entrega 4. |
| I-11 | Playwright no Windows | Ao fim da suíte, o processo do servidor é finalizado à força (sem passar pelo Ctrl+C). Para um estado só em memória, isso é aceitável e libera a porta. | O encerramento limpo por Ctrl+C (RNF-12) é verificado manualmente na Entrega 1. |
| I-12 | TypeScript | O Playwright transpila os `.ts` sozinho; o pacote `typescript` serve apenas para `tsc --noEmit` (checagem de tipos). | Script `npm run typecheck`; versões fixas, sem `^`. |
| I-13 | Caminho do projeto | `C:\Users\Ruan\Documents\jogo da velha` tem **espaços**. | Aspas em todos os comandos de `build.cmd`; `webServer.command` com caminho relativo. |
| I-14 | Delphi Berlin | Edição e local de instalação ainda não confirmados (o `rsvars.bat` fica em `...\Studio\18.0\bin`). | Registrado pelo script de validação da Entrega 1. |
| I-15 | Ambiente desta sessão | Não há terminal Windows disponível para o agente; ele lê e grava arquivos na pasta do projeto. | Cada entrega traz um script de validação que grava a saída real em `logs\`; o script é executado no Windows e o agente lê o log (DT-16). |

## 11. Critérios de aprovação

### 11.1 De um cenário

Um cenário está aprovado quando seu teste foi **executado** contra o servidor real e todas as asserções passaram na primeira tentativa (sem retries). "Pulado", "instável" ou "não executado" não contam como aprovado.

### 11.2 Da suíte (fim da Etapa 5)

1. `EngineCheck.exe` termina com código 0 e lista todos os casos M como OK.
2. `npx playwright test` com 0 falhas, 0 pulados e 0 instáveis, rodado **3 vezes seguidas** a partir de um servidor iniciado do zero.
3. `npm run typecheck` sem erros.
4. Todos os testes de sabotagem SB-01 a SB-06 produzem as falhas esperadas, e o código é revertido depois.
5. A matriz da seção 12 tem todos os CA cobertos, com o resultado real de cada execução anotado.
6. As saídas reais (console do EngineCheck e relatório do Playwright) estão guardadas como evidência; nenhum resultado é declarado sem elas.

### 11.3 O que não é critério de aprovação

- O código compilar.
- Uma verificação manual sem registro.
- Um teste que passa mas nunca foi visto falhar (por isso existe a seção 9.2).

## 12. Matriz de rastreabilidade

| CA | Descrição curta | Regras (R) / Motor (M) | Endpoints (A) | Interface (U) |
|---|---|---|---|---|
| CA-01 | Estado inicial | R-01, M-01 | A-01 | U-01 |
| CA-02 | Primeira jogada | R-02, M-02 | A-03 | U-02 |
| CA-03 | Alternância | R-03, R-04, M-02 | — | U-02 |
| CA-04 | Célula ocupada | R-06, R-07, R-08, M-03 | — | U-03 |
| CA-05 | Posição inválida | M-04 | A-04 | — |
| CA-06 | Corpo malformado | — | A-05 | — |
| CA-07 | Símbolo imposto | R-05 | — | — |
| CA-08 | Linha 0-1-2 | R-09, M-05 | — | U-04-L1 |
| CA-09 | Coluna 1-4-7 | R-13, M-05 | — | U-04-C2 |
| CA-10 | Diagonal 0-4-8 | R-15, M-05 | — | U-04-D1 |
| CA-11 | Diagonal 2-4-6 | R-16, M-05 | — | U-04-D2 |
| CA-12 | Demais combinações | R-10, R-11, R-12, R-14, M-05 | — | U-04-L2, L3, C1, C3 |
| CA-13 | Vitória na 9ª jogada | R-17, M-06 | — | U-05 |
| CA-14 | Duas combinações | R-18, M-06 | — | U-06 |
| CA-15 | Empate | R-19, M-07 | — | U-07 |
| CA-16 | Bloqueio após vitória (UI) | R-20, M-08 | — | U-08 |
| CA-17 | Bloqueio após empate (UI) | R-21, M-08 | — | U-09 |
| CA-18 | Bloqueio no backend | R-20, R-21, R-22, M-08, M-09 | — | — |
| CA-19 | Reinício após fim | R-23, R-24, R-26, M-10 | A-02 | U-10 |
| CA-20 | Reinício no meio | R-25, M-10 | — | U-11 |
| CA-21 | Mensagem some | — | — | U-12 |
| CA-22 | Servidor inacessível e recuperação | — | — | U-13 |
| CA-23 | Recarregar | — | — | U-14 |
| CA-24 | Duas abas | — | — | U-15 |
| CA-25 | Concorrência | R-27, R-28, SV-03 | — | — |
| CA-26 | Rotas e métodos | — | A-08, A-09, A-10 | — |
| CA-27 | Verificação de saúde | — | A-12 | — |
| CA-28 | Carregamento | — | — | U-18 |
| CA-29 | Teclado e acessibilidade | — | — | U-20, U-22 |
| CA-30 | Tela pequena | — | — | U-21 |
| CA-31 | Cliques rápidos | — | — | U-17 |
| CA-32 | Falha no carregamento inicial | — | — | U-19 |
| — | UTF-8 (RNF-08) | — | A-01, A-07 | — |
| — | Backend como autoridade (RN-14) | grupo R inteiro | — | U-03, U-08, U-16, verificação cruzada, SB-06 |

Todos os 27 critérios têm ao menos um cenário. Totais planejados: 19 casos de motor (M-05 tem 8), 27 cenários R, 12 cenários A e 16 cenários U, sendo que o U-04 se desdobra em 8 testes e alguns cenários A se desdobram por entrada.

## 13. Registro de alterações

| Versão | Data | Alteração |
|---|---|---|
| 0.1 | 2026-10-15 | Criação do plano de testes. |
| 0.2 | 2026-10-15 | Novo cenário A-12 (`/health`, CA-27); `webServer` usa `/health`; I-15 atualizado para os scripts de validação. |
| 0.3 | 2026-10-15 | Entrega 2: seção 9.1 reescrita com a estratégia de testes unitários do motor e o contrato verificado; M-01 a M-10 detalhados; novos M-11 (cópia independente do estado) e M-12 (teste exaustivo com oráculo); sabotagens do motor automatizadas desde a Entrega 2 (9.2). |
| 0.4 | 2026-10-15 | Esclarecido o papel dos totais do M-12 (validam o oráculo; o motor é validado pela comparação posição a posição), após a fase vermelha da Entrega 2. |
| 0.5 | 2026-10-15 | Entrega 3: execução dos grupos A e R por HTTP real antes do Playwright (seção 2); A-04 e A-05 ampliados (fração, expoente, inteiro grande, sem corpo, texto, UTF-8 inválido); novo R-28 (rajada simultânea); nova seção 9.3 (SV-01 a SV-03 e J-01 a J-05); SB-04 automatizada na Entrega 3. |
| 0.6 | 2026-10-15 | `4.0` e `1e0` passam a ser aceitos (A-06, J-02) e saem das listas de inválidos (A-04, J-03), que ganham `0.5` e `4e-1`; ver plano v0.6. |
| 0.7 | 2026-10-15 | Entrega 4: tabela de cobertura por camada (EngineCheck × Playwright), com a decisão de não repetir o teste exaustivo por HTTP; infraestrutura (seção 4) atualizada para a fixture `game` e o `webServer` real. |
| 0.8 | 2026-10-15 | Entrega 5: grupo U reescrito (fixture com controle de console, requisições e verificação cruzada; U-01 a U-16 atualizados; novos U-17 a U-22); A-10 detalhado (Content-Type, Cache-Control, HEAD, 404 JSON, 405); SB-06 automatizada; matriz com CA-28 a CA-32. |
| 0.9 | 2026-10-15 | Entrega 5, após a primeira execução real: cliques em células `aria-disabled` passam a usar `force: true` (o Playwright trata `aria-disabled` como desabilitado). |
