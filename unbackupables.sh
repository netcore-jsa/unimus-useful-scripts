#!/bin/bash
#parametric variables
UNIMUS_ADDRESS="172.17.0.1:8085"
TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJhdXRoMCJ9.Ko3FEfroI2hwNT-8M-8Us38gqwzmHHxypM7nWCqU2JA"
HEADERS_ACCEPT="Accept: application/json"
HEADERS_CONTENT_TYPE="Content-type: application/json"
HEADERS_AUTHORIZATION="Authorization: Bearer $TOKEN"

#ftp root directory
FTP_FOLDER="/home/will/docker-composer/ftp_data/"

#variable for enabling(1) creation of new devices in Unimus
CREATE_DEVICES=1

process_files() {
    local directory="$1"
    for subdir in "$directory"/*; do
        if [ -d "$subdir" ]; then
            address=$(basename "$subdir")
            id=$(get_device_id "$address")
            [ $id = "null" ] && [ $CREATE_DEVICES = 1 ] && create_new_device "$address" && id=$(get_device_id "$address")
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
curl -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"address": "'"$1"'","description":"apicreated"}'\
 "http://$UNIMUS_ADDRESS/api/v2/devices" > /dev/null
}

get_device_id() {
echo "$(curl -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_AUTHORIZATION" "http://$UNIMUS_ADDRESS/api/v2/devices/findByAddress/$1" | jq .data.id)"
}

create_backup() {
curl -sSL -H "$HEADERS_ACCEPT" -H "$HEADERS_CONTENT_TYPE" -H "$HEADERS_AUTHORIZATION" -d '{"backup": "'"$2"'","type":"'"$3"'"}' "http://$UNIMUS_ADDRESS/api/v2/devices/$1/backups" > /dev/null
}

process_files $FTP_FOLDER
