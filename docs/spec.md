# Especificação — Jogo da Velha (Delphi Berlin + Web)

| Campo | Valor |
|---|---|
| Versão | 0.6 |
| Data | 2026-10-16 |
| Etapa SDD | 1 — Especificação (revisada) |
| Status | Aguardando aprovação junto com `docs/plan.md` e `docs/test-plan.md` |

---

## 1. Objetivo

Construir um Jogo da Velha para **dois jogadores humanos no mesmo computador**, em que:

- o **backend Delphi Berlin** (servidor HTTP com Indy `TIdHTTPServer`) mantém o estado da partida e aplica todas as regras;
- a **interface web** (HTML, CSS e JavaScript puros) apenas exibe o estado e envia as intenções do usuário ao backend;
- o comportamento é verificado por **testes end-to-end com Playwright + TypeScript**, executados pelo navegador contra a aplicação real em funcionamento.

O projeto também tem objetivo didático: exercitar o fluxo Spec-Driven Development (especificação → plano → testes → implementação → validação) com rastreabilidade entre requisitos e testes.

## 2. Escopo

### 2.1 Dentro do escopo

- Tabuleiro 3x3 com uma única partida ativa por vez.
- Alternância de turnos entre X e O.
- Validação de jogadas (posição válida, partida em andamento, célula vazia).
- Detecção de vitória (3 linhas, 3 colunas, 2 diagonais) e de empate.
- Bloqueio de jogadas após o fim da partida.
- Botão "Nova partida" que reinicia o estado.
- Indicação na interface do jogador da vez, do vencedor ou do empate.
- Destaque das células vencedoras.
- Exibição de mensagem quando uma jogada for rejeitada pelo backend.
- Endpoint de verificação de saúde (`GET /health`), usado para saber se o servidor está no ar.
- Servidor HTTP local em Windows, compatível com Delphi Berlin (10.1).
- Testes E2E com Playwright + TypeScript.
- Versionamento com Git.

### 2.2 Fora do escopo

- Jogo contra o computador (IA).
- Jogo em rede entre máquinas diferentes, contas de usuário ou autenticação.
- Múltiplas partidas simultâneas ou sessões por jogador.
- Sincronização automática entre abas (sem polling, WebSocket ou SSE).
- Placar acumulado, histórico de partidas ou ranking.
- Persistência em banco de dados ou arquivo (o estado vive apenas em memória).
- Desfazer jogada.
- Frameworks de front-end (React, Vue etc.) e bibliotecas Delphi de terceiros.
- HTTPS, implantação em servidor ou nuvem.

## 3. Glossário

| Termo | Definição |
|---|---|
| Célula | Uma das 9 posições do tabuleiro, identificada pelo índice 0 a 8 (ver 4.1). |
| Jogador da vez | Símbolo (X ou O) autorizado a fazer a próxima jogada; não existe com a partida encerrada. |
| Partida em andamento | Estado em que jogadas ainda são aceitas. |
| Partida encerrada | Estado após vitória ou empate; jogadas são recusadas. |
| Combinação vencedora | Uma das 8 trincas de células alinhadas (ver 4.3). |
| Células vencedoras | União das células de todas as combinações completadas pelo vencedor (3 ou 5 células). |
| Jogada rejeitada | Tentativa de jogada que o backend recusa sem alterar o estado. |

## 4. Modelo do domínio

### 4.1 Posições do tabuleiro

As células são numeradas da esquerda para a direita, de cima para baixo:

```
 0 | 1 | 2
---+---+---
 3 | 4 | 5
---+---+---
 6 | 7 | 8
```

### 4.2 Estado da partida

O estado completo, mantido exclusivamente pelo backend, contém:

| Elemento | Valores possíveis |
|---|---|
| Tabuleiro | 9 células, cada uma vazia, `X` ou `O` |
| Status | `EM_ANDAMENTO`, `VITORIA`, `EMPATE` |
| Jogador da vez | `X` ou `O` com status `EM_ANDAMENTO`; nenhum com a partida encerrada |
| Vencedor | `X` ou `O` com status `VITORIA`; nenhum nos demais casos |
| Células vencedoras | Índices em ordem crescente (3 ou 5) com status `VITORIA`; lista vazia nos demais casos |

### 4.3 Combinações vencedoras

| Tipo | Índices |
|---|---|
| Linhas | (0,1,2), (3,4,5), (6,7,8) |
| Colunas | (0,3,6), (1,4,7), (2,5,8) |
| Diagonais | (0,4,8), (2,4,6) |

### 4.4 Transições de estado

```
                      ┌────────── jogada rejeitada (estado inalterado)
                      │
                      ▼
          ┌──► [EM_ANDAMENTO] ── jogada aceita ──┬── completa combinação? ──► [VITORIA]
          │       │      ▲                       │
          │       │      └── troca o turno ◄─────┼── não, tabuleiro com vazios
          │       │                              │
          │       │                              └── não, tabuleiro cheio ───► [EMPATE]
          │       │
 nova partida   nova partida (a qualquer momento volta ao estado inicial)
          │
 [VITORIA] / [EMPATE] ── jogada ──► rejeitada (PARTIDA_ENCERRADA)
```

Estado inicial: tabuleiro vazio, `EM_ANDAMENTO`, jogador da vez `X`, sem vencedor, sem células vencedoras.

## 5. Regras de negócio

| ID | Regra |
|---|---|
| RN-01 | O tabuleiro tem 9 células (3x3), todas vazias no início de cada partida. |
| RN-02 | Toda partida começa com o jogador **X** *(premissa — ver D-01)*. |
| RN-03 | Após cada jogada aceita que não encerra a partida, o turno passa para o outro símbolo (X → O → X ...). |
| RN-04 | Uma jogada só é aceita se a posição for um número inteiro de 0 a 8. Texto (`"4"`), número fracionário (`4.5`), booleano, `null` ou ausência de posição são inválidos. O nome do campo (`posicao`) diferencia maiúsculas de minúsculas. |
| RN-05 | Uma jogada só é aceita se a célula estiver vazia. |
| RN-06 | Uma jogada só é aceita se a partida estiver `EM_ANDAMENTO`. |
| RN-07 | O símbolo gravado na célula é sempre o do jogador da vez, determinado pelo backend. A requisição de jogada informa apenas a posição; qualquer outro campo enviado (por exemplo, um símbolo) é ignorado. |
| RN-08 | Após cada jogada aceita, o backend verifica todas as combinações de 4.3. Se o símbolo jogado completar uma ou mais delas, o status passa a `VITORIA`, com o vencedor registrado e as células vencedoras sendo a união de todas as combinações completadas. |
| RN-09 | Se não houver vitória e as 9 células estiverem ocupadas, o status passa a `EMPATE`. A verificação de vitória tem precedência sobre a de empate. |
| RN-10 | Uma partida encerrada (`VITORIA` ou `EMPATE`) permanece com tabuleiro, status, vencedor e células vencedoras inalterados até que "Nova partida" seja acionada. |
| RN-11 | "Nova partida" pode ser acionada a qualquer momento, inclusive com a partida em andamento, sem pedir confirmação, e restaura o estado inicial (4.4). *(premissa — ver D-04)* |
| RN-12 | Uma jogada rejeitada **não altera** nenhum elemento do estado. |
| RN-13 | Existe uma única partida no servidor, compartilhada por todas as abas e clientes. Uma aba não é atualizada automaticamente quando outra joga; ela vê o estado atual ao carregar a página ou ao fazer sua próxima ação. *(premissa — ver D-03)* |
| RN-14 | Todas as regras acima são aplicadas no backend. A interface não decide validade de jogada, vencedor, empate nem turno; ela apenas reflete o estado recebido. |
| RN-15 | **Ordem de validação** de uma jogada, parando no primeiro erro: (1) corpo da requisição é um objeto JSON; (2) posição válida (RN-04); (3) partida em andamento (RN-06); (4) célula vazia (RN-05). Assim, após um empate, a resposta é sempre "partida encerrada", e não "célula ocupada". |

## 6. Comportamentos esperados da interface

| ID | Comportamento |
|---|---|
| CI-01 | Ao abrir a página, a interface obtém o estado atual do backend e o exibe (não presume um tabuleiro vazio). |
| CI-02 | O tabuleiro é exibido como uma grade 3x3 de células clicáveis. |
| CI-03 | Ao clicar em qualquer célula, a interface envia a jogada ao backend, **sem validar nada localmente**, e exibe o estado retornado. |
| CI-04 | Com a partida em andamento, a área de status exibe exatamente "Vez do jogador X" ou "Vez do jogador O". |
| CI-05 | Em caso de vitória, a área de status exibe exatamente "Jogador X venceu!" ou "Jogador O venceu!", e as células vencedoras recebem destaque visual. |
| CI-06 | Em caso de empate, a área de status exibe exatamente "Empate!". |
| CI-07 | Com a partida encerrada, o tabuleiro recebe aparência de inativo, marcada com `aria-disabled="true"` nas células. É apenas visual: os cliques continuam sendo enviados ao backend (CI-03), que os rejeita (RN-06), e a interface exibe a mensagem recebida (CI-09). |
| CI-08 | Um botão "Nova partida" está sempre visível; ao acioná-lo, a interface solicita o reinício ao backend e exibe o novo estado. |
| CI-09 | Quando o backend rejeitar uma jogada, a interface exibe a mensagem de erro enviada pelo backend e mantém o tabuleiro exibido. A mensagem desaparece após a próxima jogada aceita ou após "Nova partida". |
| CI-10 | Se o backend não responder (falha de rede ou mais de 8 s sem resposta), a interface exibe exatamente "Não foi possível comunicar com o servidor.", mantém o último estado exibido e mostra o botão "Tentar novamente", que consulta o estado no backend. A mensagem e o botão desaparecem na próxima resposta bem-sucedida. Se a falha ocorrer no carregamento inicial, o tabuleiro fica vazio e inativo até a recuperação. |
| CI-11 | Os elementos testáveis possuem identificadores estáveis (`data-testid`), definidos no plano técnico, para que os testes não dependam de layout. |
| CI-12 | **Carregamento:** enquanto o estado inicial é obtido, a área de status exibe "Carregando partida…" e o tabuleiro fica marcado com `aria-busy="true"`. Durante qualquer requisição o tabuleiro também fica com `aria-busy="true"`. |
| CI-13 | **Uma requisição por vez:** enquanto houver uma requisição pendente, novos cliques em células, em "Nova partida" e em "Tentar novamente" são ignorados (não geram requisição). Assim nenhuma resposta é aplicada fora de ordem e cliques rápidos não deixam a interface inconsistente. O backend continua protegido contra concorrência de qualquer forma (RNF-06). |
| CI-14 | **Acessibilidade:** página em `pt-BR`; cada célula é um botão com nome acessível "Linha L, coluna C: vazia", "…: X" ou "…: O" (acrescido de ", vencedora" quando destacada); a área de status é anunciada (`role="status"`); a mensagem de erro usa `role="alert"`; o foco é visível. **Teclado:** Tab alcança as células e os botões; Enter e Espaço jogam; as setas movem o foco entre as células. |
| CI-15 | **Responsividade:** a interface funciona a partir de 320 px de largura, sem rolagem horizontal, com células de pelo menos 44 × 44 px. |
| CI-16 | X e O têm aparência distinta (cor e forma), e o jogador da vez também é indicado visualmente, além do texto. |

## 7. Critérios de aceitação

Formato: **Dado** (contexto) / **Quando** (ação) / **Então** (resultado). Cada critério será coberto por pelo menos um teste. "UI" indica teste pelo navegador; "API" indica requisição HTTP direta ao backend real, usada para entradas que a interface não consegue produzir. Todas as sequências de jogadas abaixo foram verificadas por simulação (ver seção 11, v0.2).

### Início e turnos

- **CA-01 — Estado inicial (UI).** Dado que uma nova partida foi iniciada, quando a página é exibida, então as 9 células estão vazias, o status é "Vez do jogador X", nenhuma célula está destacada e nenhuma mensagem de erro é exibida. *(RN-01, RN-02, CI-01, CI-04)*
- **CA-02 — Primeira jogada (UI).** Dado o estado inicial, quando o jogador clica na célula 0, então a célula 0 exibe X e o status é "Vez do jogador O". *(RN-03, RN-07)*
- **CA-03 — Alternância (UI).** Dado que X jogou na célula 0, quando o jogador clica na célula 4, então a célula 4 exibe O e o status volta a "Vez do jogador X". *(RN-03)*

### Jogadas inválidas

- **CA-04 — Célula ocupada (UI).** Dado que a célula 0 contém X e é a vez de O, quando o jogador clica na célula 0, então a célula continua com X, o status continua "Vez do jogador O" e a mensagem de erro de célula ocupada é exibida. *(RN-05, RN-12, CI-09)*
- **CA-05 — Posição inválida (API).** Dada uma partida em andamento, quando é enviada uma jogada com posição 9, -1, 4.5, `"4"`, `null` ou sem posição, então cada resposta indica posição inválida e o estado não muda. *(RN-04, RN-12, RN-15)*
- **CA-06 — Corpo malformado (API).** Dada uma partida em andamento, quando é enviada uma jogada com corpo vazio, que não é JSON válido ou que é JSON mas não é um objeto (ex.: `[4]` ou `4`), então a resposta indica corpo inválido e o estado não muda. *(RN-12, RN-15, CE-04)*
- **CA-07 — Símbolo imposto pelo cliente (API).** Dado o estado inicial, quando é enviada uma jogada na posição 0 que inclui um campo de símbolo com valor "O", então a jogada é aceita, a célula 0 recebe X e o jogador da vez passa a O. *(RN-07)*

### Vitórias

Em todos estes critérios, ao final, as células vencedoras ficam destacadas e o tabuleiro fica com `aria-disabled="true"`.

- **CA-08 — Vitória em linha (UI).** Sequência X:0, O:3, X:1, O:4, X:2. Status "Jogador X venceu!"; destacadas 0, 1, 2. *(RN-08, CI-05, CI-07)*
- **CA-09 — Vitória em coluna (UI).** Sequência X:0, O:1, X:3, O:4, X:8, O:7. Status "Jogador O venceu!"; destacadas 1, 4, 7. *(RN-08, CI-05)*
- **CA-10 — Vitória na diagonal principal (UI).** Sequência X:0, O:1, X:4, O:2, X:8. Status "Jogador X venceu!"; destacadas 0, 4, 8. *(RN-08, CI-05)*
- **CA-11 — Vitória na diagonal secundária (UI).** Sequência X:2, O:0, X:4, O:1, X:6. Status "Jogador X venceu!"; destacadas 2, 4, 6. *(RN-08, CI-05)*
- **CA-12 — Demais combinações (UI).** Cada sequência abaixo termina em vitória, com o status e as células destacadas indicados: *(RN-08, CI-05)*
  - X:3, O:0, X:4, O:1, X:5 → "Jogador X venceu!"; 3, 4, 5.
  - X:0, O:6, X:1, O:7, X:4, O:8 → "Jogador O venceu!"; 6, 7, 8.
  - X:0, O:1, X:3, O:2, X:6 → "Jogador X venceu!"; 0, 3, 6.
- **CA-13 — Vitória na última jogada (UI).** Sequência X:0, O:1, X:2, O:4, X:5, O:3, X:7, O:6, X:8. A 9ª jogada preenche o tabuleiro e completa 2-5-8: status "Jogador X venceu!" (e não "Empate!"); destacadas 2, 5, 8. *(RN-08, RN-09)*
- **CA-14 — Vitória com duas combinações (UI).** Sequência X:0, O:1, X:2, O:3, X:6, O:5, X:8, O:7, X:4. A última jogada completa as duas diagonais: status "Jogador X venceu!"; destacadas 0, 2, 4, 6, 8. *(RN-08, CI-05)*

### Empate

- **CA-15 — Empate (UI).** Sequência X:0, O:1, X:2, O:4, X:3, O:5, X:7, O:6, X:8, que preenche o tabuleiro sem combinação completa. Status "Empate!"; nenhuma célula destacada; tabuleiro com `aria-disabled="true"`. *(RN-09, CI-06, CI-07)*

### Bloqueio após o fim

- **CA-16 — Bloqueio após vitória (UI).** Dada a partida do CA-08 encerrada, quando o jogador clica na célula vazia 5, então a célula continua vazia, o status continua "Jogador X venceu!" e a mensagem de partida encerrada é exibida. *(RN-06, RN-10, RN-12, CI-07, CI-09)*
- **CA-17 — Bloqueio após empate (UI).** Dada a partida do CA-15 encerrada, quando o jogador clica na célula 4, então o tabuleiro não muda, o status continua "Empate!" e a mensagem exibida é a de partida encerrada (não a de célula ocupada). *(RN-06, RN-10, RN-15)*
- **CA-18 — Bloqueio no backend (API).** Dada uma partida encerrada por vitória e, separadamente, uma encerrada por empate, quando uma jogada é enviada diretamente ao endpoint, então a resposta indica partida encerrada e o estado não muda. Isso garante que o bloqueio não depende da interface. *(RN-06, RN-10, RN-14, RN-15)*

### Nova partida

- **CA-19 — Reinício após fim (UI).** Dada uma partida encerrada, quando o jogador clica em "Nova partida", então as 9 células ficam vazias, o status é "Vez do jogador X", nenhuma célula está destacada, o tabuleiro não está com `aria-disabled="true"` e nenhuma mensagem de erro é exibida. *(RN-11, CI-08)*
- **CA-20 — Reinício no meio da partida (UI).** Dada uma partida em andamento com as jogadas X:0, O:4, quando o jogador clica em "Nova partida", então o resultado é o mesmo do CA-19. *(RN-11, CI-08)*

### Mensagens e falhas

- **CA-21 — Mensagem de erro some (UI).** Dado que o CA-04 exibiu a mensagem de célula ocupada, quando o jogador clica na célula vazia 4, então a jogada é aceita e a mensagem desaparece. Dado novamente a mensagem visível, quando o jogador clica em "Nova partida", então a mensagem também desaparece. *(CI-09)*
- **CA-22 — Servidor inacessível e recuperação (UI).** Dada a página carregada com uma partida em andamento, quando a comunicação com o backend falha e o jogador clica em uma célula, então a mensagem "Não foi possível comunicar com o servidor." e o botão "Tentar novamente" são exibidos e o tabuleiro não muda. Quando a comunicação volta e o jogador aciona "Tentar novamente", então a mensagem e o botão desaparecem e o tabuleiro mostra o estado do backend. *(CI-10, CE-07)*

- **CA-28 — Carregamento (UI).** Dada uma resposta lenta do backend ao carregar a página, enquanto ela não chega o status mostra "Carregando partida…", o tabuleiro está com `aria-busy="true"` e cliques nas células não geram requisições; quando a resposta chega, o estado é exibido normalmente. *(CI-12, CI-13)*
- **CA-29 — Teclado e acessibilidade (UI).** Com o foco na célula 0, Enter joga X; a seta para a direita leva o foco à célula 1; Espaço joga O. As células têm os nomes acessíveis de CI-14, que mudam com o conteúdo; a página tem idioma `pt-BR`, um título `h1`, uma região principal, status com `role="status"` e erro com `role="alert"`. *(CI-14)*
- **CA-30 — Tela pequena (UI).** Numa viewport de 360 × 640, o tabuleiro inteiro cabe na largura sem rolagem horizontal, cada célula mede pelo menos 44 × 44 px e uma jogada funciona. *(CI-15)*
- **CA-31 — Cliques rápidos (UI).** Com a resposta do backend atrasada, quando o jogador clica na célula 0 e logo em seguida na célula 1, então apenas uma jogada é enviada, o tabuleiro termina com X só na célula 0, a vez é de O e nenhuma mensagem de erro aparece. *(CI-13)*
- **CA-32 — Falha no carregamento inicial (UI).** Dado o backend inacessível ao abrir a página, então a mensagem de falha de comunicação e o botão "Tentar novamente" são exibidos; quando a comunicação volta e o botão é acionado, o estado do backend é exibido. *(CI-10)*

### Estado no backend

- **CA-23 — Estado sobrevive ao recarregamento (UI).** Dada uma partida com as jogadas X:0, O:4, quando a página é recarregada, então o tabuleiro e o status exibidos são os mesmos de antes. *(RN-13, RN-14, CI-01)*
- **CA-24 — Estado compartilhado entre abas (UI).** Dadas duas abas abertas, quando X joga na célula 0 pela primeira aba e a segunda aba é recarregada, então a segunda aba mostra X na célula 0 e "Vez do jogador O". *(RN-13)*
- **CA-25 — Jogadas simultâneas (API).** Dado o estado inicial, quando duas jogadas na posição 0 são enviadas ao mesmo tempo, então exatamente uma é aceita, a outra é rejeitada por célula ocupada, e o estado final tem apenas um X na célula 0 com a vez de O. *(RN-05, CE-08, RNF-06)*

### Protocolo HTTP

- **CA-27 — Verificação de saúde (API).** Dado o servidor iniciado, quando é feita a requisição `GET /health`, então a resposta é 200, com `Content-Type` `application/json; charset=utf-8` e corpo `{"status":"ok"}`, e o estado da partida não muda. *(RNF-14)*

- **CA-26 — Rotas e métodos (API).** Uma rota inexistente responde "não encontrado"; um método não suportado em rota existente responde "método não permitido"; um arquivo estático inexistente responde "não encontrado". Em nenhum caso o estado muda. *(CE-05, CE-06, CE-09)*

## 8. Cenários de erro

| ID | Situação | Resposta esperada do backend | Efeito no estado | Interface | CA |
|---|---|---|---|---|---|
| CE-01 | Jogada em célula ocupada | Conflito, com mensagem | Inalterado | Mensagem do backend (CI-09) | CA-04 |
| CE-02 | Jogada com partida encerrada | Conflito, com mensagem | Inalterado | Mensagem do backend (CI-07, CI-09) | CA-16, CA-17, CA-18 |
| CE-03 | Posição fora de 0..8 ou não inteira | Requisição inválida | Inalterado | Não ocorre pela UI | CA-05 |
| CE-04 | Corpo ausente, que não é JSON ou que não é um objeto JSON | Requisição inválida | Inalterado | Não ocorre pela UI | CA-06 |
| CE-05 | Rota inexistente | Não encontrado | Inalterado | — | CA-26 |
| CE-06 | Método HTTP não suportado em rota existente | Método não permitido | Inalterado | — | CA-26 |
| CE-07 | Backend inacessível | — | — | Mensagem de falha de comunicação (CI-10) | CA-22 |
| CE-08 | Duas jogadas simultâneas | Serializadas; no máximo uma aceita para a mesma célula | Consistente | Cada cliente vê a resposta da sua requisição | CA-25 |
| CE-09 | Arquivo estático inexistente | Não encontrado | — | — | CA-26 |

Toda resposta de erro da API inclui um código de erro e uma mensagem legível em português. Códigos HTTP, códigos de erro e o formato do corpo estão definidos em `docs/plan.md`.

## 9. Requisitos não funcionais

| ID | Requisito |
|---|---|
| RNF-01 | **Compatibilidade:** o backend compila e executa no Delphi 10.1 Berlin, usando apenas a RTL e o Indy 10 que acompanham essa versão. Nenhum recurso de versões posteriores pode ser usado (ex.: variáveis inline, introduzidas no 10.3 Rio). |
| RNF-02 | **Plataforma:** executa localmente em Windows (Win32), sem serviços adicionais além do executável Delphi e, para testes, Node.js. |
| RNF-03 | **Sem dependências desnecessárias:** sem banco de dados, sem componentes Delphi de terceiros além do Indy que acompanha o Berlin, sem frameworks de front-end e sem bundlers. No projeto de testes, as únicas dependências são Playwright e TypeScript. |
| RNF-04 | **Rede:** o servidor escuta, por padrão, em `0.0.0.0` (todas as interfaces IPv4: o próprio computador e a rede local), em porta configurável (padrão definido no plano). A opção `--bind <IPv4>` escolhe o endereço; `--bind 127.0.0.1` restringe ao próprio computador. *(Alterado em 2026-10-16, Entrega O2 do modo online, por decisão do usuário (DO-09 de `docs/spec-online.md`): a versão 0.5 exigia somente `127.0.0.1`.)* |
| RNF-05 | **Mesma origem:** o próprio servidor Delphi entrega os arquivos da interface e a API, sem configuração de CORS *(premissa — ver D-06)*. |
| RNF-06 | **Concorrência:** como o `TIdHTTPServer` atende cada conexão em uma thread, todo acesso ao estado da partida é serializado com `TCriticalSection`. |
| RNF-07 | **Separação de responsabilidades:** a lógica do jogo fica em uma unit Delphi independente do Indy, do JSON e da UI, e pode ser verificada isoladamente. |
| RNF-08 | **Codificação:** respostas em UTF-8 com `Content-Type` correto para HTML, CSS, JS e JSON. No Indy do Berlin, o corpo da resposta é gerado explicitamente como bytes UTF-8 (não depender da codificação padrão do Indy), e o corpo das requisições é decodificado como UTF-8. Arquivos-fonte com textos acentuados são salvos em UTF-8. |
| RNF-09 | **Desempenho (meta, não verificada automaticamente):** requisições locais respondem em menos de 200 ms. |
| RNF-10 | **Testabilidade:** os testes rodam contra a aplicação real iniciada, pelo navegador ou por HTTP direto ao backend real; nenhum teste substitui respostas do backend por respostas falsas. Antes de cada teste, a partida é reiniciada pela própria API. Como o estado é global (RN-13), a suíte roda **em série**, com um único worker. |
| RNF-11 | **Reprodutibilidade:** o repositório contém instruções para compilar o backend, iniciar o servidor e executar os testes a partir de um clone limpo. |
| RNF-12 | **Encerramento limpo:** o servidor encerra com Ctrl+C ou quando o processo é finalizado pelo Playwright, sem deixar a porta presa e sem exceções não tratadas. |
| RNF-14 | **Verificação de saúde:** `GET /health` responde 200 com o JSON `{"status":"ok"}`, sem ler nem alterar o estado da partida. É o sinal usado pelos testes e pelos scripts para saber que o servidor está pronto. |
| RNF-13 | **Rastreabilidade:** cada teste referencia o(s) critério(s) de aceitação (CA-xx) que cobre no próprio título. |

## 10. Dúvidas técnicas e premissas a confirmar

Até serem respondidas, a especificação adota a **premissa** indicada. Qualquer mudança será registrada na seção 11.

| ID | Dúvida | Premissa adotada |
|---|---|---|
| D-01 | Quem inicia cada partida? | Sempre X. |
| D-02 | Qual edição do Delphi Berlin está instalada (Starter, Professional, Enterprise)? Afeta a compilação por linha de comando. | Professional ou superior, com MSBuild/`dcc32`. |
| D-03 | Uma partida única global é aceitável? | Sim. |
| D-04 | "Nova partida" no meio do jogo pede confirmação? | Não. |
| D-05 | Aplicação console ou VCL? | Console. |
| D-06 | O servidor Delphi serve também os arquivos da interface? | Sim. |
| D-07 | Porta padrão. | 8765, configurável. |
| D-08 | Versão do Node.js e do Windows. O Playwright atual exige Node 22, 24 ou 26 e Windows 11 ou Windows Server 2019+. | Ambiente atende; caso contrário, fixar uma versão anterior do Playwright (ver plano). |
| D-09 | Os testes iniciam o servidor automaticamente? | Sim, via `webServer` do Playwright, usando o executável já compilado. |
| D-10 | Destaque das células vencedoras está no escopo? | Sim. |
| D-11 | Testes unitários do motor em Delphi? | Sem framework: um pequeno programa console de verificação do motor (ver plano). DUnitX fica opcional. |
| D-12 | O CA-22 simula a falha de rede no navegador (interceptando requisições com `page.route`). Isso simula a indisponibilidade, não respostas do backend. É aceitável? | Sim. Alternativa: teste manual documentado. |

## 11. Registro de alterações

| Versão | Data | Alteração |
|---|---|---|
| 0.1 | 2026-10-15 | Criação da especificação inicial a partir dos requisitos do projeto. |
| 0.2 | 2026-10-15 | Revisão antes do plano técnico: (1) nova RN-15 com a ordem de validação; (2) vitória com duas combinações: "linha vencedora" virou "células vencedoras" (4.2, RN-08, CI-05) e novo CA-14; (3) jogador da vez e vencedor definidos com a partida encerrada (4.2); (4) RN-04 detalha posições inválidas; RN-07 diz que campos extras são ignorados; RN-10 deixou de repetir a RN-06; RN-13 declara que abas não se sincronizam; (5) conflito CI-07 × CE-02 resolvido: a UI sempre envia o clique e o backend rejeita; (6) textos exatos de status e de falha de comunicação; CI-09 define quando a mensagem some; (7) critérios renumerados (CA-01 a CA-26), com as 8 combinações cobertas e novos critérios para corpo malformado, símbolo imposto, empate pela UI, mensagem que some, servidor inacessível, abas, concorrência e protocolo HTTP; todas as sequências verificadas por script; (8) RNF-08 com a armadilha de UTF-8 do Indy; RNF-10 exige execução em série e proíbe respostas falsas; RNF-03 cita o Indy; RNF-09 virou meta; (9) diagrama de estados refeito; (10) novas dúvidas D-08 (Windows) e D-12; D-07 fixada em 8765. |
| 0.3 | 2026-10-15 | Ajustes vindos do plano de testes: RN-04 inclui booleano e diferencia maiúsculas no nome do campo; RN-15 e CE-04/CA-06 tratam JSON que não é objeto (`[4]`, `4`) como corpo inválido. Nenhuma mudança de escopo. |
| 0.4 | 2026-10-15 | Consistência antes da implementação: incluído o endpoint `GET /health` (escopo 2.1, RNF-14, CA-27), pedido para a primeira entrega do servidor. Não altera nenhuma regra do jogo. |
| 0.5 | 2026-10-15 | Entrega 5 (interface): CI-10 ganhou tempo-limite de 8 s, o botão "Tentar novamente" e o caso de falha no carregamento inicial; novos CI-12 (carregamento), CI-13 (uma requisição por vez), CI-14 (acessibilidade e teclado), CI-15 (responsividade) e CI-16 (aparência de X/O e do jogador da vez); CA-22 inclui a recuperação; novos CA-28 a CA-32. Nenhuma mudança na API nem nas regras. |
| 0.6 | 2026-10-16 | Entrega O2 do modo online: RNF-04 alinhada ao endereço de escuta em uso (`0.0.0.0` por padrão, para jogar pela rede local; `--bind 127.0.0.1` restringe ao computador). Decisão DO-09 em `docs/spec-online.md`; detalhes em `docs/plan-online.md` (DTO-16, MC-01). Nenhuma regra do jogo nem contrato da API mudou. |
