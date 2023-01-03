# Install-Sysmon
Install-Sysmon installs and updates Sysmon and its configuration file. It is intended to be run periodically (e.g. via scheduled task) from a remote repository (e.g. a file share) to keep both the executable and configuration file up-to-date.

## How it works
If the Sysmon executable in the source folder is newer than the one residing on the system, the running version of Sysmon is uninstalled and the Sysmon executable in the source folder is called upon for installation. This check is done by a comparison of the "date modified" attribute on executables rather than by version number to a) conserve bandwidth and b) allow an administrator to redeploy an older version, should it ever be required. If the hash of the configuration file in the source folder differs to that of the one stored in the registry by Sysmon, the new configuration file is loaded. These checks are performed to minimise unnecessary invocations of Sysmon.

By placing the Sysmon executable and configuration file in the same folder as this script, this script can be invoked with no hardcoded file paths, or no parameters at all. By default, diagnostic information is logged to `C:\Windows\Temp\Install-Sysmon.log`.

Please note that this script calls Sysmon, reads attributes of its executable and reads its registry values. Some EDR solutions may have detection rules for this behaviour and treat it as suspicious, so consider adding exceptions for this script.

## Examples
Install or update Sysmon using default executable and config file names (`Sysmon.exe` and `sysmonconfig-export.xml` respectively) which reside
in the same folder as this script.

```
PS C:\> Install-Sysmon.ps1
```

Install or update Sysmon using the config file `sysmonconfig-export-dc.xml`, residing in the same folder as this script.

```
PS C:\> Install-Sysmon.ps1 -ConfigPath sysmonconfig-export-dc.xml
```

Install or update Sysmon using absolute file paths.

```
PS C:\> Install-Sysmon.ps1 -ExecutablePath \\corp.example.org\...\Sysmon\Bin\Sysmon.exe -ConfigPath \\corp.example.org\...\Sysmon\Conf\sysmonconfig-export.xml
```
