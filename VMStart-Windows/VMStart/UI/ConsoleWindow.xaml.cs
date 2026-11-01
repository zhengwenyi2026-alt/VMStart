using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using VMStart.Models;
using VMStart.Engine;

namespace VMStart.UI
{
    public partial class ConsoleWindow : Window
    {
        private readonly VirtualMachine _vm;
        private QEMUEngine _engine;
        private bool _isPaused;
        private readonly StringBuilder _logBuffer = new();
        private int _activeTab; // 0=display, 1=log, 2=serial
        private int _serialPort;

        public bool IsVMRunning => _engine.IsRunning;
        public VirtualMachine VM => _vm;
        public event Action VMStateChanged;

        public void SendMonitorCommand(string command) => _engine.SendMonitorCommand(command);

        public ConsoleWindow(VirtualMachine vm)
        {
            InitializeComponent();
            _vm = vm;
            Title = $"{vm.Name} — VMStart Console";
            ToolbarVMName.Text = vm.Name;

            _engine = new QEMUEngine(vm);
            _engine.OnOutput += AppendLog;
            _engine.OnError += AppendLog;
            _engine.OnStarted += () => Dispatcher.InvokeAsync(OnVMStarted);
            _engine.OnStopped += (code) => Dispatcher.InvokeAsync(() => OnVMStopped(code));

            VNCViewer.OnConnected += () =>
            {
                AppendLog("[VNC] Display connected");
                StatusBar.Text = $"Running ({VNCViewer.FramebufferWidth}x{VNCViewer.FramebufferHeight})";
            };
            VNCViewer.OnDisconnected += () => AppendLog("[VNC] Display disconnected");

            Closed += (s, e) =>
            {
                VNCViewer?.Dispose();
                SerialTerminal?.Dispose();
                _engine.Dispose();
            };
        }

        // 每台虚拟机各自取空闲端口，多台同时运行时不会冲突
        private static int FreeTcpPort()
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }

        private static int FreeVncPort()
        {
            for (int port = 5900; port < 6000; port++)
            {
                try
                {
                    var listener = new TcpListener(IPAddress.Loopback, port);
                    listener.Start();
                    listener.Stop();
                    return port;
                }
                catch (SocketException) { }
            }
            throw new InvalidOperationException("No free VNC port in 5900-5999");
        }

        public void StartVM()
        {
            if (_engine.IsRunning) return;
            ShowSplash("Starting virtual machine...");

            try
            {
                _vm.VncPort = FreeVncPort();
                _serialPort = FreeTcpPort();
                _engine.RuntimeArgs.Clear();
                _engine.RuntimeArgs.AddRange(new[] { "-serial", $"tcp:127.0.0.1:{_serialPort},server=on,wait=off" });
                _engine.Start();
            }
            catch (Exception ex)
            {
                HideSplash();
                AppendLog($"[ERROR] {ex.Message}");
                StatusBar.Text = "Failed to start";
                MessageBox.Show(this, ex.Message, "VMStart", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        public void StopVM()
        {
            if (!_engine.IsRunning) return;
            AppendLog("[VMStart] Sending shutdown signal...");
            _engine.Stop();
            StatusBar.Text = "Stopping...";
        }

        private void OnVMStarted()
        {
            HideSplash();
            StartStopBtn.Content = "⏹ Stop";
            PauseBtn.IsEnabled = true;
            CaptureBtn.IsEnabled = true;
            StatusBar.Text = $"Running (PID: {_engine.ProcessId})";
            AppendLog("[VMStart] Virtual machine started successfully.");
            VMStateChanged?.Invoke();

            int vncPort = _vm.VncPort, serialPort = _serialPort;
            // 稍候再连，等 QEMU 开始监听
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.0) };
            timer.Tick += (s, args) =>
            {
                timer.Stop();
                if (!_engine.IsRunning) return;
                AppendLog($"[VNC] Connecting to 127.0.0.1:{vncPort}...");
                VNCViewer.Connect("127.0.0.1", vncPort);
                SerialTerminal.Connect("127.0.0.1", serialPort);
            };
            timer.Start();
        }

        private void OnVMStopped(int exitCode)
        {
            StartStopBtn.Content = "▶ Start";
            PauseBtn.IsEnabled = false;
            CaptureBtn.IsEnabled = false;
            PauseBtn.Content = "⏸ Pause";
            _isPaused = false;
            StatusBar.Text = $"Stopped (exit code: {exitCode})";
            AppendLog($"[VMStart] Virtual machine stopped (exit code: {exitCode}).");
            VNCViewer.Disconnect();
            SerialTerminal.Disconnect();
            VMStateChanged?.Invoke();
        }

        // ─── Toolbar Actions ───
        private void ToggleStartStop(object sender, RoutedEventArgs e)
        {
            if (_engine.IsRunning)
                StopVM();
            else
            {
                StartVM();
            }
        }

        private void TogglePause(object sender, RoutedEventArgs e) => TogglePauseVM();

        public void TogglePauseVM()
        {
            if (!_engine.IsRunning) return;
            if (_isPaused)
            {
                _engine.Resume();
                PauseBtn.Content = "⏸ Pause";
                _isPaused = false;
                StatusBar.Text = "Running";
                AppendLog("[VMStart] Resumed.");
            }
            else
            {
                _engine.Pause();
                PauseBtn.Content = "▶ Resume";
                _isPaused = true;
                StatusBar.Text = "Paused";
                AppendLog("[VMStart] Paused.");
            }
        }

        private void ShowMediaMenu(object sender, RoutedEventArgs e)
        {
            var menu = new System.Windows.Controls.ContextMenu();

            var cdromItem = new MenuItem { Header = "💿 Change CD-ROM..." };
            cdromItem.Click += (s, args) =>
            {
                var dlg = new Microsoft.Win32.OpenFileDialog
                {
                    Title = "Select CD-ROM Image",
                    Filter = "ISO Images (*.iso)|*.iso|IMG Files (*.img)|*.img|All Files (*.*)|*.*"
                };
                if (dlg.ShowDialog() == true)
                {
                    _vm.CdromImagePath = dlg.FileName;
                    _engine.SendMonitorCommand($"change {QEMUEngine.CdromDriveId} \"{dlg.FileName}\"");
                    AppendLog($"[Media] CD-ROM changed to: {Path.GetFileName(dlg.FileName)}");
                }
            };

            var floppyItem = new MenuItem { Header = "💾 Change Floppy A..." };
            floppyItem.Click += (s, args) =>
            {
                var dlg = new Microsoft.Win32.OpenFileDialog
                {
                    Title = "Select Floppy Image",
                    Filter = "Floppy Images (*.img, *.ima)|*.img;*.ima|All Files (*.*)|*.*"
                };
                if (dlg.ShowDialog() == true)
                {
                    _vm.FloppyAPath = dlg.FileName;
                    _engine.SendMonitorCommand($"change floppy0 \"{dlg.FileName}\"");
                    AppendLog($"[Media] Floppy A changed to: {Path.GetFileName(dlg.FileName)}");
                }
            };

            var ejectCdrom = new MenuItem { Header = "⏏ Eject CD-ROM" };
            ejectCdrom.Click += (s, args) =>
            {
                _vm.CdromImagePath = "";
                _engine.SendMonitorCommand($"eject {QEMUEngine.CdromDriveId}");
                AppendLog("[Media] CD-ROM ejected.");
            };

            var ejectFloppy = new MenuItem { Header = "⏏ Eject Floppy A" };
            ejectFloppy.Click += (s, args) =>
            {
                _vm.FloppyAPath = "";
                _engine.SendMonitorCommand("eject floppy0");
                AppendLog("[Media] Floppy A ejected.");
            };

            menu.Items.Add(cdromItem);
            menu.Items.Add(ejectCdrom);
            menu.Items.Add(new Separator());
            menu.Items.Add(floppyItem);
            menu.Items.Add(ejectFloppy);

            if (sender is System.Windows.Controls.Button btn)
            {
                menu.PlacementTarget = btn;
                menu.IsOpen = true;
            }
        }

        private void TakeScreenshot(object sender, RoutedEventArgs e)
        {
            if (!_engine.IsRunning) return;
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "VMStart");
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, $"screenshot_{DateTime.Now:yyyyMMdd_HHmmss}.ppm");
            _engine.SendMonitorCommand($"screendump \"{path}\"");
            AppendLog($"[Capture] Screenshot saved to: {path}");
            StatusBar.Text = "Screenshot captured";
        }

        private void ToggleFullscreen(object sender, RoutedEventArgs e)
        {
            if (WindowState == WindowState.Normal)
            {
                WindowStyle = WindowStyle.None;
                WindowState = WindowState.Maximized;
                ResizeMode = ResizeMode.NoResize;
            }
            else
            {
                WindowStyle = WindowStyle.SingleBorderWindow;
                WindowState = WindowState.Normal;
                ResizeMode = ResizeMode.CanResize;
            }
        }

        // ─── Tab Switching ───
        private void SwitchTab(object sender, RoutedEventArgs e)
        {
            if (sender is System.Windows.Controls.Button btn && btn.Tag is string tag)
            {
                _activeTab = int.Parse(tag);
                DisplayPanel.Visibility = _activeTab == 0 ? Visibility.Visible : Visibility.Collapsed;
                LogView.Visibility = _activeTab == 1 ? Visibility.Visible : Visibility.Collapsed;
                SerialTerminal.Visibility = _activeTab == 2 ? Visibility.Visible : Visibility.Collapsed;
                UpdateTabHighlight();
            }
        }

        private void UpdateTabHighlight()
        {
            var active = new SolidColorBrush(Color.FromRgb(37, 99, 235));
            var inactive = Brushes.Transparent;
            TabDisplay.Background = _activeTab == 0 ? active : inactive;
            TabDisplay.Foreground = _activeTab == 0 ? Brushes.White : new SolidColorBrush(Color.FromRgb(170, 170, 170));
            TabLog.Background = _activeTab == 1 ? active : inactive;
            TabLog.Foreground = _activeTab == 1 ? Brushes.White : new SolidColorBrush(Color.FromRgb(170, 170, 170));
            TabSerial.Background = _activeTab == 2 ? active : inactive;
            TabSerial.Foreground = _activeTab == 2 ? Brushes.White : new SolidColorBrush(Color.FromRgb(170, 170, 170));
        }

        // ─── Splash Screen ───
        private void ShowSplash(string subtitle)
        {
            SplashSubtitle.Text = subtitle;
            SplashOverlay.Visibility = Visibility.Visible;
        }

        private void HideSplash()
        {
            SplashOverlay.Visibility = Visibility.Collapsed;
        }

        // ─── Logging ───
        private void AppendLog(string text)
        {
            Dispatcher.InvokeAsync(() =>
            {
                LogView.AppendText(text + Environment.NewLine);
                LogView.ScrollToEnd();
            });
        }
    }
}
