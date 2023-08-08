# unimus-useful-scripts
Repo contains useful Unimus scripts.

**Unbackupables (.sh,.ps1)**
- this script is creating config backups in Unimus via API from files found under specified directory
- available in linux shell and powershell versions


Mandatory parameters:
User needs to change Unimus hostname/IP, API token and root directory to reflect their environment.

Directory structure must follow a specific pattern:
- subdirectories are named as mgmt IP addresses of devices, as they are added in Unimus.
- each subdirectory contains config backup version(s) of a given device

The script deletes the backups after it is run.

Optional parameters:
- Zone to work on in Unimus; defined as Zone ID
- insecure mode; for skipping SSL cert check
- create devices; for adding devices if not already added in Unimus
