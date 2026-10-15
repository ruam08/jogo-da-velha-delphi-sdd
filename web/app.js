/*
 * Jogo da Velha - interface web.
 *
 * O backend Delphi é a única fonte das regras e do estado (RN-14): este
 * script não decide turno, vitória nem empate. Ele só envia as intenções do
 * usuário e desenha o estado que o servidor devolve (docs/plan.md, seção 5).
 *
 * Uma requisição por vez (CI-13, DT-22): enquanto uma está pendente, novos
 * cliques são ignorados. Assim nenhuma resposta é aplicada fora de ordem.
 */
(function () {
  'use strict';

  var TIMEOUT_MS = 8000;
  var MSG_NETWORK = 'Não foi possível comunicar com o servidor.';
  var STATUS_LOADING = 'Carregando partida…';
  var STATUS_OFFLINE = 'Sem conexão com o servidor.';

  var app = document.querySelector('[data-testid="app"]');
  var board = document.querySelector('[data-testid="board"]');
  var statusEl = document.querySelector('[data-testid="status"]');
  var badge = document.querySelector('[data-testid="turn-badge"]');
  var errorEl = document.querySelector('[data-testid="error-message"]');
  var newGameButton = document.querySelector('[data-testid="new-game"]');
  var retryButton = document.querySelector('[data-testid="retry"]');
  var cells = Array.prototype.slice.call(board.querySelectorAll('.cell'));

  var busy = false;
  var hasState = false;

  /* ---- Comunicação com o servidor --------------------------------------- */

  /* Faz a requisição com tempo-limite. Lança erro em falha de rede ou
     tempo esgotado; devolve { ok, status, data } nos demais casos. */
  function request(method, path, body) {
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, TIMEOUT_MS);
    var options = { method: method, cache: 'no-store', signal: controller.signal };
    if (body !== undefined) {
      options.headers = { 'Content-Type': 'application/json' };
      options.body = JSON.stringify(body);
    }
    return fetch(path, options)
      .then(function (res) {
        return res.json()
          .catch(function () { return null; })
          .then(function (data) { return { ok: res.ok, status: res.status, data: data }; });
      })
      .finally(function () { clearTimeout(timer); });
  }

  function isState(data) {
    return !!data && Array.isArray(data.tabuleiro) && data.tabuleiro.length === 9 &&
      typeof data.status === 'string' && Array.isArray(data.celulasVencedoras);
  }

  function isApiError(data) {
    return !!data && !!data.erro && typeof data.erro.mensagem === 'string';
  }

  /* Executa uma ação se não houver outra pendente (CI-13). */
  function run(action) {
    if (busy) return Promise.resolve();
    setBusy(true);
    return action()
      .then(function (result) {
        if (result.ok && isState(result.data)) {
          render(result.data);
          clearError();
        } else if (isApiError(result.data)) {
          // Recusa do backend (409, 400...): mostra a mensagem, o tabuleiro não muda.
          showError(result.data.erro.mensagem, false);
        } else {
          showError(MSG_NETWORK, true);
        }
      })
      .catch(function () {
        showError(MSG_NETWORK, true);
      })
      .finally(function () {
        setBusy(false);
      });
  }

  function loadState() {
    return run(function () { return request('GET', '/api/game'); });
  }

  function play(index) {
    return run(function () { return request('POST', '/api/game/moves', { posicao: index }); });
  }

  function newGame() {
    return run(function () { return request('POST', '/api/game/reset'); });
  }

  /* ---- Desenho do estado ------------------------------------------------- */

  function cellLabel(index, content, winning) {
    var row = Math.floor(index / 3) + 1;
    var col = (index % 3) + 1;
    return 'Linha ' + row + ', coluna ' + col + ': ' + (content || 'vazia') +
      (winning ? ', vencedora' : '');
  }

  function statusText(state) {
    if (state.status === 'VITORIA') return 'Jogador ' + state.vencedor + ' venceu!';
    if (state.status === 'EMPATE') return 'Empate!';
    return 'Vez do jogador ' + state.jogadorDaVez;
  }

  function render(state) {
    var finished = state.status !== 'EM_ANDAMENTO';
    hasState = true;
    cells.forEach(function (cell, index) {
      var content = state.tabuleiro[index];
      var winning = state.celulasVencedoras.indexOf(index) >= 0;
      cell.textContent = content;
      cell.setAttribute('data-symbol', content);
      cell.setAttribute('aria-label', cellLabel(index, content, winning));
      if (winning) cell.setAttribute('data-winning', 'true');
      else cell.removeAttribute('data-winning');
      if (finished) cell.setAttribute('aria-disabled', 'true');
      else cell.removeAttribute('aria-disabled');
    });
    statusEl.textContent = statusText(state);
    badge.textContent = finished ? (state.vencedor || '=') : state.jogadorDaVez;
    badge.setAttribute('data-player', finished ? (state.vencedor || 'draw') : state.jogadorDaVez);
    board.setAttribute('data-status', state.status);
    app.setAttribute('data-state', finished ? 'finished' : 'playing');
  }

  function setBusy(value) {
    busy = value;
    board.setAttribute('aria-busy', value ? 'true' : 'false');
    app.classList.toggle('is-busy', value);
  }

  function showError(message, communication) {
    errorEl.textContent = message;
    errorEl.hidden = false;
    retryButton.hidden = !communication;
    if (communication) {
      app.setAttribute('data-state', 'offline');
      if (!hasState) {
        statusEl.textContent = STATUS_OFFLINE;
        badge.textContent = '!';
        badge.setAttribute('data-player', 'offline');
      }
    }
  }

  function clearError() {
    errorEl.textContent = '';
    errorEl.hidden = true;
    retryButton.hidden = true;
  }

  /* ---- Eventos ------------------------------------------------------------ */

  cells.forEach(function (cell, index) {
    cell.addEventListener('click', function () {
      // Sem estado carregado não há o que jogar; com estado, todo clique vai
      // ao servidor, inclusive em célula ocupada ou partida encerrada (DT-09).
      if (hasState) play(index);
    });
  });

  // Setas movem o foco dentro da grade 3x3 (CI-14).
  board.addEventListener('keydown', function (event) {
    var index = cells.indexOf(document.activeElement);
    if (index < 0) return;
    var row = Math.floor(index / 3);
    var col = index % 3;
    switch (event.key) {
      case 'ArrowUp': row = (row + 2) % 3; break;
      case 'ArrowDown': row = (row + 1) % 3; break;
      case 'ArrowLeft': col = (col + 2) % 3; break;
      case 'ArrowRight': col = (col + 1) % 3; break;
      default: return;
    }
    event.preventDefault();
    cells[row * 3 + col].focus();
  });

  newGameButton.addEventListener('click', function () { newGame(); });
  retryButton.addEventListener('click', function () { loadState(); });

  statusEl.textContent = STATUS_LOADING;
  loadState();
})();
