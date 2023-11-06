# unimus-useful-scripts
Repo contains useful Unimus scripts.

**Unbackupables (.sh,.ps1)**
- this script is creating config backups in Unimus via API from files found under specified directory
- intended use is to push config backups to Unimus from an FTP for devices without CLI
- available in linux shell and powershell versions
- full article describing the topic is available on our blog at https://blog.unimus.net/backing-up-the-unbackupable/

Mandatory parameters:
User needs to change Unimus hostname/IP, API token and root directory to reflect their environment.

Directory structure must follow a specific pattern:
|- ftp_root_dir
   |- 10.1.1.2
      |- Backup_from_a_date
      |- Backup_from_another_date
   |- router.san.local
      |- Backup_from_a_date
      |- Backup_from_another_date

- subdirectories are named after mgmt IP addresses of devices, as they are accounted for in Unimus
- each subdirectory contains config backup version(s) of a given network device

The script deletes the backups after it is run. This is the intended behavior.

Optional parameters:
- Zone to work on in Unimus; defined as Zone ID; case sensitive
- insecure mode; for skipping SSL cert check
- create devices; for adding devices if not already added in Unimus
