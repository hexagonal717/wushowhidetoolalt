# Function to check if the script is running as Administrator
function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if the script is running as Administrator
if (-not (Test-IsAdministrator)) {
    Write-Host "This script needs to be run as an Administrator."
    Write-Host "Trying to restart with elevated privileges..."
    Start-Process powershell -ArgumentList "$($MyInvocation.MyCommand.Definition)" -Verb RunAs
    exit
}

# Define the sageset number and format it with leading zeros
$sagesetNumber = 500
$formattedNumber = $sagesetNumber.ToString("D4")  # Formats the number as four digits
$stateFlagsName = "StateFlags$formattedNumber"

# Define the path to the registry key for VolumeCaches
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

# Define the list of specific cleanup options to modify
$cleanupOptions = @(
    "Delivery Optimization Files",
    "Device Driver Packages",
    "Temporary Files",
    "Windows Error Reporting Files",
    "Temporary Setup Files",
    "Update Cleanup"
)

# Set the StateFlags DWORD value for the specified sageset number
foreach ($option in $cleanupOptions) {
    $optionPath = "$regPath\$option"
    if (Test-Path $optionPath) {
        # Set the StateFlags DWORD for the formatted sageset number
        Set-ItemProperty -Path $optionPath -Name $stateFlagsName -Value 2
    } else {
        Write-Host "Registry path not found for option: $option"
    }
}

# Run the cleanmgr command with the specified sageset number
try {
    Start-Process cleanmgr -ArgumentList "/sagerun:$sagesetNumber" -Wait -NoNewWindow
    Write-Host "cleanmgr /sagerun:$sagesetNumber has been executed."
} catch {
    Write-Host "Failed to run cleanmgr. Error: $_"
}

# Remove the StateFlags DWORD value for the specified sageset number
foreach ($option in $cleanupOptions) {
    $optionPath = "$regPath\$option"
    if (Test-Path $optionPath) {
        # Remove the StateFlags DWORD if it exists
        Remove-ItemProperty -Path $optionPath -Name $stateFlagsName -ErrorAction SilentlyContinue
    }
}

Write-Host "StateFlags values for sageset number $sagesetNumber have been removed for specified cleanup options."

# Disable Delivery Optimization by setting the Start value of the DoSvc service to 4
Write-Host "Disabling Delivery Optimization..."

$deliveryOptimizationServicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc"
if (Test-Path $deliveryOptimizationServicePath) {
    Set-ItemProperty -Path $deliveryOptimizationServicePath -Name "Start" -Value 4
    Write-Host "Delivery Optimization service has been disabled."
} else {
    Write-Host "Delivery Optimization service registry path not found."
}

# Continue with the rest of the script

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

# Enable Delivery Optimization service by setting the Start value of the DoSvc service to 2
Write-Host "Enabling Delivery Optimization..."

$deliveryOptimizationServicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc"
if (Test-Path $deliveryOptimizationServicePath) {
    Set-ItemProperty -Path $deliveryOptimizationServicePath -Name "Start" -Value 2
    Write-Host "Delivery Optimization service has been enabled."
} else {
    Write-Host "Delivery Optimization service registry path not found."
}

# Define the path for the script to be copied
$scriptPath = "C:\HideOldGPUDriversFromWU.ps1"

# Define the keywords to search for in update titles
$hideKeywords = @("NVIDIA - Display", "Advanced Micro Devices, Inc. - Display", "NVIDIA", "ATI Technologies Inc. - Display", "Display","Intel Corporation - Display","nVidia - Display")

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
                Write-Host ""
                Write-Host "Hiding Old GPU drivers..."
                Hide-WindowsUpdate -Title $title -Confirm:$false
                Write-Host ""
                Write-Host "Hidden update: $title"
            }
        }
        Write-Host ""
        Write-Host "Old GPU drivers have been successfully hidden from Windows Update."
    } else {
        Write-Host ""
        Write-Host "No old GPU drivers have been found in Windows Update."
    }
}

# Save the script content to the specified path
$scriptContent = @'
# Function to check if the script is running as Administrator
function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if the script is running as Administrator
if (-not (Test-IsAdministrator)) {
    Write-Host "This script needs to be run as an Administrator."
    Write-Host "Trying to restart with elevated privileges..."
    Start-Process powershell -ArgumentList "$($MyInvocation.MyCommand.Definition)" -Verb RunAs
    return
}

# Define the keywords to search for in update titles
$hideKeywords = @("NVIDIA - Display", "Advanced Micro Devices, Inc. - Display", "NVIDIA", "ATI Technologies Inc. - Display", "Display","Intel Corporation - Display","nVidia - Display")

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

# Create a scheduled task with updated settings
$taskSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -IdleDuration (New-TimeSpan -Minutes 10) `
    -IdleWaitTimeout (New-TimeSpan -Minutes 30) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

# Define the task details
$taskName = "HideGPUDriversFromWU"
$taskDescription = "Hide Old GPU Drivers from Windows Update on startup."
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -WindowStyle Hidden"
$taskTrigger = New-ScheduledTaskTrigger -AtLogon
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create and register the scheduled task
try {
    Register-ScheduledTask -TaskName $taskName `
        -Description $taskDescription `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Principal $taskPrincipal `
        -Settings $taskSettings `
        -Force
    Write-Host "Scheduled task '$taskName' has been created to run at logon."
} catch {
    Write-Host "Failed to create scheduled task. Error details:"
    Write-Host $_.Exception.Message
    exit
}

# Run the logic to hide old GPU drivers directly within the script
Hide-OldGPUDrivers

# Keep the script running until the user closes it manually
Write-Host ""
Write-Host "Press Enter to exit..."
Read-Host
