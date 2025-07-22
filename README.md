# PVMC: Proxmox VM connect Script

## Description

PVMC is a Bash script designed to simplify and automate the process of connecting to Proxmox Virtual Machine (VM) instances. It handles authentication, VM selection, status checking, and automatic startup of stopped VMs, culminating in a connection via remote-viewer using the Spice protocol.  It eliminates the need for manual steps and streamlines the user experience.

## Requirements

*   **Operating System:** Debian based Linux (tested on Ubuntu Mate).
*   **Dependencies:**
    *   `bash`:  The script is written in Bash.
    *   `curl`: For making HTTP requests to the Proxmox API. (Will be auto installed if not found)
    *   `remote-viewer`: For displaying the VM console.  (virt-viewer) (Will be auto installed if not found)
    *   `jq`: For parsing JSON responses from the Proxmox API. (Will be auto installed if not found)
    *   `zenity`:  For providing graphical user interfaces (selection windows).
*   **Proxmox Environment:**
    *   Access to a Proxmox cluster.
    *   Appropriate API user with sufficient permissions.

## Usage

1.  **Configuration:**
    *   Edit the script and modify the `PROXY` variable to point to the FQDN or IP address of your Proxmox node.
    *   The script automatically determines the `NODE` from the `PROXY` setting.
2.  **Execution:**
    *   Make the script executable: `chmod +x pvmc.sh`
    *   Run the script: `./pvmc.sh`
3.  **Workflow:**
    *   The script will first ask for what realm to authenticate againts (Ex: For Proxmox setups with LDAP as backend).
    *   You will be prompted with a login screen.
    *   The script will prompt you to select a VM from a list.
    *   If the selected VM is stopped, it will automatically start the VM.
    *   Finally, a remote-viewer window will open in fullscreen, connecting you to the VM console.

## Configuration Example

```bash
PROXY="node.proxmox.domain"