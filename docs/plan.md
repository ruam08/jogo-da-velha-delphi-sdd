# Plano técnico — Jogo da Velha (Delphi Berlin + Web)

| Campo | Valor |
|---|---|
| Versão | 0.8 |
| Data | 2026-10-15 |
| Etapa SDD | 2 — Plano técnico |
| Base | `docs/spec.md` v0.4 |
| Status | Aguardando aprovação. Nenhum código foi implementado. |

---

## 1. Visão geral da arquitetura

```
┌──────────────── Navegador (Chromium) ────────────────┐
│  index.html + style.css + app.js                      │
│  - exibe o estado recebido                            │
│  - envia cliques e "Nova partida" via fetch()         │
└───────────────┬───────────────────────────────────────┘
                │ HTTP, mesma origem (http://127.0.0.1:8765)
┌───────────────▼─────── TicTacToeServer.exe (console) ─┐
│  uHttpApp      TIdHTTPServer: roteamento, arquivos    │
│                estáticos, respostas HTTP              │
│  uGameJson     conversão estado ⇄ JSON, leitura do    │
│                corpo da jogada                        │
│  uGameService  instância única da partida +           │
│                TCriticalSection                       │
│  uGameEngine   regras puras (sem Indy, sem JSON)      │
└───────────────────────────────────────────────────────┘
                ▲
┌───────────────┴── Playwright + TypeScript ───────────┐
│  inicia o .exe (webServer), testa pela UI e pela API  │
└───────────────────────────────────────────────────────┘
```

Cada camada só conhece a de baixo. O motor (`uGameEngine`) não sabe que existe HTTP, o que permite verificá-lo sozinho com um programa console (RNF-07).

## 2. Decisões técnicas

| # | Decisão | Justificativa |
|---|---|---|
| DT-01 | Aplicação **console** Win32 (`{$APPTYPE CONSOLE}`). | Mais simples de iniciar e encerrar pelo Playwright; o log aparece no terminal. (D-05) |
| DT-02 | **`TIdHTTPServer`** do Indy 10 que acompanha o Berlin, criado em código (sem formulário nem data module). | Exigência do projeto; criar em código evita depender de VCL e deixa o projeto inteiro em `.pas` legível. |
| DT-03 | O mesmo servidor entrega **API e arquivos da interface** (mesma origem). | Sem CORS e sem um segundo servidor. (D-06, RNF-05) |
| DT-04 | Arquivos estáticos servidos por **lista fixa** (`/`, `/index.html`, `/style.css`, `/app.js`), cada um com seu `Content-Type`. O arquivo é lido do disco a cada requisição (`TFile.ReadAllBytes`) a partir da pasta `--www`. | Elimina o risco de *path traversal* (`/../`) sem código de saneamento de caminho; editar a interface não exige recompilar o servidor. |
| DT-05 | JSON com a unit **`System.JSON`** da RTL. | Existe no Berlin; dispensa bibliotecas de terceiros. |
| DT-06 | Estado em memória, numa única instância de `TGameService`, protegida por **`TCriticalSection`**. | O Indy atende cada conexão em uma thread; a seção crítica garante o CA-25. (RNF-06) |
| DT-07 | Escuta só em **`127.0.0.1`**, porta padrão **8765**, alterável por `--port`. | Requisito local (RNF-04); 8765 evita conflito comum com 8080. (D-07) |
| DT-08 | Respostas geradas como **bytes UTF-8 em `ContentStream`**, com `CharSet = 'utf-8'`. | Evita a armadilha do Indy de codificar `ContentText` em ASCII/ISO-8859-1 e corromper acentos. (RNF-08) |
| DT-09 | A interface **sempre envia o clique** ao backend, mesmo com a partida encerrada ou a célula ocupada. | O backend é a única autoridade (RN-14) e isso torna os CA-04, CA-16 e CA-17 testáveis pela UI. |
| DT-10 | Interface em **HTML/CSS/JS puros**, sem build. | Nada para compilar no front-end; o Delphi serve os arquivos como estão. |
| DT-11 | Verificação do motor com um **programa console próprio** (`EngineCheck.dpr`) e um mini-framework de ~100 linhas (`uMiniTest`), sem DUnitX. | Dá feedback rápido sobre as regras sem adicionar dependências. Estratégia completa no `docs/test-plan.md`, 9.1. (D-11) |
| DT-20 | Playwright **1.64.1** (`latest` em 15/10/2026, exige Node ≥ 20), TypeScript **5.9.3** e `@types/node` **24.10.1**, fixados sem `^` e instalados só em `tests\node_modules`. | O Node 24.11.1 já instalado atende; nada é instalado globalmente. A documentação do Playwright lista Windows 11/Server 2019+; o Windows 10 não aparece, mas também não há remoção registrada nas notas de versão. Na Entrega 4 só o executor (Node puro) é usado, sem navegador, então o risco não se aplica; ele volta na Entrega 5 (Chromium) e será verificado lá. TypeScript 5.9.3 em vez do 7.0 (novo compilador nativo) por ser só para checagem de tipos e a linha mais testada. |
| DT-21 | Rotas desconhecidas, dentro ou fora de `/api`, continuam com 404 **JSON** `ROTA_NAO_ENCONTRADA` também depois dos estáticos (em vez de 404 em texto simples, como previa a v0.2). | Um único formato de erro; nenhum teste ou contrato existente muda. |
| DT-22 | A interface envia **uma requisição por vez** e ignora cliques enquanto há uma pendente (CI-13), com tempo-limite de 8 s. | Elimina respostas fora de ordem sem fila nem números de sequência; o tempo-limite impede que a interface fique travada. |
| DT-23 | Chromium instalado com `npx playwright install chromium`, no cache padrão do usuário (`%LOCALAPPDATA%\ms-playwright`). Nenhuma ferramenta global é alterada. | É o local padrão do Playwright; manter o navegador dentro de `node_modules` exigiria a mesma variável de ambiente em todos os comandos. |
| DT-19 | Na Entrega 3, os cenários A e R são executados por **requisições HTTP reais** feitas pelo script `scripts\validate-step3.ps1` (`System.Net.Http.HttpClient` do .NET), contra o servidor real. Na Entrega 4 os mesmos cenários passam para o Playwright. | Valida a API já nesta entrega sem antecipar a configuração do Playwright; os IDs dos cenários são os mesmos. |
| DT-18 | `GetSnapshot` devolve uma **cópia** de `WinningCells` (`Copy`). | Arrays dinâmicos em records são compartilhados por referência no Delphi; sem a cópia, quem recebe o estado poderia alterar o motor. |
| DT-12 | Playwright em **série (1 worker)**, **sem retries**, partida reiniciada antes de cada teste via `POST /api/game/reset`. | O estado é global (RN-13); retries esconderiam testes instáveis. (RNF-10) |
| DT-13 | Encerramento por **Ctrl+C** com `SetConsoleCtrlHandler`, e não por `ReadLn`. | Quando o Playwright inicia o processo, a entrada padrão pode estar fechada; um `ReadLn` retornaria na hora e derrubaria o servidor. |
| DT-14 | API responde com **`Cache-Control: no-store`**. | Garante que recarregar a página traga o estado atual (CA-23, CA-24). |
| DT-15 | Compilação por linha de comando com **`dcc32`** (via `scripts\build.cmd`), sem `.dproj` escrito à mão. A IDE gera o `.dproj` ao abrir o `.dpr`. | Um `.dproj` montado manualmente pode não abrir no Berlin; o `dcc32` funciona com o `.dpr` e as opções explícitas. |
| DT-16 | Cada entrega tem um **script de validação** (`scripts\validate-*.cmd`) que compila, inicia o servidor, faz requisições reais e grava tudo em `logs\` (fora do Git). | Deixa a evidência de cada validação registrada e repetível, sem depender de relato. |
| DT-17 | Fontes `.pas`/`.dpr` gravados em **UTF-8 com BOM** e fim de linha CRLF; o console é configurado para UTF-8. | Sem BOM, o Berlin lê o arquivo como ANSI e corrompe literais acentuados. |

## 3. Contrato HTTP

Base: `http://127.0.0.1:8765`. Todas as respostas da API são `application/json; charset=utf-8`.

### 3.1 Rotas

| Método | Rota | Uso | Sucesso |
|---|---|---|---|
| GET | `/health` | Verificação de saúde (RNF-14) | 200 + `{"status":"ok"}` |
| GET | `/api/game` | Obter o estado atual | 200 + estado |
| POST | `/api/game/moves` | Fazer uma jogada | 200 + estado novo |
| POST | `/api/game/reset` | Nova partida | 200 + estado inicial |
| GET | `/`, `/index.html` | Página | 200 `text/html; charset=utf-8` |
| GET | `/style.css` | Estilos | 200 `text/css; charset=utf-8` |
| GET | `/app.js` | Script | 200 `text/javascript; charset=utf-8` |

Os estáticos são enviados com `Cache-Control: no-cache` (o navegador revalida e sempre usa a versão atual).

`HEAD` é aceito onde `GET` é aceito (o Playwright pode usá-lo ao checar se o servidor subiu). Qualquer outro método em rota existente recebe 405 com o cabeçalho `Allow`:

| Rota | `Allow` no 405 |
|---|---|
| `/health`, `/api/game` | `GET, HEAD` |
| `/api/game/moves`, `/api/game/reset` | `POST` |

Qualquer rota fora da tabela (dentro ou fora de `/api`, inclusive arquivo estático inexistente) recebe 404 JSON `ROTA_NAO_ENCONTRADA` (DT-21). Os estáticos aceitam `GET` e `HEAD`; outro método recebe 405 com `Allow: GET, HEAD`.

Toda resposta de sucesso da API traz o **estado completo** (3.2). Respostas de erro trazem **só o erro** (3.4); o estado não muda (RN-12) e o cliente pode consultá-lo com `GET /api/game`.

### 3.2 Objeto de estado

```json
{
  "tabuleiro": ["X", "", "O", "", "X", "", "", "", ""],
  "status": "EM_ANDAMENTO",
  "jogadorDaVez": "O",
  "vencedor": null,
  "celulasVencedoras": []
}
```

| Campo | Tipo | Regras |
|---|---|---|
| `tabuleiro` | array de 9 strings | `"X"`, `"O"` ou `""` (vazia), na ordem 0–8 |
| `status` | string | `EM_ANDAMENTO`, `VITORIA` ou `EMPATE` |
| `jogadorDaVez` | string ou `null` | `"X"`/`"O"` em andamento; `null` encerrada |
| `vencedor` | string ou `null` | `"X"`/`"O"` com `VITORIA`; `null` nos demais |
| `celulasVencedoras` | array de inteiros | 3 ou 5 índices crescentes com `VITORIA`; `[]` nos demais |

Exemplo de vitória dupla (CA-14): `"status": "VITORIA", "jogadorDaVez": null, "vencedor": "X", "celulasVencedoras": [0, 2, 4, 6, 8]`.

### 3.3 Requisição de jogada

```http
POST /api/game/moves
Content-Type: application/json

{ "posicao": 4 }
```

- O corpo é lido como bytes UTF-8 e precisa ser um **objeto** JSON; caso contrário, `CORPO_INVALIDO`. Isso inclui corpo ausente, vazio, JSON malformado, bytes que não são UTF-8 válido e JSON que não é objeto (`[4]`, `4`, `"x"`).
- `posicao` precisa ser um número JSON de **valor inteiro** que caiba em `Integer`, e estar entre 0 e 8 (RN-04). `4`, `4.0` e `4e0` valem 4; `4.5`, `0.5` e `99999999999` são inválidos. (O parser JSON do Berlin normaliza o texto do número, então a forma escrita não é distinguível; ver registro v0.6.) Texto, `null`, booleano ou campo ausente → `POSICAO_INVALIDA`. O nome do campo diferencia maiúsculas (`Posicao` é ignorado, logo o campo está ausente).
- Outros campos são ignorados (RN-07).
- O cabeçalho `Content-Type` não é exigido: o corpo é sempre interpretado como JSON (test-plan A-06).
- A validação segue a RN-15.
- `POST /api/game/reset` não precisa de corpo; um corpo enviado é ignorado.

### 3.4 Respostas de erro

Formato único:

```json
{ "erro": { "codigo": "CELULA_OCUPADA", "mensagem": "Esta célula já está ocupada." } }
```

| HTTP | `codigo` | Quando | `mensagem` |
|---|---|---|---|
| 400 | `CORPO_INVALIDO` | Corpo ausente, vazio ou que não é um objeto JSON | O corpo da requisição deve ser um objeto JSON válido. |
| 400 | `POSICAO_INVALIDA` | `posicao` ausente, não inteira ou fora de 0..8 | A posição deve ser um número inteiro de 0 a 8. |
| 409 | `PARTIDA_ENCERRADA` | Jogada com status `VITORIA` ou `EMPATE` | A partida já terminou. Clique em "Nova partida" para jogar novamente. |
| 409 | `CELULA_OCUPADA` | Célula já preenchida | Esta célula já está ocupada. |
| 404 | `ROTA_NAO_ENCONTRADA` | Rota `/api/...` inexistente | Rota não encontrada. |
| 405 | `METODO_NAO_PERMITIDO` | Método não suportado em rota existente | Método não permitido para esta rota. |
| 500 | `ERRO_INTERNO` | Exceção inesperada (registrada no console) | Erro interno no servidor. |

`/health` e os estáticos seguem as mesmas regras de erro da API: 404 e 405 em JSON (DT-21).

## 4. Backend Delphi

### 4.1 Units

| Unit | Responsabilidade | Depende de |
|---|---|---|
| `uGameEngine.pas` | Tipos do domínio e classe `TGameEngine`: `Reset`, `Play(Position): TMoveResult`, `GetSnapshot` | Nenhuma unit |
| `uGameService.pas` | `TGameService`: instância única do motor + `TCriticalSection`. `GetState`, `Play` e `Reset` executam inteiros dentro da seção crítica; `Play` devolve resultado **e** estado na mesma seção crítica, para que a resposta descreva exatamente a jogada feita. Todo estado devolvido é cópia (`GetSnapshot`). | `uGameEngine`, `System.SyncObjs` |
| `uGameJson.pas` | Estado → JSON; erro → JSON; corpo (bytes) → posição (`mbOk`, `mbInvalidBody`, `mbInvalidPosition`). Não conhece Indy. | `uGameEngine`, `System.JSON`, `System.SysUtils` |
| `uConsoleLog.pas` | Escrita de log no console, em UTF-8 e protegida contra threads simultâneas | `System.SyncObjs` |
| `uHttpApp.pas` | `TGameHttpServer`: cria o `TIdHTTPServer`, roteia em `OnCommandGet`, serve estáticos, escreve respostas UTF-8, captura exceções | Indy, `uGameService`, `uGameJson`, `System.IOUtils` |
| `TicTacToeServer.dpr` | Lê `--port` e `--www`, sobe o servidor, espera Ctrl+C, desliga | `uHttpApp`, `Winapi.Windows`, `System.SyncObjs` |
| `EngineCheck.dpr` + `tests/uMiniTest.pas` + `tests/uEngineTests.pas` + `tests/uServiceTests.pas` + `tests/uJsonTests.pas` | Casos M (motor), SV (serviço, incluindo várias threads) e J (JSON) do test-plan, sem HTTP; código de saída 0 ou 1 | `uGameEngine`, `uGameService`, `uGameJson` |

Tipos principais do motor:

```pascal
type
  TCell = (ceEmpty, ceX, ceO);
  TGameStatus = (gsInProgress, gsWin, gsDraw);
  TMoveResult = (mrAccepted, mrInvalidPosition, mrGameOver, mrCellOccupied);

  TGameSnapshot = record
    Board: array[0..8] of TCell;
    Status: TGameStatus;
    CurrentPlayer: TCell;     // ceEmpty quando encerrada
    Winner: TCell;            // ceEmpty sem vitória
    WinningCells: TArray<Integer>;
  end;

const
  WIN_LINES: array[0..7, 0..2] of Integer = (
    (0,1,2), (3,4,5), (6,7,8), (0,3,6), (1,4,7), (2,5,8), (0,4,8), (2,4,6));
```

O motor também valida o intervalo 0..8 (defesa em profundidade). A ordem dentro de `Play` segue a RN-15: intervalo → status → célula.

### 4.2 Fluxo de uma requisição

1. `OnCommandGet` (recebe GET, POST e HEAD) e `OnCommandOther` (recebe PUT, DELETE, OPTIONS etc.) apontam para o mesmo roteador, que lê `ARequestInfo.Command` e `ARequestInfo.Document`. Sem `OnCommandOther`, `DELETE`/`PUT` não receberiam 405.
2. Rotas `/api/...` vão para o roteador da API; as demais, para a lista de estáticos.
3. Em `POST /api/game/moves`, o corpo vem de `ARequestInfo.PostStream` (pode ser `nil` se vazio; a posição do stream é zerada antes da leitura) e é lido como bytes.
4. `TJSONObject.ParseJSONValue(bytes, 0)` interpreta o corpo como UTF-8; `posicao` é procurada entre os pares do objeto por comparação exata do nome e só é aceita se for `TJSONNumber` cujo texto passe em `TryStrToInt` (o parser normaliza o número: `4.0` chega como `4` e é aceito; `4.5`, `"4"`, `true` e `null` são rejeitados). Qualquer exceção na leitura vira `CORPO_INVALIDO`.
5. `TGameService.Play` executa sob a seção crítica e devolve o resultado e o estado.
6. A resposta é montada em bytes UTF-8, colocada em `AResponseInfo.ContentStream` com `ContentType`, `CharSet` e `Cache-Control`.
7. Todo o handler fica em `try..except`: uma exceção vira 500 `ERRO_INTERNO` e é registrada no console.

### 4.3 Execução

```
TicTacToeServer.exe [--port 8765] [--www <pasta>]
```

- O servidor cria um `Binding` explícito em `127.0.0.1` (sem ele, o Indy escuta em todas as interfaces).
- `--www` padrão: `<pasta do exe>\..\..\web`, que resolve para a pasta `web` do repositório quando o exe está em `server\bin`.
- Na partida, o console mostra a URL e o caminho da pasta `web`, e avisa se `index.html` não existir nela.
- Se a porta estiver ocupada, a mensagem diz isso e o processo sai com código 1.
- Ctrl+C: `Active := False` na thread principal (nunca dentro de um evento do Indy, o que travaria), libera objetos e sai com código 0.

### 4.4 Compilação

Por linha de comando (DT-15), com `scripts\build.cmd`, que:
1. carrega o ambiente do Delphi com `rsvars.bat` (procura em `C:\Program Files (x86)\Embarcadero\Studio\18.0\bin`, ou no caminho da variável `DELPHI_RSVARS`);
2. mostra a versão do compilador (Berlin = *compiler version 31.0*);
3. chama `dcc32` com saída em `server\bin` e `.dcu` em `server\dcu`.

Pela IDE: *File > Open Project* e escolher `server\TicTacToeServer.dpr`. A IDE cria o `.dproj`; ajustar *Output directory* para `bin` e *Unit output directory* para `dcu`.

## 5. Interface web

HTML, CSS e JavaScript puros, sem bibliotecas nem etapa de build. A interface só exibe o estado recebido e envia as intenções do usuário; turno, vitória e empate vêm do backend (RN-14).

### 5.1 Arquivos

| Arquivo | Conteúdo |
|---|---|
| `web/index.html` | Estrutura acessível: `lang="pt-BR"`, `<main>`, `<h1>`, status (`role="status"`), tabuleiro (`role="group"`, 9 `<button>`), mensagem de erro (`role="alert"`), "Nova partida" e "Tentar novamente". `<link rel="icon" href="data:,">` evita a requisição de favicon (404). |
| `web/style.css` | Variáveis de cor (tema claro e escuro por `prefers-color-scheme`), grade 3x3 com `aspect-ratio`, X e O com cor e traço próprios, destaque das células vencedoras, aparência de partida encerrada, estado de carregamento, foco visível, `prefers-reduced-motion`. |
| `web/app.js` | Um IIFE sem módulos: `request` (fetch com tempo-limite de 8 s), `run` (uma requisição por vez), `render(state)`, `showError`/`clearError`, navegação por setas. |

### 5.2 Identificadores para testes (`data-testid`)

| `data-testid` | Elemento | O que os testes leem |
|---|---|---|
| `app` | `<main>` | `data-state`: `loading`, `playing`, `finished` ou `offline` |
| `board` | Grade | `aria-busy="true"` durante requisições |
| `cell-0` … `cell-8` | Botões das células | Texto `X`, `O` ou vazio; `data-winning="true"` quando vencedora; `aria-disabled="true"` com a partida encerrada ou sem estado; nome acessível (CI-14) |
| `status` | Área de status | Textos exatos de CI-04, CI-05, CI-06 e CI-12 |
| `error-message` | Mensagem de erro | Mensagem do backend ou de falha de comunicação; oculta (`hidden`) quando vazia |
| `new-game` | "Nova partida" | — |
| `retry` | "Tentar novamente" | Visível só após falha de comunicação |

As células não usam o atributo `disabled`, porque o Playwright esperaria a célula ficar habilitada e o clique nunca chegaria ao backend (DT-09).

### 5.3 Lógica da interface

- Ao carregar, `GET /api/game` (CI-01, CI-12).
- `run(ação)` só aceita uma requisição por vez (CI-13, DT-22): se já houver uma pendente, o clique é ignorado. Não há fila e nenhuma resposta chega fora de ordem.
- Resposta 2xx com estado válido → `render(state)` e `clearError()`.
- Resposta de erro do contrato → `showError(corpo.erro.mensagem)`; o tabuleiro não muda.
- Falha de rede, tempo-limite (8 s, `AbortController`) ou resposta fora do contrato → "Não foi possível comunicar com o servidor." e botão "Tentar novamente" (`GET /api/game`).
- Os textos de status são só formatação do estado recebido.
- Teclado: as células são botões (Tab, Enter, Espaço); as setas movem o foco dentro da grade.

## 6. Estratégia de testes## 6. Estratégia de testes

### 6.1 Níveis

| Nível | Ferramenta | O que cobre |
|---|---|---|
| Motor | `EngineCheck.exe` | Regras puras: todas as sequências da spec, rejeições, ordem de validação, reinício. Roda em milissegundos. |
| API | Playwright `request` contra o servidor real | Entradas que a UI não produz: CA-05, 06, 07, 18, 25, 26. |
| UI (E2E) | Playwright + Chromium contra o servidor real | O resto dos critérios, clicando na página como um usuário. |

### 6.2 Princípios

- **Nada de respostas falsas.** Os testes de UI e de API sempre falam com o `TicTacToeServer.exe` real.
- **Única exceção:** o CA-22 bloqueia as requisições no navegador com `page.route(..., route => route.abort())` para simular a rede caída. Ele não fabrica respostas do backend. (D-12)
- Cada teste começa com `POST /api/game/reset` num `beforeEach`.
- Os títulos citam o critério, por exemplo `CA-08 vitória em linha`.
- As pré-condições "Dada a partida encerrada" dos testes de UI são montadas por cliques, não pela API.

### 6.3 Estrutura

Detalhada em `docs/test-plan.md`. Na Entrega 4 só existem os grupos A (`api/`) e R (`rules/`); o grupo U (`ui/`) entra na Entrega 5.

```
tests/
  package.json            dependências com versão fixa (sem ^): @playwright/test 1.64.1,
                          typescript 5.9.3, @types/node 24.10.1
  package-lock.json       gerado na primeira instalação; depois, npm ci
  tsconfig.json
  playwright.config.ts
  support/
    api.ts                tipos do contrato, mensagens, GameApi (reset, state, move,
                          postMoveRaw, play, expectUnchanged, expectError), coerência
    fixtures.ts           fixture `game`: reinicia a partida antes de cada teste
    sequences.ts          sequências de referência (8 vitórias, 9ª jogada, dupla, empate)
    raw-http.ts           HEAD lido direto do socket (prova de corpo vazio)
  api/
    contract.spec.ts      A-01, A-02, A-03, A-11, A-12
    validation.spec.ts    A-04 (10 corpos), A-05 (8 corpos), A-06, A-07
    routes.spec.ts        A-08 (4 rotas), A-09 (8 métodos)
  rules/
    turns.spec.ts         R-01 a R-08
    wins.spec.ts          R-09 a R-18
    end-and-reset.spec.ts R-19 a R-26
    concurrency.spec.ts   R-27, R-28
```

### 6.4 Configuração do Playwright

- `workers: 1`, `fullyParallel: false`, `retries: 0`, `forbidOnly: true`.
- Relatórios: `list` (console), `html` (`tests/playwright-report`) e `json` (`tests/test-results/results.json`, lido pelo script de validação).
- `baseURL` sempre `http://127.0.0.1:<porta>` (DT-07, risco IPv6 do `localhost`).
- `webServer`: comando `"..\server\bin\TicTacToeServer.exe" --port 8765`, pronto quando `GET /health` responde, `reuseExistingServer: false`, `timeout: 15 s`. O Playwright inicia o processo antes dos testes e o finaliza no fim; no Windows a finalização é forçada, o que libera a porta (I-11).
- Variáveis `PW_PORT` e `PW_EXTERNAL_SERVER=1` (usar um servidor já iniciado) existem só para a validação rodar o R-27 contra um servidor sabotado; a suíte normal sempre inicia o executável real.
- Nenhum navegador é usado na Entrega 4 (só o `request` do Playwright), então `npx playwright install` ainda não é necessário.

### 6.5 Comandos

```bat
scripts\build.cmd
cd tests
npm ci                    :: na primeira vez, npm install (gera o package-lock.json)
npm run typecheck
npx playwright test       :: suíte completa (= npm test)
npx playwright show-report
```

Validação completa da entrega: `scripts\validate-step4.cmd` (log em `logs\step4-validation.log`).

## 7. Estrutura do repositório

```
jogo-da-velha/
├── docs/
│   ├── spec.md
│   ├── plan.md
│   └── test-plan.md        (Etapa 3)
├── server/
│   ├── TicTacToeServer.dpr / .dproj
│   ├── EngineCheck.dpr
│   ├── tests/
│   │   ├── uMiniTest.pas
│   │   └── uEngineTests.pas
│   ├── src/
│   │   ├── uGameEngine.pas
│   │   ├── uGameService.pas
│   │   ├── uGameJson.pas
│   │   └── uHttpApp.pas
│   └── bin/                (saída, fora do Git)
├── web/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── tests/                  (projeto Playwright)
├── scripts/
│   ├── build.cmd
│   └── validate-*.cmd / .ps1   (um par por entrega)
├── logs/                   (saídas das validações, fora do Git)
├── .gitignore              (dcu, exe, logs, __history, *.local, *.identcache, node_modules, test-results, playwright-report)
├── .gitattributes          (*.pas, *.dpr, *.cmd com fim de linha CRLF)
└── README.md
```

## 8. Compatibilidade com Delphi 10.1 Berlin

| Recurso usado | Disponível no Berlin? | Observação |
|---|---|---|
| Indy 10: `TIdHTTPServer`, `TIdContext`, `TIdHTTPRequestInfo/ResponseInfo` | Sim, acompanha o Berlin | Componente usado há muitas versões; uma thread por conexão. |
| `ARequestInfo.PostStream`, `AResponseInfo.ContentStream`, `CharSet`, `CustomHeaders` | Sim | Corpo JSON chega em `PostStream`, porque não é `x-www-form-urlencoded`. |
| `System.JSON` (`TJSONObject.ParseJSONValue`, `TJSONNumber`, `TJSONArray`, `TJSONNull`, `ToJSON`) | Sim | Unit com esse nome desde o XE6. `ParseJSONValue` devolve `nil` para JSON inválido. |
| `System.SyncObjs` (`TCriticalSection`, `TEvent`) | Sim | — |
| `System.IOUtils` (`TFile.ReadAllBytes`, `TPath`) | Sim | Desde o Delphi 2010. |
| `TEncoding.UTF8`, `TBytes`, `TArray<Integer>` | Sim | Desde o Delphi 2009. |
| `Winapi.Windows.SetConsoleCtrlHandler` | Sim | API do Windows. |
| Constantes de array fixo `array[0..7, 0..2] of Integer` | Sim | Sintaxe clássica. |
| MSBuild + `rsvars.bat` (`Studio\18.0`) | Sim, a partir da edição Professional | Confirmar a edição (D-02). |

**Evitado de propósito:**
- variáveis inline e `for var` (10.3);
- *managed records* (10.4);
- strings multilinha (12);
- `NetHTTP`/`System.Net.HttpClient` (desnecessário);
- WebBroker e DataSnap (dependem de edição e acrescentam camadas);
- qualquer componente de terceiros.

**Pontos a confirmar na primeira compilação real:** os itens acima vêm do histórico conhecido do Delphi e não foram compilados neste ambiente, que não é Windows. A Entrega 1 (seção 9) é exatamente o momento de confirmá-los. Atenção especial a duas coisas do Indy instalado no Berlin:
- se a resposta mantém `charset=utf-8` usando `ContentStream`;
- se `HEAD` passa pelo `OnCommandGet`.

**Playwright no Windows:** a documentação atual do Playwright exige **Node.js 22, 24 ou 26** e **Windows 11 ou Windows Server 2019+**. Num Windows 10, será preciso fixar uma versão mais antiga do Playwright que ainda o suporte, escolhida na Entrega 4. (D-08) O ambiente real é Windows 10 Pro build 19045 (registrado em `docs/delivery-log.md`).

## 9. Sequência de implementação

Regra para todos os passos: **teste primeiro (vermelho) → implementação (verde) → commit**. Um passo só termina quando seus critérios forem verificados de verdade, com a saída registrada no resumo do passo. Compilar não basta.

### Etapa 3 — Cenários de teste (antes de qualquer código)

**Passo T — `docs/test-plan.md`.** Cenários dos grupos M (motor), R (regras via HTTP), A (endpoints) e U (interface), com pré-condições, ações, resultado esperado, forma de verificação e critérios de aprovação.
- *Concluído quando:* todos os CA-01 a CA-27 têm ao menos um cenário, e você aprovou o documento.

### Etapa 4 — Implementação em pequenas entregas

**Entrega 1 — Estrutura do servidor e `/health`.**
- Repositório: `.gitignore`, `.gitattributes`, `README.md`.
- `TicTacToeServer.dpr`, `uConsoleLog.pas` e `uHttpApp.pas` com: bind em `127.0.0.1`, `--port`, Ctrl+C, `GET /health`, 404 e 405 em JSON, cabeçalho `Cache-Control`.
- `scripts\build.cmd` e `scripts\validate-step1.cmd`.
- Sem regras do jogo, sem interface, sem Playwright.
- *Concluído quando* (com a saída real em `logs\step1-validation.log`):
  - compila no Berlin (versão do compilador registrada) sem erros;
  - `GET /health` devolve 200, `application/json; charset=utf-8` e `{"status":"ok"}` (CA-27);
  - rota inexistente devolve 404 JSON com acentos corretos; `POST /health` devolve 405 com `Allow`;
  - o servidor escuta só em `127.0.0.1`;
  - depois de finalizado, o servidor sobe de novo na mesma porta;
  - Ctrl+C encerra o servidor (verificação manual, registrada no README).

**Entrega 2 — Motor do jogo.**
- Escrever primeiro o `EngineCheck` (casos M-01 a M-12 do test-plan) e depois `uGameEngine.pas`.
- `scripts\delphi-env.cmd` e `scripts\compile-dpr.cmd` passam a ser usados pelo `build.cmd` e pelas sabotagens.
- *Concluído quando* (saída real em `logs\step2-validation.log`):
  - servidor e `EngineCheck` compilam no Berlin sem erros e sem *warnings*;
  - `EngineCheck.exe` sai com código 0, com todos os casos OK;
  - as sabotagens SB-01, SB-02, SB-03 e SB-05 fazem o `EngineCheck` sair com código 1, com os casos esperados falhando;
  - a regressão da Entrega 1 (`GET /health`) continua passando;
  - o motor não usa nenhuma unit do Indy, do HTTP ou de JSON (verificado no código-fonte).

**Entrega 3 — Serviço de jogo e API HTTP.**
- Contrato HTTP fechado na seção 3 antes do código.
- Escrever primeiro os testes: `scripts\validate-step3.ps1` (cenários A e R por HTTP real) e os casos SV e J no `EngineCheck`; rodar a fase vermelha contra o servidor da Entrega 2.
- Depois: `uGameService`, `uGameJson`, rotas `GET /api/game`, `POST /api/game/moves`, `POST /api/game/reset` em `uHttpApp`.
- *Concluído quando* (saída real em `logs\step3-validation.log`):
  - compila sem erros nem warnings;
  - `EngineCheck` aprovado (M, SV, J);
  - todos os cenários A (exceto A-10, estáticos) e R do test-plan aprovados por HTTP real, incluindo concorrência (R-27, R-28);
  - a sabotagem SB-04 (sem trava e com atraso) faz o R-27 falhar;
  - regressão do `/health` aprovada.

**Entrega 4 — Playwright configurado (só API).**
- Projeto `tests/` (6.3 a 6.5) com versões fixas (DT-20) e os grupos A e R em TypeScript, sem repetir o teste exaustivo do motor.
- *Concluído quando* (saída real em `logs\step4-validation.log`):
  - servidor compilado com o Berlin e `EngineCheck` aprovado;
  - dependências instaladas localmente e `tsc --noEmit` sem erros;
  - suíte completa aprovada **duas vezes**, sem retries, pulados ou instáveis, com relatório HTML;
  - cada arquivo de teste aprovado sozinho, em ordem inversa;
  - com o executável renomeado, a suíte falha ao iniciar o servidor;
  - a sabotagem SB-04 faz o R-27 do Playwright falhar.

**Entrega 5 — Interface e testes no navegador.**
- Spec v0.5 (CI-12 a CI-16, CA-28 a CA-32) e seção 5 deste plano antes do código.
- Escrever primeiro os testes do grupo U e o A-10; rodar a fase vermelha contra o servidor sem estáticos; depois `--www`, envio dos estáticos e os arquivos `web/`.
- Instalar o Chromium do Playwright 1.64.1 e confirmar que funciona no Windows 10.
- *Concluído quando* (saída real em `logs\step5-validation.log`):
  - compila sem erros nem warnings e o `EngineCheck` passa;
  - suíte completa (API + navegador) aprovada duas vezes, sem retries, com relatório HTML;
  - nenhum erro de console, falha de requisição, 404 ou 5xx inesperado nos testes de navegador;
  - cada arquivo de teste aprovado sozinho;
  - a sabotagem SB-06 (interface desenhando a jogada sem esperar o servidor) faz os testes de navegador falharem;
  - log do servidor sem erros internos;
  - capturas de tela da interface (desktop e tela pequena) anexadas ao registro da entrega.

**Entrega 6 — Documentação final.**
- A falha de comunicação (U-13) foi antecipada para a Entrega 5, a pedido. Resta revisar o `README.md` completo.
- *Concluído quando:* o README foi seguido do início ao fim.

### Etapa 5 — Validação

**Entrega 7 — Validação final.**
- Clone limpo em outra pasta, depois `build.cmd`, `EngineCheck`, `npm ci`, instalação do Chromium e `npm test`.
- *Concluído quando:*
  - a suíte completa passa **3 vezes seguidas**, sem retries;
  - a matriz CA → teste em `docs/test-plan.md` está 100% marcada com o resultado real;
  - spec e plano estão com status "concluído" e há uma tag `v1.0`.
- Toda falha encontrada é corrigida e reexecutada. Nenhum resultado é declarado sem saída real.

## 10. Rastreabilidade CA → testes

A matriz completa CA → cenários (M, R, A, U) está em `docs/test-plan.md`, seção 12.

## 11. Riscos

| Risco | Mitigação |
|---|---|
| Acentos corrompidos pelo Indy | DT-08; o teste de API compara a mensagem exata, com acentos. |
| Windows 10 sem suporte no Playwright atual | Fixar uma versão anterior compatível (Entrega 4). |
| `localhost` resolvido como IPv6 pelo Node, com o servidor só em IPv4 | Usar sempre `127.0.0.1`. |
| Executável antigo rodando na porta 8765 | `reuseExistingServer` desligado; mensagem clara de porta ocupada. |
| Testes instáveis por estado global | 1 worker, reset antes de cada teste, sem retries. |
| Compilação e execução só possíveis no Windows do usuário | As entregas rodam na sua máquina, por você ou por mim via o computador vinculado a esta conversa, se você permitir. |

## 12. Registro de alterações

| Versão | Data | Alteração |
|---|---|---|
| 0.1 | 2026-10-15 | Criação do plano técnico. |
| 0.2 | 2026-10-15 | Revisão contra a spec v0.3 e o plano de testes: `OnCommandOther` para 405 em PUT/DELETE; `Binding` explícito em 127.0.0.1; `Content-Type` não exigido; risco IPv6/`localhost`; testes Playwright divididos em `rules/`, `api/` e `ui/`; `docs/tests.md` renomeado para `docs/test-plan.md`. |
| 0.3 | 2026-10-15 | Consistência antes da implementação: `GET /health` (3.1, 3.4, `webServer.url`); compilação por `dcc32` (DT-15, 4.4); scripts de validação com log (DT-16); UTF-8 com BOM nos fontes (DT-17); nova unit `uConsoleLog`; sequência de implementação reorganizada em entregas, começando pela estrutura do servidor (seção 9). |
| 0.4 | 2026-10-15 | Entrega 2: estratégia de testes do motor (DT-11), cópia do estado (DT-18), estrutura `server/tests`, scripts `delphi-env.cmd`/`compile-dpr.cmd` e critérios de conclusão detalhados. |
| 0.5 | 2026-10-15 | Entrega 3: contrato HTTP detalhado antes do código (405 por rota, 404 antes dos estáticos, erros sem estado, regras de corpo e de número); `uGameService` e `uGameJson` detalhados; leitura do corpo por bytes (4.2); DT-19 (validação HTTP por PowerShell até o Playwright); entregas reorganizadas: a API completa entra na Entrega 3 e as seguintes foram renumeradas (Playwright 4, interface 5, falha de comunicação 6, validação final 7). Corrigido: `uGameEngine` não usa nenhuma unit. |
| 0.6 | 2026-10-15 | Entrega 3, após a primeira validação real: o parser JSON do Delphi Berlin normaliza o texto dos números (`4.0` → `4`, `1e0` → `1`), o que tornou inviável, sem um analisador próprio, recusar inteiros escritos com fração ou expoente. O contrato (3.3) passou a exigir **valor** inteiro; a RN-04 da spec (número inteiro; fracionário inválido) continua atendida. |
| 0.7 | 2026-10-15 | Entrega 4: versões do Playwright/TypeScript (DT-20) e verificação de compatibilidade com Windows 10 e Node 24.11.1; seções 6.3 a 6.5 reescritas com a estrutura real de `tests/`, a configuração (`webServer`, relatórios, variáveis `PW_PORT`/`PW_EXTERNAL_SERVER`) e os comandos; critérios de conclusão da Entrega 4. |
| 0.8 | 2026-10-15 | Entrega 5: seção 5 reescrita (arquivos, `data-testid`, uma requisição por vez, tempo-limite, teclado); estáticos com `Content-Type` e `Cache-Control: no-cache`, lidos do disco (DT-04); 404 JSON também fora da API (DT-21); DT-22 (uma requisição por vez); DT-23 (instalação do Chromium); `--www`; critérios da Entrega 5; falha de comunicação antecipada da Entrega 6. |
