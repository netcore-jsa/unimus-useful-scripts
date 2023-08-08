#PowerShell script that extracts the names of subdirectories within a specified directory:
#mandatory parameters
$UNIMUS_ADDRESS = "http://172.17.0.1:8085"
$TOKEN = "<api token>"
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

    $subdirs = Get-ChildItem -Path $directory -Directory
    foreach ($subdir in $subdirs) {
        $address = $subdir.Name
        $id = "null"; $id = Get-DeviceId $address
        Write-Host "`nafter first DEVICE ID IS: $id"
        if ($id -eq "null" -and $CREATE_DEVICES) {
            Create-NewDevice $address
            $id = Get-DeviceId $address
        }
        Write-Host "`nDEVICE ID IS: $id"
        $files = Get-ChildItem -Path $subdir.FullName | Sort-Object -Property LastWriteTime -Descending
        foreach ($file in $files) {
            if ($file.GetType() -eq [System.IO.FileInfo]) {
                #Write-Host "Processing file: $($file.Name)"
                $encodedBackup = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.Fullname))
                $content = Get-Content -Path $file.FullName -Raw
                if ($content -match "[^\x00-\x7F]") {
                    Create-Backup $id $encodedBackup "BINARY"
                    #Write-Host "`nCreated BINARY backup"
                    Remove-Item $file.FullName
                } else {
                    Create-Backup $id $encodedBackup "TEXT"
                    #Write-Host "`nCreated TEXT backup"
                    Remove-Item $file.FullName
                }
            }
        }
    }
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
            Write-Host "doing NEWER version cert validation skip"
            $response = Invoke-RestMethod -SkipCertificateCheck -Uri "$UNIMUS_ADDRESS/$uri" -Method GET -Headers $headers
        } else {
            $response = Invoke-RestMethod -Uri "$UNIMUS_ADDRESS/$uri" -Method GET -Headers $headers
        }
        return $response.data.id
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            #Write-Host "Device with address $address not found."
            return "null"
        }
        else {
            #Write-Host "An error occurred: $($_.Exception.Message)"
            return $null
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
