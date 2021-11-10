# check-rest-api-pci-nvme-boot-controller

Check PCIe NVMe Boot Controllers via Redfish API.

# Usage:

Syntax: check_rest_pci_nvme.sh [-H <host> |-P <path> |-C <component> |-h]
options:
-H    FQDN/IP of host to check.
-P    Path to credentials file in format:
        <Username>
        <Password>
-C    Component to check.
      Available options are:
        controller: query the controller status
        disks: query status of all disks connected to the controller
        volumes: query status of all of the volumes present on disks
-h    Help menu.

