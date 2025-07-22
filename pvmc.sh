#!/bin/bash
set -e

###### VARIABLES TO CHANGE ######

# Proxy equals node if node is a DNS address
# Otherwise, you need to set the IP address of the node here
PROXY="node.proxmox.url"

# Set Node
# This must either be a DNS address or name of the node in the cluster
NODE="${PROXY%%\.*}"

###### END OF CHANGABLE VARIABLES #####

ToInstall=""
needinstall=false
if ! command -v curl >/dev/null 2>&1
then
    echo "Curl could not be found, will try and install:"
    ToInstall+=" curl"
    needinstall=true
fi
if ! command -v remote-viewer >/dev/null 2>&1
then
    echo "remote-viewer could not be found, will try and install:"
    ToInstall+=" virt-viewer"
    needinstall=true
fi

if ! command -v jq >/dev/null 2>&1
then
    echo "Jq could not be found, will try and install:"
    ToInstall+=" jq"
    needinstall=true
fi

if [ $needinstall == true ]; then
  echo "Attempting to install: $ToInstall"
  sudo apt update
  sudo apt -y install $ToInstall
fi

echo "Connecting to node to get available realms for authentication"
REALMS_json="$(curl -f -s -S -k "https://$PROXY:8006/api2/json/access/domains")"
realms=$(echo "$REALMS_json" | jq -r '.data[].realm')

# Present the list of realms
selected_realm=$(zenity --list --title="Select Realm" --text="Choose a Realm for authentication:" \
  --column "Realm Name" $realms)
echo ${selected_realm}
# Check if the user cancelled the list selection
if [ -z "$selected_realm" ]; then
  echo "Realm selection cancelled."
  exit 1
fi
echo "Prompting for loging info"
# Create the Zenity window for authentication
auth_info=$(zenity --password --username --title="Authentication")
# Check if the user clicked "Connect" or "Cancel"
if [ -n "$auth_info" ]; then
  username=$(echo $auth_info | cut -d'|' -f1)
  password=$(echo $auth_info | cut -d'|' -f2)

else
  echo "Authentication cancelled."
fi

# Set auth options
PASSWORD="${password}"
USERNAME="${username}@${selected_realm}"

# Get ticket for further authentication
echo "Generating Authentication Ticket"

DATA="$(curl -f -s -S -k --data-urlencode "username=$USERNAME" --data-urlencode "password=$PASSWORD" "https://$PROXY:8006/api2/json/access/ticket")"

echo "AUTH OK"

TICKET="${DATA//\"/}"
TICKET="${TICKET##*ticket:}"
TICKET="${TICKET%%,*}"
TICKET="${TICKET%%\}*}"

CSRF="${DATA//\"/}"
CSRF="${CSRF##*CSRFPreventionToken:}"
CSRF="${CSRF%%,*}"
CSRF="${CSRF%%\}*}"


#Get available LXCs and QEMUs
echo "Getting available LXCs and QEMUs to choose from"
LXCs="$(curl -f -s -S -k -b "PVEAuthCookie=$TICKET" -H "CSRFPreventionToken: $CSRF" "https://$PROXY:8006/api2/json/nodes/$NODE/lxc")"
VMs_raw="$(echo $LXCs | jq -r '.data[] | [.vmid, .name, .status, .type]')"


QEMUs="$(curl -f -s -S -k -b "PVEAuthCookie=$TICKET" -H "CSRFPreventionToken: $CSRF" "https://$PROXY:8006/api2/json/nodes/$NODE/qemu")"
VMs_raw+="$(echo $QEMUs | jq -r '.data[] | [.vmid, .name, .status, .type]')"

VMs=$(echo "$VMs_raw" | tr -d '"' | tr '[] ' '\n' | sed 's/,\s*/,/g' | sed 's/,$//' | sed 's/null/qemu/g')

#list available VMs
echo "Listing available VMs"
# Present the list of realms
selected_VM=$(zenity --list --title="Select VM" --text="Choose a VM to connect:" \
  --column "VMID" --column "Name" --column "status" --column "Type" $VMs)

# Check if the user cancelled the list selection
if [ -z "$selected_VM" ]; then
  echo "VM selection cancelled."
  exit 1
fi

# Set VM ID
VMID="${selected_VM}"

echo "$VMID was selected, verifying status..."
#Check if VM is running.
# Find the starting position of "109"
start_pos=$(echo "$VMs_raw" | grep -b -o "$VMID" | head -n 1 | cut -d ':' -f 1)

# If "109" is not found
if [ -z "$start_pos" ]; then
  echo "Entry '$VMID' not found."
  exit 1
fi

# Extract the string after "109"
after_vimid=$(echo "$VMs_raw" | tail -c +$(($start_pos + 1)))
after_vimid=$(echo $after_vimid | cut -f1 -d"]")

# Split the string by commas and select the 3rd element (index 2)
IFS=', ' read -r -a status <<< "$after_vimid"
STATUS=$(echo "${status[2]}" | sed 's/"//g')

# Print the status
echo "Status for entry "$VMID": $STATUS"

# Start VM if stopped
while [ "$STATUS" = "stopped" ]; do
  echo "VM is stopped, starting."
  curl -f -s -S -k -X POST -b "PVEAuthCookie=$TICKET" -H "CSRFPreventionToken: $CSRF" "https://$PROXY:8006/api2/json/nodes/$NODE/qemu/$VMID/status/start" 
  echo ""
  echo "Sleeping for 5s to allow VM to start."
  sleep 5s
  
  echo "Checking Status of VM"
  curl -f -s -S -k -b "PVEAuthCookie=$TICKET" -H "CSRFPreventionToken: $CSRF" "https://$PROXY:8006/api2/json/nodes/$NODE/qemu/$VMID/status/current" > vmstatus
  STATUS="$(cat vmstatus | jq -r '.data.status')"
done

echo "Getting spice file"
curl -f -s -S -k -b "PVEAuthCookie=$TICKET" -H "CSRFPreventionToken: $CSRF" "https://$PROXY:8006/api2/spiceconfig/nodes/$NODE/qemu/$VMID/spiceproxy" -d "proxy=$PROXY" > spiceproxy


#Launch remote-viewer with spiceproxy file, in kiosk mode, quit on disconnect
#The run loop will get a new ticket and launch us again if we disconnect
# -k --kiosk-quit on-disconnect 
echo "Connecting to vm with spice"
exec remote-viewer -f spiceproxy
