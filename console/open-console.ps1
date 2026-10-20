# Desktop launcher for the collab console.
# If the console is already listening on 8790, just open the browser;
# otherwise start console.ps1 in this (minimized) window. Close the window to stop it.
$port = 8790
$up = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($up) {
    Start-Process "http://localhost:$port/"
    exit
}
$host.UI.RawUI.WindowTitle = "Collab Console :$port (close this window to stop)"
& "$PSScriptRoot\console.ps1" -Port $port
