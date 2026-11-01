using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace VMStart.UI.Controls
{
    /// <summary>
    /// RFB 3.8 客户端：连接 QEMU 内置 VNC 服务并用 WriteableBitmap 绘制客户机画面。
    /// </summary>
    public class VNCViewerControl : Control, IDisposable
    {
        private const int EncodingRaw = 0;
        private const int EncodingDesktopSize = -223;

        private WriteableBitmap _bitmap;
        private readonly Image _image;
        private readonly UIElement _visualChild;
        private TcpClient _client;
        private NetworkStream _stream;
        private readonly object _writeLock = new();
        // 每次连接自增；旧连接线程据此判断自己已过期，不再改动当前状态
        private int _generation;
        private int _fbWidth, _fbHeight;

        public bool IsConnected { get; private set; }
        public int FramebufferWidth => _fbWidth;
        public int FramebufferHeight => _fbHeight;
        public event Action OnConnected;
        public event Action OnDisconnected;

        public VNCViewerControl()
        {
            Background = Brushes.Black;
            Focusable = true;
            _image = new Image { Stretch = Stretch.Uniform };
            RenderOptions.SetBitmapScalingMode(_image, BitmapScalingMode.HighQuality);
            var grid = new Grid { Background = Brushes.Black };
            grid.Children.Add(_image);
            _visualChild = grid;
            AddVisualChild(grid);
            AddLogicalChild(grid);
        }

        protected override int VisualChildrenCount => 1;
        protected override Visual GetVisualChild(int index) => _visualChild;

        // ─── 连接 ───

        public void Connect(string host = "127.0.0.1", int port = 5900)
        {
            Disconnect();
            int gen = ++_generation;
            new Thread(() => Run(host, port, gen)) { Name = "VNCClient", IsBackground = true }.Start();
        }

        public void Disconnect()
        {
            _generation++;
            bool was = IsConnected;
            IsConnected = false;
            lock (_writeLock)
            {
                try { _client?.Close(); } catch { }
                _client = null;
                _stream = null;
            }
            if (was) OnDisconnected?.Invoke();
        }

        private bool IsCurrent(int gen) => Volatile.Read(ref _generation) == gen;

        private void Post(int gen, Action action)
        {
            try
            {
                Dispatcher.InvokeAsync(() => { if (IsCurrent(gen)) action(); }, DispatcherPriority.Render);
            }
            catch { /* 窗口关闭时调度器可能已停止 */ }
        }

        private void Run(string host, int port, int gen)
        {
            var client = new TcpClient { NoDelay = true };
            try
            {
                // QEMU 刚启动时端口可能尚未监听，短暂重试
                for (int attempt = 0; ; attempt++)
                {
                    try { client.Connect(host, port); break; }
                    catch (SocketException) when (attempt < 20 && IsCurrent(gen)) { Thread.Sleep(250); }
                }
                var stream = client.GetStream();
                lock (_writeLock)
                {
                    if (!IsCurrent(gen)) return;
                    _client = client;
                    _stream = stream;
                }

                Handshake(stream);
                ServerInit(stream, gen);
                SendSetPixelFormat();
                SendSetEncodings();

                Post(gen, () =>
                {
                    IsConnected = true;
                    OnConnected?.Invoke();
                });
                FramebufferUpdateRequest(false);
                EventLoop(stream, gen);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"VNC error: {ex.Message}");
            }
            finally
            {
                try { client.Close(); } catch { }
                Post(gen, () =>
                {
                    bool was = IsConnected;
                    IsConnected = false;
                    if (was) OnDisconnected?.Invoke();
                });
            }
        }

        // ─── 握手 ───

        private static void Handshake(NetworkStream s)
        {
            var ver = Encoding.ASCII.GetString(ReadBytes(s, 12));
            if (!ver.StartsWith("RFB "))
                throw new IOException("Invalid RFB protocol");
            s.Write(Encoding.ASCII.GetBytes("RFB 003.008\n"));

            int numTypes = ReadU8(s);
            if (numTypes == 0)
            {
                var reason = ReadBytes(s, (int)ReadU32(s));
                throw new IOException("VNC refused: " + Encoding.UTF8.GetString(reason));
            }
            var types = ReadBytes(s, numTypes);
            if (Array.IndexOf(types, (byte)1) < 0)
                throw new IOException("VNC server requires authentication");
            s.WriteByte(1); // None

            if (ReadU32(s) != 0) throw new IOException("VNC security handshake failed");
            s.WriteByte(1); // ClientInit：共享会话
        }

        private void ServerInit(NetworkStream s, int gen)
        {
            int w = ReadU16(s), h = ReadU16(s);
            ReadBytes(s, 16); // 服务端像素格式，随后改用自己的格式
            uint nameLen = ReadU32(s);
            if (nameLen > 0) ReadBytes(s, (int)nameLen);
            Resize(w, h, gen);
        }

        private void Resize(int w, int h, int gen)
        {
            _fbWidth = w;
            _fbHeight = h;
            Post(gen, () =>
            {
                _bitmap = new WriteableBitmap(Math.Max(w, 1), Math.Max(h, 1), 96, 96, PixelFormats.Bgr32, null);
                _image.Source = _bitmap;
            });
        }

        // 32 位小端 true-color（B,G,R,X），可直接写入 Bgr32 位图
        private void SendSetPixelFormat()
        {
            Send(new byte[]
            {
                0, 0, 0, 0,
                32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0
            });
        }

        private void SendSetEncodings()
        {
            int[] encodings = { EncodingRaw, EncodingDesktopSize };
            var m = new byte[4 + encodings.Length * 4];
            m[0] = 2;
            m[3] = (byte)encodings.Length;
            for (int i = 0; i < encodings.Length; i++)
            {
                uint e = unchecked((uint)encodings[i]);
                m[4 + i * 4] = (byte)(e >> 24);
                m[5 + i * 4] = (byte)(e >> 16);
                m[6 + i * 4] = (byte)(e >> 8);
                m[7 + i * 4] = (byte)e;
            }
            Send(m);
        }

        // ─── 消息循环 ───

        private void EventLoop(NetworkStream s, int gen)
        {
            while (IsCurrent(gen))
            {
                byte msgType = ReadU8(s);
                switch (msgType)
                {
                    case 0:
                        HandleFBUpdate(s, gen);
                        FramebufferUpdateRequest(true);
                        break;
                    case 2:
                        Post(gen, () => System.Media.SystemSounds.Beep.Play());
                        break;
                    case 3:
                        HandleServerCutText(s, gen);
                        break;
                    default:
                        throw new IOException($"Unsupported RFB message {msgType}");
                }
            }
        }

        private void FramebufferUpdateRequest(bool incremental)
        {
            Send(new byte[]
            {
                3, (byte)(incremental ? 1 : 0), 0, 0, 0, 0,
                (byte)(_fbWidth >> 8), (byte)_fbWidth,
                (byte)(_fbHeight >> 8), (byte)_fbHeight
            });
        }

        private void HandleFBUpdate(NetworkStream s, int gen)
        {
            ReadU8(s);
            int numRects = ReadU16(s);
            for (int i = 0; i < numRects; i++)
            {
                int x = ReadU16(s), y = ReadU16(s), w = ReadU16(s), h = ReadU16(s);
                int enc = unchecked((int)ReadU32(s));
                switch (enc)
                {
                    case EncodingRaw:
                        var pixels = ReadBytes(s, w * h * 4);
                        Post(gen, () =>
                        {
                            if (_bitmap == null || w == 0 || h == 0
                                || x + w > _bitmap.PixelWidth || y + h > _bitmap.PixelHeight) return;
                            _bitmap.WritePixels(new Int32Rect(x, y, w, h), pixels, w * 4, 0);
                        });
                        break;
                    case EncodingDesktopSize:
                        Resize(w, h, gen);
                        break;
                    default:
                        // 未声明的编码长度未知，无法跳过
                        throw new IOException($"Unexpected VNC encoding {enc}");
                }
            }
        }

        private void HandleServerCutText(NetworkStream s, int gen)
        {
            ReadBytes(s, 3);
            var text = Encoding.Latin1.GetString(ReadBytes(s, (int)ReadU32(s)));
            Post(gen, () =>
            {
                try { Clipboard.SetText(text); } catch { }
            });
        }

        // ─── 键盘 ───

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (!IsConnected) { base.OnKeyDown(e); return; }
            uint ks = Keysym(e.Key == Key.System ? e.SystemKey : e.Key);
            if (ks != 0) SendKeyEvent(ks, true);
            e.Handled = true;
        }

        protected override void OnKeyUp(KeyEventArgs e)
        {
            if (!IsConnected) { base.OnKeyUp(e); return; }
            uint ks = Keysym(e.Key == Key.System ? e.SystemKey : e.Key);
            if (ks != 0) SendKeyEvent(ks, false);
            e.Handled = true;
        }

        private void SendKeyEvent(uint keysym, bool down)
        {
            Send(new byte[]
            {
                4, (byte)(down ? 1 : 0), 0, 0,
                (byte)(keysym >> 24), (byte)(keysym >> 16), (byte)(keysym >> 8), (byte)keysym
            });
        }

        // 发送未按 Shift 的 keysym，Shift 状态单独发送，由客户机组合出大写与符号
        private static uint Keysym(Key key)
        {
            if (key >= Key.A && key <= Key.Z) return (uint)('a' + (key - Key.A));
            if (key >= Key.D0 && key <= Key.D9) return (uint)('0' + (key - Key.D0));
            if (key >= Key.NumPad0 && key <= Key.NumPad9) return 0xFFB0u + (uint)(key - Key.NumPad0);
            if (key >= Key.F1 && key <= Key.F12) return 0xFFBEu + (uint)(key - Key.F1);
            return key switch
            {
                Key.Space => 0x20,
                Key.Return => 0xFF0D, Key.Tab => 0xFF09, Key.Back => 0xFF08,
                Key.Escape => 0xFF1B, Key.Delete => 0xFFFF, Key.Insert => 0xFF63,
                Key.Home => 0xFF50, Key.End => 0xFF57, Key.PageUp => 0xFF55, Key.PageDown => 0xFF56,
                Key.Left => 0xFF51, Key.Up => 0xFF52, Key.Right => 0xFF53, Key.Down => 0xFF54,
                Key.LeftShift => 0xFFE1, Key.RightShift => 0xFFE2,
                Key.LeftCtrl => 0xFFE3, Key.RightCtrl => 0xFFE4,
                Key.LeftAlt => 0xFFE9, Key.RightAlt => 0xFFEA,
                Key.LWin => 0xFFEB, Key.RWin => 0xFFEC, Key.Apps => 0xFF67,
                Key.CapsLock => 0xFFE5, Key.NumLock => 0xFF7F, Key.Scroll => 0xFF14,
                Key.Pause => 0xFF13, Key.PrintScreen => 0xFF61,
                Key.Multiply => 0xFFAA, Key.Add => 0xFFAB, Key.Subtract => 0xFFAD,
                Key.Decimal => 0xFFAE, Key.Divide => 0xFFAF,
                Key.OemMinus => '-', Key.OemPlus => '=', Key.OemComma => ',', Key.OemPeriod => '.',
                Key.OemQuestion => '/', Key.OemSemicolon => ';', Key.OemQuotes => '\'',
                Key.OemOpenBrackets => '[', Key.OemCloseBrackets => ']', Key.OemPipe => '\\',
                Key.OemTilde => '`', Key.OemBackslash => '\\',
                _ => 0
            };
        }

        // ─── 鼠标（客户机需有 usb-tablet 才能绝对定位）───

        protected override void OnMouseDown(MouseButtonEventArgs e)
        {
            Focus();
            SendPointer(e, 0);
        }

        protected override void OnMouseUp(MouseButtonEventArgs e) => SendPointer(e, 0);

        protected override void OnMouseMove(MouseEventArgs e) => SendPointer(e, 0);

        protected override void OnMouseWheel(MouseWheelEventArgs e)
        {
            byte wheel = (byte)(e.Delta > 0 ? 8 : 16);
            SendPointer(e, wheel);
            SendPointer(e, 0);
        }

        private void SendPointer(MouseEventArgs e, byte extra)
        {
            if (!IsConnected || _fbWidth == 0 || _fbHeight == 0) return;
            byte mask = extra;
            if (e.LeftButton == MouseButtonState.Pressed) mask |= 1;
            if (e.MiddleButton == MouseButtonState.Pressed) mask |= 2;
            if (e.RightButton == MouseButtonState.Pressed) mask |= 4;
            var pos = e.GetPosition(_image);
            int vx = Math.Clamp((int)(pos.X * _fbWidth / Math.Max(_image.ActualWidth, 1)), 0, _fbWidth - 1);
            int vy = Math.Clamp((int)(pos.Y * _fbHeight / Math.Max(_image.ActualHeight, 1)), 0, _fbHeight - 1);
            Send(new byte[] { 5, mask, (byte)(vx >> 8), (byte)vx, (byte)(vy >> 8), (byte)vy });
        }

        // ─── 读写 ───

        private static byte[] ReadBytes(NetworkStream s, int n)
        {
            var buf = new byte[n];
            int got = 0;
            while (got < n)
            {
                int r = s.Read(buf, got, n - got);
                if (r <= 0) throw new IOException("VNC connection closed");
                got += r;
            }
            return buf;
        }

        private static byte ReadU8(NetworkStream s) => ReadBytes(s, 1)[0];

        private static int ReadU16(NetworkStream s)
        {
            var b = ReadBytes(s, 2);
            return (b[0] << 8) | b[1];
        }

        private static uint ReadU32(NetworkStream s)
        {
            var b = ReadBytes(s, 4);
            return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | b[3];
        }

        private void Send(byte[] data)
        {
            lock (_writeLock)
            {
                try { _stream?.Write(data, 0, data.Length); }
                catch { /* 连接断开由读线程处理 */ }
            }
        }

        public void Dispose()
        {
            Disconnect();
            _bitmap = null;
        }
    }
}
