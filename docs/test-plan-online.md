# Plano de testes — Jogo da Velha Multiplayer Online

| Campo | Valor |
|---|---|
| Versão | 0.9 |
| Data | 2026-10-20 |
| Etapa SDD | 3 — Testes (definição, modo online) |
| Base | `docs/spec-online.md` v0.3 e `docs/plan-online.md` v0.9; continua valendo `docs/test-plan.md` v0.9 para o modo local |
| Status | **Em execução.** Testes das Entregas O1 (SL, SC, RJ, MEM), O2 (OP-01, OA-01 a OA-09, OR-01 a OR-18) O3 (OP-02, WS, HB, OA-10, OA-11, OW-01 a OW-19, OV-05, Ctrl+C do OV-04) e O4 (OA-12, OU-01 a OU-27, OV-10) O5 (JN-01, JN-02, OV-01 a OV-04, OV-11, OV-12, OU-28) e O6 (RL-01 a RL-05, OP-03, OV-06a a OV-07, OV-09, OV-13 a OV-17) e O7 (OV-18, checklist MV-L) escritos e executados; resultados em `docs/delivery-log.md`. |

---

## 1. Objetivo

Definir, antes de qualquer implementação, os cenários que provam que o modo online atende a `docs/spec-online.md`, os critérios de aprovação de cada cenário e da suíte, e as sabotagens que provam que os testes detectam defeitos reais.

Como no plano de testes atual, cada teste cita no título o cenário e o critério, por exemplo: `OR-02 [CAO-16] jogada fora da vez é recusada`.

## 2. Grupos

| Grupo | O que prova | Ferramenta | Contra o quê | Local |
|---|---|---|---|---|
| **SL — Sala** | Regras da sala, lugares, tokens, versão, ciclo de vida | `EngineCheck.exe` | Units `uRoom`, `uRoomRegistry` | `server/tests/uRoomTests.pas` |
| **SC — Concorrência da sala** | Seções críticas por sala e do registro | `EngineCheck.exe` (threads) | Idem | `server/tests/uRoomConcurrencyTests.pas` |
| **RJ — JSON da sala** | Formato exato da sala e das mensagens; leitura das mensagens do cliente | `EngineCheck.exe` | `uRoomJson` | `server/tests/uRoomJsonTests.pas` |
| **WS — Protocolo** | Handshake, quadros, limites (RFC 6455) | `EngineCheck.exe` | `uWebSocket` (sem rede) | `server/tests/uWebSocketTests.pas` |
| **HB — Hub** | Inscrições, isolamento, substituição, caixa de saída | `EngineCheck.exe` | `uRoomHub` com assinantes de teste | `server/tests/uRoomHubTests.pas` |
| **OP — Opções** | Linha de comando | `EngineCheck.exe` | `uServerOptions` | `server/tests/uOptionsTests.pas` |
| **MEM — Memória** | Nenhum vazamento após os grupos acima | `EngineCheck.exe` (`ReportMemoryLeaksOnShutdown`) | — | `EngineCheck.dpr` |
| **OA — API de salas** | Contrato REST: códigos, cabeçalhos, formato, rotas | Playwright `request` | `TicTacToeServer.exe` real | `tests/online/room-api/*.spec.ts` (ver nota da v0.4) |
| **OR — Regras online** | Regras aplicadas pelo servidor em execução, isolamento, concorrência | Playwright `request` | `.exe` real | `tests/online/room-rules/*.spec.ts` (ver nota da v0.4) |
| **OW — Canal** | Protocolo do canal: abertura, mensagens, notificações, fechamento | `WebSocket` nativo do Node 24 + `node:net` | `.exe` real | `tests/online/ws/*.spec.ts` |
| **OV — Ciclo de vida e segurança** | Reinício, abandono, desligamento, origem, limites, modo público, endereço | Playwright + servidor dedicado | `.exe` real em outra porta | `tests/online/lifecycle/*.spec.ts` e scripts |
| **OU — Interface online** | O que os jogadores veem e fazem, em navegadores isolados | Playwright + Chromium | `online.html` servida pelo `.exe` real | `tests/online/ui/*.spec.ts` |
| **MV — Validação manual** | Rede local real (celular, Firefox, leitor de tela) e, depois, a publicação (HTTPS, outra rede) | Checklist | Computador na rede local (MV-L, O7); ambiente publicado (MV-P, O8) | registro nas Entregas O7 e O8 |

Ordem de execução: **EngineCheck (M, SV, J, SL, SC, RJ, WS, HB, OP, MEM) → suíte atual (A, R, U) → OA → OR → OW → OU → OV**. Se o `EngineCheck` falha, o resto não roda.

### 2.1 Cobertura por camada

| Assunto | EngineCheck (sem rede) | Playwright (servidor real) |
|---|---|---|
| Código e token | SL-01, SL-02 | OA-01, OA-02 |
| Entrar, cheia, reentrada | SL-03 | OA-04, OA-05, OR-14, OU-03, OU-04, OU-12 |
| Validação e precedência | SL-04, SL-05, SL-07 | OR-01 a OR-08 |
| Regras completas do jogo numa sala | — (o motor já tem M-01 a M-12) | OR-09 |
| Isolamento | SL-06, SC-02, HB-02 | OR-10, OR-13, OW-07 |
| Nova partida e saída | SL-08, SL-10 | OR-11 a OR-13, OR-15, OU-14, OU-19 |
| Presença e lugar reservado | SL-09 | OW-12, OW-13, OW-17, OU-15 |
| Abandono e período de lembrança | SL-11 (relógio manual) | OV-02, OV-03 |
| Concorrência | SC-01, SC-02 | OR-16 a OR-18 |
| JSON e mensagens | RJ-01 a RJ-03 | OA-01, OA-03, OA-08, OW-03 a OW-09 |
| Protocolo WebSocket | WS-01 a WS-06 | OW-01, OW-02, OW-16 |
| Tempo real na tela | — | OU-06 a OU-08, OU-11, OU-16, OU-22 |
| Interface não decide | — | OU-09 a OU-11, OW-09 |
| Reinício e desligamento | — | OV-01, OV-04, OU-23 |
| Segurança e limites | SL-12, WS-05, WS-07 (origem) | OA-09, OA-10, OV-05 a OV-07, OV-09, OU-24 |
| Rede local pelo IP | — | OV-10 |

## 3. Como provar que o servidor é a autoridade e que a sincronização é real

1. **OR não usa navegador nem canal.** Todas as regras online (vez, ocupada, encerrada, sem oponente, token, precedência, nova partida, isolamento, concorrência) são verificadas só por HTTP.
2. **A interface não filtra cliques.** Em OU-10 (fora da vez) e nos cliques após o fim, o teste espera o `POST …/moves` com `page.waitForResponse` e confere o 409. A recusa vem do servidor.
3. **A interface espera o servidor.** No OU-09 a resposta real é atrasada em 1 s e a célula precisa continuar vazia durante o atraso (SB-09 prova que o teste detecta o contrário).
4. **Estado montado fora da interface.** No OU-11, as jogadas de uma partida inteira são feitas pela API, com os tokens dos dois jogadores, e as duas páginas precisam mostrar o resultado sem clique algum.
5. **A sincronização é por notificação, não por recarga.** Nos testes de tempo real (OU-06, OU-08, OU-16), a página do outro jogador não é recarregada nem clicada; a fixture conta as requisições `GET /api/rooms/…` da página e exige que **nenhuma** aconteça entre a jogada e a atualização. A SB-11 (hub mudo) precisa derrubar esses testes.
6. **Verificação cruzada automática.** No fim de todo teste OU, cada página aberta é comparada com `GET /api/rooms/{código}`: tabuleiro, células vencedoras, status (calculado pelo lugar daquela página), presença do oponente e `data-version` igual à versão do servidor.
7. **Mensagens forjadas.** No OW-09, um cliente identificado envia mensagens que tentam jogar ou impor um estado; o canal é fechado e a sala não muda.
8. **Sabotagens** (seção 9) para cada propriedade central.

Nenhum teste fabrica respostas do servidor. As únicas intervenções de rede, todas sobre conexões reais, são: **atrasar** uma resposta (`page.route` + `route.continue()` depois da espera); **derrubar** o canal (`page.routeWebSocket` com `connectToServer()`, depois `close()`), como a D-12 do modo local; e **parar** o processo do servidor dedicado.

## 4. Infraestrutura comum

| Item | Definição |
|---|---|
| Servidor da suíte | O mesmo `webServer` atual (`TicTacToeServer.exe --port 8765`), com os padrões do modo local. Os testes de sala não tocam na partida global, então podem rodar na mesma execução dos testes atuais. |
| Servidor dedicado (DTO-15) | `support/online/server-process.ts`: inicia `..\server\bin\TicTacToeServer.exe` com `--port` próprio (8770 em diante) e as opções do teste; espera `GET /health`; guarda stdout/stderr em `test-results/`; encerra o processo no fim. Usado por OV-xx, OU-23, OW-10 e OW-13. |
| Execução | `workers: 1`, `fullyParallel: false`, `retries: 0`, `forbidOnly: true` (sem mudança). |
| Isolamento | Cada teste cria as próprias salas, então a ordem de execução não altera os resultados. O fixture `game` atual continua reiniciando a partida local antes dos testes dela. |
| `RoomApi` (`support/online/rooms.ts`) | `create()`, `get(code)`, `join(code, token?)`, `move(code, token, pos)`, `reset(code, token)`, `leave(code, token)`, `raw(method, path, {body, headers})`, `expectUnchanged(code, ação)` (sala idêntica, versão incluída, antes e depois), `expectError(res, http, codigo)` (mensagem exata e UTF-8 estrito, como `expectError` atual), `playSequence(code, tX, tO, seq)` (usa `support/sequences.ts`) |
| `WsClient` (`support/online/ws-client.ts`) | Sobre o `WebSocket` global do Node: `open(origin?)`, `enter(code, token)`, `next(pred, timeout)`, `expectSilence(ms)`, `closed()` → `{code, reason}`, `messages` (todas as recebidas, com horário). Para pedidos inválidos e quadros malformados, `support/online/raw-ws.ts` usa `node:net`. |
| `Players` (`support/online/players.ts`) | Cria contextos isolados do Chromium (`browser.newContext()`): cada um é um "navegador" com o próprio `localStorage`. `twoPlayers()` → A cria, B entra pelo link; devolve `{a, b, code}` com objetos `OnlineUi`. |
| `OnlineUi` (`support/online/online-ui.ts`) | Ações (`create`, `joinByCode`, `openLink`, `click(i)` que espera o `POST`), leituras (`cell`, `status`, `opponent`, `connection`, `version`); registra erros de console, exceções, requisições que falharam (salvo as provocadas), respostas 404/5xx inesperadas, requisições `GET /api/rooms` (item 5 da seção 3) e **todas as URLs** de página e de requisição (para OU-24). |
| Verificação cruzada | Seção 3, item 6, no fim de todo teste OU. |
| Mensagens | As de `docs/plan-online.md` 6.6, comparadas por igualdade exata, com acentos. |
| Esperas | Só asserções que esperam condições (`toHaveText`, `toHaveAttribute`, `expect.poll`, `next(pred)`); nenhum `waitForTimeout`, salvo o `expectSilence` (que verifica ausência de mensagens por um intervalo definido). |
| Latência | No OU-06, o teste registra, para cada uma das 9 jogadas, o tempo entre a resposta do `POST` na página de quem jogou e a mudança da célula na página do outro; anexa os valores e o percentil 95 ao relatório (`test.info().annotations`). |

## 5. Grupos do EngineCheck (sem rede)

Mesmas convenções da seção 9.1 de `docs/test-plan.md`: um caso por função, isolado, com asserções "suaves", comparação do estado inteiro (`TRoomSnapshot`) e "antes = depois" em toda recusa. O relógio é um `TManualClock` e o gerador aleatório pode ser um `TScriptedRandom` (sequência de bytes definida pelo teste).

| ID | Caso | CAO |
|---|---|---|
| SL-01 | Criar: código com 6 caracteres do alfabeto; X ocupado com token de 32 hex; O livre; `rsWaiting`; versão 1; número da partida 1; partida igual ao estado inicial do motor | CAO-01 |
| SL-02 | Unicidade: com `TScriptedRandom` repetindo o código de uma sala ativa e depois o de uma sala lembrada, o registro gera outro código nos dois casos; 10.000 salas criadas têm códigos distintos | CAO-02 |
| SL-03 | Entrar: O ocupado, token diferente do de X, `rsPlaying`, versão 2; terceiro → `rrFull` sem mudar a sala; reentrada com o token de O → mesmo lugar e mesmo token, versão inalterada; reentrada com o token de X → X | CAO-04, CAO-06, CAO-29 |
| SL-04 | Validação: para cada linha da tabela de precedência do OR-08 (mesmos dados), o `TRoomResult` esperado e a sala inalterada | CAO-16 a CAO-19, CAO-22 |
| SL-05 | Jogada aceita grava o símbolo do lugar autenticado, versão +1, `Changed = True`; toda recusa tem `Changed = False` e o mesmo `TRoomSnapshot` | CAO-07 |
| SL-06 | Isolamento: em S1 e S2, uma partida completa e uma nova partida em S1 deixam S2 idêntica | CAO-09, CAO-41 |
| SL-07 | Tokens: vazio, 31 ou 33 caracteres, maiúsculas e o token de outra sala → `rrInvalidToken` em `Play`, `NewGame`, `Leave` e `Attach` | CAO-11, CAO-20 |
| SL-08 | Nova partida: com a partida em andamento → `rrGameInProgress`; aguardando oponente → `rrWaitingOpponent`; após vitória e após empate → estado inicial, X começa, número da partida +1, lugares iguais | CAO-39, CAO-40 |
| SL-09 | Presença: `Attach` marca conectado e incrementa a versão; `Attach` do mesmo lugar com outro canal devolve o anterior sem incrementar; `Detach` do canal substituído não muda nada; `Detach` do atual marca desconectado; com O desconectado na vez dele, X recebe `rrNotYourTurn` e um terceiro recebe `rrFull` | CAO-32, CAO-36, CAO-37 |
| SL-10 | Saída: `Leave` → `rsClosed`, motivo `SAIDA`; depois disso, toda operação → `rrClosed`; o registro passa a sala para "lembradas" | CAO-31 |
| SL-11 | Abandono: sem conexões, `Sweep` antes do TTL não encerra; depois do TTL encerra com `ABANDONO`; sala com um lugar conectado nunca é encerrada; depois do período de lembrança, `Find` → `rrNotFound` | CAO-38 |
| SL-12 | Capacidade: com limite 3, a 4ª criação → `rrCapacity`; após encerrar uma, a criação volta a funcionar | CAO-53 |
| SC-01 | 8 threads × 2.000 operações numa mesma sala (jogadas de X e O com os tokens certos e errados, consultas, novas partidas); toda resposta coerente; versões observadas por cada thread estritamente crescentes; nº de jogadas aceitas = soma das células preenchidas a cada partida; nenhuma exceção | CAO-23, CAO-24 |
| SC-02 | 16 threads em 50 salas, criando, entrando, jogando e encerrando, com o faxineiro rodando a cada 1 ms; nenhuma sala tem símbolo de outra; nenhuma exceção; nenhum impasse (o caso termina em até 30 s) | CAO-09, CAO-25 |
| RJ-01 | `RoomToJson` de quatro salas (aguardando, em jogo, vitória dupla, encerrada por saída) gera exatamente o JSON de `docs/plan-online.md` 6.2, com campos e ordem; `partida` é idêntica, byte a byte, a `SnapshotToJson` do mesmo estado; nenhum token no texto | CAO-01, CAO-44 |
| RJ-02 | Mensagens do servidor (`bem_vindo`, `estado` com cada motivo, `pong`, `sala_encerrada`, `erro`) exatas | CAO-15 |
| RJ-03 | Leitura das mensagens do cliente: `entrar` e `ping` válidos; inválidas: tipo `jogada`, tipo `estado`, `entrar` sem token, `protocolo` 2, `id` texto, `[1]`, `"x"`, `{}`, JSON malformado, UTF-8 inválido | CAO-28 |
| WS-01 | Chave de aceite do exemplo da RFC 6455 (`dGhlIHNhbXBsZSBub25jZQ==` → `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`) e de mais duas chaves conferidas por script | CAO-45 |
| WS-02 | Validação do pedido de abertura: válido; sem `Upgrade`; `Connection: keep-alive, Upgrade` (válido); chave com 15 bytes; versão 8 (→ 426); quando a política de origem recusa, a resposta é 403 (a política em si é testada no WS-07) | CAO-45 |
| WS-03 | Decodificar quadros com máscara: texto de 5 bytes; 126 bytes (tamanho de 16 bits); 70.000 bytes (64 bits, recusado pelo limite); entrega em pedaços de 1 byte; quadro sem máscara → 1002; opcode 3 → 1002; bit RSV1 → 1002 | CAO-52 |
| WS-04 | Fragmentação: texto em 3 fragmentos com um *ping* no meio → uma mensagem e um *pong*; continuação sem início → 1002; novo início antes do fim → 1002 | CAO-15 |
| WS-05 | Limites: mensagem remontada de 4.097 bytes → 1009; controle com 126 bytes → 1002; texto com UTF-8 inválido → 1007 | CAO-52 |
| WS-06 | Codificar: texto sem máscara com FIN nos três tamanhos; *close* com código e motivo acentuado; *pong* ecoa o conteúdo do *ping* | CAO-15 |
| WS-07 | Política de origem (`uOriginPolicy`), com a lista montada a partir de opções e de IPs de teste (`127.0.0.1`, `192.168.0.10`, `10.1.2.3`, `8.8.8.8`, `169.254.1.1`): os casos OG-01 a OG-19 de `docs/plan-online.md` 7.7 com o resultado indicado; IPs não privados e de *link-local* fora da lista automática; bind específico (`192.168.0.10`) gera só esse IP, e bind `127.0.0.1` só o loopback; modo público com e sem `https`; `--allowed-origin` inválido (com caminho, sem esquema, `ftp://`, porta 0) → erro de opção | CAO-51 |
| HB-01 | Caixa de saída: três `estado` seguidos sem envio → só o último é entregue; `pong` e `erro` não são descartados nem reordenados; `sala_encerrada` marca fechamento; fila cheia → sinal de fechamento 1008 | CAO-15 |
| HB-02 | Hub: assinante de S2 não recebe publicações de S1; inscrição do mesmo lugar devolve o assinante anterior; cancelar a inscrição do substituído não remove o atual | CAO-10, CAO-36 |
| HB-03 | *(v0.5, novo)* 8 threads publicando 2.000 estados cada, uma por sala (8 salas, um inscrito por sala), enquanto as caixas são esvaziadas ao mesmo tempo: cada caixa só tem estados da sua sala, as versões entregues são crescentes, a última é 2.000 e nenhuma caixa estoura (os estados são aglutinados) | CAO-10, CAO-25 |
| OP-01 | Opções: sem argumentos → bind `0.0.0.0` e os padrões da seção 11.4 do plano; `--bind 127.0.0.1`; `--public` sem `--bind` → `127.0.0.1`; `--public --bind 0.0.0.0` → `0.0.0.0`; valores inválidos (porta 0, TTL negativo, IP malformado, opção sem valor) → erro | CAO-46 |
| OP-02 | *(v0.5, novo)* Opções do canal e da origem: `--allowed-origin` (repetida, com vírgula, normalizada; inválida com caminho, sem esquema, `ftp://`, porta 0), `--ws-hello-seconds` (1..300) e `--ws-idle-seconds` (2..3600); `--public` sem `--allowed-origin` ou com origem `http` → erro (`ValidateServerOptions`). O OP-01 da O2 continua idêntico | CAO-46, CAO-51 |
| MEM-01 | Ao fim do `EngineCheck`, `ReportMemoryLeaksOnShutdown` não registra vazamentos (o script verifica que não há o aviso do FastMM) | — (risco R-10) |
| JN-01 | *(v0.7, novo)* Faxineiro com relógio manual (prazo 2 s, lembrança 3 s, intervalo 10 ms): a sala desconectada só é encerrada depois do prazo, contado da última desconexão; a sala com alguém conectado nunca é encerrada; a encerrada recusa entrar, jogar, nova partida, sair e identificar-se (`rrClosed`); cada sala é informada uma única vez; é esquecida (`rrNotFound`) depois da lembrança; uma sala nova tem código e tokens novos, e os tokens antigos não valem nela; depois de `Stop`, nada mais é varrido nem informado; `Stop` duas vezes não faz nada; com intervalo de 60 s, `Stop` leva menos de 1 s | CAO-38, CAO-11 |
| JN-02 | *(v0.7, novo)* Faxineiro a cada 1 ms (prazo 5 ms, lembrança 50 ms) com 8 threads criando 150 salas cada, conectando, jogando e desconectando: nenhuma operação recebe `rrClosed` com um lugar conectado; nenhum instantâneo incoerente; nenhuma sala informada duas vezes nem depois de `Stop`; nenhum erro no faxineiro; houve encerramentos | CAO-38, CAO-25 |
| RL-01 | *(v0.8, novo)* Taxa por cliente com relógio manual (limite 3, janela 60 s): três tentativas aceitas (abaixo e no limite), a quarta recusada com `Retry-After` 60; no meio da janela 30 (arredondado para cima); 1 ms antes do fim 1; no fim, janela nova; outro cliente independente; limite 0 nunca recusa e não guarda nada; teto de 2 clientes: o terceiro é recusado até as janelas vencerem | CAO-53 |
| RL-02 | *(v0.8, novo)* Canais simultâneos por cliente (limite 2): abaixo, no limite e acima; soltar libera; soltar a mais não fica negativo; limite 0 desligado; 8 threads × 5.000 tentativas com limite 3 nunca passam de 3 ao mesmo tempo e a contagem volta a zero | CAO-53 |
| RL-03 | *(v0.8, novo)* Corpo com teto (`TCappedStream`): anotar 1 TB como tamanho não aloca nada; o que passa do teto é contado e descartado; leitura e posição só no que foi guardado; 1.000 KB recebidos, 64 KB guardados | CAO-52 |
| RL-04 | *(v0.8, novo)* Mensagens por canal numa janela de 10 s (limite 3): três aceitas, a quarta recusada, de novo aceitas na janela seguinte; limite 0 desligado | CAO-52 |
| RL-05 | *(v0.8, novo)* Cliente atrás de proxy: `X-Forwarded-For` ignorado fora do loopback e sem `--trust-proxy`; com os dois, vale o último endereço (inclusive com dois cabeçalhos); último inválido ou com zeros à esquerda → o IP da conexão. Taxa de cada rota (B5): criação, consulta (GET/HEAD da sala, mesmo inexistente), entrada, canal; jogada, nova partida, saída, `/health` e `/api/game` sem taxa. Texto seguro para o log | CAO-53 |
| OP-03 | *(v0.8, novo)* Opções da O6: padrões local (0, 60 s, 30 s) e público (10/30/30, 8 canais, 30 mensagens); valor explícito vence o padrão do modo; máximos aceitos; negativos, acima do máximo, não numéricos, sem valor, janela ou prazo 0 e `--trust-proxy` com valor recusados | CAO-46, CAO-53 |

## 6. Grupo OA — API de salas

Pré-condição comum: servidor da suíte iniciado.

| ID | Cenário | Ações | Esperado | CAO |
|---|---|---|---|---|
| OA-01 | Criar sala | `POST /api/rooms` (sem corpo e com `{"x":1}`) | 201; `Location: /api/rooms/<código>`; `content-type` `application/json; charset=utf-8`; `cache-control` `no-store`; corpo com exatamente `sala` e `jogador`; `sala` igual ao modelo de 6.2 (aguardando, versão 1, partida inicial); `jogador.simbolo = "X"`; `token` casa `^[0-9a-f]{32}$` | CAO-01 |
| OA-02 | Mil códigos distintos | 1.000 criações em sequência | 1.000 códigos distintos, todos casando `^[2-9A-HJKMNP-Z]{6}$` | CAO-02 |
| OA-03 | Consultar | `GET` e `HEAD /api/rooms/{c}` (aguardando e em jogo) | 200; corpo `{sala}` igual ao da última resposta; o texto do corpo não contém nenhum dos dois tokens; `HEAD` sem corpo (socket cru, como `rawHead`) com o mesmo `content-type` | CAO-45, CAO-54 |
| OA-04 | Entrar | `POST /api/rooms/{c minúsculo}/players` | 201; `simbolo = "O"`; token diferente do de X; `situacao = "EM_JOGO"`; `versao = 2` | CAO-04 |
| OA-05 | Reentrada | depois do OA-04, `POST …/players` com `Authorization` de O; depois com o de X | 200 com o mesmo lugar e o mesmo token em cada caso; sala inalterada | CAO-06 |
| OA-06 | Rotas e métodos | `GET /api/rooms` → 405 `Allow: POST`; `POST`/`DELETE /api/rooms/{c}` → 405 `GET, HEAD`; `GET …/moves`, `…/reset`, `…/leave`, `…/players` → 405 `POST`; `GET /api/rooms/{c}/x`, `/api/rooms/`, `/api/rooms/{c}/` → 404 `ROTA_NAO_ENCONTRADA`; `POST /ws` → 405 `GET` (este último na O3, com a rota `/ws`) | códigos, `Allow` e corpo de erro exatos; salas inalteradas | CAO-45 |
| OA-07 | Códigos inválidos | `abc`, `K7PM2`, `K7PM2Q0`, `K7PM2I` (letra fora do alfabeto), `..%2Fx`, um código válido nunca criado; em `GET`, `players`, `moves`, `reset`, `leave` | 404 `SALA_INEXISTENTE` com a mensagem exata em todos | CAO-30 |
| OA-08 | Mensagens em UTF-8 | provocar cada erro novo de 6.6 alcançável pela API | mensagem exata; corpo decodificado com `TextDecoder('utf-8', {fatal: true})` | CAO-45 |
| OA-09 | Corpo grande | `POST …/moves` com 1.025 bytes (JSON válido com espaços) e `POST /api/rooms` com 2 KB | 413 `CORPO_MUITO_GRANDE`; sala inalterada; com 1.024 bytes, a jogada é aceita | CAO-52 |
| OA-10 | Origem nas rotas de sala | `POST /api/rooms` e `POST …/moves` com `Origin: http://atacante.test:8765` (e `Host` igual); com `Origin: http://127.0.0.1:<porta>`; sem `Origin`; e `POST /api/game/moves` (modo local) com `Origin: http://atacante.test:8765` | 403 `ORIGEM_NAO_PERMITIDA` e sala inalterada; 201/200; 201/200; a rota local responde como hoje (200), sem verificação de origem | CAO-51, CAO-44 |
| OA-11 | *(v0.5, novo; ressalva da O2)* `Authorization` nas rotas antigas | `/health`, `GET /api/game`, `POST /api/game/reset`, `POST /api/game/moves` (válida, ocupada, inválida), `DELETE /api/game`, sem o cabeçalho e com 7 variantes (`Bearer` de 32 hex, curto e sem valor; `Basic` válido e inválido; `Negotiate`; texto solto) | respostas idênticas, em status e corpo, às respostas sem o cabeçalho; `HEAD /api/game` 200 | CAO-44 |
| OA-12 | *(v0.6, novo; MC-04 e MC-05)* Estáticos da interface online | `GET` e `HEAD` de `/online.html`, `/online.js`, `/online.css`; `POST` neles; `/online.htm`, `/online`, `/online.html/`, `/web/online.html`, `/online.js.map`; `GET /` | 200 com `text/html`, `text/javascript`, `text/css` (UTF-8) e `Cache-Control: no-cache`; `HEAD` sem corpo; `POST` 405 `GET, HEAD`; os outros 404; `online.html` usa `/style.css`, `/online.css` e `/online.js`; a página local tem o link "Jogar online" e continua com `/app.js` | CAO-44, CAO-45 |

## 7. Grupo OR — Regras online no servidor

Pré-condição comum: sala criada por X e com O dentro (salvo indicação), por `RoomApi`.

| ID | Cenário | Esperado | CAO |
|---|---|---|---|
| OR-01 | X joga em 0 com `{"posicao":0,"simbolo":"O","jogador":"O"}`; O joga em 4 | célula 0 = X, célula 4 = O; vez de X; versão +1 a cada jogada; resposta igual ao `GET` | CAO-07 |
| OR-02 | Na vez de X, O joga em 4 | 409 `VEZ_DO_OPONENTE`; sala inalterada | CAO-16 |
| OR-03 | X:0; O joga em 0 | 409 `CELULA_OCUPADA`; sala inalterada | CAO-17 |
| OR-04 | Após S-L1 (vitória de X) e, em outra sala, após S-EMP: X e O tentam jogar em células vazias e ocupadas | todas 409 `PARTIDA_ENCERRADA`; salas inalteradas | CAO-18 |
| OR-05 | Sala sem O: X joga em 0 | 409 `AGUARDANDO_OPONENTE`; sala inalterada | CAO-19 |
| OR-06 | Jogada sem `Authorization`; com `Basic …`; com 31 hex; com hex em maiúsculas; com token inexistente; com o token de X da sala S2 | todas 401 `TOKEN_INVALIDO`; S1 e S2 inalteradas | CAO-11, CAO-20 |
| OR-07 | Corpos e posições inválidos (subconjunto de A-04/A-05: vazio, `abc`, `[4]`, `4`, posição 9, -1, 4.5, `"4"`, `null`, `true`, ausente) | 400 `CORPO_INVALIDO` / `POSICAO_INVALIDA`; sala inalterada | CAO-21 |
| OR-08 | Tabela de precedência (abaixo) | o erro da primeira condição violada pela RNO-10 | CAO-22 |
| OR-09 | As 11 sequências de referência de `docs/test-plan.md` seção 5, cada uma numa sala, alternando os tokens de X e O | resultado, vencedor e células vencedoras iguais aos do modo local; jogadas aceitas = células preenchidas | CAO-13, CAO-18 |
| OR-10 | Partida completa em S1 com S2 em andamento; e `GET /api/game` antes e depois | S2 inalterada; partida local inalterada | CAO-09, CAO-44 |
| OR-11 | Após vitória, O pede nova partida; após empate, X pede | estado inicial, X começa, `numeroDaPartida` +1, lugares iguais; nova partida jogável | CAO-39 |
| OR-12 | Nova partida com X:0 (em andamento) e numa sala sem O | 409 `PARTIDA_EM_ANDAMENTO` / 409 `AGUARDANDO_OPONENTE`; sala inalterada | CAO-40 |
| OR-13 | S1 terminada e S2 com X:0, O:4; nova partida em S1 | S2 inalterada | CAO-41 |
| OR-14 | Terceiro cliente entra numa sala cheia | 409 `SALA_CHEIA`; sala inalterada | CAO-29 |
| OR-15 | O sai; depois: `GET`, entrar, jogar, nova partida e sair, com e sem token | `leave` 200 com `ENCERRADA` e motivo `SAIDA`; todas as seguintes 410 `SALA_ENCERRADA` | CAO-31 |
| OR-16 | 20 repetições: na vez de X, duas jogadas de X em 0 e 1 com `Promise.all` | exatamente uma 200 e uma 409 `VEZ_DO_OPONENTE`; um único X; vez de O; versão +1 | CAO-23 |
| OR-17 | 20 repetições: na vez de X, X joga em 0 e O joga em 1 ao mesmo tempo | X 200 em todas. O: 409 `VEZ_DO_OPONENTE` se a jogada dele foi tratada antes da de X (célula 1 vazia, versão +1), ou 200 se foi tratada depois (célula 1 = O, versão +2, e a resposta de O já contém o X); estado coerente. *(v0.4: até a v0.3 exigia O 409 em todas, o que um servidor correto não garante.)* | CAO-24 |
| OR-18 | 20 salas; em cada uma, 10 rodadas de 18 jogadas simultâneas (cada posição duas vezes, uma com o token de X e outra com o de O), todas as salas ao mesmo tempo; *v0.4: uma sala nova por rodada, porque a nova partida só é aceita com a partida encerrada e a rodada pode terminar em andamento* | nenhuma 500; toda resposta é 200 ou 409 (`VEZ_DO_OPONENTE`, `CELULA_OCUPADA`, `PARTIDA_ENCERRADA`); em cada sala, estado coerente (critério de `coherenceProblem`), nº de 200 = células preenchidas e versão = inicial + nº de 200; toda jogada aceita gravou o símbolo do token que a enviou; nenhuma resposta de uma sala com o código de outra | CAO-25 |

**Tabela de precedência do OR-08** (mesmos dados no SL-04):

| # | Situação montada | Requisição | Esperado |
|---|---|---|---|
| P-01 | Sala encerrada | token inválido, posição 9 | 410 `SALA_ENCERRADA` |
| P-02 | Em jogo | token inválido, posição 9 | 401 `TOKEN_INVALIDO` |
| P-03 | Em jogo | token de X, corpo `abc` | 400 `CORPO_INVALIDO` |
| P-04 | Aguardando oponente | token de X, posição 9 | 400 `POSICAO_INVALIDA` |
| P-05 | Aguardando oponente | token de X, posição 0 | 409 `AGUARDANDO_OPONENTE` |
| P-06 | Vitória de X (S-L1) | token de X (fora da vez não se aplica), posição 0 (ocupada) | 409 `PARTIDA_ENCERRADA` |
| P-07 | Vitória de X | token de O, posição 9 | 400 `POSICAO_INVALIDA` |
| P-08 | X:0, vez de O | token de X, posição 0 (ocupada) | 409 `VEZ_DO_OPONENTE` |
| P-09 | X:0, vez de O | token de O, posição 0 | 409 `CELULA_OCUPADA` |

## 8. Grupo OW — Canal em tempo real

Pré-condição comum: sala criada e, salvo indicação, com O dentro; clientes `WsClient` identificados. OW-10 e OW-13 usam o servidor dedicado com `--ws-hello-seconds 2 --ws-idle-seconds 3`.

| ID | Cenário | Esperado | CAO |
|---|---|---|---|
| OW-01 | Abertura válida por socket cru com a chave do exemplo da RFC | `HTTP/1.1 101 Switching Protocols`; `Upgrade: websocket`; `Connection: Upgrade`; `Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`; nenhum `Content-Length`, `Connection: close` ou corpo HTTP depois dos cabeçalhos | CAO-45 |
| OW-02 | Aberturas inválidas: sem `Upgrade`; chave curta; versão 8; `POST /ws`; `GET /ws` comum (navegador) | 400 `HANDSHAKE_INVALIDO`; 400; 426 com `Sec-WebSocket-Version: 13`; 405 `Allow: GET`; 400 | CAO-45 |
| OW-03 | `entrar` de X | primeira mensagem `bem_vindo` com `voce = "X"`, `protocolo = 1`, `intervaloPingMs` e `sala` igual ao `GET` feito logo depois | CAO-15 |
| OW-04 | X e O conectados; X joga por REST | os dois recebem `estado` `JOGADA` com versão = anterior + 1 e sala igual ao `GET`, em até 2 s | CAO-12, CAO-15 |
| OW-05 | 9 jogadas de S-9A por REST | cada cliente recebe estados com versões estritamente crescentes (aglutinação permitida: pode pular versões, nunca voltar); o último recebido é igual ao `GET` | CAO-15 |
| OW-06 | X conectado numa sala sem O; O entra por REST | X recebe `estado` `ENTRADA`, `EM_JOGO`, versão anterior + 1 | CAO-14 |
| OW-07 | Clientes em S1 e S2; S1 recebe entrada, 5 jogadas, vitória, nova partida e saída | os clientes de S2 não recebem nenhuma mensagem nesse período (`expectSilence` até o fim do roteiro de S1); *(v0.5)* em S1, só a ordem das versões é exigida, porque a aglutinação pode juntar estados | CAO-10 |
| OW-08 | `entrar` com token inválido; com código inexistente; numa sala encerrada | `erro` `TOKEN_INVALIDO` + fechamento 4401; `SALA_INEXISTENTE` + 4404; `SALA_ENCERRADA` + 4410 | CAO-20, CAO-30, CAO-31 |
| OW-09 | Depois de `entrar`, cada um em um canal novo: `{"tipo":"jogada","posicao":0}`; `{"tipo":"estado","sala":{…vencedor X…}}`; `nao-json`; quadro binário; `entrar` repetido. E `ping` antes de `entrar` | `erro` `MENSAGEM_INVALIDA` + fechamento 4400 em todos; sala inalterada (versão incluída) | CAO-28 |
| OW-10 | Canal aberto sem `entrar` (servidor dedicado, 2 s) | `erro` `TEMPO_ESGOTADO` + fechamento 4408 entre 2 e 4 s | CAO-33 |
| OW-11 | `ping` com `id` 7 e 2147483647 | `pong` com o mesmo `id`; nenhuma outra mensagem | CAO-33 |
| OW-12 | O fecha o canal normalmente (1000) | X recebe `estado` `DESCONEXAO` com `jogadores.O.conectado = false` em até 2 s; `jogadores.O.ocupado` continua `true` | CAO-32 |
| OW-13 | O (socket cru, já identificado) para de ler e de enviar, sem fechar (servidor dedicado, 3 s) | X recebe `DESCONEXAO` entre 3 e 6 s; um terceiro cliente que manda `ping` a cada 1 s continua conectado durante todo o teste | CAO-33 |
| OW-14 | O abre um segundo canal e se identifica | o primeiro recebe `erro` `SUBSTITUIDA` + 4000; X **não** recebe `DESCONEXAO`; uma jogada seguinte chega só ao segundo canal de O | CAO-36 |
| OW-15 | O fecha; X joga duas vezes; O reabre e se identifica *(v0.5: X, O e X jogam pelo REST, porque X não pode jogar duas vezes seguidas; o REST continua valendo para O sem canal)* | `bem_vindo` de O traz as jogadas; X recebe `DESCONEXAO` e depois `CONEXAO` | CAO-34 |
| OW-16 | Mensagem de 4.097 bytes; quadro sem máscara (socket cru); texto com UTF-8 inválido | fechamentos 1009, 1002 e 1007; sala inalterada | CAO-52 |
| OW-17 | O fecha o canal na vez dele; X tenta jogar; terceiro tenta entrar; O reconecta e joga | 409 `VEZ_DO_OPONENTE`; 409 `SALA_CHEIA`; jogada de O aceita | CAO-37 |
| OW-18 | *(v0.5, novo)* 5 repetições, numa sala nova cada: X e O conectados; 18 jogadas simultâneas por REST (cada posição com o token de X e com o de O) | cada canal recebe versões estritamente crescentes, só da própria sala; o último estado de cada canal é igual ao `GET` | CAO-15, CAO-23 |
| OW-19 | *(v0.5, novo; critério "50 canais" da O3; projeto `online-lifecycle`, porta 8779)* 25 salas com X e O conectados (50 canais) por 30 s; jogadas por REST em todas as salas e nova partida no fim de cada uma; `ping` a cada 5 s | nenhum canal cai; nenhuma mensagem de outra sala; versões em ordem; estados coerentes; último estado de cada canal igual ao `GET`; todo canal recebeu `pong`; mais de 500 jogadas; log sem 5xx | CAO-10, CAO-25 |

## 9. Grupo OU — Interface online (Chromium, navegadores isolados)

Infraestrutura da seção 4 (`Players`, `OnlineUi`, verificação cruzada, controle de console e de requisições, contagem de `GET` de sala e registro de URLs). Viewport padrão: Desktop Chrome. Permissões de área de transferência concedidas no OU-02.

| ID | Cenário | Ações | Esperado | CAO |
|---|---|---|---|---|
| OU-01 | Criar sala | A abre `/online.html`; "Criar sala" | `room-code` com 6 caracteres; `room-link` = `<origem>/online.html?sala=<código>`; URL da página igual ao link; status "Aguardando o oponente…"; oponente "Aguardando oponente"; conexão "Conectado"; células com `aria-disabled="true"` | CAO-01, CAO-03 |
| OU-02 | Copiar link | "Copiar link" | área de transferência = link; "Link copiado." visível | CAO-03 |
| OU-03 | Entrar pelo link | B abre o link; "Entrar na sala" | B: "Você joga com O", "Vez do oponente"; A: "Sua vez", "Oponente conectado" | CAO-03, CAO-05 |
| OU-04 | Entrar digitando | C abre `/online.html`; digita `"  k7pm2q "` (o código real em minúsculas, com espaços); "Entrar" | C entra como O | CAO-05 |
| OU-05 | Cada um sabe quem é | A e B na sala | A: "Você joga com X" e "Sua vez"; B: "Você joga com O" e "Vez do oponente"; depois de A jogar, invertem | CAO-08 |
| OU-06 | Jogada aparece no outro | A e B jogam S-EMP alternadamente, por cliques | cada jogada aparece na outra página em até 2 s, sem `GET` de sala e sem clique nela; latências anexadas ao relatório (meta p95 ≤ 500 ms) | CAO-12 |
| OU-07 | Resultado idêntico | S-DUP por cliques; depois, em outra sala, S-EMP | as duas páginas: mesmo tabuleiro, células 0, 2, 4, 6, 8 com `data-winning`; A "Você venceu!", B "O oponente venceu."; no empate, os dois "Empate!" | CAO-13 |
| OU-08 | Oponente entra | A cria e espera; B entra pela API (sem página) *(v0.6: e depois abre o canal com um cliente WS)* | A muda para "Sua vez" sem recarregar nem `GET` de sala; *(v0.6)* com O ocupado e ainda sem canal, "Oponente desconectado. Aguardando reconexão…"; depois do canal de B, "Oponente conectado" | CAO-14 |
| OU-09 | Interface espera o servidor | atrasar as respostas de `POST …/moves` da página A em 1 s; A clica 0 | durante o atraso: célula 0 vazia, `aria-busy="true"`; depois: X; B recebe X | CAO-26 |
| OU-10 | Clique fora da vez | na vez de X, B clica 4 | o `POST` acontece e responde 409; B mostra "Não é a sua vez."; tabuleiros iguais ao servidor | CAO-16, CAO-26 |
| OU-11 | Estado montado pelo servidor | A e B abertos; S-L3 (vitória de O) inteira pela API com os tokens lidos do `localStorage` de cada contexto | sem cliques: as duas páginas mostram o tabuleiro, as células 6, 7, 8 destacadas, A "O oponente venceu." e B "Você venceu!" | CAO-27 |
| OU-12 | Sala cheia | C abre o link de uma sala com A e B | mensagem "Esta sala já tem dois jogadores." e "Criar nova sala"; nenhum lugar ocupado por C | CAO-29 |
| OU-13 | Sala inexistente | abrir `/online.html?sala=ZZZZZZ` (nunca criada); digitar `ZZZZZZ` em "Entrar" | "Sala não encontrada. Confira o código." nos dois casos | CAO-30 |
| OU-14 | Oponente sai | B aciona "Sair da sala" e aceita a confirmação | A: "Esta sala foi encerrada." e "Criar nova sala"; tabuleiro inativo; `data-connection="parado"`; nenhuma tentativa de reconexão nos 5 s seguintes | CAO-31 |
| OU-15 | Fechar a aba e voltar | fechar a página de B; depois abrir o link de novo no **mesmo** contexto | A: "Oponente desconectado. Aguardando reconexão…" em até 2 s; depois de B voltar: B "Você joga com O", mesmo tabuleiro; A "Oponente conectado" | CAO-32 |
| OU-16 | Queda do canal | `routeWebSocket` na página B conectado ao servidor real; derrubar o canal; A joga em 4; liberar | B mostra "Reconectando…"; reconecta sozinho; mostra a jogada de A (X na célula 4) sem recarregar; volta a "Conectado" | CAO-34 |
| OU-17 | Atualizar a página | X:0, O:4; B recarrega | B continua O, mesmo tabuleiro e status; `GET` da sala: dois lugares ocupados | CAO-35 |
| OU-18 | Segunda aba | B abre o link numa segunda página do mesmo contexto | a segunda assume (joga normalmente); a primeira mostra "Esta sala foi aberta em outra aba." e "Usar nesta aba"; em 10 s, no máximo 3 aberturas de canal no total (contadas pelo `page.on('websocket')`) | CAO-36 |
| OU-19 | Nova partida | S-L1 por cliques; B aciona "Nova partida"; depois X:0 e A aciona "Nova partida" | primeiro: as duas páginas com tabuleiro vazio e "Partida 2"; depois: "A partida ainda está em andamento." em A, tabuleiro mantido | CAO-39, CAO-40 |
| OU-20 | Tela pequena | viewport 360 × 640 em todas as telas (inicial, sala criada, jogo, encerrada); jogar em 8 | sem rolagem horizontal (`scrollWidth ≤ clientWidth`); tabuleiro dentro da largura; células ≥ 44 × 44 px; jogada funciona | CAO-42 |
| OU-21 | Teclado e acessibilidade | só teclado: Tab até "Criar sala", Enter; Tab até "Copiar link", Espaço; em B: Tab até o campo, digitar, Enter; jogar com Enter e Espaço, setas | todas as ações funcionam; `lang="pt-BR"`, `h1`, `main`, rótulo do campo, `role="status"` em `status` e `opponent-status`, `role="alert"` no erro, nomes acessíveis das células da CI-14 | CAO-43 |
| OU-22 | Dois navegadores de verdade | dois processos `chromium.launch()`, um contexto em cada; partida curta S-L1 | igual ao OU-06/OU-07 para essa partida | CAO-12 |
| OU-23 | Servidor reiniciado *(v0.6: feito na O4, porta 8783)* | servidor dedicado; A e B jogando; parar o processo; esperar "Reconectando…" nas duas; *(v0.6)* depois de 30 s, "Sem conexão com o servidor." e "Reconectar agora"; iniciar de novo na mesma porta; A aciona "Reconectar agora" e B espera a próxima tentativa | as duas mostram "Sala não encontrada. Confira o código." e "Se o servidor foi reiniciado, as salas anteriores deixam de existir."; "Criar nova sala"; o `localStorage` não tem mais a sala; nenhuma abertura de canal nos 15 s seguintes | CAO-49 |
| OU-24 | Token fora das URLs | verificação automática no fim de cada OU-01 a OU-27 *(v0.6: na fixture `players`, não é um teste à parte)* | nenhum token emitido no teste aparece em URL de página, de requisição ou de canal | CAO-54 |
| OU-25 | *(v0.6, novo)* Token guardado inválido | A cria a sala; no navegador C, uma entrada com o código da sala e um token inexistente; C abre o link | o canal recebe `TOKEN_INVALIDO`; C mostra "Jogador não identificado nesta sala." e "Criar nova sala", `data-state="negado"`, `data-connection="parado"`; a entrada é apagada; uma só abertura de canal; a sala não muda | CAO-20 |
| OU-26 | *(v0.6, novo)* Token guardado vencido | A e B na sala; a entrada de B fica com `salvoEm` mais antigo que 24 h; B recarrega | a entrada é descartada sem abrir o canal; a página consulta a sala e mostra "Esta sala já tem dois jogadores." | CAO-35 |
| OU-27 | *(v0.6, novo)* Falha de comunicação nas ações | A e B jogando; o `POST …/moves` de A é abortado; depois liberado. Em outra página, o `POST /api/rooms` é abortado | "Não foi possível comunicar com o servidor."; os tabuleiros não mudam; o canal continua "Conectado"; a jogada seguinte funciona e a mensagem some; a tela inicial continua depois da falha ao criar | CAO-12 |
| OU-28 | *(v0.7, novo; projeto `online-lifecycle`, porta 8789)* Interface depois do abandono | servidor com prazo de 2 s; A e B jogando; com as páginas abertas por 3 s a sala continua aberta; as duas páginas são fechadas; a sala é encerrada; A reabre o link no mesmo navegador; depois aciona "Criar nova sala"; B reabre o link | A: "Esta sala foi encerrada.", "Criar nova sala", conexão `parado`, token da sala apagado; a sala nova tem outro código e outro token; B também vê a sala encerrada e o token dela é apagado; nenhum token na URL | CAO-38, CAO-31 |

## 10. Grupo OV — Ciclo de vida, segurança e endereço (servidor dedicado)

| ID | Cenário | Servidor | Esperado | CAO |
|---|---|---|---|---|
| OV-01 | Reinício | padrão, porta 8771 | sala em jogo; parar e iniciar o processo; `GET` → 404 `SALA_INEXISTENTE`; jogada com token antigo → 404; `entrar` antigo → 4404 | CAO-48 *(v0.7: porta 8785, porque a 8771 já é usada por um teste da O3; também: entrar, reentrar, nova partida e sair com o código antigo → 404; uma sala nova depois do reinício recebe tokens novos, o token antigo recebe 401 nela e ela funciona; nenhum token no log)* |
| OV-02 | Abandono e lembrança | `--room-ttl-seconds 2 --remember-seconds 3 --sweep-ms 200` | sala com X e O, os dois desconectados; antes de 2 s: `GET` 200; entre ~2,2 s e 5 s: 410 `SALA_ENCERRADA`; depois de ~5,5 s: 404 `SALA_INEXISTENTE` | CAO-38 *(v0.7, porta 8786: medido a partir da última desconexão, o encerramento deve acontecer entre 1,9 e 3,0 s, e a sala fica lembrada, com 410, por 2,9 a 4,0 s. Encerrada, recusa jogada, entrada, reentrada com token, nova partida e sair com 410 `SALA_ENCERRADA`, e o canal com 4410. O log tem `Sala <código> encerrada por abandono`, sem erro, aviso ou token)* |
| OV-03 | Conectado não expira | mesmas opções | sala com X conectado (ping a cada 1 s) por 6 s → continua 200 | CAO-38 *(v0.7, porta 8787: também uma sala com só X conectado e O desconectado, que continua aberta e na qual O volta e joga, e uma sala sem ninguém conectado com jogadas pela API a cada 600 ms durante 5,4 s, que só é encerrada cerca de 2 s depois da última jogada; A1 do plano)* |
| OV-04 | Ctrl+C com canais abertos | padrão, iniciado pelo script | 10 clientes identificados; `scripts\send-ctrl-c.ps1` envia Ctrl+C; todos recebem fechamento 1001; processo termina com código 0 em até 5 s; a porta volta a aceitar um novo servidor | CAO-50 *(v0.7: D-01 e D-02 do script; D-03 repete com o faxineiro a cada 20 ms e prazo de 1 s, com 80 salas abandonadas, e exige 1001 nos 10 canais, código 0 em até 5 s, salas encerradas antes do desligamento e nenhuma depois; D-05 confere, no fim do script, que não sobrou processo do projeto (servidor, EngineCheck, ws-hold, Playwright) e que as portas de teste estão livres)* |
| OV-05 | Origem do canal | (a) padrão (porta 8775); (b) `--allowed-origin http://desktop-ruan:8776`; (c) `--public --allowed-origin https://jogo.test` | (a) por socket cru: OG-01, OG-02, OG-03 (com o IP privado real da máquina) e OG-18 → 101; OG-05 a OG-08, OG-10, OG-11, OG-13 a OG-16 → 403 `ORIGEM_NAO_PERMITIDA`; o log mostra a lista de origens e as recusas, sem tokens. (b) `http://desktop-ruan:8776` → 101. (c) `https://jogo.test` → 101; `http://127.0.0.1:<porta>`, `http://jogo.test` e ausente → 403; `--public --allowed-origin http://jogo.test` → o servidor não inicia (código 2) | CAO-51 |
| OV-06a | *(v0.8: substitui o OV-06)* Taxas por cliente | `--trust-proxy --rate-create 3 --rate-join 4 --rate-ws 2 --rate-window-seconds 3`, porta 8793 | criação: 3 aceitas, a 4ª → 429 `LIMITE_DE_REQUISICOES` com `Retry-After` de 1 a 3, `no-store` e cabeçalhos de segurança; outro cliente aceito; só o último endereço de `X-Forwarded-For` conta; consulta/entrada: GET, HEAD, GET de código inexistente (404) e entrada aceitos, a 5ª → 429; jogadas do mesmo cliente sem taxa; canal: 2 aberturas, a 3ª → 429 antes do 101; depois do `Retry-After`, criação e canal aceitos de novo; o log nomeia o limite e o cliente, sem token | CAO-53 |
| OV-06b | *(v0.8)* Capacidade de salas | `--max-rooms 5`, porta 8794 | 5 salas aceitas, a 6ª → 503 `CAPACIDADE_ESGOTADA` (com cabeçalhos); entrar e jogar nas salas existentes continua; depois de uma sala encerrada, uma criação aceita (no limite de novo) e a seguinte → 503 | CAO-53 |
| OV-06c | *(v0.8)* Cliente atrás de proxy | `--trust-proxy --rate-create 2` (porta 8806) e `--rate-create 2` (porta 8807) | pelo IPv4 privado da máquina (não é o proxy local), três endereços diferentes em `X-Forwarded-For` contam como um cliente: 201, 201, 429; por 127.0.0.1 com `--trust-proxy`, um cliente por endereço; sem `--trust-proxy`, cabeçalho ignorado | CAO-53 |
| OV-07 | Modo público *(v0.8: reescrito; a v0.7 usava uma origem http, que o modo público recusa — B1)* | `--public --allowed-origin https://jogo.test`, porta 8795, limites públicos padrão | `/api/game` em GET, HEAD, POST (moves, reset), DELETE, OPTIONS → 404 `ROTA_NAO_ENCONTRADA`; `/health` 200; `/` e `/index.html` → 302 `/online.html`; `/online.html` com CSP (`default-src 'self'`, `frame-ancestors 'none'`) e `X-Frame-Options: DENY`; todas as respostas com `nosniff` e `no-referrer`; partida completa por clientes REST e WebSocket com `Origin: https://jogo.test` (estados nos dois canais, vitória, nova partida, saída com 4410); a origem certa não substitui o token (401 sem token ou com token de outra sala, 4401 no canal); loopback e `http` recusados (403), canal sem `Origin` recusado, `POST` sem `Origin` aceito (B2); log com os limites públicos e sem token. A interface no navegador em modo público fica para o MV-P (O8) | CAO-55, CAO-51 |
| OV-08 | Endereço de escuta | sem opções; `--bind 127.0.0.1`; `--public` (script) | `Get-NetTCPConnection -State Listen` mostra `0.0.0.0:<porta>` no primeiro caso e só `127.0.0.1:<porta>` nos outros dois; no primeiro caso, `GET /health` pelo IP da rede local da máquina responde 200 e o canal abre com `Origin` igual a esse endereço | CAO-46 |
| OV-09 | Token fora do log | toda a suíte online (script) | os tokens emitidos durante a suíte (gravados pelos testes em `test-results/online-tokens.txt`) não aparecem em nenhum log de servidor da execução *(v0.8: verificação S-05 do script: nenhum padrão de token — 32 hex ou `Bearer` — em nenhum log de servidor da execução 2, o do script e os de todos os servidores dedicados da suíte)* | CAO-54 |
| OV-10 | Partida pelo IP da rede local | *(v0.6: servidor dedicado na porta 8784, bind padrão `0.0.0.0`, para não depender do bind do servidor da suíte)* | o teste descobre o IPv4 privado da máquina (`os.networkInterfaces()`); A abre `http://<IP>:8765/online.html` e B abre `http://127.0.0.1:8765/online.html`; os dois jogam S-L1 com as jogadas aparecendo em tempo real; sem erros de console nem recusas de origem. Sem IPv4 privado na máquina, o teste **falha** com a mensagem "sem rede local" (não é pulado) | CAO-56 |
| OV-11 | *(v0.7, novo)* Sala nova depois de salas encerradas | `--room-ttl-seconds 1 --remember-seconds 30 --sweep-ms 100`, porta 8788 | uma sala encerrada por saída e outra por abandono; cinco salas novas: código diferente, token de X diferente dos quatro antigos e estado inicial; entrar com o token de outra sala cria um O novo, com token novo; jogar com tokens antigos → 401 `TOKEN_INVALIDO`; canal com token antigo → 4401; nada disso muda a sala nova (versão 2); as antigas continuam 410 | CAO-01, CAO-11 |
| OV-12 | *(v0.7, novo)* Limpeza concorrente | `--room-ttl-seconds 1 --remember-seconds 1 --sweep-ms 20`, porta 8792 | por 10 s: 8 salas ativas (X e O conectados, ping a cada 300 ms) com jogadas e novas partidas pela API sem parar; salas abandonadas criadas a cada ~40 ms; um terço recebe uma identificação de canal entre 0,85 e 1,25 s depois de criada (em volta do prazo). Esperado: nenhuma resposta diferente de 200 nas salas ativas; canais ativos abertos, só com mensagens da própria sala, versões crescentes e estados coerentes, terminando na versão do `GET`; cada identificação ou conecta (e a sala continua aberta enquanto conectada) ou recebe `SALA_ENCERRADA`/4410 com a sala em 410/404; abandonadas há mais de 1,5 s → 410 ou 404; nenhuma sala ativa encerrada no log; log sem erro, aviso, 5xx ou token; mais de 200 jogadas e de 50 encerramentos | CAO-25, CAO-38 |
| OV-13 | *(v0.8, novo)* Modo local preservado | sem opções, porta 8796 | `/api/game` (GET, HEAD, reset, jogada) como antes, agora com `nosniff` e `no-referrer`; `/`, `/index.html` e `/online.html` com CSP; jogada local com 10 KB e com 64 KB exatos aceita (como antes); 64 KB + 1 → 413 `CORPO_MUITO_GRANDE` sem mudar o jogo (única mudança local, B3); 40 criações seguidas, 12 canais do mesmo cliente e 50 pings seguidos aceitos (limites desligados); log com "sem limite" | CAO-44, CAO-55 |
| OV-14a | *(v0.8, novo)* Configurações inválidas | porta 8797 | não iniciam (código 2, "Parâmetros inválidos"): `--public` sem origem, com `http`, com uma `http` entre `https`, origem com caminho, `ftp`, `--bind` inválido, taxa negativa ou acima do máximo, janela 0, prazo de leitura 0, `--ws-per-client` sem valor, `--trust-proxy` com valor, opção desconhecida | CAO-46, CAO-51 |
| OV-14b | *(v0.8, novo)* Combinações válidas | portas 8797 a 8801 | (1) `--public`: só 127.0.0.1 (pelo IP privado, recusado); limite público de criação 10 por minuto (11ª → 429); (2) `--public --bind 0.0.0.0` com duas origens: pelo IP privado responde; só as duas `https` abrem o canal; IP privado e loopback → 403; `/api/game` 404; (3) local `--bind 127.0.0.1`: IP privado recusado; rotas locais; origem do IP privado → 403; (4) local `--bind <IP privado>`: loopback recusado; origem do loopback → 403; (5) `--trust-proxy` no modo público informado no log | CAO-46, CAO-51 |
| OV-15a | *(v0.8, novo)* Canais por cliente e mensagens por canal | `--trust-proxy --ws-per-client 2 --ws-msg-rate 5`, porta 8802 | 2 canais do cliente A abrem, o 3º → 429 `LIMITE_DE_CONEXOES` (sem `Retry-After`, com cabeçalhos); cliente B abre os seus; A fecha um e reabre; no canal de A, `entrar` + 4 pings (5, no limite) respondidos, o 5º ping → `erro` `LIMITE_DE_MENSAGENS` e 1008; o outro lugar da sala recebe `DESCONEXAO`; a outra sala segue (pong, jogada entregue, só mensagens dela) | CAO-53, CAO-52 |
| OV-15b | *(v0.8, novo)* Conexões do servidor e prazo de leitura | `--max-connections 4 --http-timeout-seconds 2`, porta 8803 | com 4 conexões paradas, a 5ª → 503 `SERVIDOR_OCUPADO` em JSON com `Retry-After: 5` e cabeçalhos; as paradas são fechadas pelo servidor entre 1,8 e 4,5 s; vagas liberadas; cabeçalhos incompletos: no prazo o Indy dá os cabeçalhos por terminados, responde e fecha (B13); pedido lento com cada pedaço antes do prazo é atendido; canal parado 3 s continua aberto | CAO-53 |
| OV-16 | *(v0.8, novo)* Tamanho das requisições | `--http-timeout-seconds 3`, porta 8804 | 5 MB em blocos numa rota de sala e 70 KB em blocos na rota antiga → 413 (sem 500); `Content-Length: 800000000` com 5 bytes enviados: a memória privada do servidor não cresce mais que 50 MB (antes, o Indy alocava o tamanho declarado) e a conexão é fechada pelo prazo; 1.100 linhas de cabeçalho e uma linha de 20 KB: conexão encerrada, servidor segue respondendo; log sem erro nem token | CAO-52 |
| OV-17 | *(v0.8, novo)* Rajada com limites e isolamento | `--trust-proxy --rate-create 5 --rate-join 20 --rate-ws 10 --rate-window-seconds 2 --max-connections 40 --ws-per-client 3 --ws-msg-rate 20`, porta 8805 | 20 clientes, cada um com 8 criações, 25 consultas e 5 aberturas de canal, 60 de cada vez, enquanto outra sala joga uma partida inteira com canais: só respostas previstas (201/404/101, 429, 503), nenhum erro de rede; ninguém passa do próprio limite, e pelo menos uma criação é recusada com 429 *(acrescentado na validação: sem isso, o teto por cliente, folgado para rajadas longas, não detectava a SB-18)*; a partida termina, os canais não caem, versões em ordem, só mensagens da própria sala; cada 503 tem a sua linha no log; depois, vagas e canais por cliente liberados (o cliente 0 abre 3 canais de novo), e o 4º canal simultâneo do mesmo cliente continua recusado com 429 *(acrescentado na validação, para a SB-22)* | CAO-25, CAO-53 |
| OV-18 | *(v0.9, novo — pendência da O6)* Corpo HTTP exatamente no limite de 64 KB | `--bind 127.0.0.1`, porta 8810 | Semântica da B3 (`plan-online.md` 13.1): nenhum corpo ocupa mais de 65.536 bytes em memória; `/api/game/moves`, a única rota que aceita corpo acima de 1 KB, processa até 65.536 bytes e responde 413 `CORPO_MUITO_GRANDE` a partir de 65.537, sem mudar o estado. Cada corpo é um JSON que só fecha no último byte (`{"posicao":N,"x":"aaa…"}`), então um corpo truncado daria 400. Casos: 65.535 e 65.536 bytes com `Content-Length` → 200 e a jogada vale; 65.537 → 413 e o estado não muda; 65.537 e 65.536 em blocos (`chunked`, 4.096 bytes) → 413 / 200; 1 MB em blocos → 413 e `/health` 200; `POST /api/rooms` com 65.536 bytes → 413 (limite de 1 KB das salas, CAO-52) e nenhuma sala criada; cabeçalhos de segurança no 200 e no 413; log sem 5xx nem token | CAO-52 |

## 11. Sabotagens (prova de que os testes detectam defeitos)

Mesmo procedimento da seção 9.2 de `docs/test-plan.md`: cópia temporária, compilação, execução dos testes indicados em outra porta, descarte da cópia. O código original nunca é alterado. Se algum teste indicado **passar**, ele não testa o que diz testar e precisa ser corrigido antes da entrega.

| ID | Sabotagem | Testes que precisam falhar | Entrega |
|---|---|---|---|
| SB-07 | O registro devolve o mesmo `TGameEngine` para todas as salas | SL-06, SC-02, OR-10, OR-13, OR-18 | O1, O2 |
| SB-08 | `Room.Play` não verifica de quem é a vez | SL-04, OR-02, OR-08, OR-16, OR-17, OU-10 | O1, O2, O4 |
| SB-09 | `online.js` desenha o símbolo na célula clicada antes da resposta | OU-09 e a verificação cruzada | O4 |
| SB-10 | `TRoom` sem seção crítica, com `Sleep(50)` entre a validação e a gravação | SC-01, OR-16, OR-17 | O1, O2 |
| SB-11 | `Hub.Publish` não faz nada | OW-04, OW-05, OW-06, OU-06, OU-08 (e HB-02, HB-03) | O3, O4 |
| SB-12 | Qualquer token de 32 hex é aceito como o lugar da vez | SL-07, OR-06, OW-08 | O1, O2, O3 |
| SB-13 | O faxineiro nunca encerra salas *(v0.7: aplicada ao faxineiro, que roda mas não varre; o SL-11 testa o domínio da O1, que a sabotagem não toca)* | JN-01, JN-02, OV-02, OV-03, OV-11, OV-12, OU-28 | O5 |
| SB-14 | `uOriginPolicy` aceita qualquer `Origin` *(v0.8: também no modo público)* | WS-07, OA-10, OV-05, OV-07, OV-14b | O3, O6 |
| SB-16 | *(v0.6, nova)* `online.js` coloca o token na URL da página | OU-01, OU-03, OU-17 (e o controle OU-24 em todos os OU) | O4 |
| SB-15 | *(v0.5, nova)* O hub entrega o estado de uma sala aos inscritos de todas as salas | HB-02, HB-03, OW-07 | O3 |
| SB-17 | *(v0.7, nova)* `CloseAbandoned` ignora as conexões e encerra pelo prazo mesmo com alguém conectado | JN-01, JN-02, OV-03, OV-12, OU-28 | O5 |
| SB-18 | *(v0.8, nova)* A taxa por cliente nunca limita | RL-01, OV-06a, OV-06c, OV-14b, OV-17 | O6 |
| SB-19 | *(v0.8, nova)* Sem cabeçalhos de segurança | OV-06a, OV-07, OV-13 | O6 |
| SB-20 | *(v0.8, nova)* Com `--public`, `/api/game*` continuam ativas | OV-07, OV-14b | O6 |
| SB-21 | *(v0.8, nova)* O canal não limita as mensagens | OV-15a | O6 |
| SB-22 | *(v0.8, nova)* Sem limite de canais por cliente | RL-02, OV-15a, OV-17 | O6 |
| SB-23 | *(v0.8, nova)* `X-Forwarded-For` aceito de qualquer conexão, sem `--trust-proxy` | RL-05, OV-06c | O6 |
| SB-24 | *(v0.8, nova)* Corpo sem teto em memória (o Indy aloca o tamanho declarado) | OV-16 | O6 |
| SB-25 | *(v0.8, nova)* Sem prazo de leitura | OV-15b, OV-16 | O6 |
| SB-26 | *(v0.9, nova)* Teto do corpo com erro de um byte: `>=` no lugar de `>` (exatamente 65.536 bytes já recebe 413) | OV-18 | O7 |
| SB-27 | *(v0.9, nova)* Teto em memória um byte menor (o corpo de 65.536 bytes chega truncado) | OV-18 | O7 |

As sabotagens do modo local (SB-01 a SB-06) continuam valendo e continuam sendo executadas pelos scripts das Entregas 2 a 5 quando a regressão completa é exigida. *(v0.9: na O7, SB-01 a SB-06 rodam contra o código atual em `scripts\validate-online-o7-complemento.ps1`; SB-07 a SB-27 em `scripts\validate-online-o7.ps1`.)*

## 12. Matriz de rastreabilidade

| CAO | Requisito | Descrição curta | EngineCheck | API / Regras / Canal / Ciclo | Interface |
|---|---|---|---|---|---|
| CAO-01 | RO-01 | Criar sala | SL-01, RJ-01 | OA-01 | OU-01 |
| CAO-02 | RO-01 | Código único | SL-02 | OA-02 | — |
| CAO-03 | RO-01 | Link compartilhável | — | — | OU-01, OU-02, OU-03 |
| CAO-04 | RO-02 | Entrar pelo código | SL-03 | OA-04 | — |
| CAO-05 | RO-02 | Entrar pela interface | — | — | OU-03, OU-04 |
| CAO-06 | RO-02 | Reentrada com o próprio token | SL-03 | OA-05 | — |
| CAO-07 | RO-03 | Símbolo pelo lugar | SL-05 | OR-01 | — |
| CAO-08 | RO-03 | Cada um sabe quem é | — | — | OU-05 |
| CAO-09 | RO-04 | Estado isolado | SL-06, SC-02 | OR-10 | — |
| CAO-10 | RO-04 | Notificações isoladas | HB-02, HB-03 | OW-07, OW-19 | — |
| CAO-11 | RO-04 | Token não vale em outra sala | SL-07 | OR-06 | — |
| CAO-12 | RO-05 | Jogada aparece no outro navegador | — | OW-04 | OU-06, OU-22, OU-27 |
| CAO-13 | RO-05 | Resultado idêntico | — | OR-09 | OU-07 |
| CAO-14 | RO-05 | Entrada do oponente notificada | — | OW-06 | OU-08 |
| CAO-15 | RO-05 | Ordem das notificações | RJ-02, WS-04, WS-06, HB-01 | OW-03, OW-04, OW-05, OW-18 | — |
| CAO-16 | RO-06 | Fora da vez | SL-04 | OR-02 | OU-10 |
| CAO-17 | RO-06 | Célula ocupada | SL-04 | OR-03 | — |
| CAO-18 | RO-06 | Partida encerrada | SL-04 | OR-04, OR-09 | — |
| CAO-19 | RO-06 | Sem oponente | SL-04 | OR-05 | — |
| CAO-20 | RO-06 | Token ausente ou inválido | SL-07 | OR-06, OW-08 | OU-25 |
| CAO-21 | RO-06 | Corpo e posição inválidos | (J-02 a J-04 do modo local) | OR-07 | — |
| CAO-22 | RO-06 | Ordem de validação | SL-04 | OR-08 | — |
| CAO-23 | RO-07 | Mesmo jogador, duas jogadas | SC-01 | OR-16 | — |
| CAO-24 | RO-07 | X e O ao mesmo tempo | SC-01 | OR-17 | — |
| CAO-25 | RO-07 | Muitas salas em paralelo | SC-02, HB-03, JN-02 | OR-18, OW-19, OV-12 | — |
| CAO-26 | RO-08 | Só o servidor muda o tabuleiro | — | — | OU-09, OU-10 |
| CAO-27 | RO-08 | Estado montado pelo servidor | — | — | OU-11 |
| CAO-28 | RO-08 | Mensagens do cliente não mudam a sala | RJ-03 | OW-09 | — |
| CAO-29 | RO-09 | Sala cheia | SL-03 | OR-14 | OU-12 |
| CAO-30 | RO-09 | Sala inexistente | — | OA-07, OW-08 | OU-13 |
| CAO-31 | RO-09 | Sala encerrada | SL-10 | OR-15, OW-08 | OU-14 |
| CAO-32 | RO-10 | Fechar a aba | SL-09 | OW-12 | OU-15 |
| CAO-33 | RO-10 | Queda silenciosa e batimento | — | OW-10, OW-11, OW-13 | — |
| CAO-34 | RO-10 | Reconexão automática | — | OW-15 | OU-16 |
| CAO-35 | RO-10 | Atualizar a página | — | — | OU-17, OU-26 |
| CAO-36 | RO-10 | Mesma sala em outra aba | SL-09, HB-02 | OW-14 | OU-18 |
| CAO-37 | RO-10 | Lugar reservado | SL-09 | OW-17 | — |
| CAO-38 | RO-10 | Sala abandonada | SL-11, JN-01, JN-02 | OV-02, OV-03, OV-11, OV-12 | OU-28 |
| CAO-39 | RO-11 | Nova partida após o fim | SL-08 | OR-11 | OU-19 |
| CAO-40 | RO-11 | Nova partida no meio do jogo | SL-08 | OR-12 | OU-19 |
| CAO-41 | RO-11 | Nova partida não afeta outra sala | SL-06 | OR-13 | — |
| CAO-42 | RO-12 | Tela pequena | — | — | OU-20 |
| CAO-43 | RO-12 | Teclado e leitor de tela | — | — | OU-21 |
| CAO-44 | RO-13 | Regressão do modo local | M, SV, J (27 casos), RJ-01 | suíte atual A e R (80), OR-10, OA-10, OA-11, OA-12 | suíte atual U (29) |
| CAO-45 | RO-13 | Rotas novas seguem o padrão | WS-01, WS-02 | OA-03, OA-06, OA-08, OW-01, OW-02 | — |
| CAO-46 | RO-13 | Endereço de escuta | OP-01, OP-02, OP-03 | OV-08, OV-14a, OV-14b | — |
| CAO-47 | RO-14 | Cobertura e sabotagens | — | SB-07 a SB-25 + conferência desta matriz pelo script (seção 13.3) | — |
| CAO-48 | RO-15 | Salas somem no reinício | — | OV-01 | — |
| CAO-49 | RO-15 | Interface informa e para | — | — | OU-23 |
| CAO-50 | RO-15 | Encerramento com canais abertos | — | OV-04 (D-01 a D-05 do script da O5) | — |
| CAO-51 | RO-16 | Origem do canal e das rotas de sala | WS-07, OP-02 | OA-10, OV-05, OV-07, OV-14a, OV-14b | — |
| CAO-52 | RO-16 | Limites de tamanho | WS-03, WS-05, RL-03, RL-04 | OA-09, OW-16, OV-15a, OV-16 | — |
| CAO-53 | RO-16 | Limites de taxa e capacidade | SL-12, RL-01, RL-02, RL-05, OP-03 | OV-06a, OV-06b, OV-06c, OV-15a, OV-15b, OV-17 | — |
| CAO-54 | RO-16 | Token protegido | — | OA-03, OV-09 (S-05 do script), OV-06a a OV-17 (logs) | OU-24 |
| CAO-55 | RO-16 | Modo público | — | OV-07, OV-13 (cabeçalhos no modo local) | — |
| CAO-56 | RO-17 | Partida pelo IP da rede local | — | OV-10 (e MV-L01) | — |
| — | R-10 | Memória | MEM-01 | — | — |

Todos os 56 critérios têm pelo menos um cenário automatizado. Totais planejados: 27 casos novos no `EngineCheck` (SL 12, SC 2, RJ 3, WS 7, HB 2, OP 1), mais a verificação MEM-01 feita pelo script, e 79 cenários Playwright (OA 10, OR 18, OW 17, OU 24, OV 10), alguns desdobrados em vários testes (OA-07, OR-06, OR-07, OR-09, OW-02, OW-09, OW-16), além de 8 sabotagens e 14 verificações manuais (6 na rede local e 8 na publicação).

## 13. Critérios de aprovação

### 13.1 De um cenário

Igual a `docs/test-plan.md` 11.1: executado contra o servidor real e aprovado na primeira tentativa, sem retries. "Pulado", "instável" ou "não executado" não contam.

### 13.2 De uma entrega (O1 a O6)

1. `EngineCheck` com código de saída 0: os 27 casos atuais e os novos da entrega.
2. Suíte Playwright completa (atual + online até a entrega) com 0 falhas, 0 pulados e 0 instáveis, **duas vezes seguidas**.
3. `npm run typecheck` sem erros.
4. Sabotagens da entrega com as falhas esperadas.
5. Log do servidor sem 500, sem exceção e sem token (a partir da O3).
6. Registro em `docs/delivery-log.md` com a saída real; nenhum resultado declarado sem ela.

### 13.3 Da validação final na rede local (O7)

1. Itens 1 a 5 de 13.2, com a suíte rodada **3 vezes seguidas** a partir de um clone limpo.
2. O script `validate-online-o7` confere esta matriz: todo CAO-01 a CAO-56 tem pelo menos um teste com o seu identificador no título e com resultado "passou" no `results.json` (CAO-47).
3. Todas as sabotagens SB-01 a SB-14 com as falhas esperadas. *(v0.9: na O7, todas as sabotagens SB-01 a SB-27.)*
4. Checklist MV-L (13.4) registrado.
5. *(v0.9)* O "clone limpo" é uma **cópia limpa** da pasta de trabalho (sem executáveis, `.dcu`, logs nem resultados), porque o trabalho das O0 a O7 ainda não está em commit e um `git clone` não teria o código; a cópia inclui `tests\node_modules` (sem instalação pela rede). Desvio registrado no `delivery-log`.
6. *(v0.9)* Os itens MV-L **não executados** num aparelho real ficam registrados como pendentes, com o motivo; nunca como aprovados.

### 13.4 Checklist manual na rede local (MV-L, Entrega O7)

*(v0.9: roteiro ampliado e reproduzível; MV-L01 a MV-L06 da v0.8 estão nos itens L02/L03, L13, L05, L11, L14 e L15.)*

**Preparação (sempre):**
1. Compilar (`scripts\build.cmd`) e fechar qualquer servidor na porta 8765.
2. Rodar `scripts\o7-servidor-rede-local.cmd`. Ele registra, só para leitura, o perfil da rede, o estado do firewall e o SHA-256 do executável, mostra o endereço `http://<IP do computador>:8765/online.html` e grava o log do servidor em `logs\o7-rede-local-<hora>-servidor.log`. Cada canal aberto registra o IP do aparelho, que é a evidência de que o celular se conectou.
3. Celular na **mesma rede** do computador (Wi-Fi do mesmo roteador). Anotar o modelo, o sistema e o navegador do celular, e o navegador do computador.
4. Encerrar com Ctrl+C na janela do servidor; o resumo final lista os IPs que abriram canais.

| ID | Passos | Resultado esperado |
|---|---|---|
| MV-L01 | Preparação acima; abrir o endereço no computador e no celular | As duas páginas carregam; o console mostra as origens permitidas com o IP do computador |
| MV-L02 | No computador (pelo IP), "Criar sala"; "Copiar link"; enviar o link ao celular (por exemplo, por mensagem) e abri-lo | "Link copiado." no computador; o celular abre a sala, "Entrar na sala" e passa a jogar com O; o log mostra um canal do IP do celular (CAO-56) |
| MV-L03 | Partida completa até a vitória; depois "Nova partida" e outra até o empate | Cada jogada aparece no outro aparelho sem recarregar; resultado igual nos dois (CAO-12, CAO-13) |
| MV-L04 | Com a partida em andamento, desligar o Wi-Fi do celular (e os dados móveis) por ~20 s; o computador joga; religar o Wi-Fi | O celular mostra "Reconectando…" e, ao voltar, reconecta sozinho e mostra a jogada feita durante a queda, no mesmo lugar (CAO-34) |
| MV-L05 | Bloquear a tela do celular por 1 minuto durante a partida e desbloquear | Reconecta sozinho e mostra as jogadas feitas nesse tempo |
| MV-L06 | Recarregar a página no celular | Continua O, mesmo tabuleiro, nenhum lugar novo (CAO-35) |
| MV-L07 | "Sair da sala" no celular | O celular sai; o computador mostra "Esta sala foi encerrada." e para de reconectar; "Criar nova sala" funciona (CAO-31) |
| MV-L08 | No celular, "Criar sala"; no computador, digitar o código (em minúsculas) e entrar | Entra na sala certa; a partida funciona (CAO-05) |
| MV-L09 | No computador, só com o teclado (Tab, Enter/Espaço, setas): criar sala, copiar o link, jogar | Tudo funciona sem mouse; o foco é visível (CAO-43) |
| MV-L10 | No celular em retrato (tela estreita real): tela inicial, sala criada, jogo e sala encerrada | Sem rolagem horizontal; tabuleiro inteiro visível; células fáceis de tocar (CAO-42) |
| MV-L11 | Partida com o computador em outro navegador (Edge ou Firefox), contra o celular | Igual ao MV-L03 |
| MV-L12 | No computador, abrir a página pelo **nome** do computador (`http://<nome>:8765/online.html`) | A página carrega, mas o canal não conecta; o console registra "Origem recusada em /ws" (lista de origens, 7.7) |
| MV-L13 | Com uma partida aberta, encerrar o servidor (Ctrl+C) e iniciá-lo de novo | Os dois aparelhos mostram "Reconectando…", depois "Sem conexão com o servidor."; com o servidor de volta, "Sala não encontrada" (a sala antiga não existe mais; CIO-12, CAO-49) |
| MV-L14 | Firewall e perfil de rede: registrar o perfil (Privado/Público) e o estado do firewall de cada perfil. Se você decidir testar: ligar o firewall no perfil da rede **sem** regra para o servidor e tentar pelo celular; depois permitir o `TicTacToeServer.exe` **só no perfil Privado**, com a rede marcada como Privada, e tentar de novo | Sem regra (firewall ligado): o celular não abre a página. Com a regra no Privado e a rede Privada: abre e joga. As mudanças de configuração do Windows são feitas por você. |
| MV-L15 | *(opcional)* Narrador do Windows na página do computador | A jogada do oponente é anunciada |

Registro: para cada item, data e hora, aparelhos e navegadores, resultado ("passou", "falhou: …" ou "pendente: motivo") e os IPs do log. Fotos da tela do celular, quando enviadas, ficam em `docs\screenshots\mv-l\`.

### 13.5 Checklist manual da publicação (MV-P, Entrega O8 — cancelada em 20/10/2026; só referência)

| ID | Verificação |
|---|---|
| MV-P01 | O endereço público abre com HTTPS válido (cadeado, certificado do domínio). |
| MV-P02 | `http://` redireciona para `https://`. |
| MV-P03 | Nas ferramentas do navegador, o canal usa `wss://` e recebe `bem_vindo`. |
| MV-P04 | Partida completa entre um celular em rede móvel e um computador em outra rede. |
| MV-P05 | `/api/game` responde 404 no endereço público. |
| MV-P06 | `curl -I` da página mostra os cabeçalhos de segurança. |
| MV-P07 | A porta 8765 não responde quando acessada de fora da máquina. |
| MV-P08 | Reiniciar o servidor com uma partida aberta leva os dois navegadores à mensagem da CIO-12. |

### 13.6 O que não é critério de aprovação

O código compilar; uma verificação manual sem registro (exceto os checklists MV-L e MV-P, que são registrados); um teste que nunca foi visto falhar; um resultado de latência acima da meta de 500 ms (registrado e investigado, mas o limite verificado é 2 s).

## 14. Dependências e pontos a confirmar

| ID | Componente | Ponto | Tratamento |
|---|---|---|---|
| IO-01 | Indy 10.6.2.5341 | Assumir a conexão no `OnCommandGet` e escrever o 101 diretamente | E0-02, E0-04, E0-05 (O0) |
| IO-02 | Indy | Desligamento com canais abertos | E0-07 (O0), OV-04 |
| IO-03 | RTL do Berlin | `System.Hash.THashSHA1`, `System.NetEncoding` | E0-01 (O0); alternativa no Indy (DTO-18) |
| IO-04 | Node 24.11.1 | `WebSocket` global | E0-03 (O0) |
| IO-05 | Playwright 1.64.1 | `page.routeWebSocket` com `connectToServer` | E0-08 (O0) |
| IO-06 | Playwright | Diálogo de confirmação de "Sair da sala" | `page.once('dialog', d => d.accept())` no OU-14 |
| IO-07 | Windows | Enviar Ctrl+C a um processo console por script | OV-04; se não for confiável, verificação manual registrada (como RNF-12 nas Entregas 1 a 5) |
| IO-08 | Chromium | Área de transferência em modo sem janela | `context.grantPermissions(['clipboard-read','clipboard-write'])` no OU-02 |
| IO-09 | Testes de tempo | Instabilidade | Servidor dedicado com prazos curtos e margens explícitas (por exemplo, "entre 3 e 6 s") |
| IO-10 | Rede da máquina | OV-10 e MV-L01 precisam de um IPv4 privado | Se não houver, o OV-10 falha com mensagem clara; a validação é refeita com a rede conectada |

## 15. Registro de alterações

| Versão | Data | Alteração |
|---|---|---|
| 0.1 | 2026-10-16 | Criação: grupos SL, SC, RJ, WS, HB, OP, MEM (EngineCheck), OA, OR, OW, OV, OU (Playwright) e MV (manual); sabotagens SB-07 a SB-13; matriz CAO-01 a CAO-55. Nenhum teste escrito ou executado. |
| 0.2 | 2026-10-16 | Bind padrão `0.0.0.0` (DO-09): OP-01, WS-02 (`Origin` igual ao `Host`) e OV-08 ajustados. |
| 0.3 | 2026-10-16 | Decisões de 16/10: WS-02 sem a regra de `Host`; novos WS-07 (política de origem, casos OG-01 a OG-19), OA-10, OV-10 (partida pelo IP da rede local, CAO-56) e SB-14; OV-05 reescrito; checklist dividido em MV-L (rede local, O7) e MV-P (publicação, O8); matriz com CAO-56. |
| 0.4 | 2026-10-16 | Entrega O2 (testes escritos e executados: OP-01, OA-01 a OA-09, OR-01 a OR-18): pastas `tests/online/room-api` e `tests/online/room-rules` em vez de `online/api` e `online/rules`, porque o Playwright prefixa os padrões com `**/` e o projeto `api` (`api/**`) passaria a rodar os testes novos; o mesmo vale para `online/ui` e `online/ws` nas próximas entregas. OR-17 corrigido (com X tratado primeiro, a jogada de O é válida). OR-18 com uma sala nova por rodada e verificação do símbolo de cada jogada aceita. `POST /ws` do OA-06 fica para a O3. SB-10 detectada pelo OR-16; o OR-17 não detecta a falta de seção crítica (a vez é verificada antes do atraso), só a SB-08. |
| 0.5 | 2026-10-17 | Entrega O3 (testes escritos e executados: OP-02, WS-01 a WS-07, HB-01 a HB-03, OA-10, OA-11, OW-01 a OW-19, OV-05 a, b e c, e o Ctrl+C do OV-04 pelo script). Novos: OA-11 (`Authorization` nas rotas antigas, ressalva da O2), OW-18, OW-19, HB-03, OP-02 e SB-15. Projetos `online-ws` e `online-lifecycle` separados. OV-05 cobre já o modo público (antecipado da O6 a pedido do usuário). OW-07 e OW-15 ajustados (aglutinação; X não joga duas vezes seguidas). HB-02 corrigido durante a validação: o teste não esvaziava a caixa de O antes de conferir a mensagem terminal. |
| 0.6 | 2026-10-17 | Entrega O4 (testes escritos e executados: OA-12, OU-01 a OU-27, OV-10; projeto `online-ui`). Novos: OA-12, OU-25, OU-26, OU-27 e SB-16. OU-23 antecipado da O5. OU-08 ajustado (entrada pela API não abre canal; o teste abre um cliente WS para B). OU-24 feito como controle na fixture. OV-10 com servidor dedicado. |
| 0.7 | 2026-10-19 | Entrega O5 (testes escritos e executados: JN-01, JN-02, OV-01, OV-02, OV-03, OV-04 como D-01 a D-05 do script, OV-11, OV-12 e OU-28). Novos: JN-01, JN-02, OV-11, OV-12, OU-28 e SB-17. OV-01 na porta 8785 (a 8771 já era usada); OV-02 e OV-03 com prazos medidos e mais casos; SB-13 aplicada ao faxineiro. |
| 0.8 | 2026-10-19 | Entrega O6 (testes escritos e executados: RL-01 a RL-05, OP-03, OV-06a, OV-06b, OV-06c, OV-07, OV-09 como S-05 do script, OV-13, OV-14a, OV-14b, OV-15a, OV-15b, OV-16, OV-17; Ctrl+C no modo público D-06 e D-07). OV-06 dividido em três; OV-07 reescrito (origem `https`, B1); sabotagens novas SB-18 a SB-25; SB-14 também no modo público. Na validação, o OV-17 ganhou duas verificações (a primeira execução completa mostrou que ele não detectava a SB-18 nem a SB-22), e a CSP das páginas ganhou `img-src 'self' data:` (o ícone `data:,` das páginas era bloqueado, e os testes de interface acusaram o erro de console). Requisitos H-01 a H-16 ligados aos testes em `docs/plan-online.md`, seção 13.1. |
| 0.9 | 2026-10-20 | Entrega O7: OV-18 (corpo exatamente no limite de 64 KB, pendência da O6) e sabotagens SB-26 e SB-27; checklist MV-L ampliado para um roteiro reproduzível de 15 itens (13.4) com o servidor `o7-servidor-rede-local`; 13.3 com a cópia limpa no lugar do clone (o trabalho não está em commit), as sabotagens SB-01 a SB-27 e os itens manuais pendentes registrados como pendentes. |
