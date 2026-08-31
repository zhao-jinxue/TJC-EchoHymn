$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ScrInfo {
  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint param, ref RECT rect, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$work = New-Object ScrInfo+RECT
[ScrInfo]::SystemParametersInfo(0x0030, 0, [ref]$work, 0) | Out-Null
Write-Host "WORKAREA L=$($work.L) T=$($work.T) R=$($work.R) B=$($work.B) W=$($work.R-$work.L) H=$($work.B-$work.T)"

$exe = 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\echo_hymn.exe'
$p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
Start-Sleep -Seconds 8
$hwnd = $p.MainWindowHandle
$r = New-Object ScrInfo+RECT
[ScrInfo]::GetWindowRect($hwnd, [ref]$r) | Out-Null
Write-Host "WINDOW L=$($r.L) T=$($r.T) R=$($r.R) B=$($r.B) W=$($r.R-$r.L) H=$($r.B-$r.T)"
Get-Content 'e:\EchoHymn\hymn_app\build\windows\x64\runner\Release\state.json' | Select-String 'fontSizeLevel|showLeft'
Stop-Process -Id $p.Id -Force
