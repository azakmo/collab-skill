// UI strings for the console and ledger pages. Default language comes from the server (roster "language" /
// COLLAB_LANG, injected as __DEFAULT_LANG__); the toggle button stores the viewer's choice in localStorage.
const I18N = {
  en: {
    // console
    consoleTitle: 'Collab Console',
    ledgerLink: 'Ledger →',
    consoleSub: 'Choose which executors and models layers 2 and 3 use. Saving writes <code>roster.json</code>; dispatch scripts can only call models ticked here.',
    fixed: 'fixed',
    layer1: 'Layer 1 · Controller: Claude Code',
    layer2: 'Layer 2 · Implement / review',
    layer3: 'Layer 3 · Labor',
    layer2Short: 'Layer 2 · Implement/review',
    layer3Short: 'Layer 3 · Labor',
    providersSummary: 'Model sources (providers)',
    providersNote: 'Keys are not entered here: set them as Windows user environment variables first, and only enter the variable name here.',
    addProvider: 'Add model source',
    addProviderHint: '(OpenAI-compatible endpoint, e.g. a hosted model or one running on another machine in your LAN)',
    lblId: 'id', lblName: 'Name', lblUrl: 'URL', lblKeyVar: 'Key variable', lblWire: 'Wire format',
    lblProvider: 'Source', lblLayer: 'Layer', lblTier: 'Tier', lblCost: 'Cost', lblDefaultModel: 'Default model',
    phProviderId: 'e.g. deepseek (lowercase)', phDisplayName: 'Display name', phEnv: 'Env var name, e.g. DEEPSEEK_API_KEY',
    phExecutorId: 'e.g. deepseek-labor (lowercase)', phNotes: 'Good at / bad at',
    wireResponses: 'responses (required by the Codex harness)',
    wireChat: 'chat (may not work with the Codex harness, test it)',
    add: 'Add',
    addExecutor: 'Add executor',
    addExecutorHint: '(after adding, click "Probe models" and tick some)',
    discard: 'Discard changes', save: 'Save',
    loaded: 'Loaded',
    emptyLayer: '(no executors in this layer yet)',
    thId: 'id', thName: 'Name', thKind: 'Type', thUrl: 'URL', thKeyVar: 'Key variable',
    envSet: 'set', envUnset: 'not set',
    enable: 'Enabled',
    pickModelsFirst: '(tick models first)',
    probe: 'Probe models',
    probeHint: 'Click "Probe models" to list the models this source offers',
    probing: 'Probing {0} …',
    probeFail: 'Probe failed: ',
    probeOk: '{0}: found {1} model(s) (remember to save after ticking)',
    idInvalid: 'id may only contain lowercase letters, digits, - and _',
    idExists: 'This id already exists',
    urlInvalid: 'URL must start with http:// or https://',
    envInvalid: 'Key variable is an environment variable name, not the key itself',
    providerAdded: 'Added model source {0} (not saved yet)',
    executorAdded: 'Added executor {0}: probe and tick models, then enable it (not saved yet)',
    saved: 'Saved to roster.json (previous version backed up as roster.json.bak)',
    notSaved: 'Not saved: ',
    loadFail: 'Load failed: ',
    // ledger
    ledgerTitle: 'Ledger',
    backToRoster: '← Roster',
    refresh: 'Refresh',
    byExecType: 'By executor × task type',
    noData: 'No data yet',
    thExecutor: 'Executor', thType: 'Type', thRuns: 'Runs', thPassRate: 'Pass rate', thAvgTokens: 'Avg tokens', thAvgTime: 'Avg time',
    all: 'All',
    byProject: 'By project: CC vs executor spend',
    thProject: 'Project', thDispatches: 'Dispatches', thExecTokens: 'Executor tokens', thCcEquiv: 'CC equiv. tokens',
    thCcRaw: 'CC raw tokens', thCcTime: 'CC time', thRatio: 'CC / executors',
    barExecutor: 'Executors', barCc: 'CC equiv.',
    trend: 'Token trend per collaboration',
    tipExecTokens: 'Executor tokens', tipCcTokens: 'CC equiv. tokens',
    scatter: 'Tokens per dispatch',
    meta: 'Data: {0} · {1} rows', skipped: ' · {0} rows skipped', generated: ' · generated {0}',
    minutes: '{0} min',
    review: { '通过': 'pass', '返工': 'rework', '失败': 'failed', '取消': 'cancelled' },
  },
  'zh-CN': {
    consoleTitle: '协同控制台',
    ledgerLink: '账本 →',
    consoleSub: '在这里选第二层、第三层用哪些执行者和模型。保存后写入 <code>roster.json</code>；派活脚本只能调用这里勾选过的模型。',
    fixed: '固定',
    layer1: '第一层 · 主控：Claude Code',
    layer2: '第二层 · 实现 / 初审',
    layer3: '第三层 · 苦力',
    layer2Short: '第二层 · 实现/初审',
    layer3Short: '第三层 · 苦力',
    providersSummary: '模型来源（providers）',
    providersNote: '密钥不填在这里：先在 Windows 用户环境变量里设好，这里只写变量名。',
    addProvider: '新增模型来源',
    addProviderHint: '（OpenAI 兼容接口，比如国产模型或局域网里其他电脑上的模型）',
    lblId: 'id', lblName: '名称', lblUrl: '地址', lblKeyVar: '密钥变量', lblWire: '接口格式',
    lblProvider: '模型来源', lblLayer: '分层', lblTier: '能力等级', lblCost: '成本', lblDefaultModel: '默认模型',
    phProviderId: '如 deepseek（小写）', phDisplayName: '显示名', phEnv: '环境变量名，如 DEEPSEEK_API_KEY',
    phExecutorId: '如 deepseek-labor（小写）', phNotes: '擅长 / 不擅长',
    wireResponses: 'responses（Codex 执行壳要求）',
    wireChat: 'chat（可能接不上 Codex 执行壳，要实测）',
    add: '加入',
    addExecutor: '新增执行者',
    addExecutorHint: '（加入后点「探测模型」再勾选）',
    discard: '放弃修改', save: '保存',
    loaded: '已载入',
    emptyLayer: '（这一层还没有执行者）',
    thId: 'id', thName: '名称', thKind: '类型', thUrl: '地址', thKeyVar: '密钥变量',
    envSet: '已设置', envUnset: '未设置',
    enable: '启用',
    pickModelsFirst: '（先勾选模型）',
    probe: '探测模型',
    probeHint: '点「探测模型」读取这个来源的可用模型',
    probing: '正在探测 {0} …',
    probeFail: '探测失败：',
    probeOk: '{0}：找到 {1} 个模型（勾选后记得保存）',
    idInvalid: 'id 只能用小写字母、数字、- 和 _',
    idExists: '这个 id 已经存在',
    urlInvalid: '地址要以 http:// 或 https:// 开头',
    envInvalid: '密钥变量只填环境变量名，不要填密钥本身',
    providerAdded: '已加入模型来源 {0}（还没保存）',
    executorAdded: '已加入执行者 {0}：探测并勾选模型后再启用（还没保存）',
    saved: '已保存到 roster.json（旧版本备份为 roster.json.bak）',
    notSaved: '没保存：',
    loadFail: '载入失败：',
    ledgerTitle: '账本',
    backToRoster: '← 名册',
    refresh: '刷新',
    byExecType: '按执行者 × 任务类型',
    noData: '还没有数据',
    thExecutor: '执行者', thType: '类型', thRuns: '次数', thPassRate: '通过率', thAvgTokens: '平均 token', thAvgTime: '平均用时',
    all: '全部',
    byProject: '按项目：CC 与执行者花销',
    thProject: '项目', thDispatches: '派活次数', thExecTokens: '执行者 token', thCcEquiv: 'CC 等效 token',
    thCcRaw: 'CC 原始 token', thCcTime: 'CC 用时', thRatio: 'CC / 执行者',
    barExecutor: '执行者', barCc: 'CC 等效',
    trend: '每次协同的 token 趋势',
    tipExecTokens: '执行者 token', tipCcTokens: 'CC 等效 token',
    scatter: '单次派活 token 散点图',
    meta: '数据：{0} · {1} 行', skipped: ' · 跳过 {0} 行', generated: ' · 生成于 {0}',
    minutes: '{0} 分',
    review: {},
  },
};

const LANG = (() => {
  let l = null;
  try { l = localStorage.getItem('collab-lang'); } catch (e) {}
  return I18N[l] ? l : (I18N['__DEFAULT_LANG__'] ? '__DEFAULT_LANG__' : 'en');
})();
document.documentElement.lang = LANG;

// t('key', arg0, arg1, ...) → string with {0}, {1}, ... filled in
function t(key, ...args) {
  const s = I18N[LANG][key] ?? I18N.en[key] ?? key;
  return String(s).replace(/\{(\d+)\}/g, (_, i) => args[i] ?? '');
}

// Ledger stores review verdicts in Chinese; show them in the UI language.
function tReview(v) { return (I18N[LANG].review || {})[v] || v; }

// Number of tokens: 1.2万 in Chinese, 12.3k / 1.23M in English.
function fmtTokenI18n(n) {
  if (n === null || n === undefined) return '—';
  if (LANG === 'zh-CN') return n < 10000 ? String(n) : (n / 10000).toFixed(1) + '万';
  if (n < 1000) return String(n);
  if (n < 1e6) return (n / 1000).toFixed(1) + 'k';
  return (n / 1e6).toFixed(2) + 'M';
}

// Static markup: data-i18n (text), data-i18n-html (trusted dictionary HTML), data-i18n-ph (placeholder).
function applyI18n(root = document) {
  root.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
  root.querySelectorAll('[data-i18n-html]').forEach(el => { el.innerHTML = t(el.dataset.i18nHtml); });
  root.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = t(el.dataset.i18nPh); });
  const btn = document.getElementById('lang-btn');
  if (btn) btn.textContent = LANG === 'zh-CN' ? 'English' : '中文';
}

function toggleLang() {
  try { localStorage.setItem('collab-lang', LANG === 'zh-CN' ? 'en' : 'zh-CN'); } catch (e) {}
  location.reload();
}

// Header sent with every API call so server-side error messages match the UI language.
const LANG_HEADER = { 'X-Lang': LANG };
