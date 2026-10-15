# Jogo da Velha — Delphi Berlin + Web

Projeto de estudo de **Spec-Driven Development (SDD)**: um Jogo da Velha para dois jogadores locais, com servidor HTTP em Delphi 10.1 Berlin (Indy) controlando as regras, interface em HTML/CSS/JS e testes end-to-end com Playwright + TypeScript.

| Documento | Conteúdo |
|---|---|
| [`docs/spec.md`](docs/spec.md) | Especificação: regras, critérios de aceitação, requisitos |
| [`docs/plan.md`](docs/plan.md) | Plano técnico: arquitetura, contrato HTTP, entregas |
| [`docs/test-plan.md`](docs/test-plan.md) | Plano de testes: cenários e critérios de aprovação |
| [`docs/delivery-log.md`](docs/delivery-log.md) | Registro de cada entrega: comandos, resultados e limitações |

## Estado atual

- **Entrega 1 — Estrutura do servidor e `GET /health`:** concluída.
- **Entrega 2 — Motor do jogo (`uGameEngine`) e testes unitários (`EngineCheck`):** concluída.
- **Entrega 3 — Serviço de jogo (`uGameService`) e API HTTP:** concluída.
- **Entrega 4 — Testes da API com Playwright + TypeScript:** concluída.
- **Entrega 5 — Interface web e testes E2E no Chromium:** validada (109/109 testes), aguardando aprovação.
- Próximas: Entrega 6 (documentação final) e Entrega 7 (validação final).

![Partida encerrada com vitória de X](docs/screenshots/ui-desktop-vitoria.png)

## Como este projeto foi feito com SDD

Nenhuma linha de código foi escrita antes de existir uma especificação aprovada. O ciclo foi:

1. **Especificação** ([`docs/spec.md`](docs/spec.md)): regras numeradas (RN), comportamentos de interface (CI), critérios de aceitação objetivos (CA), requisitos não funcionais (RNF) e dúvidas registradas (D). Toda mudança de requisito entra no histórico de versões do documento.
2. **Plano técnico** ([`docs/plan.md`](docs/plan.md)): decisões técnicas numeradas (DT), contrato HTTP exato e a divisão em entregas pequenas.
3. **Plano de testes** ([`docs/test-plan.md`](docs/test-plan.md)): cada CA ligado a testes em uma matriz de rastreabilidade, por camada (motor, serviço, API, interface).
4. **Implementação por entrega**, uma de cada vez e com aprovação humana entre elas:
   - **fase vermelha**: os testes são escritos e executados *antes* do código, e precisam falhar;
   - **fase verde**: implementação até os testes passarem;
   - **sabotagem** (SB-01 a SB-06): defeitos são inseridos de propósito em cópias do código, e os testes precisam detectá-los — prova de que não passam por acaso.
5. **Validação real**: um script por entrega (`scripts\validate-stepN.cmd`) compila, executa e registra tudo em log. Nenhum resultado é declarado sem execução; os números e os defeitos encontrados estão em [`docs/delivery-log.md`](docs/delivery-log.md).

Princípio central: **toda regra de negócio vive no backend Delphi**. O JavaScript só exibe o estado que o servidor devolve, e a SB-06 prova que a interface não decide nada sozinha.

## Requisitos

- Windows (Win32).
- Delphi 10.1 Berlin, edição Professional ou superior (a Starter não tem o compilador de linha de comando `dcc32`).
- Windows PowerShell 5.1 e `curl.exe` (já vêm no Windows 10/11), apenas para os scripts de validação.
- Node.js 22, 24 ou 26 para os testes Playwright (testado com 24.11.1). Nada é instalado globalmente: as dependências ficam em `tests\node_modules`.

## Compilar

### Linha de comando

```bat
scripts\build.cmd
```

O script carrega `rsvars.bat` de `C:\Program Files (x86)\Embarcadero\Studio\18.0\bin`. Se o Delphi estiver em outro lugar:

```bat
set "DELPHI_RSVARS=D:\Caminho\Para\Studio\18.0\bin\rsvars.bat"
scripts\build.cmd
```

Saída: `server\bin\TicTacToeServer.exe` e `server\bin\EngineCheck.exe`.

### IDE

1. *File > Open Project* e escolha `server\TicTacToeServer.dpr` (a IDE cria o `.dproj`).
2. Em *Project > Options > Delphi Compiler*, defina *Output directory* = `bin` e *Unit output directory* = `dcu`.
3. Plataforma Win32, *Build*.

## Executar

```bat
server\bin\TicTacToeServer.exe
server\bin\TicTacToeServer.exe --port 9000
server\bin\TicTacToeServer.exe --www C:\outra\pasta\web
```

- **Jogar:** abra `http://127.0.0.1:8765/` no navegador. A interface (`web\index.html`, `style.css`, `app.js`) é servida pelo próprio servidor, lida do disco a cada requisição (por padrão, a pasta `web` do repositório).

- Endereço: `http://127.0.0.1:8765` (porta padrão 8765). Use sempre `127.0.0.1`, não `localhost`.
- Encerrar: **Ctrl+C** na janela do servidor.
- Se a porta estiver em uso, o servidor avisa e sai com código 1.

Verificação de saúde:

```bat
curl.exe -i http://127.0.0.1:8765/health
```

Resposta esperada:

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Cache-Control: no-store

{"status":"ok"}
```

## API

| Método | Rota | Resposta |
|---|---|---|
| GET | `/api/game` | 200 + estado |
| POST | `/api/game/moves` com `{"posicao": 0-8}` | 200 + estado, 400 ou 409 |
| POST | `/api/game/reset` | 200 + estado inicial |
| GET | `/health` | 200 `{"status":"ok"}` |

Exemplo:

```bat
curl.exe -X POST -H "Content-Type: application/json" -d "{\"posicao\":4}" http://127.0.0.1:8765/api/game/moves
```

Contrato completo (formato do estado, códigos de erro): `docs/plan.md`, seção 3.

## Testes do motor

```bat
server\bin\EngineCheck.exe
```

Executa os casos do motor (M), do serviço (SV, incluindo 8 threads simultâneas) e do JSON (J) do `docs/test-plan.md`, incluindo um teste exaustivo de todas as partidas possíveis. Sai com código 0 se tudo passar e 1 se algum caso falhar.

## Testes Playwright (API e navegador)

Com o servidor compilado (`scripts\build.cmd`):

```bat
cd tests
npm ci
npx playwright test
npx playwright show-report
```

- `npm ci` instala as versões fixadas em `package-lock.json` (Playwright 1.64.1, TypeScript 5.9.3).
- Na primeira vez, instale o navegador (fica no cache do usuário, nada global): `npx playwright install chromium`.
- O Playwright inicia o `server\bin\TicTacToeServer.exe` real na porta 8765, roda os 109 testes (80 do projeto `api`, sem navegador, e 29 do projeto `chromium`) e finaliza o servidor. A porta precisa estar livre.
- Só um projeto: `npx playwright test --project=chromium`.
- Relatório HTML em `tests\playwright-report\index.html`.
- Checagem de tipos: `npm run typecheck`.

## Validar as entregas

```bat
scripts\validate-step5.cmd
```

Compila com o Delphi, roda o `EngineCheck`, instala as dependências e o Chromium, roda a suíte completa duas vezes (servidor iniciado pelo Playwright e por fora, com o log do servidor verificado), cada arquivo sozinho, as sabotagens SB-06 e SB-04, e gera as capturas de `docs\screenshots`. Resultado em `logs\step5-validation.log`.

Validação da Entrega 4:

```bat
scripts\validate-step4.cmd
```

Compila com o Delphi, roda o `EngineCheck`, instala as dependências de `tests\`, roda a suíte Playwright duas vezes e cada arquivo sozinho, e confirma que a suíte falha sem o executável real e contra um servidor sem trava. Resultado em `logs\step4-validation.log`.

Validação da Entrega 3:

```bat
scripts\validate-step3.cmd
```

Compila, roda o `EngineCheck`, inicia o servidor e executa os cenários A e R do plano de testes com requisições HTTP reais (inclusive jogadas simultâneas), além da sabotagem SB-04. Resultado em `logs\step3-validation.log`.

Validação da Entrega 2:

```bat
scripts\validate-step2.cmd
```

Compila, roda o `EngineCheck`, aplica quatro sabotagens em cópias temporárias do motor (para provar que os testes detectam defeitos) e confere a regressão do `/health`. Resultado em `logs\step2-validation.log`.

Validação da Entrega 1:

```bat
scripts\validate-step1.cmd
```

O script compila, inicia o servidor, faz requisições reais (`GET`, `HEAD`, `POST` e `DELETE` em `/health`, além de uma rota inexistente), confere o bind em `127.0.0.1`, finaliza e reinicia o servidor na mesma porta. Tudo fica registrado em `logs\step1-validation.log`, com o resumo `APROVADO` ou `REPROVADO` no final.

**Verificação manual do Ctrl+C** (não automatizada): inicie o servidor numa janela de prompt, pressione Ctrl+C e confira as mensagens `Encerrando o servidor...` e `Servidor encerrado.`; em seguida, inicie de novo e confira que ele sobe na mesma porta.

## Estrutura

```
docs/        especificação, plano técnico, plano de testes, registro de entregas, capturas
server/      TicTacToeServer.dpr, EngineCheck.dpr, units em server/src e testes em server/tests
scripts/     build.cmd, delphi-env.cmd, compile-dpr.cmd e scripts de validação
web/         interface: index.html, style.css, app.js
tests/       testes Playwright + TypeScript (api/, rules/, ui/, support/, tools/)
logs/        saídas das validações (fora do Git)
```
