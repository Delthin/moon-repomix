/**
 * Moon-Repomix 仓库上下文工作台 · 前端核心脚本 (Native Connected)
 * 无外部框架与 CDN 依赖，纯同源 Fetch 与本地 Native 引擎交互
 */

(function () {
  'use strict';

  /* ==========================================================================
     API 契约与常量定义
     ========================================================================== */
  const API_HEADERS = {
    'X-Moon-Repomix': 'webui'
  };
  const API_TIMEOUT_MS = 65000; // 后端超时 60s，客户端给 65s

  /* ==========================================================================
     全局应用状态
     ========================================================================== */
  const state = {
    // 服务与会话
    session: null,
    connectionStatus: 'connecting', // 'connecting' | 'connected' | 'offline' | 'error'
    connectionError: null,

    // 用户表单配置 (待生效或已生效)
    directory: '.',
    profile: 'mixed', // 'raw' | 'mixed' | 'skeleton'
    tokenBudget: 8000,
    includePatterns: [],
    keepFull: [],

    // 打包执行与结果
    isPacking: false,
    hasGenerated: false,
    isStale: false, // 当用户改了表单后为 true，提醒旧数据
    lastPackResult: null, // { profile, directory, result, baseline }

    // 视窗与交互
    activeView: 'diff', // 'diff' | 'single' | 'bundle'
    selectedFile: null,
    searchQuery: '',
    isMobileNavOpen: false,
    isAdvancedOpen: false,

    // 目录浏览 Dialog 状态
    dialogBrowseDir: '.',
    dialogDirectories: [],
    dialogIsLoading: false,
    dialogError: null
  };

  /* ==========================================================================
     DOM 元素引用缓存
     ========================================================================== */
  const el = {
    // Header & Session
    sessionVersionBadge: document.getElementById('sessionVersionBadge'),
    workspaceBadge: document.getElementById('workspaceBadge'),
    serviceStatusPill: document.getElementById('serviceStatusPill'),
    serviceStatusText: document.getElementById('serviceStatusText'),
    sessionLimitsBtn: document.getElementById('sessionLimitsBtn'),

    // Control Hub: Directory & Profile
    currentDirDisplay: document.getElementById('currentDirDisplay'),
    selectDirBtn: document.getElementById('selectDirBtn'),
    tabRaw: document.getElementById('tab-raw'),
    tabMixed: document.getElementById('tab-mixed'),
    tabSkeleton: document.getElementById('tab-skeleton'),
    profileTabs: document.querySelectorAll('.profile-tab'),

    // Advanced Panel
    toggleAdvancedBtn: document.getElementById('toggleAdvancedBtn'),
    advancedPanel: document.getElementById('advancedPanel'),
    includePatternsInput: document.getElementById('includePatternsInput'),
    keepFullGroup: document.getElementById('keepFullGroup'),
    keepFullInput: document.getElementById('keepFullInput'),

    // Budget & Meters
    outputFreshnessBadge: document.getElementById('outputFreshnessBadge'),
    budgetBtns: document.querySelectorAll('.budget-btn'),
    budgetThreshold: document.getElementById('budgetThreshold'),
    budgetProgress: document.getElementById('budgetProgress'),
    currentTokensVal: document.getElementById('currentTokensVal'),
    currentBytesVal: document.getElementById('currentBytesVal'),
    budgetRatioVal: document.getElementById('budgetRatioVal'),
    budgetNotice: document.getElementById('budgetNotice'),
    budgetNoticeText: document.getElementById('budgetNoticeText'),

    // Pack Action
    packSubmitBtn: document.getElementById('packSubmitBtn'),
    packBtnIcon: document.getElementById('packBtnIcon'),
    packBtnText: document.getElementById('packBtnText'),
    packStateHint: document.getElementById('packStateHint'),

    // CLI & Export
    cliCommandText: document.getElementById('cliCommandText'),
    copyCliBtn: document.getElementById('copyCliBtn'),
    copyJsonBtn: document.getElementById('copyJsonBtn'),
    downloadJsonBtn: document.getElementById('downloadJsonBtn'),

    // Workbench Navigation & Sidebar
    mobileNavToggle: document.getElementById('mobileNavToggle'),
    mobileNavBtnText: document.getElementById('mobileNavBtnText'),
    fileSidebar: document.getElementById('fileSidebar'),
    fileSearchInput: document.getElementById('fileSearchInput'),
    clearSearchBtn: document.getElementById('clearSearchBtn'),
    fileCountText: document.getElementById('fileCountText'),
    fileSkippedText: document.getElementById('fileSkippedText'),
    fileListContainer: document.getElementById('fileListContainer'),
    fileEmptyState: document.getElementById('fileEmptyState'),
    resetSearchBtn: document.getElementById('resetSearchBtn'),

    // Viewport & Code
    viewTabs: document.querySelectorAll('.view-tab'),
    fileMetaPill: document.getElementById('fileMetaPill'),
    activeFilePath: document.getElementById('activeFilePath'),
    activeFileStrategyBadge: document.getElementById('activeFileStrategyBadge'),
    copyPathBtn: document.getElementById('copyPathBtn'),
    copyCodeBtn: document.getElementById('copyCodeBtn'),

    initialIdleContainer: document.getElementById('initialIdleContainer'),
    quickStartBtn: document.getElementById('quickStartBtn'),

    diffViewContainer: document.getElementById('diffViewContainer'),
    rawCodeBlock: document.getElementById('rawCodeBlock'),
    rawStats: document.getElementById('rawStats'),
    targetCodeBlock: document.getElementById('targetCodeBlock'),
    targetStats: document.getElementById('targetStats'),
    targetStrategyTitle: document.getElementById('targetStrategyTitle'),

    singleViewContainer: document.getElementById('singleViewContainer'),
    singleCodeBlock: document.getElementById('singleCodeBlock'),
    singleStats: document.getElementById('singleStats'),
    singleStrategyTitle: document.getElementById('singleStrategyTitle'),

    bundleViewContainer: document.getElementById('bundleViewContainer'),
    bundleTreeBlock: document.getElementById('bundleTreeBlock'),
    bundleTreeStats: document.getElementById('bundleTreeStats'),
    bundleJsonBlock: document.getElementById('bundleJsonBlock'),
    bundleJsonStats: document.getElementById('bundleJsonStats'),

    // Footer
    footerConnectionDot: document.getElementById('footerConnectionDot'),
    footerWorkspaceText: document.getElementById('footerWorkspaceText'),
    footerSecurityText: document.getElementById('footerSecurityText'),

    // Dialogs
    directoryDialog: document.getElementById('directoryDialog'),
    closeDirectoryDialogBtn: document.getElementById('closeDirectoryDialogBtn'),
    cancelDirSelectBtn: document.getElementById('cancelDirSelectBtn'),
    confirmDirSelectBtn: document.getElementById('confirmDirSelectBtn'),
    dialogCurrentDir: document.getElementById('dialogCurrentDir'),
    dirGoUpBtn: document.getElementById('dirGoUpBtn'),
    dirList: document.getElementById('dirList'),
    dirLoadingIndicator: document.getElementById('dirLoadingIndicator'),
    dirEmptyState: document.getElementById('dirEmptyState'),

    sessionLimitsDialog: document.getElementById('sessionLimitsDialog'),
    closeSessionLimitsBtn: document.getElementById('closeSessionLimitsBtn'),
    closeSessionLimitsFooterBtn: document.getElementById('closeSessionLimitsFooterBtn'),
    dialogWorkspaceName: document.getElementById('dialogWorkspaceName'),
    dialogPortVal: document.getElementById('dialogPortVal'),
    dialogVersionVal: document.getElementById('dialogVersionVal'),
    limitMaxFiles: document.getElementById('limitMaxFiles'),
    limitMaxBytes: document.getElementById('limitMaxBytes'),
    securityStatusVal: document.getElementById('securityStatusVal'),
    securityFindingsDesc: document.getElementById('securityFindingsDesc'),

    copyFallbackDialog: document.getElementById('copyFallbackDialog'),
    closeCopyFallbackBtn: document.getElementById('closeCopyFallbackBtn'),
    closeCopyFallbackFooterBtn: document.getElementById('closeCopyFallbackFooterBtn'),
    copyFallbackTextarea: document.getElementById('copyFallbackTextarea'),

    toastNotification: document.getElementById('toastNotification'),
    toastMessage: document.getElementById('toastMessage')
  };

  /* ==========================================================================
     网络与请求工具
     ========================================================================== */
  async function apiRequest(url, options = {}) {
    const controller = new AbortController();
    const timeoutTimer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

    const mergedHeaders = Object.assign({}, API_HEADERS, options.headers || {});
    if (options.body && typeof options.body === 'string') {
      mergedHeaders['Content-Type'] = 'application/json';
    }

    try {
      const response = await fetch(url, {
        ...options,
        headers: mergedHeaders,
        signal: controller.signal
      });
      clearTimeout(timeoutTimer);

      if (!response.ok) {
        let errorData = null;
        try {
          errorData = await response.json();
        } catch {
          // 非 JSON 响应
        }
        const safeMessage = (errorData && errorData.error && errorData.error.message)
          ? errorData.error.message
          : `HTTP ${response.status} ${response.statusText}`;

        const err = new Error(safeMessage);
        err.status = response.status;
        err.code = errorData?.error?.code || 'UNKNOWN_ERROR';
        throw err;
      }

      return await response.json();
    } catch (err) {
      clearTimeout(timeoutTimer);
      if (err.name === 'AbortError') {
        const timeoutErr = new Error('请求 Native 服务超时 (65s)，后台处理可能仍在继续');
        timeoutErr.status = 504;
        throw timeoutErr;
      }
      throw err;
    }
  }

  /* ==========================================================================
     安全与字符串工具 (安全纯文本渲染，杜绝 XSS)
     ========================================================================== */
  function escapeHtml(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function shellQuote(str) {
    if (/^[a-zA-Z0-9_\-\.\/]+$/.test(str)) {
      return str;
    }
    return "'" + str.replace(/'/g, "'\\''") + "'";
  }

  function formatBytes(bytes) {
    const num = Number(bytes);
    if (isNaN(num) || num < 0) return '—';
    if (num < 1024) return num + ' B';
    if (num < 1024 * 1024) return (num / 1024).toFixed(1) + ' KB';
    return (num / (1024 * 1024)).toFixed(2) + ' MB';
  }

  function formatNumber(num) {
    const n = Number(num);
    if (isNaN(n)) return '—';
    return n.toLocaleString('zh-CN');
  }

  function parsePatternList(text) {
    if (!text) return [];
    return text
      .split(/[,\n]/)
      .map(s => s.trim())
      .filter(s => s.length > 0 && s.length <= 1024)
      .slice(0, 64);
  }

  /* ==========================================================================
     服务状态与 Session 初始化
     ========================================================================== */
  async function fetchSession() {
    updateServiceStatus('connecting', '正在连接 Native 服务...');
    try {
      const data = await apiRequest('/api/session');
      state.session = data;
      state.connectionStatus = 'connected';
      state.connectionError = null;

      // 更新界面徽标
      if (data.version) {
        el.sessionVersionBadge.textContent = 'v' + data.version;
      }
      if (data.workspaceName) {
        el.workspaceBadge.textContent = data.workspaceName;
        el.workspaceBadge.title = `授权工作区：${data.workspaceName}`;
        el.footerWorkspaceText.textContent = `工作区：${data.workspaceName}`;
        el.dialogWorkspaceName.textContent = data.workspaceName;
      }
      if (data.port) {
        el.dialogPortVal.textContent = String(data.port);
      }
      if (data.limits) {
        el.limitMaxFiles.textContent = formatNumber(data.limits.maxFiles);
        el.limitMaxBytes.textContent = formatBytes(data.limits.maxTotalBytes);
      }
      el.dialogVersionVal.textContent = data.version ? `v${data.version}` : 'v0.4.0';

      updateServiceStatus('connected', 'Native 服务在线 (127.0.0.1)');
    } catch (err) {
      state.connectionStatus = 'offline';
      state.connectionError = err.message;
      updateServiceStatus('offline', '未连接到服务 · 点击重试');
      el.workspaceBadge.textContent = '未连接';
      el.footerWorkspaceText.textContent = '工作区：未连接';
    }
  }

  function updateServiceStatus(status, text) {
    el.serviceStatusPill.className = `service-status-pill status-${status}`;
    el.serviceStatusText.textContent = text;
    if (status === 'connected') {
      el.footerConnectionDot.style.backgroundColor = 'var(--status-ok)';
    } else if (status === 'connecting') {
      el.footerConnectionDot.style.backgroundColor = 'var(--status-warn)';
    } else {
      el.footerConnectionDot.style.backgroundColor = 'var(--status-err)';
    }
  }

  /* ==========================================================================
     目录选择 Dialog 逻辑 (/api/directories)
     ========================================================================== */
  async function openDirectoryDialog() {
    state.dialogBrowseDir = state.directory;
    el.directoryDialog.showModal();
    await loadDirectoryContents(state.dialogBrowseDir);
  }

  function closeDirectoryDialog() {
    el.directoryDialog.close();
  }

  async function loadDirectoryContents(dir) {
    state.dialogBrowseDir = dir;
    el.dialogCurrentDir.textContent = dir;
    el.dirGoUpBtn.disabled = (dir === '.' || dir === '' || dir === '/');

    el.dirLoadingIndicator.style.display = 'flex';
    el.dirList.innerHTML = '';
    el.dirEmptyState.style.display = 'none';

    try {
      const data = await apiRequest('/api/directories', {
        method: 'POST',
        body: JSON.stringify({ directory: dir })
      });

      el.dirLoadingIndicator.style.display = 'none';
      const subdirs = data.directories || [];
      state.dialogDirectories = subdirs;

      if (subdirs.length === 0) {
        el.dirEmptyState.style.display = 'block';
        return;
      }

      const fragment = document.createDocumentFragment();
      subdirs.forEach(childPath => {
        const itemBtn = document.createElement('button');
        itemBtn.type = 'button';
        itemBtn.className = 'dir-item-btn';

        const iconSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        iconSvg.setAttribute('width', '14');
        iconSvg.setAttribute('height', '14');
        iconSvg.setAttribute('viewBox', '0 0 24 24');
        iconSvg.setAttribute('fill', 'none');
        iconSvg.setAttribute('stroke', 'currentColor');
        iconSvg.setAttribute('stroke-width', '2');
        iconSvg.innerHTML = '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path>';

        const nameSpan = document.createElement('span');
        nameSpan.textContent = childPath;

        itemBtn.appendChild(iconSvg);
        itemBtn.appendChild(nameSpan);

        itemBtn.addEventListener('click', () => {
          loadDirectoryContents(childPath);
        });

        fragment.appendChild(itemBtn);
      });

      el.dirList.appendChild(fragment);
    } catch (err) {
      el.dirLoadingIndicator.style.display = 'none';
      showToast('读取目录失败: ' + err.message);
    }
  }

  function goUpDirectory() {
    const current = state.dialogBrowseDir;
    if (current === '.' || !current) return;
    const parts = current.split('/').filter(Boolean);
    parts.pop();
    const parent = parts.length === 0 ? '.' : parts.join('/');
    loadDirectoryContents(parent);
  }

  function confirmDirectorySelection() {
    const prevDir = state.directory;
    state.directory = state.dialogBrowseDir;
    el.currentDirDisplay.textContent = state.directory;
    closeDirectoryDialog();

    if (prevDir !== state.directory && state.hasGenerated) {
      markStaleState();
    }
    updateCliCommand();
  }

  /* ==========================================================================
     CLI 命令生成器 (遵守实际 CLI 语法)
     ========================================================================== */
  function updateCliCommand() {
    // 语法: moon-repomix <directory> --style json [--compress] [--keep-full <p>...] [--include <p>...] [--token-budget <N>] -o context.json
    const parts = ['moon-repomix'];

    // 目录
    parts.push(shellQuote(state.directory));

    // 风格
    parts.push('--style', 'json');

    // 压缩策略: skeleton 和 mixed 使用布尔 --compress 标志
    if (state.profile === 'skeleton' || state.profile === 'mixed') {
      parts.push('--compress');
    }

    // keep-full: 仅在 mixed 下生效
    if (state.profile === 'mixed' && state.keepFull && state.keepFull.length > 0) {
      state.keepFull.forEach(pattern => {
        parts.push('--keep-full', shellQuote(pattern));
      });
    }

    // include patterns
    if (state.includePatterns && state.includePatterns.length > 0) {
      state.includePatterns.forEach(pattern => {
        parts.push('--include', shellQuote(pattern));
      });
    }

    // 预算
    if (state.tokenBudget && Number(state.tokenBudget) > 0) {
      parts.push('--token-budget', String(state.tokenBudget));
    }

    parts.push('-o', 'context.json');

    el.cliCommandText.textContent = parts.join(' ');
  }

  /* ==========================================================================
     生成打包主逻辑 (POST /api/pack)
     ========================================================================== */
  async function performPack() {
    if (state.isPacking) return;

    // 同步输入框内容
    state.includePatterns = parsePatternList(el.includePatternsInput.value);
    state.keepFull = parsePatternList(el.keepFullInput.value);
    const budgetVal = parseInt(el.budgetThreshold.value, 10);
    state.tokenBudget = isNaN(budgetVal) || budgetVal <= 0 ? 8000 : budgetVal;

    updateCliCommand();

    // 界面置为忙态
    state.isPacking = true;
    el.packSubmitBtn.classList.add('busy');
    el.packSubmitBtn.disabled = true;
    el.packBtnText.textContent = 'Native 引擎转换中...';
    el.packStateHint.textContent = '正在由 Native 引擎扫描并构建 AST 骨架...';

    const payload = {
      directory: state.directory,
      profile: state.profile,
      tokenBudget: state.tokenBudget,
      includePatterns: state.includePatterns,
      keepFull: state.profile === 'mixed' ? state.keepFull : []
    };

    try {
      const data = await apiRequest('/api/pack', {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      // 成功生成
      state.lastPackResult = data;
      state.hasGenerated = true;
      state.isStale = false;

      renderPackSuccess(data);
      showToast('上下文生成成功');
    } catch (err) {
      // 失败保留上次结果，展示明确 safe error
      let msg = err.message;
      if (err.status === 409) {
        msg = 'Native 引擎忙碌（已有任务正在执行），请稍后重试';
      }
      showToast('打包失败: ' + msg);

      if (state.hasGenerated) {
        markStaleState();
        el.budgetNoticeText.textContent = `生成失败: ${msg}（当前仍展示上一次有效结果）`;
        el.budgetNotice.className = 'budget-alert status-warn';
      } else {
        el.budgetNoticeText.textContent = `生成失败: ${msg}`;
        el.budgetNotice.className = 'budget-alert status-warn';
      }
    } finally {
      state.isPacking = false;
      el.packSubmitBtn.classList.remove('busy');
      el.packSubmitBtn.disabled = false;
      el.packBtnText.textContent = '生成仓库上下文';
      el.packStateHint.innerHTML = '支持快捷键 <code>Cmd/Ctrl + Enter</code>';
    }
  }

  function renderPackSuccess(data) {
    const report = data.result?.report;
    const documentData = data.result?.document;

    // 1. 新鲜度标记
    el.outputFreshnessBadge.textContent = `实测 · ${getProfileName(data.profile)}`;
    el.outputFreshnessBadge.className = 'freshness-badge badge-fresh';

    // 2. 导出与复制按钮启用
    el.copyJsonBtn.disabled = false;
    el.downloadJsonBtn.disabled = false;
    el.copyPathBtn.disabled = false;
    el.copyCodeBtn.disabled = false;

    // 3. Tokens 与预算比对
    const tokens = parseInt(report?.tokens?.total || '0', 10);
    const bytes = parseInt(report?.bytes?.total || '0', 10);
    el.currentTokensVal.textContent = formatNumber(tokens);
    el.currentBytesVal.textContent = formatBytes(bytes);

    const budgetLimit = state.tokenBudget;
    const ratio = budgetLimit > 0 ? (tokens / budgetLimit) : 0;
    const percent = Math.min(Math.round(ratio * 100), 100);

    el.budgetProgress.style.width = percent + '%';
    el.budgetRatioVal.textContent = `${percent}% (上限 ${formatNumber(budgetLimit)} tok)`;

    if (tokens > budgetLimit) {
      el.budgetProgress.classList.add('exceeded');
      el.budgetNotice.className = 'budget-alert status-warn';
      el.budgetNoticeText.textContent = `超出预算 ${formatNumber(tokens - budgetLimit)} tokens。Native 引擎仍保留完整正文输出，请按需调整预算或提高骨架压缩比。`;
    } else {
      el.budgetProgress.classList.remove('exceeded');
      el.budgetNotice.className = 'budget-alert status-ok';
      el.budgetNoticeText.textContent = `在预算内，剩余空间 ${formatNumber(budgetLimit - tokens)} tokens。已完成 AST 骨架化。`;
    }

    // 4. 安全状态展示
    if (report?.security) {
      const sec = report.security;
      const findings = sec.findings || 0;
      const statusText = sec.status === 'passed' ? '安全通过 (0 泄漏)' : `排除 ${findings} 项敏感信息`;
      el.footerSecurityText.textContent = `安全检查：${statusText}`;

      el.securityStatusVal.textContent = sec.status === 'passed' ? '检查通过' : '已排除风险';
      el.securityFindingsDesc.textContent = `本次扫描敏感凭据命中项：${findings}，状态：${sec.status}`;
    }

    // 5. 渲染左侧结果文件列表
    renderFileList(data);

    // 6. 切换右侧视窗显示
    el.initialIdleContainer.style.display = 'none';
    switchViewTab(state.activeView);
  }

  function markStaleState() {
    if (!state.hasGenerated) return;
    state.isStale = true;
    el.outputFreshnessBadge.textContent = '配置已修改 · 待生成';
    el.outputFreshnessBadge.className = 'freshness-badge badge-stale';
    el.budgetNoticeText.textContent = '注意：配置已调整。上方数值为上次打包实测，请点击「生成仓库上下文」重新运行。';
    el.budgetNotice.className = 'budget-alert status-warn';
  }

  function getProfileName(profile) {
    if (profile === 'raw') return 'Raw 全文';
    if (profile === 'skeleton') return 'Skeleton 骨架';
    if (profile === 'mixed') return 'Mixed 混合';
    return profile;
  }

  /* ==========================================================================
     文件列表渲染 (结果集集合)
     ========================================================================== */
  function renderFileList(data) {
    const filesMap = data.result?.document?.files || {};
    const filePaths = Object.keys(filesMap).sort();
    const baselineMap = data.baseline?.document?.files || {};
    const report = data.result?.report;

    el.fileCountText.textContent = `${filePaths.length} 个文件`;
    if (report?.counts?.skippedEntries) {
      el.fileSkippedText.textContent = `跳过 ${report.counts.skippedEntries} 项`;
    } else {
      el.fileSkippedText.textContent = '';
    }
    el.mobileNavBtnText.textContent = `显示打包文件列表 (${filePaths.length})`;

    // 过滤
    const query = state.searchQuery.toLowerCase().trim();
    const visiblePaths = filePaths.filter(p => !query || p.toLowerCase().includes(query));

    el.fileListContainer.innerHTML = '';

    if (visiblePaths.length === 0) {
      el.fileEmptyState.style.display = 'block';
      return;
    }
    el.fileEmptyState.style.display = 'none';

    // 分组
    let currentDirGroup = '';
    const fragment = document.createDocumentFragment();

    visiblePaths.forEach(filePath => {
      const dirOfFile = filePath.lastIndexOf('/') !== -1 ? filePath.substring(0, filePath.lastIndexOf('/')) : '.';
      if (dirOfFile !== currentDirGroup) {
        currentDirGroup = dirOfFile;
        const heading = document.createElement('div');
        heading.className = 'file-group-heading';
        heading.textContent = currentDirGroup;
        fragment.appendChild(heading);
      }

      const itemBtn = document.createElement('button');
      itemBtn.type = 'button';
      itemBtn.className = 'file-tree-item' + (state.selectedFile === filePath ? ' active' : '');
      itemBtn.setAttribute('data-path', filePath);

      // 图标 + 路径
      const fileInfo = document.createElement('div');
      fileInfo.className = 'file-info';

      const iconSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      iconSvg.setAttribute('class', 'file-icon');
      iconSvg.setAttribute('viewBox', '0 0 24 24');
      iconSvg.setAttribute('fill', 'none');
      iconSvg.setAttribute('stroke', 'currentColor');
      iconSvg.setAttribute('stroke-width', '2');
      iconSvg.innerHTML = '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline>';

      const pathText = document.createElement('span');
      pathText.className = 'file-path-text';
      pathText.textContent = filePath.substring(filePath.lastIndexOf('/') + 1);
      pathText.title = filePath;

      fileInfo.appendChild(iconSvg);
      fileInfo.appendChild(pathText);

      // 标签组 (判断 AST 骨架化还是保留全文)
      const badgeGroup = document.createElement('div');
      badgeGroup.className = 'file-badge-group';

      const rawContent = baselineMap[filePath];
      const targetContent = filesMap[filePath];
      const isCompressed = rawContent && targetContent && targetContent.includes('{/* … */}');

      const tag = document.createElement('span');
      tag.className = 'badge-tag';
      if (isCompressed) {
        tag.className += ' badge-skeleton';
        tag.textContent = 'AST骨架';
      } else {
        tag.className += ' badge-full';
        tag.textContent = '全文';
      }
      badgeGroup.appendChild(tag);

      itemBtn.appendChild(fileInfo);
      itemBtn.appendChild(badgeGroup);

      itemBtn.addEventListener('click', () => {
        selectFile(filePath);
        if (state.isMobileNavOpen) {
          toggleMobileNav(false);
        }
      });

      fragment.appendChild(itemBtn);
    });

    el.fileListContainer.appendChild(fragment);

    // 默认选中第一个
    if (!state.selectedFile || !filesMap[state.selectedFile]) {
      // 优先选 cli.mbt 或 encoder.mbt，否则选第一个
      const preferred = visiblePaths.find(p => p.includes('cli.mbt') || p.includes('encoder.mbt')) || visiblePaths[0];
      if (preferred) {
        selectFile(preferred);
      }
    } else {
      selectFile(state.selectedFile);
    }
  }

  function selectFile(filePath) {
    state.selectedFile = filePath;

    // 更新 sidebar active 样式
    const items = el.fileListContainer.querySelectorAll('.file-tree-item');
    items.forEach(btn => {
      if (btn.getAttribute('data-path') === filePath) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    // 更新 Toolbar 信息
    el.fileMetaPill.style.display = 'flex';
    el.activeFilePath.textContent = filePath;

    const data = state.lastPackResult;
    if (!data) return;

    const targetCode = data.result?.document?.files?.[filePath] || '';
    const baselineCode = data.baseline?.document?.files?.[filePath] || null;
    const isSkeleton = targetCode.includes('{/* … */}');

    if (isSkeleton) {
      el.activeFileStrategyBadge.className = 'strategy-badge badge-ast';
      el.activeFileStrategyBadge.textContent = 'AST 骨架化';
    } else {
      el.activeFileStrategyBadge.className = 'strategy-badge badge-full';
      el.activeFileStrategyBadge.textContent = '保留全文';
    }

    // 渲染各个视窗
    renderDiffView(filePath, baselineCode, targetCode);
    renderSingleView(filePath, targetCode, isSkeleton);
    renderBundleView(data);
  }

  /* ==========================================================================
     代码视窗渲染
     ========================================================================== */
  function renderDiffView(filePath, baselineCode, targetCode) {
    // 基准原文
    if (baselineCode !== null && baselineCode !== undefined) {
      const rawLines = baselineCode.split('\n').length;
      el.rawStats.textContent = `${rawLines} 行 · ${formatBytes(new Blob([baselineCode]).size)}`;
      renderHighlightedCode(el.rawCodeBlock, baselineCode);
    } else {
      el.rawStats.textContent = '基准无此文件';
      el.rawCodeBlock.textContent = '// 本次独立 raw pack 中未发现此文件对照';
    }

    // 本次输出
    const targetLines = targetCode.split('\n').length;
    el.targetStats.textContent = `${targetLines} 行 · ${formatBytes(new Blob([targetCode]).size)}`;
    renderHighlightedCode(el.targetCodeBlock, targetCode);
  }

  function renderSingleView(filePath, targetCode, isSkeleton) {
    const targetLines = targetCode.split('\n').length;
    el.singleStats.textContent = `${targetLines} 行 · ${formatBytes(new Blob([targetCode]).size)}`;
    el.singleStrategyTitle.textContent = isSkeleton ? '当前输出 (AST 骨架)' : '当前输出 (全文)';
    renderHighlightedCode(el.singleCodeBlock, targetCode);
  }

  function renderBundleView(data) {
    const treeText = data.result?.document?.directoryStructure || '（无目录树输出）';
    el.bundleTreeBlock.textContent = treeText;
    el.bundleTreeStats.textContent = `${treeText.split('\n').length} 行`;

    const serialized = data.result?.serialized || '';
    el.bundleJsonBlock.textContent = serialized;
    el.bundleJsonStats.textContent = `${formatBytes(new Blob([serialized]).size)}`;
  }

  /* 极简安全代码着色器 (使用 DocumentFragment 和 Span 纯文本渲染) */
  function renderHighlightedCode(container, codeText) {
    container.innerHTML = '';
    const fragment = document.createDocumentFragment();

    const lines = codeText.split('\n');
    lines.forEach((lineText, idx) => {
      const lineDiv = document.createElement('div');
      lineDiv.className = 'code-line';

      // 语法高亮分词安全处理
      renderLineTokens(lineDiv, lineText);

      fragment.appendChild(lineDiv);
    });

    container.appendChild(fragment);
  }

  function renderLineTokens(container, line) {
    // 快速扫描 AST 折叠标记
    if (line.includes('{/* … */}')) {
      const parts = line.split('{/* … */}');
      for (let i = 0; i < parts.length; i++) {
        if (parts[i]) {
          renderBasicKeywords(container, parts[i]);
        }
        if (i < parts.length - 1) {
          const foldSpan = document.createElement('span');
          foldSpan.className = 'tok-fold';
          foldSpan.textContent = '{/* … */}';
          container.appendChild(foldSpan);
        }
      }
      return;
    }

    // 单行注释
    const commentIdx = line.indexOf('//');
    if (commentIdx !== -1) {
      const codePart = line.substring(0, commentIdx);
      const commentPart = line.substring(commentIdx);
      if (codePart) {
        renderBasicKeywords(container, codePart);
      }
      const commentSpan = document.createElement('span');
      commentSpan.className = 'tok-comment';
      commentSpan.textContent = commentPart;
      container.appendChild(commentSpan);
      return;
    }

    renderBasicKeywords(container, line);
  }

  function renderBasicKeywords(container, text) {
    // 简易关键词匹配
    const regex = /\b(fn|let|mut|pub|priv|enum|struct|type|impl|match|with|for|in|while|return|if|else|import|package)\b|(".*?")/g;
    let lastIndex = 0;
    let match;

    while ((match = regex.exec(text)) !== null) {
      // 匹配之前的普通文本
      if (match.index > lastIndex) {
        container.appendChild(document.createTextNode(text.substring(lastIndex, match.index)));
      }

      const span = document.createElement('span');
      if (match[1]) {
        span.className = 'tok-kw';
        span.textContent = match[1];
      } else if (match[2]) {
        span.className = 'tok-str';
        span.textContent = match[2];
      }
      container.appendChild(span);
      lastIndex = regex.lastIndex;
    }

    if (lastIndex < text.length) {
      container.appendChild(document.createTextNode(text.substring(lastIndex)));
    }
  }

  /* ==========================================================================
     视窗模式切换 (Diff / Single / Bundle)
     ========================================================================== */
  function switchViewTab(viewMode) {
    state.activeView = viewMode;

    el.viewTabs.forEach(tab => {
      const isActive = tab.getAttribute('data-view') === viewMode;
      tab.classList.toggle('active', isActive);
      tab.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });

    if (!state.hasGenerated) {
      el.initialIdleContainer.style.display = 'flex';
      el.diffViewContainer.style.display = 'none';
      el.singleViewContainer.style.display = 'none';
      el.bundleViewContainer.style.display = 'none';
      return;
    }

    el.initialIdleContainer.style.display = 'none';
    el.diffViewContainer.style.display = viewMode === 'diff' ? 'flex' : 'none';
    el.singleViewContainer.style.display = viewMode === 'single' ? 'flex' : 'none';
    el.bundleViewContainer.style.display = viewMode === 'bundle' ? 'flex' : 'none';
  }

  /* ==========================================================================
     导出与剪贴板复制逻辑
     ========================================================================== */
  async function copyToClipboard(text, successMsg = '已复制到剪贴板') {
    if (!text) return;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
        showToast(successMsg);
      } else {
        fallbackCopyDialog(text);
      }
    } catch {
      fallbackCopyDialog(text);
    }
  }

  function fallbackCopyDialog(text) {
    el.copyFallbackTextarea.value = text;
    el.copyFallbackDialog.showModal();
    el.copyFallbackTextarea.focus();
    el.copyFallbackTextarea.select();
  }

  function downloadJsonFile() {
    if (!state.lastPackResult || !state.lastPackResult.result?.serialized) return;
    const serialized = state.lastPackResult.result.serialized;
    const blob = new Blob([serialized], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `context-${state.lastPackResult.profile || 'bundle'}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    showToast('完整原生序列化 JSON 已开始下载');
  }

  let toastTimer = null;
  function showToast(msg) {
    el.toastMessage.textContent = msg;
    el.toastNotification.classList.add('active');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      el.toastNotification.classList.remove('active');
    }, 2400);
  }

  /* ==========================================================================
     响应式侧边栏与折叠面板
     ========================================================================== */
  function toggleMobileNav(force) {
    const next = typeof force === 'boolean' ? force : !state.isMobileNavOpen;
    state.isMobileNavOpen = next;
    el.fileSidebar.classList.toggle('mobile-open', next);
    el.mobileNavToggle.setAttribute('aria-expanded', next ? 'true' : 'false');
  }

  function toggleAdvancedPanel() {
    state.isAdvancedOpen = !state.isAdvancedOpen;
    el.advancedPanel.style.display = state.isAdvancedOpen ? 'block' : 'none';
    el.toggleAdvancedBtn.setAttribute('aria-expanded', state.isAdvancedOpen ? 'true' : 'false');
  }

  /* ==========================================================================
     事件监听绑定
     ========================================================================== */
  function bindEvents() {
    // 策略切换
    el.profileTabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const profile = tab.getAttribute('data-profile');
        if (state.profile === profile) return;

        state.profile = profile;
        el.profileTabs.forEach(t => {
          const isActive = t.getAttribute('data-profile') === profile;
          t.classList.toggle('active', isActive);
          t.setAttribute('aria-selected', isActive ? 'true' : 'false');
        });

        // 仅在 mixed 下展示 keepFull
        el.keepFullGroup.style.display = profile === 'mixed' ? 'flex' : 'none';

        if (state.hasGenerated) {
          markStaleState();
        }
        updateCliCommand();
      });
    });

    // 预算快捷按钮
    el.budgetBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        el.budgetBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const bVal = parseInt(btn.getAttribute('data-budget'), 10);
        el.budgetThreshold.value = bVal;
        state.tokenBudget = bVal;
        updateCliCommand();

        if (state.hasGenerated) {
          renderPackSuccess(state.lastPackResult);
        }
      });
    });

    el.budgetThreshold.addEventListener('input', () => {
      const bVal = parseInt(el.budgetThreshold.value, 10);
      if (!isNaN(bVal) && bVal > 0) {
        state.tokenBudget = bVal;
        el.budgetBtns.forEach(b => {
          b.classList.toggle('active', parseInt(b.getAttribute('data-budget'), 10) === bVal);
        });
        updateCliCommand();
        if (state.hasGenerated) {
          renderPackSuccess(state.lastPackResult);
        }
      }
    });

    // 高级输入监听
    el.includePatternsInput.addEventListener('input', () => {
      state.includePatterns = parsePatternList(el.includePatternsInput.value);
      updateCliCommand();
      if (state.hasGenerated) markStaleState();
    });

    el.keepFullInput.addEventListener('input', () => {
      state.keepFull = parsePatternList(el.keepFullInput.value);
      updateCliCommand();
      if (state.hasGenerated) markStaleState();
    });

    el.toggleAdvancedBtn.addEventListener('click', toggleAdvancedPanel);

    // 打包生成触发
    el.packSubmitBtn.addEventListener('click', performPack);
    el.quickStartBtn.addEventListener('click', performPack);

    // 目录选择 Dialog
    el.selectDirBtn.addEventListener('click', openDirectoryDialog);
    el.closeDirectoryDialogBtn.addEventListener('click', closeDirectoryDialog);
    el.cancelDirSelectBtn.addEventListener('click', closeDirectoryDialog);
    el.confirmDirSelectBtn.addEventListener('click', confirmDirectorySelection);
    el.dirGoUpBtn.addEventListener('click', goUpDirectory);

    // 会话限制 Dialog
    el.sessionLimitsBtn.addEventListener('click', () => {
      el.sessionLimitsDialog.showModal();
    });
    el.closeSessionLimitsBtn.addEventListener('click', () => el.sessionLimitsDialog.close());
    el.closeSessionLimitsFooterBtn.addEventListener('click', () => el.sessionLimitsDialog.close());

    // 复制 Fallback Dialog
    el.closeCopyFallbackBtn.addEventListener('click', () => el.copyFallbackDialog.close());
    el.closeCopyFallbackFooterBtn.addEventListener('click', () => el.copyFallbackDialog.close());

    // CLI 复制与 JSON 导出
    el.copyCliBtn.addEventListener('click', () => {
      copyToClipboard(el.cliCommandText.textContent, '真实原生命令已复制');
    });

    el.copyJsonBtn.addEventListener('click', () => {
      if (state.lastPackResult?.result?.serialized) {
        copyToClipboard(state.lastPackResult.result.serialized, '完整原生序列化 JSON 已复制');
      }
    });

    el.downloadJsonBtn.addEventListener('click', downloadJsonFile);

    // 视窗模式切换
    el.viewTabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const mode = tab.getAttribute('data-view');
        switchViewTab(mode);
      });
    });

    // 路径与代码复制
    el.copyPathBtn.addEventListener('click', () => {
      if (state.selectedFile) {
        copyToClipboard(state.selectedFile, '已复制相对路径');
      }
    });

    el.copyCodeBtn.addEventListener('click', () => {
      if (!state.selectedFile || !state.lastPackResult) return;
      const targetCode = state.lastPackResult.result?.document?.files?.[state.selectedFile] || '';
      copyToClipboard(targetCode, '已复制当前文件输出正文');
    });

    // 搜索框
    el.fileSearchInput.addEventListener('input', () => {
      state.searchQuery = el.fileSearchInput.value;
      el.clearSearchBtn.style.display = state.searchQuery ? 'block' : 'none';
      if (state.lastPackResult) {
        renderFileList(state.lastPackResult);
      }
    });

    el.clearSearchBtn.addEventListener('click', () => {
      el.fileSearchInput.value = '';
      state.searchQuery = '';
      el.clearSearchBtn.style.display = 'none';
      if (state.lastPackResult) {
        renderFileList(state.lastPackResult);
      }
    });

    el.resetSearchBtn.addEventListener('click', () => {
      el.fileSearchInput.value = '';
      state.searchQuery = '';
      el.clearSearchBtn.style.display = 'none';
      if (state.lastPackResult) {
        renderFileList(state.lastPackResult);
      }
    });

    // 移动端侧栏折叠
    el.mobileNavToggle.addEventListener('click', () => toggleMobileNav());

    // 全局快捷键
    window.addEventListener('keydown', (e) => {
      // Cmd/Ctrl + Enter 触发生成
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault();
        performPack();
        return;
      }

      // 按 / 聚焦搜索框
      if (e.key === '/' && document.activeElement !== el.fileSearchInput &&
          document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
        e.preventDefault();
        el.fileSearchInput.focus();
        return;
      }

      // Esc 关闭 Dialog 或搜索框
      if (e.key === 'Escape') {
        if (el.directoryDialog.open) {
          closeDirectoryDialog();
        } else if (el.sessionLimitsDialog.open) {
          el.sessionLimitsDialog.close();
        } else if (el.copyFallbackDialog.open) {
          el.copyFallbackDialog.close();
        }
      }
    });

    // 点击服务状态 Pill 重试连接
    el.serviceStatusPill.addEventListener('click', () => {
      if (state.connectionStatus === 'offline' || state.connectionStatus === 'error') {
        fetchSession();
      }
    });
  }

  /* ==========================================================================
     入口初始化
     ========================================================================== */
  function init() {
    updateCliCommand();
    bindEvents();
    fetchSession();
  }

  // 页面加载完成后启动
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
