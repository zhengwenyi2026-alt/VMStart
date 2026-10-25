const $ = (id) => document.getElementById(id);

const STR = {
  zh: {
    downloads: '最近下载', clear: '清除记录', empty: '暂无下载内容',
    autoAdd: '镜像下载完成后自动按最佳配置添加到 VMStart',
    addTip: '按最佳配置添加到 VMStart', queuedTip: '下载完成后将自动添加，点击取消',
    addedTip: '已添加到 VMStart，点击再次添加',
    pause: '暂停', resume: '继续', cancel: '取消', remove: '从列表中移除', reveal: '在访达中显示',
    left: '还剩', sec: '秒', min: '分钟', hour: '小时', done: '已完成', cancelled: '已取消',
    failed: '下载失败', paused: '已暂停', queued: '完成后自动添加', added: '已添加到 VMStart',
    detected: '识别为', search: '搜索或输入网址',
  },
  en: {
    downloads: 'Recent downloads', clear: 'Clear', empty: 'No downloads yet',
    autoAdd: 'Add finished images to VMStart with the best configuration',
    addTip: 'Add to VMStart with best configuration', queuedTip: 'Will be added when finished. Click to cancel',
    addedTip: 'Added to VMStart. Click to add again',
    pause: 'Pause', resume: 'Resume', cancel: 'Cancel', remove: 'Remove from list', reveal: 'Show in Finder',
    left: '', sec: 's left', min: 'min left', hour: 'h left', done: 'Done', cancelled: 'Cancelled',
    failed: 'Failed', paused: 'Paused', queued: 'Adds when finished', added: 'Added to VMStart',
    detected: 'Detected as', search: 'Search or enter address',
  },
};

let env = { locale: 'zh', arch: 'arm64' };
let T = STR.zh;
const view = $('view');
let homeURL = '';
let viewReady = false;
let pendingURL = '';

// webview 首次 dom-ready 前不能调用 loadURL，先暂存
function loadWhenReady(url) {
  if (viewReady) view.loadURL(url); else pendingURL = url;
}

// 与 VMStart 端识别规则保持一致，仅用于提示
function guessOS(name) {
  const n = name.toLowerCase();
  const arch = /arm64|aarch64/.test(n) ? 'ARM64' : (/x64|amd64|x86_64/.test(n) ? 'x64' : (/i386|i686|x86/.test(n) ? 'x86' : ''));
  const table = [
    [/win(dows)?[ _-]?11|win11/, 'Windows 11'], [/win(dows)?[ _-]?10|win10/, 'Windows 10'],
    [/win(dows)?[ _-]?(8|8\.1)\b/, 'Windows 8'], [/win(dows)?[ _-]?7|win7/, 'Windows 7'],
    [/windows[ _-]?xp|winxp/, 'Windows XP'], [/server/, 'Windows Server'],
    [/ubuntu|kubuntu|xubuntu|lubuntu/, 'Ubuntu'], [/debian/, 'Debian'], [/fedora/, 'Fedora'],
    [/centos|rocky|alma|rhel/, 'CentOS / RHEL'], [/archlinux|arch-?linux|^arch-/, 'Arch Linux'],
    [/freebsd/, 'FreeBSD'], [/openbsd/, 'OpenBSD'], [/android/, 'Android'], [/reactos/, 'ReactOS'],
    [/haiku/, 'Haiku'], [/mint|manjaro|opensuse|kali|alpine|deepin|ubuntukylin|linux/, 'Linux'],
  ];
  const hit = table.find(([re]) => re.test(n));
  if (!hit) return '';
  return arch ? `${hit[1]} · ${arch}` : hit[1];
}

function fmtBytes(b) {
  if (!b) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(b) / Math.log(1024)), u.length - 1);
  return `${(b / 1024 ** i).toFixed(i >= 3 ? 1 : 0)} ${u[i]}`;
}

// 已下载量与总量用同一单位显示，如 0.0/8.2 GB
function fmtProgress(r, t) {
  if (!t) return fmtBytes(r);
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(t) / Math.log(1024)), u.length - 1);
  const d = i >= 3 ? 1 : 0;
  return `${(r / 1024 ** i).toFixed(d)}/${(t / 1024 ** i).toFixed(d)} ${u[i]}`;
}

function fmtETA(sec) {
  if (!isFinite(sec) || sec <= 0) return '';
  const zh = env.locale === 'zh';
  if (sec < 60) return zh ? `${T.left} ${Math.ceil(sec)} ${T.sec}` : `${Math.ceil(sec)}${T.sec}`;
  if (sec < 3600) return zh ? `${T.left} ${Math.ceil(sec / 60)} ${T.min}` : `${Math.ceil(sec / 60)} ${T.min}`;
  const h = (sec / 3600).toFixed(1).replace(/\.0$/, '');
  return zh ? `${T.left} ${h} ${T.hour}` : `${h}${T.hour}`;
}

function statusHTML(d) {
  const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  if (d.state === 'progressing') {
    const parts = [`↓ ${fmtProgress(d.received, d.total)}`];
    if (d.paused) parts.push(T.paused);
    else if (d.speed > 0 && d.total) parts.push(fmtETA((d.total - d.received) / d.speed));
    if (d.queuedAdd) parts.push(`<span class="ok">${T.queued}</span>`);
    return parts.filter(Boolean).join(' • ');
  }
  if (d.state === 'completed') {
    const parts = [fmtBytes(d.total), d.added ? `<span class="ok">${T.added}</span>` : T.done];
    const os = d.isImage ? guessOS(d.filename) : '';
    if (os && !d.added) parts.push(esc(os));
    return parts.join(' • ');
  }
  if (d.state === 'cancelled') return T.cancelled;
  return `<span class="warn">${T.failed}</span>`;
}

function render(items) {
  const list = $('list');
  list.textContent = '';
  $('empty').style.display = items.length ? 'none' : 'block';
  const tpl = $('item-tpl');
  for (const d of items) {
    const node = tpl.content.firstElementChild.cloneNode(true);
    const running = d.state === 'progressing';
    node.classList.toggle('paused', !!d.paused);
    node.querySelector('.name').textContent = d.filename;
    node.querySelector('.name').title = d.path;
    node.querySelector('.status').innerHTML = statusHTML(d);

    const add = node.querySelector('.add');
    const canAdd = d.isImage && (running || d.state === 'completed');
    add.classList.toggle('show', canAdd);
    add.classList.toggle('queued', !!d.queuedAdd);
    add.classList.toggle('done', !!d.added);
    const os = guessOS(d.filename);
    add.title = d.queuedAdd ? T.queuedTip : d.added ? T.addedTip : (os ? `${T.addTip}（${T.detected} ${os}）` : T.addTip);

    const pause = node.querySelector('.pause');
    pause.classList.toggle('show', running);
    pause.classList.toggle('paused', !!d.paused);
    pause.title = d.paused ? T.resume : T.pause;

    node.querySelector('.reveal').classList.toggle('show', d.state === 'completed');
    node.querySelector('.reveal').title = T.reveal;
    const cancel = node.querySelector('.cancel');
    cancel.classList.add('show');
    cancel.title = running ? T.cancel : T.remove;

    const bar = node.querySelector('.bar');
    bar.classList.toggle('hidden', !running);
    node.querySelector('.fill').style.width = d.total ? `${(d.received / d.total) * 100}%` : '0%';

    node.querySelectorAll('.act').forEach((b) => b.addEventListener('click', () => window.vmsb.action(d.id, b.dataset.act)));
    list.appendChild(node);
  }
  updateRing(items);
}

function updateRing(items) {
  const running = items.filter((d) => d.state === 'progressing');
  const btn = $('dl-btn');
  btn.classList.toggle('active', running.length > 0);
  const total = running.reduce((s, d) => s + (d.total || 0), 0);
  const got = running.reduce((s, d) => s + d.received, 0);
  const ratio = total ? got / total : 0;
  $('ring').style.strokeDashoffset = String(94.25 * (1 - ratio));
}

function togglePanel(force) {
  const p = $('panel');
  const show = force === undefined ? p.classList.contains('hidden') : force;
  p.classList.toggle('hidden', !show);
}

function navigate(text) {
  const t = text.trim();
  if (!t) return;
  let url;
  if (/^(https?|file):\/\//i.test(t)) url = t;
  else if (/^[\w-]+(\.[\w-]+)+(:\d+)?(\/.*)?$/.test(t)) url = `https://${t}`;
  else url = `https://www.bing.com/search?q=${encodeURIComponent(t)}`;
  view.loadURL(url);
}

function syncNav() {
  $('back').disabled = !view.canGoBack();
  $('forward').disabled = !view.canGoForward();
  const url = view.getURL();
  if (document.activeElement !== $('address')) $('address').value = url.startsWith('file:') ? '' : url;
}

async function init() {
  env = await window.vmsb.env();
  T = STR[env.locale] || STR.zh;
  document.documentElement.lang = env.locale;
  $('address').placeholder = T.search;
  $('panel-title').textContent = T.downloads;
  $('clear').textContent = T.clear;
  $('empty').textContent = T.empty;
  $('auto-add-label').textContent = T.autoAdd;
  $('dl-btn').title = T.downloads;

  homeURL = new URL(`start.html?lang=${env.locale}&arch=${env.arch}`, location.href).href;
  view.src = homeURL;

  const prefs = await window.vmsb.prefs();
  $('auto-add').checked = !!prefs.autoAdd;
  $('auto-add').addEventListener('change', (e) => window.vmsb.setAutoAdd(e.target.checked));

  view.addEventListener('dom-ready', () => {
    if (viewReady) return;
    viewReady = true;
    if (pendingURL) view.loadURL(pendingURL);
  });
  view.addEventListener('did-navigate', syncNav);
  view.addEventListener('did-navigate-in-page', syncNav);
  view.addEventListener('did-start-loading', () => { $('loadbar').style.opacity = 1; $('loadbar').style.width = '60%'; });
  view.addEventListener('did-stop-loading', () => {
    $('loadbar').style.width = '100%';
    setTimeout(() => { $('loadbar').style.opacity = 0; $('loadbar').style.width = '0'; }, 300);
    syncNav();
  });
  view.addEventListener('page-title-updated', (e) => { document.title = e.title; });

  $('back').onclick = () => view.goBack();
  $('forward').onclick = () => view.goForward();
  $('reload').onclick = () => view.reload();
  $('home').onclick = () => view.loadURL(homeURL);
  $('address-form').onsubmit = (e) => { e.preventDefault(); navigate($('address').value); view.focus(); };
  $('address').addEventListener('focus', () => $('address').select());
  $('dl-btn').onclick = (e) => { e.stopPropagation(); togglePanel(); };
  $('clear').onclick = () => window.vmsb.action('', 'clear');
  document.addEventListener('mousedown', (e) => {
    if (!$('panel').contains(e.target) && !$('dl-btn').contains(e.target)) togglePanel(false);
  });
  view.addEventListener('focus', () => togglePanel(false));

  window.vmsb.on('downloads', render);
  window.vmsb.on('download-started', () => {
    togglePanel(true);
    $('dl-btn').classList.remove('pulse');
    void $('dl-btn').offsetWidth;
    $('dl-btn').classList.add('pulse');
  });
  window.vmsb.on('open-url', (url) => loadWhenReady(url));
  window.vmsb.on('focus-address', () => $('address').focus());
  window.vmsb.on('reload', () => view.reload());
  window.vmsb.on('toggle-downloads', () => togglePanel());
  window.vmsb.on('show-downloads', (show) => togglePanel(show));
  window.vmsb.on('prefs', (p) => { $('auto-add').checked = !!p.autoAdd; });
  window.vmsb.on('back', () => view.canGoBack() && view.goBack());
  window.vmsb.on('forward', () => view.canGoForward() && view.goForward());
  window.vmsb.on('home', () => loadWhenReady(homeURL));

  render(await window.vmsb.list());
  window.vmsb.ready();
}

init();
