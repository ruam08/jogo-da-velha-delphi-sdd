import { test, expect } from '../support/fixtures';
import { describe } from '../support/api';
import { WINS } from '../support/sequences';

/*
 * Grupo R: as 8 combinações de vitória, a vitória na 9ª jogada e a vitória
 * dupla, pela API real. O teste exaustivo de todas as partidas não é
 * repetido aqui: ele já roda no EngineCheck (M-12), direto no motor.
 */

for (const w of WINS) {
  test(`${w.id} [${w.ca}] vitória: ${w.name}`, async ({ game }) => {
    const beforeLast = w.moves.slice(0, -1);
    const last = w.moves[w.moves.length - 1];

    const mid = await game.play(beforeLast);
    expect(mid.status, `a partida terminou antes da última jogada: ${describe(mid)}`).toBe('EM_ANDAMENTO');

    const res = await game.move(last);
    expect(res.status(), `última jogada (posição ${last}): ${await res.text()}`).toBe(200);
    expect(await res.json(), 'estado devolvido pela jogada vencedora').toEqual(w.final);
    expect(await game.state(), 'estado consultado depois').toEqual(w.final);
  });
}
