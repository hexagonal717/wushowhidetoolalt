# Function to check if the script is running as Administrator
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as Administrator, restart the script with elevated privileges
if (-not (Test-Admin)) {
    Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Define the path to SoftwareDistribution
$softwareDistributionPath = "C:\Windows\SoftwareDistribution"

# Stop related services to avoid conflicts
$services = @("wuauserv", "bits", "cryptsvc", "msiserver")

foreach ($service in $services) {
    try {
        Stop-Service -Name $service -Force -ErrorAction Stop
    } catch {
        Write-Host "Failed to stop service: $service"
    }
}

# Force take ownership and reset permissions on the folder and its contents
Write-Output "Taking full ownership of the folder..."
takeown /f $softwareDistributionPath /r /d y
icacls $softwareDistributionPath /grant administrators:F /t

# Retry mechanism to delete all files and folders inside SoftwareDistribution
$retryCount = 5
for ($i = 0; $i -lt $retryCount; $i++) {
    Get-ChildItem -Path $softwareDistributionPath -Recurse -Force | Remove-Item -Recurse -Force
    Start-Sleep -Seconds 2

    # Check if the directory is empty
    if (-not (Get-ChildItem -Path $softwareDistributionPath -Recurse -Force)) {
        Write-Host "All items deleted successfully."
        break
    } else {
        Write-Host "Retrying deletion... Attempt $($i + 1) of $retryCount."
    }
}

# Restore ownership to TrustedInstaller
Write-Output "Restoring ownership to TrustedInstaller..."
$trustedInstallerSID = "NT SERVICE\TrustedInstaller"
icacls $softwareDistributionPath /setowner $trustedInstallerSID /t

# Reset permissions to the default, restrictive settings
Write-Output "Resetting permissions to the default system settings..."
icacls $softwareDistributionPath /inheritance:r /t
icacls $softwareDistributionPath /grant:r "NT SERVICE\TrustedInstaller:(OI)(CI)(F)" /t
icacls $softwareDistributionPath /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)(F)" /t
icacls $softwareDistributionPath /grant:r "BUILTIN\Administrators:(OI)(CI)(RX)" /t
icacls $softwareDistributionPath /grant:r "BUILTIN\Users:(OI)(CI)(RX)" /t
icacls $softwareDistributionPath /grant:r "CREATOR OWNER:(OI)(CI)(IO)(F)" /t
icacls $softwareDistributionPath /grant:r "APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES:(OI)(CI)(RX)" /t
icacls $softwareDistributionPath /grant:r "APPLICATION PACKAGE AUTHORITY\ALL RESTRICTED APPLICATION PACKAGES:(OI)(CI)(RX)" /t

# Restart the stopped services
foreach ($service in $services) {
    try {
        Start-Service -Name $service -ErrorAction Stop
    } catch {
        Write-Host "Failed to start service: $service"
    }
}

# Define the path for the script to be copied
$scriptPath = "C:\HideOldGPUDriversFromWU.ps1"

# Define the keywords to search for in update titles
$hideKeywords = @("Intel", "AMD", "NVIDIA", "Advanced Micro Devices", "Display")

# Function to hide old GPU drivers from Windows Update
function Hide-OldGPUDrivers {
    Write-Host "Running HideOldGPUDriversFromWU logic..."

    # Import the PSWindowsUpdate module
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        try {
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber -ErrorAction Stop
        } catch {
            Write-Host "Failed to install PSWindowsUpdate module. Exiting script."
            exit
        }
    }
    Import-Module PSWindowsUpdate

    # Get the list of available updates
    $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot

    if ($updates) {
        # Process and hide matching updates
        foreach ($update in $updates) {
            $title = $update.Title

            # Check if the title contains any hideKeywords
            if ($hideKeywords | Where-Object { $title -match $_ }) {
                # Hide updates that match hideKeywords
                Hide-WindowsUpdate -Title $title -Confirm:$false
                Write-Host "Hidden update: $title"
            }
        }
        Write-Host "Old GPU drivers have been successfully hidden from Windows Update."
    } else {
        Write-Host "No old GPU drivers have been found in Windows Update."
    }
}

# Save the script content to the specified path
$scriptContent = @'
# Function to check if the script is running as Administrator
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as Administrator, restart the script with elevated privileges
if (-not (Test-Admin)) {
    Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    return
}

# Define the keywords to search for in update titles
$hideKeywords = @("Intel", "AMD", "NVIDIA", "Advanced Micro Devices", "Display")

# Import the PSWindowsUpdate module
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    try {
        Install-Module -Name PSWindowsUpdate -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Host "Failed to install PSWindowsUpdate module. Exiting script."
        exit
    }
}
Import-Module PSWindowsUpdate

# Run the HideUpdates logic
Write-Host "Running HideOldGPUDriversFromWU script..."

# Get the list of available updates
$updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot

if ($updates) {
    # Process and hide matching updates
    foreach ($update in $updates) {
        $title = $update.Title

        # Check if the title contains any hideKeywords
        if ($hideKeywords | Where-Object { $title -match $_ }) {
            # Hide updates that match hideKeywords
            Hide-WindowsUpdate -Title $title -Confirm:$false
            Write-Host "Hidden update: $title"
        }
    }
    Write-Host "Old GPU drivers have been successfully hidden from Windows Update."
} else {
    Write-Host "No old GPU drivers have been found in Windows Update."
}

# Automatically exit the script
exit
'@

Write-Host "Saving script content to $scriptPath..."
$scriptContent | Set-Content -Path $scriptPath -Force
Write-Host "Script saved."

# Create a scheduled task to run the script at every logon
$taskName = "HideGPUDriversFromWU"
$taskDescription = "Hide Old GPU Drivers from Windows Update on startup."
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File $scriptPath -WindowStyle Hidden"
$taskTrigger = New-ScheduledTaskTrigger -AtLogon
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

try {
    Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force
    Write-Host "Scheduled task '$taskName' has been created to run at logon."
} catch {
    Write-Host "Failed to create scheduled task. Exiting script."
    exit
}

# Run the logic to hide old GPU drivers directly within the script
Hide-OldGPUDrivers

# Exit the script automatically
exit
