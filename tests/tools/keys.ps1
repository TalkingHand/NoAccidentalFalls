# Real keyboard input for the in-game test (tests/tools/livetest.sh starts it next to `pzt live`).
# The test Lua writes Zomboid/Lua/naf_key_req.txt = "<id> <KEY,KEY,...> <ms>": the keys go down in
# that order, stay down <ms>, and come up in reverse order. Then naf_key_done.txt = "<id> <ok|error ...>".
# Keys: W A S D E LSHIFT LALT. Only the test game of this project is touched (the
# ProjectZomboid64.exe whose command line has this project's -cachedir); it is brought to the front.
param([string]$EnvDir, [int]$TimeoutSec = 1200)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NafInput {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
}
"@

$KEYS = @{
    "W" = @(0x57, 0x11); "A" = @(0x41, 0x1E); "S" = @(0x53, 0x1F); "D" = @(0x44, 0x20)
    "E" = @(0x45, 0x12); "LSHIFT" = @(0xA0, 0x2A); "LALT" = @(0xA4, 0x38)
}

$luaDir = Join-Path $EnvDir "Zomboid\Lua"
$req = Join-Path $luaDir "naf_key_req.txt"
$done = Join-Path $luaDir "naf_key_done.txt"
$cacheDir = (Join-Path $EnvDir "Zomboid")
Remove-Item $req, $done -ErrorAction SilentlyContinue

function Find-Game {
    Get-CimInstance Win32_Process -Filter "Name='ProjectZomboid64.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains("-cachedir=$cacheDir") } |
        Select-Object -First 1
}

$start = Get-Date
$seen = $false
$lastId = ""
$down = @()
# pzt may wait a long time for free memory first: the timeout only runs once the game is up
while (-not $seen -or ((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
    $game = Find-Game
    if ($game -and -not $seen) { $start = Get-Date }
    if ($game) { $seen = $true } elseif ($seen) { break }
    if ($game -and (Test-Path $req)) {
        $line = (Get-Content $req -TotalCount 1 -ErrorAction SilentlyContinue)
        if ($line) {
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -eq 3 -and $parts[0] -ne $lastId) {
                $lastId = $parts[0]
                $result = "ok"
                try {
                    $hwnd = (Get-Process -Id $game.ProcessId).MainWindowHandle
                    if ($hwnd -eq [IntPtr]::Zero) { throw "no game window" }
                    if ([NafInput]::GetForegroundWindow() -ne $hwnd) {
                        # ALT tap lets a background process take the foreground (only while the game is not in front)
                        [NafInput]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
                        [NafInput]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
                        [void][NafInput]::ShowWindow($hwnd, 9)
                        [void][NafInput]::SetForegroundWindow($hwnd)
                        Start-Sleep -Milliseconds 300
                    }
                    if ([NafInput]::GetForegroundWindow() -ne $hwnd) { throw "game window not in front" }
                    $names = $parts[1] -split ','
                    foreach ($n in $names) { if (-not $KEYS.ContainsKey($n)) { throw "unknown key $n" } }
                    foreach ($n in $names) {
                        $k = $KEYS[$n]
                        [NafInput]::keybd_event([byte]$k[0], [byte]$k[1], 0, [UIntPtr]::Zero)
                        $down += $n
                        Start-Sleep -Milliseconds 30
                    }
                    Start-Sleep -Milliseconds ([int]$parts[2])
                } catch {
                    $result = "error " + $_.Exception.Message
                } finally {
                    for ($i = $down.Count - 1; $i -ge 0; $i--) {
                        $k = $KEYS[$down[$i]]
                        [NafInput]::keybd_event([byte]$k[0], [byte]$k[1], 2, [UIntPtr]::Zero)
                    }
                    $down = @()
                }
                # the game may be reading the file right now: retry
                for ($try = 0; $try -lt 20; $try++) {
                    try { Set-Content -Path $done -Value "$lastId $result" -Encoding ascii -ErrorAction Stop; break }
                    catch { Start-Sleep -Milliseconds 50 }
                }
                Write-Output "[keys] $line -> $result"
            }
        }
    }
    Start-Sleep -Milliseconds 100
}
Write-Output "[keys] exit"
