$ErrorActionPreference = 'Stop'
$exe = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\echo_hymn.exe'
$out = $args[0]
if (-not $out) { $out = 'e:\EchoHymn\docs\v150_default.png' }

$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
Start-Sleep -Seconds 4

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32Cap {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hInsert, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
"@

$hwnd = $p.MainWindowHandle
Write-Host "HWND=$hwnd"
[W32Cap]::SetWindowPos($hwnd, [IntPtr]::Zero, 60, 60, 850, 890, 0x0040) | Out-Null
[W32Cap]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Seconds 2
$bmp = New-Object System.Drawing.Bitmap 850, 890
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [W32Cap]::PrintWindow($hwnd, $dc, 2)
$g.ReleaseHdc($dc)
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "CAPTURED=$ok $out"
Stop-Process -Id $p.Id -Force
