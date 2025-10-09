<#
.SYNOPSIS
Retrieves Intune device compliance status for a specified device by display name.

.DESCRIPTION
This script connects to Microsoft Graph API to retrieve device compliance information for a specific device.
It searches for the device by display name, then retrieves detailed compliance status including any non-compliant policies and settings.

.PARAMETER DisplayName
The display name of the device to search for in Intune.

.PARAMETER ShowCompliancePolicies
Optional switch to show detailed compliance policy information for non-compliant devices.

.EXAMPLE
.\Get-DeviceIntuneComplianceStatus.ps1 -DisplayName "DESKTOP-ABC123"

.EXAMPLE
.\Get-DeviceIntuneComplianceStatus.ps1 -DisplayName "DESKTOP-ABC123" -ShowCompliancePolicies

.NOTES
Requires Microsoft Graph PowerShell SDK module and appropriate permissions:
- DeviceManagementManagedDevices.Read.All
- DeviceManagementConfiguration.Read.All

Stay spicy
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Display name of the device to search for")]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName,

    [Parameter(Mandatory = $false, HelpMessage = "Show detailed compliance policy information")]
    [switch]$ShowCompliancePolicies
)

#region Authentication

# Connect to Microsoft Graph if not already connected
$graphConnection = Get-MgContext
if (-not $graphConnection) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    try {
        Connect-MgGraph -NoWelcome -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Host "Already connected to Microsoft Graph as: $($graphConnection.Account)" -ForegroundColor Green
}

#endregion

#region Device Management Functions

function Get-ManagedDeviceByDisplayName {
    <#
    .SYNOPSIS
    Gets managed device information by display name
    .DESCRIPTION
    This function retrieves managed device information from Intune using the device display name
    .PARAMETER DisplayName
    The display name of the device to search for
    .EXAMPLE
    Get-ManagedDeviceByDisplayName -DisplayName "DESKTOP-ABC123"
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$filter=deviceName eq '$DisplayName'"

    try {
        Write-Host "Searching for device: $DisplayName" -ForegroundColor Yellow
        Write-Verbose "Calling URI: $uri"
        $response = Invoke-MgGraphRequest -Uri $uri -Method Get

        if ($response.value.Count -eq 0) {
            Write-Host "No device found with display name: $DisplayName" -ForegroundColor Red
            return $null
        } elseif ($response.value.Count -gt 1) {
            Write-Host "Multiple devices found with display name: $DisplayName" -ForegroundColor Yellow
            Write-Host "Found $($response.value.Count) devices. Using the first one." -ForegroundColor Yellow
        }

        return $response.value[0]
    } catch {
        $ex = $_.Exception
        Write-Error "Error occurred: $($ex.Message)"

        if ($_.ErrorDetails) {
            Write-Host "API Error Details:" -ForegroundColor Red
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }

        if ($ex.Response) {
            Write-Host "HTTP Status: $($ex.Response.StatusCode) - $($ex.Response.ReasonPhrase)" -ForegroundColor Red
        }

        return $null
    }
}

function Get-DeviceComplianceStatus {
    <#
    .SYNOPSIS
    Gets device compliance status information
    .DESCRIPTION
    This function retrieves compliance status for a specific managed device
    .PARAMETER DeviceId
    The ID of the managed device
    .EXAMPLE
    Get-DeviceComplianceStatus -DeviceId "12345678-1234-1234-1234-123456789012"
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )

    $graphApiVersion = "beta"
    $Resource = "deviceManagement/managedDevices('$DeviceId')/deviceCompliancePolicyStates"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"

    try {
        Write-Host "Retrieving compliance status for device..." -ForegroundColor Yellow
        Write-Verbose "Calling URI: $uri"
        $response = Invoke-MgGraphRequest -Uri $uri -Method Get
        return $response.value
    } catch {
        $ex = $_.Exception
        Write-Error "Error occurred: $($ex.Message)"

        if ($_.ErrorDetails) {
            Write-Host "API Error Details:" -ForegroundColor Red
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }

        return $null
    }
}

function Get-DeviceCompliancePolicySettingStates {
    <#
    .SYNOPSIS
    Gets detailed compliance policy setting states for non-compliant policies
    .DESCRIPTION
    This function retrieves detailed setting states for a specific device compliance policy state
    .PARAMETER PolicyStateId
    The ID of the device compliance policy state
    .EXAMPLE
    Get-DeviceCompliancePolicySettingStates -PolicyStateId "12345678-1234-1234-1234-123456789012"
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$PolicyStateId
    )

    $graphApiVersion = "beta"
    $Resource = "deviceManagement/deviceCompliancePolicyStates('$PolicyStateId')/settingStates"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"

    try {
        Write-Verbose "Calling URI: $uri"
        $response = Invoke-MgGraphRequest -Uri $uri -Method Get
        return $response.value
    } catch {
        Write-Host "Could not retrieve setting states for policy state ID: $PolicyStateId" -ForegroundColor Red
        return $null
    }
}

#endregion

#region Output Functions

function Write-ComplianceStatus {
    <#
    .SYNOPSIS
    Formats and displays device compliance status information
    .DESCRIPTION
    This function formats compliance status information with color coding
    .PARAMETER Device
    The managed device object
    .PARAMETER ComplianceStates
    Array of compliance policy states
    .EXAMPLE
    Write-ComplianceStatus -Device $device -ComplianceStates $complianceStates
    #>

    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]$Device,

        [Parameter(Mandatory = $false)]
        [array]$ComplianceStates
    )

    Write-Host ""
    Write-Host "=================================================================================" -ForegroundColor Yellow
    Write-Host "DEVICE COMPLIANCE REPORT" -ForegroundColor Yellow
    Write-Host "=================================================================================" -ForegroundColor Yellow

    # Device Information
    Write-Host ""
    Write-Host "Device Information:" -ForegroundColor Cyan
    Write-Host "  Device Name: $($Device.deviceName)" -ForegroundColor White
    Write-Host "  Device Model: $($Device.model)" -ForegroundColor White
    Write-Host "  Operating System: $($Device.operatingSystem)" -ForegroundColor White
    Write-Host "  OS Version: $($Device.osVersion)" -ForegroundColor White
    Write-Host "  Owner Type: $($Device.ownerType)" -ForegroundColor White
    Write-Host "  Last Sync: $($Device.lastSyncDateTime)" -ForegroundColor White
    Write-Host "  Enrollment Type: $($Device.deviceEnrollmentType)" -ForegroundColor White

    # Overall Compliance Status
    Write-Host ""
    Write-Host "Overall Compliance Status:" -ForegroundColor Cyan
    if ($Device.complianceState -eq "compliant") {
        Write-Host "  Status: $($Device.complianceState)" -ForegroundColor Green
    } else {
        Write-Host "  Status: $($Device.complianceState)" -ForegroundColor Red
    }

    # Compliance Policy Details
    if ($ComplianceStates -and $ComplianceStates.Count -gt 0) {
        Write-Host ""
        Write-Host "Compliance Policy Details:" -ForegroundColor Cyan

        $compliantPolicies = @()
        $nonCompliantPolicies = @()

        foreach ($policyState in $ComplianceStates) {
            if ($policyState.state -eq "compliant") {
                $compliantPolicies += $policyState
            } else {
                $nonCompliantPolicies += $policyState
            }
        }

        if ($compliantPolicies.Count -gt 0) {
            Write-Host ""
            Write-Host "  Compliant Policies:" -ForegroundColor Green
            foreach ($policy in $compliantPolicies) {
                Write-Host "    PASS: $($policy.displayName)" -ForegroundColor Green
            }
        }

        if ($nonCompliantPolicies.Count -gt 0) {
            Write-Host ""
            Write-Host "  Non-Compliant Policies:" -ForegroundColor Red
            foreach ($policy in $nonCompliantPolicies) {
                Write-Host "    FAIL: $($policy.displayName) - Status: $($policy.state)" -ForegroundColor Red

                if ($ShowCompliancePolicies) {
                    $settingStates = Get-DeviceCompliancePolicySettingStates -PolicyStateId $policy.id
                    if ($settingStates) {
                        Write-Host "      Non-compliant settings:" -ForegroundColor Yellow
                        foreach ($setting in $settingStates) {
                            if ($setting.state -ne "compliant") {
                                Write-Host "        - $($setting.setting): $($setting.state)" -ForegroundColor Red
                            }
                        }
                    }
                }
            }
        }
    } else {
        Write-Host ""
        Write-Host "  No compliance policy information available" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=================================================================================" -ForegroundColor Yellow
}

#endregion

#region Main Script

# Check if we're running as administrator for certain operations
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Note: Running without administrator privileges. Some operations may be limited." -ForegroundColor Yellow
}

Write-Host "Starting Intune Device Compliance Status Retrieval..." -ForegroundColor Green
Write-Host "Target Device: $DisplayName" -ForegroundColor White

# Verify Graph connection exists
$graphConnection = Get-MgContext
if (-not $graphConnection) {
    Write-Error "Authentication failed. No Graph connection available."
    exit 1
}

Write-Host "Authentication successful. Connected as: $($graphConnection.Account)" -ForegroundColor Green
Write-Host

# Search for the device
$device = Get-ManagedDeviceByDisplayName -DisplayName $DisplayName

if ($device) {
    Write-Host "Device found: $($device.deviceName)" -ForegroundColor Green

    # Get compliance status
    $complianceStates = Get-DeviceComplianceStatus -DeviceId $device.id

    # Display results
    Write-ComplianceStatus -Device $device -ComplianceStates $complianceStates

} else {
    Write-Host "Device not found. Please check the display name and try again." -ForegroundColor Red
    Write-Host "Make sure the device is enrolled in Intune and the display name is exact." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Script completed." -ForegroundColor Green

#endregion