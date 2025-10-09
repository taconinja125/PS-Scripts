<#

.SYNOPSIS
This script updates Apple device enrollment profile assignments using Microsoft Graph API

.DESCRIPTION
This script authenticates with Microsoft Graph API and updates device enrollment profile assignments
for Apple devices (iOS, iPadOS, and macOS) in your Intune tenant. You can provide device serial numbers
either through an input file (CSV, JSON, or XML) or as comma-separated values via the SerialNumber parameter.

.PARAMETER InputFile
Path to a file containing device serial numbers. Supported formats: CSV, JSON, XML.
For CSV files, the script expects a column named 'SerialNumber' or will use the first column.
For JSON files, the script expects an array of serial numbers or objects with serialNumber properties.
For XML files, the script expects elements containing serial numbers.
Cannot be used together with SerialNumber parameter.

.PARAMETER SerialNumber
One or more device serial numbers separated by commas.
Cannot be used together with InputFile parameter.

.PARAMETER ProfileId
The enrollment profile ID to assign to the specified devices. This is required.

.NOTES
Stay spicy

.EXAMPLE
.\Update-AppleDepProfileAssignment.ps1 -SerialNumber "ABC123,DEF456" -ProfileId "12345678-1234-1234-1234-123456789012"
Updates the enrollment profile assignment for Apple devices with serial numbers ABC123 and DEF456

.EXAMPLE
.\Update-AppleDepProfileAssignment.ps1 -InputFile "devices.csv" -ProfileId "12345678-1234-1234-1234-123456789012"
Updates the enrollment profile assignment for Apple devices listed in the CSV file

.EXAMPLE
.\Update-AppleDepProfileAssignment.ps1 -InputFile "devices.json" -ProfileId "12345678-1234-1234-1234-123456789012"
Updates the enrollment profile assignment for Apple devices listed in the JSON file

.EXAMPLE
.\Update-AppleDepProfileAssignment.ps1 -SerialNumber "ABC123" -ProfileId "12345678-1234-1234-1234-123456789012" -WhatIf
Shows what would happen without making actual changes

#>

[CmdletBinding(DefaultParameterSetName='SerialNumbers', SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'InputFile', HelpMessage = "Path to file containing device serial numbers (CSV, JSON, or XML)")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "File '$_' not found."
        }
        $extension = [System.IO.Path]::GetExtension($_).ToLower()
        if ($extension -notin @('.csv', '.json', '.xml')) {
            throw "File must have .csv, .json, or .xml extension."
        }
        return $true
    })]
    [string]$InputFile,

    [Parameter(Mandatory = $true, ParameterSetName = 'SerialNumbers', HelpMessage = "One or more device serial numbers separated by commas")]
    [ValidateNotNullOrEmpty()]
    [string]$SerialNumber,

    [Parameter(Mandatory = $true, HelpMessage = "The enrollment profile ID to assign to devices")]
    [ValidateNotNullOrEmpty()]
    [string]$ProfileId
)

####################################################

# Script variables
$script:ErrorActionPreference = "Stop"
$script:ProgressPreference = "Continue"

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
            Write-Verbose "Calling URI: $uri"
            (Invoke-MgGraphRequest -Uri $uri -Method Get)

        }

        else {

            $Resource = "deviceManagement/depOnboardingSettings/"
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
            Write-Verbose "Calling URI: $uri"
            (Invoke-MgGraphRequest -Uri $uri -Method Get).value

        }

    }

    catch {

        $ex = $_.Exception
        Write-Error "Error occurred: $($ex.Message)"

        if ($ex.Response) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd();
                Write-Error "Response content:`n$responseBody"
                Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
            }
            catch {
                Write-Error "Could not read error response: $($_.Exception.Message)"
            }
        }
        else {
            Write-Error "No HTTP response available. This may be a network or authentication issue."
        }
        throw

    }

}

####################################################

Function Update-DeviceProfileAssignment {

    <#
    .SYNOPSIS
    This function updates Apple device enrollment profile assignments using Microsoft Graph API
    .DESCRIPTION
    The function connects to the Graph API Interface and updates device enrollment profile assignments for the specified Apple devices
    .EXAMPLE
    Update-DeviceProfileAssignment -DepOnboardingSettingId "token-id" -ProfileId "profile-id" -DeviceSerialNumbers @("ABC123", "DEF456")
    Updates the enrollment profile assignment for the specified Apple devices
    .NOTES
    NAME: Update-DeviceProfileAssignment
    #>

    [cmdletbinding(SupportsShouldProcess)]

    param(
        [Parameter(Mandatory = $true)]
        [string]$DepOnboardingSettingId,

        [Parameter(Mandatory = $true)]
        [string]$ProfileId,

        [Parameter(Mandatory = $true)]
        [string[]]$DeviceSerialNumbers
    )

    $graphApiVersion = "beta"
    $Resource = "deviceManagement/depOnboardingSettings/$DepOnboardingSettingId/enrollmentProfiles('$ProfileId')/updateDeviceProfileAssignment"

    try {

        # Clean up serial numbers (remove spaces and empty entries)
        $cleanSerialNumbers = $DeviceSerialNumbers | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

        if ($cleanSerialNumbers.Count -eq 0) {
            Write-Warning "No valid serial numbers provided."
            return
        }

        Write-Host "Preparing to update enrollment profile assignment for $($cleanSerialNumbers.Count) Apple device(s)..." -ForegroundColor Yellow
        Write-Host "DEP Token ID: $DepOnboardingSettingId" -ForegroundColor Gray
        Write-Host "Profile ID: $ProfileId" -ForegroundColor Gray
        Write-Host "Serial Numbers: $($cleanSerialNumbers -join ', ')" -ForegroundColor Gray
        Write-Host

        # Ensure deviceIds is always an array, even for single device
        $JSON = @{ "deviceIds" = @($cleanSerialNumbers) } | ConvertTo-Json -Compress

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
        Write-Verbose "Calling URI: $uri"
        Write-Verbose "Request body: $JSON"

        if ($PSCmdlet.ShouldProcess("$($cleanSerialNumbers.Count) Apple device(s)", "Update enrollment profile assignment to $ProfileId")) {

            $response = Invoke-MgGraphRequest -Uri $uri -Method Post -Body $JSON -ContentType "application/json"
            $response

            Write-Host "Success: " -ForegroundColor Green -NoNewline
            Write-Host "Profile assignment updated for $($cleanSerialNumbers.Count) Apple device(s)!"
            Write-Host

            return $true
        }
        else {
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            return $false
        }

    }

    catch {

        Write-Host
        $ex = $_.Exception
        Write-Error "Error occurred: $($ex.Message)"

        # Enhanced error reporting for Microsoft Graph errors
        if ($_.ErrorDetails) {
            Write-Host "API Error Details:" -ForegroundColor Red
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }

        if ($ex.Response) {
            Write-Host "HTTP Status: $($ex.Response.StatusCode) - $($ex.Response.ReasonPhrase)" -ForegroundColor Red
        }

        throw

    }

}

####################################################

Function Get-SerialNumbersFromFile {

    <#
    .SYNOPSIS
    This function extracts device serial numbers from various file formats
    .DESCRIPTION
    The function parses CSV, JSON, and XML files to extract device serial numbers
    .EXAMPLE
    Get-SerialNumbersFromFile -FilePath "devices.csv"
    Extracts serial numbers from a CSV file
    .NOTES
    NAME: Get-SerialNumbersFromFile
    #>

    [cmdletbinding()]

    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {

        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        $serialNumbers = @()

        Write-Host "Parsing file: $FilePath" -ForegroundColor Yellow

        switch ($extension) {
            ".csv" {
                Write-Verbose "Processing CSV file..."
                $csvData = Import-Csv -Path $FilePath

                # Look for common serial number column names
                $serialNumberColumn = $null
                $possibleColumns = @('SerialNumber', 'Serial', 'SN', 'DeviceSerialNumber', 'Device_Serial_Number')

                foreach ($column in $possibleColumns) {
                    if ($csvData | Get-Member -Name $column -MemberType NoteProperty) {
                        $serialNumberColumn = $column
                        break
                    }
                }

                if ($serialNumberColumn) {
                    Write-Host "Found serial number column: $serialNumberColumn" -ForegroundColor Green
                    $serialNumbers = $csvData | ForEach-Object { $_.$serialNumberColumn } | Where-Object { $_ -and $_.Trim() -ne "" }
                }
                else {
                    # If no specific column found, try to use the first column
                    $firstColumn = ($csvData | Get-Member -MemberType NoteProperty | Select-Object -First 1).Name
                    if ($firstColumn) {
                        Write-Host "No serial number column found. Using first column: $firstColumn" -ForegroundColor Yellow
                        $serialNumbers = $csvData | ForEach-Object { $_.$firstColumn } | Where-Object { $_ -and $_.Trim() -ne "" }
                    }
                    else {
                        throw "Unable to determine serial number column in CSV file."
                    }
                }
            }

            ".json" {
                Write-Verbose "Processing JSON file..."
                $jsonContent = Get-Content -Path $FilePath -Raw | ConvertFrom-Json

                if ($jsonContent -is [Array]) {
                    # Handle array of strings or objects
                    foreach ($item in $jsonContent) {
                        if ($item -is [string]) {
                            $serialNumbers += $item
                        }
                        elseif ($item.SerialNumber) {
                            $serialNumbers += $item.SerialNumber
                        }
                        elseif ($item.serialNumber) {
                            $serialNumbers += $item.serialNumber
                        }
                        elseif ($item.Serial) {
                            $serialNumbers += $item.Serial
                        }
                    }
                }
                elseif ($jsonContent.SerialNumbers) {
                    # Handle object with SerialNumbers property
                    $serialNumbers = $jsonContent.SerialNumbers
                }
                elseif ($jsonContent.serialNumbers) {
                    # Handle object with serialNumbers property
                    $serialNumbers = $jsonContent.serialNumbers
                }
                else {
                    throw "Unable to parse serial numbers from JSON file. Expected array of strings/objects with SerialNumber property."
                }
            }

            ".xml" {
                Write-Verbose "Processing XML file..."
                [xml]$xmlContent = Get-Content -Path $FilePath

                # Try different XML structures
                $serialNumberNodes = $xmlContent.SelectNodes("//SerialNumber") +
                                   $xmlContent.SelectNodes("//serialNumber") +
                                   $xmlContent.SelectNodes("//Serial") +
                                   $xmlContent.SelectNodes("//Device/SerialNumber") +
                                   $xmlContent.SelectNodes("//Device/Serial")

                if ($serialNumberNodes.Count -gt 0) {
                    $serialNumbers = $serialNumberNodes | ForEach-Object { $_.InnerText } | Where-Object { $_ -and $_.Trim() -ne "" }
                }
                else {
                    throw "Unable to find serial number elements in XML file. Expected elements like <SerialNumber>, <Serial>, or <Device><SerialNumber>."
                }
            }

            default {
                throw "Unsupported file format: $extension"
            }
        }

        # Clean up serial numbers
        $cleanSerialNumbers = $serialNumbers | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne "" } | Sort-Object -Unique

        Write-Host "Found $($cleanSerialNumbers.Count) unique serial number(s)" -ForegroundColor Green

        if ($cleanSerialNumbers.Count -eq 0) {
            throw "No serial numbers found in file."
        }

        return $cleanSerialNumbers
    }

    catch {
        Write-Error "Error parsing file '$FilePath': $($_.Exception.Message)"
        throw
    }
}

####################################################

#region Authentication

Write-Host

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

####################################################

#region Main Script Logic

try {
    # Get device serial numbers based on parameter set
    $deviceSerialNumbers = @()

    if ($PSCmdlet.ParameterSetName -eq 'InputFile') {
        Write-Host "Using input file: $InputFile" -ForegroundColor Cyan
        $deviceSerialNumbers = Get-SerialNumbersFromFile -FilePath $InputFile
    }
    else {
        Write-Host "Using provided serial numbers: $SerialNumber" -ForegroundColor Cyan
        $deviceSerialNumbers = $SerialNumber -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        Write-Host "Found $($deviceSerialNumbers.Count) serial number(s)" -ForegroundColor Green
    }

    if ($deviceSerialNumbers.Count -eq 0) {
        Write-Error "No valid serial numbers provided."
        exit 1
    }

    Write-Host
    Write-Host "Retrieving DEP onboarding settings..." -ForegroundColor Yellow

    # Get DEP onboarding settings
    $depOnboardingSettings = Get-DEPOnboardingSettings

    if (-not $depOnboardingSettings) {
        Write-Error "No DEP onboarding settings found. Please ensure DEP tokens are configured in your tenant."
        exit 1
    }

    $settingsCount = @($depOnboardingSettings).Count
    Write-Host "Found $settingsCount DEP onboarding setting(s)" -ForegroundColor Green

    # Handle single or multiple DEP tokens
    $selectedDepSetting = $null

    if ($settingsCount -eq 1) {
        $selectedDepSetting = $depOnboardingSettings
        Write-Host "Using DEP token: $($selectedDepSetting.tokenName)" -ForegroundColor Green
    }
    else {
        Write-Host
        Write-Host "Multiple DEP tokens found. Please select which token to use:" -ForegroundColor Yellow

        for ($i = 0; $i -lt $depOnboardingSettings.Count; $i++) {
            Write-Host "$($i + 1). $($depOnboardingSettings[$i].tokenName) (ID: $($depOnboardingSettings[$i].id))" -ForegroundColor White
        }

        do {
            $selection = Read-Host "Select token (1-$settingsCount)"
            $selectionInt = 0

            if ([int]::TryParse($selection, [ref]$selectionInt) -and $selectionInt -ge 1 -and $selectionInt -le $settingsCount) {
                $selectedDepSetting = $depOnboardingSettings[$selectionInt - 1]
                Write-Host "Selected: $($selectedDepSetting.tokenName)" -ForegroundColor Green
                break
            }
            else {
                Write-Host "Invalid selection. Please enter a number between 1 and $settingsCount." -ForegroundColor Red
            }
        } while ($true)
    }

    Write-Host
    Write-Host "DEP Token ID: $($selectedDepSetting.id)" -ForegroundColor Gray
    Write-Host "Profile ID: $ProfileId" -ForegroundColor Gray
    Write-Host "Device count: $($deviceSerialNumbers.Count)" -ForegroundColor Gray
    Write-Host

    # Update device profile assignments
    $success = Update-DeviceProfileAssignment -DepOnboardingSettingId $selectedDepSetting.id -ProfileId $ProfileId -DeviceSerialNumbers $deviceSerialNumbers

    if ($success) {
        Write-Host "Profile assignment update completed successfully!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Warning "Profile assignment update was not completed."
        exit 1
    }
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

#endregion

####################################################

Write-Host "Script completed." -ForegroundColor Green