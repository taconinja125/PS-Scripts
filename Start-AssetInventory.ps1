#!/usr/local/bin/pwsh
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
$systemInfo = @{
    OSPlatform   = ($IsWindows) ? "Windows" : "macOS"
    OSVersion    = [System.Environment]::OSVersion.Version.ToString()
    MachineName  = ($IsWindows) ? $env:COMPUTERNAME : (/bin/hostname -s)
    SerialNumber = ($IsWindows) ? (Get-CimInstance -ClassName Win32_BIOS).SerialNumber : ((ioreg -l | grep IOPlatformSerialNumber).split(' ')[-1].trim('"'))
    CPU          = ($IsWindows) ? (Get-WmiObject -Class Win32_Processor).Name : (sysctl -n machdep.cpu.brand_string)
    RAM          = ($IsWindows) ? ("{0} GB" -f ((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB -as [int])) : ("{0} GB" -f ((system_profiler SPHardwareDataType | grep "Memory:" | Out-String).Split(":").Trim()[1] -replace " GB", ""))
}
#endregion System info

#region Installed apps
if ($IsWindows) {
    $installedApps = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
    Where-Object { $_.DisplayName -ne $null } | 
    Select-Object -Property DisplayName, DisplayVersion, Publisher
}else {
    $installedApps = Get-ChildItem -Path /Applications,/Applications/Utilitles -Filter *.app -Depth 1 | Foreach-Object {
        if (Test-Path -path $(Join-Path -Path $_.FullName -ChildPath /Contents/Info.plist)) {
            $identifier = /usr/bin/defaults read $(Join-Path -Path $_.FullName -ChildPath /Contents/Info.plist) CFBundleIdentifier
            $version = /usr/bin/defaults read $(Join-Path -Path $_.FullName -ChildPath /Contents/Info.plist) CFBundleShortVersionString
            [PSCustomObject]@{
                Name = $_.BaseName
                Identifier  = $identifier
                Version     = $version
            }
        }
    }
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
    $diskEncryption = (fdesetup status | Out-String).trim()
}
#endregion Disk encryption

#region Network info
if ($IsWindows) {
    $networkInfo = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | 
    Where-Object { $_.IPAddress -ne $null } | 
    Select-Object Description, IPAddress, IPSubnet, DefaultIPGateway
}
else {
    $networkInfo = /sbin/ifconfig | 
    ForEach-Object { $_ -split "\n" } | 
    Where-Object { $_ -match "inet " } | 
    ForEach-Object {
        $parts = $_ -split " "
        [PSCustomObject]@{
            Description      = "Interface"
            IPAddress        = $parts[1]
            IPSubnet         = $parts[3]
        }
    }
}
#endregion Network info

#region Bring it all together
$inventoryReport = @{
    SystemInformation = $systemInfo
    DiskSpace         = $diskSpace
    DiskEncryption    = $diskEncryption
    NetworkInfo       = $networkInfo
    InstalledSoftware = $installedApps
}
$inventoryReportJson = $inventoryReport | ConvertTo-Json -Depth 3
$inventoryReportJson | Out-File -FilePath $OutFile
#endregion