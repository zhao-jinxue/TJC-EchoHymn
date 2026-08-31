$ErrorActionPreference = 'Stop'
# 用法: _click_font.ps1 <levelIndex: 0=默认 1=中号 2=大号 3=最大> <outPng>
$exe = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\echo_hymn.exe'
$level = [int]$args[0]
if ($level -lt 0 -or $level -gt 3) { $level = 2 }
$out = $args[1]
if (-not $out) { $out = 'e:\EchoHymn\docs\v150_font.png' }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32Font {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hInsert, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
Start-Sleep -Seconds 4
$hwnd = $p.MainWindowHandle
Write-Host "HWND=$hwnd"

# 置顶并移到固定位置
[W32Font]::SetWindowPos($hwnd, [IntPtr]::Zero, 60, 60, 850, 890, 0x0040) | Out-Null
[W32Font]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Seconds 2

# 获取客户区原点（屏幕坐标）
$r = New-Object W32Font+RECT
[W32Font]::GetClientRect($hwnd, [ref]$r) | Out-Null
$pt = New-Object W32Font+POINT
[W32Font]::ClientToScreen($hwnd, [ref]$pt) | Out-Null
$cx = $pt.X; $cy = $pt.Y
Write-Host "CLIENT_ORIGIN=($cx,$cy) W=$($r.R-$r.L) H=$($r.B-$r.T)"

function Click($x, $y) {
  [W32Font]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 200
  [W32Font]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # LEFTDOWN
  [W32Font]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # LEFTUP
  Start-Sleep -Milliseconds 400
}

# 字号按钮在客户区右侧按钮组：右起 close(42) max(42) min(42) help(42) font(42) palette(42)
# 客户区宽 = 850 → font 按钮中心 x ≈ 850-4*42-21 = 661
$btnX = $cx + 661
$btnY = $cy + 15
Write-Host "CLICK font button at ($btnX,$btnY)"
Click $btnX $btnY
Start-Sleep -Seconds 1

# 点击菜单项：按钮下方，每项高约36。level 0 默认 / 1 中号 / 2 大号 / 3 最大
$itemY = $cy + 40 + $level * 38
Write-Host "CLICK menu item level=$level at ($btnX,$itemY)"
Click $btnX $itemY
Start-Sleep -Seconds 2

# 截图
$bmp = New-Object System.Drawing.Bitmap 850, 890
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [W32Font]::PrintWindow($hwnd, $dc, 2)
$g.ReleaseHdc($dc)
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "CAPTURED=$ok $out"

# 读取 state.json 确认持久化
$state = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\state.json'
if (Test-Path $state) { Write-Host '=== state.json ==='; Get-Content $state }
Stop-Process -Id $p.Id -Force
