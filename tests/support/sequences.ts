import { GameState, Player, state } from './api';

/*
 * Sequências de referência (docs/test-plan.md, seção 5). Todas foram
 * conferidas por simulação; ninguém vence antes da última jogada.
 */

export interface WinCase {
  id: string;
  ca: string;
  name: string;
  moves: number[];
  final: GameState;
}

function win(id: string, ca: string, name: string, moves: number[], board: string,
  winner: Player, cells: number[]): WinCase {
  return { id, ca, name, moves, final: state(board, 'VITORIA', null, winner, cells) };
}

export const WINS: WinCase[] = [
  win('R-09', 'CA-08', 'linha 0-1-2', [0, 3, 1, 4, 2], 'XXXOO....', 'X', [0, 1, 2]),
  win('R-10', 'CA-12', 'linha 3-4-5', [3, 0, 4, 1, 5], 'OO.XXX...', 'X', [3, 4, 5]),
  win('R-11', 'CA-12', 'linha 6-7-8 (vitória de O)', [0, 6, 1, 7, 4, 8], 'XX..X.OOO', 'O', [6, 7, 8]),
  win('R-12', 'CA-12', 'coluna 0-3-6', [0, 1, 3, 2, 6], 'XOOX..X..', 'X', [0, 3, 6]),
  win('R-13', 'CA-09', 'coluna 1-4-7 (vitória de O)', [0, 1, 3, 4, 8, 7], 'XO.XO..OX', 'O', [1, 4, 7]),
  win('R-14', 'CA-12', 'coluna 2-5-8', [2, 0, 5, 1, 8], 'OOX..X..X', 'X', [2, 5, 8]),
  win('R-15', 'CA-10', 'diagonal 0-4-8', [0, 1, 4, 2, 8], 'XOO.X...X', 'X', [0, 4, 8]),
  win('R-16', 'CA-11', 'diagonal 2-4-6', [2, 0, 4, 1, 6], 'OOX.X.X..', 'X', [2, 4, 6]),
  win('R-17', 'CA-13', 'na 9ª jogada, sem virar empate', [0, 1, 2, 4, 5, 3, 7, 6, 8], 'XOXOOXOXX', 'X', [2, 5, 8]),
  win('R-18', 'CA-14', 'com duas diagonais (5 células)', [0, 1, 2, 3, 6, 5, 8, 7, 4], 'XOXOXOXOX', 'X', [0, 2, 4, 6, 8]),
];

/** S-L1: X vence na linha 0-1-2; células 5 a 8 continuam vazias. */
export const S_L1 = [0, 3, 1, 4, 2];
export const S_L1_FINAL = state('XXXOO....', 'VITORIA', null, 'X', [0, 1, 2]);

/** S-EMP: empate com tabuleiro cheio. */
export const S_EMP = [0, 1, 2, 4, 3, 5, 7, 6, 8];
export const S_EMP_FINAL = state('XOXXOOOXX', 'EMPATE', null);
