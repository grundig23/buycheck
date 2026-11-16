# Test: P/Invoke via Reflection.Emit (ohne Compiler) gegen libc unter Linux
$asmName = New-Object System.Reflection.AssemblyName 'BCNativeTest'
$access = [System.Reflection.Emit.AssemblyBuilderAccess]::Run
$dm = [AppDomain].GetMethod('DefineDynamicAssembly', [Type[]]@([System.Reflection.AssemblyName], [System.Reflection.Emit.AssemblyBuilderAccess]))
if ($dm) { $asm = [AppDomain]::CurrentDomain.DefineDynamicAssembly($asmName, $access) } else { $asm = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($asmName, $access) }
$mod = $asm.DefineDynamicModule('BCNativeTest')
$tb = $mod.DefineType('BCTest.Native', [System.Reflection.TypeAttributes]'Public, Class, Sealed, Abstract')
function Add-P { param($Dll, $Name, $Ret, [Type[]]$Params, [int[]]$OutIdx = @(), $Conv = 'Winapi')
    $m = $tb.DefineMethod($Name, [System.Reflection.MethodAttributes]'Public, Static, PinvokeImpl, HideBySig', $Ret, $Params)
    foreach ($i in $OutIdx) { [void]$m.DefineParameter($i, [System.Reflection.ParameterAttributes]::Out, $null) }
    $dllImport = [System.Runtime.InteropServices.DllImportAttribute]
    $ctor = $dllImport.GetConstructor([Type[]]@([string]))
    $fields = [System.Reflection.FieldInfo[]]@($dllImport.GetField('SetLastError'), $dllImport.GetField('CallingConvention'), $dllImport.GetField('CharSet'), $dllImport.GetField('EntryPoint'))
    $vals = [object[]]@($true, [System.Runtime.InteropServices.CallingConvention]$Conv, [System.Runtime.InteropServices.CharSet]::Ansi, $Name)
    $cab = New-Object System.Reflection.Emit.CustomAttributeBuilder($ctor, [object[]]@($Dll), [System.Reflection.PropertyInfo[]]@(), [object[]]@(), $fields, $vals)
    $m.SetCustomAttribute($cab)
}
Add-P 'libc.so.6' 'getpid' ([int]) @()
Add-P 'libc.so.6' 'memcmp' ([int]) @([byte[]], [byte[]], [UIntPtr]) -Conv Cdecl
Add-P 'libc.so.6' 'memset' ([IntPtr]) @([byte[]], [int], [UIntPtr]) -Conv Cdecl
Add-P 'libc.so.6' 'sscanf' ([int]) @([string], [string], [int].MakeByRefType()) -OutIdx @(3) -Conv Cdecl
$t = $tb.CreateType()
"pid=" + [BCTest.Native]::getpid() + " (real $PID)"
$a = [byte[]](1,2,3,4); $b = [byte[]](1,2,3,4)
"memcmp equal: " + [BCTest.Native]::memcmp($a, $b, [UIntPtr][uint64]4)
$b[2] = 9; "memcmp diff: " + [BCTest.Native]::memcmp($a, $b, [UIntPtr][uint64]4)
$buf = New-Object byte[] 8; [void][BCTest.Native]::memset($buf, 0x41, [UIntPtr][uint64]5); "memset into byte[]: " + ($buf -join ',')
$v = 0; $n = [BCTest.Native]::sscanf('1234', '%d', [ref]$v); "sscanf out: n=$n v=$v"
"ISS.Create().LanguageMode = " + [System.Management.Automation.Runspaces.InitialSessionState]::Create().LanguageMode
$od = New-Object System.Collections.Specialized.OrderedDictionary; $od['z'] = 1; $od['a'] = 2; $od['m'] = 3
"New-Object -Property order: " + ((New-Object PSObject -Property $od).PSObject.Properties | ForEach-Object { $_.Name }) -join ','
"0x80000000 = " + 0x80000000 + " type " + (0x80000000).GetType().Name
"0xFFFFFFFF = " + 0xFFFFFFFF
