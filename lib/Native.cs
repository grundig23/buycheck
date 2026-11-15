// BuyCheck – Native Windows-Zugriffe (P/Invoke)
// Wird von BuyCheck.ps1 per Add-Type kompiliert. Bewusst C# 5 (Windows PowerShell 5.1 / .NET Framework 4.x).
// Enthält nur lesende Zugriffe auf Systeminformationen (keine Schreibzugriffe auf Datenträger).

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace BuyCheck
{
    internal static class NativeMethods
    {
        public const uint GENERIC_READ = 0x80000000;
        public const uint GENERIC_WRITE = 0x40000000;
        public const uint FILE_SHARE_READ = 0x00000001;
        public const uint FILE_SHARE_WRITE = 0x00000002;
        public const uint CREATE_ALWAYS = 2;
        public const uint OPEN_EXISTING = 3;
        public const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        public const uint FILE_FLAG_WRITE_THROUGH = 0x80000000;
        public const uint FILE_FLAG_NO_BUFFERING = 0x20000000;
        public const uint FILE_FLAG_RANDOM_ACCESS = 0x10000000;
        public const uint FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;
        public const uint MEM_COMMIT = 0x00001000;
        public const uint MEM_RESERVE = 0x00002000;
        public const uint MEM_RELEASE = 0x00008000;
        public const uint PAGE_READWRITE = 0x04;
        public const uint FILE_BEGIN = 0;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
            IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool DeviceIoControl(SafeFileHandle hDevice, uint dwIoControlCode, byte[] lpInBuffer,
            int nInBufferSize, byte[] lpOutBuffer, int nOutBufferSize, out int lpBytesReturned, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool ReadFile(SafeFileHandle hFile, IntPtr lpBuffer, int nNumberOfBytesToRead,
            out int lpNumberOfBytesRead, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool WriteFile(SafeFileHandle hFile, IntPtr lpBuffer, int nNumberOfBytesToWrite,
            out int lpNumberOfBytesWritten, IntPtr lpOverlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetFilePointerEx(SafeFileHandle hFile, long liDistanceToMove, out long lpNewFilePointer, uint dwMoveMethod);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr VirtualAlloc(IntPtr lpAddress, UIntPtr dwSize, uint flAllocationType, uint flProtect);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool VirtualFree(IntPtr lpAddress, UIntPtr dwSize, uint dwFreeType);

        [StructLayout(LayoutKind.Sequential)]
        public struct SYSTEM_INFO
        {
            public ushort wProcessorArchitecture;
            public ushort wReserved;
            public uint dwPageSize;
            public IntPtr lpMinimumApplicationAddress;
            public IntPtr lpMaximumApplicationAddress;
            public UIntPtr dwActiveProcessorMask;
            public uint dwNumberOfProcessors;
            public uint dwProcessorType;
            public uint dwAllocationGranularity;
            public ushort wProcessorLevel;
            public ushort wProcessorRevision;
        }

        [DllImport("kernel32.dll")]
        public static extern void GetNativeSystemInfo(out SYSTEM_INFO lpSystemInfo);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetLogicalProcessorInformation(IntPtr buffer, ref uint returnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint GetSystemFirmwareTable(uint firmwareTableProviderSignature, uint firmwareTableID,
            byte[] pFirmwareTableBuffer, uint bufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetFirmwareType(out int firmwareType);

        [DllImport("ntdll.dll")]
        public static extern int NtQuerySystemInformation(int systemInformationClass, byte[] systemInformation,
            int systemInformationLength, out int returnLength);

        [DllImport("kernel32.dll")]
        public static extern uint SetThreadExecutionState(uint esFlags);

        [DllImport("kernel32.dll")]
        public static extern bool IsProcessorFeaturePresent(int processorFeature);

        [StructLayout(LayoutKind.Sequential)]
        public struct MEMORYSTATUSEX
        {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetPhysicallyInstalledSystemMemory(out ulong totalMemoryInKilobytes);
    }

    // ------------------------------------------------------------------ Hilfsfunktionen
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

    // ------------------------------------------------------------------ Datenträger (nur lesend)
    public static class DiskIo
    {
        public const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
        public const uint IOCTL_DISK_GET_LENGTH_INFO = 0x0007405C;
        public const uint IOCTL_DISK_GET_DRIVE_GEOMETRY_EX = 0x000700A0;

        public const int StorageAdapterProtocolSpecificProperty = 49;
        public const int StorageDeviceProtocolSpecificProperty = 50;
        public const int ProtocolTypeNvme = 3;
        public const int NVMeDataTypeIdentify = 1;
        public const int NVMeDataTypeLogPage = 2;
        public const int NVME_IDENTIFY_CNS_CONTROLLER = 1;
        public const int NVME_LOG_PAGE_ERROR_INFO = 0x01;
        public const int NVME_LOG_PAGE_HEALTH_INFO = 0x02;

        public static string DevicePath(int diskNumber) { return @"\\.\PhysicalDrive" + diskNumber; }

        // Öffnet einen Datenträger. access: 0 = nur Abfragen, sonst GENERIC_READ (+WRITE nur für Abfrage-IOCTLs, die es verlangen).
        public static SafeFileHandle Open(int diskNumber, uint access, uint flags)
        {
            string path = DevicePath(diskNumber);
            SafeFileHandle h = NativeMethods.CreateFileW(path, access,
                NativeMethods.FILE_SHARE_READ | NativeMethods.FILE_SHARE_WRITE, IntPtr.Zero,
                NativeMethods.OPEN_EXISTING, flags, IntPtr.Zero);
            if (h.IsInvalid)
            {
                int err = Marshal.GetLastWin32Error();
                h.Dispose();
                throw new Win32Exception(err, "Datenträger " + path + " lässt sich nicht öffnen (Fehler " + err + ")");
            }
            return h;
        }

        // Zugriffsstufen für reine Abfragen (IOCTL_STORAGE_QUERY_PROPERTY ist eine Leseabfrage):
        // zuerst nur lesend, dann ganz ohne Rechte. Lese-/Schreibrecht nur als letzter Versuch, weil manche
        // Treiber es für die Abfrage verlangen – geschrieben wird dabei NIE etwas.
        static readonly uint[] QueryAccessLevels = new uint[] {
            NativeMethods.GENERIC_READ, 0, NativeMethods.GENERIC_READ | NativeMethods.GENERIC_WRITE };

        public static SafeFileHandle OpenForQuery(int diskNumber)
        {
            Exception last = null;
            foreach (uint a in QueryAccessLevels)
            {
                try { return Open(diskNumber, a, 0); }
                catch (Exception ex) { last = ex; }
            }
            throw last;
        }

        public static long GetLength(SafeFileHandle h)
        {
            byte[] o = new byte[8];
            int r;
            if (!NativeMethods.DeviceIoControl(h, IOCTL_DISK_GET_LENGTH_INFO, null, 0, o, o.Length, out r, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Größe des Datenträgers nicht ermittelbar");
            return BitConverter.ToInt64(o, 0);
        }

        public static int GetBytesPerSector(SafeFileHandle h)
        {
            byte[] o = new byte[256];
            int r;
            if (!NativeMethods.DeviceIoControl(h, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, null, 0, o, o.Length, out r, IntPtr.Zero))
                return 512;
            int bps = BitConverter.ToInt32(o, 20);
            return (bps >= 512 && bps <= 65536) ? bps : 512;
        }

        public static long GetDiskLength(int diskNumber)
        {
            using (SafeFileHandle h = Open(diskNumber, NativeMethods.GENERIC_READ, 0)) { return GetLength(h); }
        }

        // NVMe-Daten über den Windows-Standardtreiber (stornvme) abfragen – reine Leseabfrage
        // (Identify / Get Log Page). Rückgabe: Nutzdaten oder null (Fehlertext in error).
        public static byte[] QueryNvme(int diskNumber, int propertyId, int dataType, int requestValue, int requestSubValue,
            int dataLength, out string error)
        {
            error = null;
            foreach (uint access in QueryAccessLevels)
            {
                bool retry;
                byte[] result = QueryNvmeOnce(diskNumber, access, propertyId, dataType, requestValue, requestSubValue,
                    dataLength, out error, out retry);
                if (result != null || !retry) return result;
            }
            return null;
        }

        static byte[] QueryNvmeOnce(int diskNumber, uint access, int propertyId, int dataType, int requestValue,
            int requestSubValue, int dataLength, out string error, out bool retryWithOtherAccess)
        {
            error = null;
            retryWithOtherAccess = false;
            SafeFileHandle h = null;
            try
            {
                try { h = Open(diskNumber, access, 0); }
                catch (Exception ex) { error = ex.Message; retryWithOtherAccess = true; return null; }
                const int specOffset = 8;      // STORAGE_PROPERTY_QUERY: PropertyId(4) + QueryType(4)
                const int specSize = 40;       // STORAGE_PROTOCOL_SPECIFIC_DATA
                byte[] buf = new byte[specOffset + specSize + dataLength];
                WriteInt(buf, 0, propertyId);
                WriteInt(buf, 4, 0);                       // PropertyStandardQuery
                WriteInt(buf, specOffset + 0, ProtocolTypeNvme);
                WriteInt(buf, specOffset + 4, dataType);
                WriteInt(buf, specOffset + 8, requestValue);
                WriteInt(buf, specOffset + 12, requestSubValue);
                WriteInt(buf, specOffset + 16, specSize); // ProtocolDataOffset (relativ zur Struktur)
                WriteInt(buf, specOffset + 20, dataLength);
                int ret;
                if (!NativeMethods.DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, buf, buf.Length, buf, buf.Length, out ret, IntPtr.Zero))
                {
                    int err = Marshal.GetLastWin32Error();
                    error = "Abfrage abgelehnt (Windows-Fehler " + err + ": " + new Win32Exception(err).Message + ")";
                    retryWithOtherAccess = (err == 5); // ERROR_ACCESS_DENIED
                    return null;
                }
                // Antwort: STORAGE_PROTOCOL_DATA_DESCRIPTOR = Version(4) Size(4) STORAGE_PROTOCOL_SPECIFIC_DATA(40)
                int version = BitConverter.ToInt32(buf, 0);
                int size = BitConverter.ToInt32(buf, 4);
                int dataOffset = BitConverter.ToInt32(buf, 8 + 16);
                int dataLen = BitConverter.ToInt32(buf, 8 + 20);
                if (version != 48 || size != 48)
                {
                    error = "Unerwartete Antwortstruktur (Version " + version + ", Größe " + size + ")";
                    return null;
                }
                if (dataOffset < specSize || dataLen <= 0 || 8 + dataOffset + dataLen > buf.Length)
                {
                    error = "Ungültiger Datenbereich in der Antwort";
                    return null;
                }
                byte[] data = new byte[dataLen];
                Buffer.BlockCopy(buf, 8 + dataOffset, data, 0, dataLen);
                return data;
            }
            catch (Exception ex)
            {
                error = ex.Message;
                return null;
            }
            finally
            {
                if (h != null) h.Dispose();
            }
        }

        public static NvmeIdentifyInfo NvmeIdentify(int diskNumber, out string error)
        {
            byte[] d = QueryNvme(diskNumber, StorageAdapterProtocolSpecificProperty, NVMeDataTypeIdentify,
                NVME_IDENTIFY_CNS_CONTROLLER, 0, 4096, out error);
            if (d == null || d.Length < 512) return null;
            return NvmeIdentifyInfo.Parse(d);
        }

        public static NvmeHealthInfo NvmeHealth(int diskNumber, out string error)
        {
            string e1, e2;
            byte[] d = QueryNvme(diskNumber, StorageDeviceProtocolSpecificProperty, NVMeDataTypeLogPage,
                NVME_LOG_PAGE_HEALTH_INFO, 0, 512, out e1);
            if (d == null)
                d = QueryNvme(diskNumber, StorageAdapterProtocolSpecificProperty, NVMeDataTypeLogPage,
                    NVME_LOG_PAGE_HEALTH_INFO, 0, 512, out e2);
            else e2 = null;
            if (d == null || d.Length < 232)
            {
                error = e1 ?? e2 ?? "Keine Daten";
                return null;
            }
            error = null;
            return NvmeHealthInfo.Parse(d);
        }

        static void WriteInt(byte[] b, int o, int v)
        {
            b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24);
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

    // ------------------------------------------------------------------ Prozessor
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

    public static class CpuNative
    {
        // Name direkt vom Prozessor (CPUID über den Windows-Kernel/HAL) – unabhängig von der Registry.
        public static string KernelBrandString()
        {
            try
            {
                byte[] buf = new byte[256];
                int ret;
                int status = NativeMethods.NtQuerySystemInformation(105, buf, buf.Length, out ret); // SystemProcessorBrandString
                if (status != 0) return null;
                int len = (ret > 0 && ret <= buf.Length) ? ret : buf.Length;
                string s = Encoding.ASCII.GetString(buf, 0, len);
                int z = s.IndexOf('\0');
                if (z >= 0) s = s.Substring(0, z);
                s = s.Trim();
                while (s.Contains("  ")) s = s.Replace("  ", " ");
                return s;
            }
            catch { return null; }
        }

        // [Architektur, Familie, Modell, Stepping, Anzahl logischer Prozessoren] aus dem Kernel (GetNativeSystemInfo).
        public static int[] Signature()
        {
            NativeMethods.SYSTEM_INFO si;
            NativeMethods.GetNativeSystemInfo(out si);
            return new int[] { si.wProcessorArchitecture, si.wProcessorLevel, (si.wProcessorRevision >> 8) & 0xFF,
                si.wProcessorRevision & 0xFF, (int)si.dwNumberOfProcessors };
        }

        public static CpuTopology Topology()
        {
            uint len = 0;
            NativeMethods.GetLogicalProcessorInformation(IntPtr.Zero, ref len);
            if (len == 0) return null;
            IntPtr buf = Marshal.AllocHGlobal((int)len);
            try
            {
                if (!NativeMethods.GetLogicalProcessorInformation(buf, ref len)) return null;
                int entrySize = IntPtr.Size == 8 ? 32 : 24;
                int unionOffset = IntPtr.Size == 8 ? 16 : 8;
                CpuTopology t = new CpuTopology();
                for (int off = 0; off + entrySize <= (int)len; off += entrySize)
                {
                    ulong mask = IntPtr.Size == 8 ? (ulong)Marshal.ReadInt64(buf, off) : (ulong)(uint)Marshal.ReadInt32(buf, off);
                    int rel = Marshal.ReadInt32(buf, off + IntPtr.Size);
                    if (rel == 0)
                    {
                        t.Cores++;
                        t.LogicalProcessors += PopCount(mask);
                    }
                    else if (rel == 3)
                    {
                        t.Packages++;
                    }
                    else if (rel == 2)
                    {
                        int level = Marshal.ReadByte(buf, off + unionOffset);
                        long size = (uint)Marshal.ReadInt32(buf, off + unionOffset + 4);
                        int type = Marshal.ReadInt32(buf, off + unionOffset + 8);
                        if (level == 1) { if (type == 1) t.L1InstructionBytes += size; else t.L1DataBytes += size; }
                        else if (level == 2) t.L2Bytes += size;
                        else if (level == 3) { t.L3Bytes += size; t.L3Instances++; }
                    }
                }
                return t;
            }
            finally { Marshal.FreeHGlobal(buf); }
        }

        public static bool FeaturePresent(int feature)
        {
            try { return NativeMethods.IsProcessorFeaturePresent(feature); } catch { return false; }
        }

        static int PopCount(ulong v)
        {
            int c = 0;
            while (v != 0) { v &= v - 1; c++; }
            return c;
        }
    }

    // ------------------------------------------------------------------ Firmware (SMBIOS, Firmware-Typ)
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

    public static class Firmware
    {
        public static int SmbiosMajor;
        public static int SmbiosMinor;

        public static List<SmbiosStructure> ReadSmbios()
        {
            List<SmbiosStructure> list = new List<SmbiosStructure>();
            const uint RSMB = 0x52534D42;
            uint size = NativeMethods.GetSystemFirmwareTable(RSMB, 0, null, 0);
            if (size == 0) return list;
            byte[] buf = new byte[size];
            uint got = NativeMethods.GetSystemFirmwareTable(RSMB, 0, buf, size);
            if (got == 0 || got > size || got < 8) return list;
            SmbiosMajor = buf[1];
            SmbiosMinor = buf[2];
            int tableLen = BitConverter.ToInt32(buf, 4);
            int pos = 8;
            int end = (int)Math.Min((long)got, 8L + tableLen);
            while (pos + 4 <= end)
            {
                int type = buf[pos];
                int len = buf[pos + 1];
                if (len < 4 || pos + len > end) break;
                SmbiosStructure s = new SmbiosStructure();
                s.Type = type;
                s.Handle = buf[pos + 2] | (buf[pos + 3] << 8);
                s.Data = new byte[len];
                Array.Copy(buf, pos, s.Data, 0, len);
                int sp = pos + len;
                if (sp + 1 < end && buf[sp] == 0 && buf[sp + 1] == 0)
                {
                    sp += 2;
                }
                else
                {
                    while (sp < end)
                    {
                        int start = sp;
                        while (sp < end && buf[sp] != 0) sp++;
                        s.Strings.Add(Latin1(buf, start, sp - start));
                        sp++;
                        if (sp < end && buf[sp] == 0) { sp++; break; }
                    }
                }
                list.Add(s);
                pos = sp;
                if (type == 127) break;
            }
            return list;
        }

        // ISO-8859-1 ohne Codepage-Provider (funktioniert unter .NET Framework und .NET)
        static string Latin1(byte[] b, int start, int len)
        {
            char[] c = new char[len];
            for (int i = 0; i < len; i++) c[i] = (char)b[start + i];
            return new string(c);
        }

        // 1 = BIOS (Legacy), 2 = UEFI, 0 = unbekannt
        public static int FirmwareType()
        {
            try
            {
                int t;
                if (NativeMethods.GetFirmwareType(out t)) return t;
            }
            catch { }
            return 0;
        }

        public static bool HasAcpiTable(string signature)
        {
            try
            {
                if (signature == null || signature.Length != 4) return false;
                const uint ACPI = 0x41435049;
                uint id = (uint)signature[0] | ((uint)signature[1] << 8) | ((uint)signature[2] << 16) | ((uint)signature[3] << 24);
                uint size = NativeMethods.GetSystemFirmwareTable(ACPI, id, null, 0);
                return size > 0;
            }
            catch { return false; }
        }
    }

    // ------------------------------------------------------------------ Bildschirm-Identifikation (EDID)
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

    // ------------------------------------------------------------------ Sonstiges
    public static class SystemState
    {
        const uint ES_CONTINUOUS = 0x80000000;
        const uint ES_SYSTEM_REQUIRED = 0x00000001;
        const uint ES_DISPLAY_REQUIRED = 0x00000002;

        // Verhindert Standby/Bildschirmabschaltung während der Tests.
        public static void KeepAwake(bool on)
        {
            try
            {
                if (on) NativeMethods.SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
                else NativeMethods.SetThreadExecutionState(ES_CONTINUOUS);
            }
            catch { }
        }

        // [Gesamt-RAM, verfügbarer RAM] in Byte
        public static ulong[] MemoryStatus()
        {
            NativeMethods.MEMORYSTATUSEX m = new NativeMethods.MEMORYSTATUSEX();
            m.dwLength = (uint)Marshal.SizeOf(typeof(NativeMethods.MEMORYSTATUSEX));
            if (!NativeMethods.GlobalMemoryStatusEx(ref m)) return new ulong[] { 0, 0 };
            return new ulong[] { m.ullTotalPhys, m.ullAvailPhys };
        }

        public static ulong InstalledMemoryKB()
        {
            try
            {
                ulong kb;
                if (NativeMethods.GetPhysicallyInstalledSystemMemory(out kb)) return kb;
            }
            catch { }
            return 0;
        }
    }
}
