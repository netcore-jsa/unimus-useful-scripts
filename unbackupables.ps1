#PowerShell script that extracts the names of subdirectories within a specified directory:
#mandatory parameters
$UNIMUS_ADDRESS = "http://172.17.0.1:8085"
$TOKEN = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhdXRoMCJ9.Ko3FEfroI2hwNT-8M-8Us38gqwzmHHxypM7nWCqU2JA"
$FTPFOLDER = "/ftp_data"
#C:\Users\unimus\Documents\ftp_data\

#optional parameters
#Which Zone in Unimus are you working on; CAPS sensitive; comment if default
$ZONE="ES1"
#Uncomment this if you are using self-signed certs
#$INSECURE = "very"
#Variable controlling creation of new devices in Unimus; comment to disable
$CREATE_DEVICES = "yespls"

function Process-Files {
    param(
        [string]$directory
    )
    $log = "unbackupablesPS.log"
    #Health check
    $status = Health-Check
    Zone-Check
    if ($status -eq 'OK') {
        $logMessage = "Log File - " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $log -Value $logMessage
        Print-Green "Checks OK. Script starting..."
        $subdirs = Get-ChildItem -Path $directory -Directory
        foreach ($subdir in $subdirs) {
            $address = $subdir.Name
            $id = "null"; $id = Get-DeviceId $address
            if ($id -eq "null" -and $CREATE_DEVICES) {
                Create-NewDevice $address
                Print-Green "Device with address $address not found in ZONE $ZONE, creating..."
                $id = Get-DeviceId $address
            }
            $files = Get-ChildItem -Path $subdir.FullName | Sort-Object -Property LastWriteTime -Descending
            foreach ($file in $files) {
                if ($file.GetType() -eq [System.IO.FileInfo]) {
                    $encodedBackup = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.Fullname))
                    $content = Get-Content -Path $file.FullName -Raw
                    if ($content -match "[^\x00-\x7F]") {
                        Create-Backup $id $encodedBackup "BINARY"
                        Print-Green ("Pushed BINARY backup for device " + $address + " from file " + $($file.Name))
                        Remove-Item $file.FullName
                    } else {
                        Create-Backup $id $encodedBackup "TEXT"
                        Print-Green ("Pushed TEXT backup for device " + $address + " from file " + $($file.Name))
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

function Create-NewDevice {
    param(
        [string]$address
    )

    $body = @{
        address = $address
        description = "apicreated"
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

function Print-Green {
    param(
        [string]$logged_text
    )
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = $currentDateTime + " " + $logged_text
    Add-Content -Path $log -Value $output
    Write-Host $output -ForegroundColor Green
}

function Print-Red {
    param(
        [string]$logged_text
    )
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "Error: " + $currentDateTime + " " + $logged_text
    Add-Content -Path $log -Value $output
    Write-Host $output -ForegroundColor Red
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

    $response = Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/api/v3/zones" -Method GET -Headers $headers
    $zoneIDs = ($response.zones | ForEach-Object { $_.number })

    $zoneFound = $false
    foreach ($ID in $zoneIDs) {
        if ($ID -eq $ZONE) {
            $zoneFound = $true
        }
    }

    if (-not $zoneFound) {
        Print-Red "Error. Zone $ZONE not found!" -ForegroundColor Red
        exit
    }
}


$psMajorVersion = $PSVersionTable.PSVersion.Major

if ($INSECURE -and $psMajorVersion -le 5) {
    Write-Host "doing OLDER version cert validation skip"
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

    # Set Tls versions
    $allProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $allProtocols
}

Process-Files -directory $FTPFOLDER
