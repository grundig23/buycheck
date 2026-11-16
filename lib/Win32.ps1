# BuyCheck – Bekanntmachen der benötigten Windows-Funktionen (ohne Compiler, nur im Arbeitsspeicher)
#
# Diese Datei enthält ausschließlich die Liste der Windows-Funktionen, die BuyCheck aufruft, und erzeugt
# daraus per Reflection.Emit einen Typ im Arbeitsspeicher. Es wird nichts kompiliert und nichts gespeichert.
# Sie ist bewusst von den übrigen Programmteilen getrennt: Lässt ein Virenscanner sie nicht zu, läuft
# BuyCheck trotzdem weiter – nur ohne die direkten Hardware-Abfragen.
#
# Verwendet werden nur lesende Abfragen: Datenträger-, CPU-, Firmware-, Akku- und Konsoleninformationen.

function Add-BCPInvoke {
    param($Builder, [string]$Dll, [string]$Name, [Type]$Return, [Type[]]$Parameters, [int[]]$OutIndexes, [bool]$SetLastError)
    $attrs = [System.Reflection.MethodAttributes]'Public, Static, PinvokeImpl, HideBySig'
    $method = $Builder.DefineMethod($Name, $attrs, $Return, $Parameters)
    foreach ($i in @($OutIndexes)) { if ($i -gt 0) { [void]$method.DefineParameter($i, [System.Reflection.ParameterAttributes]::Out, $null) } }
    $dllImport = [System.Runtime.InteropServices.DllImportAttribute]
    $fields = [System.Reflection.FieldInfo[]]@($dllImport.GetField('SetLastError'), $dllImport.GetField('CallingConvention'),
        $dllImport.GetField('CharSet'), $dllImport.GetField('EntryPoint'), $dllImport.GetField('ExactSpelling'))
    $values = [object[]]@($SetLastError, [System.Runtime.InteropServices.CallingConvention]::Winapi,
        [System.Runtime.InteropServices.CharSet]::Unicode, $Name, $true)
    $ctor = $dllImport.GetConstructor([Type[]]@([string]))
    $cab = New-Object System.Reflection.Emit.CustomAttributeBuilder($ctor, [object[]]@($Dll), [System.Reflection.PropertyInfo[]]@(), [object[]]@(), $fields, $values)
    $method.SetCustomAttribute($cab)
}

function New-BCWin32Type {
    $name = New-Object System.Reflection.AssemblyName 'BuyCheckNative'
    $access = [System.Reflection.Emit.AssemblyBuilderAccess]::Run
    $define = [AppDomain].GetMethod('DefineDynamicAssembly', [Type[]]@([System.Reflection.AssemblyName], [System.Reflection.Emit.AssemblyBuilderAccess]))
    if ($define) { $asm = [AppDomain]::CurrentDomain.DefineDynamicAssembly($name, $access) }
    else { $asm = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($name, $access) }
    $module = $asm.DefineDynamicModule('BuyCheckNative')
    $tb = $module.DefineType('BuyCheck.Win32', [System.Reflection.TypeAttributes]'Public, Class, Sealed, Abstract')
    $intRef = [int].MakeByRefType()
    $longRef = [long].MakeByRefType()
    $sb = [System.Text.StringBuilder]
    # Dll, Funktion, Rückgabe, Parameter, Out-Parameter (1-basiert), SetLastError
    $defs = @(
        @('kernel32.dll', 'CreateFileW', [IntPtr], @([string], [int], [int], [IntPtr], [int], [int], [IntPtr]), @(), $true),
        @('kernel32.dll', 'CloseHandle', [bool], @([IntPtr]), @(), $true),
        @('kernel32.dll', 'DeviceIoControl', [bool], @([IntPtr], [int], [byte[]], [int], [byte[]], [int], $intRef, [IntPtr]), @(7), $true),
        @('kernel32.dll', 'ReadFile', [bool], @([IntPtr], [IntPtr], [int], $intRef, [IntPtr]), @(4), $true),
        @('kernel32.dll', 'SetFilePointerEx', [bool], @([IntPtr], [long], $longRef, [int]), @(3), $true),
        @('kernel32.dll', 'GetNativeSystemInfo', [void], @([byte[]]), @(), $false),
        @('kernel32.dll', 'GetLogicalProcessorInformation', [bool], @([byte[]], $intRef), @(), $true),
        @('kernel32.dll', 'GetSystemFirmwareTable', [int], @([int], [int], [byte[]], [int]), @(), $true),
        @('kernel32.dll', 'GetFirmwareType', [bool], @($intRef), @(1), $true),
        @('kernel32.dll', 'GetFirmwareEnvironmentVariableW', [int], @([string], [string], [IntPtr], [int]), @(), $true),
        @('kernel32.dll', 'SetThreadExecutionState', [int], @([int]), @(), $false),
        @('kernel32.dll', 'IsProcessorFeaturePresent', [bool], @([int]), @(), $false),
        @('kernel32.dll', 'GlobalMemoryStatusEx', [bool], @([byte[]]), @(), $true),
        @('kernel32.dll', 'GetPhysicallyInstalledSystemMemory', [bool], @($longRef), @(1), $true),
        @('kernel32.dll', 'GetSystemPowerStatus', [bool], @([byte[]]), @(), $true),
        @('kernel32.dll', 'GetStdHandle', [IntPtr], @([int]), @(), $true),
        @('kernel32.dll', 'GetConsoleMode', [bool], @([IntPtr], $intRef), @(2), $true),
        @('kernel32.dll', 'SetConsoleMode', [bool], @([IntPtr], [int]), @(), $true),
        @('kernel32.dll', 'GetNumberOfConsoleInputEvents', [bool], @([IntPtr], $intRef), @(2), $true),
        @('kernel32.dll', 'ReadConsoleInputW', [bool], @([IntPtr], [byte[]], [int], $intRef), @(4), $true),
        @('kernel32.dll', 'FlushConsoleInputBuffer', [bool], @([IntPtr]), @(), $true),
        @('kernel32.dll', 'GetConsoleWindow', [IntPtr], @(), @(), $false),
        @('ntdll.dll', 'NtQuerySystemInformation', [int], @([int], [byte[]], [int], $intRef), @(4), $false),
        @('ntdll.dll', 'RtlCompareMemory', [UIntPtr], @([byte[]], [byte[]], [UIntPtr]), @(), $false),
        @('user32.dll', 'GetCursorPos', [bool], @([byte[]]), @(), $true),
        @('user32.dll', 'GetSystemMetrics', [int], @([int]), @(), $false),
        @('user32.dll', 'ShowWindow', [bool], @([IntPtr], [int]), @(), $false),
        @('winmm.dll', 'mciSendStringW', [int], @([string], $sb, [int], [IntPtr]), @(), $false)
    )
    foreach ($d in $defs) {
        Add-BCPInvoke -Builder $tb -Dll $d[0] -Name $d[1] -Return $d[2] -Parameters ([Type[]]@($d[3])) -OutIndexes ([int[]]@($d[4])) -SetLastError $d[5]
    }
    return $tb.CreateType()
}
