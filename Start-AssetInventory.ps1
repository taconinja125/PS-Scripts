<#
.SYNOPSIS
Generate a basic system report in PowerShell 7 for macOS and Windows

.DESCRIPTION
Generate a JSON object for the following...
1. System info
2. Installed apps
3. Disk info
4. Network info

.NOTES
Stay spicy
#>

param(
    [string]$OutFile = "~\inventoryReport.json"
)

#region System info
$osPlatform = if ($IsWindows) { "Windows" } else { "macOS" }

# Collect system information
$systemInfo = @{
    OSPlatform  = $osPlatform
    OSVersion   = [System.Environment]::OSVersion.Version.ToString()
    MachineName = if ($IsWindows) {$env:COMPUTERNAME} else {/bin/hostname -s}
    CPU         = if ($IsWindows) { (Get-WmiObject -Class Win32_Processor).Name } else { sysctl -n machdep.cpu.brand_string }
    RAM         = if ($IsWindows) {"{0} GB" -f ((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB -as [int]) } else { "{0} GB" -f ((system_profiler SPHardwareDataType | grep "Memory:" | Out-String).Split(":").Trim()[1] -replace " GB", "") }
}
#endregion System info

#region Installed apps
if ($IsWindows) {
    $installedApps = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
    Where-Object { $_.DisplayName -ne $null } | 
    Select-Object -Property DisplayName, DisplayVersion, Publisher
}else {
    $installedApps = system_profiler SPApplicationsDataType | 
    Select-String "Location: /Applications/", "Version:" -Context 0, 1 | 
    ForEach-Object { $_.Context.DisplayPostContext[0] + " " + $_.Line }
}
#endregion Installed apps

#region Disk info
$diskSpace = Get-PSDrive -PSProvider FileSystem |
    Where-Object { ($_.Used -ne $null) -and ($_.Name -NE 'Temp') } |
    Select-Object Name, @{Name = "UsedSize(GB)"; Expression = { [math]::Round($_.Used / 1GB, 2) } }, @{Name = "FreeSpace(GB)"; Expression = { [math]::Round($_.Free / 1GB, 2) } }
#endregion Disk info

#region Disk encryption
if ($IsWindows) {
    $diskEncryption = Get-BitLockerVolume | ForEach-Object {
        [PSCustomObject]@{
            Drive = $_.MountPoint
            EncryptionStatus = $_.VolumeStatus
            KeyProtector = $_.KeyProtector
            'Protection Status' = $_.ProtectionStatus
        }
    }
} else {
    $diskEncryption = fdesetup status | Out-String
}
#endregion Disk encryption

#region Network info
if ($IsWindows) {
    $networkInfo = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | 
    Where-Object { $_.IPAddress -ne $null } | 
    Select-Object Description, IPAddress, IPSubnet, DefaultIPGateway
}
else {
    $networkInfo = "/sbin/ifconfig" | 
    ForEach-Object { $_ -split "\n" } | 
    Where-Object { $_ -match "inet " } | 
    ForEach-Object {
        $parts = $_ -split " "
        [PSCustomObject]@{
            Description      = "Interface"
            IPAddress        = $parts[1]
            IPSubnet         = $parts[3]
            DefaultIPGateway = "N/A"
        }
    }
}
#endregion Network info

#region Bring it all together
$inventoryReport = @{
    SystemInformation = $systemInfo
    InstalledSoftware = $installedApps
    DiskSpace         = $diskSpace
    DiskEncryption    = $diskEncryption
    NetworkInfo       = $networkInfo
}
$inventoryReportJson = $inventoryReport | ConvertTo-Json -Depth 3
$inventoryReportJson | Out-File -FilePath $OutFile
#endregion