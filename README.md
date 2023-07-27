# unimus-useful-scripts
Repo contains useful Unimus scripts.

Unbackupables - this script is creating config backups in Unimus via API on files found under specified directory.
Directory structure must follow a specific pattern 
- subdirectories are named as mgmt IP addresses of devices, as they are discovered in Unimus.
- each subdirectory contains config backup version(s) of a given device

The script deletes the backups after it is run.
