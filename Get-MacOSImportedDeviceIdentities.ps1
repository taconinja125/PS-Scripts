<#

.SYNOPSIS
This script lists imported macOS device identities using Microsoft Graph API

.DESCRIPTION
This script authenticates with Microsoft Graph API and retrieves all imported Apple device identities
where the platform is macOS for the available DEP onboarding settings in your Intune tenant.

.PARAMETER Style
Output format style. Valid values: xml, json, csv. Default is console output.

.PARAMETER OutFile
Path to output file. When specified, output is written to file instead of console.

.PARAMETER EnrollmentProfileId
Optional enrollment profile ID to filter devices. Only devices assigned to this enrollment profile will be returned.

.NOTES
Stay spicy

.EXAMPLE
.\Get-MacOSImportedDeviceIdentities.ps1
Lists all imported macOS device identities in console format

.EXAMPLE
.\Get-MacOSImportedDeviceIdentities.ps1 -Style json
Lists all imported macOS device identities in JSON format

.EXAMPLE
.\Get-MacOSImportedDeviceIdentities.ps1 -Style csv -OutFile "devices.csv"
Exports all imported macOS device identities to CSV file

.EXAMPLE
.\Get-MacOSImportedDeviceIdentities.ps1 -EnrollmentProfileId "12345678-1234-1234-1234-123456789012"
Lists only macOS devices assigned to the specified enrollment profile

#>

####################################################

param(
    [Parameter(Mandatory = $false, HelpMessage = "Output format style")]
    [ValidateSet('xml', 'json', 'csv')]
    [string]$Style,
    
    [Parameter(Mandatory = $false, HelpMessage = "Path to output file")]
    [string]$OutFile,
    
    [Parameter(Mandatory = $false, HelpMessage = "Enrollment profile ID to filter devices by")]
    [string]$EnrollmentProfileId
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

Function Get-MacOSImportedDeviceIdentities() {

    <#
    .SYNOPSIS
    This function is used to get a list of imported macOS device identities by DEP Token
    .DESCRIPTION
    The function connects to the Graph API Interface and gets a list of imported Apple device identities filtered for macOS platform
    .EXAMPLE
    Get-MacOSImportedDeviceIdentities -depOnboardingSettingId "12345678-1234-1234-1234-123456789012"
    Gets all imported macOS device identities for the specified DEP onboarding setting
    .NOTES
    NAME: Get-MacOSImportedDeviceIdentities
    #>

    [cmdletbinding()]

    param
    (
        [Parameter(Mandatory = $true)]
        $depOnboardingSettingId
    )

    $graphApiVersion = "beta"
    $Resource = "deviceManagement/depOnboardingSettings/$depOnboardingSettingId/importedAppleDeviceIdentities"

    try {

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($resource)"
        $allDevices = @()
        
        do {
            Write-Host "Retrieving page of devices from: $uri" -ForegroundColor Gray
            $response = Invoke-MgGraphRequest -Uri $uri -Method GET
            
            if ($response.value) {
                $allDevices += $response.value
                Write-Host "Retrieved $($response.value.Count) devices (Total so far: $($allDevices.Count))" -ForegroundColor Gray
            }
            
            # Check for next page
            $uri = $response.'@odata.nextLink'
            
        } while ($uri)
        
        Write-Host "Total devices retrieved: $($allDevices.Count)" -ForegroundColor Green
        
        # Filter for macOS devices only
        $macOSDevices = $allDevices | Where-Object { $_.platform -eq 'macOS' }
        Write-Host "macOS devices found: $($macOSDevices.Count)" -ForegroundColor Green
        
        return $macOSDevices

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

Write-Host "Authentication successful. Connected as: $($graphConnection.Account)" -ForegroundColor Green
Write-Host "Retrieving DEP onboarding settings..." -ForegroundColor Yellow
Write-Host

$depOnboardingSettings = Get-DEPOnboardingSettings

# Initialize data collection arrays
$allResults = @()

if ($depOnboardingSettings) {

    $settingsCount = @($depOnboardingSettings).count
    Write-Host "Found $settingsCount DEP onboarding setting(s)" -ForegroundColor Green
    Write-Host

    foreach ($setting in $depOnboardingSettings) {
        
        # Show progress for console output
        if (-not $OutFile -and -not $Style) {
            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host "DEP Token: $($setting.tokenName)" -ForegroundColor Cyan
            Write-Host "Token ID: $($setting.id)" -ForegroundColor Cyan
            Write-Host "================================================" -ForegroundColor Cyan
            Write-Host
        }

        Write-Host "Retrieving imported macOS device identities..." -ForegroundColor Yellow
        
        $macOSDevices = Get-MacOSImportedDeviceIdentities -depOnboardingSettingId $setting.id

        if ($macOSDevices) {
            
            $deviceCount = @($macOSDevices).count
            Write-Host "Found $deviceCount imported macOS device(s)" -ForegroundColor Green
            
            if (-not $OutFile -and -not $Style) {
                Write-Host ":"
                Write-Host
            }

            # Apply enrollment profile filter if specified
            if ($EnrollmentProfileId) {
                $macOSDevices = $macOSDevices | Where-Object { $_.requestedEnrollmentProfileId -eq $EnrollmentProfileId }
            }
            
            foreach ($device in $macOSDevices) {
                # Create structured data object for each device
                $deviceResult = [PSCustomObject]@{
                    TokenName             = $setting.tokenName
                    TokenId               = $setting.id
                    SerialNumber          = $device.serialNumber
                    Platform              = $device.platform
                    EnrollmentState       = $device.enrollmentState
                    IsSupervised          = $device.isSupervised
                    DiscoverySource       = $device.discoverySource
                    RequestedEnrollmentProfileId = $device.requestedEnrollmentProfileId
                    CreatedDateTime       = $device.createdDateTime
                    LastContactedDateTime = $device.lastContactedDateTime
                }
                
                $allResults += $deviceResult
                
                # Show console output if no structured output requested
                if (-not $OutFile -and -not $Style) {
                    Write-Host "  Serial Number: $($device.serialNumber)" -ForegroundColor White
                    Write-Host "  Platform: $($device.platform)" -ForegroundColor Gray
                    Write-Host "  Enrollment State: $($device.enrollmentState)" -ForegroundColor Gray
                    Write-Host "  Is Supervised: $($device.isSupervised)" -ForegroundColor Gray
                    Write-Host "  Discovery Source: $($device.discoverySource)" -ForegroundColor Gray
                    Write-Host "  Requested Profile ID: $($device.requestedEnrollmentProfileId)" -ForegroundColor Gray
                    Write-Host "  Created: $($device.createdDateTime)" -ForegroundColor Gray
                    Write-Host "  Last Contacted: $($device.lastContactedDateTime)" -ForegroundColor Gray
                    Write-Host
                }
            }

        }
        else {
            Write-Host "  No imported macOS device identities found for this token." -ForegroundColor Yellow
            if (-not $OutFile -and -not $Style) {
                Write-Host
            }
        }
    }

}
else {
    Write-Warning "No DEP onboarding settings found!"
    Write-Host
}

#endregion

####################################################

#region Output Handling

# Handle structured output (Style parameter or OutFile specified)
if ($Style -or $OutFile) {
    
    if ($allResults.Count -gt 0) {
        
        # Determine output format
        $outputContent = ""
        $outputFormat = if ($Style) { $Style } else { "json" } # Default to JSON for file output
        
        try {
            switch ($outputFormat.ToLower()) {
                "json" {
                    $outputContent = $allResults | ConvertTo-Json -Depth 10
                }
                "xml" {
                    $outputContent = $allResults | ConvertTo-Xml -As String -NoTypeInformation
                }
                "csv" {
                    $outputContent = $allResults | ConvertTo-Csv -NoTypeInformation | Out-String
                }
            }
            
            # Output to file or console
            if ($OutFile) {
                try {
                    # Ensure directory exists
                    $outDir = Split-Path -Parent $OutFile
                    if ($outDir -and -not (Test-Path $outDir)) {
                        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                    }
                    
                    # Write to file
                    $outputContent | Out-File -FilePath $OutFile -Encoding UTF8
                    Write-Host "Output written to: $OutFile" -ForegroundColor Green
                    Write-Host "Total devices exported: $($allResults.Count)" -ForegroundColor Green
                }
                catch {
                    Write-Error "Failed to write to file '$OutFile': $($_.Exception.Message)"
                }
            }
            else {
                # Output to console
                Write-Output $outputContent
            }
        }
        catch {
            Write-Error "Failed to format output as $outputFormat : $($_.Exception.Message)"
        }
    }
    else {
        $message = "No macOS device identities found to export."
        if ($OutFile) {
            Write-Host $message -ForegroundColor Yellow
        } else {
            Write-Output $message
        }
    }
}

#endregion

Write-Host "Script completed." -ForegroundColor Green