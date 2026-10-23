(function () {
  'use strict';

  var SORT_MODES = ['port', 'name', 'pid'];
  var SORT_LABELS = { port: 'Sort: Port', name: 'Sort: Name', pid: 'Sort: PID' };
  var SORT_KEY = 'localstop.sortMode', POLL_MS = 2000, SEARCH_DEBOUNCE_MS = 120;

  var ICONS = {
    pencil: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>',
    open: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>',
    stop: '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor" stroke="currentColor" stroke-width="1" stroke-linejoin="round" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>'
  };

  var servers = [], names = {}, query = '', sortMode = 'port', editing = null;
  var refreshInFlight = false, refreshQueued = false;
  var pollTimer = null, searchTimer = null, toastTimer = null, spinTimer = null;
  var stopping = new Set(), el = {};

  function cacheDom() {
    ['refresh', 'quit', 'search', 'sort', 'list', 'empty', 'toast'].forEach(function (id) {
      el[id] = document.getElementById(id);
    });
    el.sortLabel = document.getElementById('sort-label');
    el.emptyText = document.getElementById('empty-text');
  }
  function invoke(command, args) {
    var tauri = window.__TAURI__;
    if (!tauri || !tauri.core || typeof tauri.core.invoke !== 'function') {
      return Promise.reject(new Error('Tauri bridge is unavailable'));
    }
    return tauri.core.invoke(command, args);
  }
  function errorMessage(err) {
    if (err == null) return 'Unknown error';
    if (typeof err === 'string') return err;
    if (err.message) return String(err.message);
    try {
      var text = JSON.stringify(err);
      if (text && text !== '{}') return text;
    } catch (ignored) {}
    return String(err) || 'Unknown error';
  }
  function showToast(message, isError) {
    if (!el.toast) return;
    el.toast.textContent = message || 'Something went wrong';
    el.toast.classList.toggle('error', !!isError);
    el.toast.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 4000);
  }
  function hideToast() {
    if (toastTimer) { clearTimeout(toastTimer); toastTimer = null; }
    if (!el.toast) return;
    el.toast.hidden = true;
    el.toast.textContent = '';
  }
  function loadSortMode() {
    try {
      var saved = localStorage.getItem(SORT_KEY);
      if (SORT_MODES.indexOf(saved) !== -1) sortMode = saved;
    } catch (ignored) {}
  }
  function saveSortMode() {
    try { localStorage.setItem(SORT_KEY, sortMode); } catch (ignored) {}
  }
  function updateSortLabel() {
    el.sortLabel.textContent = SORT_LABELS[sortMode];
  }
  function displayTitle(server) {
    var custom = names[String(server.port)];
    return custom ? String(custom) : String(server.command || '');
  }
  function sortServers(items) {
    items.sort(function (a, b) {
      if (sortMode === 'name') {
        var cmp = displayTitle(a).localeCompare(displayTitle(b), undefined, { sensitivity: 'base', numeric: true });
        if (cmp !== 0) return cmp;
        return Number(a.port) - Number(b.port);
      }
      if (sortMode === 'pid') return Number(a.pid) - Number(b.pid);
      return Number(a.port) - Number(b.port);
    });
    return items;
  }
  function matches(server) {
    if (!query) return true;
    var custom = names[String(server.port)] || '';
    var haystack = [server.port, server.command, server.pid, custom, server.address].join(' ').toLowerCase();
    return haystack.indexOf(query) !== -1;
  }
  function makeButton(className, title, label, svg) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'icon ' + className;
    button.title = title;
    button.setAttribute('aria-label', label);
    button.innerHTML = svg;
    return button;
  }
  function buildRow(server) {
    var port = Number(server.port);
    var pid = Number(server.pid);
    var row = document.createElement('div');
    row.className = 'row';
    row.dataset.port = String(port);
    row.dataset.pid = String(pid);

    var badge = document.createElement('span');
    badge.className = 'badge';
    badge.textContent = String(port);

    var text = document.createElement('div');
    text.className = 'text';
    var name = document.createElement('div');
    name.className = 'name';
    name.textContent = displayTitle(server);
    name.addEventListener('click', function () { startEdit(server, name); });

    var detail = document.createElement('div');
    detail.className = 'detail';
    detail.textContent = String(server.command || '') + ' · PID ' + String(pid);
    text.appendChild(name);
    text.appendChild(detail);

    var actions = document.createElement('div');
    actions.className = 'actions';
    var renameButton = makeButton('pencil', 'Rename', 'Rename port ' + port, ICONS.pencil);
    renameButton.addEventListener('click', function () { startEdit(server, name); });
    var openButton = makeButton('open', 'Open in browser', 'Open port ' + port + ' in browser', ICONS.open);
    openButton.addEventListener('click', function () { openPort(port); });
    var stopButton = makeButton('stop', 'Stop', 'Stop port ' + port, ICONS.stop);
    stopButton.addEventListener('click', function () { stopServer(server, stopButton); });
    actions.appendChild(renameButton);
    actions.appendChild(openButton);
    actions.appendChild(stopButton);

    row.appendChild(badge);
    row.appendChild(text);
    row.appendChild(actions);
    return row;
  }
  function setEmpty(message) {
    el.emptyText.textContent = message;
    el.empty.hidden = false;
    el.list.hidden = true;
  }
  function render() {
    if (editing) return;
    el.list.textContent = '';

    var filtered = sortServers(servers.filter(matches));
    var fragment = document.createDocumentFragment();
    filtered.forEach(function (server) { fragment.appendChild(buildRow(server)); });
    el.list.appendChild(fragment);

    if (servers.length === 0) setEmpty('No local servers running');
    else if (filtered.length === 0) setEmpty('No matches');
    else {
      el.empty.hidden = true;
      el.list.hidden = false;
    }
  }
  function normaliseNames(raw) {
    var result = {};
    if (!raw || typeof raw !== 'object') return result;
    Object.keys(raw).forEach(function (key) {
      var value = raw[key];
      if (typeof value === 'string' && value.trim()) result[String(key)] = value.trim();
    });
    return result;
  }
  function normaliseServers(raw) {
    if (!Array.isArray(raw)) return [];
    var result = [];
    raw.forEach(function (item) {
      if (!item || typeof item !== 'object') return;
      var port = Number(item.port), pid = Number(item.pid);
      if (!Number.isFinite(port) || !Number.isFinite(pid)) return;
      result.push({
        pid: pid,
        port: port,
        command: item.command == null ? '' : String(item.command),
        address: item.address == null ? '' : String(item.address)
      });
    });
    return result;
  }
  function loadAll() {
    if (refreshInFlight) {
      refreshQueued = true;
      return;
    }
    refreshInFlight = true;
    Promise.all([invoke('get_names'), invoke('list_servers')]).then(function (results) {
      names = normaliseNames(results[0]);
      servers = normaliseServers(results[1]);
      render();
    }).catch(function (err) {
      showToast(errorMessage(err), true);
    }).then(function () {
      refreshInFlight = false;
      if (refreshQueued) {
        refreshQueued = false;
        loadAll();
      }
    });
  }
  function startEdit(server, nameEl) {
    if (editing || !nameEl || !nameEl.isConnected) return;
    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'rename-input';
    input.maxLength = 80;
    input.value = names[String(server.port)] || String(server.command || '');
    input.setAttribute('aria-label', 'Rename port ' + Number(server.port));

    var edit = { server: server, input: input, done: false };
    editing = edit;
    nameEl.replaceWith(input);
    input.focus();
    input.select();

    input.addEventListener('keydown', function (event) {
      if (event.key === 'Enter') {
        event.preventDefault();
        input.blur();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        cancelEdit();
      }
    });
    input.addEventListener('blur', function () { saveEdit(edit); });
  }
  function saveEdit(edit) {
    if (edit.done) return;
    edit.done = true;
    var port = Number(edit.server.port);
    var raw = edit.input.value.trim();
    var command = String(edit.server.command || '').trim();
    var next = raw === command ? '' : raw;
    if (editing === edit) editing = null;

    invoke('set_name', { port: port, name: next }).then(function () {
      if (next) names[String(port)] = next;
      else delete names[String(port)];
      render();
    }).catch(function (err) {
      showToast(errorMessage(err), true);
      render();
    });
  }
  function cancelEdit() {
    if (!editing) return;
    editing.done = true;
    editing = null;
    render();
  }
  function openPort(port) {
    invoke('open_url', { url: 'http://localhost:' + port }).catch(function (err) {
      showToast(errorMessage(err), true);
    });
  }
  function stopServer(server, button) {
    var pid = Number(server.pid);
    if (stopping.has(pid)) return;
    stopping.add(pid);
    button.disabled = true;
    invoke('stop_server', { pid: pid }).then(function () {
      return loadAll();
    }).catch(function (err) {
      showToast(errorMessage(err), true);
    }).then(function () {
      stopping.delete(pid);
      if (button.isConnected) button.disabled = false;
    });
  }
  function handleRefresh() {
    el.refresh.classList.add('spin');
    if (spinTimer) clearTimeout(spinTimer);
    spinTimer = setTimeout(function () { el.refresh.classList.remove('spin'); }, 500);
    loadAll();
  }
  function cycleSort() {
    var index = SORT_MODES.indexOf(sortMode);
    sortMode = SORT_MODES[(index + 1) % SORT_MODES.length];
    saveSortMode();
    updateSortLabel();
    render();
  }
  function handleSearchInput() {
    if (searchTimer) clearTimeout(searchTimer);
    searchTimer = setTimeout(function () {
      query = el.search.value.trim().toLowerCase();
      render();
    }, SEARCH_DEBOUNCE_MS);
  }
  function startPolling() {
    if (pollTimer !== null) return;
    pollTimer = setInterval(function () {
      if (document.visibilityState === 'visible') loadAll();
    }, POLL_MS);
  }
  function stopPolling() {
    if (pollTimer === null) return;
    clearInterval(pollTimer);
    pollTimer = null;
  }
  function handleVisibilityChange() {
    if (document.visibilityState === 'visible') {
      startPolling();
      loadAll();
    } else {
      stopPolling();
    }
  }
  function bindEvents() {
    el.refresh.addEventListener('click', handleRefresh);
    el.quit.addEventListener('click', function () {
      invoke('quit_app').catch(function (err) { showToast(errorMessage(err), true); });
    });
    el.sort.addEventListener('click', cycleSort);
    el.search.addEventListener('input', handleSearchInput);
    document.addEventListener('visibilitychange', handleVisibilityChange);
    document.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape') return;
      if (editing) {
        event.preventDefault();
        cancelEdit();
      } else {
        hideToast();
        invoke('hide_window').catch(function () {});
      }
    });
  }
  function init() {
    cacheDom();
    loadSortMode();
    updateSortLabel();
    bindEvents();
    if (document.visibilityState === 'visible') startPolling();
    loadAll();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
