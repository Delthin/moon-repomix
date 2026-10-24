/* Native-connected editor. No fixtures, external libraries or network origins. */
(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const el = {};
  const OUTPUT = Symbol('complete JSON'); // Cannot collide with a repository filename.
  const TIMEOUT_MS = 65000;
  const names = new Map([['raw', '全文'], ['mixed', '混合'], ['skeleton', '骨架']]);
  const state = {
    session: null, connecting: false, online: false, busy: false,
    directory: '.', profile: 'mixed', snapshot: null, snapshotConfig: null,
    stale: false, packError: '', view: 'processed', active: null, open: [],
    closedFolders: new Set(), bottomOpen: true,
    directoryRequest: 0, browseDirectory: '.', directoryReady: false
  };
  const tabIds = new Map();
  let nextId = 0;
  let treeRows = new Map();
  let rowInfo = new WeakMap();
  let toastTimer;

  const fmt = value => Number(value).toLocaleString('zh-CN');
  const own = (object, key) => Object.hasOwn(object, key);
  const files = () => state.snapshot?.result.document.files || Object.create(null);
  const baselineFiles = () => state.snapshot?.baseline.document.files || Object.create(null);
  const patterns = text => text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const byteLength = text => new TextEncoder().encode(text).length;

  async function apiRequest(path, body) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    const headers = { 'X-Moon-Repomix': 'webui' };
    const options = { headers, signal: controller.signal, mode: 'same-origin' };
    if (body !== undefined) {
      options.method = 'POST';
      headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    try {
      const response = await fetch(path, options);
      if (!response.ok) {
        let detail;
        try { detail = await response.json(); } catch { /* Use the HTTP status for non-JSON errors. */ }
        const error = new Error(detail?.error?.message || `HTTP ${response.status}`);
        error.status = response.status;
        error.code = detail?.error?.code || '';
        throw error;
      }
      return await response.json();
    } catch (error) {
      if (error.name === 'AbortError') {
        throw new Error('请求已超时（65 秒）。后台处理可能仍在继续；超时不代表任务已取消，请稍后重试。');
      }
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }

  function errorMessage(error) {
    if (error.status === 409) return 'Native 引擎忙碌，已有任务正在执行。请稍后重试。';
    if (error.status === 413) return `资源限额超出，请缩小目录或 Include 后重试。${error.message}`;
    return error.message || '无法连接 Native 服务，请检查本机服务后重试。';
  }

  function budgetValue() {
    const value = el.budgetInput.value.trim();
    const number = Number(value);
    return /^\d+$/.test(value) && Number.isInteger(number) && number >= 1 && number <= 2147483647 ? number : null;
  }

  function currentConfig() {
    return {
      directory: state.directory,
      profile: state.profile,
      tokenBudget: budgetValue(),
      includePatterns: patterns(el.includeInput.value),
      keepFull: state.profile === 'mixed' ? patterns(el.keepFullInput.value) : []
    };
  }

  function shellQuote(text) {
    return /^[a-zA-Z0-9_./-]+$/.test(text) ? text : "'" + text.replace(/'/g, "'\\''") + "'";
  }

  function cliCommand() {
    const config = currentConfig();
    if (config.tokenBudget === null) return null;
    const parts = ['moon-repomix', shellQuote(config.directory === '.' ? '.' : './' + config.directory), '--style', 'json', '--full-metadata'];
    if (config.profile !== 'raw') parts.push('--compress');
    config.keepFull.forEach(pattern => parts.push('--keep-full', shellQuote(pattern)));
    config.includePatterns.forEach(pattern => parts.push('--include', shellQuote(pattern)));
    parts.push('--token-budget', String(config.tokenBudget), '-o', 'context.json');
    return parts.join(' ');
  }

  function renderCli() {
    const command = cliCommand();
    el.cliText.textContent = command || '请输入有效的整数预算，以生成 CLI 命令。';
    el.copyCliBtn.disabled = command === null;
  }

  function renderBudget() {
    const budget = budgetValue();
    el.budgetInput.setAttribute('aria-invalid', String(budget === null));
    el.budgetMsg.className = 'bmsg';
    if (budget === null) {
      el.budgetMsg.textContent = '请输入 1–2,147,483,647 之间的整数。';
      el.budgetMsg.classList.add('err');
    } else if (!state.snapshot) {
      el.budgetMsg.textContent = '生成后对照整文计数。';
    } else {
      const tokens = BigInt(state.snapshot.result.report.tokens.total);
      const delta = BigInt(budget) - tokens;
      const prefix = state.stale ? '上次结果对照当前预算：' : '';
      el.budgetMsg.textContent = prefix + (delta < 0n
        ? `超出 ${(-delta).toLocaleString('zh-CN')} tokens · 完整输出保留`
        : `预算内 · 余 ${delta.toLocaleString('zh-CN')} tokens`);
      el.budgetMsg.classList.toggle('warn', delta < 0n);
    }
  }

  function renderResultState() {
    const snapshot = state.snapshot;
    const last = snapshot ? `${snapshot.directory} · ${names.get(snapshot.profile)}` : '';
    let text, kind;
    if (state.busy) {
      kind = 'busy';
      text = 'Native 正在生成，参数已锁定。' + (snapshot ? `下方仍是上次成功结果：${last}。` : '请等待扫描与打包完成。');
    } else if (state.packError) {
      kind = 'error';
      text = '生成失败。' + (snapshot ? `保留上次成功结果：${last}，并非本次输出。` : '暂无成功结果，请修正后重试。');
    } else if (snapshot && state.stale) {
      kind = 'stale';
      text = `旧结果 · ${last} · 配置已调整，请重新生成。`;
    } else if (snapshot) {
      kind = 'fresh';
      text = `最后成功 · ${last} · ${Object.keys(files()).length} 个文件`;
    } else {
      kind = 'idle';
      text = '尚未生成 · 选择目录与策略后，生成上下文。';
    }
    el.resultState.textContent = text;
    el.resultState.dataset.kind = kind;
    el.requestMessage.textContent = state.packError || (state.busy ? '正在执行扫描与打包…' : '');
    el.requestMessage.classList.toggle('error', !!state.packError);
  }

  function configurationChanged() {
    if (state.snapshot) state.stale = true;
    renderResultState();
    renderBudget();
    renderCli();
  }

  function updateControls() {
    el.configFields.disabled = state.busy;
    el.configFields.inert = state.busy;
    el.selectDirBtn.disabled = state.busy || !state.online;
    el.generateBtn.disabled = state.busy || !state.online;
    el.generateBtn.textContent = state.busy ? '正在生成…' : '生成上下文';
    el.editor.setAttribute('aria-busy', String(state.busy));
  }

  async function connect() {
    if (state.connecting) return;
    state.connecting = true;
    el.connectionBtn.disabled = true;
    el.connectionBtn.textContent = '正在连接 Native…';
    el.connectionBtn.dataset.status = 'connecting';
    try {
      const data = await apiRequest('/api/session');
      state.session = data;
      state.online = true;
      el.workspace.textContent = data.workspaceName;
      el.connectionBtn.textContent = `Native 在线 · v${data.version}`;
      el.connectionBtn.dataset.status = 'connected';
      el.connectionDetail.textContent = `127.0.0.1:${data.port} · 只读工作区`;
    } catch (error) {
      state.online = false;
      el.connectionBtn.textContent = '未连接 · 点击重试';
      el.connectionBtn.dataset.status = 'offline';
      el.connectionDetail.textContent = '连接失败：' + errorMessage(error);
    } finally {
      state.connecting = false;
      el.connectionBtn.disabled = false;
      updateControls();
    }
  }

  function showSession() {
    el.sessionDetails.replaceChildren();
    const session = state.session;
    const entries = session ? [
      ['工作区', session.workspaceName], ['版本', session.version], ['端口', session.port],
      ['最多候选文件', fmt(session.limits.maxFiles)],
      ['原始读取上限', fmt(session.limits.maxTotalBytes) + ' 字节'],
      ['响应上限（含对照）', fmt(session.limits.maxOutputBytes) + ' 字节'],
      ['单文件上限', '至多 2 MiB（启动参数可更小）'], ['服务端生成时限', '60 秒']
    ] : [['会话', '尚未连接，请关闭此窗口后点击连接状态重试。']];
    entries.forEach(([label, value]) => {
      const term = document.createElement('dt');
      const detail = document.createElement('dd');
      term.textContent = label;
      detail.textContent = String(value);
      el.sessionDetails.append(term, detail);
    });
    el.limitsDialog.showModal();
  }

  async function loadDirectory(directory, moveFocus = false) {
    const request = ++state.directoryRequest;
    state.browseDirectory = directory;
    state.directoryReady = false;
    el.browseDirectory.textContent = directory;
    el.confirmDirectoryBtn.disabled = true;
    el.goUpBtn.disabled = directory === '.';
    el.retryDirectoryBtn.hidden = true;
    el.directoryMessage.textContent = '正在读取目录…';
    el.dirList.replaceChildren();
    el.dirList.setAttribute('aria-busy', 'true');
    // A clicked child is removed while loading; keep focus inside the dialog.
    if (moveFocus) el.closeDirectoryBtn.focus();
    try {
      const data = await apiRequest('/api/directories', { directory });
      if (request !== state.directoryRequest || !el.directoryDialog.open) return;
      state.browseDirectory = data.directory;
      state.directoryReady = true;
      el.browseDirectory.textContent = data.directory;
      el.goUpBtn.disabled = data.directory === '.';
      el.confirmDirectoryBtn.disabled = false;
      el.directoryMessage.textContent = data.directories.length ? '进入子目录，或使用当前目录。' : '没有可浏览的子目录，可使用当前目录。';
      data.directories.forEach(path => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'dir-item';
        button.textContent = path;
        button.addEventListener('click', () => loadDirectory(path, true));
        el.dirList.append(button);
      });
    } catch (error) {
      if (request !== state.directoryRequest || !el.directoryDialog.open) return;
      el.directoryMessage.textContent = '目录读取失败：' + errorMessage(error);
      el.retryDirectoryBtn.hidden = false;
    } finally {
      if (request === state.directoryRequest) el.dirList.setAttribute('aria-busy', 'false');
    }
  }

  function openDirectory() {
    if (state.busy || !state.online) return;
    el.directoryDialog.showModal();
    loadDirectory(state.directory);
  }

  function changedFile(path) {
    const baseline = baselineFiles();
    return own(baseline, path) && files()[path] !== baseline[path];
  }

  function renderInspector() {
    const data = state.snapshot;
    const report = data.result.report;
    const resultTokens = BigInt(report.tokens.total);
    const rawTokens = BigInt(data.baseline.report.tokens.total);
    const delta = resultTokens - rawTokens;
    const change = delta === 0n ? '相同' : `${delta < 0n ? '减少' : '增加'} ${(delta < 0n ? -delta : delta).toLocaleString('zh-CN')} tokens`;
    el.mTokens.textContent = resultTokens.toLocaleString('zh-CN');
    el.mBytes.textContent = fmt(report.bytes.total);
    el.mFiles.textContent = `${fmt(report.counts.acceptedFiles)} / ${fmt(report.counts.skippedEntries)}`;
    // Compare actual file bodies; metadata.compression may be a per-file array.
    el.mChanged.textContent = `${Object.keys(files()).filter(changedFile).length} / ${Object.keys(files()).length}`;
    el.curSummary.textContent = `较 Raw 整包（${rawTokens.toLocaleString('zh-CN')} tokens）${change}。计数含完整元数据。`;
    el.snapshotLabel.textContent = `${data.directory} · ${names.get(data.profile)} · 请求预算 ${fmt(state.snapshotConfig.tokenBudget)}`;
    const security = report.security;
    el.scanFindings.textContent = `${security.enabled ? '已启用' : '未启用'} · ${fmt(security.findings)} 项命中`;
    el.scanMeta.textContent = `状态 ${security.status} · 跳过 ${fmt(report.counts.skippedEntries)} 项`;
    el.stTok.textContent = `整文 ${resultTokens.toLocaleString('zh-CN')} tokens`;
    el.stScan.textContent = `扫描 ${security.status} · ${fmt(security.findings)} 命中`;
    el.exportInfo.textContent = `最后成功：${data.directory} · ${names.get(data.profile)} · ${fmt(report.bytes.total)} 字节`;
  }

  async function generate() {
    if (state.busy || document.querySelector('dialog[open]')) return;
    if (!state.online) { toast('请先连接 Native 服务。'); return; }
    const config = currentConfig();
    if (config.tokenBudget === null) {
      renderBudget();
      el.budgetInput.focus();
      return;
    }
    const allPatterns = [...config.includePatterns, ...config.keepFull];
    if (allPatterns.length > 64 || allPatterns.some(pattern => byteLength(pattern) > 1024)) {
      toast('Include 与生效的 Keep full 合计最多 64 条，每条最多 1,024 个 UTF-8 字节。');
      return;
    }
    if (byteLength(JSON.stringify(config)) > 65536) {
      toast('请求超过 64 KiB，请减少文件规则。');
      return;
    }
    const initiatingControl = document.activeElement;
    state.busy = true;
    state.packError = '';
    updateControls();
    renderResultState();
    try {
      const data = await apiRequest('/api/pack', config);
      // Only successful responses replace this snapshot. No output is sourced from live controls.
      state.snapshot = data;
      state.snapshotConfig = config;
      state.stale = false;
      const paths = Object.keys(files()).sort();
      const validKey = key => key === OUTPUT || own(files(), key);
      state.open = state.open.filter(validKey);
      if (!paths.length) {
        state.open = [OUTPUT];
        state.active = OUTPUT;
      } else {
        if (state.active === null || !validKey(state.active)) state.active = paths[0];
        if (!state.open.includes(state.active)) state.open.push(state.active);
      }
      state.closedFolders.clear();
      el.fileSearch.value = '';
      el.fileSearch.disabled = false;
      el.treeOutput.disabled = false;
      el.copyJsonBtn.disabled = false;
      el.exportBtn.disabled = false;
      renderTree();
      renderTabs();
      renderCode();
      renderInspector();
      toast(paths.length ? '上下文已生成。' : '生成成功，本次没有入选文件；完整 JSON 已更新。');
    } catch (error) {
      state.packError = errorMessage(error);
      if (state.snapshot) state.stale = true;
    } finally {
      state.busy = false;
      updateControls();
      renderResultState();
      renderBudget();
      // Restore a control blurred by disabling/inert, without stealing focus
      // from someone browsing the previous snapshot during the request.
      if (document.activeElement === document.body && initiatingControl?.isConnected &&
          !initiatingControl.disabled && !initiatingControl.closest('[inert]')) {
        initiatingControl.focus();
      }
    }
  }

  function treeModel(paths) {
    const root = { dirs: new Map(), files: [] };
    paths.forEach(path => {
      const parts = path.split('/');
      let node = root;
      for (let i = 0; i < parts.length - 1; i++) {
        const name = parts[i];
        if (!node.dirs.has(name)) node.dirs.set(name, { id: parts.slice(0, i + 1).join('/'), name, dirs: new Map(), files: [] });
        node = node.dirs.get(name);
      }
      node.files.push(path);
    });
    return root;
  }

  function visibleRows() {
    return Array.from(el.tree.querySelectorAll('.tree-row')).filter(row => !row.closest('[hidden]'));
  }

  function focusRow(row) {
    el.tree.querySelectorAll('.tree-row').forEach(button => { button.tabIndex = button === row ? 0 : -1; });
    row.focus();
  }

  function expandFolder(row, expanded) {
    const info = rowInfo.get(row);
    if (!info?.group) return;
    if (!expanded && info.group.contains(document.activeElement)) focusRow(row);
    info.group.hidden = !expanded;
    row.setAttribute('aria-expanded', String(expanded));
    if (expanded) state.closedFolders.delete(info.folder);
    else state.closedFolders.add(info.folder);
    // A hidden selected descendant must not be the only tabbable tree item.
    const tabbable = el.tree.querySelector('.tree-row[tabindex="0"]');
    if (!tabbable || tabbable.closest('[hidden]')) {
      el.tree.querySelectorAll('.tree-row').forEach(button => { button.tabIndex = button === row ? 0 : -1; });
    }
  }

  function renderTree() {
    el.tree.replaceChildren();
    treeRows = new Map();
    rowInfo = new WeakMap();
    const paths = Object.keys(files()).sort();
    const query = el.fileSearch.value.trim().toLocaleLowerCase();
    const matching = paths.filter(path => path.toLocaleLowerCase().includes(query));
    el.treeCount.textContent = `${paths.length} 个文件`;
    el.treeEmpty.hidden = matching.length > 0;
    el.treeEmpty.textContent = paths.length ? '没有匹配的文件，请调整搜索。' : '本次没有入选文件，请调整目录或 Include 后重新生成。';
    function walk(node, container, depth, parentRow) {
      node.dirs.forEach(directory => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'tree-row is-dir';
        row.setAttribute('role', 'treeitem');
        row.setAttribute('aria-level', String(depth + 1));
        row.style.paddingLeft = `${10 + depth * 14}px`;
        row.tabIndex = -1;
        const arrow = document.createElement('span');
        arrow.className = 'chev';
        arrow.innerHTML = '<svg width="9" height="9" viewBox="0 0 10 10" fill="none"><path d="m3.5 2 3 3-3 3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        arrow.setAttribute('aria-hidden', 'true');
        const label = document.createElement('span');
        label.className = 'fname';
        label.textContent = directory.name;
        const group = document.createElement('div');
        group.setAttribute('role', 'group');
        group.id = `folder-group-${++nextId}`;
        const expanded = !!query || !state.closedFolders.has(directory.id);
        group.hidden = !expanded;
        row.setAttribute('aria-expanded', String(expanded));
        row.setAttribute('aria-controls', group.id);
        rowInfo.set(row, { folder: directory.id, parent: parentRow, group });
        row.append(arrow, label);
        row.addEventListener('click', () => {
          expandFolder(row, row.getAttribute('aria-expanded') !== 'true');
          focusRow(row);
        });
        container.append(row, group);
        walk(directory, group, depth + 1, row);
      });
      node.files.forEach(path => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'tree-row';
        row.setAttribute('role', 'treeitem');
        row.setAttribute('aria-level', String(depth + 1));
        row.tabIndex = -1;
        row.style.paddingLeft = `${26 + depth * 14}px`;
        row.title = path;
        const label = document.createElement('span');
        label.className = 'fname';
        label.textContent = path.split('/').pop();
        const dot = document.createElement('span');
        const changed = changedFile(path);
        dot.className = `dot ${changed ? 'dot-skel' : 'dot-full'}`;
        dot.setAttribute('aria-hidden', 'true');
        row.setAttribute('aria-label', `${path} · ${own(baselineFiles(), path) ? (changed ? '正文变化' : '正文相同') : '无全文对照'}`);
        row.append(label, dot);
        treeRows.set(path, row);
        rowInfo.set(row, { key: path, parent: parentRow });
        row.addEventListener('click', () => { selectKey(path); focusRow(row); });
        container.append(row);
      });
    }
    walk(treeModel(matching), el.tree, 0, null);
    updateTreeSelection();
    const selected = treeRows.get(state.active);
    const first = selected && !selected.closest('[hidden]') ? selected : visibleRows()[0];
    if (first) first.tabIndex = 0;
  }

  function updateTreeSelection() {
    treeRows.forEach((row, key) => row.setAttribute('aria-selected', String(key === state.active)));
    const outputSelected = state.active === OUTPUT;
    el.treeOutput.classList.toggle('sel', outputSelected);
    if (outputSelected) el.treeOutput.setAttribute('aria-current', 'true');
    else el.treeOutput.removeAttribute('aria-current');
  }

  function tabId(key) {
    if (!tabIds.has(key)) tabIds.set(key, `editor-tab-${++nextId}`);
    return tabIds.get(key);
  }

  function keyName(key) { return key === OUTPUT ? 'context.json' : key.split('/').pop(); }

  function renderTabs() {
    el.tabbar.replaceChildren();
    state.open.forEach(key => {
      const selected = key === state.active;
      const wrapper = document.createElement('div');
      wrapper.className = `tab${selected ? ' sel' : ''}${key === OUTPUT ? ' is-out' : ''}`;
      wrapper.setAttribute('role', 'presentation');
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'tab-btn';
      button.id = tabId(key);
      button.title = key === OUTPUT ? '完整 Native JSON' : key;
      button.setAttribute('role', 'tab');
      button.setAttribute('aria-controls', 'codepane');
      button.setAttribute('aria-selected', String(selected));
      button.tabIndex = selected ? 0 : -1;
      const name = document.createElement('span');
      name.className = 'tname';
      name.textContent = keyName(key);
      button.append(name);
      button.addEventListener('click', () => { selectKey(key); focusActiveTab(); });
      button.addEventListener('keydown', event => handleTabKey(event, key));
      const close = document.createElement('button');
      close.type = 'button';
      close.className = 'tab-x';
      close.textContent = '×';
      close.setAttribute('aria-label', `关闭 ${keyName(key)}`);
      close.addEventListener('click', () => closeTab(key));
      wrapper.append(button, close);
      el.tabbar.append(wrapper);
    });
  }

  function focusActiveTab() {
    const tab = state.active !== null ? document.getElementById(tabId(state.active)) : null;
    (tab || el.treeOutput).focus();
    if (tab) tab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }

  function handleTabKey(event, key) {
    const index = state.open.indexOf(key);
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % state.open.length;
    else if (event.key === 'ArrowLeft') next = (index - 1 + state.open.length) % state.open.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = state.open.length - 1;
    else if (event.key === 'Delete') { event.preventDefault(); closeTab(key); return; }
    else return;
    event.preventDefault();
    selectKey(state.open[next]);
    focusActiveTab();
  }

  function selectKey(key) {
    if (!state.snapshot || (key !== OUTPUT && !own(files(), key))) return;
    if (!state.open.includes(key)) state.open.push(key);
    state.active = key;
    updateTreeSelection();
    renderTabs();
    renderCode();
  }

  function closeTab(key) {
    const index = state.open.indexOf(key);
    if (index < 0) return;
    state.open.splice(index, 1);
    if (state.active === key) state.active = state.open[Math.max(0, index - 1)] ?? null;
    updateTreeSelection();
    renderTabs();
    renderCode();
    focusActiveTab();
  }

  // Tokenization preserves every character. Dynamic HTML is only escaped text;
  // filenames and paths never enter HTML strings, selectors or identifier encodings.
  const keywords = new Set(('fn pub priv let mut struct enum extend suberror derive match if else for while loop return raise ignore is in use import test true false async await where when guard export function const var new type interface impl package').split(' '));
  const sourceRE = /(\/\/.*)|(\/\*.*?\*\/)|("(?:[^"\\]|\\.)*")|('(?:[^'\\]|\\.)*')|(`(?:[^`\\]|\\.)*`)|(@[A-Za-z_][A-Za-z0-9_]*)|(#[A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*)|(\b\d[\d_]*(?:\.[\d_]+)?L?\b)/g;
  const jsonRE = /"(?:[^"\\]|\\.)*"|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\btrue\b|\bfalse\b|\bnull\b/g;
  function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function highlightLine(line, json) {
    const regex = json ? jsonRE : sourceRE;
    regex.lastIndex = 0;
    let html = '', last = 0, match;
    while ((match = regex.exec(line)) !== null) {
      html += escapeHtml(line.slice(last, match.index));
      const token = match[0];
      let kind;
      if (json) {
        kind = token.startsWith('"') ? (/^\s*:/.test(line.slice(match.index + token.length)) ? 'k' : 's') : (/^(true|false|null)$/.test(token) ? 'kw' : 'n');
      } else if (match[1] || match[2]) kind = 'cmt';
      else if (match[3] || match[4] || match[5]) kind = 'str';
      else if (match[6]) kind = 'type';
      else if (match[7]) kind = 'meta';
      else if (match[9]) kind = 'num';
      else if (keywords.has(token)) kind = 'kw';
      else if (/^[A-Z]/.test(token)) kind = 'type';
      const escaped = escapeHtml(token);
      html += kind ? `<span class="hl-${kind}">${escaped}</span>` : escaped;
      last = match.index + token.length;
    }
    return html + escapeHtml(line.slice(last));
  }

  function currentText() {
    if (!state.snapshot || state.active === null) return null;
    if (state.active === OUTPUT) return state.snapshot.result.serialized;
    const map = state.view === 'original' ? baselineFiles() : files();
    return own(map, state.active) ? map[state.active] : null;
  }

  function renderCode() {
    const text = currentText();
    const output = state.active === OUTPUT;
    const hasText = text !== null;
    el.code.replaceChildren();
    el.code.hidden = !hasText;
    el.empty.hidden = hasText;
    el.copyCodeBtn.disabled = !hasText;
    el.copyCodeBtn.textContent = output ? '复制 JSON' : '复制正文';
    el.viewSeg.hidden = state.active === null || output;
    el.chMode.hidden = !hasText;
    el.chPath.textContent = state.active === null ? '未打开文件' : (output ? 'context.json' : state.active);
    el.chPath.title = el.chPath.textContent;
    el.chInfo.textContent = '';
    el.codepane.removeAttribute('aria-labelledby');
    el.codepane.setAttribute('role', state.active === null ? 'region' : 'tabpanel');
    if (state.active !== null) el.codepane.setAttribute('aria-labelledby', tabId(state.active));
    el.openOutputBtn.hidden = !state.snapshot;
    if (!hasText) {
      if (!state.snapshot) {
        el.emptyTitle.textContent = '把仓库整理成可读的上下文';
        el.emptyText.textContent = '选择授权目录，设定策略，再点击「生成上下文」。代码与完整 JSON 将显示在这里。';
      } else if (state.active !== null && state.view === 'original') {
        el.emptyTitle.textContent = '独立 Raw 对照中没有此文件';
        el.emptyText.textContent = '两次打包是独立的安全读取。切换「处理后」查看本次输出，或打开完整 JSON。';
      } else {
        el.emptyTitle.textContent = Object.keys(files()).length ? '没有打开的文件' : '本次没有入选文件';
        el.emptyText.textContent = '从左侧选择文件，或打开最后成功结果的完整 JSON。';
      }
    } else {
      const json = output || /\.json$/i.test(state.active);
      el.code.innerHTML = text.split('\n').map((line, index) => `<div class="cl"><span class="ln" aria-hidden="true">${index + 1}</span><span class="lc">${highlightLine(line, json)}</span></div>`).join('');
      el.chMode.textContent = output ? '完整 JSON' : state.view === 'original' ? 'Raw 原文' : own(baselineFiles(), state.active) ? (changedFile(state.active) ? '正文变化' : '正文相同') : '无全文对照';
      el.chMode.className = `chip${output || (!changedFile(state.active) && state.view === 'processed') ? ' mint' : ''}`;
      el.chInfo.textContent = output ? `${fmt(state.snapshot.result.report.bytes.total)} 字节 · Native 原始序列化` : `${fmt(text === '' ? 0 : text.split('\n').length)} 行 · ${fmt(byteLength(text))} 字节`;
    }
    el.codepane.scrollTop = 0;
    el.codepane.scrollLeft = 0;
    el.stFile.textContent = state.active === null ? '未打开文件' : `${names.get(state.snapshot.profile)} · ${keyName(state.active)}`;
  }

  function toast(message) {
    clearTimeout(toastTimer);
    el.toast.textContent = message;
    el.toast.hidden = false;
    toastTimer = setTimeout(() => { el.toast.hidden = true; }, 3600);
  }

  async function copyText(text) {
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      let timer;
      try {
        await Promise.race([
          navigator.clipboard.writeText(text),
          new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Clipboard pending')), 1200); })
        ]);
      } finally { clearTimeout(timer); }
      toast('已复制。');
    } catch {
      el.copyText.value = text;
      el.copyDialog.showModal();
      el.copyText.focus();
      el.copyText.select();
    }
  }

  function download() {
    if (!state.snapshot) return;
    try {
      // Do not stringify document, normalize line endings or add a BOM.
      const blob = new Blob([state.snapshot.result.serialized], { type: 'application/json;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `context-${state.snapshot.profile}.json`;
      document.body.append(link);
      try { link.click(); } finally {
        link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      }
      toast('已开始下载最后成功结果的完整 JSON。');
    } catch (error) { toast('下载失败：' + errorMessage(error)); }
  }

  function bindEvents() {
    el.connectionBtn.addEventListener('click', connect);
    el.limitsBtn.addEventListener('click', showSession);
    el.closeLimitsBtn.addEventListener('click', () => el.limitsDialog.close());
    el.limitsDialog.addEventListener('close', () => el.limitsBtn.focus());
    el.selectDirBtn.addEventListener('click', openDirectory);
    [el.closeDirectoryBtn, el.cancelDirectoryBtn].forEach(button => button.addEventListener('click', () => el.directoryDialog.close()));
    el.directoryDialog.addEventListener('close', () => {
      ++state.directoryRequest; // Closing/Escape invalidates every outstanding directory response.
      state.directoryReady = false;
      el.confirmDirectoryBtn.disabled = true;
      el.selectDirBtn.focus();
    });
    el.goUpBtn.addEventListener('click', () => {
      const parts = state.browseDirectory.split('/');
      parts.pop();
      loadDirectory(parts.join('/') || '.', true);
    });
    el.retryDirectoryBtn.addEventListener('click', () => loadDirectory(state.browseDirectory, true));
    el.confirmDirectoryBtn.addEventListener('click', () => {
      if (!state.directoryReady || state.busy) return;
      const previous = state.directory;
      state.directory = state.browseDirectory;
      el.currentDirectory.textContent = state.directory;
      el.directoryDialog.close();
      if (previous !== state.directory) configurationChanged();
    });
    document.querySelectorAll('input[name="profile"]').forEach(input => {
      input.addEventListener('change', () => {
        state.profile = input.value;
        el.keepFullGroup.hidden = state.profile !== 'mixed';
        configurationChanged();
      });
    });
    [el.budgetInput, el.includeInput, el.keepFullInput].forEach(input => input.addEventListener('input', configurationChanged));
    document.querySelectorAll('input[name="viewmode"]').forEach(input => input.addEventListener('change', () => { state.view = input.value; renderCode(); }));
    el.generateBtn.addEventListener('click', generate);
    window.addEventListener('keydown', event => {
      if ((event.ctrlKey || event.metaKey) && event.key === 'Enter' && !document.querySelector('dialog[open]')) {
        event.preventDefault();
        generate();
      }
    });
    el.treeOutput.addEventListener('click', () => selectKey(OUTPUT));
    el.openOutputBtn.addEventListener('click', () => { selectKey(OUTPUT); focusActiveTab(); });
    el.fileSearch.addEventListener('input', renderTree);
    el.tree.addEventListener('keydown', event => {
      const row = event.target.closest('.tree-row');
      if (!row) return;
      const visible = visibleRows();
      const index = visible.indexOf(row);
      const info = rowInfo.get(row);
      let next;
      if (event.key === 'ArrowDown') next = visible[Math.min(index + 1, visible.length - 1)];
      else if (event.key === 'ArrowUp') next = visible[Math.max(index - 1, 0)];
      else if (event.key === 'Home') next = visible[0];
      else if (event.key === 'End') next = visible[visible.length - 1];
      else if (event.key === 'ArrowRight' && info.group) {
        if (info.group.hidden) expandFolder(row, true);
        else next = info.group.querySelector('.tree-row');
      } else if (event.key === 'ArrowLeft') {
        if (info.group && !info.group.hidden) expandFolder(row, false);
        else next = info.parent;
      } else return;
      event.preventDefault();
      if (next) focusRow(next);
    });
    el.copyCliBtn.addEventListener('click', () => { const command = cliCommand(); if (command !== null) copyText(command); });
    el.copyJsonBtn.addEventListener('click', () => { if (state.snapshot) copyText(state.snapshot.result.serialized); });
    el.copyCodeBtn.addEventListener('click', () => { const text = currentText(); if (text !== null) copyText(text); });
    el.closeCopyBtn.addEventListener('click', () => el.copyDialog.close());
    el.exportBtn.addEventListener('click', download);
    el.bottomToggle.addEventListener('click', () => {
      state.bottomOpen = !state.bottomOpen;
      if (!state.bottomOpen && el.bottomPanel.contains(document.activeElement)) el.bottomToggle.focus();
      el.bottomPanel.classList.toggle('closed', !state.bottomOpen);
      el.bottomPanel.inert = !state.bottomOpen;
      el.bottomPanel.setAttribute('aria-hidden', String(!state.bottomOpen));
      el.bottomToggle.setAttribute('aria-expanded', String(state.bottomOpen));
      // The chevron follows aria-expanded; the accessible name stays stable.
    });
  }

  function init() {
    const ids = ['workspace', 'connectionBtn', 'connectionDetail', 'limitsBtn', 'configFields', 'selectDirBtn', 'currentDirectory', 'keepFullGroup', 'includeInput', 'keepFullInput', 'budgetInput', 'budgetMsg', 'generateBtn', 'requestMessage', 'resultState', 'treeOutput', 'tree', 'treeCount', 'treeEmpty', 'fileSearch', 'tabbar', 'codepane', 'code', 'empty', 'emptyTitle', 'emptyText', 'openOutputBtn', 'chPath', 'chMode', 'chInfo', 'viewSeg', 'copyCodeBtn', 'snapshotLabel', 'mTokens', 'mBytes', 'mFiles', 'mChanged', 'curSummary', 'scanFindings', 'scanMeta', 'stFile', 'stTok', 'stScan', 'cliText', 'copyCliBtn', 'copyJsonBtn', 'exportBtn', 'exportInfo', 'bottomPanel', 'bottomToggle', 'directoryDialog', 'closeDirectoryBtn', 'cancelDirectoryBtn', 'confirmDirectoryBtn', 'goUpBtn', 'browseDirectory', 'directoryMessage', 'dirList', 'retryDirectoryBtn', 'limitsDialog', 'closeLimitsBtn', 'sessionDetails', 'copyDialog', 'closeCopyBtn', 'copyText', 'toast'];
    ids.forEach(id => { el[id] = $(id); });
    el.editor = document.querySelector('.editor');
    bindEvents();
    renderCli();
    renderBudget();
    connect();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
