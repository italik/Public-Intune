# Managed SOC Agent deploy script
# PowerShell

# 03/11/19 - updated for installer deployment
# 09/09/20 - updated for verification checks
# 11/12/20 - localization improvements

# PowerShell script taken from RocketCyber, but slightly tweaked to fit our needs :)
# We have centralised this script so that we can make changes globally, and then if an update is required we can change it one place and all of our customers that reference this script will get the latest version
# We download this script using another PowerShell script in Intune, and then run execute it
# We actually set the required license key as part of the Intune package, so that we can reuse these scripts anywhere! Pretty useful!

. C:\Tools\IntunePSLibrary\IKL_PS_Library.PS1 -ApplicationName "RocketCyber" -PackageAuthor "Robert Milner" -Version "1.0"

param (
    [Parameter( Mandatory=$true )]
    [string]$license_key
)

$url = "https://app.rocketcyber.com/"
$agent_setup_url = "$($url)/api/customers/$($license_key)/supports/agent-setup.exe"
$service_name = "rocketagent"
$agent_name = "RocketAgent"
$ini_file = "$env:programfiles\rocketagent\rocketagent.ini"



function download_file($file_url, $save_to_path) {

    LogScreen "Starting Download"
    (New-Object System.Net.WebClient).DownloadFile($file_url,$save_to_path)
    LogScreen "Download Completed"

    if (Test-Path $save_to_path) {
        return $true
    }
    return $false
}


function is_running() {

    $sService = Get-Service -Name $service_name
    if ($sService.Status -ne "Running") {
        return $false
    }

    return $true

}

function create_ini() {

    if (Test-Path $ini_file) {
        Remove-Item -Path $ini_file        
    }

    Add-Content -Path $ini_file -Value "url=$url"
    Add-Content -Path $ini_file -Value "license_key=$license_key"   

}

function verify_ini() {

    # check if the .ini file exists
    $file_exists = Test-Path $ini_file
    if ($file_exists -ne $true) {
        return $false
    }

    # read text file                        # find line beginning license_key=
    $license_line = Get-Content -Path $ini_file | Where-Object { $_ -match 'license_key=' }
    if ($license_line -eq $nul -or $license_line -eq "") { 
        LogScreen "Get-Content failed to get license_key"
        return $false 
    }
    $url_line = Get-Content -Path $ini_file | Where-Object { $_ -match 'url=' }
    if ($url_line -eq $nul -or $url_line -eq "") { 
        LogScreen "Get-Content failed to get license_key"
        return $false 
    }

    # split on = symbol and take second item
    $license_test = $license_line.Split('=')[1]
    if ($license_test -eq $nul -or  $license_test -eq "") {
        # license_key is empty / not set
        LogScreen "license_key is missing in Configuration"
        return $false

    } else {
        LogScreen "found license_key : $license_test"
    }
    $url_test = $url_line.Split('=')[1]
    if ($url_test -notlike 'https*') { 
        LogScreen "url does not contain https in Configuration"
        return $false
    } else {
        LogScreen "found url : $url_test"
    }

    return $true
}

function is_installed() {
    if (Get-Service $service_name -ErrorAction SilentlyContinue) {
        return $true
    }

    return $false
}


#main logic
function installer_main() {

    if (!(is_installed)) {
        $local_file = "$PSScriptRoot\agent-setup.exe"
        $result = download_file $agent_setup_url $local_file
        if ($result) {
            Start-Process $local_file "/S /license_key $license_key /url '$url'" -Wait
            if (is_installed) {
                LogScreen "$agent_name installation successful"
                Remove-Item -Path $local_file -Force
            } else {
                LogScreen "$agent_name installation failed"
            }
        }

    } else {
        LogScreen "$agent_name already installed"
        LogScreen "Checking Configuration"
        $istatus = verify_ini
        if ($istatus -ne $true) {
            # corrupt Configuration. lets create a new ini
            create_ini
            $istatus = verify_ini
            if ($istatus -ne $true) {
                # something bad happened. uninstall reinstall
                LogScreen "Configuration is corrupt. cannot continue"
                return $false
            } else {
                LogScreen "Configuration recreated."
                $rstatus = is_running
                if ($rstatus -eq $true) {
                    LogScreen "Stopping $agent_name for Configuration update"
                    Stop-Service $service_name
                }

            }
        } else {
            LogScreen "Configuration verified."
        }

        LogScreen "Checking if agent is running"
        $rstatus = is_running
        if ($rstatus -ne $true) {
            LogScreen "$agent_name not running. Attempting to start"
            Start-Service $service_name
            # wait 15 seconds
            Start-Sleep -s 15
            $rstatus = is_running
            if ($rstatus -ne $true) {
                LogScreen "$agent_name failed to start."
            } else {
                LogScreen "$agent_name successfully started."                
            }
        } else {
            LogScreen "$agent_name is running."
        }
    }

}

try
{
    installer_main
} catch {
    $err = $_.Exception.Message
    LogScreen $err
    exit -1
}


