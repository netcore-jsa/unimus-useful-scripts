#PowerShell script that extracts the names of subdirectories within a specified directory:
#parametric variables
$UNIMUS_ADDRESS = "172.17.0.1:8085"
$TOKEN = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhdXRoMCJ9.Ko3FEfroI2hwNT-8M-8Us38gqwzmHHxypM7nWCqU2JA"
$FTPFOLDER = "/ftp_data/"

#Set this $TRUE if you are using self-signed certs
$INSECURE = $TRUE
#Variable controlling creation of new devices in Unimus; 1 = create
$CREATE_DEVICES = 1

function Process-Files {
    param(
        [string]$directory
    )

    $subdirs = Get-ChildItem -Path $directory -Directory
    foreach ($subdir in $subdirs) {
        $address = $subdir.Name
        $id = "null"; $id = Get-DeviceId $address
        #Write-Host "`nDEVICE ID IS: $id"

        if ($id -eq "null" -and $CREATE_DEVICES -eq 1) {
            Create-NewDevice $address
            $id = Get-DeviceId $address
        }
        #Write-Host "`nDEVICE ID IS: $id"
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
    } | ConvertTo-Json

    $headers = @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $TOKEN"
    }
    if ($INSECURE) {
        Invoke-RestMethod -SkipCertificateCheck -Uri "http://$UNIMUS_ADDRESS/api/v2/devices" -Method POST -Headers $headers -Body $body | Out-Null
    } else {
        Invoke-RestMethod -Uri "http://$UNIMUS_ADDRESS/api/v2/devices" -Method POST -Headers $headers -Body $body | Out-Null
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
    try {
        if ($INSECURE) {
            $response = Invoke-RestMethod -SkipCertificateCheck -Uri "http://$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$address" -Method GET -Headers $headers
        } else {
            $response = Invoke-RestMethod -Uri "http://$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$address" -Method GET -Headers $headers
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
    if ($INSECURE) {
        Invoke-RestMethod -SkipCertificateCheck -Uri "http://$UNIMUS_ADDRESS/api/v2/devices/$id/backups" -Method POST -Headers $headers -Body $body | Out-Null
    } else {
        Invoke-RestMethod -Uri "http://$UNIMUS_ADDRESS/api/v2/devices/$id/backups" -Method POST -Headers $headers -Body $body | Out-Null
    }
}

Process-Files -directory $FTPFOLDER
