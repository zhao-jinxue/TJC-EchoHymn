$ErrorActionPreference = 'Stop'
# 用法: _click2.ps1 <clientX> <clientY> <outPng>
$exe = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\echo_hymn.exe'
$clickX = [int]$args[0]
$clickY = [int]$args[1]
$out = $args[2]
if (-not $out) { $out = 'e:\EchoHymn\docs\v150_click2.png' }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32C2 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hInsert, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
Start-Sleep -Seconds 5
$hwnd = $p.MainWindowHandle
[W32C2]::SetWindowPos($hwnd, [IntPtr]::Zero, 60, 60, 850, 890, 0x0040) | Out-Null
[W32C2]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
[W32C2]::BringWindowToTop($hwnd) | Out-Null
[W32C2]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Seconds 3

$r = New-Object W32C2+RECT
[W32C2]::GetClientRect($hwnd, [ref]$r) | Out-Null
$pt = New-Object W32C2+POINT
[W32C2]::ClientToScreen($hwnd, [ref]$pt) | Out-Null
$cx = $pt.X; $cy = $pt.Y

function Click($x, $y) {
  [W32C2]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 300
  [W32C2]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
  [W32C2]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 600
}

Write-Host "CLICK client($clickX,$clickY) -> screen($($cx+$clickX),$($cy+$clickY))"
Click ($cx + $clickX) ($cy + $clickY)
Start-Sleep -Seconds 2

$bmp = New-Object System.Drawing.Bitmap 850, 890
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [W32C2]::PrintWindow($hwnd, $dc, 2)
$g.ReleaseHdc($dc)
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "CAPTURED=$ok $out"
Stop-Process -Id $p.Id -Force
