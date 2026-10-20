# Prova de conceito — WebSocket no Indy do Delphi Berlin (Entrega O0)

**Descartável.** Esta pasta existe só para verificar, antes de qualquer código de produção, se o `TIdHTTPServer` do Indy 10.6.2.5341 (que acompanha o Delphi 10.1 Berlin) consegue assumir uma conexão HTTP e manter uma sessão WebSocket confiável (`docs/plan-online.md`, seção 3.1 e Entrega O0).

Não faz parte do jogo:
- nada aqui é compilado pelo `scripts\build.cmd`;
- nenhum arquivo do servidor, da interface, dos testes, dos scripts ou dos documentos antigos é alterado;
- não há salas, interface multiplayer nem mudança nas rotas atuais;
- o servidor escuta só em `127.0.0.1` (nada é exposto à rede);
- nenhuma dependência é instalada: o cliente WebSocket é o nativo do Node e o navegador é o Chromium do Playwright já instalado em `tests\`.

## Como executar

Dê dois cliques em `spikes\ws-indy\validate-o0.cmd` (ou execute-o num prompt). Leva de 2 a 3 minutos. O resultado fica em `logs\online-o0.log`, e os logs de cada servidor ficam em `logs\online-o0\`.

As portas 8790, 8791 e 8792 precisam estar livres.

## Conteúdo

| Arquivo | Papel |
|---|---|
| `WsSpike.dpr` | Programa console: `--selftest` (autoteste sem rede) ou servidor (`--port`, `--idle-seconds`) |
| `src/uWsCodec.pas` | Handshake e quadros WebSocket (RFC 6455) sobre `TBytes`, sem Indy |
| `src/uWsSelfTest.pas` | Autoteste: aceite da RFC pela RTL e pelo Indy, quadros, fragmentos, limites, UTF-8 |
| `src/uWsSpikeServer.pas` | `TIdHTTPServer` com a mesma configuração do jogo; rota `/ws` com resposta 101 escrita diretamente; sessão dentro do `OnCommandGet`; caixa de saída por canal |
| `src/uSpikeLog.pas` | Log em UTF-8 e relógio monotônico |
| `page.html` | Página mínima para o teste no Chromium |
| `client/ws-tests.mjs` | Testes sem navegador: suítes `basic`, `idle`, `load`, `hold` |
| `client/browser-test.cjs` | Teste com dois navegadores Chromium isolados e queda simulada (`routeWebSocket`) |
| `tools/send-ctrl-c.ps1` | Envia um Ctrl+C real ao console do servidor |
| `validate-o0.ps1` / `.cmd` | Validação completa, com log |

## Protocolo de teste (só desta prova de conceito)

- Ao abrir, o servidor envia `ola:<id>`.
- `todos:<texto>`: os outros canais recebem `de:<id>:<texto>`; quem enviou recebe `enviado:<n>`.
- `fechar`: o servidor fecha com 1000.
- Qualquer outro texto: `eco:<texto>`.
- `POST /push` com um texto no corpo: todos os canais recebem `push:<texto>`. O envio parte da thread da requisição HTTP, ou seja, de outra thread.
- `GET /stats`: `{"ativas":n,"abertas":n,"fechadas":n,"erros":n}`.

## Verificações (ver `logs\online-o0.log`)

| ID | O que prova | Critério do plano |
|---|---|---|
| A-01 | Node com `WebSocket` nativo e Playwright já instalado | E0-03 |
| E0-01a/b/c | Compila sem warnings; aceite da RFC pela RTL e pelo Indy; versão do Indy compilada | E0-01 |
| E0-03/E0-09 #1..3 | Handshake, 2 clientes simultâneos, envio de outra thread (< 200 ms), fragmentos, UTF-8 inválido, binário, sem máscara, limite de 4 KB, aberturas inválidas, fechamentos, queda abrupta; repetidos 3 vezes | E0-03, E0-04, E0-05 e mensagens inválidas |
| E0-02/E0-08 #1..2 | Dois navegadores Chromium; fechar a página; queda simulada com `routeWebSocket`; repetidos 2 vezes | E0-02, E0-04, E0-05, E0-08 |
| E0-06 | 50 canais por 30 s, sem perdas | E0-06 |
| E0-05b | Inatividade: cliente calado recebe 4408 | E0-05 |
| E0-07a/b/c/d | Encerramento pelo evento e por Ctrl+C real com 20 canais (todos recebem 1001, saída 0 em até 5 s); porta liberada | E0-07 |
| E0-11 | Arquivos de produção idênticos antes e depois (SHA-256) | escopo da O0 |
| E0-12 | Logs sem erros inesperados; todo canal aberto foi fechado | — |

A suíte do jogo (109 testes Playwright e 27 casos do EngineCheck) **não** é executada aqui, e o log diz isso explicitamente.
