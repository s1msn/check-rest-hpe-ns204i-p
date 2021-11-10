#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

Help() {
  # Display Help
  echo "Check PCIe NVMe Boot Controllers via Redfish API."
  echo
  echo "Syntax: check_rest_pci_nvme.sh [-H <host> |-P <path> |-C <component> |-h]"
  echo "options:"
  echo "-H    FQDN/IP of host to check."
  echo "-P    Path to credentials file in format:"
  echo "        <Username>"
  echo "        <Password>"
  echo "-C    Component to check."
  echo "      Available options are:"
  echo "        controller: query the controller status"
  echo "        disks: query status of all disks connected to the controller"
  echo "        volumes: query status of all of the volumes present on disks"
  echo "-h    Help menu."
  echo
}

if [[ ! $* =~ ^\-.+ ]]; then
  Help
  exit
fi

while [ -n "${1:-}" ]; do # while loop starts
  case "$1" in
  -H)
    param="$2"
    host="$param"
    shift
    ;;
  -P)
    param="$2"
    creds="$param"
    shift
    ;;
  -C)
    param="$2"
    component="$param"
    shift
    ;;
  -h)
    Help
    exit
    ;;
  *)
    echo
    echo "Option $1 not recognized"
    echo
    Help
    exit
    ;;
  esac
  shift
done

# get credentials from creds file
user=$(sed -n -e 1p $creds)
password=$(sed -n -e 2p $creds)

# identify storage controller
controllermodel=$(curl https://$host/redfish/v1/Systems/1/Storage --insecure -u $user:$password --silent -S -f | jq -r '.Members[]."@odata.id"')
controllerapi=$(curl "https://$host$controllermodel#/StorageControllers/0" --insecure -u $user:$password --silent -S -f)
controllername=$(echo $controllerapi | jq -r '.Name')

### CONTROLLER CHECK
if [ $component = "controller" ]; then
  # get controller info
  controllerhealth=$(echo $controllerapi | jq -r '.StorageControllers[].Status.Health')
  controllersn=$(echo $controllerapi | jq -r '.StorageControllers[].SerialNumber')

  # generate exit codes
  if [ $controllerhealth = "OK" ]; then
    echo "OK: Storage Controller $controllername Serial Number: $controllersn is in state $controllerhealth."
    exit 0
  elif [ $controllerhealth = "Warning" ]; then
    echo "WARN: Storage Controller $controllername Serial Number: $controllersn is in state $controllerhealth."
    exit 1
  elif [ $controllerhealth = "Critical" ]; then
    echo "CRIT: Storage Controller $controllername Serial Number: $controllersn is in state $controllerhealth."
    exit 2
  else
    echo "UNKNOWN"
    exit 3
  fi

### DISK CHECK
elif [ $component = "disks" ]; then
  # get all disks connected to controller
  disks=$(curl https://$host$controllermodel --insecure -u $user:$password --silent -S -f | jq -r '.Drives[]."@odata.id"')

  # check disk health
  for disk in $disks; do
    diskapi=$(curl https://$host$disk --insecure -u $user:$password --silent)
    diskhealth=$(echo $diskapi | jq -r '.PredictedMediaLifeLeftPercent')
    diskname=$(echo $diskapi | jq -r '.Name')
    disksn=$(echo $diskapi | jq -r '.SerialNumber')
    diskport=$(echo $diskapi | jq -r '.PhysicalLocation.PartLocation.ServiceLabel')

    # generate exit codes
    if [ $diskhealth -gt 25 ]; then
      continue
    elif [[ $diskhealth -le 25 && $diskhealth -gt 10 ]]; then
      echo "WARN: $diskname (Serial: $disksn) at Port $diskport has $diskhealth% life left"
      exit 1
    elif [ $diskhealth -le 10 ]; then
      echo "CRIT: $diskname (Serial: $disksn) at Port $diskport has $diskhealth% life left"
      exit 2
    else
      echo "UNKNOWN"
      exit 3
    fi
  done
  echo "OK: All disks on controller $controllername are OK."
  exit 0

### VOLUME CHECK
elif [ $component = "volumes" ]; then
  # get all volumes registered on controller
  volumes=$(curl "https://$host$controllermodel/Volumes" --insecure -u $user:$password --silent -S -f | jq -r '.Members[]."@odata.id"')

  # check health of all volumes
  for volume in $volumes; do
    volumeapi=$(curl https://$host$volume --insecure -u $user:$password --silent -S -f)
    volumeid=$(echo $volumeapi | jq -r '.Id')
    volumehealth=$(echo $volumeapi | jq -r '.Status.Health')
    volumeraid=$(echo $volumeapi | jq -r '.RAIDType')

    # generate exit codes
    if [ $volumehealth = "OK" ]; then
      continue
    elif [ $volumehealth = "Warning" ]; then
      echo "WARN: Volume $volumeid ($volumeraid) is in state $volumehealth"
      exit 1
    elif [ $volumehealth = "Critical" ]; then
      echo "CRIT: Volume $volumeid ($volumeraid) is in state $volumehealth"
      exit 2
    else
      echo "UNKNOWN"
      exit 3
    fi
  done
  echo "OK: All volumes on controller $controllername are OK."
  exit 0
fi
