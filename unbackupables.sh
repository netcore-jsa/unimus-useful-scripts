#!/bin/bash
# !!! The script works for Unimus v2.4.0 beta 3 onwards !!!
# Mandatory parameters
UNIMUS_ADDRESS="http://172.17.0.1:8085"
TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhdXRoMCJ9.Ko3FEfroI2hwNT-8M-8Us38gqwzmHHxypM7nWCqU2JA"
HEADERS_ACCEPT="Accept: application/json"
HEADERS_CONTENT_TYPE="Content-type: application/json"
HEADERS_AUTHORIZATION="Authorization: Bearer $TOKEN"
#ftp root directory
FTP_FOLDER="/home/will/docker-composer/ftp_data/"

# Optional parameters
# Specifies the Zone where devices will be searched for by address/hostname
# CASE SENSITIVE; leave commented to use the Default (0) zone
ZONE="ES1"
# Insecure mode
# If you are using self-signed certificates you might want to uncomment this
#SELF_SIGNED_CERT=true
# Variable for enabling creation of new devices in Unimus; comment to disable
CREATE_DEVICES=true
# Specify description of new devices created in Unimus by the script
CREATED_DESC="The Unbackupable"

function process_files() {

    # Set script directory for the script
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

    # Creating a log file
    log="$script_dir/unbackupables.log"
    printf 'Log File - ' >> $log
    date +"%F %H:%M:%S" >> $log

    # Insecure curl switch
    [ -n "$SELF_SIGNED_CERT" ] && insecure="-k"

    # Perform Unimus health check
    status=$(healthCheck)
    errorCheck "$?" 'Status check failed'

    if [ $status == 'OK' ]; then
        [ -n "$ZONE" ] && zoneCheck
        echoGreen 'Checks OK. Script starting...'
        ftp_directory="$1"
        # Begin sweeping through the specified FTP directory
        for subdir in "$ftp_directory"/*; do
            if [ -d "$subdir" ]; then
                # Interpret directory names as device addresses/host names in Unimus
                address=$(basename "$subdir")
                id=$(getDeviceId "$address")
                # Add device to Unimus if it was not found and creating devices is enabled
                [ $id = "null" ] && [ -n "$CREATE_DEVICES" ] && createNewDevice "$address" && id=$(getDeviceId "$address") && echoGreen "New device added. Address:$address, id:$id"
                if [ $id = "null" ] || [ -z "$id" ]; then
                    echoYellow "Device $address not found on Unimus. Consider enabling creating devices. Continuing with next device."
                else
                    for file in $(ls -tr "$subdir"); do
                        if [ -f "$subdir/$file" ]; then
                            isTextFile=$(file -b "$subdir/$file")
                            if [[ $isTextFile == *"text"* ]]; then
                                bkp_type="TEXT"
                            else
                                bkp_type="BINARY"
                            fi
                            encoded_backup=$(base64 -w 0 "$subdir/$file")
                            temp_json_file=$(mktemp)
                            cat <<EOF > "$temp_json_file"
                            {
                            "backup": "$encoded_backup",
                            "type": "$bkp_type"
                            }
EOF
                            # Use jq to process the JSON from the temporary file
                            jq '.' "$temp_json_file" > output.json
                            createBackup "$id" "output.json" && echoGreen "Pushed $bkp_type backup for device $address from file $file" #&& rm "$subdir/$file"
                            sleep 1
                            # Clean up the temporary files
                            rm "$temp_json_file" output.json
                        fi
                    done
                fi
            fi
        done
    else
        if [ -z $status ]; then
            echoRed 'Unable to connect to unimus server'\
            exit 2
        else
            echoRed "Unimus server status: $status"
        fi
    fi
    echoGreen 'Script finished'
}

function healthCheck() {
    local response=$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/health")
    local status=$(jq -r '.data.status' <<< $response)
    echo "$status"
}

function errorCheck() {
    if [ $1 -ne 0 ]; then
        echoRed "$2"
        exit "$1"
    fi
}

function zoneCheck() {
    local response=$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v3/zones")
    local zoneIDs=$(jq -r '.zones[].number' <<< $response)
    for ID in $zoneIDs; do
        [ $ID = $ZONE ] && local zoneFound=1
    done
    [ -z $zoneFound ] && echoRed "Error. Zone $ZONE not found!" && exit
}

function echoGreen() {
    printf "$(date +'%F %H:%M:%S') $1\n" >> $log
    local green='\033[0;32m'
    local reset='\033[0m'
    echo -e "${green}$1${reset}"
}

function echoYellow(){
    printf "WARNING: $(date +'%F %H:%M:%S') $1\n" >> $log
    local yellow='\033[1;33m'
    local reset='\033[0m'
    echo -e "WARNING: ${yellow}$1${reset}"
}

function echoRed() {
    printf "ERROR: $(date +'%F %H:%M:%S') $1\n" >> $log
    local red='\033[0;31m'
    local reset='\033[0m'
    echo -e "ERROR: ${red}$1${reset}"
}

function getDeviceId() {
    if [ -z "$ZONE" ]; then
        echo "$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1" | jq .data.id)"
    else
        echo "$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1?zoneId=$ZONE" | jq .data.id)"
    fi
}

function createNewDevice() {
    if [ -z "$ZONE" ]; then
        curl $insecure  -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"'"$CREATED_DESC"'"}'\
        "$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
    else
        curl $insecure  -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"'"$CREATED_DESC"'", "zoneId": "'"$ZONE"'"}'\
        "$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
    fi
}

function createBackup() {
    curl $insecure -X POST -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d "@$2"  "$UNIMUS_ADDRESS/api/v2/devices/$1/backups"
}

process_files $FTP_FOLDER
