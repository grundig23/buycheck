// BuyCheck – Belastungs- und Messroutinen (laufen in Hintergrund-Threads, PowerShell fragt den Fortschritt ab)
// C# 5 / .NET Framework 4.x kompatibel.
//
// GRUNDSATZ: Der Laptop gehört (noch) nicht uns. Deshalb:
//  - Datenträger werden ausschließlich LESEND geöffnet (GENERIC_READ). Es wird nie etwas auf den
//    internen Datenträger geschrieben – keine Testdateien, keine Schreibtests.
//  - Der RAM-Test nutzt nur freien Arbeitsspeicher innerhalb dieses Prozesses.
//  - Der CPU-Test erzeugt nur Rechenlast; PowerShell überwacht Temperatur/Takt und bricht bei Bedarf ab.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace BuyCheck
{
    // Seitenausgerichteter Puffer (nötig für ungepufferte Datenträgerzugriffe)
    public sealed class AlignedBuffer : IDisposable
    {
        public IntPtr Ptr;
        public int Size;

        public AlignedBuffer(int size)
        {
            Ptr = NativeMethods.VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)size,
                NativeMethods.MEM_COMMIT | NativeMethods.MEM_RESERVE, NativeMethods.PAGE_READWRITE);
            if (Ptr == IntPtr.Zero) throw new OutOfMemoryException("Puffer konnte nicht reserviert werden");
            Size = size;
        }

        public void Dispose()
        {
            if (Ptr != IntPtr.Zero)
            {
                NativeMethods.VirtualFree(Ptr, UIntPtr.Zero, NativeMethods.MEM_RELEASE);
                Ptr = IntPtr.Zero;
            }
        }
    }

    // ================================================================== CPU-Belastung mit Rechenprüfung
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

    // ================================================================== Oberflächen-Lesetest (NUR LESEND)
    public class DiskReadScan
    {
        public int DiskNumber;
        public long DiskBytes;
        public long PlannedBytes;
        public long BytesRead;
        public int ReadErrors;
        public double CurrentMBps;
        public double MaxBlockMs;
        public int SlowBlocks;          // Blöcke mit > 1 s Lesezeit
        public bool Aborted;
        public string AbortReason = "";
        public volatile bool Done;
        public string Error;
        public long SegmentBytes = 256L * 1024 * 1024;
        public int Stride = 1;
        public readonly List<long> ErrorOffsets = new List<long>();
        public readonly List<double> SegmentMBps = new List<double>();
        public readonly List<long> SegmentOffsets = new List<long>();
        public double ElapsedSeconds { get { return sw.Elapsed.TotalSeconds; } }

        volatile bool cancel;
        Thread worker;
        readonly Stopwatch sw = new Stopwatch();
        int maxSeconds;

        public void Start(int diskNumber, int stride, int maxSeconds)
        {
            DiskNumber = diskNumber;
            Stride = Math.Max(1, stride);
            this.maxSeconds = maxSeconds;
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Start();
        }

        public void Cancel() { AbortReason = "vom Benutzer abgebrochen"; Aborted = true; cancel = true; }
        public void Wait(int ms) { if (worker != null) worker.Join(ms); }

        void Run()
        {
            const int block = 4 * 1024 * 1024;
            SafeFileHandle h = null;
            AlignedBuffer buf = null;
            try
            {
                // Ausschließlich Lesezugriff
                h = DiskIo.Open(DiskNumber, NativeMethods.GENERIC_READ,
                    NativeMethods.FILE_FLAG_NO_BUFFERING | NativeMethods.FILE_FLAG_SEQUENTIAL_SCAN);
                DiskBytes = DiskIo.GetLength(h);
                int sector = DiskIo.GetBytesPerSector(h);
                buf = new AlignedBuffer(block);
                long segments = (DiskBytes + SegmentBytes - 1) / SegmentBytes;
                long plannedSegs = (segments + Stride - 1) / Stride;
                PlannedBytes = Math.Min(DiskBytes, plannedSegs * SegmentBytes);
                sw.Start();
                Stopwatch blockSw = new Stopwatch();
                Stopwatch speedSw = Stopwatch.StartNew();
                long speedBytes = 0;
                long dummy;
                for (long seg = 0; seg < segments && !cancel; seg += Stride)
                {
                    long segStart = seg * SegmentBytes;
                    long segEnd = Math.Min(DiskBytes, segStart + SegmentBytes);
                    Stopwatch segSw = Stopwatch.StartNew();
                    long segRead = 0;
                    long pos = segStart;
                    NativeMethods.SetFilePointerEx(h, pos, out dummy, NativeMethods.FILE_BEGIN);
                    while (pos < segEnd && !cancel)
                    {
                        int toRead = (int)Math.Min((long)block, segEnd - pos);
                        toRead = toRead / sector * sector;
                        if (toRead <= 0) break;
                        int got;
                        blockSw.Reset();
                        blockSw.Start();
                        bool ok = NativeMethods.ReadFile(h, buf.Ptr, toRead, out got, IntPtr.Zero);
                        double ms = blockSw.Elapsed.TotalMilliseconds;
                        if (!ok || got != toRead)
                        {
                            ReadErrors++;
                            lock (ErrorOffsets) { if (ErrorOffsets.Count < 200) ErrorOffsets.Add(pos); }
                            if (ReadErrors >= 50)
                            {
                                Aborted = true;
                                AbortReason = "zu viele Lesefehler (50)";
                                return;
                            }
                            pos += toRead;
                            NativeMethods.SetFilePointerEx(h, pos, out dummy, NativeMethods.FILE_BEGIN);
                            continue;
                        }
                        if (ms > MaxBlockMs) MaxBlockMs = ms;
                        if (ms > 1000) SlowBlocks++;
                        pos += got;
                        segRead += got;
                        Interlocked.Add(ref BytesRead, got);
                        speedBytes += got;
                        if (speedSw.ElapsedMilliseconds >= 1000)
                        {
                            CurrentMBps = speedBytes / 1048576.0 / speedSw.Elapsed.TotalSeconds;
                            speedBytes = 0;
                            speedSw.Reset();
                            speedSw.Start();
                        }
                        if (maxSeconds > 0 && sw.Elapsed.TotalSeconds > maxSeconds)
                        {
                            Aborted = true;
                            AbortReason = "Zeitlimit erreicht";
                            cancel = true;
                        }
                    }
                    double segSec = segSw.Elapsed.TotalSeconds;
                    if (segRead > 0 && segSec > 0)
                    {
                        lock (SegmentMBps)
                        {
                            SegmentMBps.Add(segRead / 1048576.0 / segSec);
                            SegmentOffsets.Add(segStart);
                        }
                    }
                }
            }
            catch (Exception ex) { Error = ex.Message; }
            finally
            {
                if (buf != null) buf.Dispose();
                if (h != null) h.Dispose();
                sw.Stop();
                Done = true;
            }
        }
    }

    // ================================================================== Lese-Geschwindigkeit (NUR LESEND, direkt vom Datenträger)
    public class DiskReadBenchmark
    {
        public int DiskNumber;
        public long DiskBytes;
        public double SeqReadMBps;
        public double RandReadIops;
        public double RandReadMBps;
        public double RandReadAvgLatencyMs;
        public double RandReadMaxLatencyMs;
        public volatile string Phase = "";
        public double Progress;
        public volatile bool Done;
        public string Error;

        volatile bool cancel;
        Thread worker;
        int seqMB;
        int randomSeconds;

        public void Start(int diskNumber, int seqMB, int randomSeconds)
        {
            DiskNumber = diskNumber;
            this.seqMB = Math.Max(256, seqMB);
            this.randomSeconds = Math.Max(3, randomSeconds);
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Start();
        }

        public void Cancel() { cancel = true; }
        public void Wait(int ms) { if (worker != null) worker.Join(ms); }

        void Run()
        {
            const int block = 4 * 1024 * 1024;
            SafeFileHandle h = null;
            AlignedBuffer buf = null;
            try
            {
                h = DiskIo.Open(DiskNumber, NativeMethods.GENERIC_READ, NativeMethods.FILE_FLAG_NO_BUFFERING);
                DiskBytes = DiskIo.GetLength(h);
                int sector = DiskIo.GetBytesPerSector(h);
                int small = Math.Max(4096, sector);
                buf = new AlignedBuffer(block);
                long dummy;

                // 1) Sequentiell lesen: drei Bereiche im vorderen Teil (dort liegen i. d. R. Windows-Dateien,
                //    leere/getrimmte Bereiche würden die Messung verfälschen).
                Phase = "Sequentielles Lesen";
                long perRegion = ((long)seqMB * 1024 * 1024 / 3) / block * block;
                double[] starts = new double[] { 0.02, 0.08, 0.15 };
                long total = 0;
                Stopwatch s = Stopwatch.StartNew();
                for (int r = 0; r < starts.Length && !cancel; r++)
                {
                    long pos = (long)(DiskBytes * starts[r]) / block * block;
                    NativeMethods.SetFilePointerEx(h, pos, out dummy, NativeMethods.FILE_BEGIN);
                    long done = 0;
                    while (done < perRegion && pos + block <= DiskBytes && !cancel)
                    {
                        int got;
                        if (!NativeMethods.ReadFile(h, buf.Ptr, block, out got, IntPtr.Zero) || got != block)
                            throw new System.IO.IOException("Lesefehler bei Offset " + pos + " (Windows-Fehler " + Marshal.GetLastWin32Error() + ")");
                        done += got;
                        pos += got;
                        total += got;
                        Progress = 0.6 * total / (perRegion * 3.0);
                    }
                }
                double sec = s.Elapsed.TotalSeconds;
                if (total > 0 && sec > 0) SeqReadMBps = total / 1048576.0 / sec;
                if (cancel) return;

                // 2) Zufällige 4K-Lesezugriffe (Warteschlangentiefe 1) in der vorderen Hälfte
                Phase = "Zufälliges Lesen (4K)";
                Random random = new Random(42);
                long range = Math.Max(small, DiskBytes / 2) / small;
                long ops = 0;
                double maxMs = 0;
                Stopwatch op = new Stopwatch();
                s = Stopwatch.StartNew();
                while (s.Elapsed.TotalSeconds < randomSeconds && !cancel)
                {
                    long off = (long)(random.NextDouble() * range) * small;
                    NativeMethods.SetFilePointerEx(h, off, out dummy, NativeMethods.FILE_BEGIN);
                    int got;
                    op.Reset();
                    op.Start();
                    if (!NativeMethods.ReadFile(h, buf.Ptr, small, out got, IntPtr.Zero) || got != small)
                        throw new System.IO.IOException("Lesefehler bei Offset " + off + " (Windows-Fehler " + Marshal.GetLastWin32Error() + ")");
                    double ms = op.Elapsed.TotalMilliseconds;
                    if (ms > maxMs) maxMs = ms;
                    ops++;
                    Progress = 0.6 + 0.4 * Math.Min(1.0, s.Elapsed.TotalSeconds / randomSeconds);
                }
                sec = s.Elapsed.TotalSeconds;
                if (ops > 0 && sec > 0)
                {
                    RandReadIops = ops / sec;
                    RandReadMBps = RandReadIops * small / 1048576.0;
                    RandReadAvgLatencyMs = sec * 1000.0 / ops;
                    RandReadMaxLatencyMs = maxMs;
                }
                Progress = 1.0;
            }
            catch (Exception ex) { Error = ex.Message; }
            finally
            {
                if (buf != null) buf.Dispose();
                if (h != null) h.Dispose();
                Done = true;
            }
        }
    }
}
