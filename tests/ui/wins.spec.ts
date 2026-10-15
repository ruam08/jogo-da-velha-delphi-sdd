import { test, expect } from '../support/fixtures';
import { WINS } from '../support/sequences';
import { STATUS_TEXT } from '../support/ui';

/*
 * Grupo U: vitórias pela interface. As 8 combinações, a vitória na 9ª
 * jogada e a dupla são as mesmas sequências do grupo R; aqui o foco é o que
 * a tela mostra (status, destaque, células inativas).
 */

const UI_IDS: Record<string, string> = {
  'R-09': 'U-04-L1', 'R-10': 'U-04-L2', 'R-11': 'U-04-L3', 'R-12': 'U-04-C1',
  'R-13': 'U-04-C2', 'R-14': 'U-04-C3', 'R-15': 'U-04-D1', 'R-16': 'U-04-D2',
  'R-17': 'U-05', 'R-18': 'U-06',
};

for (const w of WINS) {
  test(`${UI_IDS[w.id]} [${w.ca}] vitória na tela: ${w.name}`, async ({ ui }) => {
    await ui.open();
    await ui.play(w.moves);

    const board = w.final.tabuleiro.map((c) => (c === '' ? '.' : c)).join('');
    await ui.expectBoard(board);
    await expect(ui.status).toHaveText(w.final.vencedor === 'X' ? STATUS_TEXT.winX : STATUS_TEXT.winO);
    await ui.expectWinning(w.final.celulasVencedoras);
    await ui.expectCellsDisabled(true);
    await expect(ui.app).toHaveAttribute('data-state', 'finished');
    await ui.expectNoError();
  });
}
