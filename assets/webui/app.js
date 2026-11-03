/* Native-connected editor. No fixtures, external libraries or network origins. */
(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const el = {};
  const OUTPUT = Symbol('complete JSON'); // Cannot collide with a repository filename.
  const AUDIT = Symbol('selection audit');
  const TIMEOUT_MS = 65000;
  const INT_MAX = 2147483647;
  const names = new Map([['raw', '全文'], ['mixed', '混合'], ['skeleton', '骨架'], ['task', '任务预算'], ['code', '代码补读']]);
  const state = {
    session: null, connecting: false, online: false, busy: false, presetBusy: false,
    directory: '.', profile: 'mixed', operation: 'pack', snapshot: null, snapshotConfig: null,
    codeSession: null, latestAudit: null,
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
  const files = () => state.snapshot?.uiFiles || state.snapshot?.result.document?.files || Object.create(null);
  const baselineFiles = () => state.snapshot?.baseline?.document?.files || Object.create(null);
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
        const timeout = new Error('请求已超时（65 秒），服务器提交状态未知。旧结果保留；代码补读请重新开始会话，不要盲目续读。');
        timeout.outcomeUnknown = true;
        throw timeout;
      }
      if (error.name === 'TypeError' || error.name === 'SyntaxError') error.outcomeUnknown = true;
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }

  function errorMessage(error) {
    if (error.outcomeUnknown && error.name !== 'Error') return '连接中断，服务器提交状态未知；请重新开始代码会话。旧成功结果保留。';
    if (error.status === 409 && /busy/.test(error.code || '')) return 'Native 引擎忙碌，已有任务正在执行。请稍后重试。';
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
    const parts = ['moon-repomix'];
    if (config.directory !== '.') parts.push(shellQuote('./' + config.directory));
    parts.push('-f', 'json', '--full-metadata');
    if (config.profile !== 'raw') parts.push('--compress');
    config.keepFull.forEach(pattern => parts.push('--keep-full', shellQuote(pattern)));
    config.includePatterns.forEach(pattern => parts.push('--include', shellQuote(pattern)));
    parts.push('--budget', String(config.tokenBudget), '-o', 'context.json');
    return parts.join(' ');
  }

  function renderCli() {
    el.commandLabel.textContent = state.operation === 'pack' ? 'CLI' : '请求 JSON';
    el.copyCliBtn.textContent = state.operation === 'pack' ? '复制命令' : '复制请求';
    try {
      const command = state.operation === 'pack' ? cliCommand() : JSON.stringify(portableRequest(false));
      el.cliText.textContent = command || '请输入有效的整数预算，以生成 CLI 命令。';
      el.copyCliBtn.disabled = command === null;
    } catch (error) {
      el.cliText.textContent = error.message;
      el.copyCliBtn.disabled = true;
    }
  }

  function renderBudget() {
    const budget = activeBudget();
    el.budgetInput.setAttribute('aria-invalid', String(budget === null));
    el.budgetMsg.className = 'bmsg';
    if (budget === null) {
      el.budgetMsg.textContent = '请输入 1–2,147,483,647 之间的整数。';
      el.budgetMsg.classList.add('err');
    } else if (state.operation === 'code' && state.codeSession?.directory === state.directory) {
      el.budgetMsg.textContent = `当前会话剩余 ${fmt(state.codeSession.remaining)} / ${fmt(state.codeSession.limit)} tokens；输入预算仅用于新会话。`;
    } else if (!state.snapshot) {
      el.budgetMsg.textContent = state.operation === 'pack' ? '生成后对照整文计数。' : '按完整正文精确计数，成功结果受硬上限约束。';
    } else {
      const tokens = BigInt(state.snapshot.result.report.tokens.total);
      const delta = BigInt(budget) - tokens;
      const prefix = state.stale ? '上次结果对照当前预算：' : '';
      el.budgetMsg.textContent = prefix + (delta < 0n
        ? `超出 ${(-delta).toLocaleString('zh-CN')} tokens${state.snapshot.operation === 'pack' ? ' · 完整输出保留' : ' · 仅为旧结果对照'}`
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
      text = 'Native 正在处理，参数已锁定。' + (snapshot ? `下方仍是上次成功结果：${last}。` : '请等待完整原文扫描与处理完成。');
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
    el.requestMessage.textContent = state.packError || (state.busy ? '正在执行扫描与处理…' : '');
    el.requestMessage.classList.toggle('error', !!state.packError);
  }

  function configurationChanged() {
    if (state.snapshot) state.stale = true;
    renderResultState();
    renderBudget();
    renderCli();
    renderCodeSession();
  }

  function updateControls() {
    const locked = state.busy || state.presetBusy;
    el.configFields.disabled = locked;
    el.configFields.inert = locked;
    el.selectDirBtn.disabled = locked || !state.online;
    el.generateBtn.disabled = locked || !state.online;
    el.importRequestBtn.disabled = locked || !state.online;
    el.saveRequestBtn.disabled = locked || !state.online || state.operation === 'pack';
    el.generateBtn.textContent = state.presetBusy ? '正在校验配置…' : state.busy ? '正在处理…' : state.operation === 'task' ? '生成预算内上下文' : state.operation === 'code' ? '开始新补读会话' : '生成上下文';
    el.budgetInput.disabled = locked || (state.operation === 'task' && el.taskAdvanced.checked);
    el.editor.setAttribute('aria-busy', String(state.busy));
    renderCodeSession();
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
      const extensions = data.context?.code?.definitionExtensions;
      el.definitionHint.textContent = Array.isArray(extensions)
        ? `符号与目录支持 ${extensions.join(' / ')}；其他 UTF-8 文件可选全文或行范围。`
        : '当前服务未提供符号读取类型，请查阅本机版本文档。';
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
      ['整体响应上限', fmt(session.limits.maxOutputBytes) + ' 字节'],
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
    if (!data) return;
    const report = data.result.report;
    const resultTokens = BigInt(report.tokens.total);
    el.mTokens.textContent = resultTokens.toLocaleString('zh-CN');
    el.mBytes.textContent = fmt(report.bytes.total);
    el.mFiles.textContent = report.counts.skippedEntries == null ? fmt(report.counts.acceptedFiles) : `${fmt(report.counts.acceptedFiles)} / ${fmt(report.counts.skippedEntries)}`;
    el.changedMetric.hidden = data.operation !== 'pack';
    if (data.baseline) {
      const rawTokens = BigInt(data.baseline.report.tokens.total);
      const delta = resultTokens - rawTokens;
      const change = delta === 0n ? '相同' : `${delta < 0n ? '减少' : '增加'} ${(delta < 0n ? -delta : delta).toLocaleString('zh-CN')} tokens`;
      el.mChanged.textContent = `${Object.keys(files()).filter(changedFile).length} / ${Object.keys(files()).length}`;
      el.curSummary.textContent = `较 Raw 整包（${rawTokens.toLocaleString('zh-CN')} tokens）${change}。计数含完整元数据。`;
    } else {
      el.curSummary.textContent = data.operation === 'task' ? '正文受完整文档硬预算约束；独立审计另计，不含在正文额度内。' : '代码与嵌入审计已计入本轮正文；累计消费见补读会话。';
    }
    const budget = report.budget?.limit ?? state.snapshotConfig?.tokenBudget ?? state.snapshotConfig?.spec?.maxTokens;
    el.snapshotLabel.textContent = `${data.directory} · ${names.get(data.profile)}${budget == null ? '' : ` · 本轮上限 ${fmt(budget)}`}`;
    const security = report.security;
    const findings = security.findings == null ? '' : ` · ${fmt(security.findings)} 项命中`;
    el.scanFindings.textContent = `${security.enabled ? '已启用' : '未启用'}${findings}`;
    el.scanMeta.textContent = `状态 ${security.status}${report.counts.skippedEntries == null ? ' · 返回范围之前已扫描完整源文件' : ` · 跳过 ${fmt(report.counts.skippedEntries)} 项`}`;
    el.stTok.textContent = `整文 ${resultTokens.toLocaleString('zh-CN')} tokens`;
    el.stScan.textContent = `扫描 ${security.status}${findings}`;
    el.exportInfo.textContent = `最后成功：${data.directory} · ${names.get(data.profile)} · ${fmt(report.bytes.total)} 字节`;
  }

  async function generatePack() {
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
      state.codeSession = null;
      state.latestAudit = null;
      data.operation = 'pack';
      acceptSnapshot(data, config);
      const paths = Object.keys(files());
      toast(paths.length ? '上下文已生成。' : '生成成功，本次没有入选文件；完整 JSON 已更新。');
    } catch (error) {
      state.packError = errorMessage(error);
      if (error.outcomeUnknown) state.codeSession = null;
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
    el.treeEmpty.textContent = paths.length ? '没有匹配的文件，请调整搜索。' : state.snapshot ? '本次没有入选文件，请调整目录或请求。' : '生成成功后在此浏览实际返回的文件。';
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
        row.setAttribute('aria-label', `${path} · ${own(baselineFiles(), path) ? (changed ? '正文变化' : '正文相同') : '实际返回'}`);
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
    const auditSelected = state.active === AUDIT;
    el.treeAudit.classList.toggle('sel', auditSelected);
    if (auditSelected) el.treeAudit.setAttribute('aria-current', 'true');
    else el.treeAudit.removeAttribute('aria-current');
  }

  function tabId(key) {
    if (!tabIds.has(key)) tabIds.set(key, `editor-tab-${++nextId}`);
    return tabIds.get(key);
  }

  function keyName(key) { return key === OUTPUT ? 'context.json' : key === AUDIT ? 'audit.json' : key.split('/').pop(); }

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
      button.title = key === OUTPUT ? '最后成功的完整 Native JSON' : key === AUDIT ? '本次请求的完整审计' : key;
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
    if (key === AUDIT ? !state.latestAudit : !state.snapshot || (key !== OUTPUT && !own(files(), key))) return;
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
    if (state.active === AUDIT) return state.latestAudit?.serialized ?? null;
    if (!state.snapshot || state.active === null) return null;
    if (state.active === OUTPUT) return state.snapshot.result.serialized;
    const map = state.snapshot.operation === 'pack' && state.view === 'original' ? baselineFiles() : files();
    return own(map, state.active) ? map[state.active] : null;
  }

  function appendSourceLines(text, start = 1, json = false, end = Infinity) {
    const block = document.createElement('div');
    block.innerHTML = text.split('\n').slice(0, end - start + 1).map((line, index) => `<div class="cl"><span class="ln" aria-hidden="true">${start + index}</span><span class="lc">${highlightLine(line, json)}</span></div>`).join('');
    el.code.append(block);
  }

  function renderCode() {
    const text = currentText();
    const output = state.active === OUTPUT;
    const audit = state.active === AUDIT;
    const entry = state.snapshot?.codeEntries?.get(state.active);
    const hasText = text !== null;
    el.code.replaceChildren();
    el.code.hidden = !hasText;
    el.empty.hidden = hasText;
    el.copyCodeBtn.disabled = !hasText;
    el.copyCodeBtn.textContent = output || audit ? '复制 JSON' : entry && entry.mode !== 'full' ? '复制片段 JSON' : '复制正文';
    el.viewSeg.hidden = state.active === null || output || audit || state.snapshot?.operation !== 'pack';
    el.chMode.hidden = !hasText;
    el.chPath.textContent = state.active === null ? '未打开文件' : keyName(state.active);
    el.chPath.title = state.active === null || typeof state.active === 'symbol' ? el.chPath.textContent : state.active;
    el.chInfo.textContent = '';
    el.codepane.removeAttribute('aria-labelledby');
    el.codepane.setAttribute('role', state.active === null ? 'region' : 'tabpanel');
    if (state.active !== null) el.codepane.setAttribute('aria-labelledby', tabId(state.active));
    el.openOutputBtn.hidden = !state.snapshot;
    if (!hasText) {
      if (!state.snapshot) {
        el.emptyTitle.textContent = '选择需要交给模型的内容';
        el.emptyText.textContent = '普通打包整理目录；任务预算挑选文件；代码补读按范围取得实现。所有内容由本机 Native 返回。';
      } else if (state.active !== null && state.view === 'original' && state.snapshot.operation === 'pack') {
        el.emptyTitle.textContent = '独立 Raw 对照中没有此文件';
        el.emptyText.textContent = '两次打包是独立的安全读取。切换「处理后」查看本次输出，或打开完整 JSON。';
      } else {
        el.emptyTitle.textContent = Object.keys(files()).length ? '没有打开的文件' : '本次没有入选文件';
        el.emptyText.textContent = '从左侧选择实际返回的文件，或打开最后成功的完整 JSON。';
      }
    } else if (entry?.mode === 'ranges' && !output && !audit) {
      for (const fragment of entry.fragments) {
        const heading = document.createElement('div');
        heading.className = 'fragment-head';
        heading.textContent = `源文件第 ${fragment.startLine}–${fragment.endLine} 行 · 独立片段`;
        el.code.append(heading);
        appendSourceLines(fragment.text, fragment.startLine, false, fragment.endLine);
      }
      el.chMode.textContent = '精确行片段';
      el.chInfo.textContent = `${entry.fragments.length} 段 · 复制保留行范围的 JSON`;
    } else if (entry?.mode === 'outline' && !output && !audit) {
      for (const definition of entry.definitions) {
        const row = document.createElement('div'); row.className = 'outline-row';
        const name = document.createElement('span'); name.textContent = definition.qualifiedName || definition.name;
        const range = document.createElement('span'); range.textContent = `${definition.startLine}–${definition.endLine} 行`;
        row.append(name, range); el.code.append(row);
      }
      if (!entry.definitions.length) {
        const note = document.createElement('div'); note.className = 'fragment-head'; note.textContent = '此文件没有可返回的定义。'; el.code.append(note);
      }
      el.chMode.textContent = '符号目录';
      el.chInfo.textContent = `${entry.definitions.length} 个定义 · 未请求源码正文`;
    } else {
      appendSourceLines(text, 1, output || audit || /\.json$/i.test(String(state.active)));
      el.chMode.textContent = audit ? (state.latestAudit.failed ? '本次失败审计' : '本次选择审计') : output ? '完整 JSON' : state.snapshot.operation !== 'pack' ? '实际返回正文' : state.view === 'original' ? 'Raw 原文' : changedFile(state.active) ? '正文变化' : '正文相同';
      el.chInfo.textContent = output ? `${fmt(state.snapshot.result.report.bytes.total)} 字节 · Native 原始序列化` : audit ? `${fmt(state.latestAudit.bytes)} 字节 · ${state.latestAudit.includedInDocument ? '已包含在本轮正文' : '独立于正文预算'}` : `${fmt(text === '' ? 0 : text.split('\n').length)} 行 · ${fmt(byteLength(text))} 字节`;
    }
    el.chMode.className = 'chip mint';
    el.codepane.scrollTop = 0;
    el.codepane.scrollLeft = 0;
    el.stFile.textContent = state.active === null ? '未打开文件' : `${audit ? '本次审计' : names.get(state.snapshot.profile)} · ${keyName(state.active)}`;
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
      if (previous !== state.directory) {
        state.codeSession = null;
        configurationChanged();
      }
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
    el.copyCliBtn.addEventListener('click', () => {
      try { const command = state.operation === 'pack' ? cliCommand() : JSON.stringify(portableRequest(false)); if (command !== null) copyText(command); }
      catch (error) { toast(error.message); }
    });
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

  // Native context adapters extend the existing workbench.
  let taskSequence = 0;
  function field(labelText, control, wide = false) {
    const label = document.createElement('label');
    label.className = wide ? 'context-field wide' : 'context-field';
    const title = document.createElement('span'); title.textContent = labelText;
    label.append(title, control); return label;
  }
  function inputControl(name, value = '', type = 'text') {
    const input = document.createElement('input');
    input.name = name; input.type = type; input.value = value;
    input.autocomplete = 'off'; input.spellcheck = false; return input;
  }
  function selectControl(name, options, value) {
    const select = document.createElement('select'); select.name = name;
    for (const [key, text] of options) {
      const option = document.createElement('option'); option.value = key; option.textContent = text; select.append(option);
    }
    select.value = value; return select;
  }
  function removeControl(label, row, fallback) {
    const button = document.createElement('button'); button.type = 'button';
    button.className = 'context-remove'; button.textContent = label;
    button.addEventListener('click', () => {
      const previous = row.previousElementSibling?.querySelector('input,select,button');
      row.remove(); (previous || fallback)?.focus(); configurationChanged();
    });
    return button;
  }
  function addTaskPath(card, kind, path = '', mode = 'full', priority = 70) {
    const list = card.querySelector(`[data-path-list="${kind}"]`);
    if (list.children.length >= 128) { toast('每组最多 128 个条目。'); return; }
    const row = document.createElement('div'); row.className = 'context-path-row';
    const pathInput = inputControl('path', path); pathInput.placeholder = 'src/config/types.mbt';
    const modes = [['full', '全文'], ['skeleton', '骨架']];
    if (kind === 'optional') modes.push(['either', '按预算选择']);
    row.append(field('根相对路径', pathInput, true), field('表示', selectControl('mode', modes, mode)));
    if (kind === 'optional') {
      const number = inputControl('priority', String(priority), 'number'); number.min = '0'; number.max = '100'; number.step = '1';
      row.append(field('优先级 0–100', number));
    }
    row.append(removeControl('移除此文件', row, card.querySelector(`[data-add-path="${kind}"]`)));
    list.append(row);
  }
  function addTask() {
    if (el.taskEditor.children.length >= 16) { toast('最多 16 个共享上下文的任务。'); return; }
    const card = document.createElement('section'); card.className = 'context-card'; card.dataset.taskCard = '';
    const header = document.createElement('div'); header.className = 'context-card-head';
    header.append(field('任务 ID', inputControl('taskId', `task-${++taskSequence}`), true), removeControl('移除任务', card, el.addTaskBtn));
    card.append(header);
    for (const [kind, title] of [['required', '必选文件'], ['optional', '可选文件']]) {
      const heading = document.createElement('h3'); heading.textContent = title;
      const list = document.createElement('div'); list.dataset.pathList = kind;
      const add = document.createElement('button'); add.type = 'button'; add.dataset.addPath = kind; add.className = 'context-add';
      add.textContent = kind === 'required' ? '添加必选文件' : '添加可选文件';
      add.addEventListener('click', () => { addTaskPath(card, kind); configurationChanged(); list.lastElementChild?.querySelector('input')?.focus(); });
      card.append(heading, list, add);
    }
    el.taskEditor.append(card); addTaskPath(card, 'required');
  }
  function addCodeRequest() {
    if (el.codeEditor.children.length >= 32) { toast('每轮最多 32 个不同文件。'); return; }
    const card = document.createElement('section'); card.className = 'context-card'; card.dataset.codeCard = '';
    const path = inputControl('path'); path.placeholder = 'src/api.ts';
    const mode = selectControl('mode', [['symbols', '符号实现'], ['ranges', '精确行范围'], ['full', '完整文件'], ['outline', '符号目录']], 'symbols');
    const selector = document.createElement('textarea'); selector.name = 'selector'; selector.rows = 3; selector.spellcheck = false;
    const selectorField = field('符号名称', selector, true);
    const dependencies = inputControl('dependencies', '', 'checkbox');
    const dependencyLabel = field('包含直接依赖声明', dependencies, true);
    const sync = () => {
      const symbols = mode.value === 'symbols';
      selectorField.hidden = !symbols && mode.value !== 'ranges';
      selectorField.firstElementChild.textContent = symbols ? '符号名称，每行一个' : '行范围，每行一个';
      selector.placeholder = symbols ? 'greet\nApi.handle' : '1-20\n35-50';
      dependencyLabel.hidden = !symbols;
    };
    mode.addEventListener('change', sync);
    card.append(field('根相对路径', path, true), field('读取方式', mode, true), selectorField, dependencyLabel, removeControl('移除此请求', card, el.addCodeBtn));
    el.codeEditor.append(card); sync();
  }
  function parseObject(text, label) {
    let value;
    try { value = JSON.parse(text); } catch { throw new Error(`${label}不是有效的 JSON。`); }
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${label}必须是 JSON 对象。`);
    return value;
  }
  function activeBudget() {
    if (state.operation === 'task' && el.taskAdvanced?.checked) {
      try {
        const n = parseObject(el.taskJson.value, '任务描述').maxTokens;
        return Number.isInteger(n) && n > 0 && n <= INT_MAX ? n : null;
      } catch { return null; }
    }
    return budgetValue();
  }
  function taskSpec() {
    if (el.taskAdvanced.checked) {
      const spec = parseObject(el.taskJson.value, '任务描述');
      if (!Number.isInteger(spec.maxTokens) || spec.maxTokens < 1 || spec.maxTokens > INT_MAX) throw new Error('任务 JSON 的 maxTokens 必须是正 Int32 整数。');
      return spec;
    }
    const maxTokens = budgetValue();
    if (maxTokens === null) throw new Error('请输入有效的正整数预算。');
    const cards = [...el.taskEditor.querySelectorAll('[data-task-card]')];
    if (!cards.length) throw new Error('请至少添加一个任务。');
    const ids = new Set(); let totalPaths = 0;
    const tasks = cards.map(card => {
      const id = card.querySelector('[name="taskId"]').value;
      if (!id || byteLength(id) > 64 || id.includes('\0') || ids.has(id)) throw new Error('任务 ID 必须非空、唯一且不超过 64 UTF-8 bytes。');
      ids.add(id);
      const task = { id, required: [], optional: [] };
      for (const kind of ['required', 'optional']) {
        for (const row of card.querySelector(`[data-path-list="${kind}"]`).children) {
          const path = row.querySelector('[name="path"]').value;
          if (!path) continue;
          if (byteLength(path) > 4096) throw new Error('路径不能超过 4096 UTF-8 bytes。');
          const item = { path, mode: row.querySelector('[name="mode"]').value };
          if (kind === 'optional') {
            const raw = row.querySelector('[name="priority"]').value; const priority = Number(raw);
            if (raw === '' || !Number.isInteger(priority) || priority < 0 || priority > 100) throw new Error('可选文件优先级必须是 0–100 的整数。');
            item.priority = priority;
          }
          task[kind].push(item); totalPaths += 1;
        }
      }
      return task;
    });
    if (!totalPaths) throw new Error('请添加至少一个必选或可选文件。');
    return { maxTokens, tasks };
  }
  function codeSpec(continuation) {
    let spec;
    if (el.codeAdvanced.checked) {
      spec = parseObject(el.codeJson.value, '补读描述');
      if (own(spec, 'maxTokens')) throw new Error('补读 JSON 不填写 maxTokens；首轮使用右侧预算，续读使用服务器剩余额度。');
    } else {
      const paths = new Set();
      const requests = [...el.codeEditor.querySelectorAll('[data-code-card]')].map(card => {
        const path = card.querySelector('[name="path"]').value;
        if (!path || byteLength(path) > 4096 || paths.has(path)) throw new Error('补读路径必须非空、唯一且不超过 4096 UTF-8 bytes。');
        paths.add(path);
        const mode = card.querySelector('[name="mode"]').value; const request = { path };
        if (mode === 'full' || mode === 'outline') request[mode] = true;
        else {
          const values = card.querySelector('[name="selector"]').value.split('\n').map(s => s.trim()).filter(Boolean);
          if (!values.length || values.length > 16) throw new Error('每个文件需填写 1–16 个符号或行范围。');
          if (mode === 'symbols') {
            if (values.some(s => byteLength(s) > 256 || /[\0\r]/.test(s))) throw new Error('符号名不得含控制换行，且不超过 256 UTF-8 bytes。');
            request.symbols = values;
            if (card.querySelector('[name="dependencies"]').checked) request.includeDependencies = true;
          } else {
            request.ranges = values.map(value => {
              const match = /^(\d+)\s*[-–]\s*(\d+)$/.exec(value) || /^(\d+)$/.exec(value);
              if (!match) throw new Error('行范围写作 1-20 或单行 8；每行一个范围。');
              const startLine = Number(match[1]); const endLine = Number(match[2] ?? match[1]);
              if (!Number.isInteger(startLine) || !Number.isInteger(endLine) || startLine < 1 || endLine < startLine || endLine > INT_MAX) throw new Error('行范围必须是有序、从 1 开始的 Int32 整数。');
              return { startLine, endLine };
            });
          }
        }
        return request;
      });
      if (!requests.length) throw new Error('请至少添加一个补读文件。');
      spec = { requests };
    }
    if (!continuation) {
      const maxTokens = budgetValue();
      if (maxTokens === null) throw new Error('请输入有效的正整数预算。');
      spec = { ...spec, maxTokens };
    }
    return spec;
  }
  function portableRequest(continuation) {
    const current = contextRequest(continuation);
    const request = {
      schemaVersion: 1,
      operation: state.operation === 'task' ? 'plan_task_context' : 'read_code_context',
      spec: current.spec
    };
    if (continuation) request.continueFrom = current.runId;
    return request;
  }
  function presetMessage(message, error = false) {
    el.presetMessage.textContent = message;
    el.presetMessage.dataset.error = String(error);
  }
  async function validatePortable(value) {
    const response = await apiRequest('/api/context-request/validate', value).catch(error => {
      if (error.outcomeUnknown) throw new Error('配置校验连接中断，未修改配置；请重试。');
      throw error;
    });
    const request = response.request;
    if (request?.schemaVersion !== 1 || !['plan_task_context', 'read_code_context'].includes(request.operation) || !request.spec || Array.isArray(request.spec)) {
      throw new Error('Native 未返回有效的请求配置。');
    }
    return request;
  }
  async function importRequest() {
    const file = el.requestFile.files?.[0];
    if (!file || state.busy || state.presetBusy || !state.online) return;
    state.presetBusy = true; updateControls();
    let imported = false;
    try {
      if (file.size > 65536) throw new Error('配置文件不能超过 64 KiB。');
      const text = new TextDecoder('utf-8', { fatal: true }).decode(await file.arrayBuffer());
      const value = JSON.parse(text);
      if (value?.continueFrom !== undefined) throw new Error('可保存的配置不接受会话 ID；请导入一个带 maxTokens 的新请求。');
      const request = await validatePortable(value);
      const operation = request.operation === 'plan_task_context' ? 'task' : 'code';
      el.operationSelect.value = operation;
      el.budgetInput.value = String(request.spec.maxTokens);
      if (operation === 'task') {
        el.taskAdvanced.checked = true; el.taskJson.hidden = false;
        el.taskEditor.hidden = true; el.addTaskBtn.hidden = true;
        el.taskJson.value = JSON.stringify(request.spec, null, 2);
        el.taskJson.closest('details').open = true;
      } else {
        const spec = { ...request.spec }; delete spec.maxTokens;
        el.codeAdvanced.checked = true; el.codeJson.hidden = false;
        el.codeEditor.hidden = true; el.addCodeBtn.hidden = true;
        el.codeJson.value = JSON.stringify(spec, null, 2);
        el.codeJson.closest('details').open = true;
      }
      state.codeSession = null; state.packError = '';
      applyOperation();
      presetMessage('已导入并校验。沿用当前授权目录；点击生成后才读取源码。');
      imported = true;
    } catch (error) {
      presetMessage('未导入：' + errorMessage(error), true);
    } finally {
      el.requestFile.value = ''; state.presetBusy = false; updateControls();
      (imported ? el.operationSelect : el.importRequestBtn).focus();
    }
  }
  async function saveRequest() {
    if (state.operation === 'pack' || state.busy || state.presetBusy || !state.online) return;
    state.presetBusy = true; updateControls();
    try {
      const request = await validatePortable(portableRequest(false));
      let text = JSON.stringify(request, null, 2) + '\n';
      if (byteLength(text) > 65536) text = JSON.stringify(request);
      if (byteLength(text) > 65536) throw new Error('配置 JSON 不能超过 64 KiB。');
      const url = URL.createObjectURL(new Blob([text], { type: 'application/json;charset=utf-8' }));
      const link = document.createElement('a'); link.href = url; link.download = 'context-request.json';
      document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
      presetMessage('已保存新请求配置：不含目录、源码或会话 ID。CLI 可用 --context-request 执行。');
    } catch (error) {
      presetMessage('未保存：' + errorMessage(error), true);
    } finally { state.presetBusy = false; updateControls(); }
  }
  function contextRequest(continuation) {
    if (state.operation === 'task') return { directory: state.directory, spec: taskSpec() };
    const request = { directory: state.directory, spec: codeSpec(continuation) };
    if (continuation) {
      if (!state.codeSession?.canContinue || state.codeSession.directory !== state.directory) throw new Error('没有可继续的当前目录补读会话；请开始新会话。');
      request.runId = state.codeSession.runId;
    }
    return request;
  }
  function renderCodeSession() {
    if (!el.codeSessionSummary) return;
    const session = state.codeSession;
    el.codeSessionSummary.hidden = state.operation !== 'code';
    el.continueCodeBtn.hidden = state.operation !== 'code';
    el.continueCodeBtn.disabled = state.busy || state.presetBusy || !state.online || !session?.canContinue || session.directory !== state.directory;
    el.codeSessionSummary.textContent = session
      ? `${session.rounds}/${session.maxRounds} 轮 · 已用 ${fmt(session.spent)} / ${fmt(session.limit)} · 剩余 ${fmt(session.remaining)} tokens${session.canContinue ? '' : ' · 会话已结束'}`
      : '首轮确定累计预算；成功最多三轮。失败不扣额度，续读不能增加预算。';
  }
  function renderAudit() {
    const audit = state.latestAudit;
    el.auditSection.hidden = !audit; el.treeAudit.hidden = !audit; el.treeAudit.disabled = !audit;
    el.downloadAuditBtn.disabled = !audit;
    el.auditDecisions.replaceChildren();
    if (!audit) return;
    el.auditSummary.textContent = `${audit.status} · ${fmt(audit.tokens)} tokens / ${fmt(audit.bytes)} bytes · ${audit.includedInDocument ? '已计入本轮正文' : '独立于正文预算'}${audit.failed ? ' · 旧成功正文保留' : ''}`;
    const decisions = Array.isArray(audit.document?.paths) ? audit.document.paths : [];
    for (const decision of decisions) {
      const row = document.createElement('div'); row.className = 'audit-decision';
      const path = document.createElement('strong'); path.textContent = decision.path;
      const reason = document.createElement('span');
      reason.textContent = `${decision.selected ? '已纳入' : '未纳入'} · ${decision.reason}${decision.mode ? ` · ${decision.mode}` : ''}${decision.scanned === true ? ' · 已扫描' : decision.scanned === false ? ' · 未扫描' : ''}`;
      row.append(path, reason); el.auditDecisions.append(row);
    }
  }
  function setAudit(data) {
    state.latestAudit = { ...data.audit, operation: data.operation, status: data.result.status, failed: !['complete', 'with_omissions'].includes(data.result.status) };
    renderAudit(); if (state.active === AUDIT) renderCode();
  }
  function acceptSnapshot(data, config) {
    const uiFiles = Object.create(null); const codeEntries = new Map();
    if (data.operation === 'code') {
      if (!Array.isArray(data.result.document?.files)) throw new Error('Native 补读响应缺少文件数组。');
      for (const entry of data.result.document.files) {
        codeEntries.set(entry.path, entry);
        uiFiles[entry.path] = entry.mode === 'full' ? entry.text : JSON.stringify(entry, null, 2);
      }
    } else Object.assign(uiFiles, data.result.document?.files || {});
    data.uiFiles = uiFiles; data.codeEntries = codeEntries;
    state.snapshot = data; state.snapshotConfig = config; state.stale = false;
    if (data.operation !== 'pack') {
      state.view = 'processed';
      document.querySelectorAll('input[name="viewmode"]').forEach(input => { input.checked = input.value === 'processed'; });
    }
    const paths = Object.keys(uiFiles).sort();
    const validKey = key => key === OUTPUT || (key === AUDIT && state.latestAudit) || own(uiFiles, key);
    state.open = state.open.filter(validKey);
    if (!paths.length) { state.open = [OUTPUT]; state.active = OUTPUT; }
    else {
      if (state.active === null || !validKey(state.active)) state.active = paths[0];
      if (!state.open.includes(state.active)) state.open.push(state.active);
    }
    state.closedFolders.clear(); el.fileSearch.value = ''; el.fileSearch.disabled = false;
    el.treeOutput.disabled = false; el.copyJsonBtn.disabled = false; el.exportBtn.disabled = false;
    renderTree(); renderTabs(); renderCode(); renderInspector(); renderAudit();
  }
  async function generateContext(continuation) {
    if (state.busy || state.presetBusy || !state.online || document.querySelector('dialog[open]')) return;
    const operation = state.operation;
    let request;
    try {
      request = { directory: state.directory, request: portableRequest(continuation) };
      if (byteLength(JSON.stringify(request)) > 65536) throw new Error('请求 JSON 不能超过 64 KiB。');
    } catch (error) { state.packError = error.message; renderResultState(); renderBudget(); return; }
    state.busy = true; state.packError = null; updateControls(); renderResultState();
    try {
      const data = await apiRequest('/api/context-request', request);
      data.operation = operation; setAudit(data);
      if (data.result.serialized === null) {
        state.packError = `${data.result.status}${data.result.report.requiredTokens == null ? '' : ` · 必选正文需 ${fmt(data.result.report.requiredTokens)} tokens`}。未替换上次成功正文；审计已更新。`;
        if (state.snapshot) state.stale = true;
        if (data.codeSession && state.codeSession?.runId === data.codeSession.runId && state.codeSession.directory === data.directory) {
          state.codeSession = { ...data.codeSession, directory: data.directory };
        }
        toast('本次未取得可交付正文，查看选择审计。');
      } else {
        state.codeSession = operation === 'code' ? { ...data.codeSession, directory: data.directory } : null;
        data.profile = operation; acceptSnapshot(data, request);
        toast(`${names.get(operation)}已完成：${fmt(data.result.report.tokens.total)} tokens`);
      }
    } catch (error) {
      state.packError = errorMessage(error);
      if (error.outcomeUnknown || /stale|unknown_run|invalid_code_session/.test(error.code || '')) state.codeSession = null;
      if (state.snapshot) state.stale = true;
    } finally { state.busy = false; updateControls(); renderResultState(); renderBudget(); }
  }
  function generate() {
    if (state.presetBusy) return;
    return state.operation === 'pack' ? generatePack() : generateContext(false);
  }
  function applyOperation() {
    state.operation = el.operationSelect.value; $('app').dataset.operation = state.operation;
    el.packSettings.hidden = state.operation !== 'pack'; el.taskSettings.hidden = state.operation !== 'task'; el.codeSettings.hidden = state.operation !== 'code';
    el.treeLegend.textContent = state.operation === 'pack' ? '实心：正文变化 · 圈点：全文保留' : '只显示实际返回内容；审计独立查看';
    el.operationHint.textContent = state.operation === 'pack' ? '整理目录，完整输出；超预算仍保留。' : state.operation === 'task' ? '必选优先，可选按优先级；正文受硬上限约束。' : '完整原文先扫描，再返回请求范围；不获取额外全文对照。';
    el.budgetHint.textContent = state.operation === 'pack' ? '普通打包只检查完整输出；超限仍可下载。' : state.operation === 'task' ? 'o200k_base 正文硬预算。高级 JSON 使用其 maxTokens；独立审计另计。' : '新会话的累计正文硬预算，含嵌入审计；续读使用服务器剩余额度。';
    configurationChanged(); updateControls();
  }
  function downloadAudit() {
    if (!state.latestAudit) return;
    const url = URL.createObjectURL(new Blob([state.latestAudit.serialized], { type: 'application/json;charset=utf-8' }));
    const link = document.createElement('a'); link.href = url; link.download = `audit-${state.latestAudit.operation}.json`;
    document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function bindContextEvents() {
    el.operationSelect.addEventListener('change', applyOperation);
    el.addTaskBtn.addEventListener('click', () => { addTask(); configurationChanged(); el.taskEditor.lastElementChild?.querySelector('input')?.focus(); });
    el.addCodeBtn.addEventListener('click', () => { addCodeRequest(); configurationChanged(); el.codeEditor.lastElementChild?.querySelector('input')?.focus(); });
    for (const editor of [el.taskEditor, el.codeEditor]) {
      editor.addEventListener('input', configurationChanged); editor.addEventListener('change', configurationChanged);
    }
    el.taskAdvanced.addEventListener('change', () => { el.taskJson.hidden = !el.taskAdvanced.checked; el.taskEditor.hidden = el.taskAdvanced.checked; el.addTaskBtn.hidden = el.taskAdvanced.checked; configurationChanged(); updateControls(); });
    el.codeAdvanced.addEventListener('change', () => { el.codeJson.hidden = !el.codeAdvanced.checked; el.codeEditor.hidden = el.codeAdvanced.checked; el.addCodeBtn.hidden = el.codeAdvanced.checked; configurationChanged(); });
    el.taskJson.addEventListener('input', configurationChanged); el.codeJson.addEventListener('input', configurationChanged);
    el.continueCodeBtn.addEventListener('click', () => generateContext(true));
    el.treeAudit.addEventListener('click', () => selectKey(AUDIT)); el.openAuditBtn.addEventListener('click', () => { selectKey(AUDIT); focusActiveTab(); });
    el.downloadAuditBtn.addEventListener('click', downloadAudit);
    el.importRequestBtn.addEventListener('click', () => el.requestFile.click());
    el.requestFile.addEventListener('change', importRequest);
    el.saveRequestBtn.addEventListener('click', saveRequest);
    addTask(); addCodeRequest();
    el.taskJson.value = JSON.stringify({ maxTokens: 8000, tasks: [{ id: 'review', required: [{ path: 'src/config/types.mbt', mode: 'full' }], optional: [{ path: 'src/config/cli.mbt', mode: 'either', priority: 90 }] }] }, null, 2);
    el.codeJson.value = JSON.stringify({ requests: [{ path: 'src/api.ts', symbols: ['greet'] }] }, null, 2);
    applyOperation();
  }

  function init() {
    const ids = ['workspace', 'connectionBtn', 'connectionDetail', 'limitsBtn', 'configFields', 'selectDirBtn', 'currentDirectory', 'keepFullGroup', 'includeInput', 'keepFullInput', 'budgetInput', 'budgetMsg', 'generateBtn', 'requestMessage', 'resultState', 'treeOutput', 'tree', 'treeCount', 'treeEmpty', 'fileSearch', 'tabbar', 'codepane', 'code', 'empty', 'emptyTitle', 'emptyText', 'openOutputBtn', 'chPath', 'chMode', 'chInfo', 'viewSeg', 'copyCodeBtn', 'snapshotLabel', 'mTokens', 'mBytes', 'mFiles', 'mChanged', 'curSummary', 'scanFindings', 'scanMeta', 'stFile', 'stTok', 'stScan', 'cliText', 'copyCliBtn', 'copyJsonBtn', 'exportBtn', 'exportInfo', 'bottomPanel', 'bottomToggle', 'directoryDialog', 'closeDirectoryBtn', 'cancelDirectoryBtn', 'confirmDirectoryBtn', 'goUpBtn', 'browseDirectory', 'directoryMessage', 'dirList', 'retryDirectoryBtn', 'limitsDialog', 'closeLimitsBtn', 'sessionDetails', 'copyDialog', 'closeCopyBtn', 'copyText', 'toast'];
    ids.forEach(id => { el[id] = $(id); });
    ['operationSelect','operationHint','packSettings','taskSettings','codeSettings','taskEditor','codeEditor','addTaskBtn','addCodeBtn','taskAdvanced','taskJson','codeAdvanced','codeJson','budgetHint','continueCodeBtn','codeSessionSummary','changedMetric','treeLegend','treeAudit','auditSection','auditSummary','auditDecisions','openAuditBtn','downloadAuditBtn','commandLabel','importRequestBtn','saveRequestBtn','requestFile','presetMessage','definitionHint'].forEach(id => { el[id] = $(id); });
    el.editor = document.querySelector('.editor');
    bindEvents();
    bindContextEvents();
    renderCli();
    renderBudget();
    connect();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
