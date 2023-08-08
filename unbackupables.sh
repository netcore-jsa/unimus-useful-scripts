#!/bin/bash
#mandatory parameters
UNIMUS_ADDRESS="http://172.17.0.1:8085"
TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhdXRoMCJ9.Ko3FEfroI2hwNT-8M-8Us38gqwzmHHxypM7nWCqU2JA"
HEADERS_ACCEPT="Accept: application/json"
HEADERS_CONTENT_TYPE="Content-type: application/json"
HEADERS_AUTHORIZATION="Authorization: Bearer $TOKEN"
#ftp root directory
FTP_FOLDER="/home/will/docker-composer/ftp_data_test/"

#optional parameters
#which zone in Unimus to add backups to; CASE SENSITIVE; comment for default
ZONE="A1"
#if you are using self-signed certificates you might want to uncomment this
#SELF_SIGNED_CERT="si_senor"
#variable for enabling creation of new devices in Unimus, comment to disable
CREATE_DEVICES="yessir"

process_files() {
    local directory="$1"
    for subdir in "$directory"/*; do
        if [ -d "$subdir" ]; then
            address=$(basename "$subdir")
            id=$(get_device_id "$address")
            [ $id = "null" ] && [ -n "$CREATE_DEVICES" ] && create_new_device "$address" && id=$(get_device_id "$address") && echo "new device address:$address"
            for file in $(ls -tr "$subdir"); do
                #echo -e "\nCurrent file: " $file
                if [ -f "$subdir/$file" ]; then
                    encoded_backup=$(base64 -w 0 "$subdir/$file")
                    isTextFile=$(file -b "$subdir/$file")
                    if [[ $isTextFile == *"text"* ]]; then
                        create_backup "$id" "$encoded_backup" "TEXT" && echo -e "created TEXT backup\n" && rm "$subdir/$file"
                        sleep 1
                    else
                        create_backup "$id" "$encoded_backup" "BINARY" && echo -e "created BINARY backup\n" && rm "$subdir/$file"
                        sleep 1
                    fi
                fi
            done
        fi
    done
}

create_new_device() {
if [ -z "$ZONE" ]; then
    echo "create new device no-ZONE"
    curl $insecure  -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"apicreated"}'\
 "$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
else
    echo "create new device in ZONE $ZONE"
    curl $insecure  -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"apicreated", "zoneId": "'"$ZONE"'"}'\
 "$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
fi
}

get_device_id() {
if [ -z "$ZONE" ]; then
    echo "$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1" | jq .data.id)"
else
    echo "$(curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1?zoneId=$ZONE" | jq .data.id)"
fi
}

create_backup() {
curl $insecure -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"backup": "'"$2"'","type":"'"$3"'"}' "$UNIMUS_ADDRESS/api/v2/devices/$1/backups" > /dev/null
}

[ -n "$SELF_SIGNED_CERT" ] && insecure="-k"

process_files $FTP_FOLDER
