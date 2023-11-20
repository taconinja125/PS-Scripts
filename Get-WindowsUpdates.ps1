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
    [switch]$NoDownload,
    [switch]$NoInstall,
    [switch]$ShowDetails,
    [bool]$Reboot
)

#region Functions
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
#endregion Functions

#region Variables
# Windows Updates search object and results
$updateSession  = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()
$criteria       = "IsInstalled=0 and RebootRequired=0 and Type='Software'"
$results        = $updateSearcher.search($criteria)
# Windows Updates collection object
$updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
# Windows Updates To Install Collection
$updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
#endregion Variables

#region Main
# Check update count
if ($results.Updates.Count -eq 0) {
    Write-Host "No updates found" -ForegroundColor Green
    exit 0
}else {
    foreach ($update in $results.Updates){
        # Add to collection
        $updatesToDownload.Add($update)
        $atLeastOneAdded   = $true
    }
}

# Filter updates
for ($i = 0; $i -lt $results.Updates.Count; $i++){
    $update = $results.Updates.Item($i)
    $description = Get-UpdateDescription -Update $update
    if ($update.IsHidden -ne $true) {
        $updatesToDownload.Add($update)
    }else {
        Write-Host "[SKIPPING HIDDEN UPDATE] $description"
    }
}

# Download Updates
Write-Host "Downloading updates..."
$updateDownloader = $updateSession.CreateUpdateDownloader()
$updateDownloader.Updates = $updatesToDownload
$updateDownloader.Download()
Write-Host "Finished downloading updates"

# Get downloaded updates
for ($i = 0; $i -lt $updatesToDownload.Count; $i++){
    $update = $updatesToDownload.Item($i)
    $description = Get-UpdateDescription -Update $update
    if ($update.IsDownloaded -eq $true) {
        Write-Host "[DOWNLOADED ] $description"
        $updatesToInstall.Add($update)
    }
}

# Install Updates
if ($updatesToInstall -gt 0) {
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
        Write-Event $message
        if ($installResults.GetUpdateResult($i).HResult -eq -2145116147) {
            Write-Host "An update needed additional downloaded content. Re-run this script"
        }
    }
}

# Check Reboot Required
if ($installResults.RebootRequired) {
    <# Action to perform if the condition is true #>
}

#endregion Main