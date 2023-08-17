#!/bin/bash
#mandatory parameters
UNIMUS_ADDRESS="http://172.17.0.1:8085"
TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhdXRoMCJ9.Ko3FEfroI2hwNT-8M-8Us38gqwzmHHxypM7nWCqU2JA"
HEADERS_ACCEPT="Accept: application/json"
HEADERS_CONTENT_TYPE="Content-type: application/json"
HEADERS_AUTHORIZATION="Authorization: Bearer $TOKEN"
#ftp root directory
FTP_FOLDER="/home/will/docker-composer/ftp_data/"

#optional parameters
#which zone in Unimus to add backups to; CASE SENSITIVE; comment for default
ZONE="ES1"
#if you are using self-signed certificates you might want to uncomment this
#SELF_SIGNED_CERT="si_senor"
#variable for enabling creation of new devices in Unimus, comment to disable
CREATE_DEVICES="yessir"

function process_files() {
# Creating a log file
log="unbackupables.log"
printf 'Log File - ' >> $log
date +"%F %H:%M:%S" >> $log
#insecure curl switch
[ -n "$SELF_SIGNED_CERT" ] && insecure="-k"
status=$(healthCheck)
errorCheck "$?" 'Status check failed'
zoneCheck
if [ $status == 'OK' ]; then
    echoGreen 'Checks OK. Script starting...'
    local directory="$1"
    for subdir in "$directory"/*; do
        if [ -d "$subdir" ]; then
            address=$(basename "$subdir")
            id=$(getDeviceId "$address")
            [ $id = "null" ] && [ -n "$CREATE_DEVICES" ] && createNewDevice "$address" && id=$(getDeviceId "$address") && echoGreen "new device in ZONE:$ZONE added. address:$address,id:$id"
            for file in $(ls -tr "$subdir"); do
                if [ -f "$subdir/$file" ]; then
                    encoded_backup=$(base64 -w 0 "$subdir/$file")
                    isTextFile=$(file -b "$subdir/$file")
                    if [[ $isTextFile == *"text"* ]]; then
                        createBackup "$id" "$encoded_backup" "TEXT" && echoGreen "pushed TEXT backup for device $address from file $file" && rm "$subdir/$file"
                        sleep 1
                    else
                        createBackup "$id" "$encoded_backup" "BINARY" && echoGreen "pushed BINARY backup for device $address from file $file" && rm "$subdir/$file"
                        sleep 1
                    fi
                fi
            done
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

function createNewDevice() {
if [ -z "$ZONE" ]; then
    curl $insecure  -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"apicreated"}'\
    "$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
else
    curl $insecure  -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"apicreated", "zoneId": "'"$ZONE"'"}'\
    "$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
fi
}

function getDeviceId() {
if [ -z "$ZONE" ]; then
    echo "$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1" | jq .data.id)"
else
    echo "$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1?zoneId=$ZONE" | jq .data.id)"
fi
}

function createBackup() {
    curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"backup": "'"$2"'","type":"'"$3"'"}' "$UNIMUS_ADDRESS/api/v2/devices/$1/backups" > /dev/null
}

function echoGreen(){
	printf "$(date +'%F %H:%M:%S') $1\n" >> $log
	local green='\033[0;32m'
	local reset='\033[0m'
	echo -e "${green}$1${reset}"
}

function echoRed(){
	printf "ERROR: $(date +'%F %H:%M:%S') $1\n" >> $log
	local red='\033[0;31m'
	local reset='\033[0m'
	echo -e "ERROR: ${red}$1${reset}"
}

function errorCheck(){
	if [ $1 -ne 0 ]; then
		echoRed "$2"
		exit "$1"
	fi
}
function zoneCheck(){
    local response=$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v3/zones")
    local zoneIDs=$(jq -r '.zones[].number' <<< $response)
    for ID in $zoneIDs; do
        [ $ID = $ZONE ] && local zoneFound=1
    done
    [ -z $zoneFound ] && echoRed "Error. Zone $ZONE not found!" && exit
}

function healthCheck(){
    local response=$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/health")
	local status=$(jq -r '.data.status' <<< $response)
	errorCheck "$?" 'Unable to perform Unimus Health Check'
	echo "$status"
}

process_files $FTP_FOLDER
