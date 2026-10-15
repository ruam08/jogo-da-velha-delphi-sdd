import { test, expect } from '../support/fixtures';
import { GameState, coherenceProblem, describe, state } from '../support/api';

/*
 * Grupo R: requisições simultâneas (CA-25, RNF-06). As requisições são
 * disparadas juntas com Promise.all; o servidor atende cada conexão em uma
 * thread e precisa serializar o acesso à partida.
 *
 * Um teste de concorrência pode passar por sorte; por isso há repetições, e
 * a validação da entrega roda o R-27 contra um servidor sabotado (sem trava)
 * para provar que ele detecta o defeito (SB-04).
 */

test('R-27 [CA-25] duas jogadas simultâneas na mesma célula: uma 200 e uma 409 (20 repetições)', async ({ game }) => {
  for (let rep = 1; rep <= 20; rep++) {
    await game.reset();
    const responses = await Promise.all([game.move(0), game.move(0)]);
    const codes = responses.map((r) => r.status()).sort();
    expect(codes, `repetição ${rep}: códigos HTTP`).toEqual([200, 409]);

    const conflict = responses.find((r) => r.status() === 409)!;
    expect((await conflict.json()).erro.codigo, `repetição ${rep}: código do 409`).toBe('CELULA_OCUPADA');

    expect(await game.state(), `repetição ${rep}: estado final`).toEqual(state('X........', 'EM_ANDAMENTO', 'O'));
  }
});

test('R-28 [CA-25] rajada de 18 jogadas simultâneas mantém o estado coerente (10 repetições)', async ({ game }) => {
  const positions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8];
  for (let rep = 1; rep <= 10; rep++) {
    await game.reset();
    const responses = await Promise.all(positions.map((p) => game.move(p)));
    const final = await game.state();
    const where = `repetição ${rep}, estado final ${describe(final)}`;

    let accepted = 0;
    for (const [i, res] of responses.entries()) {
      const body = await res.json();
      if (res.status() === 200) {
        accepted++;
        const s = body as GameState;
        expect(s.tabuleiro[positions[i]], `${where}: resposta 200 para a posição ${positions[i]} com a célula vazia`).not.toBe('');
        expect(coherenceProblem(s), `${where}: resposta 200 com estado incoerente (${describe(s)})`).toBeNull();
      } else {
        expect(res.status(), `${where}: resposta inesperada ${JSON.stringify(body)}`).toBe(409);
        expect(['CELULA_OCUPADA', 'PARTIDA_ENCERRADA'], `${where}: código do 409`).toContain(body.erro.codigo);
      }
    }

    const filled = final.tabuleiro.filter((c) => c !== '').length;
    expect(accepted, `${where}: respostas 200 x células preenchidas`).toBe(filled);
    expect(coherenceProblem(final), `${where}: estado final incoerente`).toBeNull();
  }
});
