<#
.SYNOPSIS
    Download and install Windows Updates
.DESCRIPTION
    Download and install Windows Updtes using Windows Update APIs
.NOTES
    Stay spicy
.LINK
    https://learn.microsoft.com/en-us/windows/win32/wua_sdk/using-the-windows-update-agent-api
#>

[CmdletBinding()]
param (
    [switch]$IncludeOptionalUpdates,
    [switch]$NoDownload,
    [switch]$NoInstall,
    [switch]$ShowDetails,
    [bool]$Reboot
)

#region Functions
Function Get-WindowsUpdateDownloadResults{
    param(
        [Parameter(Mandatory=$true)]
        [Int]$Result
    )

    switch ($Result) {
        2 { $resultText = "Download succeeded" }
        3 { $resultText = "Download succeeded with errors" }
        4 { $resultText = "Download Failed" }
        5 { $resultText = "Download Cancelled" }
        Default { $resultText = "Unexpected ($Result)"}
    }

    return $resultText
}
Function Get-WindowsUpdateInstallResults {
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [Int]$Result
    )

    switch ($Result) {
        2 { $resultText = "Succeeded" }
        3 { $resultText = "Succeeded with errors" }
        4 { $resultText = "Failed" }
        5 { $resultText = "Cancelled" }
        Default { $resultText = "Unexpected ($Result)"}
    }

    return $resultText
}
Function Get-UpdateDescription {
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Update
    )
    # Base description
    $description = $update.Title + " {$($update.Identity.UpdateID).$($update.Identity.RevisionNumber)}"

    if ($update.IsHidden) {
        $description += " (hidden)"
    }

    return $description
}
Function Write-Log
{
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        $File
    )
    Add-Content -Value "$(Get-Date -Format u) -- $Message" -Path $backupLogFile -PassThru
}
#endregion Functions

#region Variables
$log               = "C:\Windows\Logs\ECS\WindowsUpdates.log"
$logPathTest       = Test-Path -Path $(Split-Path -Path $log)
$updateSession     = New-Object -ComObject Microsoft.Update.Session
$updateSearcher    = $updateSession.CreateUpdateSearcher()
if ($IncludeOptionalUpdates) {
    $criteria      = "IsInstalled=0 and RebootRequired=0 and Type='Software'"
}else {
    $criteria      = "IsInstalled=0 and RebootRequired=0 and Type='Software' and BrowseOnly=0"
}
$results           = $updateSearcher.search($criteria).Updates
$updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
$updatesToInstall  = New-Object -ComObject Microsoft.Update.UpdateColl
#endregion Variables

#region Pre-reqs
# Event source
if (!([System.Diagnostics.EventLog]::SourceExists("ECS Patching"))) {
    New-EventLog -LogName "Application" -Source "ECS Patching"
}

# Log file test
if (!$logPathTest) {
    New-Item -Path $(Split-Path -Path $log) -ItemType Directory | Out-Null
}

#region Main
# Check update count
if ($results.Count -eq 0) {
    Write-Host "No updates found" -ForegroundColor Green
    exit 0
}

# Print available updates
foreach ($item in $results){
    Write-Host "Available update: $(Get-UpdateDescription -Update $item)"
}

# Filter updates
for ($i = 0; $i -lt $results.Count; $i++){
    $update = $results.Item($i)
    $description = Get-UpdateDescription -Update $update
    if ($update.IsHidden -ne $true) {
        $updatesToDownload.Add($update) | Out-Null
    }else {
        Write-Host "[SKIPPING HIDDEN UPDATE] $description"
    }
}

if ($NoDownload) {
    Write-Host "Skipping downloads"
}else{
    # Download Updates
    Write-Host "Downloading updates..."
    $updateDownloader = $updateSession.CreateUpdateDownloader()
    $updateDownloader.Updates = $updatesToDownload
    $downloadResults = $updateDownloader.Download()
    Write-Host "Finished downloading updates"

    # Get download result
    Write-Host "Download results: $(Get-WindowsUpdateDownloadResults -Result $downloadResults.ResultCode)"

    # Get downloaded updates
    for ($i = 0; $i -lt $updatesToDownload.Count; $i++){
        $update = $updatesToDownload.Item($i)
        $description = Get-UpdateDescription -Update $update
        if ($update.IsDownloaded -eq $true) {
            Write-Host "[DOWNLOADED ] $description"
            $updatesToInstall.Add($update) | Out-Null
        }
    }
}

if ($NoInstall) {
    Write-Host "Skipping installs"
}else {
    # Install Updates
    if ($updatesToInstall.Count -gt 0) {
        $updateInstaller = $updateSession.CreateUpdateInstaller()
        $updateInstaller.Updates = $updatesToInstall
        $installResults = $updateInstaller.Install()
        
        # Results
        Write-Host "Install results: $(Get-WindowsUpdateInstallResults -Result $installResults.ResultCode)"
        Write-Host "Reboot required: $($installResults.RebootRequired)"
        for ($i = 0; $i -lt $updatesToInstall.Count; $i++) {
            $message = @"
$(Get-UpdateDescription -Update $updatesToInstall.Item($i)): $(Get-WindowsUpdateInstallResults -Result $installResults.GetUpdateResult($i).ResultCode) HRESULT: $($installResults.GetUpdateResult($i).HResult)
"@
            Write-Host $message
            if ($installResults.GetUpdateResult($i).HResult -eq -2145116147) {
                Write-Host "An update needed additional downloaded content. Re-run this script"
            }
        }
    }
}

# Check Reboot Required
if ($Reboot -and $installResults.RebootRequired) {
    Write-Host "Rebooting in 30 seconds to finish updates..."
    Restart-Computer -Timeout 3600 -Delay 30
}elseif (!$Reboot -and $installResults.RebootRequired) {
    Write-Host "Reboot required to finish updates"
}elseif (!$installResults.RebootRequired) {
    Write-Host "No reboot required"
}
#endregion Main