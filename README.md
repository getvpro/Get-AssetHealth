## Get-AssetHealth for vmware/windows environments

This script scans remote windows assets
Update the settings.xml for your own environment accordingly

1. Reads settings.xml for various settings
2. Pulls in list of machines within active directory: Note: use the <filteredassets> section of the settings.xml to stop scans against desired computers
3. Connects to vCenter to pull in VM / infra info: data stores, VMs, esxi level 
4. Reboots assets with 14 or more days of uptime when run reboot is set to Y (yes)
5. Generates a CSV report as well as an HTML formatted email to the receipient specified in the settings.xml

## Code examples
```
Get-AssetHealth.ps1 -reboot "Y"
```


