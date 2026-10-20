import { test, expect } from '../../support/online/fixtures';
import { coherenceProblem } from '../../support/api';
import { INITIAL_GAME, Room } from '../../support/online/rooms';
import { S_EMP, S_EMP_FINAL, S_L1, WINS } from '../../support/sequences';

/* Grupo OR: partidas completas, isolamento, nova partida, sala cheia e saída. */

test('OR-09 [CAO-13, CAO-18] as 11 sequências de referência, cada uma numa sala, alternando os tokens', async ({ rooms }) => {
  const cases = [...WINS.map((w) => ({ id: w.id, moves: w.moves, final: w.final })), { id: 'S-EMP', moves: S_EMP, final: S_EMP_FINAL }];
  expect(cases.length).toBe(11);
  for (const c of cases) {
    const pair = await rooms.pair();
    const last = await rooms.playSequence(pair, c.moves);
    expect(last.partida, `${c.id}: resultado igual ao do modo local`).toEqual(c.final);
    expect(coherenceProblem(last.partida), `${c.id}: coerência`).toBeNull();
    const filled = last.partida.tabuleiro.filter((x) => x !== '').length;
    expect(filled, `${c.id}: jogadas aceitas = células preenchidas`).toBe(c.moves.length);
    expect(last.versao, `${c.id}: uma versão por jogada`).toBe(pair.room.versao + c.moves.length);
    expect(last.situacao, `${c.id}: a sala continua em jogo`).toBe('EM_JOGO');
  }
});

test('OR-10 [CAO-09, CAO-44] partida completa em S1 não muda S2 nem a partida local', async ({ rooms, request }) => {
  const localBefore = await (await request.get('/api/game')).text();
  const s2 = await rooms.pair();
  await rooms.moveOk(s2.code, s2.tx, 0);
  await rooms.moveOk(s2.code, s2.to, 4);
  const s2Before = await rooms.snapshotText(s2.code);

  const s1 = await rooms.pair();
  const end = await rooms.playSequence(s1, S_L1);
  expect(end.partida.status).toBe('VITORIA');

  expect(await rooms.snapshotText(s2.code), 'S2 inalterada').toBe(s2Before);
  expect(await (await request.get('/api/game')).text(), 'partida local inalterada').toBe(localBefore);
});

test('OR-11 [CAO-39] nova partida após vitória (pedida por O) e após empate (por X)', async ({ rooms }) => {
  for (const [label, moves, who] of [['vitória', S_L1, 'O'], ['empate', S_EMP, 'X']] as const) {
    const pair = await rooms.pair();
    const end = await rooms.playSequence(pair, [...moves]);
    const res = await rooms.reset(pair.code, who === 'O' ? pair.to : pair.tx);
    expect(res.status(), `${label}: ${await res.text()}`).toBe(200);
    const room = ((await res.json()) as { sala: Room }).sala;
    expect(room.partida, `${label}: estado inicial, X começa`).toEqual(INITIAL_GAME);
    expect(room.numeroDaPartida, `${label}: número da partida +1`).toBe(end.numeroDaPartida + 1);
    expect(room.jogadores, `${label}: lugares iguais`).toEqual(end.jogadores);
    expect(room.situacao).toBe('EM_JOGO');
    expect(room.versao, `${label}: versão +1`).toBe(end.versao + 1);
    expect(await rooms.room(pair.code), `${label}: resposta = GET`).toEqual(room);
    // A nova partida é jogável, com os mesmos tokens.
    const next = await rooms.moveOk(pair.code, pair.tx, 4);
    expect(next.partida.tabuleiro[4]).toBe('X');
  }
});

test('OR-12 [CAO-40] nova partida no meio do jogo ou sem oponente: 409, sala inalterada', async ({ rooms }) => {
  const pair = await rooms.pair();
  await rooms.moveOk(pair.code, pair.tx, 0);
  for (const [mark, token] of [['X', pair.tx], ['O', pair.to]] as const) {
    const res = await rooms.expectUnchanged(pair.code, `nova partida por ${mark}`, () => rooms.reset(pair.code, token));
    await rooms.expectError(res, 409, 'PARTIDA_EM_ANDAMENTO', `nova partida por ${mark} em andamento`);
  }
  const waiting = await rooms.create();
  const res = await rooms.expectUnchanged(waiting.code, 'nova partida sem O', () => rooms.reset(waiting.code, waiting.token));
  await rooms.expectError(res, 409, 'AGUARDANDO_OPONENTE', 'nova partida sem O');
});

test('OR-13 [CAO-41] nova partida em S1 não muda S2', async ({ rooms }) => {
  const s1 = await rooms.pair();
  await rooms.playSequence(s1, S_L1);
  const s2 = await rooms.pair();
  await rooms.moveOk(s2.code, s2.tx, 0);
  await rooms.moveOk(s2.code, s2.to, 4);
  const before = await rooms.snapshotText(s2.code);
  expect((await rooms.reset(s1.code, s1.tx)).status()).toBe(200);
  expect(await rooms.snapshotText(s2.code), 'S2 inalterada').toBe(before);
});

test('OR-14 [CAO-29] terceiro cliente numa sala cheia: 409 SALA_CHEIA, sala inalterada', async ({ rooms }) => {
  const pair = await rooms.pair();
  for (const [label, token] of [['sem token', undefined], ['com token desconhecido', 'abcdefabcdefabcdefabcdefabcdefab']] as const) {
    const res = await rooms.expectUnchanged(pair.code, `terceiro ${label}`, () => rooms.join(pair.code, token));
    await rooms.expectError(res, 409, 'SALA_CHEIA', `terceiro ${label}`);
  }
});

test('OR-15 [CAO-31] O sai: sala ENCERRADA (SAIDA); toda operação seguinte 410', async ({ rooms }) => {
  const pair = await rooms.pair();
  await rooms.moveOk(pair.code, pair.tx, 0);
  const res = await rooms.leave(pair.code, pair.to);
  expect(res.status(), await res.text()).toBe(200);
  const room = ((await res.json()) as { sala: Room }).sala;
  expect(room.situacao).toBe('ENCERRADA');
  expect(room.motivoEncerramento).toBe('SAIDA');
  expect(room.partida.tabuleiro[0], 'o tabuleiro é mantido no estado final').toBe('X');

  const after: Array<[string, () => ReturnType<typeof rooms.get>]> = [
    ['GET', () => rooms.get(pair.code)],
    ['entrar sem token', () => rooms.join(pair.code)],
    ['entrar com o token de O', () => rooms.join(pair.code, pair.to)],
    ['jogar com o token de O', () => rooms.move(pair.code, pair.to, 4)],
    ['jogar sem token', () => rooms.move(pair.code, undefined, 4)],
    ['nova partida com o token de X', () => rooms.reset(pair.code, pair.tx)],
    ['nova partida sem token', () => rooms.reset(pair.code)],
    ['sair com o token de X', () => rooms.leave(pair.code, pair.tx)],
    ['sair sem token', () => rooms.leave(pair.code)],
  ];
  for (const [label, action] of after) {
    await rooms.expectError(await action(), 410, 'SALA_ENCERRADA', label);
  }
});
