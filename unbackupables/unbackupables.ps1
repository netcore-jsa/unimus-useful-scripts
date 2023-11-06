# This script is for pushing config backups from local directory to Unimus
# !!! Specifying Zone to search in works for Unimus 2.4.0-Beta3 onwards !!!
# Mandatory parameters
$UNIMUS_ADDRESS = "<http(s)://unimus.server.address(:port)>"
$TOKEN = "<api token>"
# FTP root directory
$FTP_FOLDER = "/ftp_data"
# Example of Windows file format with backslashes
#C:\Users\unimus\Documents\ftp_data\

# Optional parameters
# Specifies the Zone where devices will be searched for by address/hostname
# CASE SENSITIVE; leave commented to use the Default (0) zone
#$ZONE="0"
# Insecure mode
# If you are using self-signed certificates you might want to set this to true
$INSECURE = $false
# Variable for enabling creation of new devices in Unimus; set to true to enable
$CREATE_DEVICES = $false
# Specify description of new devices created in Unimus by the script
$CREATED_DESC = "Unbackupable"

function Process-Files {
    param(
        [string]$directory
    )

    $log = Join-Path $PSScriptRoot "unbackupablesPS.log"
    $logMessage = "Log File - " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $log -Value $logMessage
    #Health check
    $status = Health-Check

    if ($status -eq 'OK') {
        if ($ZONE) {
            Zone-Check
        }

        Print-Green "Checks OK. Script starting..."
        $ftpSubdirs = Get-ChildItem -Path $directory -Directory

        foreach ($subdir in $ftpSubdirs) {
            $address = $subdir.Name
            # Check if device already exists in Unimus
            $id = "null"; $id = Get-DeviceId $address

            if ($id -eq "null" -and $CREATE_DEVICES) {
                Create-NewDevice $address
                $id = Get-DeviceId $address
                Print-Green ("New device added. Address: " + $address + ", id: " + $id)
            }

            if ($id -eq "null" -or $id -eq $null) {
                Print-Yellow ("Device " + $address + " not found on Unimus. Consider enabling creating devices. Continuing with next device.")
            } else {
                $files = Get-ChildItem -Path $subdir.FullName | Sort-Object -Property LastWriteTime -Descending

                foreach ($file in $files) {
                    if ($file.GetType() -eq [System.IO.FileInfo]) {
                        $content = [System.IO.File]::ReadAllBytes($file.Fullname)
                        $encodedBackup = [System.Convert]::ToBase64String($content)

                        if ($content -contains 0) {
                            $bkp_type = "BINARY"
                        } else {
                            $bkp_type = "TEXT"
                        }
                        Create-Backup $id $encodedBackup $bkp_type
                        Print-Green ("Pushed " + $bkp_type + " backup for device " + $address + " from file " + $($file.Name))
                        Remove-Item $file.FullName
                    }
                }
            }
        }
    } else {
        Print-Red "Unimus server status: $status"
    }
    Print-Green "Script finished."
}

function Health-Check {
    $headers = @{
        "Accept" = "application/json"
        "Authorization" = "Bearer $TOKEN"
    }

    try {
        if ($INSECURE -and $psMajorVersion -ge 6) {
            $response = Invoke-RestMethod -SkipCertificateCheck -Uri "$UNIMUS_ADDRESS/api/v2/health" -Method GET -Headers $headers
        } else {
            $response = Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/api/v2/health" -Method GET -Headers $headers
        }
        return $response.data.status
    }
    catch {
        Print-Red "Unimus health check failed. Error: $($_.Exception.Message)"
        Exit
    }
}

function Zone-Check {
    $headers = @{
        "Accept" = "application/json"
        "Authorization" = "Bearer $TOKEN"
    }

    if ($INSECURE -and $psMajorVersion -ge 6) {
        $response = Invoke-RestMethod -SkipCertificateCheck -Uri "$UNIMUS_ADDRESS/api/v3/zones" -Method GET -Headers $headers
    } else {
        $response = Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/api/v3/zones" -Method GET -Headers $headers
    }
    $zoneIDs = ($response.zones | ForEach-Object { $_.number })

    $zoneFound = $false
    foreach ($ID in $zoneIDs) {
        if ($ID -eq $ZONE) {
            $zoneFound = $true
        }
    }

    if (-not $zoneFound) {
        Print-Red "Error. Zone $ZONE not found!"
        exit
    }
}

function Print-Green {
    param(
        [string]$logged_text
    )
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = $currentDateTime + " " + $logged_text
    Add-Content -Path $log -Value $output
    Write-Host $logged_text -ForegroundColor Green
}

function Print-Yellow {
    param(
        [string]$logged_text
    )
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "Warning: " + $currentDateTime + " " + $logged_text
    Add-Content -Path $log -Value $output
    $output = "Warning: " + $logged_text
    Write-Host $output -ForegroundColor Yellow
}

function Print-Red {
    param(
        [string]$logged_text
    )
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "Error: " + $currentDateTime + " " + $logged_text
    Add-Content -Path $log -Value $output
    $output = "Error: " + $logged_text
    Write-Host $output -ForegroundColor Red
}

function Get-DeviceId {
    param(
        [string]$address
    )

    $headers = @{
        "Accept" = "application/json"
        "Authorization" = "Bearer $TOKEN"
    }

    if ($ZONE) {
        $uri="api/v2/devices/findByAddress/" + $address + "?zoneId=" + $ZONE
    } else {
        $uri="api/v2/devices/findByAddress/" + $address
    }

    try {
        if ($INSECURE -and $psMajorVersion -ge 6) {
            $response = Invoke-RestMethod -SkipCertificateCheck -Uri "$UNIMUS_ADDRESS/$uri" -Method GET -Headers $headers
        } else {
            $response = Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/$uri" -Method GET -Headers $headers
        }
        return $response.data.id
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            return "null"
        }
    }
}

function Create-NewDevice {
    param(
        [string]$address
    )

    $body = @{
        address = $address
        description = $CREATED_DESC
    }

    if ($ZONE) {
        $body["zoneId"] = $ZONE
    }

    $body = $body | ConvertTo-Json

    $headers = @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $TOKEN"
    }

    if ($INSECURE -and $psMajorVersion -ge 6) {
        Invoke-RestMethod -SkipCertificateCheck -Uri "$UNIMUS_ADDRESS/api/v2/devices" -Method POST -Headers $headers -Body $body | Out-Null
    } else {
        Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/api/v2/devices" -Method POST -Headers $headers -Body $body | Out-Null
    }
}

function Create-Backup {
    param(
        [string]$id,
        [string]$encodedBackup,
        [string]$type
    )

    $body = @{
        backup = $encodedBackup
        type = $type
    } | ConvertTo-Json

    $headers = @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $TOKEN"
    }
    if ($INSECURE -and $psMajorVersion -ge 6) {
        Invoke-RestMethod -SkipCertificateCheck -Uri "$UNIMUS_ADDRESS/api/v2/devices/$id/backups" -Method POST -Headers $headers -Body $body | Out-Null
    } else {
        Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/api/v2/devices/$id/backups" -Method POST -Headers $headers -Body $body | Out-Null
    }
}

$psMajorVersion = $PSVersionTable.PSVersion.Major

# This block handles insecure API calls for earlier PS versions
if ($INSECURE -and $psMajorVersion -le 5) {
    Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

    # Set TLS versions
    $allProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $allProtocols
}

Process-Files -directory $FTP_FOLDER
