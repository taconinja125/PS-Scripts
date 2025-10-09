<#

.SYNOPSIS
This script retrieves device recovery keys for both Windows (BitLocker) and macOS (FileVault) devices from Intune using Microsoft Graph API

.DESCRIPTION
This script authenticates with Microsoft Graph API and retrieves recovery keys for managed devices.
It supports both BitLocker recovery keys for Windows devices and FileVault recovery keys for macOS devices.
The script automatically detects the device platform or allows explicit platform specification.

.PARAMETER DeviceName
The name of the device for which to retrieve the recovery key. This parameter is mandatory.

.PARAMETER Platform
Optionally specify the device platform. Valid values are: Windows, macOS, Auto (default).
When set to 'Auto', the script will attempt to detect the platform automatically.

.NOTES
Stay spicy

.EXAMPLE
.\Get-ManagedDeviceRecoveryKey.ps1 -DeviceName "LAPTOP-ABC123" -AppId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -AppSecret "your-secret-here"
Retrieves the recovery key for the specified device, automatically detecting if it's Windows or macOS

.EXAMPLE
.\Get-ManagedDeviceRecoveryKey.ps1 -DeviceName "Johns-MacBook-Pro" -Platform macOS -AppId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -AppSecret "your-secret-here"
Explicitly retrieves the FileVault recovery key for a macOS device

.EXAMPLE
.\Get-ManagedDeviceRecoveryKey.ps1 -DeviceName "DESKTOP-XYZ789" -Platform Windows -AppId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -AppSecret "your-secret-here"
Explicitly retrieves the BitLocker recovery key for a Windows device

.EXAMPLE
# Using Azure Key Vault for secure secret retrieval
$appSecret = Get-AzKeyVaultSecret -VaultName "MyKeyVault" -Name "GraphAppSecret" -AsPlainText
.\Get-ManagedDeviceRecoveryKey.ps1 -DeviceName "LAPTOP-ABC123" -AppId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321" -AppSecret $appSecret
Retrieves the recovery key using a secret stored in Azure Key Vault

.NOTES
- Requires Microsoft Graph PowerShell SDK module
- BitLocker requires: BitlockerKey.ReadBasic.All or BitlockerKey.Read.All permissions
- FileVault requires: DeviceManagementManagedDevices.Read.All permission
- For BitLocker: User must be device owner or have Azure AD roles (Cloud device admin, Helpdesk admin, etc.)
- BitLocker keys are retrieved via Azure AD device ID
- FileVault keys are retrieved via Intune managed device ID

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The name of the device to retrieve recovery key for")]
    [string]$DeviceName,

    [Parameter(Mandatory = $false, HelpMessage = "Device platform (Windows, macOS, or Auto)")]
    [ValidateSet("Windows", "macOS", "Auto")]
    [string]$Platform = "Auto",

    [Parameter(Mandatory = $true, HelpMessage = "Azure AD Application (Client) ID with appropriate Graph API permissions")]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory = $true, HelpMessage = "Azure AD Tenant ID")]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $true, HelpMessage = "Application client secret for authentication")]
    [ValidateNotNullOrEmpty()]
    [string]$AppSecret
)

####################################################

Function Get-ManagedDeviceInfo {

    <#
    .SYNOPSIS
    Retrieves managed device information from Intune by device name
    .DESCRIPTION
    Queries Microsoft Graph for managed devices matching the specified name and handles duplicates
    .PARAMETER DeviceName
    The name of the device to search for
    .PARAMETER Headers
    The authentication headers to use for the request
    .NOTES
    Handles multiple devices with the same name by selecting the most recently synced device
    #>

    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $graphApiVersion = "beta"
    
    try {
        Add-Type -AssemblyName System.Web
        $encodedDeviceName = [System.Web.HttpUtility]::UrlEncode($DeviceName)
        
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/managedDevices" +
            "?`$filter=deviceName eq '$encodedDeviceName'" +
            "&`$orderby=lastSyncDateTime desc"
        
        Write-Host "Searching for device: $DeviceName..." -ForegroundColor Yellow
        $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
        $deviceInfo = $response.value
        
        if ($deviceInfo.Count -eq 0) {
            Write-Host "No devices found matching '$DeviceName'" -ForegroundColor Red
            return $null
        }
        
        if ($deviceInfo.Count -gt 1) {
            Write-Host "Found $($deviceInfo.Count) devices matching '$DeviceName'. Using most recently synced device: '$($deviceInfo[0].deviceName)'" -ForegroundColor Yellow
            $deviceInfo = $deviceInfo[0]
        } else {
            Write-Host "Found device: $($deviceInfo[0].deviceName)" -ForegroundColor Green
            $deviceInfo = $deviceInfo[0]
        }
        
        return $deviceInfo
        
    } catch {
        Write-Host "Error querying devices: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

####################################################

Function Get-BitLockerRecoveryKey {

    <#
    .SYNOPSIS
    Retrieves BitLocker recovery key for a Windows device
    .DESCRIPTION
    Queries Microsoft Graph BitLocker API using the device's Azure AD device ID
    .PARAMETER DeviceInfo
    The managed device information object from Get-ManagedDeviceInfo
    .PARAMETER Headers
    The authentication headers to use for the request
    .NOTES
    Requires the device to have an Azure AD device ID and BitLocker enabled
    Requires BitlockerKey.ReadBasic.All or BitlockerKey.Read.All permissions
    User must be device owner or have appropriate Azure AD roles
    #>

    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DeviceInfo,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    try {
        if (-not $DeviceInfo.azureADDeviceId) {
            Write-Host "Device does not have an Azure AD Device ID. BitLocker recovery key cannot be retrieved." -ForegroundColor Red
            return $null
        }

        $deviceID = $DeviceInfo.azureADDeviceId
        Write-Host "Retrieving BitLocker recovery key..." -ForegroundColor Yellow

        # Use beta API endpoint like the sample module
        $recoveryKeysUri = "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId%20eq%20%27$deviceID%27"
        Write-Host "Querying recovery keys for device ID: $deviceID" -ForegroundColor Gray
        
        try {
            $results = Invoke-RestMethod -Uri $recoveryKeysUri -Headers $Headers -Method Get
            $recoveryKey = $results.value[0].id
            $key = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$recoveryKey`?`$select=key" -Headers $Headers -Method Get
            
            return @{
                DeviceName = $DeviceInfo.deviceName
                DeviceId = $DeviceInfo.id
                AzureADDeviceId = $DeviceInfo.azureADDeviceId
                Platform = $DeviceInfo.operatingSystem
                RecoveryKey = $key.key
            }
            
        } catch {
            Write-Host "Unable to find Bitlocker key for " -ForegroundColor DarkRed -NoNewline
            Write-Host "$($DeviceInfo.deviceName)" -ForegroundColor Red
            return $null
        }
        
    } catch {
        Write-Host "Error retrieving BitLocker recovery key: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

####################################################

Function Get-FileVaultRecoveryKey {

    <#
    .SYNOPSIS
    Retrieves FileVault recovery key for a macOS device
    .DESCRIPTION
    Queries Microsoft Graph Intune API using the device's managed device ID
    .PARAMETER DeviceInfo
    The managed device information object from Get-ManagedDeviceInfo
    .NOTES
    Requires the device to be enrolled in Intune and have FileVault enabled
    #>

    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DeviceInfo
    )

    try {
        # Ensure Graph connection for FileVault (macOS uses Graph SDK)
        $graphConnection = Get-MgContext
        if (-not $graphConnection) {
            Write-Host "Connecting to Microsoft Graph for FileVault key retrieval..." -ForegroundColor Yellow
            Connect-MgGraph -NoWelcome
        }
        
        $deviceID = $DeviceInfo.id
        Write-Host "Retrieving FileVault recovery key..." -ForegroundColor Yellow

        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceID/getFileVaultKey"
        $result = Invoke-MgGraphRequest -Uri $uri -Method Get
        
        if (-not $result.value) {
            Write-Host "No FileVault recovery key found for this device." -ForegroundColor Red
            return $null
        }
        
        return @{
            DeviceName = $DeviceInfo.deviceName
            DeviceId = $DeviceInfo.id
            AzureADDeviceId = $DeviceInfo.azureADDeviceId
            Platform = $DeviceInfo.operatingSystem
            RecoveryKey = $result.value
        }
        
    } catch {
        Write-Host "Error retrieving FileVault recovery key: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

####################################################

Function Get-DeviceRecoveryKey {

    <#
    .SYNOPSIS
    Main function to retrieve recovery key with automatic platform detection
    .DESCRIPTION
    Determines the appropriate recovery key method based on device platform
    .PARAMETER DeviceName
    The name of the device to retrieve recovery key for
    .PARAMETER Platform
    The platform specification (Windows, macOS, or Auto)
    .PARAMETER Headers
    The authentication headers to use for requests
    .NOTES
    Handles platform detection and calls the appropriate recovery key function
    #>

    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceName,
        
        [Parameter(Mandatory = $false)]
        [string]$Platform = "Auto",
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $deviceInfo = Get-ManagedDeviceInfo -DeviceName $DeviceName -Headers $Headers
    
    if (-not $deviceInfo) {
        return
    }

    Write-Host
    Write-Host "Device Details:" -ForegroundColor Cyan
    Write-Host "  Name: $($deviceInfo.deviceName)" -ForegroundColor White
    Write-Host "  Platform: $($deviceInfo.operatingSystem)" -ForegroundColor White
    Write-Host "  Device ID: $($deviceInfo.id)" -ForegroundColor White
    Write-Host "  Azure AD Device ID: $($deviceInfo.azureADDeviceId)" -ForegroundColor White
    Write-Host

    $detectedPlatform = $deviceInfo.operatingSystem
    $targetPlatform = if ($Platform -eq "Auto") { $detectedPlatform } else { $Platform }

    switch ($targetPlatform) {
        "Windows" {
            if ($detectedPlatform -notmatch "Windows") {
                Write-Host "Warning: Detected platform is '$detectedPlatform' but Windows was specified." -ForegroundColor Yellow
            }
            $recoveryInfo = Get-BitLockerRecoveryKey -DeviceInfo $deviceInfo -Headers $Headers
        }
        "macOS" {
            if ($detectedPlatform -notmatch "macOS") {
                Write-Host "Warning: Detected platform is '$detectedPlatform' but macOS was specified." -ForegroundColor Yellow
            }
            $recoveryInfo = Get-FileVaultRecoveryKey -DeviceInfo $deviceInfo
        }
        default {
            if ($detectedPlatform -match "Windows") {
                Write-Host "Auto-detected Windows device, retrieving BitLocker key..." -ForegroundColor Green
                $recoveryInfo = Get-BitLockerRecoveryKey -DeviceInfo $deviceInfo -Headers $Headers
            }
            elseif ($detectedPlatform -match "macOS") {
                Write-Host "Auto-detected macOS device, retrieving FileVault key..." -ForegroundColor Green
                $recoveryInfo = Get-FileVaultRecoveryKey -DeviceInfo $deviceInfo
            }
            else {
                Write-Host "Unsupported platform: $detectedPlatform" -ForegroundColor Red
                return
            }
        }
    }

    if ($recoveryInfo) {
        Write-Host
        Write-Host "Recovery Key Information:" -ForegroundColor Cyan
        Write-Host "  Device Name: " -NoNewline
        Write-Host "$($recoveryInfo.DeviceName)" -ForegroundColor Green
        Write-Host "  Device Object ID: " -NoNewline
        Write-Host "$($recoveryInfo.DeviceId)" -ForegroundColor White
        Write-Host "  Recovery Key: " -NoNewline
        Write-Host "$($recoveryInfo.RecoveryKey)" -ForegroundColor Yellow
    }
}

####################################################

#region Authentication

Write-Host

# Get access token using client credentials flow
Function Get-AccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant,
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [string]$AppSecret
    )

    $body = @{
        grant_type    = "client_credentials";
        client_id     = $AppId;
        client_secret = $AppSecret;
        scope         = "https://graph.microsoft.com/.default";
    }

    $response = Invoke-RestMethod -Method Post -Uri https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token -Body $body
    return $response.access_token
}

$accessToken = Get-AccessToken -Tenant $TenantId -AppId $AppId -AppSecret $AppSecret
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-type"  = "application/json"
}

#endregion

####################################################

#region Main Script Logic

if (-not $accessToken) {
    Write-Error "Authentication failed. No access token available."
    exit 1
}

Write-Host "Authentication successful. Using client credentials flow." -ForegroundColor Green
Write-Host

Get-DeviceRecoveryKey -DeviceName $DeviceName -Platform $Platform -Headers $headers

#endregion

Write-Host
Write-Host "Script completed." -ForegroundColor Green