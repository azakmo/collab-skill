# Windows desktop notification (toast) for the collab pipeline; clicking it opens the console.
#   & "$env:COLLAB_HOME\bin\notify.ps1" -Title '...' [-Message '...'] [-Url http://localhost:8790/]
# Off: env COLLAB_NOTIFY=0 or roster "notify": false. Never fails the caller: any error is only printed.
# pwsh 7 has no WinRT projection, so the toast is shown by Windows PowerShell 5.1 (built in, nothing to install),
# under PowerShell's registered app id.
param(
    [Parameter(Mandatory)][string]$Title,
    [string]$Message = '',
    [string]$Url = 'http://localhost:8790/',
    [switch]$Wait   # tests: wait for the helper and report its exit code
)
try {
    . (Join-Path $PSScriptRoot 'tools.ps1')
    if ($env:COLLAB_NOTIFY -eq '0') { return }
    try { if ((Get-Roster).notify -eq $false) { return } } catch {}
    $x = { param($s) [Security.SecurityElement]::Escape($s) }
    $xml = "<toast activationType=`"protocol`" launch=`"$(& $x $Url)`"><visual><binding template=`"ToastGeneric`">" +
        "<text>$(& $x $Title)</text><text>$(& $x $Message)</text></binding></visual></toast>"
    $ps = @"
`$ErrorActionPreference = 'Stop'
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
`$d = New-Object Windows.Data.Xml.Dom.XmlDocument
`$d.LoadXml('$($xml -replace "'", "''")')
`$n = New-Object Windows.UI.Notifications.ToastNotification `$d
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show(`$n)
"@
    # -EncodedCommand (UTF-16) keeps Chinese text intact regardless of the console code page.
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $enc -WindowStyle Hidden -PassThru
    if ($Wait) { $p.WaitForExit(); "notify exit=$($p.ExitCode)" }
} catch { Write-Host "  notify failed: $($_.Exception.Message)" }
