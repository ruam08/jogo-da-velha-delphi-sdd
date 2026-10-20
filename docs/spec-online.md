# Especificação — Jogo da Velha Multiplayer Online

| Campo | Valor |
|---|---|
| Versão | 0.3 |
| Data | 2026-10-16 |
| Etapa SDD | 1 — Especificação (modo online) |
| Base | `docs/spec.md` v0.5, `docs/plan.md` v0.8, `docs/test-plan.md` v0.9, `docs/delivery-log.md` (Entregas 1 a 5), código-fonte inspecionado em 2026-10-16 |
| Documentos irmãos | `docs/plan-online.md` v0.3, `docs/test-plan-online.md` v0.3 |
| Status | **Planejamento. Nada foi implementado.** Aguardando aprovação. |

---

## 1. Objetivo

Evoluir o Jogo da Velha para **partidas multiplayer online**: dois jogadores, em navegadores diferentes, participam da mesma partida por meio de uma **sala** identificada por um código compartilhável, e todas as jogadas e mudanças de estado aparecem nos dois navegadores **em tempo real**, sem recarregar a página.

Princípios herdados de `docs/spec.md` que continuam valendo:

- **O servidor Delphi é a única autoridade** sobre o estado de cada partida (RN-14). O navegador só envia intenções e desenha o estado recebido.
- As **regras do jogo não mudam** (RN-01 a RN-12 e RN-15): tabuleiro, turnos, vitória, empate, bloqueio e ordem de validação são os do motor atual (`uGameEngine`).
- Estado **somente em memória** (sem banco de dados nem arquivo).
- Sem frameworks, bibliotecas de terceiros ou dependências novas sem justificativa (RNF-03).

## 2. Relação com a especificação atual

Esta especificação **estende** `docs/spec.md` sem substituí-la.

| Assunto | `docs/spec.md` (modo local) | Este documento (modo online) |
|---|---|---|
| Partida | Uma única partida global (RN-13) | Uma partida por sala, várias salas ao mesmo tempo |
| Jogadores | Dois humanos no mesmo computador, sem identificação | Dois jogadores identificados (X e O), cada um no seu navegador |
| Sincronização | Nenhuma (RN-13, item 2.2) | Em tempo real entre os navegadores da sala |
| Rotas | `/health`, `/api/game`, `/api/game/moves`, `/api/game/reset`, estáticos | Todas preservadas, mais as rotas de sala e o canal de tempo real |
| Página | `/` (`index.html`, `app.js`) | Página própria (`/online.html`); a página local continua existindo |

Os itens de `docs/spec.md`, seção 2.2, **"jogo em rede entre máquinas diferentes"**, **"múltiplas partidas simultâneas ou sessões por jogador"** e **"sincronização automática (sem polling, WebSocket ou SSE)"** passam a fazer parte do escopo **apenas no modo online**. Todo o resto de `docs/spec.md` continua valendo para o modo local, com o mesmo contrato e os mesmos 109 testes Playwright e 27 casos do `EngineCheck`.

## 3. Escopo

### 3.1 Dentro do escopo

- Criar uma sala com código único e um link para compartilhar.
- Entrar numa sala pelo código ou pelo link, a partir de outro navegador.
- Dois jogadores por sala: quem cria é X e quem entra é O.
- Salas isoladas entre si: cada uma tem tabuleiro, turno, resultado, participantes e versão próprios.
- Sincronização em tempo real de entradas, jogadas, resultados, reinícios, conexões e desconexões.
- Validação no servidor de todas as jogadas, inclusive "vez de quem".
- Jogadas simultâneas sem corromper o estado.
- Mensagens para sala cheia, sala inexistente e sala encerrada.
- Comportamento definido para desconexão, reconexão, atualização da página e segunda aba.
- Nova partida dentro da sala, sem afetar outras salas.
- Saída voluntária da sala.
- Limpeza automática de salas abandonadas.
- Comportamento definido quando o servidor é reiniciado (as salas deixam de existir).
- Interface responsiva e acessível.
- Preservação das rotas e do contrato atuais.
- Testes automatizados novos para o multiplayer, mantendo os existentes.
- Desenvolvimento e validação na **rede local**, com o servidor Delphi no Windows e acesso pelo IP do computador (DO-10).
- Validação de origem do canal e das rotas de sala por lista de origens permitidas (RNO-22).
- Preparação para a publicação na internet (modo `--public`, limites, cabeçalhos), testada localmente. A **publicação em si** (domínio, HTTPS, proxy reverso) fica para uma etapa posterior, depois de confirmado o ambiente de hospedagem (DO-10).

### 3.2 Fora do escopo

- Contas de usuário, senha, login social ou nome de exibição.
- Espectadores pelo canal em tempo real, chat e convites por e-mail ou mensagem.
- Placar acumulado, ranking e histórico de partidas.
- Persistência das salas (banco de dados, arquivo, recuperação após reinício).
- Vários servidores ou balanceamento de carga (as salas vivem num único processo).
- Jogo contra o computador.
- Aplicativo nativo para celular (o navegador do celular é atendido pela interface responsiva).
- Desistência automática (W.O.) por desconexão *(premissa — ver DO-03)*.
- Modo de contingência por *polling* quando o tempo real falhar *(premissa — ver DO-15)*.

## 4. Glossário

| Termo | Definição |
|---|---|
| Sala | Espaço isolado com uma partida, dois lugares (X e O), uma versão e um ciclo de vida próprio. |
| Código da sala | Identificador de 6 caracteres, gerado pelo servidor, usado para entrar na sala e no link compartilhável. |
| Lugar | Posição de um jogador na sala: X (quem criou) ou O (quem entrou). |
| Token do jogador | Segredo aleatório que o servidor entrega a quem ocupa um lugar. Prova, nas requisições seguintes, que o autor é aquele jogador. Não é uma conta. |
| Situação da sala | `AGUARDANDO_OPONENTE`, `EM_JOGO` ou `ENCERRADA` (ver 5.3). Não confundir com o status da partida (`EM_ANDAMENTO`, `VITORIA`, `EMPATE`). |
| Versão da sala | Inteiro que o servidor incrementa a cada mudança na sala. Os clientes usam a versão para descartar estados antigos. |
| Canal em tempo real | Conexão persistente entre o navegador e o servidor pela qual o servidor envia o estado da sala sempre que ele muda (WebSocket, ver `docs/plan-online.md`, DTO-01). |
| Conectado | Um lugar está conectado quando há um canal em tempo real ativo autenticado com o token desse lugar. |
| Sala abandonada | Sala sem nenhum lugar conectado por mais tempo que o limite de abandono (RNO-16). |
| Sala encerrada | Sala fechada por saída de um jogador ou por abandono. Não aceita mais nada; o servidor ainda a reconhece por um tempo para informar "encerrada" (RNO-17). |
| Sala inexistente | Código que o servidor não conhece: nunca existiu, foi esquecido após o encerramento ou o servidor foi reiniciado. |

## 5. Modelo do domínio

### 5.1 Sala

| Elemento | Valores |
|---|---|
| Código | 6 caracteres do alfabeto `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (31 símbolos, sem `0`, `1`, `I`, `L` e `O`, que se confundem) |
| Situação | `AGUARDANDO_OPONENTE`, `EM_JOGO`, `ENCERRADA` |
| Lugar X | ocupado (sempre, desde a criação); conectado sim/não |
| Lugar O | livre ou ocupado; conectado sim/não |
| Partida | exatamente o estado de `docs/spec.md` 4.2 (tabuleiro, status, jogador da vez, vencedor, células vencedoras) |
| Número da partida | 1 na criação; +1 a cada "Nova partida" |
| Versão | inteiro ≥ 1, estritamente crescente |
| Motivo do encerramento | `SAIDA` ou `ABANDONO` (apenas com situação `ENCERRADA`) |

### 5.2 Jogador

Um jogador é **um lugar ocupado**, identificado pelo token. O token é a única credencial: quem o tem joga por aquele lugar. O símbolo de cada jogada é sempre o do lugar autenticado, nunca um valor enviado pelo navegador.

### 5.3 Ciclo de vida da sala

```
              criar sala (X ocupa)
                     │
                     ▼
         ┌── [AGUARDANDO_OPONENTE] ──── O entra ────► [EM_JOGO] ◄──┐
         │            │                                 │   │      │ nova partida
         │            │                                 │   └──────┘ (após o fim)
         │   saída de X ou abandono           saída de X ou O, ou abandono
         │            │                                 │
         │            ▼                                 ▼
         └──────► [ENCERRADA] ◄─────────────────────────┘
                      │
          após o período de lembrança (RNO-17)
                      │
                      ▼
                 (inexistente)

 Reinício do servidor: toda sala, em qualquer situação, passa a ser inexistente.
```

Dentro de `EM_JOGO`, a partida segue exatamente o diagrama de `docs/spec.md` 4.4.

## 6. Requisitos

Cada requisito do pedido recebeu um identificador **RO-xx** (Requisito Online). Todos os critérios de aceitação (seção 9) citam o requisito que verificam, e a matriz de `docs/test-plan-online.md`, seção 12, liga cada critério aos testes.

| ID | Requisito | Regras | Critérios |
|---|---|---|---|
| RO-01 | Criar uma sala de jogo com identificador único e compartilhável. | RNO-01, RNO-02 | CAO-01 a CAO-03 |
| RO-02 | Permitir que outro navegador entre na sala usando o código. | RNO-03, RNO-04 | CAO-04 a CAO-06 |
| RO-03 | Admitir dois jogadores por partida, identificados como X e O. | RNO-03, RNO-05 | CAO-07, CAO-08 |
| RO-04 | Manter partidas isoladas: cada sala tem tabuleiro, turno, resultado e participantes próprios. | RNO-06 | CAO-09 a CAO-11 |
| RO-05 | Sincronizar jogadas e resultados em tempo real entre os navegadores. | RNO-07, RNO-08 | CAO-12 a CAO-15 |
| RO-06 | Validar no servidor todas as jogadas, incluindo vez do jogador, posição ocupada e partida encerrada. | RNO-09, RNO-10 | CAO-16 a CAO-22 |
| RO-07 | Tratar jogadas simultâneas sem corromper o estado. | RNO-11 | CAO-23 a CAO-25 |
| RO-08 | Impedir que a interface determine o resultado oficial da partida. | RNO-12 | CAO-26 a CAO-28 |
| RO-09 | Informar quando uma sala estiver cheia, inexistente ou encerrada. | RNO-04, RNO-17 | CAO-29 a CAO-31 |
| RO-10 | Definir o comportamento para desconexão, reconexão e atualização da página. | RNO-13 a RNO-16 | CAO-32 a CAO-38 |
| RO-11 | Definir como reiniciar uma partida sem afetar outras salas. | RNO-18 | CAO-39 a CAO-41 |
| RO-12 | Manter a interface responsiva e acessível. | CIO-14, CIO-15 | CAO-42, CAO-43 |
| RO-13 | Preservar as rotas existentes, incluindo `/health` e o contrato atual da API, ou documentar claramente qualquer mudança. | RNO-19 | CAO-44 a CAO-46 |
| RO-14 | Manter os testes automatizados e adicionar testes para o multiplayer. | RNFO-12, RNFO-13 | CAO-47 |
| RO-15 | Definir o comportamento quando o servidor for reiniciado, sem persistência em banco de dados. | RNO-20 | CAO-48 a CAO-50 |
| RO-16 | Poder ser disponibilizado na internet com segurança, em etapa posterior à validação na rede local (DO-10). *(requisito derivado do item "Considerações de segurança" do pedido)* | RNO-21, RNO-22, RNFO-09 | CAO-51 a CAO-55 |
| RO-17 | Funcionar e ser validado na rede local, com os navegadores acessando o servidor pelo IP do computador. *(requisito derivado da decisão DO-10)* | RNO-22, RNO-23 | CAO-56 |

## 7. Regras de negócio do modo online

| ID | Regra |
|---|---|
| RNO-01 | **Criação.** Qualquer cliente pode criar uma sala. O servidor gera o código (seção 5.1) com um gerador aleatório criptograficamente seguro, garante que ele não coincide com o de nenhuma sala existente ou lembrada (RNO-17) e coloca o criador no lugar **X**. A sala nasce em `AGUARDANDO_OPONENTE`, com a partida no estado inicial de `docs/spec.md` 4.4, número da partida 1 e versão 1. |
| RNO-02 | **Link compartilhável.** O link da sala é `<origem>/online.html?sala=<CÓDIGO>`. Ele não contém o token nem qualquer outro segredo. |
| RNO-03 | **Entrada.** Quem informa o código de uma sala em `AGUARDANDO_OPONENTE` ocupa o lugar **O**; a sala passa a `EM_JOGO`. O código é aceito sem distinção de maiúsculas e minúsculas e sem espaços nas pontas. |
| RNO-04 | **Sala cheia, inexistente ou encerrada.** Entrar numa sala `EM_JOGO` é recusado com "sala cheia"; um código desconhecido, com "sala inexistente"; uma sala `ENCERRADA` ainda lembrada, com "sala encerrada". Nenhuma recusa altera a sala. |
| RNO-05 | **Reentrada.** Quem já ocupa um lugar e pede para entrar de novo apresentando o seu token recebe o **mesmo** lugar, sem ocupar outro e sem mudar a versão. |
| RNO-06 | **Isolamento.** Toda operação atua sobre uma única sala. Nenhuma operação numa sala altera, revela ou notifica outra sala. O token de um lugar só vale na sua sala. |
| RNO-07 | **Notificação.** Toda mudança aceita numa sala (entrada, jogada, nova partida, conexão, desconexão, encerramento) incrementa a versão em exatamente 1 e é enviada pelo canal em tempo real a todos os lugares conectados daquela sala. Recusas não mudam a versão e não geram notificação. |
| RNO-08 | **Estado completo e versão.** Cada notificação carrega o estado completo da sala, e não só a diferença. O cliente aplica um estado apenas se a versão dele for maior que a do último estado aplicado. Assim, notificações repetidas, atrasadas ou fora de ordem não desfazem o estado. |
| RNO-09 | **Validação da jogada.** Uma jogada só é aceita se todas as condições forem verdadeiras: a sala existe e não está encerrada; o token é de um lugar da sala; o corpo e a posição são válidos (RN-04, mesmas regras do modo local); a sala está `EM_JOGO`; a partida está `EM_ANDAMENTO`; o jogador da vez é o do lugar autenticado; a célula está vazia. O símbolo gravado é o do lugar autenticado (RN-07). |
| RNO-10 | **Ordem de validação** de uma jogada, parando no primeiro erro: (1) sala existe; (2) sala não está encerrada; (3) token válido para a sala; (4) corpo é um objeto JSON; (5) posição é um inteiro de 0 a 8; (6) sala tem os dois jogadores; (7) partida em andamento; (8) é a vez do jogador; (9) célula vazia. Os passos 4, 5, 7 e 9 são os da RN-15 do modo local, na mesma ordem relativa. |
| RNO-11 | **Concorrência.** Operações sobre a mesma sala são serializadas no servidor: cada uma vê o resultado completo da anterior. Operações sobre salas diferentes não se bloqueiam entre si. Uma jogada e o estado devolvido a ela são lidos sem que outra operação na mesma sala possa intervir. |
| RNO-12 | **Autoridade do servidor.** A interface não decide validade de jogada, turno, vencedor, empate, células vencedoras, situação da sala nem presença do oponente: ela desenha o último estado recebido do servidor. Mensagens enviadas pelo navegador no canal em tempo real não alteram a sala; o canal só serve para o servidor enviar estados e para o cliente se identificar e verificar a conexão. |
| RNO-13 | **Desconexão.** Quando o canal de um lugar fecha, ou fica sem atividade além do tempo-limite (RNFO-06), o lugar passa a desconectado e o outro jogador é notificado. O lugar continua reservado: ninguém mais pode ocupá-lo, e a partida não muda. Se era a vez do desconectado, a partida espera por ele *(premissa — ver DO-03)*. |
| RNO-14 | **Reconexão.** O cliente reabre o canal automaticamente, com espera crescente entre as tentativas, e se identifica com o token. Ao se identificar, o lugar volta a conectado, o outro jogador é notificado e o cliente recebe o estado atual, incluindo o que mudou durante a queda. O cliente para de tentar quando o servidor responde que a sala é inexistente ou está encerrada, que o token é inválido, ou que o lugar foi aberto em outra aba (RNO-15). |
| RNO-15 | **Uma conexão por lugar.** Se o mesmo lugar abrir um segundo canal (outra aba do mesmo navegador, por exemplo), o novo canal substitui o anterior, que é fechado com o motivo "aberta em outra aba". A aba substituída **não** reconecta sozinha: ela oferece "Usar nesta aba", que retoma o lugar ao ser acionado. |
| RNO-16 | **Atualização da página e retorno.** O token fica guardado no navegador, associado ao código da sala, e não aparece na URL *(premissa — ver DO-05)*. Ao recarregar ou reabrir o link da sala no mesmo navegador, o cliente retoma o mesmo lugar. **Abandono:** uma sala sem nenhum lugar conectado por mais tempo que o limite de abandono (padrão 10 minutos, *premissa — ver DO-04*) é encerrada com motivo `ABANDONO`. |
| RNO-17 | **Encerramento e período de lembrança.** Uma sala é encerrada pela saída voluntária de qualquer jogador (motivo `SAIDA`) ou por abandono (`ABANDONO`). O encerramento é notificado a quem estiver conectado e é definitivo: nenhuma operação é aceita depois dele. Durante o período de lembrança (padrão 1 hora) o servidor responde "sala encerrada"; depois disso, "sala inexistente". |
| RNO-18 | **Nova partida.** Qualquer um dos dois jogadores pode pedir "Nova partida" depois que a partida terminou (vitória ou empate). O pedido restaura o estado inicial da partida **somente daquela sala**, mantém os lugares (X continua X), incrementa o número da partida e é notificado aos dois. Com a partida em andamento, o pedido é recusado *(premissa — ver DO-01 e DO-02)*. Com a sala ainda aguardando o oponente, também é recusado. |
| RNO-19 | **Compatibilidade.** As rotas e o contrato de `docs/plan.md` seção 3 continuam iguais. Rotas novas usam o mesmo formato de erro (`{"erro":{"codigo","mensagem"}}`), o mesmo tratamento de 404 e 405 com `Allow` e a mesma codificação UTF-8. Toda mudança de comportamento de algo que já existe está listada em `docs/plan-online.md`, seção 4.3. |
| RNO-20 | **Reinício do servidor.** As salas vivem apenas na memória do processo. Ao reiniciar o servidor, todas as salas, lugares e tokens deixam de existir; qualquer operação com um código anterior recebe "sala inexistente", e a interface informa isso e para de reconectar. Encerrar o servidor fecha os canais abertos avisando os clientes de que o servidor está saindo. |
| RNO-21 | **Disponibilização pública.** Na internet, o jogo só é acessível por HTTPS. Na publicação, o servidor Delphi ouve apenas no endereço local da máquina (`--public` usa `127.0.0.1` como padrão), atrás de um proxy reverso que cuida do HTTPS. No modo público, as rotas do modo local (`/api/game*`), cuja partida é global e compartilhada por qualquer visitante, podem ser desativadas *(premissa — ver DO-07)*. |
| RNO-22 | **Origem permitida.** A abertura do canal em tempo real e as requisições `POST` das rotas de sala só são aceitas se o cabeçalho `Origin` for igual, em **esquema, host e porta**, a uma origem de uma lista montada pelo servidor a partir da sua própria configuração. O cabeçalho `Host` e cabeçalhos de proxy nunca entram nessa decisão. No modo local, a lista é formada pelos endereços locais da máquina (`127.0.0.1`, `localhost` e os IPv4 privados das interfaces abrangidas pelo bind), mais as origens configuradas; no modo público, só pelas origens configuradas, todas `https`. A ausência do cabeçalho é aceita no modo local (clientes que não são navegadores) e recusada no canal no modo público. As regras completas estão em `docs/plan-online.md`, seção 7.7. As rotas do modo local (`/health`, `/api/game*`, estáticos) não passam por essa verificação. |
| RNO-23 | **Rede local.** Com as opções padrão, o jogo online funciona por qualquer endereço da lista automática da RNO-22, em especial pelo IP privado do computador, como um celular na mesma rede o acessa. Esse modo usa HTTP sem criptografia e destina-se a uma rede confiável. |

## 8. Comportamentos esperados da interface online

A interface online é uma página própria, `/online.html`, com o script `/online.js` e o mesmo `style.css` *(premissa — ver DO-08)*. A página local (`/`) recebe apenas um link "Jogar online".

| ID | Comportamento |
|---|---|
| CIO-01 | **Tela inicial.** Sem `?sala=` na URL, a página mostra "Criar sala" e um campo "Código da sala" com o botão "Entrar". |
| CIO-02 | **Sala criada.** Depois de criar, a página mostra o código, o link compartilhável, o botão "Copiar link" (que confirma com "Link copiado.") e o status "Aguardando o oponente…". A URL da página passa a ser o próprio link da sala. |
| CIO-03 | **Abrir o link.** Com `?sala=CÓDIGO` e sem token guardado para essa sala, a página consulta a sala: se ela aguarda oponente, mostra "Entrar na sala"; se está cheia, inexistente ou encerrada, mostra a mensagem correspondente do servidor e o botão "Criar nova sala". Com token guardado, retoma o lugar sem perguntar (RNO-16). |
| CIO-04 | **Identificação.** Durante o jogo, a página mostra "Você joga com X" ou "Você joga com O". |
| CIO-05 | **Status da partida**, formatado exclusivamente a partir do estado recebido e do lugar do jogador. Os textos são exatos: "Aguardando o oponente…" (sala aguardando), "Sua vez" e "Vez do oponente" (partida em andamento), "Você venceu!", "O oponente venceu." e "Empate!" (partida encerrada). |
| CIO-06 | **Presença do oponente.** Textos exatos: "Aguardando oponente" (lugar O livre), "Oponente conectado" e "Oponente desconectado. Aguardando reconexão…". |
| CIO-07 | **Conexão do próprio navegador.** Textos exatos: "Conectado", "Reconectando…" e "Sem conexão com o servidor.". O último aparece após 30 s sem conseguir reconectar, junto com o botão "Reconectar agora". |
| CIO-08 | **Jogadas.** Todo clique numa célula é enviado ao servidor, sem validação local, inclusive fora da vez, em célula ocupada e com a partida encerrada (como DT-09 do modo local). A célula só muda quando chega um estado do servidor (resposta da jogada ou notificação). |
| CIO-09 | **Aparência de inativo**, só visual: quando não é a vez do jogador, a partida terminou ou a sala aguarda oponente, as células ficam com `aria-disabled="true"`. O clique continua sendo enviado (CIO-08) e a recusa do servidor é exibida (CIO-10). |
| CIO-10 | **Recusas.** A mensagem enviada pelo servidor aparece na área de erro (`role="alert"`) e some na próxima ação aceita ou no próximo estado recebido com versão nova. |
| CIO-11 | **Uma ação por vez.** Enquanto houver uma requisição pendente (criar, entrar, jogar, nova partida, sair), novos cliques nesses controles são ignorados, como na CI-13 do modo local. Isso não impede a chegada de estados pelo canal em tempo real. |
| CIO-12 | **Sala encerrada ou inexistente durante o jogo.** A página mostra a mensagem do servidor ("Esta sala foi encerrada." ou "Sala não encontrada. Confira o código."); nesse segundo caso, acrescenta "Se o servidor foi reiniciado, as salas anteriores deixam de existir.". O tabuleiro fica inativo, a reconexão para e o botão "Criar nova sala" aparece. O token guardado para essa sala é apagado. |
| CIO-13 | **Aberta em outra aba.** Quando o servidor substitui o canal (RNO-15), a página mostra "Esta sala foi aberta em outra aba." e o botão "Usar nesta aba", e não reconecta sozinha. |
| CIO-14 | **Acessibilidade**, mesmas exigências da CI-14 do modo local, e mais: o status da partida e a presença do oponente ficam em regiões `role="status"`, de modo que a jogada do oponente e as mudanças de conexão sejam anunciadas; o campo do código tem rótulo visível; "Criar sala", "Entrar", "Copiar link", "Nova partida", "Sair da sala", "Reconectar agora" e "Usar nesta aba" são botões alcançáveis por Tab e acionáveis por Enter e Espaço. |
| CIO-15 | **Responsividade**, a mesma da CI-15: a partir de 320 px de largura, sem rolagem horizontal em nenhuma tela (inicial, sala criada, jogo, encerrada), com células de pelo menos 44 × 44 px. |
| CIO-16 | **Identificadores estáveis** (`data-testid`) para os testes, definidos em `docs/plan-online.md`, seção 9.2. |
| CIO-17 | **Sair da sala.** O botão "Sair da sala" encerra a sala para os dois jogadores (RNO-17), depois de uma confirmação nativa do navegador ("Sair da sala encerra a partida para os dois jogadores.") *(premissa — ver DO-02)*. |

## 9. Critérios de aceitação

Formato: **Dado** / **Quando** / **Então**. "API" indica requisições HTTP ao servidor real; "WS" indica um cliente do canal em tempo real (sem navegador) contra o servidor real; "UI" indica dois ou mais navegadores isolados (contextos separados do Chromium, cada um com armazenamento próprio) contra o servidor real; "U" indica teste do domínio em Delphi, sem HTTP. Nenhum critério é verificado com respostas falsas do servidor.

Quando um critério diz que **a sala não muda**, isso significa: o estado completo da sala obtido por `GET` antes e depois é idêntico, versão incluída, e nenhum cliente conectado recebe notificação.

### RO-01 — Criar sala

- **CAO-01 — Criar sala (API, U).** Quando um cliente pede para criar uma sala, então a resposta é 201, traz o código da sala (6 caracteres do alfabeto de 5.1), o lugar `X` e um token de 32 caracteres hexadecimais; a situação é `AGUARDANDO_OPONENTE`, a partida é o estado inicial do modo local, o número da partida é 1 e a versão é 1. *(RNO-01)*
- **CAO-02 — Código único (U, API).** Quando 1.000 salas são criadas em sequência, então os 1.000 códigos são diferentes e todos seguem o formato. Quando o gerador aleatório é forçado, num teste do domínio, a repetir o código de uma sala existente ou lembrada, então o servidor gera outro código. *(RNO-01)*
- **CAO-03 — Link compartilhável (UI).** Dado que um jogador criou uma sala, então a página mostra o código, o link `/online.html?sala=<CÓDIGO>` (sem token) e "Aguardando o oponente…"; quando ele aciona "Copiar link", então a área de transferência contém o link e aparece "Link copiado."; quando o link é aberto em outro navegador, então aparece a opção "Entrar na sala". *(RNO-02, CIO-02, CIO-03)*

### RO-02 — Entrar na sala

- **CAO-04 — Entrar pelo código (API).** Dada uma sala aguardando oponente, quando outro cliente pede para entrar com o código, então a resposta é 201 com o lugar `O` e um token diferente do de X, e a sala passa a `EM_JOGO` com versão 2. *(RNO-03)*
- **CAO-05 — Entrar pela interface (UI).** Dada uma sala criada no navegador A, quando o navegador B digita o código em minúsculas e com espaços nas pontas e aciona "Entrar", então B entra como O; quando, em outra sala, o navegador C abre o link e aciona "Entrar na sala", então C entra como O. *(RNO-03, CIO-01, CIO-03)*
- **CAO-06 — Reentrada com o próprio token (API).** Dado que O já entrou, quando O pede para entrar de novo apresentando o seu token, então a resposta é 200 com o mesmo lugar e o mesmo token, e a sala não muda. *(RNO-05)*

### RO-03 — Dois jogadores, X e O

- **CAO-07 — Símbolo pelo lugar (API, U).** Dada uma sala `EM_JOGO`, quando X joga na célula 0 enviando também `"simbolo":"O"` no corpo, então a célula 0 recebe X; quando O joga na célula 4, então a célula 4 recebe O. *(RNO-09, RN-07)*
- **CAO-08 — Cada um sabe quem é (UI).** Dada uma sala com A como criador e B como convidado, então A mostra "Você joga com X" e B mostra "Você joga com O", e ambos mostram, para X na vez, "Sua vez" em A e "Vez do oponente" em B. *(CIO-04, CIO-05)*

### RO-04 — Salas isoladas

- **CAO-09 — Estado isolado (API, U).** Dadas duas salas S1 e S2 em jogo, quando uma partida completa é jogada em S1, então o estado de S2 não muda; e a partida do modo local (`GET /api/game`) também não muda. *(RNO-06)*
- **CAO-10 — Notificações isoladas (WS).** Dados clientes conectados em S1 e em S2, quando S1 recebe entrada, jogadas, nova partida e encerramento, então os clientes de S2 não recebem nenhuma mensagem nesse período. *(RNO-06, RNO-07)*
- **CAO-11 — Token não vale em outra sala (API, U).** Quando o token de X de S1 é usado para jogar, reiniciar ou sair em S2, então a resposta é 401 `TOKEN_INVALIDO` e nenhuma das duas salas muda. *(RNO-06)*

### RO-05 — Tempo real

- **CAO-12 — Jogada aparece no outro navegador (UI).** Dados A (X) e B (O) na mesma sala, quando A joga na célula 0, então B mostra X na célula 0 e "Sua vez" em no máximo 2 s, sem recarregar a página e sem nenhuma ação em B. O tempo medido fica registrado no relatório (meta: até 500 ms, RNFO-05). *(RNO-07)*
- **CAO-13 — Resultado idêntico (UI).** Quando A e B jogam uma partida até a vitória de X, então os dois mostram o mesmo tabuleiro e as mesmas células vencedoras destacadas, A mostra "Você venceu!" e B mostra "O oponente venceu."; numa partida empatada, os dois mostram "Empate!". *(RNO-07, CIO-05)*
- **CAO-14 — Entrada do oponente é notificada (UI, WS).** Dado A aguardando numa sala nova, quando B entra, então A passa a mostrar "Sua vez" e "Oponente conectado" sem recarregar; e um cliente WS de X recebe um estado `EM_JOGO`, com motivo `ENTRADA` e versão igual à anterior + 1. *(RNO-07)*
- **CAO-15 — Ordem das notificações (WS).** Dados clientes de X e de O conectados, quando as 9 jogadas de uma partida completa são feitas, então cada cliente recebe estados com versões estritamente crescentes, e o último estado recebido é idêntico ao obtido por `GET`. *(RNO-07, RNO-08)*

### RO-06 — Validação no servidor

Em todos estes critérios, a recusa vem com o código HTTP e o código de erro indicados, com a mensagem exata de `docs/plan-online.md` seção 6.6, e **a sala não muda**.

- **CAO-16 — Fora da vez (API, UI).** Dada a vez de X, quando O tenta jogar, então 409 `VEZ_DO_OPONENTE`. Pela interface, o clique de O é enviado e a mensagem "Não é a sua vez." aparece. *(RNO-09, CIO-08, CIO-10)*
- **CAO-17 — Célula ocupada (API).** Dado X na célula 0 e a vez de O, quando O joga na célula 0, então 409 `CELULA_OCUPADA`. *(RNO-09)*
- **CAO-18 — Partida encerrada (API).** Dada uma partida terminada por vitória e, em outra sala, uma por empate, quando qualquer um dos dois jogadores tenta jogar, então 409 `PARTIDA_ENCERRADA`. *(RNO-09)*
- **CAO-19 — Sem oponente (API).** Dada uma sala aguardando oponente, quando X tenta jogar, então 409 `AGUARDANDO_OPONENTE`. *(RNO-09)*
- **CAO-20 — Sem token ou token inválido (API, WS).** Quando uma jogada é enviada sem token, com token mal formado ou com token inexistente, então 401 `TOKEN_INVALIDO`; quando um cliente WS se identifica com um token inválido, então recebe o erro `TOKEN_INVALIDO` e o canal é fechado com o código 4401. *(RNO-09)*
- **CAO-21 — Corpo e posição inválidos (API).** Quando a jogada tem corpo ausente, vazio, não JSON ou JSON que não é objeto, então 400 `CORPO_INVALIDO`; quando a posição é 9, -1, 4.5, `"4"`, `null`, `true` ou está ausente, então 400 `POSICAO_INVALIDA`. *(RNO-09, RN-04)*
- **CAO-22 — Ordem de validação (API, U).** Para cada linha da tabela de precedência de `docs/test-plan-online.md` (cenário OR-08), quando a jogada tem dois ou mais problemas ao mesmo tempo, então o erro devolvido é o do primeiro passo da RNO-10. Exemplos: token inválido e posição 9 → `TOKEN_INVALIDO`; fora da vez e célula ocupada → `VEZ_DO_OPONENTE`; partida encerrada e fora da vez → `PARTIDA_ENCERRADA`; sala encerrada e token inválido → `SALA_ENCERRADA`. *(RNO-10)*

### RO-07 — Jogadas simultâneas

- **CAO-23 — Mesmo jogador, duas jogadas ao mesmo tempo (API, U).** Dada a vez de X, quando X envia ao mesmo tempo jogadas nas células 0 e 1, então exatamente uma é aceita, a outra recebe 409 `VEZ_DO_OPONENTE`, o tabuleiro tem um único X, a vez é de O e a versão subiu exatamente 1. Repetido 20 vezes. *(RNO-11)*
- **CAO-24 — X e O ao mesmo tempo (API).** Dada a vez de X, quando X e O enviam jogadas ao mesmo tempo, então a de X é aceita e a de O recebe `VEZ_DO_OPONENTE`, em todas as 20 repetições. *(RNO-11)*
- **CAO-25 — Muitas salas em paralelo (API, U).** Quando 20 salas jogam partidas completas ao mesmo tempo, com rajadas de jogadas simultâneas, então nenhuma resposta é 500, cada sala termina com um estado coerente (nº de X − nº de O é 0 ou 1; vez, vencedor e células compatíveis com o status), o número de jogadas aceitas em cada sala é igual ao número de células preenchidas nela e nenhuma sala tem jogadas de outra. *(RNO-06, RNO-11)*

### RO-08 — A interface não decide

- **CAO-26 — Só o servidor muda o tabuleiro (UI).** Com a resposta da jogada atrasada em 1 s (a resposta real, só atrasada), quando A clica numa célula vazia na sua vez, então a célula continua vazia até a resposta chegar e depois mostra X; quando A clica fora da vez, então o tabuleiro não muda e a mensagem do servidor aparece. *(RNO-12, CIO-08)*
- **CAO-27 — Estado montado pelo servidor (UI).** Dados A e B na sala, quando as jogadas de uma vitória de O são feitas diretamente pela API com os tokens dos dois, então A e B mostram, sem nenhum clique, o tabuleiro, as células vencedoras e os resultados decididos pelo servidor. *(RNO-12)*
- **CAO-28 — Mensagens do cliente não mudam a sala (WS, U).** Quando um cliente identificado envia pelo canal mensagens que tentam jogar, impor um estado ou um vencedor (`{"tipo":"jogada",...}`, `{"tipo":"estado",...}`), texto que não é JSON ou um quadro binário, então recebe o erro `MENSAGEM_INVALIDA`, o canal é fechado com 4400 e a sala não muda. *(RNO-12)*

### RO-09 — Sala cheia, inexistente ou encerrada

- **CAO-29 — Sala cheia (API, UI).** Dada uma sala `EM_JOGO`, quando um terceiro cliente tenta entrar, então 409 `SALA_CHEIA` com a mensagem "Esta sala já tem dois jogadores."; pela interface, o terceiro navegador mostra essa mensagem e "Criar nova sala". *(RNO-04, CIO-03)*
- **CAO-30 — Sala inexistente (API, UI).** Quando um código que nunca existiu, ou malformado (`abc`, `K7PM2Q0`, `../x`), é usado para consultar, entrar, jogar, reiniciar ou sair, então 404 `SALA_INEXISTENTE` com a mensagem "Sala não encontrada. Confira o código."; pela interface, a mensagem aparece ao abrir o link ou ao digitar o código. *(RNO-04)*
- **CAO-31 — Sala encerrada (API, WS, UI).** Dados A e B na sala, quando B aciona "Sair da sala", então A recebe a notificação de encerramento e mostra "Esta sala foi encerrada." e "Criar nova sala"; a partir daí, qualquer operação na sala responde 410 `SALA_ENCERRADA`, e um cliente WS que tenta se identificar nela recebe `SALA_ENCERRADA` e o fechamento 4410. *(RNO-04, RNO-17, CIO-12)*

### RO-10 — Desconexão, reconexão e atualização da página

- **CAO-32 — Fechar a aba (UI, WS).** Dados A e B jogando, quando a aba de B é fechada, então A mostra "Oponente desconectado. Aguardando reconexão…" em até 2 s; quando B reabre o link no mesmo navegador, então B retoma o lugar O com o mesmo estado e A volta a mostrar "Oponente conectado". *(RNO-13, RNO-14, RNO-16)*
- **CAO-33 — Queda silenciosa (WS).** Dado um cliente de O que para de responder sem fechar a conexão, quando passa o tempo-limite de inatividade (60 s no padrão; 3 s no servidor de teste, RNFO-06), então o servidor fecha esse canal e o cliente de X recebe um estado com O desconectado. Um cliente que envia `ping` dentro do prazo recebe `pong` com o mesmo identificador e não é desconectado. *(RNO-13)*
- **CAO-34 — Reconexão automática (UI, WS).** Dados A e B jogando, quando o canal de B cai (simulado no navegador) e A joga durante a queda, então B mostra "Reconectando…", reconecta sozinho e passa a mostrar a jogada de A, sem recarregar a página. *(RNO-14, CIO-07)*
- **CAO-35 — Atualizar a página (UI).** Dados A e B no meio de uma partida, quando B recarrega a página, então B continua sendo O, vê o mesmo tabuleiro e o mesmo status, e a sala continua com dois lugares (nenhum lugar novo foi ocupado). *(RNO-16)*
- **CAO-36 — Mesma sala em outra aba (UI, WS).** Dado B jogando numa aba, quando B abre o link da sala numa segunda aba do mesmo navegador, então a segunda aba assume o lugar O, a primeira mostra "Esta sala foi aberta em outra aba." e "Usar nesta aba", e nenhuma das duas fica reconectando em laço (no máximo 3 aberturas de canal em 10 s). *(RNO-15, CIO-13)*
- **CAO-37 — Lugar reservado (API, U).** Dado O desconectado na sua vez, quando X tenta jogar, então 409 `VEZ_DO_OPONENTE`; quando um terceiro tenta entrar, então 409 `SALA_CHEIA`; quando O reconecta, então pode jogar normalmente. *(RNO-13)*
- **CAO-38 — Sala abandonada (U, API).** Dada uma sala sem nenhum lugar conectado, quando passa o limite de abandono (10 min no padrão; 2 s no servidor de teste), então a sala é encerrada com motivo `ABANDONO` e responde 410 durante o período de lembrança e 404 depois dele; uma sala com pelo menos um lugar conectado não é encerrada por abandono. *(RNO-16, RNO-17)*

### RO-11 — Nova partida

- **CAO-39 — Nova partida após o fim (API, UI).** Dada uma partida terminada, quando qualquer um dos dois jogadores aciona "Nova partida", então os dois navegadores mostram o tabuleiro vazio e "Sua vez" para X / "Vez do oponente" para O, o número da partida passa a 2 e os lugares não mudam. *(RNO-18)*
- **CAO-40 — Nova partida no meio do jogo (API, UI).** Dada uma partida em andamento, ou uma sala aguardando oponente, quando um jogador pede nova partida, então 409 `PARTIDA_EM_ANDAMENTO` (ou `AGUARDANDO_OPONENTE`) e a sala não muda; pela interface, a mensagem do servidor aparece. *(RNO-18)*
- **CAO-41 — Nova partida não afeta outra sala (API).** Dadas S1 terminada e S2 em andamento, quando S1 recebe nova partida, então S2 não muda. *(RNO-06, RNO-18)*

### RO-12 — Responsiva e acessível

- **CAO-42 — Tela pequena (UI).** Numa viewport de 360 × 640, as telas inicial, sala criada, jogo e sala encerrada não têm rolagem horizontal, o tabuleiro cabe na largura, cada célula mede pelo menos 44 × 44 px e uma jogada funciona. *(CIO-15)*
- **CAO-43 — Teclado e leitor de tela (UI).** Só com o teclado, é possível criar a sala, copiar o link, (em outro navegador) digitar o código e entrar, e jogar com Enter e Espaço, movendo o foco pelas setas; a página tem `lang="pt-BR"`, um `h1`, uma região `main`, rótulo no campo do código, status da partida e presença do oponente em `role="status"`, erro em `role="alert"`, e as células têm os nomes acessíveis da CI-14. *(CIO-14)*

### RO-13 — Rotas e contrato preservados

- **CAO-44 — Regressão do modo local.** Em toda entrega, a suíte existente passa inteira (109 testes Playwright: 80 de API e 29 de Chromium), o `EngineCheck` passa os 27 casos atuais e nenhum arquivo de teste existente é alterado para isso. *(RNO-19)*
- **CAO-45 — Rotas novas seguem o padrão (API, WS).** Rotas novas respondem com `application/json; charset=utf-8` e `Cache-Control: no-store`, erros no formato único com acentos corretos em UTF-8, 404 `ROTA_NAO_ENCONTRADA` para sub-rotas inexistentes, 405 `METODO_NAO_PERMITIDO` com `Allow` para métodos errados e `HEAD` onde há `GET`. O canal em tempo real aceita um pedido de abertura válido (101 com a chave de aceite correta) e recusa os inválidos com 400, 405 ou 426. *(RNO-19)*
- **CAO-46 — Endereço de escuta (API, script).** Sem opções de linha de comando, o servidor escuta em todas as interfaces (`0.0.0.0`), como o código atual, e é alcançável por outro aparelho da rede local; com `--bind 127.0.0.1`, escuta só no endereço local; com `--public` e sem `--bind`, escuta só em `127.0.0.1`. Nos três casos, a página e o canal funcionam pelo endereço usado no navegador. A mudança em relação à RNF-04 está registrada em `docs/plan-online.md`, seção 4.3. *(RNO-19, RNO-21)*

### RO-14 — Testes

- **CAO-47 — Cobertura e prova de que os testes detectam defeitos (script).** Todo critério CAO-01 a CAO-56 tem pelo menos um teste executado contra o servidor real; as sabotagens SB-07 a SB-13 de `docs/test-plan-online.md` fazem falhar os testes indicados; a suíte completa (modo local + online) passa duas vezes seguidas sem retries, testes pulados ou instáveis. *(RNFO-12, RNFO-13)*

### RO-15 — Reinício do servidor

- **CAO-48 — Salas somem no reinício (API, WS).** Dada uma sala em jogo, quando o servidor é finalizado e iniciado de novo na mesma porta, então `GET` da sala responde 404 `SALA_INEXISTENTE`, jogar com o token antigo responde 404 `SALA_INEXISTENTE` e um cliente WS que se identifica com o código e o token antigos recebe `SALA_INEXISTENTE` e o fechamento 4404. *(RNO-20)*
- **CAO-49 — A interface informa e para (UI).** Dados A e B jogando, quando o servidor é reiniciado, então os dois mostram "Reconectando…" enquanto ele está fora do ar e, quando ele volta, "Sala não encontrada. Confira o código." com "Se o servidor foi reiniciado, as salas anteriores deixam de existir." e "Criar nova sala"; depois disso, não há novas tentativas de reconexão. *(RNO-14, RNO-20, CIO-12)*
- **CAO-50 — Encerramento com canais abertos (script).** Com 10 canais abertos, quando o servidor recebe Ctrl+C, então cada cliente recebe o fechamento 1001 ("servidor encerrando") e o processo termina com código 0 em até 5 s, liberando a porta. *(RNO-20, RNF-12)*

### RO-16 — Disponibilização pública com segurança

- **CAO-51 — Origem do canal e das rotas de sala (WS, API, U).** No modo local, sem opções, a abertura do canal é aceita com `Origin` `http://127.0.0.1:<porta>`, `http://localhost:<porta>` e `http://<IP privado da máquina>:<porta>`, e recusada com 403 `ORIGEM_NAO_PERMITIDA` quando a origem difere em esquema (`https://…`), host (outra máquina, um site externo, o nome do computador sem `--allowed-origin`) ou porta, quando é `null`, malformada, tem caminho ou aparece duas vezes, e quando o `Host` da requisição foi forjado para coincidir com uma origem não permitida; sem `Origin`, é aceita. Uma origem incluída por `--allowed-origin` passa a ser aceita. No modo público, só as origens `https` configuradas são aceitas, e a ausência de `Origin` é recusada. Um `POST` de sala com `Origin` não permitida recebe 403 e não muda nada; as rotas do modo local continuam iguais. *(RNO-22)*
- **CAO-52 — Limites de tamanho (API, WS).** Quando o corpo de uma requisição de sala passa de 1 KB, então 413 `CORPO_MUITO_GRANDE`; quando uma mensagem do canal passa de 4 KB, então o canal é fechado com 1009; quando o cliente envia um quadro sem máscara, então o canal é fechado com 1002. *(RNO-21)*
- **CAO-53 — Limites de taxa e de capacidade (API).** Com limites baixos configurados no servidor de teste, quando um mesmo endereço cria salas acima do limite por minuto, então 429 `LIMITE_DE_REQUISICOES` com `Retry-After`; quando o número máximo de salas ativas é atingido, então 503 `CAPACIDADE_ESGOTADA`. *(RNO-21)*
- **CAO-54 — Token protegido (UI, script).** Durante toda a suíte online, nenhum token aparece em URL de página ou de requisição, em resposta de `GET` da sala nem no log do servidor. *(RNO-02, RNFO-09)*
- **CAO-55 — Modo público (API).** Com `--public`, as rotas `/api/game`, `/api/game/moves` e `/api/game/reset` respondem 404 `ROTA_NAO_ENCONTRADA`, `/health` continua respondendo, e todas as respostas trazem `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` e, nas páginas, `Content-Security-Policy` com `default-src 'self'` e `frame-ancestors 'none'`. Sem `--public`, as rotas locais funcionam como hoje (CAO-44). *(RNO-21, DO-07)*

### RO-17 — Rede local

- **CAO-56 — Partida pelo IP da rede local (UI, manual).** Com o servidor iniciado sem opções, quando um navegador abre `http://<IP privado da máquina>:8765/online.html` e outro abre `http://127.0.0.1:8765/online.html`, então os dois jogam uma partida completa na mesma sala, com as jogadas aparecendo em tempo real nos dois; e, na validação manual, o mesmo vale entre um celular na mesma rede Wi-Fi e o computador. *(RNO-23)*

## 10. Cenários de erro

| ID | Situação | HTTP / canal | Código | Efeito na sala | Interface | CA |
|---|---|---|---|---|---|---|
| CEO-01 | Código desconhecido ou malformado | 404 / fechamento 4404 | `SALA_INEXISTENTE` | — | Mensagem + "Criar nova sala" | CAO-30, CAO-48 |
| CEO-02 | Sala encerrada e ainda lembrada | 410 / fechamento 4410 | `SALA_ENCERRADA` | — | Mensagem + "Criar nova sala" | CAO-31, CAO-38 |
| CEO-03 | Entrar em sala com dois jogadores | 409 | `SALA_CHEIA` | Inalterada | Mensagem + "Criar nova sala" | CAO-29 |
| CEO-04 | Token ausente, mal formado ou de outra sala | 401 / fechamento 4401 | `TOKEN_INVALIDO` | Inalterada | Mensagem; token guardado é apagado | CAO-11, CAO-20 |
| CEO-05 | Jogada fora da vez | 409 | `VEZ_DO_OPONENTE` | Inalterada | Mensagem | CAO-16 |
| CEO-06 | Jogada antes do oponente | 409 | `AGUARDANDO_OPONENTE` | Inalterada | Mensagem | CAO-19 |
| CEO-07 | Célula ocupada / partida encerrada / corpo ou posição inválidos | 409 / 409 / 400 | os do modo local | Inalterada | Mensagem | CAO-17, CAO-18, CAO-21 |
| CEO-08 | Nova partida com a partida em andamento | 409 | `PARTIDA_EM_ANDAMENTO` | Inalterada | Mensagem | CAO-40 |
| CEO-09 | Mensagem inválida no canal | fechamento 4400 | `MENSAGEM_INVALIDA` | Inalterada | (não ocorre pela interface) | CAO-28 |
| CEO-10 | Canal sem identificação ou sem atividade além do prazo | fechamento 4408 | `TEMPO_ESGOTADO` | Lugar desconectado | Reconecta | CAO-33 |
| CEO-11 | Lugar aberto em outra aba | fechamento 4000 | `SUBSTITUIDA` | Lugar continua conectado (pela nova aba) | "Usar nesta aba" | CAO-36 |
| CEO-12 | Servidor fora do ar | — | — | — | "Reconectando…" e, após 30 s, "Sem conexão com o servidor." | CAO-49 |
| CEO-13 | Servidor encerrando | fechamento 1001 | — | — | "Reconectando…" | CAO-50 |
| CEO-14 | Pedido de abertura do canal inválido | 400 / 405 / 426 | `HANDSHAKE_INVALIDO` / `METODO_NAO_PERMITIDO` / `VERSAO_WEBSOCKET` | — | — | CAO-45 |
| CEO-15 | Origem não permitida | 403 | `ORIGEM_NAO_PERMITIDA` | — | — | CAO-51 |
| CEO-16 | Corpo grande demais / mensagem grande demais / quadro sem máscara | 413 / 1009 / 1002 | `CORPO_MUITO_GRANDE` / — / — | Inalterada | — | CAO-52 |
| CEO-17 | Excesso de requisições / capacidade esgotada | 429 / 503 | `LIMITE_DE_REQUISICOES` / `CAPACIDADE_ESGOTADA` | — | Mensagem | CAO-53 |
| CEO-18 | Exceção inesperada | 500 / fechamento 1011 | `ERRO_INTERNO` | Inalterada (a operação é desfeita ou não chega a ser aplicada) | Mensagem | — (coberto pelos controles de "nenhuma 500" dos testes) |

## 11. Requisitos não funcionais do modo online

| ID | Requisito |
|---|---|
| RNFO-01 | **Compatibilidade:** compila e executa no Delphi 10.1 Berlin (compilador 31.0) com a RTL e o **Indy 10.6.2.5341** que acompanham essa versão (versão lida de `IdVers.inc` da instalação em 2026-10-16). Sem recursos de versões posteriores (RNF-01) e sem componentes de terceiros. |
| RNFO-02 | **Plataforma e ferramentas:** Windows 10 Pro (build 19045), Node.js 24.11.1, Playwright 1.64.1, TypeScript 5.9.3, as mesmas da Entrega 5. Nenhum pacote npm novo: o cliente WebSocket dos testes é o nativo do Node e o do Chromium *(a confirmar na Entrega O0)*. |
| RNFO-03 | **Sem persistência:** salas, lugares e tokens só em memória (RNO-20). |
| RNFO-04 | **Rede:** por padrão, escuta em todas as interfaces (`0.0.0.0`), para permitir o acesso por outros aparelhos da rede local, como o celular (decisão de 2026-10-16, DO-09). Isso **substitui a RNF-04** de `docs/spec.md` para os dois modos. `--bind` escolhe outro endereço; com `--public`, o padrão é `127.0.0.1` (atrás do proxy). Página, API e canal em tempo real na **mesma origem e porta**, sem CORS (RNF-05). |
| RNFO-05 | **Latência (meta, medida e registrada):** em localhost, uma jogada aparece no outro navegador em até 500 ms no percentil 95. O limite verificado pelos testes é 2 s (CAO-12). |
| RNFO-06 | **Tempos:** o cliente envia `ping` a cada 20 s; o servidor fecha o canal sem nenhuma mensagem recebida há 60 s; o cliente tem 5 s após abrir o canal para se identificar; limite de abandono de 10 min; período de lembrança de 1 h. Todos configuráveis por linha de comando, para que os testes usem valores de poucos segundos. |
| RNFO-07 | **Capacidade inicial:** pelo menos 100 salas ativas e 200 canais simultâneos num único processo; limites configuráveis (padrões em `docs/plan-online.md`, seção 11.4). |
| RNFO-08 | **Concorrência:** cada sala é protegida pela sua própria seção crítica; o registro de salas tem uma seção crítica própria; a ordem de aquisição é fixa e documentada, para não haver impasse (*deadlock*). |
| RNFO-09 | **Segurança:** token de 128 bits de um gerador criptograficamente seguro do Windows; token nunca em URL, nunca em resposta de consulta e nunca em log; verificação de `Origin` contra uma lista de origens permitidas, por esquema, host e porta, sem usar o `Host` (RNO-22); limites de tamanho, de taxa e de capacidade; HTTPS obrigatório na publicação, feito por proxy reverso (`docs/plan-online.md`, seção 13). |
| RNFO-10 | **Encerramento limpo:** Ctrl+C com canais abertos encerra em até 5 s, avisando os clientes (CAO-50). |
| RNFO-11 | **Testabilidade:** o relógio do domínio de salas e o gerador aleatório são substituíveis nos testes Delphi; os tempos são configuráveis no servidor real. Como no modo local, nenhum teste substitui respostas do servidor por respostas falsas; as únicas intervenções de rede são abortar, atrasar ou derrubar conexões reais (como na D-12 do modo local). |
| RNFO-12 | **Rastreabilidade:** cada teste cita no título o cenário e o(s) CAO que cobre. |
| RNFO-13 | **Regressão:** em toda entrega, a suíte existente (109 testes) e o `EngineCheck` (27 casos atuais) passam sem alteração nos arquivos de teste existentes. |
| RNFO-14 | **Codificação:** mensagens do canal em texto UTF-8 válido (validado no servidor); respostas HTTP em UTF-8 como no modo local (RNF-08). |
| RNFO-15 | **Navegadores:** os testes automatizados usam o Chromium do Playwright, como no modo local; Firefox e o navegador de um celular entram na validação manual na rede local (checklist MV-L, Entrega O7) *(premissa — ver DO-14)*. |

## 12. Dúvidas e premissas a confirmar

Até cada dúvida ser respondida, vale a **premissa** indicada. Respostas diferentes serão registradas na seção 13 e propagadas para o plano e o plano de testes.

| ID | Dúvida | Premissa adotada |
|---|---|---|
| DO-01 | Quem começa nas partidas seguintes da mesma sala? | Sempre X, que é sempre o criador; os símbolos não trocam. (Trocar os símbolos a cada partida é possível sem mudar o motor, mas fica fora desta versão.) |
| DO-02 | "Nova partida" e "Sair" precisam do consentimento do outro jogador? | Nova partida só depois do fim, por qualquer um dos dois, sem confirmação do outro. Sair encerra a sala para os dois, com confirmação apenas de quem sai. |
| DO-03 | Há desistência automática (W.O.) quando um jogador some? | Não. O lugar fica reservado até a sala ser encerrada por abandono (quando ninguém está conectado) ou pela saída do outro jogador. |
| DO-04 | Limite de abandono e período de lembrança. | 10 minutos e 1 hora. |
| DO-05 | O token fica guardado por aba (`sessionStorage`) ou pelo navegador (`localStorage`)? | `localStorage`, por código de sala, com validade de 24 h: permite voltar à sala depois de fechar a aba (CAO-32). Duas abas do mesmo navegador são o mesmo jogador (RNO-15). Para jogar consigo mesmo num só computador, usa-se uma janela anônima ou outro navegador. |
| DO-06 | Quem tem o código pode ver a sala sem jogar? | Sim, por `GET` (sem tokens na resposta); espectadores pelo canal em tempo real ficam fora do escopo. |
| DO-07 | O que fazer com a partida global do modo local quando o servidor estiver na internet? | Por padrão, as rotas locais continuam ativas (testes e uso local); com `--public`, elas respondem 404. |
| DO-08 | A interface online substitui a página atual? | Não: página própria, `/online.html`; a página local ganha um link "Jogar online". |
| DO-09 | O código atual (`server/src/uHttpApp.pas`) faz bind em `0.0.0.0`, ao contrário do comentário ao lado, da RNF-04 e do README. Foi intencional? | **Respondida em 2026-10-16:** sim, para acessar pelo celular. O padrão `0.0.0.0` é mantido (RNFO-04); `--bind` permite restringir, e `--public` usa `127.0.0.1`. A verificação de `Origin` do canal compara com o cabeçalho `Host` da própria requisição, para que o acesso pelo IP da rede local funcione (`docs/plan-online.md`, 7.1). O comentário do código, `docs/spec.md` (RNF-04), `docs/plan.md` (DT-07) e o README serão alinhados na Entrega O2. |
| DO-10 | Onde o jogo será publicado? | **Respondida em 2026-10-16:** a implementação é desenvolvida e validada primeiro na **rede local**, com o servidor Delphi no Windows e acesso pelo IP da rede (RO-17). A publicação (domínio, HTTPS, proxy reverso) fica para uma etapa posterior, a Entrega O8, que só começa depois de confirmado o ambiente definitivo de hospedagem. |
| DO-11 | Um proxy reverso (Caddy) é aceitável na etapa pública? | **Respondida em 2026-10-16:** sim, o Caddy pode ser considerado como proxy reverso da etapa pública, com HTTPS e WebSocket. Nesta fase ele é **apenas documentado** (`docs/plan-online.md`, 16.3); nada é instalado nem configurado. |
| DO-12 | Os jogadores terão nome ou apelido? | Não nesta versão. |
| DO-13 | Limites numéricos (salas, canais, taxas). | Os padrões de `docs/plan-online.md`, seção 11.4. |
| DO-14 | Testes automatizados em outros navegadores? | Só Chromium; Firefox e celular na validação manual da Entrega O7. |
| DO-15 | Contingência por *polling* quando o WebSocket não funcionar (rede corporativa, proxy antigo)? | Não nesta versão. A página sempre consulta a sala por `GET` ao abrir e ao reconectar, então o jogo volta a funcionar quando o canal volta. A contingência continua registrada como alternativa (DTO-01, alternativa E). |
| DO-16 | A Entrega O6 (limites de taxa, cabeçalhos de segurança, modo `--public`) é feita antes da validação na rede local ou junto com a publicação? | Antes, na sequência O1 → O7: os limites e os cabeçalhos também protegem a rede local, e o modo `--public` pode ser testado no próprio computador sem publicar nada. |
| DO-17 | Quais endereços entram automaticamente na lista de origens do modo local? | `127.0.0.1`, `localhost` e os IPv4 **privados** (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) das interfaces abrangidas pelo bind, recalculados a cada 60 s. Outros endereços (nome do computador, IP público, VPN) só com `--allowed-origin`. |

## 13. Registro de alterações

| Versão | Data | Alteração |
|---|---|---|
| 0.1 | 2026-10-16 | Criação a partir do pedido de evolução para multiplayer online, depois de inspecionar os documentos SDD, o código do servidor, da interface e dos testes, e o código-fonte do Indy 10.6.2.5341 instalado. Requisitos RO-01 a RO-16, regras RNO-01 a RNO-21, comportamentos CIO-01 a CIO-17, critérios CAO-01 a CAO-55, erros CEO-01 a CEO-18, requisitos não funcionais RNFO-01 a RNFO-15 e dúvidas DO-01 a DO-15. Nenhum código foi alterado. |
| 0.2 | 2026-10-16 | DO-09 respondida: o bind `0.0.0.0` é intencional (acesso pelo celular) e passa a ser o padrão (RNFO-04, CAO-46); `--public` usa `127.0.0.1`. RNO-21 ajustada. |
| 0.3 | 2026-10-16 | Planejamento v0.2 aprovado com decisões: DO-10 (validação na rede local; publicação na Entrega O8, depois de confirmada a hospedagem) e DO-11 (Caddy só documentado) respondidas; validação de origem revista: lista de origens permitidas por esquema, host e porta, sem confiar no `Host` (RNO-22, CAO-51 reescrito); novo RO-17 (rede local) com RNO-23 e CAO-56; novas dúvidas DO-16 e DO-17. |
