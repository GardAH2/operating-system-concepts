# ID616001 Operating Systems Concepts – Assignment 1

## Author Details

| Field         | Value                        |
|---------------|------------------------------|
| Full Name     | <!-- Your full name here --> |
| Student Code  | <!-- Your login name here -->|
| Last Updated  | <!-- e.g. 2026-04-30 -->     |

---

## Repository Structure

```
.
├── README.md
├── BSA_Self_Assessment.txt
├── task1/
│   └── create_users.sh        # Task 1 – user creation script
└── task2/
    └── backup.sh              # Task 2 – backup and upload script
```

---

## Task 1 – User Creation Script (`task1/create_users.sh`)

### Purpose

Automates the creation of Linux user accounts on an Ubuntu server from a CSV file.
For each user the script will:

- Create the account with a home directory and `/bin/bash` shell
- Set a default password derived from the user's birth date (`YYYYMM`)
- Force a password change on first login
- Create any required secondary groups
- Create shared folders with correct group ownership and `rwxrws---` permissions
- Create a `shared` symbolic link in the user's home directory
- Add a `myls` alias (lists home directory including hidden files) for sudo users

### Pre-requisites

- Ubuntu Linux (tested on 22.04 LTS)
- Must be run as **root** (`sudo`)
- The following tools must be installed (all present by default on Ubuntu):
  `curl`, `useradd`, `groupadd`, `chage`, `usermod`, `chown`, `chmod`, `ln`
- Network access if supplying a remote URL

### CSV Format

The script accepts a CSV with the following header and columns:

```
e-mail,birth date,groups,sharedFolder
edsger.dijkstra@tue.nl,1930/05/11,sudo,staff,/staffData
```

- **e-mail** – used to derive the username (`tLinus` from `linus.torvalds@…`)
- **birth date** – `YYYY/MM/DD` format; used to set the default password (`YYYYMM`)
- **groups** – one or two comma-separated supplementary groups (e.g. `sudo`, `staff`)
- **sharedFolder** – absolute path to a shared directory (e.g. `/staffData`)

### How to Run

```bash
# Make the script executable (first time only)
chmod +x task1/create_users.sh

# Run with a local CSV file
sudo ./task1/create_users.sh /path/to/users.csv

# Run with a remote URL
sudo ./task1/create_users.sh https://osc.op-bit.nz/share/users.csv

# Run interactively (will prompt for input)
sudo ./task1/create_users.sh
```

The script will ask for confirmation before making any changes.
A timestamped log file is created in the same directory as the script.

---

## Task 2 – Backup Script (`task2/backup.sh`)

### Purpose

Compresses a local directory into a gzip-compressed tarball (`.tar.gz`) and uploads
it to a remote server using `scp` over SSH.

### Pre-requisites

- Ubuntu Linux (tested on 22.04 LTS)
- The following tools must be installed: `tar`, `gzip`, `scp`, `ssh`
- SSH access to the remote server (key-based authentication recommended)
- The target directory must exist on the remote server

### How to Run

```bash
# Make the script executable (first time only)
chmod +x task2/backup.sh

# Run with a directory argument
./task2/backup.sh /home/user/docs

# Run interactively (will prompt for the directory)
./task2/backup.sh
```

The script will then prompt you for:

| Prompt                          | Example              |
|---------------------------------|----------------------|
| Remote server IP or hostname    | `192.168.1.50`       |
| SSH port                        | `22`                 |
| Remote username                 | `backupuser`         |
| Target directory on remote      | `/home/backupuser/backups` |

A `.tar.gz` archive named after the source directory (e.g. `docs.tar.gz`) is created
locally and uploaded. A timestamped log file is created in the same directory.

---

## Notes

- Both scripts produce a timestamped log file alongside the script for detailed auditing.
- All errors are printed to the console **and** written to the log file.
- If a username already exists during Task 1, the user is skipped (not overwritten).
