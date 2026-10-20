# Plano técnico — Jogo da Velha Multiplayer Online

| Campo | Valor |
|---|---|
| Versão | 0.9 |
| Data | 2026-10-20 |
| Etapa SDD | 2 — Plano técnico (modo online) |
| Base | `docs/spec-online.md` v0.3; `docs/plan.md` v0.8 (contrato atual) |
| Documentos irmãos | `docs/spec-online.md` v0.3, `docs/test-plan-online.md` v0.9 |
| Status | **Em implementação.** **Encerrado na O7.** Entregas O0 a O7 aprovadas (O7 em 20/10, com o roteiro manual na rede local parcial). **A O8 foi cancelada pelo usuário**: projeto de estudo, sem publicação. Nada publicado (`docs/delivery-log.md`). |

---

## 1. Resumo da proposta

- **Mesmo servidor, mesma porta.** O `TIdHTTPServer` atual continua atendendo a página, a API e o `/health`. Ele passa a atender também as rotas de sala (`/api/rooms/...`) e o canal em tempo real (`/ws`).
- **Comandos por REST, notificações por WebSocket.** Criar, entrar, jogar, reiniciar e sair são requisições HTTP, validadas como hoje. O WebSocket só leva o estado da sala do servidor para os navegadores (e, do navegador, apenas "entrar" e "ping").
- **WebSocket feito no próprio projeto.** O Indy 10.6.2.5341 instalado não tem WebSocket. O protocolo (RFC 6455) é pequeno o bastante para uma unit própria, sem dependências, testada no `EngineCheck`. Antes de qualquer código de produção, uma **prova de conceito descartável** (Entrega O0) confirma que o `TIdHTTPServer` do Berlin aceita a troca de protocolo. Se ela falhar, o plano B é SSE e o plano C é *polling*, com as mesmas mensagens (DTO-01).
- **Motor intocado.** Cada sala tem a sua instância de `TGameEngine`. O `TGameService` continua servindo o modo local.
- **Estado completo com versão.** Toda notificação traz a sala inteira e um número de versão. O cliente descarta versões antigas. Não há diferenças parciais, fila de eventos nem reenvio.
- **Origem verificada por lista.** O canal e as rotas de sala comparam o `Origin` (esquema, host e porta) com uma lista montada pelo servidor; o `Host` da requisição não é usado (seção 7.7).
- **Rede local primeiro.** Tudo é desenvolvido e validado na rede local (Entregas O0 a O7). A publicação na internet é a Entrega O8, bloqueada até a confirmação da hospedagem; o Caddy só é documentado (DO-10, DO-11).
- **Rede local e publicação.** Por padrão o servidor continua ouvindo em `0.0.0.0` (acesso pelo celular na rede de casa, como hoje). Na internet, fica atrás de um proxy reverso com HTTPS e ouvindo só em `127.0.0.1` (`--public`).

## 2. Situação atual (inspecionada em 2026-10-16)

Tudo abaixo foi lido nos arquivos, não presumido.

| Item | Evidência | Situação |
|---|---|---|
| Delphi | `logs/step5-validation.log` | 10.1 Berlin, *compiler version 31.0*, em `C:\Program Files (x86)\Embarcadero\Studio\18.0` |
| Indy | `Studio\18.0\source\Indy10\System\IdVers.inc` | **10.6.2.5341** |
| WebSocket no Indy | listagem de `source\Indy10\Core`, `Protocols` e `System` | Não existe nenhuma unit de WebSocket. Existem `IdHashSHA` (SHA-1 nativo) e `IdCoderMIME` (Base64), suficientes para o handshake. |
| OpenSSL no Indy | `Protocols\IdSSLOpenSSLHeaders.pas` | Só a API da linha 1.0.x (`libeay32`/`ssleay32`, `TLSv1_2_method`); nada da API 1.1+ (`TLS_method`). A linha 1.0.2 não recebe mais correções. |
| Servidor | `server/src/uHttpApp.pas` | `TIdHTTPServer` criado em código; `KeepAlive := False`; `OnCommandGet` e `OnCommandOther` apontam para o mesmo roteador; lista fixa de estáticos; respostas em bytes UTF-8. |
| **Endereço de escuta** | `uHttpApp.pas`, construtor | **`Binding.IP := '0.0.0.0'`**, embora o comentário logo acima, a RNF-04, o plano e o README digam `127.0.0.1`. Arquivo e `.exe` modificados em 15/10/2026 às 20:08, depois da publicação no GitHub (19:52); a mudança não estava no `docs/delivery-log.md`. **Confirmada como intencional em 2026-10-16** (acesso pelo celular): mantida como padrão (DO-09). |
| Motor | `server/src/uGameEngine.pas` | Sem dependências; `Play`, `Reset`, `GetSnapshot` com cópia. Reutilizável por sala sem alteração. |
| Serviço | `server/src/uGameService.pas` | Uma partida global com `TCriticalSection`. |
| JSON | `server/src/uGameJson.pas` | `SnapshotToJson`, `ErrorToJson`, `ParseMoveBody`, `IsValidUtf8` (reaproveitáveis). |
| Interface | `web/index.html`, `web/app.js`, `web/style.css` | Uma requisição por vez, tempo-limite de 8 s, sem regras no JavaScript. |
| Testes Delphi | `server/EngineCheck.dpr`, `server/tests/*.pas` | 27 casos (M, SV, J), mini-framework próprio. |
| Testes Playwright | `tests/` | Projetos `api` (80) e `chromium` (29) = 109; 1 worker, sem retries; `webServer` inicia o `.exe`; variáveis `PW_PORT` e `PW_EXTERNAL_SERVER`. |
| Último resultado gravado | `tests/test-results/.last-run.json` | `failed` (R-27) às 19:12 de 15/10: é a sabotagem SB-04 no fim de `validate-step5`, ou seja, uma falha esperada. Não indica regressão. |
| Ambiente | `docs/delivery-log.md` | Windows 10 Pro 19045, Node 24.11.1, PowerShell 5.1. |

**Não executado nesta etapa:** nenhuma compilação, nenhum teste e nenhum comando no Windows. O shell do computador vinculado não estava disponível; todas as leituras foram feitas por cópia dos arquivos. Também não foi verificado se a mudança do bind está *commitada* no Git.

## 3. Decisões técnicas

### 3.1 Canal em tempo real — investigação

**O que o código-fonte do Indy 10.6.2.5341 instalado mostra** (`Protocols\IdCustomHTTPServer.pas`):

1. Cada conexão é atendida numa thread própria, e o evento `OnCommandGet` roda nessa thread. O laço `repeat ... until LCloseConnection` de `DoExecute` só lê a próxima requisição depois que o evento retorna. Ou seja, **enquanto o evento não retorna, a conexão pertence ao código do evento** e pode ser usada para outro protocolo.
2. `TIdHTTPResponseInfo.HeaderHasBeenWritten` é uma propriedade **gravável**. Depois do evento, o Indy só escreve o cabeçalho se ela for falsa e só escreve corpo se houver `ContentText` ou `ContentStream`.
3. `WriteHeader` não serve para o `101`: `SetCloseConnection` grava `Connection: close` (com `KeepAlive = False`, que é o caso do projeto, toda resposta fecha a conexão), e o handshake exige `Connection: Upgrade`. Além disso, `SetResponseNo` não tem texto para o código 101. Por isso, a resposta `101 Switching Protocols` precisa ser **escrita diretamente** em `AContext.Connection.IOHandler`, seguida de `HeaderHasBeenWritten := True`.
4. Ao fim do evento, como `CloseConnection` é verdadeiro, o Indy desconecta a conexão. Isso fecha o canal de forma limpa quando a sessão termina.
5. GET, POST e HEAD chegam em `OnCommandGet` (`DoCommandGet`); exceções de socket (`EIdSocketError`) são repassadas para cima, as demais viram 500.
6. Ao desativar o servidor (`Active := False`), o `TIdCustomTCPServer` desconecta todos os contextos e espera as threads por até `TerminateWaitTime` (padrão 5000 ms, `Core\IdCustomTCPServer.pas`).

Remy Lebeau, mantenedor do Indy, confirma que o Indy "não tem nenhum conceito de websockets" e que o canal deve ser atendido "no evento, depois de enviar a resposta de upgrade" (fórum da Atozed, tópico 6336). As linhas acima mostram que isso é viável no Indy desta instalação. A prova de conceito da Entrega O0 confirma esse comportamento na prática.

**Alternativas avaliadas:**

| | Alternativa | Prós | Contras | Veredito |
|---|---|---|---|---|
| A | **WebSocket próprio sobre o `TIdHTTPServer` atual**, rota `/ws`, mesma porta | Mesma origem (sem CORS, RNF-05); bidirecional; sem dependência; suporte nativo em todo navegador e no Node 24; proxies reversos (Caddy) repassam sem configuração; não conta no limite de ~6 conexões HTTP/1.1 por servidor do navegador | Implementar handshake e quadros (RFC 6455): estimativa de 300 a 400 linhas, testáveis sem rede; uma thread do Indy por canal aberto | **Escolhida (DTO-01)** |
| B | WebSocket num `TIdTCPServer` separado, outra porta | Isola o protocolo | Outra origem (CORS e `Origin`), segunda porta no firewall e no proxy, mesmo código de protocolo | Rejeitada: mais peças, nenhum ganho |
| C | Biblioteca de terceiros (sgcWebSockets, comercial; projetos abertos diversos) | Protocolo pronto | Contraria a RNF-03 (sem componentes de terceiros); licença ou compatibilidade com o Berlin e com o Indy 10.6.2.5341 a verificar; mais uma coisa para manter | Rejeitada sem a sua aprovação explícita |
| D | **Server-Sent Events** (SSE) sobre o `TIdHTTPServer` | Protocolo trivial (texto); `EventSource` reconecta sozinho | Só servidor → cliente; `EventSource` não envia cabeçalhos, então o token iria na URL (log, histórico) ou em cookie (duas abas do mesmo navegador viram o mesmo jogador também no teste); conta no limite de ~6 conexões HTTP/1.1 por servidor; alguns proxies acumulam a resposta; também ocupa uma thread por cliente | **Plano B**, se a O0 reprovar a alternativa A |
| E | *Polling* (`GET` da sala a cada 1–2 s) | Nenhum código novo de protocolo | Latência de até o intervalo; tráfego constante; presença só aproximada | **Plano C** e possível contingência futura (DO-15) |
| F | WebBroker/DataSnap | — | Sem WebSocket no Berlin; dependem da edição; mais camadas (o plano atual já os evita) | Rejeitada |

### 3.2 Tabela de decisões

| # | Decisão | Justificativa |
|---|---|---|
| DTO-01 | Canal em tempo real por **WebSocket (RFC 6455, versão 13)**, implementado no projeto, na rota `/ws` do `TIdHTTPServer` existente. A sessão roda dentro do `OnCommandGet` até o canal fechar. | Seção 3.1. Mesma origem, sem dependências; o Indy instalado permite assumir a conexão. |
| DTO-02 | **Comandos por REST, notificações pelo canal.** O canal aceita do cliente só `entrar` e `ping`. | Uma única via de validação para jogadas (a HTTP, já testada e com códigos de status), reaproveitamento de `ParseMoveBody`, testes de API simples, e a troca de transporte (plano B/C) não toca nas regras. RNO-12 fica estrutural: não existe mensagem de jogo vinda do cliente pelo canal. |
| DTO-03 | **Estado completo + versão por sala**, sem diferenças parciais nem reenvio de eventos. | Reconexão trivial (o servidor manda o estado atual); notificações duplicadas ou fora de ordem são descartadas pela versão (RNO-08). |
| DTO-04 | **Uma instância de `TGameEngine` por sala**; motor e `TGameService` sem alteração. | Regras já provadas por M-01 a M-12 (inclusive o exaustivo) valem para todas as salas; o modo local não é tocado. |
| DTO-05 | **Seção crítica por sala** + seção crítica do registro de salas. Salas são acessadas por **interface** (`IRoom`, contagem de referência), para que uma sessão que ainda segura uma sala removida não aponte para memória liberada. | Isolamento de desempenho entre salas (RNO-11); segurança de memória sem coletor de lixo. |
| DTO-06 | **Caixa de saída por canal**: quem muda a sala só **enfileira** a mensagem; a **thread do próprio canal** é a única que escreve no seu socket. Estados pendentes são **aglutinados** (fica só o mais recente). | Um cliente lento não trava a jogada de ninguém; não há duas threads escrevendo no mesmo socket; memória limitada. |
| DTO-07 | **Token de 128 bits** de `BCryptGenRandom` (Windows), em hexadecimal; enviado em `Authorization: Bearer <token>` nas requisições e na mensagem `entrar` do canal, nunca na URL. | Não adivinhável; não aparece em log de acesso, histórico ou cabeçalho `Referer`. `Random` do Delphi não é criptográfico. |
| DTO-08 | **Código de sala de 6 caracteres** de um alfabeto de 31 símbolos sem caracteres ambíguos (≈ 887 milhões de combinações), do mesmo gerador seguro. | Fácil de ditar e digitar; com o limite de taxa (DTO-20), adivinhar uma sala ativa é impraticável. |
| DTO-09 | **HTTPS por proxy reverso** (Caddy, sugerido) na publicação; o Delphi não faz TLS. | O OpenSSL suportado por este Indy é a linha 1.0.x, que já não recebe correções; o proxy dá certificados automáticos e repassa WebSocket. |
| DTO-10 | **Página separada** `/online.html` + `/online.js` + `/online.css`, acrescentados à **lista fixa** de estáticos (DT-04). A página local recebe só um link. | Os 29 testes de interface e o A-10 continuam valendo sem mudança; nenhuma rota dinâmica de arquivos. |
| DTO-11 | Token guardado em **`localStorage`**, por código de sala, com validade de 24 h (DO-05). | Atualizar a página, fechar e reabrir a aba e voltar pelo link retomam o lugar. |
| DTO-12 | **Batimento de aplicação**: o cliente envia `{"tipo":"ping"}` a cada `intervaloPingMs` (informado pelo servidor no `bem_vindo`; 20 s no padrão); o servidor responde `pong` e fecha canais sem nenhuma mensagem recebida há 60 s. O servidor responde também a quadros *ping* do protocolo. | O JavaScript do navegador não vê quadros *ping/pong* do protocolo; assim os dois lados detectam queda silenciosa. 20 s fica abaixo do tempo ocioso comum de proxies (60 s). |
| DTO-13 | **Tempos e limites por linha de comando** (seção 11.4); **relógio e gerador aleatório injetáveis** no domínio. | Testes de abandono e de inatividade em segundos, sem esperas de minutos e sem respostas falsas (RNFO-11). |
| DTO-14 | **Nenhuma dependência npm nova**: testes do canal com o `WebSocket` nativo do Node 24 e com `node:net` (socket cru, já usado em `support/raw-http.ts`) para pedidos inválidos; queda do canal no navegador com `page.routeWebSocket` (Playwright ≥ 1.48), conectado ao servidor real. | RNFO-02. A O0 confirma o `WebSocket` global no Node 24.11.1. |
| DTO-15 | Testes de ciclo de vida (reinício, abandono, encerramento, modo público, limites) usam um **servidor dedicado**, iniciado pelo próprio teste em outra porta, com opções próprias. | Não interferem no servidor da suíte; permitem reiniciar o processo. |
| DTO-16 | **`--bind <ip>`, padrão `0.0.0.0`** (o atual); com `--public` e sem `--bind`, `127.0.0.1`. | Mantém o acesso pela rede local que você usa hoje (DO-09) e permite restringir quando necessário; na publicação, só o proxy fala com o Delphi. |
| DTO-17 | **`--public`**: desativa `/api/game*` (404), exige pelo menos um `--allowed-origin` `https`, desliga as origens automáticas, recusa canal sem `Origin`, usa `127.0.0.1` como bind padrão e ativa os limites estritos. | A partida global não deve ficar exposta a qualquer visitante (DO-07); na internet, só a origem pública do jogo é legítima. |
| DTO-18 | SHA-1 e Base64 do handshake pela RTL (`System.Hash.THashSHA1`, `System.NetEncoding.TNetEncoding.Base64`), **se confirmados no Berlin na O0**; senão, `IdHashSHA.TIdHashSHA1` e `IdCoderMIME.TIdEncoderMIME`, presentes na instalação. | Com a RTL, a unit do protocolo não depende do Indy e é testável no `EngineCheck`. |
| DTO-19 | **Entrega O0: prova de conceito descartável** antes de qualquer código de produção. | O ponto mais arriscado (o Indy do Berlin assumir a conexão) é verificado antes de se comprometer com ele. |
| DTO-20 | **Limite de taxa por endereço**, em memória, com janela fixa de 60 s. `X-Forwarded-For` só é considerado com `--trust-proxy` e quando a conexão vem de `127.0.0.1`. | Contém força bruta de códigos e criação em massa de salas sem dependência externa. |
| DTO-21 | Domínio de salas, JSON e protocolo do canal em units **sem Indy**; o Indy fica só em `uHttpApp`, `uRoomHttp` e `uWsSession`. | Mesmo princípio do RNF-07: o que tem regra é testável sem rede. |
| DTO-22 | **Política de origem por lista** (seção 7.7), numa unit sem Indy (`uOriginPolicy`): `Origin` normalizado (RFC 6454) e comparado por igualdade exata de esquema, host e porta com uma lista montada pelo servidor; nunca pelo `Host`. No modo local, a lista automática vem de `GStack.GetLocalAddressList` (Indy 10.6.2.5341, lido em `System\IdStack.pas`), só com IPv4 privados, recalculada a cada 60 s. | Comparar com o `Host` aceitaria um ataque de *DNS rebinding* (o `Host` e o `Origin` do atacante são iguais). A lista vem da configuração do próprio servidor, que o cliente não controla. |
| DTO-23 | **Publicação adiada** (DO-10): as Entregas O0 a O7 são validadas na rede local; a O8 (domínio, HTTPS, Caddy) só começa depois de você confirmar a hospedagem. O Caddy fica documentado na seção 16.3, sem instalação nem configuração (DO-11). | Decisão sua de 2026-10-16. |

## 4. Arquitetura proposta

### 4.1 Componentes

```
┌──── Navegador A (X) ────┐            ┌──── Navegador B (O) ────┐
│ online.html/.js/.css    │            │ online.html/.js/.css    │
│  fetch  ──REST──┐       │            │       ┌──REST──  fetch  │
│  WebSocket ◄─┐  │       │            │       │  ┌─► WebSocket  │
└──────────────┼──┼───────┘            └───────┼──┼──────────────┘
               │  │      mesma origem          │  │
               │  │  (http://127.0.0.1:8765 ou https://<domínio> via proxy)
┌──────────────┼──┼────── TicTacToeServer.exe ─┼──┼──────────────────────┐
│ uHttpApp     │  └──► roteador ◄──────────────┘  │  TIdHTTPServer        │
│   /health, /api/game*, estáticos (como hoje)    │  (uma thread por      │
│   /api/rooms*  ─► uRoomHttp                     │   conexão)            │
│   /ws          ─► uWsSession ◄──────────────────┘                       │
│                    │  laço da sessão: lê quadros, envia a caixa de saída │
│ uRoomHttp ─────────┼──► uRoomRegistry ──► IRoom (uRoom)                 │
│                    │        │  seção crítica      │ seção crítica       │
│                    │        │  do registro        │ por sala            │
│                    │        │                     └─► TGameEngine (1/sala)│
│                    └──► uRoomHub (inscrições por sala, caixas de saída) │
│ uRoomJson (sala ⇄ JSON, mensagens)  uWebSocket (handshake, quadros)     │
│ uSecureRandom (BCryptGenRandom)     uClock (GetTickCount64)              │
│ uRoomJanitor (thread: abandono e período de lembrança)                   │
│ uGameService ─► TGameEngine (partida global do modo local, como hoje)    │
└──────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Fluxo de mensagens

**Criar e entrar**

```
A                         Servidor                                B
│ POST /api/rooms ───────► registro: novo código, X = token tA
│ ◄── 201 {sala v1, jogador X, tA}
│ GET /ws (upgrade) ─────► 101
│ {"tipo":"entrar",sala,tA} ► X conectado (v2)
│ ◄── bem_vindo {voce:X, sala v2}
│                                    ◄─── POST /api/rooms/K7PM2Q/players
│                          O = token tB, EM_JOGO (v3) ───► 201 {sala v3, jogador O, tB}
│ ◄── estado ENTRADA (v3)  (caixa de saída de A)
│                                    ◄─── GET /ws + entrar(tB)
│                          O conectado (v4) ─────────────► bem_vindo {voce:O, sala v4}
│ ◄── estado CONEXAO (v4)
```

**Jogada**

```
A (vez de X)              Servidor                                B
│ POST .../moves {posicao:4}, Authorization: Bearer tA
│                          seção crítica da sala:
│                            valida (RNO-10) → motor.Play → v5 → JSON
│                          fim da seção crítica
│                          hub.Publicar(K7PM2Q, estado JOGADA v5)
│ ◄── 200 {sala v5}                  (enfileira para A e para B)
│ ◄── estado JOGADA v5 (descartado por A: versão já aplicada)
│                                    ──────────────────────► estado JOGADA v5
```

**Queda e reconexão**

```
B: canal cai ──► servidor: sessão termina → O desconectado (v6) → A recebe estado DESCONEXAO
A joga (v7) → B não recebe (fora do ar)
B: reconecta (espera crescente) → entrar(tB) → O conectado (v8)
   → B recebe bem_vindo {sala v8} (inclui a jogada v7); A recebe estado CONEXAO v8
```

**Reinício do servidor**

```
servidor cai ──► A e B: "Reconectando…" (tentativas com espera crescente)
servidor volta (sem salas) ──► entrar(tA) → erro SALA_INEXISTENTE + fechamento 4404
   → A: mensagem, apaga o token guardado, para de reconectar, "Criar nova sala"
```

### 4.3 Mudanças de comportamento em relação ao que existe

Nenhuma delas altera o contrato de `docs/plan.md`, seções 3.1 a 3.4 (as rotas `/health` e `/api/game*`, seus corpos, códigos e mensagens).

| # | O quê | Hoje | Depois | Entrega |
|---|---|---|---|---|
| MC-01 | Endereço de escuta | `0.0.0.0` fixo no código (comentário e documentos dizem `127.0.0.1`) | `0.0.0.0` continua o padrão; `--bind` para outro endereço; `127.0.0.1` com `--public`; comentário, `docs/spec.md` RNF-04, `docs/plan.md` DT-07 e README alinhados | O2 |
| MC-02 | `/api/rooms`, `/api/rooms/...` | 404 `ROTA_NAO_ENCONTRADA` | Novas rotas (seção 6) | O2 |
| MC-03 | `/ws` | 404 `ROTA_NAO_ENCONTRADA` | 101 / 400 / 405 / 426 / 403 (seção 7) | O3 |
| MC-04 | `/online.html`, `/online.js`, `/online.css` | 404 | 200 (lista fixa) | O4 |
| MC-05 | Página `/` | — | Ganha o link "Jogar online" | O4 |
| MC-06 | Cabeçalhos de todas as respostas | — | Acrescenta `X-Content-Type-Options` e `Referrer-Policy`; páginas ganham `Content-Security-Policy` | O6 |
| MC-07 | `/api/game*` com `--public` | (não existe a opção) | 404 só com `--public`; sem a opção, igual a hoje | O6 |
| MC-08 | Log do console | Uma linha por requisição | Mais linhas de abertura e fechamento de canal (sem tokens) | O3 |

### 4.4 Impacto nas classes e arquivos atuais

| Arquivo | Impacto | Detalhe |
|---|---|---|
| `uGameEngine.pas` | **Nenhum** | Reutilizado: uma instância por sala. |
| `uGameService.pas` | **Nenhum** | Continua sendo a partida do modo local. |
| `uGameJson.pas` | **Aditivo** | Nova `SnapshotToJsonValue` (devolve `TJSONObject`), usada por `SnapshotToJson` (mesmo texto, protegido por J-01) e por `uRoomJson`, para que a partida dentro da sala tenha exatamente o formato do modo local. Funções e constantes atuais intocadas. |
| `uConsoleLog.pas` | **Nenhum** | — |
| `uHttpApp.pas` | **Alterado** | (a) recebe `TServerOptions` no construtor; `Binding.IP := Options.BindIP`; `MaxConnections`. (b) Roteador: `/api/rooms*` → `uRoomHttp`; `/ws` → `uWsSession`; resto igual. (c) Lista fixa ganha `online.*`; obtém os IPv4 locais com `GStack.GetLocalAddressList` e os entrega à `uOriginPolicy` (a cada 60 s). (d) O `try..except` de `HandleCommand` não pode transformar em 500 uma exceção de socket do canal (a resposta já foi trocada por WebSocket); o caminho `/ws` trata as próprias exceções. (e) Log de `/ws` com 101 e fechamento. (f) Cabeçalhos de segurança (O6). (g) Cria e libera registro, hub e faxineiro. |
| `TicTacToeServer.dpr` | **Alterado** | `ReadOptions` sai para `uServerOptions` (opções novas da seção 11.4); `uses` das units novas; ordem de desligamento (seção 11.3). Mensagens atuais de partida mantidas. |
| `EngineCheck.dpr` | **Alterado** | `uses` das units novas e chamadas dos grupos novos; casos M, SV e J intocados. |
| `web/index.html` | **Mínimo** (O4) | Link "Jogar online". |
| `web/app.js`, `web/style.css` | **Nenhum** | — |
| `tests/playwright.config.ts` | **Aditivo** | Projetos novos (seção 12); os projetos `api` e `chromium` continuam iguais. |
| `tests/support/*`, `tests/api`, `tests/rules`, `tests/ui` | **Nenhum** | Arquivos novos em `tests/online/` e `tests/support/online/`. |
| `scripts/build.cmd` | **Nenhum previsto** | As units novas entram pelos `uses` dos `.dpr`; confirmar na O1. |
| `scripts/validate-online-oN.*` | **Novos** | Um par por entrega, como DT-16. |
| `README.md` | O7 (rede local) e O8 (publicação) | Seção do modo online na rede local; a de publicação entra na O8. |

**Units novas:**

| Unit | Responsabilidade | Depende de | Indy? |
|---|---|---|---|
| `uSecureRandom.pas` | `IRandomSource`; implementação com `BCryptGenRandom` (`bcrypt.dll`, declaração externa); gera tokens e códigos | `Winapi.Windows`, `System.SysUtils` | Não |
| `uClock.pas` | `IClock` (`NowMs` monotônico com `GetTickCount64`); `TManualClock` para testes | `Winapi.Windows` | Não |
| `uRoom.pas` | `IRoom`/`TRoom`: lugares, tokens, presença, versão, número da partida, situação; operações `Join`, `Play`, `NewGame`, `Leave`, `Attach`, `Detach`, `Snapshot`, cada uma inteira na seção crítica da sala | `uGameEngine`, `System.SyncObjs` | Não |
| `uRoomRegistry.pas` | `TRoomRegistry`: criar (código único), localizar, lembrar encerradas, varrer abandonadas, limite de salas | `uRoom`, `uSecureRandom`, `uClock`, `System.Generics.Collections` | Não |
| `uRoomJson.pas` | Sala → JSON; resposta de criação e entrada; mensagens do canal; leitura das mensagens do cliente; códigos e textos de erro novos | `uRoom`, `uGameJson`, `System.JSON` | Não |
| `uWebSocket.pas` | Validação do pedido de abertura e chave de aceite; decodificador incremental de quadros (máscara, tamanhos 7/16/64 bits, fragmentos, controle, limites, UTF-8); codificação de quadros do servidor | `System.SysUtils`, `System.Hash`/`System.NetEncoding` (DTO-18), `uGameJson.IsValidUtf8` | Não |
| `uRoomHub.pas` | `TRoomHub`: inscrições por sala e lugar, substituição, `Publish`; `TOutbox` (aglutinação) | `System.SyncObjs`, `System.Generics.Collections` | Não |
| `uRoomJanitor.pas` | Thread que chama `Registry.Sweep` periodicamente | `uRoomRegistry`, `System.Classes` | Não |
| `uServerOptions.pas` | Leitura e validação da linha de comando | `System.SysUtils` | Não |
| `uOriginPolicy.pas` | Normalização e comparação de `Origin`; montagem da lista a partir das opções e de uma lista de IPs recebida de fora (testável sem rede) | `System.SysUtils` | Não |
| `uRateLimiter.pas` (O6) | Janela fixa por endereço e por categoria | `uClock`, `System.SyncObjs` | Não |
| `uRoomHttp.pas` | Rotas REST de sala: recebe método, caminho cru, `Authorization` e corpo já lidos por `uHttpApp`; chama o registro; devolve status, JSON e cabeçalhos; publica no hub (O3) | `uRoomRegistry`, `uRoomJson`, `uGameJson` (`uRoomHub` na O3) | Não *(v0.4: a leitura do Indy ficou em `uHttpApp`)* |
| `uWsSession.pas` | Troca de protocolo e laço da sessão sobre `TIdIOHandler` | Indy, `uWebSocket`, `uRoomRegistry`, `uRoomHub`, `uRoomJson` | Sim |

## 5. Modelo de dados

```pascal
type
  TSeat = (seX, seO);                       { ceX / ceO do motor }
  TRoomSituation = (rsWaiting, rsPlaying, rsClosed);
  TCloseReason = (crNone, crLeave, crAbandoned);

  TSeatState = record
    Occupied: Boolean;
    Token: string;               { 32 hex; vazio se livre }
    Connected: Boolean;
    ConnectionId: Int64;         { 0 = sem canal; identifica o canal atual (RNO-15) }
  end;

  TRoomSnapshot = record         { cópia independente, como TGameSnapshot (DT-18) }
    Code: string;
    Situation: TRoomSituation;
    Version: Int64;
    GameNumber: Integer;
    Seats: array[TSeat] of record Occupied, Connected: Boolean; end;   { sem tokens }
    Game: TGameSnapshot;
    CloseReason: TCloseReason;
  end;

  TRoomResult = (rrOk, rrNotFound, rrClosed, rrInvalidToken, rrFull,
                 rrWaitingOpponent, rrInvalidPosition, rrGameOver,
                 rrNotYourTurn, rrCellOccupied, rrGameInProgress, rrCapacity);

  TRoomOutcome = record
    Result: TRoomResult;
    Changed: Boolean;            { True => versão incrementada e notificação devida }
    Snapshot: TRoomSnapshot;     { estado depois da operação, lido na mesma seção crítica }
  end;

  IRoom = interface
    function Code: string;
    function Join(const AToken: string; out ASeat: TSeat; out AIssuedToken: string): TRoomOutcome;
    function Play(const AToken: string; APosition: Integer): TRoomOutcome;
    function NewGame(const AToken: string): TRoomOutcome;
    function Leave(const AToken: string): TRoomOutcome;
    function Attach(const AToken: string; AConnectionId: Int64; out ASeat: TSeat;
      out AReplacedId: Int64): TRoomOutcome;
    function Detach(ASeat: TSeat; AConnectionId: Int64): TRoomOutcome;  { ignora se não for o canal atual }
    function Snapshot: TRoomSnapshot;
    function LastActivityMs: UInt64;
    function AnyConnected: Boolean;
    function CloseAbandoned(ANowMs, ATtlMs: UInt64): TRoomOutcome;
  end;
```

- **Registro:** `TDictionary<string, IRoom>` para salas ativas e `TDictionary<string, TRememberedRoom>` (código → momento e motivo do encerramento) para o período de lembrança, os dois sob a seção crítica do registro.
- **Hub:** `TDictionary<string, TList<ISubscriber>>` por código de sala; cada `ISubscriber` tem o lugar, o identificador do canal e uma `TOutbox`.
- **`TOutbox`:** fila de no máximo 16 mensagens, com seção crítica e `TEvent`. Um `estado` novo substitui um `estado` ainda não enviado. `sala_encerrada` e `erro` nunca são descartados e marcam o canal para fechar depois do envio. Se a fila estourar, o canal é fechado com 1008.
- **Tokens** ficam só na sala, em memória. A comparação é exata. Nenhuma estrutura de log ou de JSON de consulta os contém.

## 6. Contrato HTTP das salas

Base: a mesma do modo local. Todas as respostas são `application/json; charset=utf-8` e `Cache-Control: no-store`, geradas como bytes UTF-8 (DT-08).

### 6.1 Rotas

| Método | Rota | Autenticação | Sucesso | `Allow` no 405 |
|---|---|---|---|---|
| POST | `/api/rooms` | — | 201 + `{sala, jogador}`, cabeçalho `Location: /api/rooms/<CÓDIGO>` | `POST` |
| GET, HEAD | `/api/rooms/{codigo}` | — | 200 + `{sala}` | `GET, HEAD` |
| POST | `/api/rooms/{codigo}/players` | opcional (reentrada) | 201 + `{sala, jogador}`; reentrada: 200 | `POST` |
| POST | `/api/rooms/{codigo}/moves` | obrigatória | 200 + `{sala}` | `POST` |
| POST | `/api/rooms/{codigo}/reset` | obrigatória | 200 + `{sala}` | `POST` |
| POST | `/api/rooms/{codigo}/leave` | obrigatória | 200 + `{sala}` (situação `ENCERRADA`) | `POST` |
| GET | `/ws` | na mensagem `entrar` | 101 (seção 7) | `GET` |

- `{codigo}`: aceito sem distinção de maiúsculas (normalizado para maiúsculas). Qualquer valor que não tenha 6 caracteres do alfabeto responde 404 `SALA_INEXISTENTE` (CAO-30).
- Qualquer outra sub-rota (`/api/rooms/K7PM2Q/x`, `/api/rooms/`, `/api/rooms/K7PM2Q/`) responde 404 `ROTA_NAO_ENCONTRADA`, como DT-21.
- Corpo: só `moves` usa (`{"posicao": n}`, mesmas regras de `docs/plan.md` 3.3). Nas outras rotas, o corpo é ignorado. Qualquer corpo acima de 1.024 bytes responde 413 `CORPO_MUITO_GRANDE` (lido pelo `Content-Length` antes de processar).

### 6.2 Objeto sala

```json
{
  "codigo": "K7PM2Q",
  "situacao": "EM_JOGO",
  "versao": 7,
  "numeroDaPartida": 1,
  "jogadores": {
    "X": { "ocupado": true, "conectado": true },
    "O": { "ocupado": true, "conectado": false }
  },
  "partida": {
    "tabuleiro": ["X", "", "", "", "O", "", "", "", ""],
    "status": "EM_ANDAMENTO",
    "jogadorDaVez": "X",
    "vencedor": null,
    "celulasVencedoras": []
  },
  "motivoEncerramento": null
}
```

| Campo | Regras |
|---|---|
| `codigo` | 6 caracteres de `23456789ABCDEFGHJKMNPQRSTUVWXYZ` |
| `situacao` | `AGUARDANDO_OPONENTE`, `EM_JOGO` ou `ENCERRADA` |
| `versao` | inteiro ≥ 1, +1 a cada mudança aceita (RNO-07) |
| `numeroDaPartida` | inteiro ≥ 1 |
| `jogadores.X`, `jogadores.O` | `ocupado` e `conectado` (booleanos); **nunca** o token |
| `partida` | exatamente o objeto de estado de `docs/plan.md` 3.2, gerado pela mesma função |
| `motivoEncerramento` | `null`, `"SAIDA"` ou `"ABANDONO"` |

A ordem dos campos é fixa (verificada no RJ-01), como no modo local.

### 6.3 Criação e entrada

```http
POST /api/rooms
```
```http
HTTP/1.1 201 Created
Location: /api/rooms/K7PM2Q
Content-Type: application/json; charset=utf-8
Cache-Control: no-store

{"sala":{"codigo":"K7PM2Q","situacao":"AGUARDANDO_OPONENTE","versao":1,"numeroDaPartida":1,
 "jogadores":{"X":{"ocupado":true,"conectado":false},"O":{"ocupado":false,"conectado":false}},
 "partida":{"tabuleiro":["","","","","","","","",""],"status":"EM_ANDAMENTO","jogadorDaVez":"X",
 "vencedor":null,"celulasVencedoras":[]},"motivoEncerramento":null},
 "jogador":{"simbolo":"X","token":"3f9c0a6d1e7b42c8a5d09e61f2b4c7a8"}}
```

```http
POST /api/rooms/k7pm2q/players
```
→ 201 com `"situacao":"EM_JOGO"`, `"versao":2` e `"jogador":{"simbolo":"O","token":"…"}`.

Com `Authorization: Bearer <token de um lugar da sala>`, a resposta é 200 com o mesmo lugar e token, e a sala não muda (RNO-05).

### 6.4 Identificação e validação dos jogadores

- O servidor emite o token ao ocupar o lugar (criação → X, entrada → O). É a única credencial e vale só naquela sala (RNO-06).
- Envio: `Authorization: Bearer <32 hex>`. O esquema `Bearer` é aceito sem distinção de maiúsculas; o token precisa ter exatamente 32 caracteres `0-9a-f`. Qualquer outra forma (ausente, `Basic`, curto, maiúsculas, espaços extras) responde 401 `TOKEN_INVALIDO`.
- O lugar é **derivado do token**; nenhum campo do corpo indica jogador ou símbolo (RN-07).
- O navegador guarda `{token, simbolo, salvoEm}` em `localStorage`, na chave `jdv-online:<CÓDIGO>` (DTO-11). A entrada é apagada quando o servidor responde `SALA_INEXISTENTE`, `SALA_ENCERRADA` ou `TOKEN_INVALIDO`, e quando tem mais de 24 h.
- O token nunca vai na URL, nem no link compartilhável, nem no log. O log registra método, caminho, status e lugar (`X`/`O`), nunca o cabeçalho `Authorization` nem o corpo de `entrar`.
- Sem contas: quem tem o token joga por aquele lugar. Isso está declarado na spec (5.2) e é suficiente para um jogo casual. O risco residual está na seção 17.

### 6.5 Ordem de validação

Para todas as rotas de sala, parando no primeiro erro:

| Passo | Verificação | Erro | Rotas |
|---|---|---|---|
| 0 | Rota e método conhecidos | 404 `ROTA_NAO_ENCONTRADA` / 405 `METODO_NAO_PERMITIDO` | todas |
| 1 | `Origin`, quando presente, permitida pela seção 7.7 (O3); limite de taxa (O6) | 403 `ORIGEM_NAO_PERMITIDA`; 429 `LIMITE_DE_REQUISICOES` | todas as rotas `POST` de sala (origem); todas (taxa) |
| 2 | Corpo ≤ 1.024 bytes | 413 `CORPO_MUITO_GRANDE` | todas |
| 3 | Sala existe (código válido e conhecido) | 404 `SALA_INEXISTENTE` | todas exceto criar |
| 4 | Sala não encerrada | 410 `SALA_ENCERRADA` | todas exceto criar |
| 5 | Token válido para a sala | 401 `TOKEN_INVALIDO` | moves, reset, leave (em players, token inválido é ignorado e trata-se como entrada nova) |
| 6 | Corpo é objeto JSON; posição inteira 0..8 | 400 `CORPO_INVALIDO` / `POSICAO_INVALIDA` | moves |
| 7 | Sala com dois jogadores | 409 `AGUARDANDO_OPONENTE` | moves, reset |
| 8 | Lugar livre | 409 `SALA_CHEIA` | players |
| 9 | Partida em andamento (moves) / encerrada (reset) | 409 `PARTIDA_ENCERRADA` / `PARTIDA_EM_ANDAMENTO` | moves / reset |
| 10 | Vez do jogador | 409 `VEZ_DO_OPONENTE` | moves |
| 11 | Célula vazia | 409 `CELULA_OCUPADA` | moves |
| — | Capacidade de salas | 503 `CAPACIDADE_ESGOTADA` | criar |

Os passos 3 a 11 de `moves` são a RNO-10. Os passos 6, 9 e 11 preservam a RN-15: corpo → posição → partida encerrada → célula. A posição 0..8 é verificada pela sala antes do motor e de novo pelo motor (defesa em profundidade, como no modo local).

### 6.6 Códigos de erro novos

Formato único `{"erro":{"codigo":"…","mensagem":"…"}}`. Os códigos atuais (`CORPO_INVALIDO`, `POSICAO_INVALIDA`, `PARTIDA_ENCERRADA`, `CELULA_OCUPADA`, `ROTA_NAO_ENCONTRADA`, `METODO_NAO_PERMITIDO`, `ERRO_INTERNO`) são reutilizados com as mesmas mensagens.

| HTTP | `codigo` | `mensagem` |
|---|---|---|
| 404 | `SALA_INEXISTENTE` | Sala não encontrada. Confira o código. |
| 410 | `SALA_ENCERRADA` | Esta sala foi encerrada. |
| 409 | `SALA_CHEIA` | Esta sala já tem dois jogadores. |
| 401 | `TOKEN_INVALIDO` | Jogador não identificado nesta sala. |
| 409 | `AGUARDANDO_OPONENTE` | Aguarde o segundo jogador entrar na sala. |
| 409 | `VEZ_DO_OPONENTE` | Não é a sua vez. |
| 409 | `PARTIDA_EM_ANDAMENTO` | A partida ainda está em andamento. |
| 413 | `CORPO_MUITO_GRANDE` | O corpo da requisição é grande demais. |
| 429 | `LIMITE_DE_REQUISICOES` | Muitas requisições. Tente novamente em instantes. (com `Retry-After` em segundos) |
| 503 | `CAPACIDADE_ESGOTADA` | O servidor está sem vagas para novas salas. Tente mais tarde. |
| 400 | `HANDSHAKE_INVALIDO` | Requisição de WebSocket inválida. |
| 426 | `VERSAO_WEBSOCKET` | Versão de WebSocket não suportada. (com `Sec-WebSocket-Version: 13`) |
| 403 | `ORIGEM_NAO_PERMITIDA` | Origem não permitida. |

## 7. Protocolo do canal em tempo real (WebSocket)

### 7.1 Abertura

```http
GET /ws HTTP/1.1
Host: 127.0.0.1:8765
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
Origin: http://127.0.0.1:8765
```
```http
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

- `Sec-WebSocket-Accept` = Base64(SHA-1(chave + `258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)). O par acima é o exemplo da RFC 6455 e é o caso WS-01.
- Exigências, nesta ordem: método `GET` (senão 405 `Allow: GET`); `Upgrade` contém `websocket`, `Connection` contém o token `Upgrade` (sem distinção de maiúsculas) e `Sec-WebSocket-Key` decodifica em 16 bytes (senão 400 `HANDSHAKE_INVALIDO`); `Sec-WebSocket-Version` é `13` (senão 426 com `Sec-WebSocket-Version: 13`); `Origin` permitida (senão 403 `ORIGEM_NAO_PERMITIDA`).
- `Origin`: verificado pela política de origem da seção 7.7. Origem não permitida → 403 `ORIGEM_NAO_PERMITIDA`.
- Sem subprotocolo e sem extensões: `Sec-WebSocket-Protocol` e `Sec-WebSocket-Extensions` (por exemplo, `permessage-deflate`) são ignorados e não aparecem na resposta.
- A resposta 101 é escrita diretamente no `IOHandler` e `HeaderHasBeenWritten := True` (seção 3.1, itens 2 e 3).

### 7.2 Mensagens do cliente

Todas são quadros de **texto** com um objeto JSON em UTF-8.

```json
{ "tipo": "entrar", "protocolo": 1, "sala": "K7PM2Q", "token": "3f9c0a6d1e7b42c8a5d09e61f2b4c7a8" }
```
```json
{ "tipo": "ping", "id": 17 }
```

- `entrar` precisa ser a primeira mensagem, dentro de 5 s depois da abertura; só pode ser enviada uma vez.
- `ping` só depois de `entrar`; `id` é um inteiro de 0 a 2³¹−1 devolvido no `pong`.
- Qualquer outra coisa (tipo desconhecido como `jogada` ou `estado`, campos faltando ou de tipo errado, JSON que não é objeto, texto que não é JSON, quadro binário, `entrar` repetido, `ping` antes de `entrar`) → mensagem `erro` `MENSAGEM_INVALIDA` e fechamento 4400 (CAO-28).

### 7.3 Mensagens do servidor

```json
{ "tipo": "bem_vindo", "protocolo": 1, "voce": "O", "intervaloPingMs": 20000, "sala": { "…": "objeto da seção 6.2" } }
```
```json
{ "tipo": "estado", "motivo": "JOGADA", "sala": { "…": "objeto da seção 6.2" } }
```
`motivo`: `ENTRADA`, `JOGADA`, `NOVA_PARTIDA`, `CONEXAO`, `DESCONEXAO`.
```json
{ "tipo": "pong", "id": 17 }
```
```json
{ "tipo": "sala_encerrada", "motivo": "SAIDA", "sala": { "…": "situacao ENCERRADA" } }
```
```json
{ "tipo": "erro", "codigo": "TOKEN_INVALIDO", "mensagem": "Jogador não identificado nesta sala." }
```

- `bem_vindo` é sempre a primeira mensagem do servidor depois de um `entrar` aceito e traz o estado lido **depois** da inscrição no hub (seção 8.3). `intervaloPingMs` é um terço de `--ws-idle-seconds` (20.000 no padrão): o cliente usa esse valor, de modo que um servidor de teste com prazo curto não derruba clientes saudáveis.
- Não há `estado` em resposta a `ping`.
- `sala_encerrada` e `erro` são seguidos do fechamento do canal (seção 7.4).

### 7.4 Códigos de fechamento

| Código | Motivo | Quando | O cliente reconecta? |
|---|---|---|---|
| 1000 | Normal | O cliente fechou (aba fechada) | — |
| 1001 | Servidor encerrando | Ctrl+C / desligamento (CAO-50) | Sim |
| 1002 | Erro de protocolo | Quadro sem máscara, opcode reservado, bits RSV, continuação inválida | Sim |
| 1007 | Dados inválidos | Texto que não é UTF-8 válido | Sim |
| 1008 | Política | Caixa de saída estourada | Sim |
| 1009 | Grande demais | Mensagem acima de 4.096 bytes | Sim |
| 1011 | Erro interno | Exceção inesperada na sessão | Sim |
| 4000 | `SUBSTITUIDA` | Outro canal assumiu o mesmo lugar (RNO-15) | **Não** ("Usar nesta aba") |
| 4400 | `MENSAGEM_INVALIDA` | Seção 7.2 | **Não** |
| 4401 | `TOKEN_INVALIDO` | Token não é de um lugar da sala | **Não** |
| 4404 | `SALA_INEXISTENTE` | Sala desconhecida (inclusive após reinício) | **Não** |
| 4408 | `TEMPO_ESGOTADO` | Sem `entrar` em 5 s ou sem mensagens há 60 s | Sim |
| 4410 | `SALA_ENCERRADA` | Sala encerrada | **Não** |

Antes de um fechamento 4xxx, o servidor envia a mensagem `erro` (ou `sala_encerrada`) correspondente. Assim, mesmo um cliente que não lê o código de fechamento recebe o motivo.

### 7.5 Quadros e limites

- Cliente → servidor: quadros **com máscara** (obrigatório pela RFC); tamanhos de 7, 16 e 64 bits; fragmentação com continuação, inclusive com quadros de controle intercalados; *ping* do protocolo → *pong* com o mesmo conteúdo; *close* → *close* de volta e fim da sessão.
- Servidor → cliente: quadros de texto sem máscara, sempre com FIN (sem fragmentar); *close* com código e motivo em UTF-8.
- Limite de 4.096 bytes por mensagem (já remontada); 125 bytes para quadros de controle.
- Leitura incremental: a sessão copia o que chegou para um buffer próprio e o decodificador de `uWebSocket` devolve "quadro completo" ou "faltam bytes". Ele funciona sobre `TBytes`, sem rede, e é testado nos casos WS.

### 7.6 Exemplo completo

```
→ GET /ws … (101)
→ {"tipo":"entrar","protocolo":1,"sala":"K7PM2Q","token":"…"}
← {"tipo":"bem_vindo","protocolo":1,"voce":"X","intervaloPingMs":20000,"sala":{…"versao":2…}}
← {"tipo":"estado","motivo":"ENTRADA","sala":{…"situacao":"EM_JOGO","versao":3…}}
← {"tipo":"estado","motivo":"CONEXAO","sala":{…"versao":4…}}
   (X faz POST …/moves {"posicao":4})
← {"tipo":"estado","motivo":"JOGADA","sala":{…"versao":5…}}
→ {"tipo":"ping","id":1}
← {"tipo":"pong","id":1}
   (O faz POST …/leave)
← {"tipo":"sala_encerrada","motivo":"SAIDA","sala":{…"situacao":"ENCERRADA","versao":9…}}
← close 4410
```

### 7.7 Validação de origem (`Origin`)

**Princípio.** A decisão usa somente o cabeçalho `Origin` e uma **lista de origens permitidas** montada pelo servidor a partir da sua própria configuração (opções de linha de comando e endereços das interfaces da máquina). `Host`, `X-Forwarded-Host` e cabeçalhos parecidos **nunca** entram na decisão. Motivo: numa página maliciosa que usa *DNS rebinding* (`http://atacante.test:8765` passando a resolver para o IP do computador), o navegador envia `Origin: http://atacante.test:8765` e `Host: atacante.test:8765`. Uma comparação com o `Host` aceitaria esse pedido; a comparação com a lista o recusa, porque `atacante.test` não está nela.

**Onde se aplica.** (a) Toda abertura de `/ws`. (b) Toda requisição `POST` das rotas `/api/rooms*` que traga `Origin`. As rotas do modo local (`/health`, `/api/game*`) e os estáticos não mudam (CAO-44).

**Normalização** (RFC 6454), feita por `uOriginPolicy`:
1. Exatamente um cabeçalho `Origin`, com até 255 caracteres; senão, recusada.
2. O valor `null` é recusado.
3. Formato `esquema://host[:porta]`, sem usuário, caminho (nem `/` final), consulta ou fragmento; qualquer outra coisa é recusada.
4. Esquema `http` ou `https`, comparado sem distinção de maiúsculas.
5. Host: IPv4 em notação decimal com pontos (quatro números de 0 a 255, sem zeros à esquerda) ou nome DNS (letras, dígitos, `-` e `.`, sem ponto final), em minúsculas. IPv6 é recusado: o servidor só escuta em IPv4.
6. Porta: 1 a 65535; se omitida, 80 para `http` e 443 para `https`. `http://x:80` é igual a `http://x`.
7. Comparação: igualdade exata da tupla (esquema, host, porta) com algum item da lista. Sem curingas, prefixos, sufixos ou "contém".

**Lista de origens permitidas:**

| Modo | Origens automáticas | Origens configuradas | Sem `Origin` |
|---|---|---|---|
| Local (padrão) | `http://127.0.0.1:<porta>` e `http://localhost:<porta>`, se o bind abrange o loopback (`0.0.0.0` ou `127.0.0.1`); `http://<IPv4>:<porta>` para cada IPv4 **privado** (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) das interfaces abrangidas pelo bind (todas com `0.0.0.0`; só o próprio IP com um bind específico) | cada `--allowed-origin` (por exemplo, `http://desktop-ruan:8765`) | canal: aceito; `POST` de sala: aceito |
| Público (`--public`) | nenhuma | cada `--allowed-origin`, obrigatoriamente `https` (pelo menos uma) | canal: **recusado**; `POST` de sala: aceito (sem `Origin` não há navegador de outro site envolvido) |

- A lista automática é calculada na partida e **recalculada a cada 60 s** (o IP pode mudar por DHCP). O console mostra a lista na partida e a cada mudança, por exemplo: `Origens permitidas: http://127.0.0.1:8765, http://localhost:8765, http://192.168.0.10:8765`.
- Cada `--allowed-origin` é validado na partida pelas regras acima. Um valor inválido, ou um valor sem `https` com `--public`, encerra o servidor com o código 2 e a mensagem de uso.
- Uma recusa responde 403 `ORIGEM_NAO_PERMITIDA` em JSON e registra no console o IP de quem pediu e a origem recusada (truncada em 100 caracteres, só com caracteres imprimíveis). Nenhum token é registrado.

**Casos de referência** (servidor na porta 8765, IP privado `192.168.0.10`, modo local sem opções). São os dados do WS-07 e do OV-05:

| # | `Origin` | Observação | Resultado |
|---|---|---|---|
| OG-01 | `http://127.0.0.1:8765` | navegador no próprio PC | aceita |
| OG-02 | `http://localhost:8765` | idem | aceita |
| OG-03 | `http://192.168.0.10:8765` | celular na rede local | aceita |
| OG-04 | `HTTP://192.168.0.10:8765` | esquema em maiúsculas | aceita (normalizada) |
| OG-05 | `http://192.168.0.20:8765` | IP de outra máquina | 403 |
| OG-06 | `http://192.168.0.10:9000` | outra porta | 403 |
| OG-07 | `http://192.168.0.10` | porta 80 implícita | 403 |
| OG-08 | `https://192.168.0.10:8765` | outro esquema | 403 |
| OG-09 | `http://desktop-ruan:8765` | nome do computador | 403; aceita com `--allowed-origin http://desktop-ruan:8765` |
| OG-10 | `https://exemplo.com` | site externo | 403 |
| OG-11 | `http://atacante.test:8765`, com `Host: atacante.test:8765` | *DNS rebinding* | 403 |
| OG-12 | `http://192.168.0.10:8765.atacante.test` | sufixo enganoso | 403 |
| OG-13 | `null` | página local ou em *sandbox* | 403 |
| OG-14 | `http://192.168.0.10:8765/` e `http://192.168.0.10:8765/x` | com caminho | 403 |
| OG-15 | dois cabeçalhos `Origin` | ambíguo | 403 |
| OG-16 | `http://[::1]:8765` | IPv6 | 403 |
| OG-17 | `http://192.168.000.010:8765` | zeros à esquerda | 403 |
| OG-18 | (ausente) | cliente que não é navegador | aceita |
| OG-19 | `http://8.8.8.8:8765` com o PC tendo esse IP público numa interface | IP não privado | 403; aceita só com `--allowed-origin` |

No modo público (`--public --allowed-origin https://jogo.exemplo.com.br`): `https://jogo.exemplo.com.br` e `https://jogo.exemplo.com.br:443` são aceitas; `http://jogo.exemplo.com.br`, `https://www.jogo.exemplo.com.br`, `http://127.0.0.1:8765` e a ausência de `Origin` (no canal) são recusadas.

## 8. Concorrência e isolamento por sala

### 8.1 Seções críticas e ordem

| Nível | Seção crítica | Protege |
|---|---|---|
| 1 | Registro | dicionários de salas ativas e lembradas |
| 2 | Sala (uma por sala) | motor, lugares, tokens, presença, versão |
| 3 | Hub | inscrições por sala |
| 4 | Caixa de saída (uma por canal) | fila de mensagens daquele canal |
| 5 | Log (já existe) | console |

Regra: uma thread só adquire na ordem crescente de nível, e o código é escrito para **segurar uma de cada vez**. A única exceção é o hub, que adquire a caixa de saída (3 → 4) para enfileirar. Nenhuma operação de sala chama o hub com a seção da sala aberta. Isso elimina impasses entre salas, hub e canais (RNFO-08).

### 8.2 Operação típica (jogada)

1. `uRoomHttp` lê o caminho e o token e chama `Registry.Find(código)`. O registro é consultado na sua seção e devolve `IRoom` (a referência mantém a sala viva).
2. `Room.Play(token, posição)` executa **inteira na seção da sala**: validações da RNO-10, `Engine.Play`, `Inc(Version)`, cópia do estado. Devolve `TRoomOutcome`.
3. Fora da seção da sala, se `Changed`, monta o JSON e chama `Hub.Publish(código, mensagem, versão)`, que só enfileira.
4. Responde ao HTTP com o estado do `TRoomOutcome`, que é exatamente o da jogada (como SV-02 no modo local).

Duas jogadas na mesma sala são serializadas no passo 2; jogadas em salas diferentes só disputam, por instantes, a seção do registro no passo 1 (CAO-23 a CAO-25).

### 8.3 Inscrição sem perder notificações

Na sessão, ao receber `entrar`:
1. `Room.Attach(token, idDoCanal)` (seção da sala): valida o token, marca o lugar como conectado, guarda o novo `ConnectionId` e devolve o anterior, se houver; `Inc(Version)` somente se o lugar estava desconectado.
2. `Hub.Subscribe(código, lugar, caixa)`: devolve o inscrito anterior do mesmo lugar, que recebe `erro SUBSTITUIDA` e é fechado com 4000.
3. Se o passo 1 mudou a sala, `Hub.Publish(estado CONEXAO)` para os demais.
4. Envia `bem_vindo` com `Room.Snapshot` lido **agora**, depois da inscrição. Qualquer mudança ocorrida entre 1 e 2 está nesse estado, e notificações repetidas são descartadas pela versão.

Ao terminar a sessão: `Hub.Unsubscribe` e `Room.Detach(lugar, idDoCanal)`. Se o canal que terminou não é o atual (foi substituído), nada muda. Isso evita que a aba substituída marque o lugar como desconectado.

### 8.4 Laço da sessão (thread do Indy)

```
enquanto não terminar:
  se o servidor está encerrando: enviar close 1001; sair
  se há dados no socket (CheckForDataOnSource(50 ms)): copiar para o buffer; decodificar quadros
      controle: ping → pong; close → close de volta; sair
      texto: tratar mensagem (seção 7.2)
  enviar tudo o que estiver na caixa de saída (só esta thread escreve no socket)
  se a mensagem terminal foi enviada: enviar close correspondente; sair
  se não houve `entrar` em 5 s, ou nada recebido há 60 s: erro TEMPO_ESGOTADO, close 4408; sair
ao sair: cancelar inscrição, Detach, publicar DESCONEXAO se mudou
```

A espera de 50 ms limita o atraso de entrega a ~50 ms por canal, dentro da meta da RNFO-05. Exceções de socket encerram a sessão sem tentar escrever uma resposta HTTP.

## 9. Interface online

### 9.1 Arquivos

| Arquivo | Conteúdo |
|---|---|
| `web/online.html` | Estrutura acessível com as telas inicial, sala e mensagens; mesmo padrão de `index.html` (`lang="pt-BR"`, `main`, `h1`, ícone `data:,`); inclui `style.css` e `online.css`. |
| `web/online.css` | Só o que é novo (painel de código e link, presença, conexão); classes com prefixo `online-`, para não afetar a página local. |
| `web/online.js` | IIFE sem módulos: `api` (fetch com tempo-limite de 8 s e `Authorization`), `channel` (WebSocket, `entrar`, `ping`, reconexão), `store` (`localStorage`), `render(sala)` com descarte por versão, `run` (uma ação por vez). Nenhuma regra de jogo. |

### 9.2 Identificadores para testes (`data-testid`)

| `data-testid` | Elemento | O que os testes leem |
|---|---|---|
| `online-app` | `<main>` | `data-state`: `inicio`, `consultando`, `convite`, `aguardando`, `jogando`, `finalizada`, `encerrada`, `inexistente`, `substituida` e, *v0.6*, `cheia` (link de uma sala com dois jogadores) e `negado` (token recusado pelo servidor); `data-connection`: `conectando` (*v0.6*: primeira tentativa), `conectado`, `reconectando`, `offline`, `parado` |
| `create-room` | "Criar sala" | — |
| `room-code-input` / `join-room` | Campo "Código da sala" / "Entrar" | — |
| `join-this-room` | "Entrar na sala" (link aberto sem token) | — |
| `room-code` / `room-link` | Código e link da sala | texto exato |
| `copy-link` / `copy-feedback` | "Copiar link" / "Link copiado." | — |
| `you-are` | "Você joga com X" / "…O" | texto exato (CIO-04) |
| `game-number` | "Partida 1" | número da partida |
| `status` | Status da partida (`role="status"`) | textos da CIO-05 |
| `opponent-status` | Presença do oponente (`role="status"`) | textos da CIO-06 |
| `connection-status` | Conexão do navegador | textos da CIO-07 |
| `board`, `cell-0` … `cell-8` | Tabuleiro | os mesmos atributos do modo local (`data-winning`, `aria-disabled`, `aria-label`, `aria-busy`) |
| `error-message` | Erro (`role="alert"`) | mensagem do servidor |
| `new-game` / `leave-room` | "Nova partida" / "Sair da sala" | — |
| `reconnect` / `use-here` / `create-new-room` | "Reconectar agora" / "Usar nesta aba" / "Criar nova sala" | visíveis só nas situações das CIO-07, CIO-13 e CIO-12 |
| `room-hint` | *(v0.6)* "Se o servidor foi reiniciado, as salas anteriores deixam de existir." | só com a sala inexistente durante o jogo (CIO-12) |
| `invite-code`, `turn-badge`, `retry` | *(v0.6)* código no convite, indicador do jogador da vez (decorativo, `aria-hidden`), "Tentar novamente" quando a consulta da sala falha por rede | — |
| `data-version` (atributo de `online-app`) | versão do último estado aplicado | usado pelos testes de versão |

### 9.3 Lógica

- **Abertura:** lê `?sala=`; se existir token guardado, abre o canal direto; senão, `GET /api/rooms/{c}` decide entre "Entrar na sala" e as mensagens de cheia, inexistente ou encerrada (CIO-03).
- **Aplicação de estado:** `render(sala)` só se `sala.versao > versaoAtual` (RNO-08). Fontes: respostas REST, `bem_vindo` e `estado`. Os textos são só formatação do estado e do próprio lugar (CIO-05, CIO-06).
- **Ações:** `run(ação)` aceita uma por vez (CIO-11). Clique em célula → `POST …/moves` sempre (CIO-08). Recusa → `error-message` com a mensagem do servidor (CIO-10).
- **Canal:** abre `ws://` ou `wss://` conforme o protocolo da página (`location`), no mesmo host. Envia `entrar` ao abrir e `ping` a cada `intervaloPingMs`. Se nada chegar em 2,25 × `intervaloPingMs` (45 s no padrão), fecha e reconecta (detecta queda do lado do cliente).
- **Teclado:** setas movem o foco entre as células, como em `app.js`.
- *v0.6 (como implementado na O4):* guarda do token em `localStorage`, chave `jogo-da-velha:sala:<CÓDIGO>`, valor `{codigo, simbolo, token, salvoEm}`; validade de 24 h renovada a cada `bem_vindo`; entrada vencida ou malformada é apagada sem ir ao servidor; se o `localStorage` não estiver disponível, o token fica só na memória da página. Link de uma sala `EM_JOGO` sem token: a página mostra "Esta sala já tem dois jogadores." a partir do estado consultado (não faz `POST`). Sem `bem_vindo` em 10 s depois de abrir o canal, a tentativa é descartada e uma nova é agendada. "Copiar link" usa `navigator.clipboard` em contexto seguro e, fora dele (página aberta pelo IP da rede local), a cópia por seleção (`execCommand('copy')`); se ela falhar, a página pede para copiar o link mostrado. Status fora do jogo: "Crie uma sala ou entre com o código de uma sala.", "Consultando a sala…", "Você foi convidado para uma partida.", "Não foi possível entrar nesta sala.", "Sala encerrada." e "Sala aberta em outra aba.".

## 10. Estratégia de reconexão

| Situação | Comportamento do cliente |
|---|---|
| Canal fechou com 1000/1001/1002/1007/1008/1009/1011/4408 ou erro de rede | `data-connection="reconectando"`, "Reconectando…"; novas tentativas após 0,5 s, 1 s, 2 s, 4 s, 8 s e depois a cada 10 s, com variação aleatória de ±20% (para não sincronizar os clientes depois de um reinício) |
| 30 s sem conseguir | "Sem conexão com o servidor." + "Reconectar agora" (`data-connection="offline"`); as tentativas continuam a cada 10 s |
| `online` do navegador ou aba volta a ficar visível | Tenta na hora (zera a espera) |
| `bem_vindo` recebido | "Conectado"; espera zerada; aplica o estado (que inclui o que mudou durante a queda) |
| 4000 | Para; "Esta sala foi aberta em outra aba." + "Usar nesta aba" (CIO-13) |
| 4401, 4404, 4410 | Para; apaga o token guardado; mensagem do servidor; "Criar nova sala" (CIO-12) |
| 4400 | Para; mensagem genérica (só ocorre por defeito do cliente) |

Durante a queda, as ações REST continuam funcionando. Se a jogada responder, o estado é aplicado. Se falhar por rede, a mensagem de falha de comunicação do modo local é usada.

## 11. Gerenciamento de conexões e limpeza

### 11.1 Presença

Um lugar está conectado enquanto houver um canal identificado como ele (seção 8.3). Desconexão é detectada pelo fechamento do canal, por erro de socket na escrita ou na leitura, ou pelo tempo-limite de 60 s sem mensagens (DTO-12).

### 11.2 Salas abandonadas e período de lembrança

`uRoomJanitor` é uma thread que, a cada `--sweep-ms` (padrão 5.000 ms), chama `Registry.Sweep(agora)`:

1. Na seção do registro, copia a lista de salas ativas e solta a seção.
2. Para cada sala, `CloseAbandoned(agora, ttl)` (seção da sala): se nenhum lugar está conectado e `agora − últimaAtividade > ttl`, encerra com `ABANDONO` e incrementa a versão.
3. Na seção do registro, move as encerradas para "lembradas" e remove as lembradas há mais de `--remember-seconds`.
4. Publica `sala_encerrada` para eventuais inscritos (normalmente nenhum, porque ninguém está conectado).

"Última atividade" é o instante da última operação aceita ou da última mensagem recebida por algum canal da sala. Uma sala com alguém conectado nunca é encerrada por abandono (CAO-38).

*v0.7 (como implementado na O5).* Antes de escrever o código, o comportamento existente foi inspecionado: `Sweep` e `CloseAbandoned` existiam desde a O1, mas nada os chamava. Nenhuma sala era encerrada por abandono, e as salas encerradas por saída ficavam para sempre na lista de ativas, respondendo 410, sem nunca passar a lembradas nem ser esquecidas. As três opções `--room-ttl-seconds`, `--remember-seconds` e `--sweep-ms` eram lidas, mas não tinham efeito. As ambiguidades encontradas foram resolvidas assim, sem contrariar o plano:

| ID | Ambiguidade | Decisão |
|---|---|---|
| A1 | "Última atividade": a v0.6 inclui "a última mensagem recebida por algum canal"; o domínio (O1, não alterado) registra só as mudanças aceitas. A especificação (RNO-16) fala em "sem nenhum lugar conectado por mais tempo que o limite". | Vale o registro do domínio: criação, entrada, jogada, nova partida, saída, identificação de um canal (`Attach`) e fim de um canal (`Detach`). `ping` e `GET` não contam. O resultado é o mesmo do texto da v0.6: mensagem de canal só existe com um lugar conectado, e sala com lugar conectado nunca é encerrada; quando o último canal fecha, o próprio `Detach` é a última atividade, então o prazo conta a partir da última desconexão. Uma sala usada só pela API (jogadas REST, sem canal) não é abandonada enquanto receber mudanças aceitas: cada uma reinicia a contagem (OV-03, sala C). |
| A2 | Limite exato | Estrito: encerra quando `agora − últimaAtividade > ttl` e nenhum lugar está conectado. |
| A3 | Quando o encerramento acontece | Na primeira varredura depois do prazo: entre `ttl` e `ttl + sweep-ms` (mais a duração da varredura). Com os padrões, de 600 a 605 s. |
| A4 | De quando conta o período de lembrança | Da varredura que passa a sala para "lembradas": no abandono, a mesma que a encerra; na saída (`SAIDA`), a varredura seguinte (até `sweep-ms` depois). Nesse intervalo a sala continua na lista de ativas, encerrada, e já responde 410. Depois de `--remember-seconds` (mais até `sweep-ms`), 404. |
| A5 | Sala encerrada e salas novas | A sala encerrada recusa tudo, mesmo com token válido: 410 `SALA_ENCERRADA` nas rotas e fechamento 4410 no canal. Uma sala nova sempre recebe código novo (nunca igual ao de uma sala ativa ou lembrada, RNO-01) e tokens novos. Depois de esquecida, o código pode voltar a ser sorteado (31 símbolos, 6 posições), mas os tokens antigos nunca valem na sala nova. |
| A6 | Ordem de desligamento com o faxineiro | Seção 11.3, item 4. O faxineiro para depois do Indy. Até lá ele ainda pode encerrar salas e publicar no hub, que só é liberado depois que ele para. |

Garantias de concorrência, verificadas por JN-02 e OV-12:
- O faxineiro nunca segura a seção do registro enquanto decide uma sala (passo 1). A decisão de encerrar acontece na seção crítica da própria sala, a mesma de `Attach`, `Play` e `Join`. Se um canal se identifica antes, a sala passa a ter alguém conectado e não é encerrada. Se o encerramento vem antes, a identificação recebe `SALA_ENCERRADA` (4410). Não há estado intermediário.
- A ordem das seções é sempre registro → sala (passo 3 e criação de sala); nenhuma operação de sala toma a seção do registro, então não há inversão nem *deadlock*. A publicação no hub e o log acontecem fora de qualquer seção.
- As salas são interfaces com contagem de referência (DTO-05): uma sala retirada do registro enquanto uma requisição ou sessão ainda a usa continua viva até a última referência ser solta. Assim, nenhum objeto liberado é acessado.
- O hub publica pelo código da sala, com uma lista de inscritos por sala, e nenhuma mensagem vai para outra sala (HB-02, HB-03, OW-07, OV-12).
- Uma exceção numa varredura é registrada como `ERRO no faxineiro: <classe>: <mensagem>`, e o faxineiro continua. Os instantâneos de sala não têm tokens.
- O console registra cada encerramento (`Sala <CÓDIGO> encerrada por abandono`) e, no início, os prazos em vigor.

### 11.3 Desligamento (Ctrl+C)

Ordem, na thread principal (como DT-13):
1. Sinaliza "encerrando" (as sessões enviam *close* 1001 na próxima volta do laço, em até ~50 ms).
2. Espera até 1 s pelas sessões. *(v0.5: 1,5 s na implementação da O3, para dar tempo à confirmação do *close*; medido: 92 ms com 10 canais.)*
3. `Active := False`: o Indy desconecta o que restou e espera as threads (até `TerminateWaitTime`, 5 s).
4. Para o faxineiro (evento + `WaitFor`), libera hub, registro e serviço.

*v0.7 (como implementado na O5):* 1. `FStopping`; as sessões enviam o fechamento 1001. 2. Espera de até 1,5 s pelas sessões. 3. `Active := False` no Indy. 4. `TRoomJanitor.Stop`, chamado também quando o Indy já estava parado: sinaliza o evento, espera a varredura em andamento terminar (`WaitFor`) e libera a thread. Depois disso não há varredura, publicação nem log do faxineiro. Chamar `Stop` duas vezes não faz nada. Com `--sweep-ms` de 1 hora, `Stop` também retorna na hora, porque a espera entre varreduras é o próprio evento. 5. O destrutor libera o faxineiro antes do hub e do registro. Medido na O5: 92 ms com 10 canais (D-01) e 91 ms com o faxineiro a cada 20 ms encerrando salas (D-03), sem nenhum encerramento depois de "Servidor encerrado".

Meta: sair com código 0 em até 5 s (CAO-50). Esse ponto é verificado já na O0.

### 11.4 Parâmetros de linha de comando

| Opção | Padrão | Uso |
|---|---|---|
| `--port N` | 8765 | já existe |
| `--www <pasta>` | `..\..\web` | já existe |
| `--bind <ip>` | `0.0.0.0` (`127.0.0.1` com `--public`) | DTO-16 |
| `--public` | desligado | DTO-17 |
| `--allowed-origin <url>[,<url>…]` | nenhuma (modo local usa só as automáticas); obrigatória com `--public` | seção 7.7 |
| `--trust-proxy` | desligado | DTO-20; *(v0.8)* com conexão de 127.0.0.1, o cliente é o último endereço de `X-Forwarded-For` (B8) |
| `--room-ttl-seconds N` | 600 | abandono (RNO-16) |
| `--remember-seconds N` | 3600 | período de lembrança (RNO-17) |
| `--sweep-ms N` | 5000 | intervalo do faxineiro |
| `--ws-hello-seconds N` | 5 | prazo para `entrar` |
| `--ws-idle-seconds N` | 60 | inatividade do canal |
| `--max-rooms N` | 500 | salas ativas |
| `--max-connections N` | 256 | `TIdHTTPServer.MaxConnections` |
| `--rate-create N` | 0 (sem limite) local; 10 com `--public` | criações por minuto por endereço |
| `--rate-join N` | 0 local; 30 com `--public` | entradas e consultas de sala por minuto por endereço |
| `--rate-ws N` | 0 local; 30 com `--public` | aberturas de canal por minuto por endereço |
| `--rate-window-seconds N` | 60 | *(v0.8)* janela das três taxas, 1 a 3.600 (B6; menor só nos testes) |
| `--ws-per-client N` | 0 local; 8 com `--public` | *(v0.8)* canais simultâneos por cliente (B4, B14) |
| `--ws-msg-rate N` | 0 local; 30 com `--public` | *(v0.8)* quadros do cliente por canal a cada 10 s (B4, B14) |
| `--http-timeout-seconds N` | 30 | *(v0.8)* prazo de cada leitura até a requisição chegar inteira (B13) |

Valores inválidos encerram com o código 2 e a mensagem de uso, como hoje.

## 12. Estratégia de testes (resumo)

Detalhada em `docs/test-plan-online.md`.

| Camada | Ferramenta | Grupos |
|---|---|---|
| Domínio, JSON, protocolo, hub (sem rede) | `EngineCheck.exe` | SL, SC, RJ, WS, HB, OP |
| REST de salas | Playwright `request` | OA (contrato), OR (regras) |
| Canal | `WebSocket` nativo do Node + `node:net` | OW |
| Ciclo de vida e segurança | Playwright + servidor dedicado (DTO-15) | OV |
| Interface | Playwright + Chromium, 2 a 3 contextos isolados (e um teste com dois processos do navegador) | OU |
| Regressão | Suíte atual (109) + `EngineCheck` (27) | — |

Projetos Playwright novos: `online-api` (`online/room-api`, `online/room-rules`), `online-ws` (`online/room-ws`; *v0.5: projeto próprio, em vez de entrar no `online-api`, para o canal poder ser repetido e sabotado sozinho*), `online-ui` (`online/room-ui`, Chromium) e `online-lifecycle` (`online/lifecycle`, Node e Chromium). *(v0.4: pastas `room-*`, porque o Playwright prefixa os padrões com `**/`, e `online/api` seria capturada também pelo projeto `api`.)* Os projetos atuais continuam iguais. Como os testes de sala não tocam na partida global, os projetos novos não interferem nos atuais. A suíte continua com 1 worker (DT-12).

## 13. Segurança (rede local e internet)

| Ameaça | Medida | Onde | CA |
|---|---|---|---|
| Interceptação / alteração no caminho | HTTPS obrigatório (proxy reverso, DTO-09); `wss://` automático pela página; HSTS pelo proxy | O8 | — (checklist manual) |
| Acesso direto ao Delphi pela internet | `--public` faz bind em `127.0.0.1`; firewall só com 80/443 para o proxy | O2, O6, O8 | CAO-46 |
| Adivinhar códigos de sala | 887 milhões de combinações + `--rate-join` por endereço | O1, O6 | CAO-02, CAO-53 |
| Roubo ou abuso de token | 128 bits aleatórios; nunca em URL, `Referer`, log ou resposta de consulta; `Referrer-Policy: no-referrer` | O1–O6 | CAO-54 |
| Sequestro do canal ou de ações de sala por outro site (CSWSH, CSRF) | Lista de origens permitidas por esquema, host e porta (7.7); token na mensagem e no `Authorization`, nunca em cookie | O3, O6 | CAO-51 |
| *DNS rebinding* contra o servidor na rede local | A origem é comparada com a lista, nunca com o `Host` (7.7, OG-11) | O3 | CAO-51 |
| XSS | Interface só usa `textContent`; código validado no servidor; CSP `default-src 'self'` | O4, O6 | CAO-55 |
| *Clickjacking* | CSP `frame-ancestors 'none'` | O6 | CAO-55 |
| Esgotamento (muitas salas, conexões ou mensagens) | `--max-rooms`, `--max-connections`, limites de taxa, 1 KB por corpo, 4 KB por mensagem, prazos de 5 s e 60 s, caixa de saída limitada | O3, O6 | CAO-52, CAO-53 |
| Conexões lentas (*slowloris*) contra o modelo de uma thread por conexão | Proxy reverso com tempos-limite; `--max-connections` | O8 | — (risco R-02) |
| Partida global exposta | `--public` desativa `/api/game*` | O6 | CAO-55 |
| Vazamento por erro | 500 genérico; detalhes só no console | já existe | — |
| Dados pessoais | Nenhum cadastro; o log tem endereço IP e código de sala; retenção do log definida na publicação | O8 | — |

### 13.1 Entrega O6: requisitos, limites atuais e decisões *(v0.8, escrito antes da implementação)*

**Limites que já existiam (inspecionados no código aprovado até a O5 e no código-fonte do Indy 10.6.2.5341 instalado):**

| Recurso | Limite antes da O6 | Onde |
|---|---|---|
| Conexões simultâneas | `--max-connections` (padrão 256), global. Acima dele, o Indy aceita a conexão e a fecha sem resposta HTTP (`TIdListenerThread.Run`; `DoMaxConnectionsExceeded` vazio) | `uHttpApp`, `IdCustomTCPServer` |
| Fila de aceite | 200 (`ListenQueue`) | `uHttpApp` |
| Salas abertas | `--max-rooms` (padrão 500): 503 `CAPACIDADE_ESGOTADA` | `uRoomRegistry`, `uRoomHttp` |
| Corpo das rotas de sala | 1.024 bytes: 413 `CORPO_MUITO_GRANDE`. Mas o Indy lê o corpo inteiro para a memória **antes** do roteador, com qualquer tamanho declarado ou em blocos (`chunked`) | `uRoomHttp`, `IdCustomHTTPServer.PreparePostStream` |
| Corpo das rotas locais (`/api/game/moves`) | nenhum | — |
| Cabeçalhos | 1.024 linhas (`MaximumHeaderLineCount`) e 16 KB por linha (`MaxLineLength`), padrões do Indy | Indy |
| Tempo de leitura HTTP | nenhum (`ReadTimeout` = −1): uma conexão aberta que não envia nada fica presa numa thread para sempre | Indy |
| Taxa de requisições | nenhuma (`--rate-*` previstas na seção 11.4, não implementadas) | — |
| Canais por cliente | nenhum (só o global de conexões) | — |
| Mensagens do canal | 4.096 bytes por mensagem (1009), 125 por quadro de controle, `entrar` em 5 s, inatividade de 60 s, caixa de saída de 16 itens (1008); nenhuma taxa | `uWebSocket`, `uWsSession`, `uRoomHub` |
| Origem | lista por esquema, host e porta; modo público só `https` configurado; canal sem `Origin` recusado no público (O3) | `uOriginPolicy` |
| `/api/game*` | sempre ativas | `uHttpApp` |
| Cabeçalhos de segurança | nenhum | — |

**Requisitos da O6 e testes que os verificam** (os IDs novos estão em `docs/test-plan-online.md` v0.8):

| # | Requisito | Testes |
|---|---|---|
| H-01 | `--public` aceita só as origens `https` configuradas, exige pelo menos uma válida e recusa canal sem `Origin`; `Host` nunca decide | OV-05c (O3), OV-14, OP-02, OG-11, SB-14 |
| H-02 | Origem não substitui o token: com a origem certa, sem token ou com token de outra sala, as ações continuam recusadas (401/4401) | OV-07 |
| H-03 | Limite de taxa por cliente (criação, consulta/entrada e abertura de canal): abaixo, no limite e acima; `Retry-After`; janela que reabre; clientes isolados | RL-01, OV-06, SB-18 |
| H-04 | Canais simultâneos por cliente | RL-02, OV-15, SB-22 |
| H-05 | Conexões simultâneas (global): 503 em JSON, sem conexão presa, recuperação | OV-15 |
| H-06 | Salas abertas: 503 no limite, volta ao liberar | SL-12 (O1), OV-06 |
| H-07 | Tamanho de requisição: 1 KB nas salas; teto de 64 KB em memória para qualquer rota (declarado ou em blocos); cabeçalhos | RL-03, OA-09 (O2), OV-16 |
| H-08 | Mensagens do canal: tamanho (O3) e taxa por canal | WS-05, OW-16, RL-04, OV-15, SB-21 |
| H-09 | Conexão lenta ou parada não prende thread para sempre | OV-16 |
| H-10 | `--public` desativa `/api/game*` (404 em qualquer método); salas, canal, `/health` e a página online funcionam | OV-07, SB-20 |
| H-11 | Cabeçalhos de segurança em todas as respostas; CSP nas páginas | OV-07, OV-13, SB-19 |
| H-12 | Nenhum token em URL, log ou resposta de consulta, inclusive nas recusas novas | OV-09 (varredura do script), OV-06 a OV-16 |
| H-13 | Recusas (taxa, origem, capacidade, conexões) não deixam recursos presos nem afetam outras salas | OV-15, OV-17 |
| H-14 | Combinações de `--public`, `--bind`, `--allowed-origin`, `--trust-proxy` e limites, inclusive inválidas | OP-03, OV-14 |
| H-15 | Modo local preservado (rotas antigas, interface local e online, limites desligados por padrão) | suíte completa, OV-13, OA-10, OA-11 |
| H-16 | Encerramento seguro com as proteções ativas | D-01 a D-05, D-06 (Ctrl+C no modo público) |

**Ambiguidades e decisões** (nenhuma muda o que o plano já previa para o modo local):

| ID | Ambiguidade | Decisão |
|---|---|---|
| B1 | O OV-07 da v0.7 usa `--public --allowed-origin http://127.0.0.1:8774`, mas a seção 7.7, a DTO-17 e o OP-02 exigem `https` no modo público (o servidor nem inicia com `http`). | O OV-07 usa `--allowed-origin https://jogo.test`. Sem HTTPS (fora do escopo), um navegador não consegue ser essa origem. Por isso, a partida completa no modo público é jogada por clientes REST e WebSocket que enviam `Origin: https://jogo.test`, como faria a página servida pelo proxy. A interface no navegador em modo público fica para o checklist MV-P da O8. |
| B2 | "Recuse conexões sem `Origin`" e `POST` de sala sem `Origin` no modo público. | Como na RNO-22 e na seção 7.7: o **canal** sem `Origin` é recusado no modo público (403), e um `POST` de sala sem `Origin` continua aceito. Todo navegador envia `Origin` num `POST` de outro site, então esse caso não vem de uma página maliciosa; e o token continua obrigatório para jogar. |
| B3 | Quais proteções valem no modo local. | As que **não mudam a resposta a um cliente comum** valem nos dois modos: cabeçalhos de segurança (MC-06 já dizia "todas as respostas"), teto de 64 KB em memória, prazo de leitura de 30 s e resposta 503 no limite de conexões. As que podem recusar uso legítimo (taxas, canais por cliente, mensagens por canal) ficam **desligadas por padrão no modo local** e ligadas no público, como a seção 11.4 já previa para as taxas. Única mudança visível no modo local: um corpo acima de 64 KB em `/api/game/moves`, que antes era lido inteiro e processado, passa a receber 413 `CORPO_MUITO_GRANDE`. |
| B4 | Códigos das recusas novas. | Taxa: 429 `LIMITE_DE_REQUISICOES` com `Retry-After` (já especificado). Canais por cliente: 429 `LIMITE_DE_CONEXOES`, sem `Retry-After`. Conexões do servidor: 503 `SERVIDOR_OCUPADO` com `Retry-After: 5`. Taxa de mensagens no canal: mensagem `erro` `LIMITE_DE_MENSAGENS` e fechamento 1008 (política, já existente: o cliente reconecta com espera crescente). Corpo acima de 64 KB: 413 `CORPO_MUITO_GRANDE`. Salas: 503 `CAPACIDADE_ESGOTADA` (sem mudança). |
| B5 | O que conta em cada taxa. | `--rate-create`: `POST /api/rooms`. `--rate-join`: `GET`/`HEAD /api/rooms/{código}` e `POST /api/rooms/{código}/players`, com qualquer resultado (inclusive 404: é o que impede adivinhar códigos). `--rate-ws`: todo pedido a `/ws`. Jogada, nova partida e saída não têm taxa: exigem token, e o volume fica limitado pelas conexões. Toda tentativa conta, inclusive as recusadas. |
| B6 | Janela. | Fixa, de 60 s, por cliente e por tipo (DTO-20). `--rate-window-seconds` (1 a 3.600, padrão 60) existe para os testes verem a janela reabrir em poucos segundos, como `--room-ttl-seconds` na O5. `Retry-After` = segundos até o fim da janela, de 1 a 60. |
| B7 | Ordem das verificações. | Rotas de sala: rota e método → **taxa** → origem → corpo → … (a taxa vem antes da origem; as duas são o passo 1 da seção 6.5). `/ws`: **taxa** → pedido de abertura → origem → canais por cliente. |
| B8 | Quem é "o cliente". | O IP da conexão. Com `--trust-proxy` e conexão vinda de `127.0.0.1`, o último endereço de `X-Forwarded-For` (o que o proxy acrescentou), se for um IPv4 válido; senão, o IP da conexão; sem a opção, ou vindo de outro endereço, o cabeçalho é ignorado (DTO-20). No modo público atrás de um proxy **sem** `--trust-proxy`, todos os visitantes contariam como um só cliente: a O8 precisa da opção. `Host` e `X-Forwarded-Host` nunca são usados. |
| B9 | `/` no modo público. | A página local depende de `/api/game*`, que ficam desativadas. Por isso `/` e `/index.html` respondem 302 para `/online.html` no modo público. No modo local, nada muda. |
| B10 | `/api/game*` no modo público. | 404 `ROTA_NAO_ENCONTRADA` para qualquer método (inclusive `HEAD`, `DELETE`, `OPTIONS`), igual a uma rota desconhecida. |
| B11 | Cabeçalhos exatos. | Todas as respostas: `X-Content-Type-Options: nosniff` e `Referrer-Policy: no-referrer`. Páginas HTML: `Content-Security-Policy: default-src 'self'; base-uri 'none'; object-src 'none'; form-action 'self'; frame-ancestors 'none'; img-src 'self' data:` e `X-Frame-Options: DENY`. As páginas não têm script nem estilo *inline* (conferido), mas usam `<link rel="icon" href="data:,">` (O4), daí o `img-src 'self' data:` (*acrescentado durante a validação: na primeira execução verde, sem ele, o Chromium registrava um erro de console em todas as páginas e os 57 testes de interface falharam*); e `connect-src` herda `'self'`, que cobre `ws://`/`wss://` do mesmo endereço. HSTS é do proxy (O8). A resposta 101 não muda. |
| B12 | O Indy troca o método de um `POST` por `X-HTTP-Method` / `X-HTTP-Method-Override` / `X-METHOD-OVERRIDE`. | Não abre brecha: só `POST` muda estado, e a troca transforma um `POST` em outro método (405, ou leitura pública da sala). Registrado; sem mudança. |
| B13 | Conexão lenta (*slowloris*). | `--http-timeout-seconds` (padrão 30, nos dois modos) é o prazo **de cada leitura** até a requisição chegar inteira; a sessão do canal tem prazos próprios e não é afetada. Um cliente que manda um byte a cada 29 s ainda segura a conexão: o tempo total fica com o proxy da O8 (R-02). Observado no código do Indy: se o prazo vence **no meio dos cabeçalhos**, o `Capture` trata a linha vazia devolvida como fim dos cabeçalhos, e a requisição incompleta é processada e respondida; a conexão é liberada do mesmo jeito (OV-15b). Se vence no corpo, a leitura levanta exceção e a conexão é fechada sem resposta. |
| B14 | Novas opções e padrões. | `--rate-create` 0 local / 10 público; `--rate-join` 0 / 30; `--rate-ws` 0 / 30; `--rate-window-seconds` 60; `--ws-per-client` 0 / 8 canais; `--ws-msg-rate` 0 / 30 mensagens por 10 s por canal; `--http-timeout-seconds` 30; `--trust-proxy`. Um valor explícito sempre vence o padrão do modo (por exemplo, `--public --rate-create 0`). |
| B15 | Memória do limitador. | No máximo 100.000 clientes em memória por tipo; janelas vencidas são descartadas a cada janela. Se o teto for atingido mesmo assim, um cliente novo é recusado (429) até haver espaço: um ataque distribuído não consegue esgotar a memória. |

## 14. Compatibilidade

| Recurso | Disponível? | Observação |
|---|---|---|
| `TIdHTTPServer`, `TIdContext.Connection.IOHandler` (`Write(TIdBytes)`, `CheckForDataOnSource`, `InputBuffer`) | Sim (Indy 10.6.2.5341, lido no código) | Leitura sem bloqueio longo pelo `CheckForDataOnSource(50)` |
| `TIdHTTPResponseInfo.HeaderHasBeenWritten` gravável | Sim (lido no código) | Essencial para o 101 manual |
| `TIdCustomTCPServer.MaxConnections`, `TerminateWaitTime` | Sim (lido no código) | — |
| `IdHashSHA.TIdHashSHA1` (nativo), `IdCoderMIME.TIdEncoderMIME` | Sim (arquivos presentes) | Plano B da DTO-18 |
| `System.Hash.THashSHA1`, `System.NetEncoding.TNetEncoding.Base64` | Esperado (introduzidos antes do 10.1) | **Confirmar na O0** compilando |
| `System.Generics.Collections` (`TDictionary`, `TList`), `TInterfacedObject`, `TThread`, `TEvent`, `TCriticalSection` | Sim | Já usados ou clássicos |
| `GetTickCount64` | Sim (Windows Vista+) | Relógio monotônico |
| `BCryptGenRandom` (`bcrypt.dll`) | Sim (Windows Vista+) | Declaração externa, sem unit extra |
| `ReportMemoryLeaksOnShutdown` (FastMM embutido) | Sim | Verificação de vazamentos no `EngineCheck` (HB/SL) |
| `GStack.GetLocalAddressList` (`TIdStackLocalAddressIPv4` com endereço e máscara) | Sim (lido em `System\IdStack.pas`) | Lista automática de origens (DTO-22) |
| WebSocket no Chromium do Playwright 1.64.1 | Sim | — |
| `WebSocket` global no Node 24.11.1 | Esperado (estável desde o Node 22) | **Confirmar na O0** |
| `page.routeWebSocket` no Playwright 1.64.1 | Esperado (desde 1.48) | **Confirmar na O0** |
| Windows 10 Pro 19045 | Sim | Já é o ambiente das Entregas 1 a 5 |
| Proxy reverso (Caddy) no Windows 10 | Sim (binário único) | Só na O8, depois de confirmada a hospedagem; nesta fase, apenas documentado (DO-11) |

Evitado de propósito, como antes: variáveis inline, *managed records*, bibliotecas de terceiros, WebBroker/DataSnap, TLS no Delphi.

## 15. Entregas incrementais

Regras para todas as entregas (as mesmas das Entregas 1 a 5): teste primeiro (fase vermelha) → implementação (fase verde) → sabotagens → validação real por script com log em `logs\` → registro em `docs/delivery-log.md` → sua aprovação antes da próxima. **Em toda entrega**, a regressão completa (109 testes Playwright e 27 casos do `EngineCheck`) precisa passar (CAO-44).

**Reversibilidade:** cada entrega é um conjunto de commits próprio, que acrescenta units, rotas e testes sem alterar o comportamento das anteriores. Reverter uma entrega (`git revert` dos seus commits) devolve o sistema ao estado da entrega anterior, com a suíte dela passando. A O0 não toca o código de produção.

### Entrega O0 — Prova de conceito do canal (descartável)

- **Escopo:** pasta `spikes/ws-indy/` com um `.dpr` próprio (não entra no `build.cmd` nem no servidor), que sobe um `TIdHTTPServer` com a mesma configuração (`KeepAlive := False`, bind em `0.0.0.0`) e uma rota `/ws` de eco e de *push*; script `scripts\validate-online-o0.ps1`.
- **Critérios (todos com saída real em `logs\online-o0.log`):**
  - E0-01: compila no Berlin, sem warnings; `THashSHA1` e `TNetEncoding.Base64` compilam e geram o aceite do exemplo da RFC (senão, registrar o uso do Indy pela DTO-18);
  - E0-02: Chromium do Playwright abre o canal (101), envia e recebe texto com acentos;
  - E0-03: `WebSocket` global do Node 24.11.1 faz o mesmo (senão, plano: cliente pelo navegador);
  - E0-04: *push* vindo de outra thread (outra requisição HTTP) chega pelo canal em menos de 200 ms;
  - E0-05: fechar a página encerra a sessão no servidor em até 2 s; matar o socket do cliente é detectado pelo tempo-limite;
  - E0-06: 50 canais simultâneos abertos e recebendo durante 30 s, sem erro;
  - E0-07: Ctrl+C (ou desligamento equivalente, pelo script) com 20 canais abertos encerra em até 5 s;
  - E0-08: `page.routeWebSocket` com `connectToServer` derruba o canal real.
- **Se E0-02, E0-04, E0-05 ou E0-07 falharem:** parar e trazer a você a revisão da DTO-01 (plano B: SSE com as mesmas mensagens da seção 7.3; plano C: *polling*), antes da O1.
- **Saída:** registro no `delivery-log`; o código fica na pasta `spikes/` como evidência (ou é apagado, conforme a sua preferência).

### Entrega O1 — Domínio de salas, sem HTTP

- **Escopo:** `uSecureRandom`, `uClock`, `uRoom`, `uRoomRegistry`, `uRoomJson`, `SnapshotToJsonValue` (aditivo em `uGameJson`); casos SL-01 a SL-12, SC-01, SC-02, RJ-01 a RJ-03 e MEM-01 no `EngineCheck`.
- **CAO cobertos (na camada do domínio):** 01, 02, 04, 06, 07, 09, 11, 16 a 25, 28 (leitura das mensagens), 29 a 31, 37 a 41, 53 (capacidade).
- **Sabotagens:** SB-07 (todas as salas compartilham um motor), SB-08 (sem verificação de vez), SB-10 (sala sem seção crítica + atraso), SB-12 (token de qualquer lugar aceito).
- **Concluída quando:** compila sem warnings; `EngineCheck` com os 27 casos antigos e todos os novos aprovados; as quatro sabotagens detectadas; as units novas não usam Indy (verificado no código); regressão completa aprovada.

### Entrega O2 — API REST de salas e endereço de escuta

- **Escopo:** `uServerOptions` (`--bind` e as opções de tempo e limites), `uRoomHttp`, roteamento em `uHttpApp`, `--bind` com padrão `0.0.0.0` e `127.0.0.1` com `--public` (MC-01, MC-02); comentário do código, RNF-04, DT-07 e README alinhados; caso OP-01; testes Playwright OA-01 a OA-09 e OR-01 a OR-18; OV-08 (endereço de escuta, pelo script); projeto `online-api`.
- **CAO:** 01, 02, 04, 06, 07, 09, 11, 13 (servidor), 16 a 25, 29 a 31, 39 a 41, 44 a 46, 52 (corpo).
- **Sabotagens:** SB-07, SB-08, SB-10 e SB-12 repetidas contra o servidor real (os testes OR indicados precisam falhar).
- **Concluída quando:** suíte (109 + novos) aprovada duas vezes, sem retries; `Get-NetTCPConnection` mostra o servidor em `0.0.0.0:8765` sem opções, só em `127.0.0.1` com `--bind 127.0.0.1` e com `--public`; nenhum 500 no log.

### Entrega O3 — Canal em tempo real

- **Escopo:** `uWebSocket`, `uOriginPolicy`, `uRoomHub`, `uWsSession`, rota `/ws` (MC-03, MC-08); verificação de origem no canal e nos `POST` de sala (seção 7.7, modo local); casos WS-01 a WS-07 e HB-01, HB-02 no `EngineCheck`; testes OW-01 a OW-17, OA-10 e OV-05 (casos do modo local).
- **CAO:** 10, 12 e 14 (no protocolo), 15, 20, 28, 30 a 34, 36 (no protocolo), 37, 45, 51 (modo local), 52 (mensagens e quadros).
- **Sabotagens:** SB-11 (hub não publica nada): OW-04, OW-05 e OW-06 precisam falhar; SB-14 (política de origem aceita qualquer valor): WS-07, OA-10 e OV-05 precisam falhar.
- **Observação:** OW-10 e OW-13 usam o servidor dedicado (DTO-15) com prazos de 2 a 3 s; os demais usam o servidor da suíte.
- **Concluída quando:** suíte aprovada duas vezes; 50 canais simultâneos sem erro (repete o E0-06 com o servidor real); log sem tokens.
- *v0.5 (como executada):* a pedido do usuário, a política de origem entrou **inteira**, com o modo público (só `--allowed-origin` https, pelo menos um; canal sem `Origin` recusado), antecipado da O6; testes acrescentados: OA-11 (`Authorization` nas rotas antigas, ressalva da O2), OW-18 (rajada com canais), OW-19 (os 50 canais, projeto `online-lifecycle`), HB-03, OP-02 e a sabotagem SB-15 (hub entrega a todas as salas: OW-07 precisa falhar); o Ctrl+C com 10 canais (parte do OV-04, da O5) já é verificado pelo script, com o `send-ctrl-c.ps1` da O0. `GetTickCount64` não existe no `Winapi.Windows` do Berlin: a medição de tempo usa `TStopwatch`. As regras que dependem de mais de uma opção ficam em `ValidateServerOptions`, para o OP-01 da O2 continuar idêntico.

### Entrega O4 — Interface online

- **Escopo:** `web/online.html`, `online.js`, `online.css`; estáticos na lista fixa (MC-04); link na página local (MC-05); testes OU-01 a OU-22, OU-24 e OV-10 (partida pelo IP da rede local); projeto `online-ui`.
- *v0.6 (como executada):* OU-23 (servidor reiniciado, com "Sem conexão com o servidor." depois de 30 s) antecipado da O5; testes novos OU-25 (token guardado inválido), OU-26 (validade de 24 h), OU-27 (falha de comunicação nas ações REST) e OA-12 (estáticos e link); sabotagem nova SB-16 (token na URL da página); OV-10 com servidor dedicado (porta 8784, bind padrão), para não depender do bind do servidor da suíte; OU-24 é um controle automático no fim de cada teste OU, não um teste à parte; regressão de linha de base antes das mudanças (`scripts\regression-o4-baseline.cmd`).
- **CAO:** 03, 05, 08, 12, 13, 14, 16, 26, 27, 29 a 32, 34 a 36, 39, 40, 42, 43, 54 (URLs), 56.
- **Sabotagem:** SB-09 (`online.js` desenha a jogada antes do servidor): OU-09 e a verificação cruzada precisam falhar; SB-11 também derruba OU-06 e OU-08.
- **Concluída quando:** suíte aprovada duas vezes; nenhum erro de console nem 404/5xx inesperado; latência do OU-06 registrada (meta de 500 ms); capturas de tela (desktop e 360 px) anexadas.

### Entrega O5 — Ciclo de vida: abandono, reinício e desligamento

- **Escopo:** `uRoomJanitor`, período de lembrança, ordem de desligamento (seção 11.3); fixture de servidor dedicado; testes OV-01 a OV-04 e OU-23; auxiliar `scripts\send-ctrl-c.ps1` (envia Ctrl+C a um processo console com `GenerateConsoleCtrlEvent`).
- **CAO:** 38, 48, 49, 50.
- **Sabotagem:** SB-13 (faxineiro não encerra nada): OV-02 precisa falhar.
- **Concluída quando:** suíte aprovada duas vezes; OV-04 (Ctrl+C com 10 canais) aprovado pelo script. Se o envio automático de Ctrl+C não for confiável, o OV-04 vira verificação manual registrada, como o Ctrl+C das Entregas 1 a 5.
- *v0.7 (como executada):* `uRoomJanitor` sem Indy e com relógio e intervalo injetáveis, com testes no `EngineCheck`: JN-01 (prazos com relógio manual, sala conectada, sala nova, parada) e JN-02 (faxineiro a cada 1 ms com 8 threads). Testes Playwright novos: OV-11 (sala nova não reaproveita credenciais nem estado), OV-12 (limpeza concorrente com jogadas, canais e entradas na hora do prazo) e OU-28 (a interface depois do abandono). O OV-01 usa a porta 8785, porque a 8771 já é de um teste da O3. O OV-04 é o Ctrl+C do script (D-01) e ganhou uma segunda versão com o faxineiro trabalhando (D-03), além da verificação de processos órfãos e portas (D-05). Sabotagens: SB-13 aplicada ao faxineiro (não varre), detectada por JN-01, JN-02, OV-02, OV-03, OV-11, OV-12 e OU-28. O SL-11 testa o domínio da O1, que essa sabotagem não toca. SB-17, nova: a sala é encerrada mesmo com alguém conectado. Antes de qualquer mudança, rodou a regressão de linha de base (`scripts\regression-o5-baseline.cmd`). Fase vermelha com o faxineiro em esqueleto.

### Entrega O6 — Endurecimento (limites, cabeçalhos e modo público), validado localmente

- **Escopo:** `uRateLimiter`, `--public` (origens só `https` configuradas, canal sem `Origin` recusado; *v0.5: já feito na O3*), `--trust-proxy`, cabeçalhos de segurança (MC-06, MC-07), limites; testes OV-05 (casos do modo público), OV-06, OV-07 e OV-09. Tudo testado no próprio computador; nada é publicado (DO-16).
- **CAO:** 51 (modo público), 52, 53, 54, 55.
- **Concluída quando:** suíte aprovada duas vezes; nenhum token nos logs da suíte inteira (varredura feita pelo script); o modo local (sem `--public`) continua idêntico (CAO-44).
- *v0.8 (como executada):* requisitos H-01 a H-16, limites anteriores e decisões B1 a B15 na seção 13.1, escritos antes da implementação. Unidades novas sem Indy: `uRateLimiter` (janela fixa por cliente, contador de canais e janela de mensagens) e `uRequestLimits` (`TCappedStream`, `ClientKey`, `ClassifyRateKind`, constantes), com os casos RL-01 a RL-05 e OP-03 no `EngineCheck` (65 casos). No `uHttpApp`: subclasse do `TIdHTTPServer` que responde 503 acima de `--max-connections` (o Indy só fechava a conexão), `ReadTimeout` por conexão, corpo com teto de 64 KB (`OnCreatePostStream`; o Indy pré-alocava o `Content-Length` declarado), taxas antes do roteador, cabeçalhos de segurança e `/api/game*` desativadas no público. Testes Playwright novos: OV-06a/b/c, OV-07 (reescrito), OV-13 a OV-17 e OV-14a/b, no projeto `online-lifecycle` (23 testes; suíte 206). Sabotagens SB-14 (atualizada) e SB-18 a SB-25. O Ctrl+C ganhou uma terceira versão no modo público com limites (D-06/D-07). Regressão de linha de base antes das mudanças (`scripts\regression-o6-baseline.cmd`) e fase vermelha com `uRateLimiter`/`uRequestLimits` em esqueleto. Correções durante a validação (tentativas registradas no `delivery-log`): `img-src 'self' data:` na CSP (B11) e duas verificações a mais no OV-17 (SB-18 e SB-22). Fora da validação, `scripts\demo-playwright-headed.cmd` mostra alguns testes de interface com o navegador visível, a pedido do usuário. Nada publicado: sem domínio, HTTPS, Caddy ou encaminhamento de portas.

### Entrega O7 — Validação final na rede local

- **Escopo:** `README.md` atualizado (modo online na rede local, opções, firewall do perfil Privado); `docs/spec.md` (RNF-04), `docs/plan.md` (DT-07) e o comentário do bind alinhados ao padrão `0.0.0.0`, se ainda não tiverem sido na O2; validação manual com o checklist MV-L01 a MV-L06; validação final por clone limpo.
- **Concluída quando:** suíte completa aprovada **3 vezes seguidas** a partir de um clone limpo; checklist MV-L registrado (celular na mesma rede Wi-Fi contra o computador, entre outros itens); matrizes do `test-plan-online.md` com os resultados reais; documentos com status "concluído para a rede local"; tag `v2.0`.
- *v0.9 (como executada):*
  - **Pendência da O6:** o teto de 64 KB passou a ter teste exato (OV-18: 65.535 e 65.536 bytes processados, 65.537 → 413, também em blocos), com duas sabotagens de um byte (SB-26 e SB-27).
  - **Clone limpo:** a validação final roda numa **cópia limpa** da pasta, não num clone. Os trabalhos das O0 a O7 não estão em commit, e o commit não foi autorizado; por isso um `git clone` não teria o código.
  - **Validação automática:** `validate-online-o7` e o complemento cobrem a suíte três vezes seguidas, a matriz CAO-01 a CAO-56 e as sabotagens SB-01 a SB-27.
  - **Roteiro manual:** ampliado para 15 itens (`test-plan-online.md` 13.4). Executado com o computador e um iPhone na rede local, em parte; os itens não executados ficam pendentes.
  - **Firewall:** encontrado desligado nos perfis Privado e Público, com a rede cabeada marcada como Pública. Não foi alterado.
  - **Publicação:** preparada só no papel (`docs/checklist-publicacao-o8.md`).
  - **Tag `v2.0`:** não criada, porque depende de commit, que não foi autorizado.

### Entrega O8 — Publicação na internet (cancelada)

> *v0.9:* **cancelada pelo usuário em 20/10/2026.** O projeto é de estudo e não será publicado. O texto abaixo e `docs/checklist-publicacao-o8.md` ficam só como referência.


- **Pré-condição:** você confirma o ambiente definitivo de hospedagem (DO-10) e o domínio. Até lá, esta entrega **não começa**.
- **Escopo previsto:** `docs/deploy-online.md` com o passo a passo da seção 16.3 para o ambiente escolhido; instalação e configuração do proxy reverso (Caddy, DO-11, ou outro que você aprovar); servidor com `--public --allowed-origin https://<domínio> --trust-proxy`; checklist MV-P01 a MV-P08.
- **Concluída quando:** checklist MV-P registrado no ambiente publicado; a suíte automatizada continua aprovada localmente; tag `v2.1`.

## 16. Implantação

### 16.1 Fase 1 — localhost (O0 a O7)

```bat
server\bin\TicTacToeServer.exe
```
- Abrir `http://127.0.0.1:8765/online.html` numa janela normal e noutra anônima (ou em outro navegador), porque as duas abas de uma mesma janela são o mesmo jogador (DO-05).
- Pelo celular na mesma rede: `http://<IP do computador>:8765/online.html`, já que o padrão é `0.0.0.0` (fase 2).
- Os testes automatizados sempre usam essa fase.

### 16.2 Fase 2 — rede local (padrão, como você já usa pelo celular)

```bat
server\bin\TicTacToeServer.exe
```
- Escuta em `0.0.0.0`. O celular abre `http://<IP privado do computador>:8765/online.html`; esse endereço está na lista automática de origens (7.7), então não é preciso `--allowed-origin`. Para acessar pelo nome do computador, use `--allowed-origin http://<nome>:8765`.
- O console mostra as origens permitidas na partida; se o IP mudar, a lista é atualizada em até 60 s. Uma reserva de DHCP no roteador evita a troca de IP.
- Regra no Firewall do Windows só para o perfil **Privado** e a porta 8765.
- HTTP sem criptografia: **só em rede confiável**. Não usar em rede pública.

### 16.3 Fase 3 — internet (Entrega O8, bloqueada até a confirmação da hospedagem)

> Esta seção é **documentação de referência**. Nada aqui é instalado ou configurado antes da Entrega O8 (DO-10, DO-11).

```
Internet ──HTTPS 443──► Caddy (mesma máquina) ──HTTP──► 127.0.0.1:8765 TicTacToeServer.exe --public
```

1. **Hospedagem** (DO-10): (a) este computador, com redirecionamento das portas 80 e 443 no roteador, IP fixo ou DNS dinâmico, e verificando se a operadora usa CGNAT (que impede receber conexões); ou (b) um servidor Windows alugado (Windows Server 2019 ou superior), onde o mesmo `.exe` roda sem alteração.
2. **Domínio** apontando para o IP público (registro A).
3. **Proxy:** Caddy (DTO-09, DO-11), com uma configuração mínima como esta:
   ```
   jogo.exemplo.com.br {
       reverse_proxy 127.0.0.1:8765
   }
   ```
   O Caddy obtém e renova o certificado sozinho e repassa o WebSocket sem configuração extra. Alternativa sem Caddy: IIS com ARR e o módulo WebSocket, ou nginx para Windows (que exige configurar o cabeçalho `Upgrade`).
4. **Servidor:** `TicTacToeServer.exe --public --allowed-origin https://jogo.exemplo.com.br --trust-proxy`, iniciado pelo Agendador de Tarefas do Windows "ao iniciar o sistema", com a saída redirecionada para um arquivo de log. Sem serviço de terceiros.
5. **Firewall:** liberar só 80/443 para o Caddy; a porta 8765 nunca é exposta (o bind em `127.0.0.1` do `--public` já garante; não redirecionar a 8765 no roteador).
6. **Antes de abrir ao público:** checklist MV-P do test-plan (HTTPS, `wss://`, rotas locais com 404, cabeçalhos, dois aparelhos em redes diferentes, reinício do servidor).
7. **Operação:** um reinício do servidor encerra todas as salas (RNO-20); atualizar fora de horário de uso. Os logs têm IPs; definir a retenção (por exemplo, 7 dias).

## 17. Riscos

| ID | Risco | Probabilidade / impacto | Mitigação |
|---|---|---|---|
| R-01 | O `TIdHTTPServer` do Berlin não se comportar como o código sugere ao assumir a conexão (bytes extras, buffer, desconexão precoce) | Média / alto | Prova de conceito O0 antes de tudo; planos B (SSE) e C (*polling*) com as mesmas mensagens |
| R-02 | Uma thread por conexão limita a escala e é vulnerável a conexões lentas | Média / médio | Limites de conexões; proxy com tempos-limite; capacidade declarada (RNFO-07); revisar se o uso crescer |
| R-03 | Desligamento travar com threads presas no laço da sessão | Baixa / médio | Laço com espera de 50 ms e verificação do sinal; E0-07 e OV-04 |
| R-04 | OpenSSL 1.0.x do Indy desatualizado | Certa / alto se usado | TLS só no proxy (DTO-09) |
| R-05 | Recursos de teste (`WebSocket` do Node, `routeWebSocket`) com comportamento diferente do esperado | Baixa / médio | Confirmados na O0; alternativa: cliente no navegador |
| R-06 | Exposição de um computador pessoal na internet; CGNAT ou IP dinâmico | Média / alto | Proxy, firewall, `--public`, limites; considerar servidor alugado (DO-10) |
| R-07 | Abas duplicadas brigando pelo mesmo lugar | Média / baixo | Código 4000 sem reconexão automática (RNO-15, CAO-36) |
| R-08 | Testes dependentes de tempo instáveis | Média / médio | Tempos curtos configuráveis, asserções que esperam condições, nenhum retry; repetição dupla da suíte |
| R-09 | Com o padrão `0.0.0.0`, qualquer aparelho da rede local acessa o jogo, inclusive a partida global do modo local, por HTTP sem criptografia | Certa / baixo em rede doméstica | Regra de firewall só no perfil Privado; não usar em rede pública; não redirecionar a 8765 no roteador; na internet, `--public` (bind `127.0.0.1` e proxy HTTPS) |
| R-10 | Vazamentos ou acesso a memória liberada com salas removidas durante uma sessão | Baixa / alto | Interfaces com contagem de referência (DTO-05); `ReportMemoryLeaksOnShutdown` no `EngineCheck` (MEM-01) |
| R-11 | Proxies ou redes que cortam conexões ociosas | Média / baixo | `ping` a cada 20 s; reconexão automática |
| R-12 | Escopo grande | — | Oito entregas pequenas, cada uma reversível e aprovada por você |
| R-13 | Token roubado de um computador compartilhado (`localStorage`) | Baixa / baixo | Validade de 24 h; "Sair da sala" apaga o token; jogo casual, sem dados pessoais |
| R-14 | O IP do computador muda (DHCP) e o celular deixa de ser aceito pela origem | Média / baixo | Lista automática recalculada a cada 60 s e mostrada no console; reserva de DHCP no roteador |

## 18. Registro de alterações

| Versão | Data | Alteração |
|---|---|---|
| 0.1 | 2026-10-16 | Criação. Investigação do canal em tempo real no código-fonte do Indy 10.6.2.5341 instalado; decisões DTO-01 a DTO-21; contrato REST das salas, protocolo do canal, concorrência, interface, reconexão, limpeza, segurança, compatibilidade, entregas O0 a O7, implantação e riscos. Divergência do bind registrada (DO-09, MC-01). Nenhum código alterado. |
| 0.2 | 2026-10-16 | DO-09 respondida: bind padrão `0.0.0.0` mantido (DTO-16, MC-01, 11.4, 16.1, 16.2, R-09); `--public` usa `127.0.0.1` (DTO-17, 13, 16.3); `Origin` comparada com o `Host` da requisição (7.1), para o acesso pelo celular funcionar. |
| 0.3 | 2026-10-16 | Planejamento aprovado com decisões: validação de origem revista (seção 7.7, DTO-22, `uOriginPolicy`, linha de `Origin` em 6.5 e 7.1, seção 13, opção `--allowed-origin`); DO-10 (rede local primeiro; nova Entrega O8, bloqueada até a confirmação da hospedagem; O7 vira validação final na rede local; DTO-23) e DO-11 (Caddy só documentado, 16.3 e 14); DTO-17 ajustada; R-14 novo. |
| 0.4 | 2026-10-16 | Entrega O2 implementada: `uRoomHttp` sem Indy (a leitura e a escrita do Indy ficam em `uHttpApp`); `OnParseAuthentication` do Indy tratado (sem ele, qualquer `Authorization` que não seja `Basic` derrubava a conexão antes do roteador); `ListenQueue` do Indy em 200 (o padrão 15 fazia o Windows recusar conexões numa rajada de 360 requisições); rotas de sala lidas pelo caminho cru (`URI`), sem decodificar `%xx`; opção desconhecida encerra com código 2; `--public` só muda o bind padrão até a O6; `--room-ttl-seconds` e `--sweep-ms` lidos e validados, com efeito a partir da O5 (faxineiro). Pastas Playwright `room-*` (seção 12). |
| 0.5 | 2026-10-17 | Entrega O3 implementada: política de origem com o modo público antecipado da O6 (pedido do usuário); projeto Playwright `online-ws` separado do `online-api` (seção 12); espera de 1,5 s no desligamento (11.3); `TStopwatch` no lugar de `GetTickCount64`, que o Berlin não declara; `ValidateServerOptions`; testes OA-11, OW-18, OW-19, HB-03, OP-02 e SB-15 acrescentados; Ctrl+C com 10 canais verificado já na O3. |
| 0.6 | 2026-10-17 | Entrega O4 implementada: identificadores e estados novos da interface (9.2: `cheia`, `negado`, `conectando`, `room-hint`, `invite-code`, `turn-badge`, `retry`); detalhes da guarda do token, da cópia do link fora de contexto seguro e dos status fora do jogo (9.3); OU-23 antecipado da O5; OU-25 a OU-27, OA-12 e SB-16 acrescentados; OV-10 com servidor dedicado. |
| 0.7 | 2026-10-19 | Entrega O5 implementada: comportamento anterior inspecionado e ambiguidades A1 a A6 do ciclo de vida decididas e documentadas (11.2); garantias de concorrência do faxineiro (11.2); ordem de desligamento como implementada (11.3); JN-01, JN-02, OV-11, OV-12, OU-28 e SB-17 acrescentados; OV-01 na porta 8785; SB-13 aplicada ao faxineiro. |
| 0.8 | 2026-10-19 | Entrega O6 implementada: seção 13.1 (limites anteriores, requisitos H-01 a H-16 ligados aos testes, decisões B1 a B15); opções `--rate-create`, `--rate-join`, `--rate-ws`, `--rate-window-seconds`, `--ws-per-client`, `--ws-msg-rate`, `--http-timeout-seconds` e `--trust-proxy` (11.4); `/api/game*` desativadas e `/` levando a `/online.html` no público; cabeçalhos de segurança; teto do corpo, prazo de leitura e 503 acima do limite de conexões; RL-01 a RL-05, OP-03, OV-06a/b/c, OV-07 reescrito, OV-13 a OV-17, SB-14 atualizada e SB-18 a SB-25. |
| 0.9 | 2026-10-20 | Entrega O7 executada: OV-18, SB-26 e SB-27; validação final a partir de uma cópia limpa (o trabalho não está em commit); roteiro MV-L ampliado e executado em parte com computador e iPhone; checklist da O8 (`docs/checklist-publicacao-o8.md`); tag `v2.0` pendente de autorização. |
