// Nachgebaute Windows-Funktionen für die BuyCheck-Simulation (nur Testumgebung, nicht Teil von BuyCheck).
// Signaturen entsprechen exakt den per Reflection.Emit erzeugten P/Invoke-Methoden in lib/Native.ps1.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace BuyCheckSim
{
    public static class Win32
    {
        // ------------------------------------------------------------ Szenario-Daten (werden aus PowerShell gesetzt)
        public static int DiskCount = 2;
        public static int[] BusType = new int[] { 17, 7 };
        public static bool[] Removable = new bool[] { false, true };
        public static bool[] SeekPenalty = new bool[] { false, false };
        public static bool SeekPenaltySupported = true;
        public static string[] Vendor = new string[] { "", "SanDisk" };
        public static string[] Product = new string[] { "Samsung SSD 980 PRO 1TB", "Ultra" };
        public static string[] Revision = new string[] { "5B2QGXA7", "1.00" };
        public static string[] Serial = new string[] { "S5GXNF0R123456", "4C530001" };
        public static long[] Size = new long[] { 1000204886016L, 32000000000L };
        public static bool[] Nvme = new bool[] { true, false };
        public static bool NvmeSupported = true;
        public static byte[] NvmeIdentify;
        public static byte[] NvmeHealth;
        public static int SystemDisk = 0;
        public static long SlowFrom = -1, SlowTo = -1;
        public static long[] BadOffsets = new long[0];
        public static int BlockSleepMs = 2;
        public static int SlowSleepMs = 40;

        public static int Arch = 9, Level = 6, Revision16 = 0x8E0A, Procs = 8;
        public static string Brand = "Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz";
        public static int Cores = 4, ThreadsPerCore = 2;
        public static int L1 = 32768, L2 = 262144, L3 = 8388608;
        public static byte[] Smbios;
        public static bool HasFirmwareTypeApi = true;
        public static int FirmwareType = 2;
        public static bool Sse42 = true;
        public static ulong MemTotal = 16UL << 30, MemAvail = 9UL << 30;
        public static long InstalledKB = 16L << 20;
        public static bool AcOnline = true;
        public static int Percent = 80;
        public static int InjectMemErrorAt = -1;

        // ------------------------------------------------------------ Protokoll für die Auswertung der Simulation
        public static List<string> Log = new List<string>();
        public static bool WriteAccessRequested = false;
        public static int OpenHandles = 0;
        static readonly Dictionary<long, string> paths = new Dictionary<long, string>();
        static readonly Dictionary<long, int> access = new Dictionary<long, int>();
        static readonly Dictionary<long, long> pos = new Dictionary<long, long>();
        static readonly Dictionary<long, IntPtr> allocs = new Dictionary<long, IntPtr>();
        static long nextHandle = 100;

        static bool Fail(int err) { Marshal.SetLastPInvokeError(err); return false; }
        static void W32(byte[] b, int o, int v) { Array.Copy(BitConverter.GetBytes(v), 0, b, o, 4); }
        static void W64(byte[] b, int o, long v) { Array.Copy(BitConverter.GetBytes(v), 0, b, o, 8); }
        static int DiskOf(IntPtr h)
        {
            string p; if (!paths.TryGetValue(h.ToInt64(), out p)) return -2;
            if (p.StartsWith(@"\\.\PhysicalDrive")) return int.Parse(p.Substring(17));
            return -1; // Laufwerk/Volume
        }

        // ------------------------------------------------------------ kernel32
        public static IntPtr CreateFileW(string path, int acc, int share, IntPtr sa, int disp, int flags, IntPtr tmpl)
        {
            Log.Add(string.Format("CreateFile {0} access=0x{1:X8} flags=0x{2:X8} disp={3}", path, acc, flags, disp));
            if ((acc & 0x40000000) != 0 || disp != 3) WriteAccessRequested = true;
            if (path.StartsWith(@"\\.\PhysicalDrive"))
            {
                int n; if (!int.TryParse(path.Substring(17), out n) || n >= DiskCount) { Marshal.SetLastPInvokeError(2); return new IntPtr(-1); }
                if (acc != 0 && (acc & unchecked((int)0x80000000)) == 0) { Marshal.SetLastPInvokeError(5); return new IntPtr(-1); }
            }
            else if (!path.StartsWith(@"\\.\")) { Marshal.SetLastPInvokeError(2); return new IntPtr(-1); }
            long h = nextHandle++;
            paths[h] = path; access[h] = acc; pos[h] = 0; OpenHandles++;
            return new IntPtr(h);
        }

        public static bool CloseHandle(IntPtr h)
        {
            if (paths.Remove(h.ToInt64())) { OpenHandles--; return true; }
            return Fail(6);
        }

        public static bool DeviceIoControl(IntPtr h, int code, byte[] inBuf, int inSize, byte[] outBuf, int outSize, out int returned, IntPtr ov)
        {
            returned = 0;
            int disk = DiskOf(h);
            if (disk == -2) return Fail(6);
            if (code == 0x002D1400)
            {
                int prop = BitConverter.ToInt32(inBuf, 0);
                if (disk < 0) return Fail(1);
                if (prop == 0)
                {
                    Array.Clear(outBuf, 0, outSize);
                    int o = 40;
                    W32(outBuf, 0, 40); W32(outBuf, 4, 200);
                    outBuf[10] = (byte)(Removable[disk] ? 1 : 0);
                    W32(outBuf, 28, BusType[disk]);
                    string[] s = new string[] { Vendor[disk], Product[disk], Revision[disk], Serial[disk] };
                    int[] at = new int[] { 12, 16, 20, 24 };
                    for (int i = 0; i < 4; i++)
                    {
                        if (string.IsNullOrEmpty(s[i])) continue;
                        W32(outBuf, at[i], o);
                        byte[] b = Encoding.ASCII.GetBytes(s[i]);
                        Array.Copy(b, 0, outBuf, o, b.Length); o += b.Length + 1;
                    }
                    returned = o; return true;
                }
                if (prop == 7)
                {
                    if (!SeekPenaltySupported) return Fail(1);
                    W32(outBuf, 0, 12); W32(outBuf, 4, 12); outBuf[8] = (byte)(SeekPenalty[disk] ? 1 : 0); returned = 12; return true;
                }
                if (prop == 49 || prop == 50)
                {
                    if (!NvmeSupported || !Nvme[disk]) return Fail(50);
                    int proto = BitConverter.ToInt32(inBuf, 8), type = BitConverter.ToInt32(inBuf, 12), req = BitConverter.ToInt32(inBuf, 16);
                    int off = BitConverter.ToInt32(inBuf, 24), len = BitConverter.ToInt32(inBuf, 28);
                    if (proto != 3 || off != 40) return Fail(87);
                    byte[] data = null;
                    if (type == 1 && req == 1) data = NvmeIdentify;
                    else if (type == 2 && req == 2) data = NvmeHealth;
                    if (data == null || 48 + len > outSize) return Fail(87);
                    W32(outBuf, 0, 48); W32(outBuf, 4, 48);
                    W32(outBuf, 8, 3); W32(outBuf, 12, type); W32(outBuf, 16, req); W32(outBuf, 24, 40); W32(outBuf, 28, Math.Min(len, data.Length));
                    Array.Copy(data, 0, outBuf, 48, Math.Min(len, data.Length));
                    returned = 48 + len; return true;
                }
                return Fail(1);
            }
            if (code == 0x000700A0) { if (disk < 0) return Fail(1); Array.Clear(outBuf, 0, outSize); W32(outBuf, 20, 512); W64(outBuf, 24, Size[disk]); returned = 32; return true; }
            if (code == 0x0007405C)
            {
                if (disk < 0) return Fail(1);
                if ((access[h.ToInt64()] & unchecked((int)0x80000000)) == 0) return Fail(5);
                W64(outBuf, 0, Size[disk]); returned = 8; return true;
            }
            if (code == 0x002D1080) { if (disk != -1) return Fail(1); W32(outBuf, 0, 7); W32(outBuf, 4, SystemDisk); W32(outBuf, 8, 3); returned = 12; return true; }
            return Fail(1);
        }

        public static bool SetFilePointerEx(IntPtr h, long dist, out long newPos, int method)
        {
            newPos = 0;
            if (!paths.ContainsKey(h.ToInt64())) return Fail(6);
            if (method != 0) return Fail(87);
            pos[h.ToInt64()] = dist; newPos = dist; return true;
        }

        public static bool ReadFile(IntPtr h, IntPtr buffer, int toRead, out int read, IntPtr ov)
        {
            read = 0;
            int disk = DiskOf(h);
            if (disk < 0) return Fail(6);
            if ((access[h.ToInt64()] & unchecked((int)0x80000000)) == 0) return Fail(5);
            long p = pos[h.ToInt64()];
            if ((buffer.ToInt64() & 4095) != 0 || (toRead % 512) != 0 || (p % 512) != 0) return Fail(87);   // ungepuffert: ausgerichtet!
            if (p >= Size[disk]) return true;
            foreach (long bad in BadOffsets) { if (bad >= p && bad < p + toRead) { Thread.Sleep(30); return Fail(23); } }
            bool slow = p + toRead > SlowFrom && p < SlowTo;
            if (toRead >= 1048576) Thread.Sleep(slow ? SlowSleepMs : BlockSleepMs);
            read = (int)Math.Min(toRead, Size[disk] - p);
            pos[h.ToInt64()] = p + read;
            return true;
        }

        public static IntPtr VirtualAlloc(IntPtr a, UIntPtr size, int type, int protect)
        {
            IntPtr raw = Marshal.AllocHGlobal((IntPtr)((long)size.ToUInt64() + 4096));
            long aligned = (raw.ToInt64() + 4095) & ~4095L;
            allocs[aligned] = raw;
            return new IntPtr(aligned);
        }

        public static bool VirtualFree(IntPtr a, UIntPtr size, int freeType)
        {
            IntPtr raw; if (!allocs.TryGetValue(a.ToInt64(), out raw)) return Fail(87);
            allocs.Remove(a.ToInt64()); Marshal.FreeHGlobal(raw); return true;
        }

        public static void GetNativeSystemInfo(byte[] b)
        {
            int p = IntPtr.Size;
            Array.Clear(b, 0, b.Length);
            b[0] = (byte)Arch; b[1] = (byte)(Arch >> 8);
            W32(b, 4, 4096);
            W32(b, 8 + 3 * p, Procs);
            b[20 + 3 * p] = (byte)Level; b[21 + 3 * p] = (byte)(Level >> 8);
            b[22 + 3 * p] = (byte)Revision16; b[23 + 3 * p] = (byte)(Revision16 >> 8);
        }

        public static bool GetLogicalProcessorInformation(byte[] buffer, ref int len)
        {
            int entry = IntPtr.Size == 8 ? 32 : 24, u = IntPtr.Size == 8 ? 16 : 8;
            var list = new List<byte[]>();
            Func<long, int, byte[]> mk = (mask, rel) => { byte[] e = new byte[entry]; if (IntPtr.Size == 8) W64(e, 0, mask); else W32(e, 0, (int)mask); W32(e, IntPtr.Size, rel); return e; };
            long all = 0;
            for (int c = 0; c < Cores; c++)
            {
                long mask = ((1L << ThreadsPerCore) - 1) << (c * ThreadsPerCore); all |= mask;
                byte[] core = mk(mask, 0); core[u] = (byte)(ThreadsPerCore > 1 ? 1 : 0); list.Add(core);
                foreach (int[] cache in new int[][] { new int[] { 1, L1, 2 }, new int[] { 1, L1, 1 }, new int[] { 2, L2, 0 } })
                {
                    byte[] e = mk(mask, 2); e[u] = (byte)cache[0]; e[u + 1] = 8; e[u + 2] = 64; W32(e, u + 4, cache[1]); W32(e, u + 8, cache[2]); list.Add(e);
                }
            }
            byte[] l3 = mk(all, 2); l3[u] = 3; e3(l3, u, L3); list.Add(l3);
            list.Add(mk(all, 3));
            int need = list.Count * entry;
            if (buffer == null || buffer.Length < need || len < need) { len = need; return Fail(122); }
            for (int i = 0; i < list.Count; i++) Array.Copy(list[i], 0, buffer, i * entry, entry);
            len = need; return true;
        }
        static void e3(byte[] e, int u, int size) { e[u + 1] = 16; e[u + 2] = 64; W32(e, u + 4, size); W32(e, u + 8, 0); }

        public static int GetSystemFirmwareTable(int provider, int id, byte[] buf, int size)
        {
            if (provider != 0x52534D42 || Smbios == null) { Marshal.SetLastPInvokeError(1); return 0; }
            int need = Smbios.Length + 8;
            if (buf == null || size < need) return need;
            buf[0] = 0; buf[1] = 3; buf[2] = 2; buf[3] = 0; W32(buf, 4, Smbios.Length);
            Array.Copy(Smbios, 0, buf, 8, Smbios.Length);
            return need;
        }

        public static bool GetFirmwareType(out int t)
        {
            if (!HasFirmwareTypeApi) throw new EntryPointNotFoundException("GetFirmwareType (Windows 7)");
            t = FirmwareType; return true;
        }

        public static int GetFirmwareEnvironmentVariableW(string name, string guid, IntPtr buf, int size)
        {
            Marshal.SetLastPInvokeError(FirmwareType == 2 ? 998 : 1); return 0;
        }

        public static int SetThreadExecutionState(int flags) { Log.Add(string.Format("SetThreadExecutionState 0x{0:X8}", flags)); return 0; }
        public static bool IsProcessorFeaturePresent(int f) { return f == 38 ? Sse42 : true; }

        public static bool GlobalMemoryStatusEx(byte[] b)
        {
            if (BitConverter.ToInt32(b, 0) != 64) return Fail(87);
            W64(b, 8, (long)MemTotal); W64(b, 16, (long)MemAvail); return true;
        }

        public static bool GetPhysicallyInstalledSystemMemory(out long kb) { kb = InstalledKB; return true; }

        public static bool GetSystemPowerStatus(byte[] b)
        {
            b[0] = (byte)(AcOnline ? 1 : 0); b[1] = (byte)(AcOnline ? 8 : 0); b[2] = (byte)Percent; b[3] = 0;
            W32(b, 4, -1); W32(b, 8, -1); return true;
        }

        // Konsole: in der Simulation gibt es keine echte Konsole
        public static IntPtr GetStdHandle(int which) { return IntPtr.Zero; }
        public static bool GetConsoleMode(IntPtr h, out int mode) { mode = 0; return Fail(6); }
        public static bool SetConsoleMode(IntPtr h, int mode) { return Fail(6); }
        public static bool GetNumberOfConsoleInputEvents(IntPtr h, out int n) { n = 0; return Fail(6); }
        public static bool ReadConsoleInputW(IntPtr h, byte[] buf, int len, out int read) { read = 0; return Fail(6); }
        public static bool FlushConsoleInputBuffer(IntPtr h) { return Fail(6); }
        public static IntPtr GetConsoleWindow() { return IntPtr.Zero; }

        // ------------------------------------------------------------ ntdll
        public static int NtQuerySystemInformation(int cls, byte[] buf, int len, out int ret)
        {
            ret = 0;
            if (cls != 105 || Brand == null) return unchecked((int)0xC0000003);
            byte[] b = Encoding.ASCII.GetBytes(Brand + "\0");
            Array.Copy(b, 0, buf, 0, Math.Min(b.Length, len)); ret = b.Length; return 0;
        }

        public static UIntPtr RtlCompareMemory(byte[] a, byte[] b, UIntPtr len)
        {
            long n = (long)len.ToUInt64();
            if (InjectMemErrorAt >= 0 && InjectMemErrorAt < n) { int at = InjectMemErrorAt; InjectMemErrorAt = -1; return new UIntPtr((ulong)at); }
            for (long i = 0; i < n; i++) if (a[i] != b[i]) return new UIntPtr((ulong)i);
            return len;
        }

        // ------------------------------------------------------------ user32 / winmm
        public static bool GetCursorPos(byte[] p) { return Fail(5); }
        public static short GetAsyncKeyState(int vk) { return 0; }
        public static int GetSystemMetrics(int i) { return i == 0 ? 1920 : 1080; }
        public static bool ShowWindow(IntPtr h, int cmd) { return false; }

        public static int mciSendStringW(string cmd, StringBuilder ret, int len, IntPtr hwnd)
        {
            Log.Add("MCI " + cmd);
            if (cmd.StartsWith("status") && cmd.EndsWith("level")) ret.Append("9000");
            return 0;
        }
    }
}
