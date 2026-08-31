$ErrorActionPreference = 'Stop'
$exe = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\echo_hymn.exe'
$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
Start-Sleep -Seconds 5
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32Rect {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
}
"@
$hwnd = $p.MainWindowHandle
$r = New-Object W32Rect+R
[W32Rect]::GetWindowRect($hwnd, [ref]$r) | Out-Null
Write-Host "WINDOW_RECT L=$($r.L) T=$($r.T) R=$($r.Rt) B=$($r.B) W=$($r.Rt-$r.L) H=$($r.B-$r.T)"
Get-Content 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\state.json' | Select-String 'fontSizeLevel|showLeft'
Stop-Process -Id $p.Id -Force
