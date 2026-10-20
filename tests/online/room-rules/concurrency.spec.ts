import { APIResponse } from '@playwright/test';
import { test, expect } from '../../support/online/fixtures';
import { coherenceProblem, describe } from '../../support/api';
import { Pair, Room } from '../../support/online/rooms';

/*
 * Grupo OR: requisições HTTP simultâneas (CAO-23 a CAO-25). As requisições
 * são disparadas juntas com Promise.all contra o servidor real; cada conexão
 * é atendida por uma thread do Indy, e a sala serializa as operações na sua
 * seção crítica. Concorrência pode passar por sorte; por isso há repetições,
 * e a validação da entrega roda estes testes contra servidores sabotados.
 */

async function roomOf(res: APIResponse): Promise<Room> {
  return ((await res.json()) as { sala: Room }).sala;
}

test('OR-16 [CAO-23] duas jogadas simultâneas de X: uma 200 e uma 409 VEZ_DO_OPONENTE (20 repetições)', async ({ rooms }) => {
  for (let rep = 1; rep <= 20; rep++) {
    const pair = await rooms.pair();
    const responses = await Promise.all([rooms.move(pair.code, pair.tx, 0), rooms.move(pair.code, pair.tx, 1)]);
    const codes = responses.map((r) => r.status()).sort();
    expect(codes, `repetição ${rep}: códigos HTTP`).toEqual([200, 409]);
    const conflict = responses.find((r) => r.status() === 409)!;
    expect((await conflict.json()).erro.codigo, `repetição ${rep}: código do 409`).toBe('VEZ_DO_OPONENTE');
    const final = await rooms.room(pair.code);
    const xs = final.partida.tabuleiro.filter((c) => c === 'X').length;
    const os = final.partida.tabuleiro.filter((c) => c === 'O').length;
    expect([xs, os], `repetição ${rep}: um único X (${describe(final.partida)})`).toEqual([1, 0]);
    expect(final.partida.jogadorDaVez, `repetição ${rep}: vez de O`).toBe('O');
    expect(final.versao, `repetição ${rep}: versão +1`).toBe(pair.room.versao + 1);
    await rooms.leave(pair.code, pair.tx);
  }
});

test('OR-17 [CAO-24] X e O jogam ao mesmo tempo na vez de X: X sempre 200; O só é aceito se chegou depois (20 repetições)', async ({ rooms }) => {
  for (let rep = 1; rep <= 20; rep++) {
    const pair = await rooms.pair();
    const [rx, ro] = await Promise.all([rooms.move(pair.code, pair.tx, 0), rooms.move(pair.code, pair.to, 1)]);
    expect(rx.status(), `repetição ${rep}: X (${await rx.text()})`).toBe(200);
    const final = await rooms.room(pair.code);
    const where = `repetição ${rep}, estado final ${describe(final.partida)}`;
    expect(final.partida.tabuleiro[0], `${where}: célula 0`).toBe('X');
    if (ro.status() === 409) {
      // O chegou antes da jogada de X: era a vez de X.
      expect((await ro.json()).erro.codigo, `${where}: código do 409 de O`).toBe('VEZ_DO_OPONENTE');
      expect(final.partida.tabuleiro[1], `${where}: célula 1`).toBe('');
      expect(final.versao, `${where}: versão +1`).toBe(pair.room.versao + 1);
    } else {
      // O chegou depois: a jogada dele era válida e é a única outra mudança.
      expect(ro.status(), `${where}: O (${await ro.text()})`).toBe(200);
      expect(final.partida.tabuleiro[1], `${where}: célula 1`).toBe('O');
      expect(final.versao, `${where}: versão +2`).toBe(pair.room.versao + 2);
      // A resposta de O já contém a jogada de X (ordem serializada).
      expect((await roomOf(ro)).partida.tabuleiro[0], `${where}: resposta de O inclui o X`).toBe('X');
    }
    expect(coherenceProblem(final.partida), `${where}: coerência`).toBeNull();
    await rooms.leave(pair.code, pair.tx);
  }
});

test('OR-18 [CAO-25] 20 salas ao mesmo tempo, 10 rodadas de 18 jogadas simultâneas em cada', async ({ rooms }) => {
  test.setTimeout(120_000);
  const positions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8];
  const problems: string[] = [];

  async function slot(slotId: number): Promise<void> {
    for (let round = 1; round <= 10; round++) {
      // Uma sala nova por rodada: a nova partida só é permitida com a partida
      // encerrada (RNO-11), e a rodada pode terminar com a partida em andamento.
      const pair: Pair = await rooms.pair();
      const where = `sala ${slotId}, rodada ${round} (${pair.code})`;
      // Metade com o token de X e metade com o de O, cada posição duas vezes.
      const tokens = positions.map((p, i) => ((p % 2 === 0) === (i < 9) ? pair.tx : pair.to));
      const responses = await Promise.all(positions.map((p, i) => rooms.move(pair.code, tokens[i], p)));
      let accepted = 0;
      for (const [i, res] of responses.entries()) {
        const status = res.status();
        const body = await res.json().catch(() => null);
        if (status === 200) {
          accepted++;
          const room = (body as { sala: Room }).sala;
          const mark = tokens[i] === pair.tx ? 'X' : 'O';
          if (room.codigo !== pair.code) problems.push(`${where}: resposta 200 com o código ${room.codigo}`);
          if (room.partida.tabuleiro[positions[i]] !== mark) {
            problems.push(`${where}: jogada de ${mark} na posição ${positions[i]} aceita, mas a célula tem "${room.partida.tabuleiro[positions[i]]}"`);
          }
          const incoherent = coherenceProblem(room.partida);
          if (incoherent) problems.push(`${where}: resposta 200 incoerente (${incoherent})`);
        } else if (status === 409) {
          const code = body?.erro?.codigo;
          if (!['VEZ_DO_OPONENTE', 'CELULA_OCUPADA', 'PARTIDA_ENCERRADA'].includes(code)) {
            problems.push(`${where}: 409 inesperado ${JSON.stringify(body)}`);
          }
        } else {
          problems.push(`${where}: status ${status} ${JSON.stringify(body)}`);
        }
      }
      const final = await rooms.room(pair.code);
      const filled = final.partida.tabuleiro.filter((c) => c !== '').length;
      if (accepted !== filled) problems.push(`${where}: ${accepted} respostas 200 e ${filled} células preenchidas`);
      if (final.versao !== pair.room.versao + accepted) problems.push(`${where}: versão ${final.versao}, esperado ${pair.room.versao + accepted}`);
      const incoherent = coherenceProblem(final.partida);
      if (incoherent) problems.push(`${where}: estado final incoerente (${incoherent}; ${describe(final.partida)})`);
      await rooms.leave(pair.code, pair.tx);
    }
  }

  await Promise.all(Array.from({ length: 20 }, (_, i) => slot(i + 1)));
  expect(problems, 'problemas encontrados').toEqual([]);
});
