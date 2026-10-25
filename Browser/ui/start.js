const params = new URLSearchParams(location.search);
const zh = params.get('lang') === 'zh';
const arch = params.get('arch') || 'arm64';
const s = zh ? {
  name: 'VMStart 镜像工具',
  subtitle: '系统镜像下载与 VMStart 虚拟机一键创建', search: '搜索镜像或输入网址', go: '搜索',
  recommended: '官方系统镜像', device: arch === 'arm64' ? 'Apple 芯片 · 优先选择 ARM64' : 'Intel 芯片 · 优先选择 x64',
  win: arch === 'arm64' ? '建议下载 ARM64 版本' : '建议下载 x64 版本',
  linux: arch === 'arm64' ? '选择 ARM64 / aarch64 镜像' : '选择 AMD64 / x86_64 镜像',
  howTitle: '一键按最佳配置添加到 VMStart',
  howText: '镜像下载时打开右上角下载面板，点击带加号的 VMStart 图标。下载完成后会自动识别系统与架构，并创建最合适的 CPU、内存、磁盘和加速配置。',
} : {
  name: 'VMStart Image Tool',
  subtitle: 'Download OS images and create VMStart virtual machines in one step', search: 'Search images or enter address', go: 'Search',
  recommended: 'Official OS images', device: arch === 'arm64' ? 'Apple silicon · Prefer ARM64' : 'Intel Mac · Prefer x64',
  win: arch === 'arm64' ? 'ARM64 image recommended' : 'x64 image recommended',
  linux: arch === 'arm64' ? 'Choose ARM64 / aarch64' : 'Choose AMD64 / x86_64',
  howTitle: 'Add to VMStart with the best configuration',
  howText: 'Open Downloads and click the VMStart plus icon. VMStart detects the OS and architecture, then creates optimized CPU, memory, disk and acceleration settings.',
};
document.documentElement.lang = zh ? 'zh-Hans' : 'en';
document.title = s.name;
document.querySelector('#brand-name').textContent = s.name;
document.querySelector('#subtitle').textContent = s.subtitle;
document.querySelector('#q').placeholder = s.search;
document.querySelector('#go').textContent = s.go;
document.querySelector('#recommended-title').textContent = s.recommended;
document.querySelector('#device').textContent = s.device;
document.querySelector('#win-note').textContent = s.win;
for (const id of ['ubuntu-note', 'fedora-note', 'debian-note']) document.querySelector(`#${id}`).textContent = s.linux;
document.querySelector('#how-title').textContent = s.howTitle;
document.querySelector('#how-text').textContent = s.howText;
document.querySelector('#search').addEventListener('submit', (e) => {
  e.preventDefault();
  const q = document.querySelector('#q').value.trim();
  if (q) location.href = `https://www.bing.com/search?q=${encodeURIComponent(q)}`;
});
