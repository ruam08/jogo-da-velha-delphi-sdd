import { test, expect } from '../../support/online/ui-fixtures';
import { CODE_RE, ONLINE_MESSAGES, TOKEN_RE } from '../../support/online/rooms';
import { ONLINE_TEXT, STORAGE_PREFIX, STORAGE_TTL_MS, youAre } from '../../support/online/online-ui';

/*
 * Grupo OU (docs/test-plan-online.md, seção 9): criar, compartilhar e entrar.
 * Cada jogador é um contexto isolado do Chromium (outro "navegador"), contra o
 * servidor real da suíte. Os controles do fim de cada teste (verificação
 * cruzada, OU-24 e problemas no navegador) ficam na fixture `players`.
 */

test('OU-01 [CAO-01, CAO-03] criar sala: código, link, URL, aguardando, conectado e células inativas', async ({ players, baseURL }) => {
  const a = await players.open('A');
  await a.open();
  await a.expectState('inicio');
  await expect(a.createRoom).toBeVisible();
  await expect(a.codeInput).toBeVisible();
  await expect(a.joinRoom).toBeVisible();

  const code = await a.create();
  expect(code).toMatch(CODE_RE);
  const link = `${baseURL}/online.html?sala=${code}`;
  await expect(a.roomCode).toHaveText(code);
  await expect(a.roomLink).toHaveText(link);
  expect(a.page.url(), 'a URL da página passa a ser o link da sala').toBe(link);
  await expect(a.status).toHaveText(ONLINE_TEXT.waiting);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentMissing);
  await expect(a.connection).toHaveText(ONLINE_TEXT.connected);
  await expect(a.youAre).toHaveText(youAre('X'));
  await expect(a.gameNumber).toHaveText('Partida 1');
  await a.expectCellsDisabled(true);
  expect(await a.storedToken(code), 'token guardado no navegador').toMatch(TOKEN_RE);
  const room = await players.rooms.room(code);
  expect(room.jogadores.X.conectado, 'X conectado pelo canal').toBe(true);
});

test('OU-02 [CAO-03] copiar link: área de transferência e "Link copiado."', async ({ players, baseURL }) => {
  const a = await players.open('A', { permissions: ['clipboard-read', 'clipboard-write'] });
  await a.open();
  const code = await a.create();
  await expect(a.copyFeedback).toBeHidden();
  await a.copyLink.click();
  await expect(a.copyFeedback).toHaveText(ONLINE_TEXT.copied);
  const clip = await a.page.evaluate(() => navigator.clipboard.readText());
  expect(clip).toBe(`${baseURL}/online.html?sala=${code}`);
});

test('OU-03 [CAO-03, CAO-05] entrar pelo link: "Entrar na sala" e B joga com O', async ({ players }) => {
  const { a, b, link } = await players.pair();
  expect(b.page.url(), 'B continua no link, sem token na URL').toBe(link);
  await expect(b.youAre).toHaveText(youAre('O'));
  await expect(b.status).toHaveText(ONLINE_TEXT.opponentTurn);
  await expect(a.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  await expect(b.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
  await expect(b.joinThisRoom).toBeHidden();
});

test('OU-04 [CAO-05] entrar digitando o código em minúsculas e com espaços', async ({ players }) => {
  const a = await players.open('A');
  await a.open();
  const code = await a.create();
  const c = await players.open('C');
  await c.open();
  const res = await c.joinByCode(`  ${code.toLowerCase()} `, code);
  expect(res.status()).toBe(201);
  expect(new URL(res.url()).pathname, 'o código vai ao servidor sem espaços e em maiúsculas').toBe(`/api/rooms/${code}/players`);
  await c.expectState('jogando');
  await c.expectConnection('conectado');
  await expect(c.youAre).toHaveText(youAre('O'));
  await expect(c.roomCode).toHaveText(code);
  await expect(a.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(a.opponent).toHaveText(ONLINE_TEXT.opponentOnline);
});

test('OU-05 [CAO-08] cada um sabe quem é; o status inverte depois da jogada', async ({ players }) => {
  const { a, b } = await players.pair();
  await expect(a.youAre).toHaveText(youAre('X'));
  await expect(b.youAre).toHaveText(youAre('O'));
  await expect(a.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(b.status).toHaveText(ONLINE_TEXT.opponentTurn);
  await a.expectCellsDisabled(false);
  await b.expectCellsDisabled(true);
  expect((await a.click(0)).status()).toBe(200);
  await expect(a.status).toHaveText(ONLINE_TEXT.opponentTurn);
  await expect(b.status).toHaveText(ONLINE_TEXT.yourTurn);
  await expect(b.cell(1)).not.toHaveAttribute('aria-disabled', 'true');
});

test('OU-12 [CAO-29] sala cheia: terceiro navegador vê a mensagem e "Criar nova sala"', async ({ players }) => {
  const { code, link } = await players.pair();
  const before = await players.rooms.snapshotText(code);
  const c = await players.open('C');
  await c.openLink(link);
  await c.expectState('cheia');
  await expect(c.error).toHaveText(ONLINE_MESSAGES.SALA_CHEIA);
  await expect(c.createNewRoom).toBeVisible();
  await expect(c.joinThisRoom).toBeHidden();
  expect(await c.storedToken(code), 'C não tem lugar').toBeNull();
  expect(await players.rooms.snapshotText(code), 'a sala não muda').toBe(before);
});

test('OU-13 [CAO-30] sala inexistente: pelo link e digitando o código', async ({ players }) => {
  const c = await players.open('C');
  await c.open('/online.html?sala=ZZZZZZ');
  await c.expectState('inexistente');
  await expect(c.error).toHaveText(ONLINE_MESSAGES.SALA_INEXISTENTE);
  await expect(c.createNewRoom).toBeVisible();

  const d = await players.open('D');
  await d.open();
  const res = await d.joinByCode('zzzzzz');
  expect(res.status()).toBe(404);
  await expect(d.error).toHaveText(ONLINE_MESSAGES.SALA_INEXISTENTE);
  await d.expectState('inicio');

  // Código vazio: aviso local, sem requisição.
  await d.codeInput.fill('   ');
  let posted = false;
  d.page.on('request', (r) => { if (r.method() === 'POST') posted = true; });
  await d.joinRoom.click();
  await expect(d.error).toHaveText(ONLINE_TEXT.emptyCode);
  expect(posted, 'código vazio não vai ao servidor').toBe(false);
});

test('OU-25 [CAO-20] token guardado inválido: o servidor recusa, o token é apagado e a sala não muda', async ({ players }) => {
  const a = await players.open('A');
  await a.open();
  const code = await a.create();
  const before = await players.rooms.snapshotText(code);

  const c = await players.open('C');
  await c.open();
  await c.page.evaluate(([key, code]) => {
    localStorage.setItem(key, JSON.stringify({ codigo: code, simbolo: 'O', token: '0123456789abcdef0123456789abcdef', salvoEm: Date.now() }));
  }, [STORAGE_PREFIX + code, code]);
  await c.openLink(`/online.html?sala=${code}`);
  await c.expectState('negado');
  await expect(c.error).toHaveText(ONLINE_MESSAGES.TOKEN_INVALIDO);
  await c.expectConnection('parado');
  await expect(c.createNewRoom).toBeVisible();
  expect(await c.storedToken(code), 'token inválido apagado do navegador').toBeNull();
  expect(await players.rooms.snapshotText(code), 'a sala não muda').toBe(before);
  // Sem reconexão em laço: uma única abertura de canal.
  const opens = c.wsOpens.length;
  await c.page.waitForTimeout(3000);
  expect(c.wsOpens.length, 'nenhuma nova abertura de canal').toBe(opens);
  expect(opens).toBe(1);
});

test('OU-26 [CAO-35] token guardado há mais de 24 h é descartado sem ir ao servidor', async ({ players }) => {
  const { b, code } = await players.pair();
  const token = await b.storedToken(code);
  expect(token).toMatch(/^[0-9a-f]{32}$/);
  // Envelhece a entrada de B além da validade (24 h desde o último uso) e recarrega.
  await b.page.evaluate(([key, ttl]) => {
    const entry = JSON.parse(localStorage.getItem(key as string)!);
    entry.salvoEm = Date.now() - (ttl as number) - 60_000;
    localStorage.setItem(key as string, JSON.stringify(entry));
  }, [STORAGE_PREFIX + code, STORAGE_TTL_MS]);
  const opens = b.wsOpens.length;
  await b.page.reload();
  // Sem token válido, a página consulta a sala: ela tem dois lugares ocupados.
  await b.expectState('cheia');
  await expect(b.error).toHaveText(ONLINE_MESSAGES.SALA_CHEIA);
  expect(await b.storedToken(code), 'entrada vencida apagada').toBeNull();
  expect(b.wsOpens.length, 'o token vencido não foi enviado pelo canal').toBe(opens);
  b.code = '';
});
