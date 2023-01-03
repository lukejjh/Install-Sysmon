#Requires -RunAsAdministrator
<#
   
   .SYNOPSIS
      Installs and updates Sysmon and its configuration file.

   .DESCRIPTION
      Install-Sysmon installs and updates Sysmon and its configuration file. It is intended to be run periodically (e.g. via scheduled task)
      from a remote repository (e.g. a file share) to keep both the executable and configuration file up-to-date.
      
      If the Sysmon executable in the source folder is newer than the one residing on the system, the running version of Sysmon is uninstalled
      and the Sysmon executable in the source folder is called upon for installation. This check is done by a comparison of the "date modified"
      attribute on executables rather than by version number to a) conserve bandwidth and b) allow an administrator to redeploy an older version,
      should it ever be required. If the hash of the configuration file in the source folder differs to that of the one stored in the registry
      by Sysmon, the new configuration file is loaded. These checks are performed to minimise unnecessary invocations of Sysmon.
      
      By placing the Sysmon executable and configuration file in the same folder as this script, this script can be invoked with no hardcoded
      file paths, or no parameters at all. By default, diagnostic information is logged to C:\Windows\Temp\Install-Sysmon.log.

      Please note that this script calls Sysmon, reads attributes of its executable and reads its registry values. Some EDR solutions may have
      detection rules for this behaviour and treat it as suspicious, so consider adding exceptions for this script.

   .EXAMPLE
      Install or update Sysmon using default executable and config file names (Sysmon.exe and sysmonconfig-export.xml respectively) which reside
      in the same folder as this script.

      PS C:\> Install-Sysmon.ps1

   .EXAMPLE
      Install or update Sysmon using the config file sysmonconfig-export-dc.xml, residing in the same folder as this script.

      PS C:\> Install-Sysmon.ps1 -ConfigPath sysmonconfig-export-dc.xml

   .EXAMPLE
      Install or update Sysmon using absolute file paths.

      PS C:\> Install-Sysmon.ps1 -ExecutablePath \\corp.example.org\...\Sysmon\Bin\Sysmon.exe -ConfigPath \\corp.example.org\...\Sysmon\Conf\sysmonconfig-export.xml
   
#>

<#PSScriptInfo
   
   .VERSION
      0.1
   
   .AUTHOR
      Luke Humberdross <luke@humberdross.com>
   
   .PROJECTURI
      https://github.com/lukejjh/Install-Sysmon
   
#>

[CmdletBinding()]

Param (
  [Parameter()]
  [string]$ExecutablePath,

  [Parameter()]
  [string]$ConfigPath,

  [Parameter()]
  [string[]]$LogPath,

  [Parameter()]
  [ValidateSet("None", "Debug", "Info", "Warn", "Error")]
  [string]$LogLevel = "Info",

  [Parameter()]
  [switch]$Uninstall,

  [Parameter()]
  [switch]$ForceInstall,

  [Parameter()]
  [switch]$ForceConfig
)

$ErrorActionPreference = "Stop"

enum LogLevel {
  None  = -1
  Debug = 0
  Info  = 1
  Warn  = 2
  Error = 3
}

$Files = @{
  "Executable" = @{
    "DefaultName" = "Sysmon.exe"
    "Path"        = $ExecutablePath
  }
  "Config" = @{
    "DefaultName" = "sysmonconfig-export.xml"
    "Path"        = $ConfigPath
  }
}

$ScriptName = $MyInvocation.MyCommand.Name -replace "\.[^\.]*$"
$SysmonName = [System.IO.Path]::GetFileNameWithoutExtension(@(
  if ($Files["Executable"]["Path"]) {
    $Files["Executable"]["Path"]
  } else {
    $Files["Executable"]["DefaultName"]
  }
))

function Write-Log {
  Param (
    [Parameter(Mandatory, Position=0)]
    [string]$Message,

    [Parameter()]
    [ValidateSet("Debug", "Info", "Warn", "Error")]
    [string]$Level = "Debug"
  )

  if ([LogLevel]$LogLevel -ne [LogLevel]"None" -and [LogLevel]$Level -ge [LogLevel]$LogLevel) {
    $LogString = "{0} - {1} - {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $Message
    Write-Host $LogString
    $LogPath | ForEach-Object {
      try { $LogString | Out-File -FilePath $_ -Append } catch { }
    }
  }
}

function Invoke-Sysmon {
  Param (
    [Parameter()]
    [string]$FilePath = $SysmonName,

    [Parameter(Mandatory)]
    [string]$Arguments
  )

  Start-Process -FilePath $FilePath -ArgumentList @("-accepteula", $Arguments) -Wait -NoNewWindow
}

if (!$PSBoundParameters.ContainsKey("LogPath")) {
  $LogPath = Join-Path -Path ([System.Environment]::GetEnvironmentVariable("TEMP", "Machine")) -ChildPath "${ScriptName}.log"
}

Write-Log -Level Debug -Message "${ScriptName} has started. Logging to $($LogPath -join ", ")"

if ($Uninstall) {
  Write-Log -Level Info -Message "Uninstalling Sysmon."
  Invoke-Sysmon -Arguments "-u"
  Exit
}

# Locate files.
$Files.GetEnumerator() | ForEach-Object {
  if ($_.Value["Path"]) {
    Write-Log -Level Debug -Message "$($_.Key): Using supplied value: `"$($_.Value["Path"])`"."
    $TryPath = $_.Value["Path"]
  } else {
    Write-Log -Level Debug -Message "$($_.Key): Using default value `"$($_.Value["DefaultName"])`"."
    $TryPath = $_.Value["DefaultName"]
  }

  if ([System.IO.Path]::IsPathRooted($TryPath)) {
    if (Test-Path -Path $TryPath) {
      Write-Log -Level Debug -Message "$($_.Key): Absolute file path exists."
      $_.Value["Path"] = $TryPath
    } else {
      Write-Log -Level Error -Message "$($_.Key): Absolute file path doesn't exist. Exiting."
      Exit 1
    }
  } else {
    if (Test-Path ($p = Join-Path -Path ((Get-Location).Path -replace "^Microsoft\.PowerShell\.Core\\FileSystem::") -ChildPath $TryPath)) {
      Write-Log -Level Debug -Message "$($_.Key): Relative file path found in working directory (`"${p}`")."
      $_.Value["Path"] = $p
    }
    elseif (Test-Path ($p = Join-Path -Path $PSScriptRoot -ChildPath $TryPath)) {
      Write-Log -Level Debug -Message "$($_.Key): Relative file path found in script directory (`"${p}`")."
      $_.Value["Path"] = $p
    }
    else {
      Write-Log -Level Error -Message "$($_.Key): Relative file path could not be located. Exiting."
      Exit 1
    }
  }
}

$SysmonName      = [System.IO.Path]::GetFileNameWithoutExtension($Files["Executable"]["Path"])
$SysmonSrvRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\${SysmonName}"
$SysmonDrvRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\SysmonDrv"
$SysmonService   = Get-Service -Name $SysmonName -ErrorAction SilentlyContinue
$SysmonInstalled = $SysmonService.Length -gt 0

if ($SysmonInstalled) {
  Write-Log -Level Debug -Message "Sysmon service is already installed."

  if ($SysmonService.Status -ne "Running") {
    Write-Log -Level Warn -Message "Sysmon service is not running."
  }

  if ($SysmonService.StartType -ne "Automatic") {
    Write-Log -Level Warn -Message "Sysmon service startup type is not set to Automatic."
  }

  try {
    $SysmonImagePath = Get-ItemPropertyValue -Path $SysmonSrvRegKey -Name "ImagePath"
  }
  catch {
    Write-Log -Level Error -Message "Sysmon ImagePath registry value not found. Exiting."
    Exit 1
  }

  if ((Get-Item $Files["Executable"]["Path"]).LastWriteTime -gt (Get-Item -Path $SysmonImagePath).LastWriteTime) {
    Write-Log -Level Info -Message "Source executable is newer than current one on system. Uninstalling Sysmon."
    Invoke-Sysmon -Arguments "-u"
    $SysmonInstalled = $false
  }
}

if ($SysmonInstalled) {
  try {
    $SysmonConfigHashRegVal    = Get-ItemPropertyValue -Path "${SysmonDrvRegKey}\Parameters" -Name "ConfigHash" -ErrorAction Stop
    $SysmonConfigHashAlgorithm = ($SysmonConfigHashRegVal -split "=")[0]
    $SysmonConfigHashHash      = ($SysmonConfigHashRegVal -split "=")[1]
    $SysmonConfigHashExists    = $true
  }
  catch {
    $SysmonConfigHashExists    = $false
  }

  if ($SysmonConfigHashExists) {
    if ((Get-FileHash -Path $Files["Config"]["Path"] -Algorithm $SysmonConfigHashAlgorithm).Hash -eq $SysmonConfigHashHash) {
      Write-Log -Level Debug -Message "Current config hash matches source config hash. No update required."
      $SysmonConfigUpdateRequired = $false
    } else {
      Write-Log -Level Info -Message "Current config hash differs from source config hash. Updating config."
      $SysmonConfigUpdateRequired = $true
    }
  } else {
    Write-Log -Level Info -Message "No config hash found. Updating config."
    $SysmonConfigUpdateRequired = $true
  }

  if ($SysmonConfigUpdateRequired) {
    Invoke-Sysmon -FilePath $Files["Executable"]["Path"] -Arguments "-c `"$($Files["Config"]["Path"])`"" # TODO: If updating config using newer source exec, will exec update?
  }
}
else {
  Write-Log -Level Info -Message "Installing Sysmon."
  Invoke-Sysmon -FilePath $Files["Executable"]["Path"] -Arguments "-i `"$($Files["Config"]["Path"])`""
}

Write-Log -Level Debug -Message "${ScriptName} has finished."

# TODO: Log Sysmon.exe output to log.