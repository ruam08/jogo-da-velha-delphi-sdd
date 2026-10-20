# Checklist de publicação — Entrega O8 (preparação, sem publicar)

| Campo | Valor |
|---|---|
| Versão | 0.1 (Entrega O7) |
| Data | 2026-10-20 |
| Base | `docs/plan-online.md` v0.9 (16.3, 13.1), `docs/test-plan-online.md` v0.9 (13.5, MV-P) |
| Status | **Só referência.** A O8 foi cancelada pelo usuário em 20/10/2026 (projeto de estudo, sem publicação). Nada desta lista foi instalado, configurado ou exposto. |

Cada item tem uma caixa para marcar durante a O8 e diz como conferir. "Decidir" é decisão sua; "Fazer" é execução na O8; "Conferir" é verificação registrada no `delivery-log`.

## 1. Decisões que precisam vir antes (bloqueiam a O8)

- [ ] **Decidir a hospedagem (DO-10).**
  - (a) **Este computador:** exige redirecionar as portas 80 e 443 no roteador, ter IP público fixo ou DNS dinâmico e confirmar que a operadora não usa CGNAT (com CGNAT, conexões de fora não chegam).
  - (b) **Servidor Windows alugado** (Windows Server 2019 ou superior): o mesmo `.exe` roda sem alteração.
  - Conferir no caso (a): o IP WAN do roteador é igual ao IP mostrado por um site de "qual é meu IP". Se for diferente, há CGNAT.
- [ ] **Decidir o domínio** (por exemplo, `jogo.exemplo.com.br`) e quem administra o DNS.
- [ ] **Decidir quem opera:** quem reinicia o servidor, quem recebe alertas, janela de manutenção (um reinício encerra todas as salas, RNO-20).
- [ ] **Decidir a retenção dos logs**, que contêm IPs (sugestão: 7 dias) e onde eles ficam.
- [ ] **Autorizar o versionamento:** os trabalhos das O1 a O7 ainda não estão em commit. Para ter um ponto de volta (seção 9), é preciso commit e uma tag (por exemplo, `v2.0`), feitos só com a sua autorização.

## 2. Pré-requisitos da máquina

- [ ] Windows 10/11 ou Windows Server 2019+, com o executável compilado pelo Delphi 10.1 Berlin e a pasta `web\` ao lado (o servidor não precisa de mais nada instalado).
- [ ] Relógio do sistema sincronizado (os certificados e os prazos dependem dele).
- [ ] Usuário sem privilégio de administrador para rodar o servidor (o servidor não precisa de administrador; só o proxy usa as portas 80/443).
- [ ] Antivírus/Defender sem bloquear o `.exe` (conferir: o servidor inicia e `/health` responde 200 em `127.0.0.1`).

## 3. Domínio e DNS

- [ ] Registro **A** (e **AAAA**, se houver IPv6) do domínio apontando para o IP público da hospedagem.
- [ ] TTL baixo (300 s) durante a implantação, para permitir voltar atrás rápido; aumentar depois.
- [ ] Conferir: `nslookup <domínio>` devolve o IP público esperado, de uma rede externa (por exemplo, o celular no 4G).

## 4. HTTPS e proxy reverso (Caddy, DO-11)

- [ ] Instalar o Caddy (binário único) **na mesma máquina** do servidor.
- [ ] Caddyfile mínimo (referência; ajustar o domínio):
  ```
  jogo.exemplo.com.br {
      encode gzip
      header Strict-Transport-Security "max-age=31536000"
      request_body {
          max_size 64KB
      }
      reverse_proxy 127.0.0.1:8765
  }
  ```
  - O Caddy obtém e renova o certificado sozinho, redireciona `http://` para `https://` e repassa o WebSocket sem configuração extra.
  - `request_body max_size 64KB` reforça no proxy o teto que o servidor já aplica (B3, OV-16, OV-18).
  - **HSTS** é do proxy (B11): o servidor não o envia.
  - **Tempo total de conexão lenta** (*slowloris*, B13): o servidor limita cada leitura a 30 s, mas não o tempo total; configurar os tempos de leitura de cabeçalho/corpo do proxy (opção `servers { timeouts { read_header … read_body … } }` do Caddy).
- [ ] O Caddy acrescenta o IP do visitante ao fim de `X-Forwarded-For`; o servidor só confia nesse cabeçalho com `--trust-proxy` **e** conexão vinda de `127.0.0.1` (B8, OV-06c). Não colocar outro proxy na frente sem rever isso.
- [ ] Conferir: `curl -I https://<domínio>/online.html` mostra 200, `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff` e `Referrer-Policy: no-referrer` (MV-P06).
- [ ] Conferir: `http://<domínio>` redireciona para `https://` (MV-P02); certificado válido no navegador (MV-P01).

## 5. Servidor no modo público

- [ ] Linha de comando:
  ```
  TicTacToeServer.exe --public --allowed-origin https://jogo.exemplo.com.br --trust-proxy
  ```
  - `--public` escuta só em `127.0.0.1`, exige pelo menos uma origem `https`, recusa canal sem `Origin`, desativa `/api/game*` (404) e leva `/` a `/online.html`.
  - **Origens permitidas:** só o(s) domínio(s) `https` exatos do site (sem barra no fim, sem caminho). Incluir `https://www.<domínio>` apenas se esse endereço também for servido. Nunca `http://`.
  - **`--trust-proxy` é obrigatório atrás do Caddy:** sem ele, todos os visitantes contam como um único cliente (`127.0.0.1`) e os limites por cliente passam a valer para todos juntos.
- [ ] Iniciar pelo **Agendador de Tarefas** ("ao iniciar o sistema", reiniciar em caso de falha), com a saída redirecionada para um arquivo de log com data.
- [ ] Conferir no console/log, ao iniciar, a linha "Modo --public" e a linha "Limites:" com os valores em vigor.
- [ ] Conferir: `/api/game` responde 404 pelo domínio (MV-P05); `/health` responde 200.

## 6. Limites por cliente (padrões do modo público, B14)

| Opção | Padrão no público | Quando ajustar |
|---|---|---|
| `--rate-create` | 10 criações de sala por minuto por cliente | Escola/evento atrás de um único IP (NAT): aumentar |
| `--rate-join` | 30 consultas/entradas por minuto | Idem |
| `--rate-ws` | 30 aberturas de canal por minuto | Redes móveis instáveis (muitas reconexões): aumentar com cautela |
| `--ws-per-client` | 8 canais simultâneos por cliente | NAT com muitos jogadores: aumentar |
| `--ws-msg-rate` | 30 mensagens por canal a cada 10 s | Raramente |
| `--max-connections` | 256 conexões simultâneas (503 acima) | Conforme a memória da máquina |
| `--max-rooms` | 500 salas abertas (503 acima) | Conforme a memória da máquina |
| `--http-timeout-seconds` | 30 s por leitura | Manter; o tempo total fica no proxy |

- [ ] Registrar os valores escolhidos no `delivery-log` da O8.
- [ ] Conferir com um teste curto pelo domínio que uma rajada de criações acima do limite recebe 429 com `Retry-After` (como no OV-06a), sem afetar outra sala.

## 7. Firewall e rede

- [ ] Liberar **somente 80 e 443** (TCP) para o Caddy, no perfil de rede em uso.
- [ ] A porta **8765 nunca** é exposta: o `--public` já escuta só em `127.0.0.1`; **não** redirecionar a 8765 no roteador.
- [ ] Hoje (20/10, inventário da O7) o firewall do Windows deste computador está **desligado** nos perfis Privado e Público, e a rede cabeada está marcada como **Pública**. Antes da O8 neste computador: ligar o firewall e classificar a rede conforme o uso.
- [ ] Conferir de fora (celular no 4G): `https://<domínio>` abre; `http://<IP público>:8765` **não** responde (MV-P07).

## 8. Validação antes de abrir ao público (MV-P, `docs/test-plan-online.md` 13.5)

- [ ] MV-P01 a MV-P08 executados e registrados com data, aparelhos e resultado real.
- [ ] Partida completa entre um celular em rede móvel e um computador em outra rede (MV-P04); o canal usa `wss://` (MV-P03).
- [ ] Reinício do servidor com partida aberta leva os dois à mensagem de servidor indisponível (MV-P08).
- [ ] Varredura dos logs das primeiras horas: nenhum token, nenhum 5xx, nenhuma exceção.

## 9. Procedimento de volta atrás (rollback)

Antes de publicar:
- [ ] Guardar a versão em produção numa pasta própria (por exemplo, `C:\jogo\releases\<data>\` com `TicTacToeServer.exe` e `web\`), com o SHA-256 do executável anotado (o da O7 está no `delivery-log`).
- [ ] Guardar o Caddyfile anterior.

Para tirar do ar rapidamente (incidente):
1. Parar a tarefa do servidor no Agendador (ou Ctrl+C no console): os canais recebem 1001 e as salas se encerram.
2. Parar o Caddy (ou trocar o site por uma página estática de manutenção).
3. Se a hospedagem for este computador: remover o redirecionamento das portas 80/443 no roteador.

Para voltar à versão anterior:
1. Parar a tarefa do servidor.
2. Trocar a pasta pela versão guardada (conferir o SHA-256).
3. Iniciar a tarefa e conferir `/health`, a linha "Limites:" e uma partida curta.
4. Registrar no `delivery-log` o motivo, o horário e o resultado.

Observação: o servidor não guarda estado em disco (as salas vivem na memória), então voltar de versão não exige migração de dados; todas as salas abertas se perdem no reinício.

## 10. Operação

- [ ] Monitorar `/health` de fora (a cada poucos minutos) e o espaço em disco dos logs.
- [ ] Revisar semanalmente os logs: recusas por limite (429/503) frequentes indicam limite apertado ou abuso.
- [ ] Atualizar o Windows e o Caddy fora do horário de uso; um reinício encerra todas as salas.

## 11. Limitações conhecidas que continuam valendo na internet

- Janelas de taxa fixas (não deslizantes): na virada da janela, um cliente pode fazer até 2× o limite em pouco tempo.
- Clientes atrás do mesmo IP público dividem os limites por cliente.
- O tempo total de conexões lentas depende do proxy (seção 4).
- A interface no navegador em modo público (HTTPS de verdade) só é testada na O8 (MV-P).
