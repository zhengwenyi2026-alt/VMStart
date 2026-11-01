using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using VMStart.Engine;
using VMStart.Models;

namespace VMStart.UI
{
    public partial class MainWindow : Window
    {
        private const string BundleExtension = ".vmstart";
        private List<VirtualMachine> _vms = new();
        private readonly Dictionary<string, ConsoleWindow> _consoles = new();
        private readonly string _vmDirectory;
        private AppMode _currentMode = AppMode.Standard;

        public MainWindow()
        {
            InitializeComponent();
            _vmDirectory = VirtualMachine.DefaultBundleDirectory();
            RefreshVMList();
            UpdateStatusBar();
            UpdateModeButtons();
        }

        private void RefreshVMList()
        {
            var selectedId = (VMList.SelectedItem as VirtualMachine)?.Id;
            _vms = Directory.GetDirectories(_vmDirectory)
                .Select(VirtualMachine.Load)
                .Where(vm => vm != null)
                // 正在运行的虚拟机沿用控制台持有的对象，保证状态一致
                .Select(vm => _consoles.TryGetValue(vm.Id, out var c) ? c.VM : vm)
                .ToList();
            ApplyFilter();
            VMList.SelectedItem = _vms.FirstOrDefault(v => v.Id == selectedId);
            UpdateContentVisibility();
            UpdateStatusBar();
        }

        private void ApplyFilter()
        {
            var query = SearchBox.Text.Trim().ToLowerInvariant();
            VMList.ItemsSource = _vms
                .Where(v => query.Length == 0 || v.Name.ToLowerInvariant().Contains(query)
                            || v.ArchitectureDisplayName.ToLowerInvariant().Contains(query))
                .OrderBy(v => v.Name)
                .ToList();
        }

        private void UpdateStatusBar()
        {
            var running = _vms.Count(v => v.Status == VMStatus.Running || v.Status == VMStatus.Paused);
            StatusBar.Text = $"{_vms.Count} VMs ({running} running) • QEMU Engine";
        }

        private void UpdateContentVisibility()
        {
            if (VMList.SelectedItem is VirtualMachine selected)
            {
                WelcomePanel.Visibility = Visibility.Collapsed;
                DetailsPanel.Visibility = Visibility.Visible;
                UpdateDetails(selected);
            }
            else
            {
                WelcomePanel.Visibility = Visibility.Visible;
                DetailsPanel.Visibility = Visibility.Collapsed;
            }
        }

        private void UpdateDetails(VirtualMachine vm)
        {
            DetailName.Text = vm.Name;
            DetailArch.Text = vm.ArchitectureDisplayName;
            DetailStatus.Text = vm.StatusDisplayName;
            DetailStatusBadge.Background = vm.StatusColor;

            DetailCPU.Text = $"{vm.CpuModel} ({vm.CpuCores} cores)";
            DetailMemory.Text = $"{vm.MemoryValue} {vm.MemoryUnit}";
            DetailDisk.Text = string.IsNullOrEmpty(vm.DiskImagePath) || !File.Exists(vm.DiskImagePath)
                ? "No disk" : $"{vm.DiskSizeValue} {vm.DiskSizeUnit}";
            DetailNetwork.Text = vm.NetworkMode;
            DetailDisplay.Text = "VNC (embedded)";
            DetailStatusInfo.Text = vm.StatusDisplayName;
            DetailNotes.Text = string.IsNullOrEmpty(vm.Notes) ? "No notes" : vm.Notes;

            NotesCard.Visibility = _currentMode == AppMode.Simple ? Visibility.Collapsed : Visibility.Visible;
            StartBtn.Content = IsRunning(vm) ? "⏹ Stop" : "▶ Start";
        }

        private bool IsRunning(VirtualMachine vm) =>
            _consoles.TryGetValue(vm.Id, out var c) && c.IsVMRunning;

        // ─── 模式切换 ───
        private void ModeSwitch_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tag)
            {
                _currentMode = (AppMode)int.Parse(tag);
                UpdateModeButtons();
                if (VMList.SelectedItem is VirtualMachine vm) UpdateDetails(vm);
            }
        }

        private void UpdateModeButtons()
        {
            var primary = (SolidColorBrush)FindResource("PrimaryBrush");
            SimpleBtn.Background = _currentMode == AppMode.Simple ? primary : Brushes.Transparent;
            SimpleBtn.Foreground = _currentMode == AppMode.Simple ? Brushes.White : Brushes.Black;
            StandardBtn.Background = _currentMode == AppMode.Standard ? primary : Brushes.Transparent;
            StandardBtn.Foreground = _currentMode == AppMode.Standard ? Brushes.White : Brushes.Black;
            AdvancedBtn.Background = _currentMode == AppMode.Advanced ? primary : Brushes.Transparent;
            AdvancedBtn.Foreground = _currentMode == AppMode.Advanced ? Brushes.White : Brushes.Black;
        }

        private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (IsLoaded) ApplyFilter();
        }

        // ─── 控制台 ───

        private ConsoleWindow GetConsole(VirtualMachine vm)
        {
            if (_consoles.TryGetValue(vm.Id, out var existing)) return existing;
            var console = new ConsoleWindow(vm);
            console.VMStateChanged += () =>
            {
                if (VMList.SelectedItem is VirtualMachine sel) UpdateDetails(sel);
                UpdateStatusBar();
            };
            console.Closed += (_, _) =>
            {
                _consoles.Remove(vm.Id);
                vm.Status = VMStatus.Stopped;
                if (VMList.SelectedItem is VirtualMachine sel) UpdateDetails(sel);
                UpdateStatusBar();
            };
            _consoles[vm.Id] = console;
            console.Show();
            return console;
        }

        private void StartOrStop(VirtualMachine vm)
        {
            if (IsRunning(vm))
            {
                _consoles[vm.Id].StopVM();
                return;
            }
            var console = GetConsole(vm);
            console.Activate();
            console.StartVM();
        }

        // ─── 操作 ───
        private void AddVM_Click(object sender, RoutedEventArgs e)
        {
            var vm = new VirtualMachine { Name = "New Virtual Machine" };
            vm.BundlePath = Path.Combine(_vmDirectory, vm.Id + BundleExtension);
            var wizard = new ConfigWizardWindow(vm, isNew: true) { Owner = this };
            if (wizard.ShowDialog() != true) return;

            vm.SaveToBundle();
            if (vm.DiskSizeUnit != "none" && vm.DiskSizeValue > 0)
            {
                try
                {
                    var disk = Path.Combine(vm.BundlePath, "disk.qcow2");
                    QEMUEngine.CreateDiskImage(disk, vm.DiskSizeValue, vm.DiskSizeUnit);
                    vm.DiskImagePath = disk;
                    vm.SaveToBundle();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, $"The VM was created without a disk.\n\n{ex.Message}", "Disk Not Created",
                        MessageBoxButton.OK, MessageBoxImage.Warning);
                }
            }
            RefreshVMList();
            VMList.SelectedItem = _vms.FirstOrDefault(v => v.Id == vm.Id);
        }

        private void OpenVM_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new Microsoft.Win32.OpenFolderDialog { Title = "Select a VMStart virtual machine folder" };
            if (dlg.ShowDialog(this) == true) ImportBundle(dlg.FolderName);
        }

        private void ImportBundle(string path)
        {
            var vm = VirtualMachine.Load(path);
            if (vm == null)
            {
                MessageBox.Show(this, "This folder does not contain a VMStart config.json.", "Open VM",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            if (_vms.Any(v => v.Id == vm.Id))
            {
                MessageBox.Show(this, $"\"{vm.Name}\" is already in the library.", "Open VM");
                return;
            }
            var dest = Path.Combine(_vmDirectory, vm.Id + BundleExtension);
            if (!string.Equals(Path.GetFullPath(path).TrimEnd('\\'), Path.GetFullPath(dest), StringComparison.OrdinalIgnoreCase))
            {
                CopyDirectory(path, dest);
                // 原包内的磁盘随包复制，路径改指向新位置
                var imported = VirtualMachine.Load(dest);
                if (imported != null && IsInside(imported.DiskImagePath, path))
                {
                    imported.DiskImagePath = Path.Combine(dest, Path.GetRelativePath(path, imported.DiskImagePath));
                    imported.SaveToBundle();
                }
            }
            RefreshVMList();
        }

        private static bool IsInside(string file, string dir) =>
            !string.IsNullOrEmpty(file) && Path.GetFullPath(file)
                .StartsWith(Path.GetFullPath(dir).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);

        private static void CopyDirectory(string src, string dst)
        {
            Directory.CreateDirectory(dst);
            foreach (var file in Directory.GetFiles(src))
                File.Copy(file, Path.Combine(dst, Path.GetFileName(file)));
            foreach (var dir in Directory.GetDirectories(src))
                CopyDirectory(dir, Path.Combine(dst, Path.GetFileName(dir)));
        }

        private void RemoveVM_Click(object sender, RoutedEventArgs e)
        {
            if (VMList.SelectedItem is not VirtualMachine vm) return;
            if (_consoles.ContainsKey(vm.Id))
            {
                MessageBox.Show(this, "Close the VM's console window before deleting it.", "Delete Virtual Machine");
                return;
            }
            var result = MessageBox.Show(this,
                "This action cannot be undone. The virtual machine and its data will be permanently removed.",
                "Delete Virtual Machine?", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
            if (result != MessageBoxResult.OK) return;
            try { Directory.Delete(vm.BundlePath, true); }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Delete Failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            RefreshVMList();
        }

        private void EditVM_Click(object sender, RoutedEventArgs e)
        {
            if (VMList.SelectedItem is not VirtualMachine vm) return;
            var wizard = new ConfigWizardWindow(vm, isNew: false) { Owner = this };
            if (wizard.ShowDialog() == true)
            {
                vm.SaveToBundle();
                ApplyFilter();
                VMList.SelectedItem = vm;
                UpdateContentVisibility();
            }
        }

        private void StartVM_Click(object sender, RoutedEventArgs e)
        {
            if (VMList.SelectedItem is VirtualMachine vm) StartOrStop(vm);
        }

        private void VMList_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateContentVisibility();

        // ─── 右键菜单 ───

        private VirtualMachine GetContextVM() => VMList.SelectedItem as VirtualMachine;

        private void CtxStart_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is VirtualMachine vm && !IsRunning(vm)) StartOrStop(vm);
        }

        private void CtxStop_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is VirtualMachine vm && IsRunning(vm)) _consoles[vm.Id].StopVM();
        }

        private void CtxPause_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is VirtualMachine vm && IsRunning(vm)) _consoles[vm.Id].TogglePauseVM();
        }

        private void CtxConsole_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm) return;
            var console = GetConsole(vm);
            console.Activate();
            if (!console.IsVMRunning) console.StartVM();
        }

        private void CtxFavorite_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is VirtualMachine vm)
            {
                vm.IsFavorite = !vm.IsFavorite;
                vm.SaveToBundle();
                RefreshVMList();
            }
        }

        private void CtxSetGroup_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is VirtualMachine vm && Prompt("Set Group", "Group name:", vm.Group ?? "") is string group)
            {
                vm.Group = group;
                vm.SaveToBundle();
                RefreshVMList();
            }
        }

        // ─── 快照（qcow2 内部快照）───

        private string Prompt(string title, string label, string initial)
        {
            var dialog = new Window
            {
                Title = title, Width = 320, Height = 150, ResizeMode = ResizeMode.NoResize,
                WindowStartupLocation = WindowStartupLocation.CenterOwner, Owner = this
            };
            var panel = new StackPanel { Margin = new Thickness(16) };
            var tb = new TextBox { Text = initial, Margin = new Thickness(0, 8, 0, 8) };
            var okBtn = new Button { Content = "OK", Width = 80, HorizontalAlignment = HorizontalAlignment.Right, IsDefault = true };
            okBtn.Click += (_, _) => dialog.DialogResult = true;
            panel.Children.Add(new TextBlock { Text = label });
            panel.Children.Add(tb);
            panel.Children.Add(okBtn);
            dialog.Content = panel;
            tb.SelectAll();
            tb.Focus();
            return dialog.ShowDialog() == true ? tb.Text.Trim() : null;
        }

        private SnapshotInfo PickSnapshot(VirtualMachine vm, string title)
        {
            if (vm.Snapshots.Count == 0)
            {
                MessageBox.Show(this, "This VM has no snapshots.", title);
                return null;
            }
            var dialog = new Window
            {
                Title = title, Width = 340, Height = 300, ResizeMode = ResizeMode.NoResize,
                WindowStartupLocation = WindowStartupLocation.CenterOwner, Owner = this
            };
            var panel = new DockPanel { Margin = new Thickness(12) };
            var okBtn = new Button { Content = "OK", Width = 80, HorizontalAlignment = HorizontalAlignment.Right, IsDefault = true, Margin = new Thickness(0, 8, 0, 0) };
            DockPanel.SetDock(okBtn, Dock.Bottom);
            var list = new ListBox { ItemsSource = vm.Snapshots.Select(s => $"{s.Name}  ({s.Date})").ToList(), SelectedIndex = vm.Snapshots.Count - 1 };
            okBtn.Click += (_, _) => dialog.DialogResult = list.SelectedIndex >= 0;
            panel.Children.Add(okBtn);
            panel.Children.Add(list);
            dialog.Content = panel;
            return dialog.ShowDialog() == true ? vm.Snapshots[list.SelectedIndex] : null;
        }

        private bool HasQcow2Disk(VirtualMachine vm, string title)
        {
            if (!string.IsNullOrEmpty(vm.DiskImagePath) && File.Exists(vm.DiskImagePath)
                && QEMUEngine.DiskFormat(vm.DiskImagePath) == "qcow2")
                return true;
            MessageBox.Show(this, "Snapshots require a qcow2 disk image.", title);
            return false;
        }

        private void CtxTakeSnapshot_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm || !HasQcow2Disk(vm, "Take Snapshot")) return;
            var input = Prompt("Take Snapshot", "Snapshot name:", $"snapshot-{vm.Snapshots.Count + 1}");
            if (string.IsNullOrEmpty(input)) return;
            // 监视器命令按空白分词，名称只保留安全字符
            var name = Regex.Replace(input, @"[^A-Za-z0-9._-]", "-");
            try
            {
                if (IsRunning(vm)) _consoles[vm.Id].SendMonitorCommand($"savevm {name}");
                else QEMUEngine.RunQemuImg("snapshot", "-c", name, vm.DiskImagePath);
                vm.Snapshots.RemoveAll(s => s.Name == name);
                vm.Snapshots.Add(new SnapshotInfo { Name = name, Date = DateTime.Now.ToString("yyyy-MM-dd HH:mm"), Type = "manual" });
                vm.SaveToBundle();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Snapshot Failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CtxRestoreSnapshot_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm || !HasQcow2Disk(vm, "Restore Snapshot")) return;
            if (PickSnapshot(vm, "Restore Snapshot") is not SnapshotInfo snap) return;
            try
            {
                if (IsRunning(vm)) _consoles[vm.Id].SendMonitorCommand($"loadvm {snap.Name}");
                else QEMUEngine.RunQemuImg("snapshot", "-a", snap.Name, vm.DiskImagePath);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Restore Failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CtxDeleteSnapshot_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm || !HasQcow2Disk(vm, "Delete Snapshot")) return;
            if (PickSnapshot(vm, "Delete Snapshot") is not SnapshotInfo snap) return;
            try
            {
                if (IsRunning(vm)) _consoles[vm.Id].SendMonitorCommand($"delvm {snap.Name}");
                else QEMUEngine.RunQemuImg("snapshot", "-d", snap.Name, vm.DiskImagePath);
                vm.Snapshots.Remove(snap);
                vm.SaveToBundle();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "Delete Failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        // ─── 克隆 ───

        private VirtualMachine CopyConfig(VirtualMachine vm, string suffix)
        {
            var clone = JsonSerializer.Deserialize<VirtualMachine>(JsonSerializer.Serialize(vm));
            clone.Id = Guid.NewGuid().ToString("N").Substring(0, 12);
            clone.Name = $"{vm.Name} ({suffix})";
            clone.CreatedAt = DateTime.Now;
            clone.BundlePath = Path.Combine(_vmDirectory, clone.Id + BundleExtension);
            Directory.CreateDirectory(clone.BundlePath);
            return clone;
        }

        private async void CtxFullClone_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm) return;
            if (IsRunning(vm))
            {
                MessageBox.Show(this, "Stop the VM before cloning it.", "Full Clone");
                return;
            }
            var clone = CopyConfig(vm, "Clone");
            try
            {
                if (!string.IsNullOrEmpty(vm.DiskImagePath) && File.Exists(vm.DiskImagePath))
                {
                    var dst = Path.Combine(clone.BundlePath, Path.GetFileName(vm.DiskImagePath));
                    StatusBar.Text = "Copying disk...";
                    await Task.Run(() => File.Copy(vm.DiskImagePath, dst));
                    clone.DiskImagePath = dst;
                }
                clone.SaveToBundle();
                RefreshVMList();
                MessageBox.Show(this, $"Full clone created: {clone.Name}", "Clone Complete");
            }
            catch (Exception ex)
            {
                try { Directory.Delete(clone.BundlePath, true); } catch { }
                RefreshVMList();
                MessageBox.Show(this, ex.Message, "Clone Failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CtxLinkedClone_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm) return;
            if (string.IsNullOrEmpty(vm.DiskImagePath) || !File.Exists(vm.DiskImagePath))
            {
                MessageBox.Show(this, "A linked clone needs the source VM to have a disk.", "Linked Clone");
                return;
            }
            if (IsRunning(vm))
            {
                MessageBox.Show(this, "Stop the VM before cloning it.", "Linked Clone");
                return;
            }
            var clone = CopyConfig(vm, "Linked");
            try
            {
                // 新建以源盘为底的增量盘，克隆体写入不会影响源虚拟机
                var dst = Path.Combine(clone.BundlePath, "disk.qcow2");
                QEMUEngine.RunQemuImg("create", "-f", "qcow2", "-b", vm.DiskImagePath,
                    "-F", QEMUEngine.DiskFormat(vm.DiskImagePath), dst);
                clone.DiskImagePath = dst;
                clone.Snapshots = new();
                clone.SaveToBundle();
                RefreshVMList();
                MessageBox.Show(this,
                    $"Linked clone created: {clone.Name}\n\nIt depends on the source disk — booting the source VM afterwards may invalidate the clone.",
                    "Clone Complete");
            }
            catch (Exception ex)
            {
                try { Directory.Delete(clone.BundlePath, true); } catch { }
                RefreshVMList();
                MessageBox.Show(this, ex.Message, "Clone Failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CtxExportOVF_Click(object sender, RoutedEventArgs e)
        {
            if (GetContextVM() is not VirtualMachine vm) return;
            var dialog = new Microsoft.Win32.SaveFileDialog
            {
                Filter = "OVF Files|*.ovf",
                FileName = $"{vm.Name}.ovf",
                Title = "Export OVF"
            };
            if (dialog.ShowDialog() != true) return;

            string X(string s) => SecurityElement.Escape(s ?? "");
            int memMB = (vm.MemoryUnit ?? "MB").ToUpperInvariant().StartsWith("G") ? vm.MemoryValue * 1024 : vm.MemoryValue;
            var ovf = new StringBuilder();
            ovf.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
            ovf.AppendLine("<Envelope xmlns=\"http://schemas.dmtf.org/ovf/envelope/1\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\"");
            ovf.AppendLine("          xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\">");
            ovf.AppendLine($"  <VirtualSystem ovf:id=\"{X(vm.Name)}\">");
            ovf.AppendLine($"    <Name>{X(vm.Name)}</Name>");
            ovf.AppendLine($"    <OperatingSystemSection><Info>{X(vm.ArchitectureDisplayName)}</Info></OperatingSystemSection>");
            ovf.AppendLine("    <VirtualHardwareSection>");
            ovf.AppendLine($"      <Item><rasd:ElementName>CPU</rasd:ElementName><rasd:ResourceType>3</rasd:ResourceType><rasd:VirtualQuantity>{vm.CpuCores}</rasd:VirtualQuantity></Item>");
            ovf.AppendLine($"      <Item><rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits><rasd:ElementName>Memory</rasd:ElementName><rasd:ResourceType>4</rasd:ResourceType><rasd:VirtualQuantity>{memMB}</rasd:VirtualQuantity></Item>");
            ovf.AppendLine("    </VirtualHardwareSection>");
            ovf.AppendLine("  </VirtualSystem>");
            ovf.AppendLine("</Envelope>");
            File.WriteAllText(dialog.FileName, ovf.ToString());
            MessageBox.Show(this, $"OVF exported to {dialog.FileName}", "Export Complete");
        }

        // ─── 拖放 ───

        private void VMList_DragOver(object sender, DragEventArgs e)
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            e.Handled = true;
        }

        private void VMList_Drop(object sender, DragEventArgs e)
        {
            if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;
            foreach (var file in (string[])e.Data.GetData(DataFormats.FileDrop))
            {
                var ext = Path.GetExtension(file)?.ToLowerInvariant();
                if (Directory.Exists(file))
                {
                    ImportBundle(file);
                    continue;
                }
                var vm = new VirtualMachine { Name = Path.GetFileNameWithoutExtension(file) };
                if (ext is ".qcow2" or ".vmdk" or ".vdi" or ".vhd" or ".vhdx")
                    vm.DiskImagePath = file;
                else if (ext is ".iso" or ".img")
                    vm.BootISOPath = file;
                else
                    continue;
                vm.BundlePath = Path.Combine(_vmDirectory, vm.Id + BundleExtension);
                vm.SaveToBundle();
            }
            RefreshVMList();
        }
    }
}
