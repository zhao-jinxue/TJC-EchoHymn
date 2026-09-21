Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int W, int H, bool R);
}
"@
$p = Get-Process echo_hymn -ErrorAction Stop
[Win32]::ShowWindow($p.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
[Win32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
[Win32]::MoveWindow($p.MainWindowHandle, 0, 0, 1280, 860, $true) | Out-Null
Start-Sleep -Seconds 2
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save('e:\EchoHymn\tools\_shot_now.png')
$g.Dispose(); $bmp.Dispose()
Write-Output 'shot ok'