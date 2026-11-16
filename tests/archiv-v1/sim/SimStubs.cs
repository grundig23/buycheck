using System.Text;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
namespace BuyCheck {
    public static class Bytes
    {
        public static int U16(byte[] d, int o) { return (o + 1 < d.Length) ? (d[o] | (d[o + 1] << 8)) : 0; }
        public static long U32(byte[] d, int o) { return (o + 3 < d.Length) ? (long)BitConverter.ToUInt32(d, o) : 0; }
        public static double U128(byte[] d, int o)
        {
            if (o + 15 >= d.Length) return 0;
            ulong lo = BitConverter.ToUInt64(d, o);
            ulong hi = BitConverter.ToUInt64(d, o + 8);
            return (double)lo + (double)hi * 18446744073709551616.0;
        }
        public static string Ascii(byte[] d, int o, int len)
        {
            if (o >= d.Length) return "";
            len = Math.Min(len, d.Length - o);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < len; i++)
            {
                byte b = d[o + i];
                if (b == 0) break;
                sb.Append((b >= 32 && b < 127) ? (char)b : '?');
            }
            return sb.ToString().Trim();
        }
        public static string Hex(byte[] d, int o, int len)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < len && o + i < d.Length; i++) sb.Append(d[o + i].ToString("X2"));
            return sb.ToString();
        }
    }

    public class NvmeIdentifyInfo
    {
        public int VendorId;
        public int SubsystemVendorId;
        public string SerialNumber;
        public string Model;
        public string Firmware;
        public string IeeeOui;
        public int ControllerId;
        public string NvmeVersion;
        public int Oacs;
        public bool SelfTestSupported;
        public int WarningTempThresholdKelvin;
        public int CriticalTempThresholdKelvin;
        public double TotalNvmCapacityBytes;
        public double UnallocatedNvmCapacityBytes;
        public long NamespaceCount;

        public string VendorIdHex { get { return VendorId.ToString("X4"); } }
        public string SubsystemVendorIdHex { get { return SubsystemVendorId.ToString("X4"); } }

        public static NvmeIdentifyInfo Parse(byte[] d)
        {
            NvmeIdentifyInfo i = new NvmeIdentifyInfo();
            i.VendorId = Bytes.U16(d, 0);
            i.SubsystemVendorId = Bytes.U16(d, 2);
            i.SerialNumber = Bytes.Ascii(d, 4, 20);
            i.Model = Bytes.Ascii(d, 24, 40);
            i.Firmware = Bytes.Ascii(d, 64, 8);
            i.IeeeOui = d[75].ToString("X2") + d[74].ToString("X2") + d[73].ToString("X2");
            i.ControllerId = Bytes.U16(d, 78);
            long ver = Bytes.U32(d, 80);
            i.NvmeVersion = ver == 0 ? "" : ((ver >> 16) & 0xFFFF) + "." + ((ver >> 8) & 0xFF) + "." + (ver & 0xFF);
            i.Oacs = Bytes.U16(d, 256);
            i.SelfTestSupported = (i.Oacs & 0x10) != 0;
            i.WarningTempThresholdKelvin = Bytes.U16(d, 266);
            i.CriticalTempThresholdKelvin = Bytes.U16(d, 268);
            i.TotalNvmCapacityBytes = Bytes.U128(d, 280);
            i.UnallocatedNvmCapacityBytes = Bytes.U128(d, 296);
            i.NamespaceCount = Bytes.U32(d, 516);
            return i;
        }
    }

    public class NvmeHealthInfo
    {
        public int CriticalWarning;
        public int CompositeTemperatureKelvin;
        public int AvailableSpare;
        public int AvailableSpareThreshold;
        public int PercentageUsed;
        public int EnduranceGroupCriticalWarning;
        public double DataUnitsRead;
        public double DataUnitsWritten;
        public double HostReadCommands;
        public double HostWriteCommands;
        public double ControllerBusyTimeMinutes;
        public double PowerCycles;
        public double PowerOnHours;
        public double UnsafeShutdowns;
        public double MediaErrors;
        public double ErrorLogEntries;
        public long WarningTempMinutes;
        public long CriticalTempMinutes;
        public int[] TempSensorsKelvin;
        public long ThermalMgmtT1Transitions;
        public long ThermalMgmtT2Transitions;
        public long ThermalMgmtT1Seconds;
        public long ThermalMgmtT2Seconds;
        public string RawHex;

        public double TemperatureCelsius { get { return CompositeTemperatureKelvin > 0 ? CompositeTemperatureKelvin - 273 : double.NaN; } }
        // 1 Data Unit = 1000 * 512 Byte
        public double TerabytesWritten { get { return DataUnitsWritten * 512000.0 / 1e12; } }
        public double TerabytesRead { get { return DataUnitsRead * 512000.0 / 1e12; } }

        public static NvmeHealthInfo Parse(byte[] d)
        {
            NvmeHealthInfo h = new NvmeHealthInfo();
            h.CriticalWarning = d[0];
            h.CompositeTemperatureKelvin = Bytes.U16(d, 1);
            h.AvailableSpare = d[3];
            h.AvailableSpareThreshold = d[4];
            h.PercentageUsed = d[5];
            h.EnduranceGroupCriticalWarning = d[6];
            h.DataUnitsRead = Bytes.U128(d, 32);
            h.DataUnitsWritten = Bytes.U128(d, 48);
            h.HostReadCommands = Bytes.U128(d, 64);
            h.HostWriteCommands = Bytes.U128(d, 80);
            h.ControllerBusyTimeMinutes = Bytes.U128(d, 96);
            h.PowerCycles = Bytes.U128(d, 112);
            h.PowerOnHours = Bytes.U128(d, 128);
            h.UnsafeShutdowns = Bytes.U128(d, 144);
            h.MediaErrors = Bytes.U128(d, 160);
            h.ErrorLogEntries = Bytes.U128(d, 176);
            h.WarningTempMinutes = Bytes.U32(d, 192);
            h.CriticalTempMinutes = Bytes.U32(d, 196);
            List<int> sensors = new List<int>();
            for (int i = 0; i < 8; i++)
            {
                int t = Bytes.U16(d, 200 + i * 2);
                if (t > 0) sensors.Add(t);
            }
            h.TempSensorsKelvin = sensors.ToArray();
            h.ThermalMgmtT1Transitions = Bytes.U32(d, 216);
            h.ThermalMgmtT2Transitions = Bytes.U32(d, 220);
            h.ThermalMgmtT1Seconds = Bytes.U32(d, 224);
            h.ThermalMgmtT2Seconds = Bytes.U32(d, 228);
            h.RawHex = Bytes.Hex(d, 0, Math.Min(d.Length, 512));
            return h;
        }
    }

    public class CpuTopology
    {
        public int Cores;
        public int LogicalProcessors;
        public int Packages;
        public long L1DataBytes;
        public long L1InstructionBytes;
        public long L2Bytes;
        public long L3Bytes;
        public int L3Instances;
    }

    public class SmbiosStructure
    {
        public int Type;
        public int Handle;
        public byte[] Data;
        public List<string> Strings = new List<string>();

        public int Length { get { return Data == null ? 0 : Data.Length; } }

        public string Str(int offset)
        {
            if (Data == null || offset >= Data.Length) return null;
            int idx = Data[offset];
            if (idx == 0 || idx > Strings.Count) return null;
            string s = Strings[idx - 1];
            return s == null ? null : s.Trim();
        }
        public int Byte(int offset) { return (Data != null && offset < Data.Length) ? Data[offset] : -1; }
        public int Word(int offset) { return (Data != null && offset + 1 < Data.Length) ? (Data[offset] | (Data[offset + 1] << 8)) : -1; }
        public long Dword(int offset) { return (Data != null && offset + 3 < Data.Length) ? (long)BitConverter.ToUInt32(Data, offset) : -1; }
        public string HexBytes(int offset, int count) { return Data == null ? "" : Bytes.Hex(Data, offset, count); }
    }

    public class EdidInfo
    {
        public bool Valid;
        public string ManufacturerId;
        public int ProductCode;
        public long SerialNumber;
        public int WeekOfManufacture;
        public int YearOfManufacture;
        public string Version;
        public bool Digital;
        public int WidthCm;
        public int HeightCm;
        public int NativeWidth;
        public int NativeHeight;
        public double NativeRefreshHz;
        public int ImageWidthMm;
        public int ImageHeightMm;
        public string MonitorName = "";
        public string SerialText = "";
        public List<string> TextDescriptors = new List<string>();
        public int ExtensionCount;

        public string ProductCodeHex { get { return ProductCode.ToString("X4"); } }
        public string PnpId { get { return (ManufacturerId ?? "???") + ProductCode.ToString("X4"); } }
        public double DiagonalInches
        {
            get
            {
                double w = ImageWidthMm > 0 ? ImageWidthMm / 25.4 : WidthCm / 2.54;
                double h = ImageHeightMm > 0 ? ImageHeightMm / 25.4 : HeightCm / 2.54;
                return Math.Sqrt(w * w + h * h);
            }
        }

        public static EdidInfo Parse(byte[] d)
        {
            EdidInfo e = new EdidInfo();
            if (d == null || d.Length < 128) return e;
            if (!(d[0] == 0 && d[1] == 0xFF && d[2] == 0xFF && d[3] == 0xFF && d[4] == 0xFF && d[5] == 0xFF && d[6] == 0xFF && d[7] == 0))
                return e;
            e.Valid = true;
            int m = (d[8] << 8) | d[9];
            e.ManufacturerId = new string(new char[] {
                (char)('A' - 1 + ((m >> 10) & 0x1F)), (char)('A' - 1 + ((m >> 5) & 0x1F)), (char)('A' - 1 + (m & 0x1F)) });
            e.ProductCode = d[10] | (d[11] << 8);
            e.SerialNumber = (long)BitConverter.ToUInt32(d, 12);
            e.WeekOfManufacture = d[16];
            e.YearOfManufacture = d[17] + 1990;
            e.Version = d[18] + "." + d[19];
            e.Digital = (d[20] & 0x80) != 0;
            e.WidthCm = d[21];
            e.HeightCm = d[22];
            e.ExtensionCount = d[126];
            bool first = true;
            for (int i = 0; i < 4; i++)
            {
                int o = 54 + i * 18;
                int pclk = d[o] | (d[o + 1] << 8);
                if (pclk != 0)
                {
                    if (first)
                    {
                        first = false;
                        int hActive = d[o + 2] | ((d[o + 4] & 0xF0) << 4);
                        int hBlank = d[o + 3] | ((d[o + 4] & 0x0F) << 8);
                        int vActive = d[o + 5] | ((d[o + 7] & 0xF0) << 4);
                        int vBlank = d[o + 6] | ((d[o + 7] & 0x0F) << 8);
                        e.NativeWidth = hActive;
                        e.NativeHeight = vActive;
                        e.ImageWidthMm = d[o + 12] | ((d[o + 14] & 0xF0) << 4);
                        e.ImageHeightMm = d[o + 13] | ((d[o + 14] & 0x0F) << 8);
                        double total = (double)(hActive + hBlank) * (vActive + vBlank);
                        if (total > 0) e.NativeRefreshHz = Math.Round(pclk * 10000.0 / total, 1);
                    }
                }
                else
                {
                    int tag = d[o + 3];
                    string text = DescriptorText(d, o + 5);
                    if (tag == 0xFC) e.MonitorName = text;
                    else if (tag == 0xFF) e.SerialText = text;
                    else if (tag == 0xFE && text.Length > 0) e.TextDescriptors.Add(text);
                }
            }
            return e;
        }

        static string DescriptorText(byte[] d, int o)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 13 && o + i < d.Length; i++)
            {
                byte b = d[o + i];
                if (b == 0x0A || b == 0) break;
                sb.Append((b >= 32 && b < 127) ? (char)b : ' ');
            }
            return sb.ToString().Trim();
        }
    }

    public class CheckOption
    {
        public string Key = "";
        public string Label = "";
        public string Unit = "";
        public decimal Value;
        public decimal Min;
        public decimal Max = 100;
        public decimal Increment = 1;
        public int DecimalPlaces;
        public int SecondsPerUnit;   // wie stark die Option die geschätzte Dauer beeinflusst
    }

    public class CheckInfo
    {
        public string Id = "";
        public string Category = "";
        public int CategoryOrder;
        public int Order;
        public string Title = "";
        public string Description = "";
        public int BaseSeconds;
        public bool Interactive;
        public bool NeedsAcPower;
        public string[] Profiles = new string[0];
        public bool Selected;
        public List<CheckOption> Options = new List<CheckOption>();

        public CheckOption AddOption(string key, string label, decimal value, decimal min, decimal max, int secondsPerUnit, string unit)
        {
            CheckOption o = new CheckOption();
            o.Key = key; o.Label = label; o.Value = value; o.Min = min; o.Max = max;
            o.SecondsPerUnit = secondsPerUnit; o.Unit = unit ?? "";
            Options.Add(o);
            return o;
        }

        public decimal GetOption(string key, decimal fallback)
        {
            foreach (CheckOption o in Options) if (o.Key == key) return o.Value;
            return fallback;
        }

        public void SetOption(string key, decimal value)
        {
            foreach (CheckOption o in Options)
                if (o.Key == key) o.Value = Math.Max(o.Min, Math.Min(o.Max, value));
        }

        public int EstimatedSeconds()
        {
            decimal s = BaseSeconds;
            foreach (CheckOption o in Options) s += o.Value * o.SecondsPerUnit;
            return (int)s;
        }

        public bool InProfile(string profileId)
        {
            if (profileId == "all") return true;
            if (profileId == "none") return false;
            foreach (string p in Profiles) if (p == profileId) return true;
            return false;
        }
    }

    public class ProfileInfo
    {
        public string Id = "";
        public string Label = "";
        public string Description = "";
        public ProfileInfo() { }
        public ProfileInfo(string id, string label, string description) { Id = id; Label = label; Description = description; }
    }

    // Ergebnis eines interaktiven Tests
    public class InteractiveResult
    {
        public string Verdict = "Skip";   // OK | Problem | Skip
        public string Comment = "";
        public List<string> Problems = new List<string>();
        public List<string> Details = new List<string>();
    }

    public class AskResult
    {
        public bool Cancelled = true;
        public int Choice = -1;
        public string ChoiceText = "";
        public bool[] Checked = new bool[0];
        public List<string> CheckedTexts = new List<string>();
        public string Comment = "";
    }

    public class ChecklistItem
    {
        public string Text = "";
        public string Hint = "";
        public int State = 2;     // 0 = OK, 1 = Problem, 2 = nicht geprüft
        public string Comment = "";
        public ChecklistItem() { }
        public ChecklistItem(string text, string hint) { Text = text; Hint = hint ?? ""; }
    }

    public class CpuStress
    {
        Thread[] threads;
        volatile bool stop;
        long[] counters;
        long errors;
        ulong expected;
        readonly Stopwatch sw = new Stopwatch();

        public int ThreadCount;
        public bool Running { get { return threads != null && !stop; } }
        public long Errors { get { return Interlocked.Read(ref errors); } }
        public double ElapsedSeconds { get { return sw.Elapsed.TotalSeconds; } }

        public long TotalUnits
        {
            get
            {
                long s = 0;
                if (counters == null) return 0;
                for (int i = 0; i < ThreadCount; i++) s += Interlocked.Read(ref counters[i * 16]);
                return s;
            }
        }

        // Deterministische Mischung aus Gleitkomma- und Ganzzahlarbeit. Jeder Aufruf mit gleichem Startwert
        // muss exakt dasselbe Ergebnis liefern – Abweichungen bedeuten Rechenfehler (Instabilität).
        public static ulong WorkUnit(uint seed)
        {
            double a = 1.0001 + seed * 1e-9, b = 0.9999, c = 0.5;
            ulong h = 14695981039346656037UL;
            for (int i = 0; i < 150000; i++)
            {
                a = a * b + c;
                b = Math.Sqrt(a) * 0.999 + 1e-7 * (i & 7);
                c = (a - b) * 0.5 + 1e-3;
                ulong bits = unchecked((ulong)BitConverter.DoubleToInt64Bits(a));
                h ^= bits;
                h = unchecked(h * 1099511628211UL);
                h ^= h >> 29;
                if (a > 1e6) a = 1.0001;
            }
            return h;
        }

        public void Start(int threadCount)
        {
            if (threadCount < 1) threadCount = 1;
            expected = WorkUnit(4242);
            ThreadCount = threadCount;
            counters = new long[threadCount * 16]; // Abstand gegen False Sharing
            errors = 0;
            stop = false;
            threads = new Thread[threadCount];
            for (int i = 0; i < threadCount; i++)
            {
                int idx = i;
                threads[i] = new Thread(delegate() { Run(idx); });
                threads[i].IsBackground = true;
                threads[i].Priority = ThreadPriority.BelowNormal;
            }
            sw.Reset();
            sw.Start();
            foreach (Thread t in threads) t.Start();
        }

        void Run(int idx)
        {
            while (!stop)
            {
                ulong r = WorkUnit(4242);
                if (r != expected) Interlocked.Increment(ref errors);
                Interlocked.Increment(ref counters[idx * 16]);
            }
        }

        public void Stop()
        {
            stop = true;
            if (threads != null) foreach (Thread t in threads) { try { t.Join(3000); } catch { } }
            sw.Stop();
        }
    }

    // ================================================================== Arbeitsspeichertest (nur freier RAM)
    public class MemTest
    {
        public long RequestedBytes;
        public long AllocatedBytes;
        public long TestedBytes;
        public long Errors;
        public int Pass;
        public volatile string Phase = "";
        public volatile bool Done;
        public string Error;
        public readonly List<string> ErrorSamples = new List<string>();
        public double ElapsedSeconds { get { return sw.Elapsed.TotalSeconds; } }

        volatile bool cancel;
        Thread worker;
        readonly Stopwatch sw = new Stopwatch();
        int seconds;
        int threads;

        public void Start(long bytes, int seconds, int threads)
        {
            RequestedBytes = bytes;
            this.seconds = Math.Max(10, seconds);
            this.threads = Math.Max(1, threads);
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Start();
        }

        public void Cancel() { cancel = true; }
        public void Wait(int ms) { if (worker != null) worker.Join(ms); }

        void Run()
        {
            List<long[]> chunks = new List<long[]>();
            sw.Start();
            try
            {
                Phase = "Speicher reservieren";
                const int chunkLongs = 4 * 1024 * 1024; // 32 MiB je Block
                long remaining = RequestedBytes;
                while (remaining >= 8L * 1024 * 1024 && !cancel)
                {
                    int n = (int)Math.Min((long)chunkLongs, remaining / 8);
                    long[] c;
                    try { c = new long[n]; }
                    catch (OutOfMemoryException) { break; }
                    chunks.Add(c);
                    AllocatedBytes += (long)n * 8;
                    remaining -= (long)n * 8;
                }
                if (chunks.Count == 0) { Error = "Es konnte kein freier Arbeitsspeicher reserviert werden."; return; }
                long[] baseIndex = new long[chunks.Count];
                long acc = 0;
                for (int i = 0; i < chunks.Count; i++) { baseIndex[i] = acc; acc += chunks[i].Length; }

                while (!cancel)
                {
                    Pass++;
                    for (int p = 0; p < 4 && !cancel; p++)
                    {
                        int pattern = p;
                        ulong seed = unchecked((ulong)Pass * 0x9E3779B97F4A7C15UL + (ulong)pattern * 0x632BE59BD9B4E019UL);
                        Phase = "Durchlauf " + Pass + ", Muster " + (pattern + 1) + "/4: schreiben";
                        ForEachChunk(chunks.Count, delegate(int ci) { Fill(chunks[ci], baseIndex[ci], pattern, seed); });
                        if (cancel) break;
                        Phase = "Durchlauf " + Pass + ", Muster " + (pattern + 1) + "/4: prüfen";
                        ForEachChunk(chunks.Count, delegate(int ci) { Verify(chunks[ci], baseIndex[ci], pattern, seed, ci); });
                        Interlocked.Add(ref TestedBytes, AllocatedBytes);
                    }
                    if (sw.Elapsed.TotalSeconds >= seconds) break;
                }
            }
            catch (Exception ex) { Error = ex.Message; }
            finally
            {
                chunks.Clear();
                chunks = null;
                GC.Collect();
                GC.WaitForPendingFinalizers();
                sw.Stop();
                Phase = "fertig";
                Done = true;
            }
        }

        void ForEachChunk(int count, Action<int> body)
        {
            int next = -1;
            Thread[] ts = new Thread[threads];
            for (int t = 0; t < threads; t++)
            {
                ts[t] = new Thread(delegate()
                {
                    while (!cancel)
                    {
                        int i = Interlocked.Increment(ref next);
                        if (i >= count) break;
                        body(i);
                    }
                });
                ts[t].IsBackground = true;
                ts[t].Start();
            }
            foreach (Thread t in ts) t.Join();
        }

        static ulong Value(long globalIndex, int pattern, ulong seed)
        {
            unchecked
            {
                ulong g = (ulong)globalIndex;
                switch (pattern)
                {
                    case 0: return g * 0x9E3779B97F4A7C15UL ^ seed;
                    case 1: return ~(g * 0x9E3779B97F4A7C15UL ^ seed);
                    case 2: return (((g ^ (seed & 1UL)) & 1UL) == 0) ? 0x5555555555555555UL : 0xAAAAAAAAAAAAAAAAUL;
                    default: return 0;
                }
            }
        }

        static void Fill(long[] c, long baseIdx, int pattern, ulong seed)
        {
            if (pattern == 3)
            {
                ulong x = unchecked(seed ^ ((ulong)baseIdx * 0xD1B54A32D192ED03UL)) | 1UL;
                for (int i = 0; i < c.Length; i++)
                {
                    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
                    c[i] = unchecked((long)x);
                }
                return;
            }
            for (int i = 0; i < c.Length; i++) c[i] = unchecked((long)Value(baseIdx + i, pattern, seed));
        }

        void Verify(long[] c, long baseIdx, int pattern, ulong seed, int chunkIndex)
        {
            if (pattern == 3)
            {
                ulong x = unchecked(seed ^ ((ulong)baseIdx * 0xD1B54A32D192ED03UL)) | 1UL;
                for (int i = 0; i < c.Length; i++)
                {
                    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
                    if (c[i] != unchecked((long)x)) Report(chunkIndex, i, unchecked((long)x), c[i]);
                }
                return;
            }
            for (int i = 0; i < c.Length; i++)
            {
                long e = unchecked((long)Value(baseIdx + i, pattern, seed));
                if (c[i] != e) Report(chunkIndex, i, e, c[i]);
            }
        }

        void Report(int chunk, int index, long expectedValue, long actual)
        {
            Interlocked.Increment(ref Errors);
            lock (ErrorSamples)
            {
                if (ErrorSamples.Count < 20)
                    ErrorSamples.Add("Block " + chunk + ", Wort " + index + ": erwartet 0x" + expectedValue.ToString("X16") +
                        ", gelesen 0x" + actual.ToString("X16") + " (Bits: 0x" + (expectedValue ^ actual).ToString("X16") + ")");
            }
        }
    }


    // ---------------- Simulations-Stubs (nur für Tests unter Linux) ----------------
    public static class CpuNative {
        public static string Brand = "Intel(R) Core(TM) i5-8350U CPU @ 1.70GHz";
        public static string KernelBrandString() { return Brand; }
        public static int[] Sig = new int[] { 9, 6, 0x8E, 10, 8 };
        public static int[] Signature() { return Sig; }
        public static CpuTopology Topology() { CpuTopology t = new CpuTopology(); t.Cores = 4; t.LogicalProcessors = 8; t.Packages = 1; t.L2Bytes = 1048576; t.L3Bytes = 6291456; return t; }
        public static bool FeaturePresent(int f) { return true; }
    }
    public static class Firmware {
        public static int SmbiosMajor = 3, SmbiosMinor = 0;
        static SmbiosStructure S(int type, int len, Dictionary<int, int> bytes, params string[] strings) {
            SmbiosStructure s = new SmbiosStructure(); s.Type = type; s.Handle = type; s.Data = new byte[len]; s.Data[0] = (byte)type; s.Data[1] = (byte)len;
            foreach (KeyValuePair<int, int> kv in bytes) s.Data[kv.Key] = (byte)kv.Value;
            s.Strings.AddRange(strings); return s;
        }
        static void W(Dictionary<int, int> d, int off, long v, int n) { for (int i = 0; i < n; i++) d[off + i] = (int)((v >> (8 * i)) & 0xFF); }
        public static List<SmbiosStructure> ReadSmbios() {
            List<SmbiosStructure> l = new List<SmbiosStructure>();
            Dictionary<int, int> d;
            d = new Dictionary<int, int>(); d[4] = 1; d[5] = 2; d[8] = 3; l.Add(S(0, 0x18, d, "LENOVO", "N2IET98W (1.76 )", "05/12/2024"));
            d = new Dictionary<int, int>(); d[4] = 1; d[5] = 2; d[6] = 3; d[7] = 4; l.Add(S(1, 0x1B, d, "LENOVO", "20L5S00G00", "ThinkPad T480", "PF1ABCDE"));
            d = new Dictionary<int, int>(); d[4] = 1; d[5] = 10; d[7] = 2; d[8] = 3; l.Add(S(3, 0x16, d, "LENOVO", "PF1ABCDE", "No Asset Information"));
            d = new Dictionary<int, int>(); d[4] = 1; d[7] = 2; W(d, 8, 0x000806EA, 4); W(d, 12, 0xBFEBFBFF, 4); d[0x10] = 3; W(d, 0x14, 3600, 2); d[0x23] = 4; d[0x25] = 8;
            l.Add(S(4, 0x30, d, "U3E1", "Intel(R) Corporation", "Intel(R) Core(TM) i5-8350U CPU @ 1.70GHz"));
            d = new Dictionary<int, int>(); d[5] = 3; W(d, 0x0D, 2, 2); l.Add(S(16, 0x17, d));
            for (int i = 0; i < 2; i++) {
                d = new Dictionary<int, int>(); W(d, 0x0C, 8192, 2); d[0x0E] = 0x0D; d[0x10] = 1; d[0x11] = 2; d[0x12] = 0x1A; W(d, 0x15, 2400, 2); d[0x17] = 3; d[0x1A] = 4; W(d, 0x20, 2400, 2);
                l.Add(S(17, 0x28, d, "ChannelA-DIMM" + i, "BANK " + i, "Samsung", "M471A1K43CB1-CTD"));
            }
            d = new Dictionary<int, int>(); d[4] = 1; d[5] = 2; d[8] = 3; W(d, 0x0A, 5700, 2); W(d, 0x0C, 11400, 2); d[0x15] = 10; W(d, 0x12, ((2018 - 1980) << 9) | (3 << 5) | 15, 2);
            l.Add(S(22, 0x1A, d, "Front", "SMP", "01AV489"));
            return l;
        }
        public static int FirmwareType() { return 2; }
        public static bool HasAcpiTable(string s) { return true; }
    }
    public static class DiskIo {
        public static bool NvmeEnabled = true;
        static byte[] U128(double v) { byte[] b = new byte[16]; ulong u = (ulong)v; Array.Copy(BitConverter.GetBytes(u), b, 8); return b; }
        public static NvmeHealthInfo NvmeHealth(int disk, out string error) {
            error = null; if (disk != 0 || !NvmeEnabled) { error = "kein NVMe"; return null; }
            byte[] d = new byte[512]; d[0] = 0; d[1] = (byte)(310 & 0xFF); d[2] = (byte)(310 >> 8); d[3] = 100; d[4] = 10; d[5] = 12;
            Array.Copy(U128(25000000), 0, d, 32, 16); Array.Copy(U128(19000000), 0, d, 48, 16); Array.Copy(U128(1500), 0, d, 112, 16);
            Array.Copy(U128(3200), 0, d, 128, 16); Array.Copy(U128(85), 0, d, 144, 16); Array.Copy(U128(0), 0, d, 160, 16); Array.Copy(U128(14), 0, d, 176, 16);
            return NvmeHealthInfo.Parse(d);
        }
        public static NvmeIdentifyInfo NvmeIdentify(int disk, out string error) {
            error = null; byte[] d = new byte[4096]; d[0] = 0x4B; d[1] = 0x1E; d[2] = 0x4B; d[3] = 0x1E;
            byte[] m = System.Text.Encoding.ASCII.GetBytes("Samsung SSD 980 PRO 1TB                 "); Array.Copy(m, 0, d, 24, 40);
            byte[] sn = System.Text.Encoding.ASCII.GetBytes("8888888888          "); Array.Copy(sn, 0, d, 4, 20);
            byte[] fw = System.Text.Encoding.ASCII.GetBytes("SN11929 "); Array.Copy(fw, 0, d, 64, 8);
            byte[] cap = U128(1000204886016.0); Array.Copy(cap, 0, d, 280, 16);
            return NvmeIdentifyInfo.Parse(d);
        }
    }
    public static class SystemState {
        public static void KeepAwake(bool on) { }
        public static ulong[] MemoryStatus() { return new ulong[] { 16UL << 30, 2600UL << 20 }; }
        public static ulong InstalledMemoryKB() { return 16UL << 20; }
    }
    public class DiskReadScan {
        public int DiskNumber; public long DiskBytes = 1000204886016; public long PlannedBytes = 1000204886016; public long BytesRead = 1000204886016; public int ReadErrors = 0;
        public double CurrentMBps = 2900; public double MaxBlockMs = 35; public int SlowBlocks = 0; public bool Aborted; public string AbortReason = ""; public volatile bool Done; public string Error;
        public long SegmentBytes = 268435456; public int Stride = 1; public List<long> ErrorOffsets = new List<long>(); public List<double> SegmentMBps = new List<double>(); public List<long> SegmentOffsets = new List<long>();
        public double ElapsedSeconds { get { return 340; } }
        public void Start(int disk, int stride, int max) { DiskNumber = disk; Random r = new Random(1); for (int i = 0; i < 300; i++) { SegmentMBps.Add(i == 120 ? 40 : 2800 + r.Next(-200, 200)); SegmentOffsets.Add(i * SegmentBytes); } Done = true; }
        public void Cancel() { } public void Wait(int ms) { }
    }
    public class DiskReadBenchmark {
        public int DiskNumber; public long DiskBytes; public double SeqReadMBps = 2950, RandReadIops = 14200, RandReadMBps = 55.5, RandReadAvgLatencyMs = 0.07, RandReadMaxLatencyMs = 4.2;
        public volatile string Phase = "fertig"; public double Progress = 1; public volatile bool Done; public string Error;
        public void Start(int d, int s, int r) { Done = true; } public void Cancel() { } public void Wait(int ms) { }
    }
    public static class PowerWaitDialog {
        public static bool IsOnline() { return true; } public static int BatteryPercent() { return 80; }
        public static bool WaitFor(string t, string m, bool o) { return true; }
    }
    public static class Ask {
        public static int NextChoice = 0;
        public static AskResult Choice(string t, string q, string[] o, bool c) { AskResult r = new AskResult(); r.Cancelled = false; r.Choice = NextChoice; r.ChoiceText = o[NextChoice]; return r; }
        public static AskResult Multi(string t, string q, string[] o, bool c) { AskResult r = new AskResult(); r.Cancelled = false; r.Checked = new bool[o.Length]; r.Checked[0] = true; if (o.Length > 4) { r.Checked[4] = true; r.CheckedTexts.Add(o[4]); } r.Comment = "leichte Lichthöfe unten links"; return r; }
        public static bool Info(string t, string m, string ok, string c) { return true; }
        public static string Input(string t, string p, string pre) { return pre; }
    }
    public class FakeForm { public InteractiveResult Result = new InteractiveResult(); public FakeForm() { Result.Verdict = "OK"; Result.Details.Add("simuliert"); } public object ShowDialog() { return null; } public void Dispose() { } }
    public class KeyboardTestForm : FakeForm { public KeyboardTestForm() { Result.Verdict = "Problem"; Result.Problems.Add("Taste Ö reagiert nicht"); } }
    public class TouchpadTestForm : FakeForm { } public class UsbTestForm : FakeForm { } public class SpeakerTestForm : FakeForm { }
    public class MicTestForm : FakeForm { public MicTestForm(string p) { Result.Details.Add("Aufnahmepegel: Spitze -12,0 dBFS"); } }
    public class ExternalDisplayForm : FakeForm { } public class PixelTestForm : FakeForm { }
    public class ChecklistDialog : FakeForm { public ChecklistDialog(string t, string i, ChecklistItem[] items) { for (int k = 0; k < items.Length; k++) items[k].State = (k == 4) ? 1 : (k < 10 ? 0 : 2); items[4].Comment = "Scharnier links knackt"; } }
}
