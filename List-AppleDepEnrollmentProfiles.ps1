<#

.SYNOPSIS
This script lists all Apple (macOS and iOS/iPadOS) DEP enrollment profiles using Microsoft Graph API

.DESCRIPTION
This script authenticates with Microsoft Graph API and retrieves all Apple DEP enrollment profiles
(both macOS and iOS/iPadOS) for the available DEP onboarding settings in your Intune tenant.

.PARAMETER Format
Specifies the output format. Valid values are: table, csv, json, xml. Default is table.

.PARAMETER Platform
Specifies the platform to filter by. Valid values are: macOS, iOS/iPadOS. If not specified, returns all Apple DEP enrollment profiles.

.NOTES
Stay spicy

.EXAMPLE
.\List-AllAppleDepEnrollmentProfiles.ps1
Lists all Apple DEP enrollment profiles in table format

.EXAMPLE
.\List-AllAppleDepEnrollmentProfiles.ps1 -Format csv
Lists all Apple DEP enrollment profiles in CSV format

.EXAMPLE
.\List-AllAppleDepEnrollmentProfiles.ps1 -Format json
Lists all Apple DEP enrollment profiles in JSON format

.EXAMPLE
.\List-AllAppleDepEnrollmentProfiles.ps1 -Platform macOS
Lists only macOS DEP enrollment profiles in table format

.EXAMPLE
.\List-AllAppleDepEnrollmentProfiles.ps1 -Platform "iOS/iPadOS" -Format csv
Lists only iOS/iPadOS DEP enrollment profiles in CSV format

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("list", "csv", "json", "xml")]
    [string]$Format = "list",

    [Parameter(Mandatory = $false)]
    [ValidateSet("macOS", "iOS/iPadOS")]
    [string]$Platform
)

####################################################


####################################################

Function Get-DEPOnboardingSettings {

    <#
    .SYNOPSIS
    This function retrieves the DEP onboarding settings for your tenant. DEP Onboarding settings contain information such as Token ID, which is used to sync DEP and VPP
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a retrieves the DEP onboarding settings.
    .EXAMPLE
    Get-DEPOnboardingSettings
    Gets all DEP Onboarding Settings for each DEP token present in the tenant
    .NOTES
    NAME: Get-DEPOnboardingSettings
    #>

    [cmdletbinding()]

    Param(
        [parameter(Mandatory = $false)]
        [string]$tokenid
    )

    $graphApiVersion = "beta"

    try {

        if ($tokenid) {

            $Resource = "deviceManagement/depOnboardingSettings/$tokenid/"
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            Write-Host "Calling URI: $uri" -ForegroundColor Gray
            (Invoke-MgGraphRequest -Uri $uri -Method Get)

        }

        else {

            $Resource = "deviceManagement/depOnboardingSettings/"
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            Write-Host "Calling URI: $uri" -ForegroundColor Gray
            (Invoke-MgGraphRequest -Uri $uri -Method Get).value

        }

    }

    catch {

        $ex = $_.Exception
        Write-Host "Error occurred: $($ex.Message)" -f Red

        if ($ex.Response) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd();
                Write-Host "Response content:`n$responseBody" -f Red
                Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
            }
            catch {
                Write-Host "Could not read error response: $($_.Exception.Message)" -f Red
            }
        }
        else {
            Write-Host "No HTTP response available. This may be a network or authentication issue." -f Red
        }
        write-host
        break

    }

}

####################################################

Function Get-AllAppleDepEnrollmentProfiles() {

    <#
    .SYNOPSIS
    This function is used to get a list of all Apple (macOS and iOS/iPadOS) DEP enrollment profiles by DEP Token
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a list of all Apple DEP enrollment profiles based on DEP token
    .EXAMPLE
    Get-AllAppleDepEnrollmentProfiles -depOnboardingSettingId "12345678-1234-1234-1234-123456789012"
    Gets all Apple DEP enrollment profiles for the specified DEP onboarding setting
    .NOTES
    NAME: Get-AllAppleDepEnrollmentProfiles
    #>

    [cmdletbinding()]

    param
    (
        [Parameter(Mandatory = $true)]
        $depOnboardingSettingId,

        [Parameter(Mandatory = $false)]
        [string]$Platform
    )

    $graphApiVersion = "beta"
    $Resource = "deviceManagement/depOnboardingSettings/$depOnboardingSettingId/enrollmentProfiles"

    try {

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET

        # Filter for Apple profiles based on platform parameter
        if ($Platform) {
            switch ($Platform) {
                'macOS' {
                    $appleProfiles = $response.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.depMacOSEnrollmentProfile' }
                }
                'iOS/iPadOS' {
                    $appleProfiles = $response.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.depIOSEnrollmentProfile' }
                }
            }
        } else {
            # Filter for both macOS and iOS/iPadOS profiles when no platform specified
            $appleProfiles = $response.value | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.depMacOSEnrollmentProfile' -or
                $_.'@odata.type' -eq '#microsoft.graph.depIOSEnrollmentProfile'
            }
        }

        return $appleProfiles

    }

    catch {

        Write-Host
        $ex = $_.Exception
        Write-Host "Error occurred: $($ex.Message)" -f Red

        if ($ex.Response) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd();
                Write-Host "Response content:`n$responseBody" -f Red
                Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
            }
            catch {
                Write-Host "Could not read error response: $($_.Exception.Message)" -f Red
            }
        }
        else {
            Write-Host "No HTTP response available. This may be a network or authentication issue." -f Red
        }
        write-host
        break

    }

}

####################################################

#region Authentication

write-host

# Connect to Microsoft Graph if not already connected
$graphConnection = Get-MgContext
if (-not $graphConnection) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -NoWelcome
}

#endregion

####################################################

#region Main Script Logic

# Verify Graph connection exists
$graphConnection = Get-MgContext
if (-not $graphConnection) {
    Write-Error "Authentication failed. No Graph connection available."
    exit 1
}

if ($Format -eq "table") {
    Write-Host "Authentication successful. Connected as: $($graphConnection.Account)" -ForegroundColor Green
    Write-Host "Retrieving DEP onboarding settings..." -ForegroundColor Yellow
    Write-Host
}

$depOnboardingSettings = Get-DEPOnboardingSettings
$allProfiles = @()

if ($depOnboardingSettings) {

    $settingsCount = @($depOnboardingSettings).count
    if ($Format -eq "table") {
        Write-Host "Found $settingsCount DEP onboarding setting(s)" -ForegroundColor Green
        Write-Host
    }

    foreach ($setting in $depOnboardingSettings) {

        if ($Format -eq "table") {
            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host "DEP Token: $($setting.tokenName)" -ForegroundColor Cyan
            Write-Host "Token ID: $($setting.id)" -ForegroundColor Cyan
            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host
            if ($Platform) {
                Write-Host "Retrieving $Platform DEP enrollment profiles..." -ForegroundColor Yellow
            } else {
                Write-Host "Retrieving Apple DEP enrollment profiles..." -ForegroundColor Yellow
            }
        }

        $appleProfiles = Get-AllAppleDepEnrollmentProfiles -depOnboardingSettingId $setting.id -Platform $Platform

        if ($appleProfiles) {

            $profileCount = @($appleProfiles).count
            if ($Format -eq "table") {
                if ($Platform) {
                    Write-Host "Found $profileCount $Platform DEP enrollment profile(s):" -ForegroundColor Green
                } else {
                    Write-Host "Found $profileCount Apple DEP enrollment profile(s):" -ForegroundColor Green
                }
                Write-Host
            }

            foreach ($p in $appleProfiles) {
                # Determine platform based on odata type
                $platform = switch ($p.'@odata.type') {
                    '#microsoft.graph.depMacOSEnrollmentProfile' { 'macOS' }
                    '#microsoft.graph.depIOSEnrollmentProfile' { 'iOS/iPadOS' }
                    default { 'Unknown' }
                }

                $profileObj = [PSCustomObject]@{
                    'DEP Token' = $setting.tokenName
                    'Token ID' = $setting.id
                    'Platform' = $platform
                    'Profile Name' = $p.displayName
                    'Profile ID' = $p.id
                    'Description' = $p.description
                    'Created' = $p.createdDateTime
                    'Modified' = $p.lastModifiedDateTime
                    'Skip Setup Assistant' = $p.isDefault
                    'Require Authentication' = $p.requiresUserAuthentication
                    'Lock Enrollment Profile' = $p.isProfileLocked
                }
                $allProfiles += $profileObj
            }

        }
        else {
            if ($Format -eq "table") {
                if ($Platform) {
                    Write-Host "  No $Platform DEP enrollment profiles found for this token." -ForegroundColor Yellow
                } else {
                    Write-Host "  No Apple DEP enrollment profiles found for this token." -ForegroundColor Yellow
                }
                Write-Host
            }
        }
    }

}
else {
    if ($Format -eq "table") {
        Write-Warning "No DEP onboarding settings found!"
        Write-Host
    }
}

# Output results in specified format
if ($allProfiles.Count -gt 0) {
    switch ($Format) {
        "list" {
            $allProfiles | Format-List
        }
        "csv" {
            $allProfiles | ConvertTo-Csv -NoTypeInformation
        }
        "json" {
            $allProfiles | ConvertTo-Json -Depth 3
        }
        "xml" {
            $allProfiles | ConvertTo-Xml -NoTypeInformation | Select-Object -ExpandProperty OuterXml
        }
    }
}
else {
    if ($Format -eq "table") {
        if ($Platform) {
            Write-Warning "No $Platform DEP enrollment profiles found."
        } else {
            Write-Warning "No Apple DEP enrollment profiles found."
        }
    }
}

#endregion

if ($Format -eq "table") {
    Write-Host "Script completed." -ForegroundColor Green
}