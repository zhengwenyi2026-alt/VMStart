using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;

namespace VMStart.UI.Controls
{
    public partial class SerialTerminalControl : UserControl, IDisposable
    {
        private TcpClient _client;
        private NetworkStream _stream;
        private int _generation;
        private readonly List<string> _lines = new();
        private string _currentLine = "";
        private const int MaxLines = 5000;
        private readonly object _lock = new();

        public bool IsConnected { get; private set; }
        public event Action OnConnected;
        public event Action OnDisconnected;

        public SerialTerminalControl()
        {
            InitializeComponent();
            AppendLine("VMStart Serial Terminal");
            AppendLine("Waiting for connection...");
        }

        // ─── Connection ───

        public void Connect(string host = "127.0.0.1", int port = 4321)
        {
            Disconnect();
            int gen = ++_generation;
            new Thread(() => Run(host, port, gen)) { Name = "SerialClient", IsBackground = true }.Start();
        }

        public void Disconnect()
        {
            _generation++;
            IsConnected = false;
            lock (_lock)
            {
                try { _client?.Close(); } catch { }
                _client = null;
                _stream = null;
            }
        }

        private bool IsCurrent(int gen) => Volatile.Read(ref _generation) == gen;

        private void Post(int gen, Action action)
        {
            try { Dispatcher.InvokeAsync(() => { if (IsCurrent(gen)) action(); }); }
            catch { /* 窗口关闭时调度器可能已停止 */ }
        }

        private void Run(string host, int port, int gen)
        {
            var client = new TcpClient();
            try
            {
                for (int attempt = 0; ; attempt++)
                {
                    try { client.Connect(host, port); break; }
                    catch (SocketException) when (attempt < 20 && IsCurrent(gen)) { Thread.Sleep(250); }
                }
                var stream = client.GetStream();
                lock (_lock)
                {
                    if (!IsCurrent(gen)) return;
                    _client = client;
                    _stream = stream;
                }
                Post(gen, () =>
                {
                    IsConnected = true;
                    AppendLine($"[Connected to serial port {port}]");
                    OnConnected?.Invoke();
                });

                var buf = new byte[4096];
                var decoder = Encoding.UTF8.GetDecoder();
                var chars = new char[Encoding.UTF8.GetMaxCharCount(buf.Length)];
                int n;
                while (IsCurrent(gen) && (n = stream.Read(buf, 0, buf.Length)) > 0)
                {
                    // 解码器跨批次保留半个 UTF-8 字符
                    int c = decoder.GetChars(buf, 0, n, chars, 0);
                    var text = new string(chars, 0, c);
                    Post(gen, () => ProcessANSI(text));
                }
            }
            catch (Exception ex)
            {
                Post(gen, () => AppendLine($"[Error: {ex.Message}]"));
            }
            finally
            {
                try { client.Close(); } catch { }
                Post(gen, () =>
                {
                    IsConnected = false;
                    OnDisconnected?.Invoke();
                });
            }
        }

        // ─── ANSI Processing ───

        private void ProcessANSI(string text)
        {
            // Strip ANSI escape sequences
            var cleaned = Regex.Replace(text, @"\x1b\[[0-9;]*[a-zA-Z]", "");
            cleaned = Regex.Replace(cleaned, @"\x1b\([a-zA-Z]", "");

            foreach (char ch in cleaned)
            {
                if (ch == '\r') continue;
                if (ch == '\n')
                    FlushLine();
                else if (ch == '\b')
                {
                    if (_currentLine.Length > 0) _currentLine = _currentLine[..^1];
                }
                else
                    _currentLine += ch;
            }
            RefreshDisplay();
        }

        private void FlushLine()
        {
            lock (_lock)
            {
                _lines.Add(_currentLine);
                if (_lines.Count > MaxLines) _lines.RemoveRange(0, _lines.Count - MaxLines);
                _currentLine = "";
            }
        }

        private void AppendLine(string text)
        {
            lock (_lock)
            {
                _lines.Add(text);
                if (_lines.Count > MaxLines) _lines.RemoveRange(0, _lines.Count - MaxLines);
            }
            RefreshDisplay();
        }

        private void RefreshDisplay()
        {
            lock (_lock)
            {
                var allLines = new List<string>(_lines);
                if (!string.IsNullOrEmpty(_currentLine)) allLines.Add(_currentLine);
                TerminalOutput.Text = string.Join("\n", allLines);
            }
            TerminalOutput.ScrollToEnd();
        }

        // ─── Input ───

        private void InputBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                SendInput();
                e.Handled = true;
            }
        }

        private void SendInput()
        {
            var text = InputBox.Text;
            InputBox.Text = "";

            if (!IsConnected || _stream == null)
            {
                AppendLine("[Not connected]");
                return;
            }

            var data = Encoding.UTF8.GetBytes(text + "\r");
            try
            {
                lock (_lock) _stream?.Write(data, 0, data.Length);
            }
            catch
            {
                AppendLine("[Send failed]");
            }
        }

        public void SendString(string text)
        {
            if (!IsConnected || _stream == null) return;
            var data = Encoding.UTF8.GetBytes(text);
            try { lock (_lock) _stream?.Write(data, 0, data.Length); } catch { }
        }

        public void ClearScreen()
        {
            lock (_lock)
            {
                _lines.Clear();
                _currentLine = "";
            }
            Dispatcher.Invoke(() => RefreshDisplay());
        }

        public void Dispose()
        {
            Disconnect();
        }
    }
}
