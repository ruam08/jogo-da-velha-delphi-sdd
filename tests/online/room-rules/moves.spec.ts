import { test, expect } from '../../support/online/fixtures';
import { Room, bearer } from '../../support/online/rooms';
import { S_EMP, S_L1 } from '../../support/sequences';

/*
 * Grupo OR: regras aplicadas pelo servidor em execução, só por HTTP
 * (test-plan-online, seção 3, item 1). Toda recusa deixa a sala idêntica,
 * versão incluída.
 */

test('OR-01 [CAO-07] o símbolo vem do token: campos do corpo não escolhem o jogador', async ({ rooms }) => {
  const pair = await rooms.pair();
  const res1 = await rooms.moveRaw(pair.code, bearer(pair.tx), '{"posicao":0,"simbolo":"O","jogador":"O"}');
  expect(res1.status(), await res1.text()).toBe(200);
  const after1 = ((await res1.json()) as { sala: Room }).sala;
  expect(after1.partida.tabuleiro[0], 'célula 0').toBe('X');
  expect(after1.partida.jogadorDaVez).toBe('O');
  expect(after1.versao, 'versão +1').toBe(pair.room.versao + 1);
  expect(await rooms.room(pair.code), 'resposta = GET').toEqual(after1);

  const res2 = await rooms.moveRaw(pair.code, bearer(pair.to), '{"posicao":4,"simbolo":"X","jogador":"X"}');
  expect(res2.status(), await res2.text()).toBe(200);
  const after2 = ((await res2.json()) as { sala: Room }).sala;
  expect(after2.partida.tabuleiro[4], 'célula 4').toBe('O');
  expect(after2.partida.jogadorDaVez).toBe('X');
  expect(after2.versao, 'versão +1').toBe(after1.versao + 1);
  expect(await rooms.room(pair.code), 'resposta = GET').toEqual(after2);
});

test('OR-02 [CAO-16] jogada fora da vez: 409 VEZ_DO_OPONENTE, sala inalterada', async ({ rooms }) => {
  const pair = await rooms.pair();
  const res = await rooms.expectUnchanged(pair.code, 'O na vez de X', () => rooms.move(pair.code, pair.to, 4));
  await rooms.expectError(res, 409, 'VEZ_DO_OPONENTE', 'O na vez de X');
  await rooms.moveOk(pair.code, pair.tx, 0);
  const res2 = await rooms.expectUnchanged(pair.code, 'X na vez de O', () => rooms.move(pair.code, pair.tx, 4));
  await rooms.expectError(res2, 409, 'VEZ_DO_OPONENTE', 'X na vez de O');
});

test('OR-03 [CAO-17] célula ocupada: 409 CELULA_OCUPADA, sala inalterada', async ({ rooms }) => {
  const pair = await rooms.pair();
  await rooms.moveOk(pair.code, pair.tx, 0);
  const res = await rooms.expectUnchanged(pair.code, 'O na célula 0', () => rooms.move(pair.code, pair.to, 0));
  await rooms.expectError(res, 409, 'CELULA_OCUPADA', 'O na célula 0');
});

test('OR-04 [CAO-18] partida encerrada (vitória e empate): 409 PARTIDA_ENCERRADA para X e O', async ({ rooms }) => {
  for (const [label, moves, tries] of [
    ['S-L1', S_L1, [5, 0, 8, 3]],
    ['S-EMP', S_EMP, [0, 4]],
  ] as const) {
    const pair = await rooms.pair();
    await rooms.playSequence(pair, [...moves]);
    for (const position of tries) {
      for (const [mark, token] of [['X', pair.tx], ['O', pair.to]] as const) {
        const what = `${label}: ${mark} na posição ${position}`;
        const res = await rooms.expectUnchanged(pair.code, what, () => rooms.move(pair.code, token, position));
        await rooms.expectError(res, 409, 'PARTIDA_ENCERRADA', what);
      }
    }
  }
});

test('OR-05 [CAO-19] sem oponente: 409 AGUARDANDO_OPONENTE, sala inalterada', async ({ rooms }) => {
  const created = await rooms.create();
  const res = await rooms.expectUnchanged(created.code, 'X sem O', () => rooms.move(created.code, created.token, 0));
  await rooms.expectError(res, 409, 'AGUARDANDO_OPONENTE', 'X sem O');
});

test('OR-06 [CAO-11, CAO-20] token ausente, malformado, de outra sala ou na URL: 401 TOKEN_INVALIDO', async ({ rooms }) => {
  const s1 = await rooms.pair();
  const s2 = await rooms.pair();
  const cases: Array<[string, Record<string, string>]> = [
    ['sem Authorization', {}],
    ['Basic', { Authorization: 'Basic dXN1YXJpbzpzZW5oYQ==' }],
    ['Basic com o token', { Authorization: `Basic ${s1.tx}` }],
    ['token sem esquema', { Authorization: s1.tx }],
    ['31 hex', { Authorization: `Bearer ${s1.tx.slice(0, 31)}` }],
    ['33 hex', { Authorization: `Bearer ${s1.tx}0` }],
    ['hex em maiúsculas', { Authorization: `Bearer ${s1.tx.toUpperCase()}` }],
    ['dois espaços', { Authorization: `Bearer  ${s1.tx}` }],
    ['token inexistente', bearer('0123456789abcdef0123456789abcdef')],
    ['token de X da sala S2', bearer(s2.tx)],
    ['token de O da sala S2', bearer(s2.to)],
  ];
  for (const [label, headers] of cases) {
    const before2 = await rooms.snapshotText(s2.code);
    const res = await rooms.expectUnchanged(s1.code, label,
      () => rooms.moveRaw(s1.code, headers, '{"posicao":0}'));
    await rooms.expectError(res, 401, 'TOKEN_INVALIDO', label);
    expect(await rooms.snapshotText(s2.code), `${label}: S2 inalterada`).toBe(before2);
  }
  // O token na URL (query) nunca autentica (DTO-07).
  const inQuery = await rooms.expectUnchanged(s1.code, 'token na query', () =>
    rooms.request.post(`/api/rooms/${s1.code}/moves?token=${s1.tx}`, { data: { posicao: 0 } }));
  await rooms.expectError(inQuery, 401, 'TOKEN_INVALIDO', 'token na query');
  // Nova partida e saída também exigem o token.
  await rooms.expectError(await rooms.reset(s1.code, s2.tx), 401, 'TOKEN_INVALIDO', 'reset com token de S2');
  await rooms.expectError(await rooms.leave(s1.code, s2.tx), 401, 'TOKEN_INVALIDO', 'leave com token de S2');
  await rooms.expectError(await rooms.leave(s1.code), 401, 'TOKEN_INVALIDO', 'leave sem token');
  // Com o token certo (esquema em minúsculas), a jogada é aceita.
  const ok = await rooms.moveRaw(s1.code, { Authorization: `bearer ${s1.tx}` }, '{"posicao":0}');
  expect(ok.status(), await ok.text()).toBe(200);
});

test('OR-07 [CAO-21] corpos e posições inválidos: 400, sala inalterada', async ({ rooms }) => {
  const pair = await rooms.pair();
  const cases: Array<[string, string | undefined, 'CORPO_INVALIDO' | 'POSICAO_INVALIDA']> = [
    ['sem corpo', undefined, 'CORPO_INVALIDO'],
    ['corpo vazio', '', 'CORPO_INVALIDO'],
    ['abc', 'abc', 'CORPO_INVALIDO'],
    ['[4]', '[4]', 'CORPO_INVALIDO'],
    ['4', '4', 'CORPO_INVALIDO'],
    ['JSON incompleto', '{"posicao":', 'CORPO_INVALIDO'],
    ['posição 9', '{"posicao":9}', 'POSICAO_INVALIDA'],
    ['posição -1', '{"posicao":-1}', 'POSICAO_INVALIDA'],
    ['posição 4.5', '{"posicao":4.5}', 'POSICAO_INVALIDA'],
    ['posição "4"', '{"posicao":"4"}', 'POSICAO_INVALIDA'],
    ['posição null', '{"posicao":null}', 'POSICAO_INVALIDA'],
    ['posição true', '{"posicao":true}', 'POSICAO_INVALIDA'],
    ['campo ausente', '{}', 'POSICAO_INVALIDA'],
    ['nome com maiúscula', '{"Posicao":4}', 'POSICAO_INVALIDA'],
  ];
  for (const [label, body, code] of cases) {
    const res = await rooms.expectUnchanged(pair.code, label, () => rooms.moveRaw(pair.code, bearer(pair.tx), body));
    await rooms.expectError(res, 400, code, label);
  }
});

test('OR-08 [CAO-22] precedência dos erros (tabela P-01 a P-09 e passos de HTTP)', async ({ rooms }) => {
  const badToken = bearer('ffffffffffffffffffffffffffffffff');

  // P-01: sala encerrada, token inválido, posição 9 -> 410
  const closed = await rooms.pair();
  expect((await rooms.leave(closed.code, closed.to)).status()).toBe(200);
  await rooms.expectError(await rooms.moveRaw(closed.code, badToken, '{"posicao":9}'), 410, 'SALA_ENCERRADA', 'P-01');
  await rooms.expectError(await rooms.moveRaw(closed.code, {}, 'abc'), 410, 'SALA_ENCERRADA', 'P-01b encerrada, sem token, corpo inválido');

  // P-02: em jogo, token inválido, posição 9 -> 401
  const playing = await rooms.pair();
  await rooms.expectError(await rooms.moveRaw(playing.code, badToken, '{"posicao":9}'), 401, 'TOKEN_INVALIDO', 'P-02');
  await rooms.expectError(await rooms.moveRaw(playing.code, badToken, 'abc'), 401, 'TOKEN_INVALIDO', 'P-02b token inválido e corpo inválido');
  // P-03: em jogo, token de X, corpo abc -> 400 CORPO_INVALIDO
  await rooms.expectError(await rooms.moveRaw(playing.code, bearer(playing.tx), 'abc'), 400, 'CORPO_INVALIDO', 'P-03');
  await rooms.expectError(await rooms.moveRaw(playing.code, bearer(playing.to), 'abc'), 400, 'CORPO_INVALIDO', 'P-03b corpo inválido fora da vez');

  // P-04 e P-05: aguardando oponente
  const waiting = await rooms.create();
  await rooms.expectError(await rooms.moveRaw(waiting.code, bearer(waiting.token), '{"posicao":9}'), 400, 'POSICAO_INVALIDA', 'P-04');
  await rooms.expectError(await rooms.moveRaw(waiting.code, bearer(waiting.token), '{"posicao":0}'), 409, 'AGUARDANDO_OPONENTE', 'P-05');

  // P-06 e P-07: vitória de X
  const won = await rooms.pair();
  await rooms.playSequence(won, S_L1);
  await rooms.expectError(await rooms.moveRaw(won.code, bearer(won.tx), '{"posicao":0}'), 409, 'PARTIDA_ENCERRADA', 'P-06');
  await rooms.expectError(await rooms.moveRaw(won.code, bearer(won.to), '{"posicao":9}'), 400, 'POSICAO_INVALIDA', 'P-07');

  // P-08 e P-09: X:0, vez de O
  const turn = await rooms.pair();
  await rooms.moveOk(turn.code, turn.tx, 0);
  await rooms.expectError(await rooms.moveRaw(turn.code, bearer(turn.tx), '{"posicao":0}'), 409, 'VEZ_DO_OPONENTE', 'P-08');
  await rooms.expectError(await rooms.moveRaw(turn.code, bearer(turn.to), '{"posicao":0}'), 409, 'CELULA_OCUPADA', 'P-09');

  // Nenhuma das recusas acima mudou as salas.
  expect((await rooms.room(turn.code)).versao, 'sala P-08/P-09: só a jogada de X').toBe(turn.room.versao + 1);
  expect((await rooms.room(playing.code)).versao, 'sala P-02/P-03 inalterada').toBe(playing.room.versao);
});
