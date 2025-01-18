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
    [bool]$Reboot,
    [string]$LogPath = "C:\ECS\WindowsUpdates.log",
    [switch]$AutoAcceptEULA,
    [switch]$Force
)

#region Functions
Function Get-WindowsUpdateDeploymentActionToText {
    param(
        [Parameter(Mandatory=$true)]
        [Int]$Action
    )

    switch ($Action) {
        0 { $DeploymentAction = "None (Inherit)" }
        1 { $DeploymentAction = "Installation" }
        2 { $DeploymentAction = "Uninstallation" }
        3 { $DeploymentAction = "Detection" }
        4 { $DeploymentAction = "Optional Installation" }
        Default { $DeploymentAction = "Unexpected ($Action)" }
    }

    $DeploymentAction
}
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
        Default { $resultText = "Unexpected download return code ($Result)"}
    }

    return $resultText
}
Function Get-WindowsUpdateInstallResults {
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [Int]$Result
    )

    switch ($Result) {
        2 { $resultText = "Install succeeded" }
        3 { $resultText = "Install succeeded with errors" }
        4 { $resultText = "Install failed" }
        5 { $resultText = "Install Cancelled" }
        Default { $resultText = "Unexpected install return code ($Result)"}
    }

    return $resultText
}
Function Get-WindowsUpdateDescription {
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
Function Write-Log {
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Message,
        [Parameter(Mandatory=$true,Position=1)]
        [ValidateSet("INFO","WARNING","ERROR")]
        [string]$EventType,
        $File
    )
    Add-Content -Value "$(Get-Date -Format u) -- [$EventType ] $Message" -Path $File -PassThru
}
Function Show-WindowsUpdateDetails {
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Update
    )

    BEGIN{
        $kbArticles = @()
        $updateCategories = @{}
    }
    
    PROCESS{
        $updateTitle  = $Update.Title
        $updateDescription = $Update.Description
        $updateID     = "$($Update.Identity.UpdateID).$($Update.Identity.RevisionNumber)"
        $updateHidden = $Update.IsHidden
        $updateDeploymentAction = Get-WindowsUpdateDeploymentActionToText -Action $Update.DeploymentAction

        # KB Article IDs
        if ($Update.KBArticleIDs.Count -gt 0) {
            for ($i = 0; $i -lt $Update.KBArticleIDs.Count; $i++) {
                $kbArticles += $Update.KBArticleIDs.Item($i)
            }
        }

        # Update Categories
        if ($Update.Categories.Count -gt 0) {
            for ($i = 0; $i -lt $Update.Categories.Count; $i++) {
                $category = $Update.Categories.Item($i)
                $updateCategories.Add($category.Name, $category.CategoryID)
            }
        }

        $outObj = @{
            Title            = $updateTitle
            Description      = $updateDescription
            ID               = $updateID
            Hidden           = $updateHidden
            DeploymentAction = $updateDeploymentAction
            KBArticleIds     = $kbArticles
            Categories       = $updateCategories
        }
    }

    END{
        $outObj
    }
}
Function Test-WindowsUpdateInstallationBehavior {
    param(
        [Parameter(Mandatory=$true)]
        $Update
    )
    
    try {
        # Check if update requires user input
        if ($Update.InstallationBehavior.CanRequestUserInput) {
            Write-Log -Message "Update requires user input: $($Update.Title)" -EventType WARNING -File $log
            return $false
        }
        
        # Check impact level
        if ($Update.InstallationBehavior.Impact -eq 2) {
            Write-Log -Message "Update is exclusive: $($Update.Title)" -EventType WARNING -File $log
            return $true  # Return true but caller should handle exclusive updates
        }
        
        return $true
    }
    catch {
        Write-Log -Message "Error checking installation behavior: $($_.Exception.Message)" -EventType ERROR -File $log
        return $false
    }
}
#endregion Functions

#region Variables
$log               = $LogPath
$logPathTest       = Test-Path -Path $(Split-Path -Path $log)
$updateSession     = $null
$updateSearcher    = $null
$criteria          = if ($IncludeOptionalUpdates) {
    "IsInstalled=0 and Type='Software'"  # Removed RebootRequired=0 to match original
} else {
    "IsInstalled=0 and Type='Software' and BrowseOnly=0"
}
$rebootTimeOut     = 3600
$rebootDelay       = 30
#endregion Variables

#region Pre-reqs
# Log file test
if (!$logPathTest) {
    New-Item -Path $(Split-Path -Path $log) -ItemType Directory -Force | Out-Null
}
#endregion Pre-reqs

#region Main
try {
    # Initialize COM objects
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    
    # Check update count
    $results = $updateSearcher.search($criteria).Updates
    if ($results.Count -eq 0) {
        Write-Log -Message "No updates found" -EventType INFO -File $log
        exit 0
    }
    
    # Print available updates
    foreach ($item in $results){
        if ($ShowDetails) {
            Show-WindowsUpdateDetails -Update $item
        }else {
            Write-Log -Message "Available update: $(Get-WindowsUpdateDescription -Update $item)" -EventType INFO -File $log
        }
    }
    
    # Filter updates
    $exclusiveUpdateFound = $false
    $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $results.Count; $i++){
        $update = $results.Item($i)
        $description = Get-WindowsUpdateDescription -Update $update
        
        # Skip if update is hidden
        if ($update.IsHidden) {
            Write-Log -Message "Skipping hidden update: $($update.Title)" -EventType INFO -File $log
            continue
        }
        
        # Check EULA
        if (-not $update.EulaAccepted) {
            if ($AutoAcceptEULA) {
                $update.AcceptEula()
                Write-Log -Message "Auto-accepted EULA for: $($update.Title)" -EventType INFO -File $log
            } else {
                Write-Log -Message "Update requires EULA acceptance: $($update.Title)" -EventType WARNING -File $log
                continue
            }
        }
        
        # Check installation behavior
        $canInstall = Test-WindowsUpdateInstallationBehavior -Update $update
        if (-not $canInstall) {
            continue
        }
        
        # Handle exclusive updates
        if ($update.InstallationBehavior.Impact -eq 2) {
            if ($exclusiveUpdateFound -or $updatesToDownload.Count -gt 0) {
                Write-Log -Message "Skipping exclusive update due to other updates already selected: $($update.Title)" -EventType WARNING -File $log
                continue
            }
            $exclusiveUpdateFound = $true
        } elseif ($exclusiveUpdateFound) {
            Write-Log -Message "Skipping update due to exclusive update already selected: $($update.Title)" -EventType WARNING -File $log
            continue
        }
        
        Write-Log -Message "Adding to download collection: $($update.Title)" -EventType INFO -File $log
        $updatesToDownload.Add($update) | Out-Null
    }
    
    if ($NoDownload) {
        Write-Log -Message "Skipping downloads" -EventType INFO -File $log
    }else{
        # Download Updates
        Write-Log -Message "Beginning download" -EventType INFO -File $log
        $updateDownloader = $updateSession.CreateUpdateDownloader()
        $updateDownloader.Updates = $updatesToDownload
        $downloadResults = $updateDownloader.Download()

        # Get download result
        Write-Log -Message "Download run results: $(Get-WindowsUpdateDownloadResults -Result $downloadResults.ResultCode)" -EventType INFO -File $log

        # Get downloaded updates
        $results = $updateSearcher.search($criteria).Updates
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        for ($i = 0; $i -lt $results.Count; $i++){
            $update = $results.Item($i)
            if ($update.IsDownloaded -eq $true) {
                Write-Log -Message "Downloaded: $($update.Title)" -EventType INFO -File $log
                Write-Host "[DOWNLOADED ] $($update.Title)"
                $updatesToInstall.Add($update) | Out-Null
            }else {
                Write-Log -Message "Not downloaded: $($update.Title)" -EventType WARNING -File $log
            }
        }
    }

    if ($NoDownload -or $NoInstall) {
        Write-Log -Message "Skipping installs" -EventType INFO -File $log
    } else {
        # Install Updates
        if ($updatesToDownload.Count -gt 0) {
            try {
                $updateInstaller = $updateSession.CreateUpdateInstaller()
                $updateInstaller.Updates = $updatesToDownload
                $installResults = $updateInstaller.Install()
                
                # Results
                Write-Log -Message "Install results: $(Get-WindowsUpdateInstallResults -Result $installResults.ResultCode)" -EventType INFO -File $log
                Write-Log -Message "Reboot required: $($installResults.RebootRequired)" -EventType INFO -File $log
                
                for ($i = 0; $i -lt $updatesToDownload.Count; $i++) {
                    $message = @"
$(Get-WindowsUpdateDescription -Update $updatesToDownload.Item($i)): $(Get-WindowsUpdateInstallResults -Result $installResults.GetUpdateResult($i).ResultCode) HRESULT: $($installResults.GetUpdateResult($i).HResult)
"@
                    Write-Log -Message $message -EventType INFO -File $log
                    
                    if ($installResults.GetUpdateResult($i).HResult -eq -2145116147) {
                        Write-Log -Message "An update needed additional downloaded content. Re-run this script or complete in Windows Update menu." -EventType WARNING -File $log
                    }
                }
            }
            catch {
                Write-Log -Message "Error during installation: $($_.Exception.Message)" -EventType ERROR -File $log
                throw
            }
        }
    }
    
    # Check Reboot Required
    if ($Reboot -and $installResults.RebootRequired) {
        Write-Log -Message "Rebooting in [$rebootDelay] seconds to finish updates..." -EventType INFO -File $log
        Restart-Computer -Timeout $rebootTimeOut -Delay $rebootDelay
    }elseif (!$Reboot -and $installResults.RebootRequired) {
        Write-Log -Message "Reboot required to finish updates" -EventType INFO -File $log
    }elseif (!$installResults.RebootRequired) {
        Write-Log -Message "No reboot required" -EventType INFO -File $log
    }
}
catch {
    Write-Log -Message "Critical error: $($_.Exception.Message)" -EventType ERROR -File $log
    throw
}
finally {
    # Clean up COM objects
    if ($updateSession) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($updateSession) | Out-Null }
    if ($updateSearcher) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($updateSearcher) | Out-Null }
    [System.GC]::Collect()
}
#endregion Main