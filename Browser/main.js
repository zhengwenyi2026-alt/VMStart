// VMStart 镜像工具主进程：基于 Chromium 内核的镜像下载器，支持命令行控制
const { app, BrowserWindow, ipcMain, session, shell, dialog, Menu } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');

// Chromium 下载与网络的最佳配置：大文件分片并行下载、启用 QUIC
app.commandLine.appendSwitch('enable-features', 'ParallelDownloading');
app.commandLine.appendSwitch('enable-quic');

// 固定数据目录，命令行脚本从这里读取 state.json
app.setPath('userData', path.join(app.getPath('appData'), 'VMStart Image Tool'));

const PARTITION = 'persist:vmstart';
const IMAGE_EXTS = ['.iso', '.img', '.qcow2', '.vmdk', '.vdi', '.vhd', '.vhdx'];
const isZh = () => app.getLocale().toLowerCase().startsWith('zh');

let win = null;
const live = new Map();
let history = [];
let prefs = { autoAdd: false };
const pendingAdd = new Set();
let uiReady = false;
const commandQueue = [];
let stateTimer = null;

const dataFile = (name) => path.join(app.getPath('userData'), name);

function load(name, fallback) {
  try { return JSON.parse(fs.readFileSync(dataFile(name), 'utf8')); } catch { return fallback; }
}

function save(name, value) {
  fs.mkdirSync(app.getPath('userData'), { recursive: true });
  fs.writeFileSync(dataFile(name), JSON.stringify(value, null, 2));
}

const isImage = (file) => IMAGE_EXTS.includes(path.extname(file).toLowerCase());

// 下载目录下的同名文件自动加序号，避免覆盖已下载的镜像
function uniquePath(dir, filename) {
  const ext = path.extname(filename);
  const base = path.basename(filename, ext);
  let candidate = path.join(dir, filename);
  for (let i = 1; fs.existsSync(candidate); i++) candidate = path.join(dir, `${base} (${i})${ext}`);
  return candidate;
}

function snapshot(rec) {
  return {
    id: rec.id, filename: rec.filename, path: rec.path, url: rec.url,
    received: rec.received, total: rec.total, speed: rec.speed,
    state: rec.state, paused: rec.paused, isImage: isImage(rec.filename),
    queuedAdd: rec.queuedAdd, added: rec.added, time: rec.time,
  };
}

function allDownloads() {
  const items = [...live.values()].map(snapshot);
  return items.concat(history.filter((h) => !live.has(h.id))).sort((a, b) => b.time - a.time);
}

function broadcast() {
  if (win && !win.isDestroyed()) win.webContents.send('downloads', allDownloads());
  scheduleState();
}

// 节流写出当前状态，供命令行 `vmstart downloads` 读取
function scheduleState() {
  if (stateTimer) return;
  stateTimer = setTimeout(() => {
    stateTimer = null;
    try { save('state.json', { pid: process.pid, updated: Date.now(), autoAdd: prefs.autoAdd, downloads: allDownloads() }); } catch {}
  }, 400);
}

function persistHistory() {
  save('downloads.json', history.slice(0, 50));
}

function vmstartInstalled() {
  return app.getApplicationNameForProtocol('vmstart://').length > 0;
}

function addToVMStart(rec) {
  if (!vmstartInstalled()) {
    dialog.showMessageBox(win, {
      type: 'warning',
      message: isZh() ? '未找到 VMStart' : 'VMStart not found',
      detail: isZh() ? '请先安装 VMStart 到“应用程序”文件夹，再添加镜像。' : 'Install VMStart into the Applications folder first.',
    });
    return false;
  }
  shell.openExternal(`vmstart://add?path=${encodeURIComponent(rec.path)}`);
  rec.added = true;
  rec.queuedAdd = false;
  return true;
}

function finish(rec) {
  live.delete(rec.id);
  history = [snapshot(rec), ...history.filter((h) => h.id !== rec.id)];
  persistHistory();
  broadcast();
}

function trackDownload(item) {
  const filename = item.getFilename();
  const dir = path.join(app.getPath('downloads'), 'VMStart');
  fs.mkdirSync(dir, { recursive: true });
  const savePath = uniquePath(dir, filename);
  item.setSavePath(savePath);

  const fromCLI = item.getURLChain().some((u) => pendingAdd.has(u));
  item.getURLChain().forEach((u) => pendingAdd.delete(u));
  const rec = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    item, filename: path.basename(savePath), path: savePath, url: item.getURL(),
    received: 0, total: item.getTotalBytes(), speed: 0,
    state: 'progressing', paused: false, queuedAdd: (prefs.autoAdd || fromCLI) && isImage(filename), added: false,
    time: Date.now(), lastBytes: 0, lastTick: Date.now(),
  };
  live.set(rec.id, rec);

  item.on('updated', (_e, state) => {
    const now = Date.now();
    const bytes = item.getReceivedBytes();
    const dt = (now - rec.lastTick) / 1000;
    if (dt >= 0.5) {
      // 指数平滑速度，使剩余时间显示稳定
      const inst = Math.max(0, bytes - rec.lastBytes) / dt;
      rec.speed = rec.speed ? rec.speed * 0.7 + inst * 0.3 : inst;
      rec.lastBytes = bytes;
      rec.lastTick = now;
    }
    rec.received = bytes;
    rec.total = item.getTotalBytes();
    rec.paused = item.isPaused();
    rec.state = state === 'interrupted' ? 'interrupted' : 'progressing';
    broadcast();
  });

  item.once('done', (_e, state) => {
    rec.received = item.getReceivedBytes();
    rec.total = item.getTotalBytes() || rec.received;
    rec.speed = 0;
    rec.paused = false;
    rec.state = state;
    rec.item = null;
    if (state === 'completed' && rec.queuedAdd) addToVMStart(rec);
    rec.queuedAdd = false;
    finish(rec);
  });

  broadcast();
  if (win) win.webContents.send('download-started');
}

function createWindow() {
  win = new BrowserWindow({
    width: 1280, height: 820, minWidth: 820, minHeight: 520,
    titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 14, y: 16 },
    backgroundColor: '#f3f3f5', title: isZh() ? 'VMStart 镜像工具' : 'VMStart Image Tool',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true, nodeIntegration: false, webviewTag: true,
    },
  });
  uiReady = false;
  win.loadFile(path.join(__dirname, 'ui', 'index.html'));
  win.on('closed', () => { win = null; uiReady = false; });
}

function send(channel, data) {
  if (win && !win.isDestroyed()) win.webContents.send(channel, data);
}

function focusWindow() {
  if (!win) createWindow();
  if (win.isMinimized()) win.restore();
  win.show();
  app.focus({ steal: true });
}

// 按 id、序号（1 起，最新在前）或文件名关键字查找下载项
function findDownload(key) {
  const items = allDownloads();
  if (!key) return items.find((d) => d.state === 'progressing') || items[0];
  if (/^\d+$/.test(key) && Number(key) >= 1 && Number(key) <= items.length) return items[Number(key) - 1];
  const k = key.toLowerCase();
  return items.find((d) => d.id === key) || items.find((d) => d.filename.toLowerCase().includes(k));
}

// 从进程参数中提取命令，忽略 Chromium/Electron 开关与 macOS 的 -psn 参数
function parseCommand(argv) {
  const args = argv.slice(app.isPackaged ? 1 : 2);
  const words = args.filter((a) => !a.startsWith('-'));
  if (!words.length) return null;
  return { name: words[0].toLowerCase(), args: words.slice(1), add: args.includes('--add') };
}

function enqueue(cmd) {
  if (!cmd) return;
  if (cmd.name === 'quit') return runCommand(cmd);
  if (uiReady) return runCommand(cmd);
  commandQueue.push(cmd);
  if (!win && app.isReady()) createWindow();
}

function runCommand({ name, args, add }) {
  const arg = args[0];
  if (name !== 'quit') focusWindow();
  switch (name) {
    case 'open':
      if (arg) send('open-url', /^(https?|file):\/\//i.test(arg) ? arg : `https://${arg}`);
      break;
    case 'download':
      if (!arg) break;
      if (add) pendingAdd.add(arg);
      send('show-downloads', true);
      session.fromPartition(PARTITION).downloadURL(arg);
      break;
    case 'add': {
      if (!arg) break;
      const file = path.resolve(arg);
      if (!fs.existsSync(file) || !isImage(file)) {
        dialog.showMessageBox(win, { type: 'warning', message: isZh() ? '无法添加镜像' : 'Unable to Add Image',
          detail: isZh() ? `镜像不存在或格式不受支持：${file}` : `Image missing or unsupported: ${file}` });
        break;
      }
      const st = fs.statSync(file);
      const rec = { id: `cli-${Date.now()}`, filename: path.basename(file), path: file, url: `file://${file}`,
        received: st.size, total: st.size, speed: 0, state: 'completed', paused: false, queuedAdd: false, added: false, time: Date.now() };
      if (addToVMStart(rec)) {
        history = [snapshot(rec), ...history.filter((h) => h.path !== file)];
        persistHistory();
      }
      send('show-downloads', true);
      broadcast();
      break;
    }
    case 'downloads':
      send('show-downloads', arg !== 'hide');
      break;
    case 'auto-add':
      prefs.autoAdd = arg !== 'off';
      save('prefs.json', prefs);
      send('prefs', prefs);
      send('show-downloads', true);
      scheduleState();
      break;
    case 'pause':
    case 'resume':
    case 'cancel': {
      const d = findDownload(arg);
      const rec = d && live.get(d.id);
      if (rec && rec.item) {
        if (name === 'pause') rec.item.pause();
        else if (name === 'resume' && rec.item.canResume()) rec.item.resume();
        else if (name === 'cancel') rec.item.cancel();
        // cancel() 会同步触发 done 并清空 rec.item
        if (rec.item) rec.paused = rec.item.isPaused();
      }
      send('show-downloads', true);
      broadcast();
      break;
    }
    case 'home':
    case 'back':
    case 'forward':
    case 'reload':
      send(name);
      break;
    case 'quit':
      live.forEach((r) => r.item && r.item.cancel());
      clearState();
      // 稍后退出，先让转发进程收到确认，否则它会等待超时后自行成为主实例
      setTimeout(() => app.exit(0), 300);
      break;
    default:
      break;
  }
}

function buildMenu() {
  const zh = isZh();
  const send = (ch) => () => win && win.webContents.send(ch);
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { role: 'appMenu' },
    { label: zh ? '文件' : 'File', submenu: [
      { label: zh ? '打开地址…' : 'Open Location…', accelerator: 'CmdOrCtrl+L', click: send('focus-address') },
      { type: 'separator' }, { role: 'close' } ] },
    { role: 'editMenu' },
    { label: zh ? '显示' : 'View', submenu: [
      { label: zh ? '重新载入' : 'Reload', accelerator: 'CmdOrCtrl+R', click: send('reload') },
      { label: zh ? '下载内容' : 'Downloads', accelerator: 'CmdOrCtrl+Shift+J', click: send('toggle-downloads') },
      { type: 'separator' }, { role: 'togglefullscreen' } ] },
    { label: zh ? '历史' : 'History', submenu: [
      { label: zh ? '后退' : 'Back', accelerator: 'CmdOrCtrl+[', click: send('back') },
      { label: zh ? '前进' : 'Forward', accelerator: 'CmdOrCtrl+]', click: send('forward') },
      { label: zh ? '主页' : 'Home', accelerator: 'CmdOrCtrl+Shift+H', click: send('home') } ] },
    { role: 'windowMenu' },
  ]));
}

const launchCommand = parseCommand(process.argv);
if (!app.requestSingleInstanceLock()) {
  // 已有实例在运行：参数已随加锁请求转交，直接退出，app.quit() 在 ready 前会挂住
  process.exit(0);
} else if (launchCommand && launchCommand.name === 'quit') {
  // 退出命令抢到了锁说明原实例已退出，无需再启动
  clearState();
  process.exit(0);
} else {
  app.on('second-instance', (_e, argv) => {
    const cmd = parseCommand(argv);
    if (cmd) enqueue(cmd); else focusWindow();
  });
}

app.whenReady().then(() => {
  history = load('downloads.json', []).filter((h) => h.state === 'completed' && fs.existsSync(h.path)).map((h) => ({ ...h, queuedAdd: false }));
  prefs = { ...prefs, ...load('prefs.json', {}) };

  const ses = session.fromPartition(PARTITION);
  ses.on('will-download', (_e, item) => trackDownload(item));

  // 网页弹出的新窗口统一在当前浏览器中打开
  app.on('web-contents-created', (_e, wc) => {
    if (wc.getType() !== 'webview') return;
    wc.setWindowOpenHandler(({ url }) => {
      if (win) win.webContents.send('open-url', url);
      return { action: 'deny' };
    });
  });

  ipcMain.handle('env', () => ({ locale: isZh() ? 'zh' : 'en', arch: process.arch, home: os.homedir(), partition: PARTITION }));
  ipcMain.handle('list', () => allDownloads());
  ipcMain.on('ui-ready', () => {
    uiReady = true;
    commandQueue.splice(0).forEach(runCommand);
  });
  ipcMain.handle('prefs', () => prefs);
  ipcMain.handle('set-auto-add', (_e, on) => { prefs.autoAdd = !!on; save('prefs.json', prefs); return prefs; });

  ipcMain.handle('action', (_e, id, act) => {
    const rec = live.get(id);
    const hist = history.find((h) => h.id === id);
    if (act === 'add') {
      if (rec) {
        // 下载中点击：完成后自动按最佳配置添加
        rec.queuedAdd = !rec.queuedAdd;
      } else if (hist && fs.existsSync(hist.path)) {
        if (addToVMStart(hist)) persistHistory();
      }
    } else if (act === 'pause' && rec && rec.item) {
      rec.item.isPaused() ? rec.item.resume() : rec.item.pause();
      rec.paused = rec.item.isPaused();
    } else if (act === 'resume' && rec && rec.item && rec.item.canResume()) {
      rec.item.resume();
    } else if (act === 'cancel') {
      if (rec && rec.item) rec.item.cancel();
      else if (hist) { history = history.filter((h) => h.id !== id); persistHistory(); }
    } else if (act === 'reveal') {
      const p = (rec || hist || {}).path;
      if (p && fs.existsSync(p)) shell.showItemInFolder(p);
    } else if (act === 'clear') {
      history = [];
      persistHistory();
    }
    broadcast();
  });

  buildMenu();
  createWindow();
  enqueue(launchCommand);
  scheduleState();
  app.on('activate', () => { if (!win) createWindow(); });
});

function clearState() {
  clearTimeout(stateTimer);
  stateTimer = null;
  try { fs.rmSync(dataFile('state.json'), { force: true }); } catch {}
}

app.on('will-quit', clearState);

app.on('window-all-closed', () => {
  if ([...live.values()].some((r) => r.state === 'progressing')) return;
  app.quit();
});
