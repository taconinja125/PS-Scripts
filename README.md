# PS-Scripts

PowerShell scripts I've come up with for various purposes

## Table of Contents
- [Start-AssetInventory.ps1](#start-assetinventoryps1)
- [Get-WindowsUpdates.ps1](#get-windowsupdatesps1)

## Start-AssetInventory.ps1

A cross-platform PowerShell 7 script that generates comprehensive system information reports for both macOS and Windows environments. The script creates a JSON report containing detailed system, application, disk, and network information.

### Purpose

This script provides a standardized way to collect system information across different platforms by:
- Gathering detailed system specifications
- Inventorying installed applications
- Collecting disk space and encryption status
- Documenting network configuration
- Outputting all data in a structured JSON format

### Key Components

1. **System Information**
   - OS version and platform detection
   - Machine name and serial number
   - CPU specifications
   - RAM configuration

2. **Application Inventory**
   - Windows: Registry-based application detection
   - macOS: Application directory scanning
   - Version and publisher information

3. **Storage Information**
   - Disk space usage and availability
   - Encryption status (BitLocker/FileVault)
   - Drive mapping details

4. **Network Configuration**
   - Network adapter information
   - IP addressing and subnet details
   - Gateway configuration

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-OutFile` | String | `~\inventoryReport.json` | Specify the output path for the JSON report |

### Usage Examples

```powershell
# Generate report with default output location
Start-AssetInventory.ps1

# Specify custom output location
Start-AssetInventory.ps1 -OutFile "C:\Reports\inventory.json"
```

### Requirements
- PowerShell 7 or later
- Administrative privileges (Windows) or root access (macOS)

## Get-WindowsUpdates.ps1

A PowerShell script that automates the Windows Update process using the Windows Update Agent API. This script provides a flexible and programmatic way to search, download, and install Windows updates with detailed logging and error handling.

### Purpose

The script serves as a PowerShell implementation of Microsoft's Windows Update Agent API, allowing you to:
- Search for available Windows updates
- Filter updates based on various criteria
- Handle update EULAs automatically
- Download selected updates
- Install updates with proper error handling
- Manage system reboots when required
- Provide detailed logging of the entire process

### Key Components

1. **Update Search**
   - Uses Windows Update Agent API to search for applicable updates
   - Filters updates based on specified criteria
   - Handles both regular and optional updates

2. **Update Processing**
   - Checks for and handles update EULAs
   - Validates installation behavior requirements
   - Manages exclusive updates that must be installed alone
   - Tracks update dependencies

3. **Download and Installation**
   - Downloads selected updates with progress tracking
   - Installs updates with proper error handling
   - Manages reboot requirements
   - Provides detailed logging of all operations

4. **Logging System**
   - Comprehensive logging of all operations
   - Timestamps for all events
   - Different log levels (INFO, WARNING, ERROR)
   - Configurable log file location

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-IncludeOptionalUpdates` | Switch | `$false` | Include optional updates in the search results |
| `-NoDownload` | Switch | `$false` | Skip downloading updates, only perform search |
| `-NoInstall` | Switch | `$false` | Skip installing updates, only perform search and download |
| `-ShowDetails` | Switch | `$false` | Display detailed information about each update |
| `-Reboot` | Boolean | `$false` | Automatically reboot system if required after installation |
| `-LogPath` | String | `"C:\ECS\WindowsUpdates.log"` | Path to the log file |
| `-AutoAcceptEULA` | Switch | `$false` | Automatically accept update EULAs |
| `-Force` | Switch | `$false` | Reserved for future use to force operations |

### Examples

1. Basic usage - Search, download, and install updates:
```powershell
.\Get-WindowsUpdates.ps1
```

2. Include optional updates and show details:
```powershell
.\Get-WindowsUpdates.ps1 -IncludeOptionalUpdates -ShowDetails
```

3. Search and download only (no installation):
```powershell
.\Get-WindowsUpdates.ps1 -NoInstall
```

4. Full automation with auto-reboot and EULA acceptance:
```powershell
.\Get-WindowsUpdates.ps1 -AutoAcceptEULA -Reboot $true
```

5. Custom log path and search only:
```powershell
.\Get-WindowsUpdates.ps1 -LogPath "C:\Logs\WindowsUpdates.log" -NoDownload
```

### Log File Format

The log file contains entries in the following format:
```
[Timestamp UTC] -- [Level] Message
```

Example log entries:
```
2025-01-17 20:30:00Z -- [INFO   ] Beginning Windows Update search
2025-01-17 20:30:05Z -- [INFO   ] Found 3 applicable updates
2025-01-17 20:30:10Z -- [WARNING] Update KB5025841 requires EULA acceptance
2025-01-17 20:31:00Z -- [INFO   ] Successfully installed 3 updates
```

### Error Handling

The script includes comprehensive error handling for common scenarios:
- COM object initialization failures
- Network connectivity issues
- Update download failures
- Installation errors
- EULA acceptance failures
- Reboot requirements

### Requirements

- Windows PowerShell 5.1 or later
- Administrative privileges
- Internet connectivity for downloading updates
- Windows Update service must be running
