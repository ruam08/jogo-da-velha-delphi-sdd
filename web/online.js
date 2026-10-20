/*
 * Jogo da Velha online - interface (docs/plan-online.md, seções 9 e 10;
 * docs/spec-online.md, seção 8).
 *
 * O servidor Delphi é a única autoridade (RNO-12): este script não decide
 * turno, validade de jogada, vencedor, empate nem presença. Ele envia as
 * intenções (criar, entrar, jogar, nova partida, sair) pelas rotas REST,
 * recebe os estados pela resposta e pelo canal em tempo real (/ws) e desenha
 * o estado de versão mais alta que recebeu (RNO-08).
 *
 * O token do jogador só viaja no cabeçalho Authorization e dentro da
 * mensagem "entrar" do canal; fica guardado no localStorage, por sala, e
 * nunca vai para a URL (RNO-02, RNO-16, DO-05).
 */
(function () {
  'use strict';

  var TIMEOUT_MS = 8000;
  var STORAGE_PREFIX = 'jogo-da-velha:sala:';
  var STORAGE_TTL_MS = 24 * 60 * 60 * 1000;
  var OFFLINE_AFTER_MS = 30000;
  var RETRY_DELAYS_MS = [500, 1000, 2000, 4000, 8000];
  var RETRY_MAX_MS = 10000;
  var WELCOME_TIMEOUT_MS = 10000;
  var DEFAULT_PING_MS = 20000;

  var TEXT = {
    loading: 'Carregando…',
    start: 'Crie uma sala ou entre com o código de uma sala.',
    lookup: 'Consultando a sala…',
    invite: 'Você foi convidado para uma partida.',
    unavailable: 'Não foi possível entrar nesta sala.',
    waiting: 'Aguardando o oponente…',
    yourTurn: 'Sua vez',
    opponentTurn: 'Vez do oponente',
    youWon: 'Você venceu!',
    opponentWon: 'O oponente venceu.',
    draw: 'Empate!',
    closedStatus: 'Sala encerrada.',
    replacedStatus: 'Sala aberta em outra aba.',
    opponentMissing: 'Aguardando oponente',
    opponentOnline: 'Oponente conectado',
    opponentOffline: 'Oponente desconectado. Aguardando reconexão…',
    connecting: 'Conectando…',
    connected: 'Conectado',
    reconnecting: 'Reconectando…',
    offline: 'Sem conexão com o servidor.',
    copied: 'Link copiado.',
    copyFailed: 'Não foi possível copiar. Selecione o link acima e copie.',
    network: 'Não foi possível comunicar com o servidor.',
    emptyCode: 'Informe o código da sala.',
    restartHint: 'Se o servidor foi reiniciado, as salas anteriores deixam de existir.',
    leaveConfirm: 'Sair da sala encerra a partida para os dois jogadores.',
    channelProblem: 'O servidor recusou a comunicação desta página. Recarregue a página.',
    // Mesmas mensagens do servidor (docs/plan-online.md, 6.6), usadas quando
    // a situação vem do estado da sala ou só do código de fechamento do canal.
    roomFull: 'Esta sala já tem dois jogadores.',
    roomClosed: 'Esta sala foi encerrada.',
    roomMissing: 'Sala não encontrada. Confira o código.',
    invalidToken: 'Jogador não identificado nesta sala.',
    replaced: 'Esta sala foi aberta em outra aba.'
  };

  var ROOM_STATES = ['aguardando', 'jogando', 'finalizada'];

  function $(id) { return document.querySelector('[data-testid="' + id + '"]'); }

  var app = $('online-app');
  var el = {
    status: $('status'),
    badge: $('turn-badge'),
    start: $('start-panel'),
    createRoom: $('create-room'),
    joinForm: $('join-form'),
    codeInput: $('room-code-input'),
    invite: $('invite-panel'),
    inviteCode: $('invite-code'),
    joinThisRoom: $('join-this-room'),
    share: $('share-panel'),
    roomCode: $('room-code'),
    roomLink: $('room-link'),
    copyLink: $('copy-link'),
    copyFeedback: $('copy-feedback'),
    presence: $('room-panel'),
    youAre: $('you-are'),
    gameNumber: $('game-number'),
    opponent: $('opponent-status'),
    connection: $('connection-status'),
    board: $('board'),
    error: $('error-message'),
    hint: $('room-hint'),
    newGame: $('new-game'),
    leave: $('leave-room'),
    reconnect: $('reconnect'),
    useHere: $('use-here'),
    createNewRoom: $('create-new-room'),
    retry: $('retry'),
    keysHint: document.querySelector('.online-footer__keys')
  };
  var cells = Array.prototype.slice.call(el.board.querySelectorAll('.cell'));

  /* ---- Estado da página ------------------------------------------------------ */

  var screen = 'inicio';     // data-state (plan-online 9.2)
  var code = '';             // código da sala atual
  var seat = null;           // 'X' ou 'O' (vem do servidor)
  var token = null;          // credencial do lugar (nunca na URL)
  var room = null;           // último estado aplicado
  var version = 0;           // versão do último estado aplicado (RNO-08)
  var busy = false;          // uma ação por vez (CIO-11)
  var memorySeats = {};      // reserva, se o localStorage não estiver disponível

  /* ---- Guarda do token (DO-05: localStorage por sala, validade de 24 h) ---- */

  function storageKey(c) { return STORAGE_PREFIX + c; }

  function validEntry(e, c) {
    return !!e && e.codigo === c && (e.simbolo === 'X' || e.simbolo === 'O') &&
      typeof e.token === 'string' && /^[0-9a-f]{32}$/.test(e.token) &&
      typeof e.salvoEm === 'number' && Date.now() - e.salvoEm <= STORAGE_TTL_MS;
  }

  function loadSeat(c) {
    var raw;
    try {
      raw = window.localStorage.getItem(storageKey(c));
    } catch (e) {
      raw = null;   // localStorage indisponível: só a reserva em memória desta página
    }
    if (raw === null) {
      if (validEntry(memorySeats[c], c)) return memorySeats[c];
      delete memorySeats[c];
      return null;
    }
    var entry = null;
    try { entry = JSON.parse(raw); } catch (e) { entry = null; }
    if (validEntry(entry, c)) return entry;
    forgetSeat(c);   // vencida ou inválida: descartada sem ir ao servidor
    return null;
  }

  function saveSeat(c, simbolo, t) {
    var entry = { codigo: c, simbolo: simbolo, token: t, salvoEm: Date.now() };
    memorySeats[c] = entry;
    try { window.localStorage.setItem(storageKey(c), JSON.stringify(entry)); } catch (e) { /* só em memória */ }
  }

  function forgetSeat(c) {
    delete memorySeats[c];
    try { window.localStorage.removeItem(storageKey(c)); } catch (e) { /* nada a apagar */ }
  }

  function purgeExpired() {
    try {
      var keys = [];
      for (var i = 0; i < window.localStorage.length; i++) {
        var k = window.localStorage.key(i);
        if (k && k.indexOf(STORAGE_PREFIX) === 0) keys.push(k);
      }
      keys.forEach(function (k) { loadSeat(k.substring(STORAGE_PREFIX.length)); });
    } catch (e) { /* localStorage indisponível */ }
  }

  /* ---- REST ------------------------------------------------------------------- */

  function roomPath(c) { return '/api/rooms/' + encodeURIComponent(c); }
  function pagePath(c) { return '/online.html?sala=' + encodeURIComponent(c); }
  function roomLink(c) { return window.location.origin + pagePath(c); }

  /* Requisição com tempo-limite. Lança erro em falha de rede ou tempo
     esgotado; devolve { ok, status, data } nos demais casos. */
  function request(method, path, auth, body) {
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, TIMEOUT_MS);
    var headers = {};
    if (auth) headers.Authorization = 'Bearer ' + auth;
    var options = { method: method, cache: 'no-store', credentials: 'same-origin', signal: controller.signal, headers: headers };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
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

  function isRoom(s) {
    return !!s && typeof s.codigo === 'string' && typeof s.versao === 'number' &&
      typeof s.situacao === 'string' && !!s.jogadores && !!s.partida &&
      Array.isArray(s.partida.tabuleiro) && s.partida.tabuleiro.length === 9 &&
      Array.isArray(s.partida.celulasVencedoras);
  }

  function apiError(data) {
    return data && data.erro && typeof data.erro.mensagem === 'string' ? data.erro : null;
  }

  /* Executa uma ação se não houver outra pendente (CIO-11). */
  function run(action) {
    if (busy) return Promise.resolve();
    setBusy(true);
    return action()
      .catch(function () { showError(TEXT.network); })
      .finally(function () { setBusy(false); });
  }

  /* ---- Aplicação de estado (RNO-08) ------------------------------------------- */

  function applyRoom(s) {
    if (!isRoom(s) || s.codigo !== code || s.versao <= version) return false;
    version = s.versao;
    room = s;
    if (isRoomScreen(screen) || screen === 'consultando') setScreen(roomScreen());
    render();
    return true;
  }

  function roomScreen() {
    if (!room) return 'consultando';
    if (room.situacao === 'ENCERRADA') return 'encerrada';
    if (room.situacao === 'AGUARDANDO_OPONENTE') return 'aguardando';
    return room.partida.status === 'EM_ANDAMENTO' ? 'jogando' : 'finalizada';
  }

  function isRoomScreen(s) { return ROOM_STATES.indexOf(s) >= 0; }

  /* Entrou numa sala (criação ou entrada aceitas pelo servidor). */
  function enterRoom(sala, jogador) {
    stopChannel();
    code = sala.codigo;
    seat = jogador.simbolo;
    token = jogador.token;
    room = null;
    version = 0;
    saveSeat(code, seat, token);
    window.history.replaceState(null, '', pagePath(code));
    clearError();
    el.copyFeedback.hidden = true;
    setScreen('consultando');
    applyRoom(sala);
    openChannel();
  }

  /* Situação terminal: sala encerrada, inexistente, cheia ou token recusado (CIO-12). */
  function finish(kind, message, hint) {
    stopChannel();
    if (kind !== 'cheia' && code) forgetSeat(code);
    token = null;
    setScreen(kind);
    showError(message);
    el.hint.textContent = hint || '';
    el.hint.hidden = !hint;
    render();
  }

  function handleRefusal(err, inGame) {
    if (err.codigo === 'SALA_INEXISTENTE') finish('inexistente', err.mensagem, inGame ? TEXT.restartHint : '');
    else if (err.codigo === 'SALA_ENCERRADA') finish('encerrada', err.mensagem);
    else if (err.codigo === 'TOKEN_INVALIDO') finish('negado', err.mensagem);
    else showError(err.mensagem);
  }

  /* ---- Ações ------------------------------------------------------------------ */

  function createRoom() {
    return run(function () {
      return request('POST', '/api/rooms').then(function (r) {
        if (r.status === 201 && r.data && isRoom(r.data.sala) && r.data.jogador) {
          code = r.data.sala.codigo;
          enterRoom(r.data.sala, r.data.jogador);
        } else if (apiError(r.data)) {
          showError(apiError(r.data).mensagem);
        } else {
          showError(TEXT.network);
        }
      });
    });
  }

  function normalizeCode(value) { return String(value || '').trim().toUpperCase(); }

  /* Entrar numa sala; com token guardado, é uma reentrada (RNO-05). */
  function joinRoom(c, fromInvite) {
    if (!c) {
      showError(TEXT.emptyCode);
      return Promise.resolve();
    }
    var saved = loadSeat(c);
    return run(function () {
      return request('POST', roomPath(c) + '/players', saved ? saved.token : null).then(function (r) {
        if ((r.status === 201 || r.status === 200) && r.data && isRoom(r.data.sala) && r.data.jogador) {
          code = r.data.sala.codigo;
          enterRoom(r.data.sala, r.data.jogador);
          return;
        }
        var err = apiError(r.data);
        if (!err) { showError(TEXT.network); return; }
        if (fromInvite) {
          code = c;
          if (err.codigo === 'SALA_CHEIA') finish('cheia', err.mensagem);
          else handleRefusal(err, false);
        } else {
          showError(err.mensagem);   // tela inicial: só a mensagem, o campo continua
        }
      });
    });
  }

  /* Link aberto sem lugar guardado: o servidor diz se a sala aceita entrada (CIO-03). */
  function lookupRoom() {
    setScreen('consultando');
    function failed() {
      showError(TEXT.network);
      el.retry.hidden = false;
    }
    return run(function () {
      return request('GET', roomPath(code)).then(function (r) {
        var err = apiError(r.data);
        if (r.status === 200 && r.data && isRoom(r.data.sala)) {
          var s = r.data.sala;
          if (s.situacao === 'AGUARDANDO_OPONENTE') setScreen('convite');
          else if (s.situacao === 'ENCERRADA') finish('encerrada', TEXT.roomClosed);
          else finish('cheia', TEXT.roomFull);
        } else if (err) {
          handleRefusal(err, false);
          if (screen === 'consultando') setScreen('inicio');
        } else {
          failed();
        }
      }, failed);
    });
  }

  function play(index) {
    return run(function () {
      return request('POST', roomPath(code) + '/moves', token, { posicao: index }).then(handleRoomResponse);
    });
  }

  function newGame() {
    return run(function () {
      return request('POST', roomPath(code) + '/reset', token).then(handleRoomResponse);
    });
  }

  function leaveRoom() {
    if (busy || !window.confirm(TEXT.leaveConfirm)) return Promise.resolve();
    return run(function () {
      return request('POST', roomPath(code) + '/leave', token).then(function (r) {
        if (r.ok && r.data && isRoom(r.data.sala)) {
          applyRoom(r.data.sala);
          finish('encerrada', TEXT.roomClosed);
        } else {
          handleRoomResponse(r);
        }
      });
    });
  }

  function handleRoomResponse(r) {
    if (!isRoomScreen(screen)) return;   // a sala terminou enquanto a ação estava pendente
    if (r.ok && r.data && isRoom(r.data.sala)) {
      applyRoom(r.data.sala);
      clearError();
    } else if (apiError(r.data)) {
      handleRefusal(apiError(r.data), true);
    } else {
      showError(TEXT.network);
    }
  }

  function resetToStart() {
    stopChannel();
    code = '';
    seat = null;
    token = null;
    room = null;
    version = 0;
    clearError();
    el.copyFeedback.hidden = true;
  }

  /* ---- Canal em tempo real (plan-online, seções 7 e 10) ----------------------- */

  var socket = null;          // canal atual
  var channelWanted = false;  // a página quer um canal para a sala atual
  var welcomed = false;       // o canal atual já recebeu bem_vindo
  var everWelcomed = false;   // algum canal desta sala já foi aceito
  var openedAt = 0;
  var lastReceived = 0;
  var pingInterval = DEFAULT_PING_MS;
  var pingId = 0;
  var attempt = 0;
  var downSince = 0;
  var lastChannelError = '';
  var pingTimer = null;
  var watchdogTimer = null;
  var retryTimer = null;
  var offlineTimer = null;
  var connection = 'parado';

  function channelUrl() {
    return (window.location.protocol === 'https:' ? 'wss://' : 'ws://') + window.location.host + '/ws';
  }

  function openChannel() {
    closeSocket();
    clearTimeout(retryTimer);
    retryTimer = null;
    channelWanted = true;
    welcomed = false;
    lastChannelError = '';
    if (!everWelcomed && !downSince) setConnection('conectando');
    var ws;
    try {
      ws = new WebSocket(channelUrl());
    } catch (e) {
      channelLost();
      return;
    }
    socket = ws;
    openedAt = Date.now();
    ws.onopen = function () {
      if (socket !== ws) return;
      send({ tipo: 'entrar', protocolo: 1, sala: code, token: token });
    };
    ws.onmessage = function (ev) {
      if (socket !== ws) return;
      lastReceived = Date.now();
      onMessage(ev.data);
    };
    ws.onclose = function (ev) {
      if (socket !== ws) return;
      socket = null;
      onClose(ev.code);
    };
    ws.onerror = function () { /* o fechamento vem em seguida */ };
    clearInterval(watchdogTimer);
    watchdogTimer = setInterval(watchdog, 1000);
  }

  function send(message) {
    if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  }

  function closeSocket() {
    clearInterval(pingTimer);
    clearInterval(watchdogTimer);
    pingTimer = null;
    watchdogTimer = null;
    if (socket) {
      var ws = socket;
      socket = null;
      ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null;
      try { ws.close(1000); } catch (e) { /* já fechado */ }
    }
  }

  function stopChannel() {
    channelWanted = false;
    closeSocket();
    clearTimeout(retryTimer);
    clearTimeout(offlineTimer);
    retryTimer = null;
    offlineTimer = null;
    attempt = 0;
    downSince = 0;
    everWelcomed = false;
    setConnection('parado');
  }

  /* Sem bem_vindo em 10 s, ou sem nada recebido em 2,25 x intervalo de ping: o canal caiu. */
  function watchdog() {
    if (!socket) return;
    var now = Date.now();
    if ((!welcomed && now - openedAt > WELCOME_TIMEOUT_MS) ||
        (welcomed && now - lastReceived > pingInterval * 2.25)) {
      closeSocket();
      channelLost();
    }
  }

  function onMessage(data) {
    var msg;
    try { msg = JSON.parse(data); } catch (e) { return; }
    if (!msg || typeof msg.tipo !== 'string') return;
    switch (msg.tipo) {
      case 'bem_vindo':
        welcomed = true;
        everWelcomed = true;
        attempt = 0;
        downSince = 0;
        clearTimeout(offlineTimer);
        if (msg.voce === 'X' || msg.voce === 'O') seat = msg.voce;
        if (typeof msg.intervaloPingMs === 'number' && msg.intervaloPingMs >= 500) pingInterval = msg.intervaloPingMs;
        saveSeat(code, seat, token);   // renova a validade de 24 h
        clearInterval(pingTimer);
        pingTimer = setInterval(function () { send({ tipo: 'ping', id: (pingId = (pingId + 1) % 2147483647) }); }, pingInterval);
        setConnection('conectado');
        if (applyRoom(msg.sala)) clearError();
        if (screen === 'consultando' || screen === 'substituida') { setScreen(roomScreen()); render(); }
        break;
      case 'estado':
        if (applyRoom(msg.sala)) clearError();
        break;
      case 'sala_encerrada':
        applyRoom(msg.sala);
        finish('encerrada', TEXT.roomClosed);
        break;
      case 'erro':
        lastChannelError = msg.codigo || '';
        onChannelError(msg.codigo, typeof msg.mensagem === 'string' ? msg.mensagem : '');
        break;
      default:
        break;   // pong e outras mensagens não mudam a tela
    }
  }

  function onChannelError(codigo, mensagem) {
    if (codigo === 'SUBSTITUIDA') replaced(mensagem || TEXT.replaced);
    else if (codigo === 'TOKEN_INVALIDO') finish('negado', mensagem || TEXT.invalidToken);
    else if (codigo === 'SALA_INEXISTENTE') finish('inexistente', mensagem || TEXT.roomMissing, TEXT.restartHint);
    else if (codigo === 'SALA_ENCERRADA') finish('encerrada', mensagem || TEXT.roomClosed);
    else if (codigo === 'MENSAGEM_INVALIDA') { stopChannel(); showError(TEXT.channelProblem); }
    // TEMPO_ESGOTADO: o fechamento vem em seguida e a página reconecta.
  }

  /* Códigos de fechamento (plan-online 7.4 e 10). */
  function onClose(closeCode) {
    if (!channelWanted) return;
    if (closeCode === 4000) replaced(TEXT.replaced);
    else if (closeCode === 4401) finish('negado', TEXT.invalidToken);
    else if (closeCode === 4404) finish('inexistente', TEXT.roomMissing, TEXT.restartHint);
    else if (closeCode === 4410) finish('encerrada', TEXT.roomClosed);
    else if (closeCode === 4400) { stopChannel(); showError(TEXT.channelProblem); }
    else channelLost();
  }

  /* Queda: novas tentativas com espera crescente e variação de ±20% (seção 10). */
  function channelLost() {
    if (!channelWanted) return;
    closeSocket();
    welcomed = false;
    if (!downSince) {
      downSince = Date.now();
      clearTimeout(offlineTimer);
      offlineTimer = setTimeout(updateDownState, OFFLINE_AFTER_MS);
    }
    updateDownState();
    var base = attempt < RETRY_DELAYS_MS.length ? RETRY_DELAYS_MS[attempt] : RETRY_MAX_MS;
    attempt++;
    var delay = Math.round(base * (0.8 + Math.random() * 0.4));
    clearTimeout(retryTimer);
    retryTimer = setTimeout(openChannel, delay);
  }

  function updateDownState() {
    if (!channelWanted || !downSince || welcomed) return;
    setConnection(Date.now() - downSince >= OFFLINE_AFTER_MS ? 'offline' : 'reconectando');
  }

  /* Tentar já (botão, rede de volta, aba visível). */
  function retryNow() {
    if (!channelWanted || welcomed || !retryTimer) return;
    clearTimeout(retryTimer);
    retryTimer = null;
    openChannel();
  }

  /* O mesmo lugar foi aberto em outro canal (RNO-15): não reconecta sozinho. */
  function replaced(message) {
    stopChannel();
    setScreen('substituida');
    showError(message);
    render();
  }

  function useHere() {
    clearError();
    setScreen(room ? roomScreen() : 'consultando');
    render();
    openChannel();
  }

  /* ---- Desenho ----------------------------------------------------------------- */

  function setScreen(s) {
    screen = s;
    app.setAttribute('data-state', s);
    var inRoom = isRoomScreen(s) || s === 'encerrada' || s === 'substituida' || (s === 'consultando' && !!seat);
    el.start.hidden = s !== 'inicio';
    el.invite.hidden = s !== 'convite';
    var stale = s === 'encerrada' || s === 'substituida';   // estado que não muda mais nesta aba
    el.share.hidden = !(inRoom && code && seat) || s === 'encerrada';
    el.presence.hidden = !(inRoom && code && seat);
    el.opponent.hidden = stale;
    el.board.hidden = !(inRoom && room);
    el.keysHint.hidden = el.board.hidden || stale;
    el.newGame.hidden = !isRoomScreen(s);
    el.leave.hidden = !isRoomScreen(s);
    el.useHere.hidden = s !== 'substituida';
    el.createNewRoom.hidden = ['cheia', 'inexistente', 'encerrada', 'negado'].indexOf(s) < 0;
    el.retry.hidden = true;
    if (s !== 'inexistente') { el.hint.hidden = true; el.hint.textContent = ''; }
    updateReconnectButton();
    render();
  }

  function setConnection(state) {
    connection = state;
    app.setAttribute('data-connection', state);
    var text = { conectando: TEXT.connecting, conectado: TEXT.connected, reconectando: TEXT.reconnecting, offline: TEXT.offline }[state];
    el.connection.textContent = text || '';
    el.connection.hidden = !text;
    updateReconnectButton();
  }

  function updateReconnectButton() {
    el.reconnect.hidden = connection !== 'offline';
  }

  function cellLabel(index, content, winning) {
    var row = Math.floor(index / 3) + 1;
    var col = (index % 3) + 1;
    return 'Linha ' + row + ', coluna ' + col + ': ' + (content || 'vazia') + (winning ? ', vencedora' : '');
  }

  /* Textos da CIO-05 e da CIO-06, formatados só a partir do estado e do lugar. */
  function statusText() {
    switch (screen) {
      case 'inicio': return TEXT.start;
      case 'consultando': return room ? '' : (seat ? TEXT.connecting : TEXT.lookup);
      case 'convite': return TEXT.invite;
      case 'cheia':
      case 'inexistente':
      case 'negado': return TEXT.unavailable;
      case 'encerrada': return TEXT.closedStatus;
      case 'substituida': return TEXT.replacedStatus;
      default: break;
    }
    if (!room) return TEXT.loading;
    if (room.situacao === 'AGUARDANDO_OPONENTE') return TEXT.waiting;
    var g = room.partida;
    if (g.status === 'VITORIA') return g.vencedor === seat ? TEXT.youWon : TEXT.opponentWon;
    if (g.status === 'EMPATE') return TEXT.draw;
    return g.jogadorDaVez === seat ? TEXT.yourTurn : TEXT.opponentTurn;
  }

  function opponentText() {
    if (!room || !seat) return '';
    var other = room.jogadores[seat === 'X' ? 'O' : 'X'];
    if (!other || !other.ocupado) return TEXT.opponentMissing;
    return other.conectado ? TEXT.opponentOnline : TEXT.opponentOffline;
  }

  function render() {
    app.setAttribute('data-version', String(version));
    var text = statusText();
    if (el.status.textContent !== text) el.status.textContent = text;

    if (code) {
      el.roomCode.textContent = code;
      el.inviteCode.textContent = code;
      el.roomLink.textContent = roomLink(code);
      el.roomLink.setAttribute('href', pagePath(code));
    }
    if (seat) el.youAre.textContent = 'Você joga com ' + seat;

    var badgeValue = '';
    var badgePlayer = '';
    if (room) {
      var g = room.partida;
      var finished = g.status !== 'EM_ANDAMENTO';
      var myTurn = screen === 'jogando' && room.situacao === 'EM_JOGO' && !finished && g.jogadorDaVez === seat;
      cells.forEach(function (cell, index) {
        var content = g.tabuleiro[index];
        var winning = g.celulasVencedoras.indexOf(index) >= 0;
        cell.textContent = content;
        cell.setAttribute('data-symbol', content);
        cell.setAttribute('aria-label', cellLabel(index, content, winning));
        if (winning) cell.setAttribute('data-winning', 'true');
        else cell.removeAttribute('data-winning');
        // Só aparência (CIO-09): o clique continua indo ao servidor.
        if (myTurn) cell.removeAttribute('aria-disabled');
        else cell.setAttribute('aria-disabled', 'true');
      });
      el.gameNumber.textContent = 'Partida ' + room.numeroDaPartida;
      el.opponent.textContent = opponentText();
      if (isRoomScreen(screen)) {
        if (room.situacao === 'AGUARDANDO_OPONENTE') { badgeValue = seat || ''; badgePlayer = seat || ''; }
        else if (finished) { badgeValue = g.vencedor || '='; badgePlayer = g.vencedor || 'draw'; }
        else { badgeValue = g.jogadorDaVez; badgePlayer = g.jogadorDaVez; }
      }
    }
    el.badge.textContent = badgeValue;
    el.badge.setAttribute('data-player', badgePlayer);
  }

  function setBusy(value) {
    busy = value;
    el.board.setAttribute('aria-busy', value ? 'true' : 'false');
    app.classList.toggle('is-busy', value);
  }

  function showError(message) {
    el.error.textContent = message;
    el.error.hidden = false;
  }

  function clearError() {
    el.error.textContent = '';
    el.error.hidden = true;
  }

  /* ---- Copiar link ------------------------------------------------------------- */

  /* Fora de um contexto seguro (http://<IP da rede local>) não existe
     navigator.clipboard: usa a seleção de um campo temporário. */
  function legacyCopy(text) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.top = '0';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(area);
    el.copyLink.focus();
    return ok;
  }

  function copyLink() {
    var text = roomLink(code);
    function done(ok) {
      el.copyFeedback.textContent = ok ? TEXT.copied : TEXT.copyFailed;
      el.copyFeedback.hidden = false;
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(legacyCopy(text)); });
    } else {
      done(legacyCopy(text));
    }
  }

  /* ---- Eventos ------------------------------------------------------------------ */

  cells.forEach(function (cell, index) {
    cell.addEventListener('click', function () {
      // Todo clique vai ao servidor, inclusive fora da vez (CIO-08); só não há
      // o que enviar sem uma sala ativa e um lugar.
      if (isRoomScreen(screen) && token) play(index);
    });
  });

  // Setas movem o foco dentro da grade 3x3 (CIO-14), como na página local.
  el.board.addEventListener('keydown', function (event) {
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

  el.createRoom.addEventListener('click', function () { createRoom(); });
  el.joinForm.addEventListener('submit', function (event) {
    event.preventDefault();
    joinRoom(normalizeCode(el.codeInput.value), false);
  });
  el.joinThisRoom.addEventListener('click', function () { joinRoom(code, true); });
  el.copyLink.addEventListener('click', copyLink);
  el.newGame.addEventListener('click', function () { newGame(); });
  el.leave.addEventListener('click', function () { leaveRoom(); });
  el.reconnect.addEventListener('click', function () { attempt = 0; retryNow(); });
  el.useHere.addEventListener('click', useHere);
  el.createNewRoom.addEventListener('click', function () {
    resetToStart();
    window.history.replaceState(null, '', '/online.html');
    setScreen('inicio');
    createRoom();
  });
  el.retry.addEventListener('click', function () { clearError(); lookupRoom(); });

  window.addEventListener('online', retryNow);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') retryNow();
  });

  /* ---- Abertura (plan-online 9.3) ---------------------------------------------- */

  purgeExpired();
  var param = new URLSearchParams(window.location.search).get('sala');
  var initial = normalizeCode(param);
  if (!initial) {
    setScreen('inicio');
  } else {
    code = initial;
    if (param !== initial) window.history.replaceState(null, '', pagePath(code));
    var saved = loadSeat(code);
    if (saved) {
      // Lugar guardado: retoma direto pelo canal (RNO-16).
      seat = saved.simbolo;
      token = saved.token;
      setScreen('consultando');
      openChannel();
    } else {
      lookupRoom();
    }
  }
})();
