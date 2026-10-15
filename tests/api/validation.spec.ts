import { test, expect } from '../support/fixtures';
import { state } from '../support/api';
import { S_L1 } from '../support/sequences';

/* Grupo A: entradas inválidas. Toda recusa deixa o estado intacto (RN-12). */

const INVALID_POSITIONS: Array<[string, string]> = [
  ['{"posicao":9}', 'acima do intervalo'],
  ['{"posicao":-1}', 'abaixo do intervalo'],
  ['{"posicao":4.5}', 'valor fracionário'],
  ['{"posicao":0.5}', 'valor fracionário'],
  ['{"posicao":"4"}', 'texto'],
  ['{"posicao":null}', 'nulo'],
  ['{"posicao":true}', 'booleano'],
  ['{}', 'campo ausente'],
  ['{"Posicao":4}', 'nome com maiúscula'],
  ['{"posicao":99999999999}', 'não cabe em inteiro de 32 bits'],
];

/* {"posicao":4,"x":"__"} com os dois '_' trocados por bytes UTF-8 inválidos. */
const INVALID_UTF8 = Buffer.from('{"posicao":4,"x":"__"}', 'latin1');
INVALID_UTF8[18] = 0xff;
INVALID_UTF8[19] = 0xfe;

const INVALID_BODIES: Array<[string, string | Buffer | undefined]> = [
  ['sem corpo', undefined],
  ['corpo vazio', ''],
  ['texto que não é JSON', 'abc'],
  ['JSON incompleto', '{"posicao":'],
  ['array no topo', '[4]'],
  ['número no topo', '4'],
  ['texto JSON no topo', '"x"'],
  ['UTF-8 inválido', INVALID_UTF8],
];

test.describe('Posições inválidas', () => {
  for (const [body, reason] of INVALID_POSITIONS) {
    test(`A-04 [CA-05] ${body} (${reason}) -> 400 POSICAO_INVALIDA, estado inalterado`, async ({ game }) => {
      await game.play([0]);
      const res = await game.expectUnchanged(body, () => game.postMoveRaw(body));
      await game.expectError(res, 400, 'POSICAO_INVALIDA', body);
    });
  }
});

test.describe('Corpos inválidos', () => {
  for (const [label, body] of INVALID_BODIES) {
    test(`A-05 [CA-06] ${label} -> 400 CORPO_INVALIDO, estado inalterado`, async ({ game }) => {
      await game.play([0]);
      const res = await game.expectUnchanged(label, () => game.postMoveRaw(body));
      await game.expectError(res, 400, 'CORPO_INVALIDO', label);
    });
  }
});

test('A-06 Content-Type text/plain é aceito; 4.0 e 1e0 valem como inteiros', async ({ game }) => {
  const plain = await game.postMoveRaw('{"posicao":4}', 'text/plain');
  expect(plain.status(), `text/plain: ${await plain.text()}`).toBe(200);
  expect(await plain.json()).toEqual(state('....X....', 'EM_ANDAMENTO', 'O'));

  await game.reset();
  const withFraction = await game.postMoveRaw('{"posicao":4.0}');
  expect(withFraction.status(), `4.0: ${await withFraction.text()}`).toBe(200);
  const withExponent = await game.postMoveRaw('{"posicao":1e0}');
  expect(withExponent.status(), `1e0: ${await withExponent.text()}`).toBe(200);
  expect(await withExponent.json()).toEqual(state('.O..X....', 'EM_ANDAMENTO', 'X'));
});

test('A-07 mensagens com acentos chegam em UTF-8 válido', async ({ game }) => {
  await game.play([0]);
  await game.expectError(await game.move(0), 409, 'CELULA_OCUPADA', 'célula ocupada');

  await game.reset();
  await game.play(S_L1);
  await game.expectError(await game.move(5), 409, 'PARTIDA_ENCERRADA', 'partida encerrada');
});
