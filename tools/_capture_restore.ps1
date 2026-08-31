$ErrorActionPreference = 'Stop'
$exe = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\echo_hymn.exe'
$out = 'e:\EchoHymn\docs\v150_restore.png'

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32Restore {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hInsert, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
}
"@

$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
Start-Sleep -Seconds 5
$hwnd = $p.MainWindowHandle
[W32Restore]::SetWindowPos($hwnd, [IntPtr]::Zero, 60, 60, 850, 890, 0x0040) | Out-Null
[W32Restore]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Seconds 2
$bmp = New-Object System.Drawing.Bitmap 850, 890
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [W32Restore]::PrintWindow($hwnd, $dc, 2)
$g.ReleaseHdc($dc)
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "CAPTURED=$ok $out"

$logDir = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\logs'
if (Test-Path $logDir) {
  $f = Get-ChildItem $logDir | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Write-Host "=== LOG: $($f.Name) (tail) ==="
  Get-Content $f.FullName -Tail 8
}
Stop-Process -Id $p.Id -Force
