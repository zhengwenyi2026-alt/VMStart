using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using VMStart.Models;

namespace VMStart.Engine
{
    /// <summary>
    /// QEMU 进程管理，对应 macOS 端 VMStartQEMUProcess。
    /// </summary>
    public class QEMUEngine : IDisposable
    {
        private readonly VirtualMachine _vm;
        private Process _process;
        private readonly StringBuilder _logOutput = new();

        public event Action<string> OnOutput;
        public event Action<string> OnError;
        public event Action OnStarted;
        public event Action<int> OnStopped;

        public bool IsRunning { get; private set; }
        public int ProcessId => _process?.Id ?? -1;
        public string LogOutput => _logOutput.ToString();

        public const string CdromDriveId = "cd0";

        // 仅本次启动生效的参数（如控制台分配的串口），不写入虚拟机配置
        public List<string> RuntimeArgs { get; } = new();

        public QEMUEngine(VirtualMachine vm)
        {
            _vm = vm ?? throw new ArgumentNullException(nameof(vm));
        }

        // ─── 生命周期 ───

        public void Start()
        {
            if (IsRunning)
                throw new InvalidOperationException("VM is already running");

            var binaryPath = FindQEMUBinary(_vm.Architecture);
            if (binaryPath == null)
                throw new FileNotFoundException(
                    $"QEMU not found for {_vm.ArchitectureDisplayName}. Install QEMU for Windows (https://qemu.weilnetz.de) to C:\\Program Files\\qemu or add it to PATH.");

            var startInfo = new ProcessStartInfo
            {
                FileName = binaryPath,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(binaryPath)
            };
            foreach (var arg in BuildArguments(binaryPath)) startInfo.ArgumentList.Add(arg);

            _process?.Dispose();
            var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };

            process.OutputDataReceived += (s, e) =>
            {
                if (e.Data == null) return;
                lock (_logOutput) _logOutput.AppendLine(e.Data);
                OnOutput?.Invoke(e.Data);
            };
            process.ErrorDataReceived += (s, e) =>
            {
                if (e.Data == null) return;
                lock (_logOutput) _logOutput.AppendLine(e.Data);
                OnError?.Invoke(e.Data);
            };
            process.Exited += (s, e) =>
            {
                // 只处理当前进程的退出，避免旧进程的迟到事件覆盖新一次启动的状态
                if (!ReferenceEquals(_process, process)) return;
                IsRunning = false;
                _vm.Status = VMStatus.Stopped;
                OnStopped?.Invoke(process.ExitCode);
            };

            try
            {
                _process = process;
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                IsRunning = true;
                _vm.Status = VMStatus.Running;
                _vm.LastUsedAt = DateTime.Now;
                _vm.SaveToBundle();
                OnStarted?.Invoke();
            }
            catch (Exception ex)
            {
                _vm.Status = VMStatus.Error;
                throw new InvalidOperationException($"Failed to launch QEMU: {ex.Message}", ex);
            }
        }

        public void Stop()
        {
            if (!IsRunning || _process == null) return;
            _vm.Status = VMStatus.Stopping;
            SendMonitorCommand("system_powerdown");

            // 5 秒内客户机未关机则强制结束；捕获当前进程，避免误杀之后重新启动的进程
            var process = _process;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                Thread.Sleep(5000);
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
            });
        }

        public void ForceStop()
        {
            if (!IsRunning || _process == null) return;
            try { _process.Kill(entireProcessTree: true); } catch { }
        }

        public void Pause()
        {
            if (!IsRunning) return;
            SendMonitorCommand("stop");
            _vm.Status = VMStatus.Paused;
        }

        public void Resume()
        {
            if (!IsRunning) return;
            SendMonitorCommand("cont");
            _vm.Status = VMStatus.Running;
        }

        public void SendMonitorCommand(string command)
        {
            if (!IsRunning || _process == null) return;
            try
            {
                _process.StandardInput.WriteLine(command);
                _process.StandardInput.Flush();
            }
            catch { /* 进程可能已退出 */ }
        }

        // ─── 参数构建 ───

        private static string Esc(string path) => path.Replace(",", ",,");

        private static bool IsX86(VMArchitecture a) => a == VMArchitecture.X86 || a == VMArchitecture.X86_64;

        private static bool UsesVirtMachine(VMArchitecture a) => a is VMArchitecture.ARM or VMArchitecture.AArch64
            or VMArchitecture.RISCV32 or VMArchitecture.RISCV64 or VMArchitecture.LoongArch64;

        // 这些架构没有默认机型或默认机型需要内核，未指定时补一个可用的板子
        private static string DefaultMachine(VMArchitecture a) => a switch
        {
            _ when UsesVirtMachine(a) => "virt",
            VMArchitecture.M68k => "q800",
            VMArchitecture.SH4 or VMArchitecture.SH4EB => "r2d",
            VMArchitecture.Tricore => "tricore_testboard",
            VMArchitecture.AVR => "arduino-mega-2560-v3",
            VMArchitecture.RX => "gdbsim-r5f562n8",
            _ => null
        };

        // 默认板子的内存上限（MB），超出时 QEMU 直接拒绝启动
        private static int? DefaultMachineMaxMemoryMB(VMArchitecture a) => a switch
        {
            VMArchitecture.SPARC => 256,
            VMArchitecture.MIPS or VMArchitecture.MIPSEL or VMArchitecture.MIPS64 or VMArchitecture.MIPS64EL => 1024,
            VMArchitecture.M68k => 1024,
            VMArchitecture.PPC => 2047,
            _ => null
        };

        private List<string> BuildArguments(string binaryPath)
        {
            var args = new List<string>();
            var arch = _vm.Architecture;
            bool hasMachine = !string.IsNullOrEmpty(_vm.MachineType) && _vm.MachineType != "default";
            // 只有 x86 与 virt 类机型保证有 PCI 总线，其余架构使用板载默认设备
            bool pci = IsX86(arch) || (UsesVirtMachine(arch) && (!hasMachine || _vm.MachineType == "virt"));

            args.AddRange(new[] { "-name", _vm.Name });

            if (hasMachine)
                args.AddRange(new[] { "-machine", _vm.MachineType });
            else if (DefaultMachine(arch) is string defMachine)
                args.AddRange(new[] { "-machine", defMachine });

            if (!string.IsNullOrEmpty(_vm.CpuModel) && _vm.CpuModel != "default")
                args.AddRange(new[] { "-cpu", _vm.CpuModel });
            else if (arch == VMArchitecture.AArch64)
                args.AddRange(new[] { "-cpu", "max" }); // virt 默认 CPU 为 32 位 cortex-a15

            // 老式板载机型（g3beige、SS-5 等）大多只支持单 CPU
            if (pci || hasMachine)
                args.AddRange(new[] { "-smp", Math.Max(_vm.CpuCores, 1).ToString() });

            var unit = (_vm.MemoryUnit ?? "MB").ToUpperInvariant();
            long memMB = Math.Max(1L, unit.StartsWith("G") ? _vm.MemoryValue * 1024L : _vm.MemoryValue);
            if (!hasMachine && DefaultMachineMaxMemoryMB(arch) is int maxMB && memMB > maxMB)
            {
                OnError?.Invoke($"[VMStart] Memory exceeds the default machine limit; clamped to {maxMB} MB.");
                memMB = maxMB;
            }
            args.AddRange(new[] { "-m", $"{memMB}M" });

            // WHPX 仅能加速与宿主同架构的 x86 客户机；不可用时 QEMU 会回退到下一个 -accel
            if (_vm.EnableAcceleration && IsX86(arch) && RuntimeInformation.OSArchitecture == Architecture.X64)
                args.AddRange(new[] { "-accel", "whpx,kernel-irqchip=off" });
            args.AddRange(new[] { "-accel", "tcg" });

            if (!string.IsNullOrEmpty(_vm.BiosPath))
                args.AddRange(new[] { "-bios", _vm.BiosPath });
            else if (arch == VMArchitecture.AArch64 && FindShareFile(binaryPath, "edk2-aarch64-code.fd") is string efi)
                args.AddRange(new[] { "-bios", efi });
            if (!string.IsNullOrEmpty(_vm.RomFilePath))
                args.AddRange(new[] { "-option-rom", _vm.RomFilePath });

            // 显示：图形输出走本地回环 VNC，由控制台窗口内嵌显示
            if (_vm.VncPort >= 5900)
            {
                args.AddRange(new[] { "-display", "none" });
                args.AddRange(new[] { "-vnc", $"127.0.0.1:{_vm.VncPort - 5900}" });
            }
            else
            {
                args.AddRange(new[] { "-display", string.IsNullOrEmpty(_vm.DisplayType) ? "sdl" : _vm.DisplayType });
            }
            int vramMB = Math.Clamp(_vm.VramSizeMB > 0 ? _vm.VramSizeMB : 128, 1, 256);
            if (IsX86(arch))
                args.AddRange(new[] { "-device", $"VGA,vgamem_mb={vramMB}" });
            else if (pci)
                args.AddRange(new[] { "-device", "virtio-gpu-pci" });

            // 磁盘；r2d（sh4 默认板）只有一个 IDE 位，有启动 ISO 时让给光盘
            bool singleIde = (arch is VMArchitecture.SH4 or VMArchitecture.SH4EB) && !hasMachine;
            bool hasDisk = !string.IsNullOrEmpty(_vm.DiskImagePath) && File.Exists(_vm.DiskImagePath);
            if (hasDisk && singleIde && !string.IsNullOrEmpty(_vm.BootISOPath))
            {
                OnError?.Invoke("[VMStart] This machine has a single IDE slot; booting the ISO without the hard disk.");
                hasDisk = false;
            }
            if (hasDisk)
            {
                var file = $"file={Esc(_vm.DiskImagePath)},format={DiskFormat(_vm.DiskImagePath)}";
                if (!pci)
                {
                    args.AddRange(new[] { "-drive", file });
                }
                else
                {
                    args.AddRange(new[] { "-drive", $"{file},if=none,id=hd0" });
                    switch (_vm.DiskController ?? "VirtIO")
                    {
                        case "NVMe":
                            args.AddRange(new[] { "-device", "nvme,drive=hd0,serial=VMSTART001" });
                            break;
                        case "SCSI":
                            args.AddRange(new[] { "-device", "lsi53c895a,id=scsi0" });
                            args.AddRange(new[] { "-device", "scsi-hd,drive=hd0,bus=scsi0.0" });
                            break;
                        case "SATA":
                            args.AddRange(new[] { "-device", "ahci,id=ahci0" });
                            args.AddRange(new[] { "-device", "ide-hd,drive=hd0,bus=ahci0.0" });
                            break;
                        default:
                            args.AddRange(new[] { "-device", "virtio-blk-pci,drive=hd0" });
                            break;
                    }
                }
            }

            // 光盘：启动 ISO 优先；固定驱动器 ID 为 cd0，空光驱也保留，便于运行中换盘
            var cdrom = !string.IsNullOrEmpty(_vm.BootISOPath) ? _vm.BootISOPath : _vm.CdromImagePath;
            var cdFile = string.IsNullOrEmpty(cdrom) ? "" : $",file={Esc(cdrom)}";
            if (IsX86(arch))
            {
                args.AddRange(new[] { "-drive", $"if=ide,index=2,media=cdrom,id={CdromDriveId}{cdFile}" });
                if (!string.IsNullOrEmpty(_vm.BootISOPath))
                    args.AddRange(new[] { "-boot", "order=dc" });
            }
            else if (pci)
            {
                args.AddRange(new[] { "-device", "virtio-scsi-pci,id=scsicd" });
                args.AddRange(new[] { "-drive", $"if=none,media=cdrom,id={CdromDriveId}{cdFile}" });
                args.AddRange(new[] { "-device", $"scsi-cd,drive={CdromDriveId},bus=scsicd.0" });
            }
            else if (singleIde)
            {
                if (!string.IsNullOrEmpty(cdrom) && !hasDisk)
                    args.AddRange(new[] { "-drive", $"if=ide,index=0,media=cdrom,id={CdromDriveId}{cdFile}" });
            }
            else if (!string.IsNullOrEmpty(cdrom))
            {
                args.AddRange(new[] { "-cdrom", cdrom });
            }

            if (!string.IsNullOrEmpty(_vm.FloppyAPath))
                args.AddRange(new[] { "-fda", _vm.FloppyAPath });
            if (!string.IsNullOrEmpty(_vm.FloppyBPath))
                args.AddRange(new[] { "-fdb", _vm.FloppyBPath });

            // 网络
            // PCI 机型显式挂网卡；-nic model= 在部分 virt 机型（如 riscv）上不会生效
            string nicDevice = IsX86(arch) ? "e1000" : "virtio-net-pci";
            void AddNic(string backend)
            {
                if (pci)
                {
                    args.AddRange(new[] { "-netdev", $"{backend},id=net0" });
                    args.AddRange(new[] { "-device", $"{nicDevice},netdev=net0" });
                }
                else
                {
                    args.AddRange(new[] { "-nic", backend });
                }
            }
            switch (_vm.NetworkMode)
            {
                case "bridge":
                    // Windows 没有 bridge helper，需要预先安装 TAP-Windows 网卡
                    var tap = string.IsNullOrEmpty(_vm.BridgeInterface) ? "" : $",ifname={_vm.BridgeInterface}";
                    AddNic($"tap{tap}");
                    break;
                case "host-only":
                    AddNic("socket,listen=127.0.0.1:12340");
                    break;
                case "none":
                case "modem":
                case "terminal":
                    args.AddRange(new[] { "-nic", "none" });
                    break;
                default:
                    var user = new StringBuilder("user");
                    foreach (var pf in _vm.PortForwards ?? new List<PortForwardRule>())
                        user.Append($",hostfwd={pf.Protocol}:127.0.0.1:{pf.HostPort}-{pf.GuestIP}:{pf.GuestPort}");
                    AddNic(user.ToString());
                    break;
            }

            if (_vm.EnableAudio && pci)
            {
                args.AddRange(new[] { "-audiodev", "dsound,id=audio0" });
                switch (_vm.SoundCardModel ?? "hda")
                {
                    case "ac97":
                        args.AddRange(new[] { "-device", "AC97,audiodev=audio0" });
                        break;
                    case "es1370":
                        args.AddRange(new[] { "-device", "ES1370,audiodev=audio0" });
                        break;
                    case "sb16" when IsX86(arch):
                        args.AddRange(new[] { "-device", "sb16,audiodev=audio0" });
                        break;
                    default:
                        args.AddRange(new[] { "-device", "intel-hda" });
                        args.AddRange(new[] { "-device", "hda-duplex,audiodev=audio0" });
                        break;
                }
            }

            // USB；usb-tablet 提供绝对坐标，VNC 鼠标位置才能与画面对齐
            if (_vm.EnableUSB && pci)
            {
                var usbVer = _vm.UsbVersion ?? "3.0";
                if (usbVer == "2.0" && IsX86(arch))
                {
                    args.AddRange(new[] { "-device", "ich9-usb-ehci1,id=usb0" });
                    args.AddRange(new[] { "-device", "ich9-usb-uhci1,masterbus=usb0.0,firstport=0,multifunction=on" });
                }
                else
                {
                    args.AddRange(new[] { "-device", "qemu-xhci,id=usb0" });
                }
                args.AddRange(new[] { "-device", "usb-tablet" });
                if (!IsX86(arch))
                    args.AddRange(new[] { "-device", "usb-kbd" }); // virt 机型没有 PS/2 键盘
            }

            if (_vm.EnableParallelPort && IsX86(arch) && !string.IsNullOrEmpty(_vm.BundlePath))
                args.AddRange(new[] { "-parallel", $"file:{Path.Combine(_vm.BundlePath, "parallel.out")}" });

            // 剪贴板经 qemu-vdagent 与 VNC 剪贴板互通
            if ((_vm.EnableSharedClipboard || _vm.EnableDragDrop) && pci)
            {
                args.AddRange(new[] { "-device", "virtio-serial-pci" });
                args.AddRange(new[] { "-chardev", "qemu-vdagent,id=vdagent,name=vdagent,clipboard=on" });
                args.AddRange(new[] { "-device", "virtserialport,chardev=vdagent,name=com.redhat.spice.0" });
            }

            if (_vm.EnableTimeSync)
                args.AddRange(new[] { "-rtc", "base=localtime,clock=host" });

            // Windows 版 QEMU 不支持 -virtfs，共享文件夹在此平台忽略
            if (_vm.SharedFolders?.Count > 0)
                OnError?.Invoke("[VMStart] Shared folders (virtfs) are not supported by QEMU on Windows; skipped.");

            args.AddRange(new[] { "-monitor", "stdio" });
            args.AddRange(RuntimeArgs);
            if (_vm.AdditionalArgs != null) args.AddRange(_vm.AdditionalArgs);

            return args;
        }

        public static string DiskFormat(string path) => Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".vmdk" => "vmdk",
            ".vdi" => "vdi",
            ".vhd" => "vpc",
            ".vhdx" => "vhdx",
            ".img" or ".raw" => "raw",
            _ => "qcow2"
        };

        // ─── QEMU 程序查找 ───

        private static readonly Dictionary<VMArchitecture, string> ArchBinaries = new()
        {
            { VMArchitecture.X86_64, "qemu-system-x86_64" },
            { VMArchitecture.X86, "qemu-system-i386" },
            { VMArchitecture.ARM, "qemu-system-arm" },
            { VMArchitecture.AArch64, "qemu-system-aarch64" },
            { VMArchitecture.MIPS, "qemu-system-mips" },
            { VMArchitecture.MIPS64, "qemu-system-mips64" },
            { VMArchitecture.MIPSEL, "qemu-system-mipsel" },
            { VMArchitecture.MIPS64EL, "qemu-system-mips64el" },
            { VMArchitecture.PPC, "qemu-system-ppc" },
            { VMArchitecture.PPC64, "qemu-system-ppc64" },
            { VMArchitecture.RISCV32, "qemu-system-riscv32" },
            { VMArchitecture.RISCV64, "qemu-system-riscv64" },
            { VMArchitecture.S390x, "qemu-system-s390x" },
            { VMArchitecture.SPARC, "qemu-system-sparc" },
            { VMArchitecture.SPARC64, "qemu-system-sparc64" },
            { VMArchitecture.M68k, "qemu-system-m68k" },
            { VMArchitecture.Alpha, "qemu-system-alpha" },
            { VMArchitecture.HPPA, "qemu-system-hppa" },
            { VMArchitecture.SH4, "qemu-system-sh4" },
            { VMArchitecture.SH4EB, "qemu-system-sh4eb" },
            { VMArchitecture.MicroBlaze, "qemu-system-microblaze" },
            { VMArchitecture.MicroBlazeEL, "qemu-system-microblazeel" },
            { VMArchitecture.OR1K, "qemu-system-or1k" },
            { VMArchitecture.LoongArch64, "qemu-system-loongarch64" },
            { VMArchitecture.Xtensa, "qemu-system-xtensa" },
            { VMArchitecture.XtensaEB, "qemu-system-xtensaeb" },
            { VMArchitecture.Tricore, "qemu-system-tricore" },
            { VMArchitecture.AVR, "qemu-system-avr" },
            { VMArchitecture.RX, "qemu-system-rx" },
        };

        private static IEnumerable<string> SearchDirectories()
        {
            foreach (var p in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
                if (!string.IsNullOrWhiteSpace(p)) yield return p.Trim();
            yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "qemu");
            yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "qemu");
            yield return Path.Combine(AppContext.BaseDirectory, "qemu");
        }

        private static string FindExecutable(string name)
        {
            foreach (var dir in SearchDirectories())
            {
                try
                {
                    var candidate = Path.Combine(dir, name + ".exe");
                    if (File.Exists(candidate)) return candidate;
                }
                catch (ArgumentException) { /* PATH 中可能有非法字符 */ }
            }
            return null;
        }

        // 经典 Mac / 6502 / Z80 等由 macOS 端的其他引擎提供，Windows 端没有对应 QEMU 程序
        public static string FindQEMUBinary(VMArchitecture arch) =>
            ArchBinaries.TryGetValue(arch, out var name) ? FindExecutable(name) : null;

        public static string FindQEMUImg() => FindExecutable("qemu-img");

        private static string FindShareFile(string binaryPath, string fileName)
        {
            var dir = Path.GetDirectoryName(binaryPath);
            foreach (var candidate in new[] { Path.Combine(dir, "share", fileName), Path.Combine(dir, fileName) })
                if (File.Exists(candidate)) return candidate;
            return null;
        }

        public static string RunQemuImg(params string[] arguments)
        {
            var qemuImg = FindQEMUImg() ?? throw new FileNotFoundException("qemu-img.exe not found. Install QEMU for Windows first.");
            var info = new ProcessStartInfo
            {
                FileName = qemuImg,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };
            foreach (var a in arguments) info.ArgumentList.Add(a);
            using var p = Process.Start(info);
            var stderrTask = p.StandardError.ReadToEndAsync();
            var stdout = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            if (p.ExitCode != 0)
                throw new InvalidOperationException($"qemu-img {arguments[0]} failed: {stderrTask.Result.Trim()}");
            return stdout;
        }

        public static void CreateDiskImage(string path, int size, string unit) =>
            RunQemuImg("create", "-f", "qcow2", path, $"{size}{(unit == "TB" ? "T" : "G")}");

        public void Dispose()
        {
            if (IsRunning) ForceStop();
            _process?.Dispose();
        }
    }
}
