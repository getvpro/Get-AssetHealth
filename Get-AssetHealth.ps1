<#

.FUNCTIONALITY
Remote asset scan: Checks ping uptime, C drive size/space, licensed remaining days, will ID if asset is virtual/hardware type
Part 1 Various tests on run based on the $Assets variable being populated via "Get-ADComputer -Filter *"
Part 2 - Scheduled tasks
Part 3 - VMWARE asset info
Part 4 - DFS scan

.SYNOPSIS
Change log

May 10, 2019
-Initial upload to GIT hub

.DESCRIPTION
Author oreynolds@gmail.com

.EXAMPLE
./Get-AssetHealth.ps1

.NOTES

.Link
https://github.com/ovdamn/Get-AssetHealth

#>

$XMLSet = ""
[XML]$XMLSet = Get-Content ".\Settings.xml"

IF (-not($XMLSet)) {
    write-warning -Message "XML settings file not found, script will now exit"
    EXIT
}

Else {

    Write-host "XML settings file will now be parsed and the script will start"

}

$ShortDate = (Get-Date).ToString('MM-dd-yyyy')
$EmailFrom = $XMLSet.Properties.Global.Email.From
$EmailTo = $XMLSet.Properties.Global.Email.To
$EmailSMTP = $XMLSet.Properties.Global.Email.SMTP
$CSS = $XMLSet.Properties.Global.CSS
$ReportsPath = $XMLSet.Properties.Global.ReportsPath
$FilteredAssets = $XMLSet.Properties.Global.vMWARE.FilteredESXi.Asset
$FilteredESXi = $XMLSet.Properties.Global.FilteredAssets.Asset
$vCenter = $XMLSet.Properties.Global.VMWARE.vCenter
$DFSPath = $XMLSet.Properties.Global.DFSPath
$SchTask = $XMLSet.Properties.Global.SchTask

### Create empty arrays
$ESXiHostSummary = @()
$MainArray = @()

$ScriptLog = $XMLSet.Properties.Global.ScriptLog

If (!(test-path $ScriptLog)) {

    Write-Warning "Creating log"
    new-item -ItemType File -path $ScriptLog
    add-content -Value "This log was created $(Get-Date)" -Path $ScriptLog

}

Function Ping-Asset {
  	Param ($Asset)
    
	$error.clear()

    try {

		write-host "Checking if $Asset is online"
        $PingTest = test-connection $Asset -count 3 -EA 0	    

    }
	
    Catch {}

	IF (!($PingTest)) {		
	
    	$PingTest = "Offline"
    
    }
	    			
    Else {$PingTest = "Online"}

    $PingTest

}

Function Get-DrvSpace {
    Param(
    [String]$Asset,
    [String]$Drv
    )
        
    $Disk = Get-WmiObject Win32_LogicalDisk -ComputerName $Asset -Filter "DeviceID='$Drv'" | Select-Object Size, FreeSpace    
    $Size = "{0:N2}" -f ($Disk.Size/1GB)
    $Free = "{0:N2}" -f ($Disk.FreeSpace/1GB)
    Return $Size, $Free    
}

Function Get-Uptime {
    Param($Asset)
    $OS = Get-WmiObject win32_operatingsystem -computer $Asset -EA 0
    $Uptime = (Get-Date) - $OS.ConvertToDateTime($OS.LastBootUpTime)
    Write-Output ($Asset, "Last boot: " + $os.ConvertToDateTime($os.LastBootUpTime)) |out-null
    Write-Output ("Uptime   : " + $uptime.Days + " Days " + $uptime.Hours + " Hours ") |out-null
    write-output $Uptime.Days

    IF ($Uptime.Days -ge 14) {
        Write-warning "Uptime is hot @ $($Uptime.Days) days without a reboot!!!"
        $UptimeAlert = "Yes"
    }

    Else {$UptimeAlert = "No"}

    Return $Uptime.Days, $UptimeAlert

}

Function Get-LicDaysRemain {
    Param ($Asset)
    $LicDaysRem = Get-CimInstance SoftwareLicensingProduct -ComputerName $Asset `
    -Filter "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'" | Where-Object licensestatus -eq 1 | Select-object -expand GracePeriodRemaining
    $LicDaysRem = new-timespan -minutes $LicDaysRem | Select-object -ExpandProperty Days    
    Write-warning "Remaining licensing days left = $LicDaysRem"
    Return $LicDaysRem
}

Function Get-AssetType {
    Param($Asset)    
    $Type = (Get-WMIObject -class Win32_computersystem -ComputerName $Asset)    

    IF (($Type.Model -eq "Virtual Machine") -and ($Type.Manufacturer -eq "Microsoft Corporation")) {$AssetType = "Hyper-V VM"; write-host "$AssetType"}
        
        ElseIF (($Type.model -eq "Vmware Virtual Platform") -and ($Type.Manufacturer -eq "VMware, Inc.")) {$AssetType = "VMware VM"; write-host "$AssetType"}            
        
                Else {$AssetType = $Type.Model; write-host "$AssetType Hardware"}
    
    Return $AssetType
}

Function Get-CPU {
    Param($Asset)
    $CPU = Get-WmiObject -class win32_processor -ComputerName $Asset | Select-object -first 1 | Select-object -expand Name
    write-host "$CPU"
    Return $CPU
    
}

Function Get-OS {
    param($Asset)    
    $OperatingSystem  = (Get-WmiObject -class win32_OperatingSystem -ComputerName $Asset).Caption
    write-host "$OperatingSystem"
    Return $OperatingSystem
}

Function Get-Mem {
    Param($Asset)
    $Memory = [math]::Round((Get-WMIObject -class win32_computersystem -ComputerName $Asset).TotalPhysicalMemory/1GB,2)
    Return $Memory
}

Function Get-Cluster {
    param($Asset)
    $ClusterHealth = Get-ClusterResource -Cluster $Asset | Select-object Name, Ownergroup, ResourceType, OwnerNode, State    
    Return $ClusterHealth
}

Function Move-Cluster {
    Param(
    [String]$Asset,
    [String]$Cluster
    )
    IF (Test-connection -ComputerName $Asset -count 2) {

        Write-host "$Asset online, checking resources and level-setitng to SQL1V as needed"

        IF ($Section2 | Where-Object {$_.Ownernode -ne "$Asset"}) {

            Add-content -Value "WARNING: Level-set of $Cluster resources performed @ $(Get-Date)" -Path $ScriptLog
            Get-ClusterGroup -Cluster $Cluster | Move-ClusterGroup -Cluster $Cluster -Node $Asset
    
        }

        Else {
        
            write-host "No changes required to $Cluster at this time" -ForegroundColor green
        
        }
    }
}    

Function Get-PowerPlan {
    Param($Asset)
    $PowerPlan = Get-CimInstance -ComputerName $Asset -Name root\cimv2\power -Class win32_PowerPlan -Filter "ISActive = 'True'" | Select-object -expand ElementName
    write-host $Powerplan
    Return $PowerPlan
}

Function Get-HotfixRecent {
    Param($Asset)
    $HFX = Get-hotfix -ComputerName $Asset | Sort-Object InstalledOn -ErrorAction SilentlyContinue | Select-object -last 1 | Select-object HotFixID, InstalledOn
    Return $HFX
}

Function Get-SchedTasks {
    Param($Asset)
    $AllTasks = invoke-command -computername $Asset {Get-ScheduledTask -TaskPath "$SchTask" | Get-ScheduledTaskInfo } | Select-object TaskName, LastTaskResult, LastRunTime
    $TasksSummary = @()

    ForEach ($Task in $AllTasks) {    

        If ($Task.LastTaskResult -eq 0) {

            $LastTaskResult = "SUCCESS"

        }

        ElseIf ($Task.LastTaskResult -eq 267011) {

            $LastTaskResult = "NEVER RUN"
            $Task.LastRunTime = "NEVER RUN"

        }

        Else {

            $LastTaskResult = "FAILED"

        }

        $TasksSummary += New-Object PSObject -Property @{

            TaskName = $Task.TaskName
            LastRunResult = $LastTaskResult
            LastRunTime = $Task.LastRunTime
            OwnerNode = $Asset

        }

    }
    
    $TasksSummary = $TasksSummary | Sort-Object TaskName
    Return $TasksSummary

} # End get-Tasks

### Core logic
### Get list of servers

$ScriptStart = Get-Date
Add-content -Value "Script started: $ScriptStart from asset $Env:Computername by user ID $Env:USERNAME" -Path $ScriptLog

If (Get-Module -ListAvailable ActiveDirectory) {
    
    Write-host "Importing AD module"
    import-module ActiveDirectory

}

$Assets = Get-ADComputer -Filter * | Sort-Object DNSHostname | Select-object -Expand Name
$Assets = $Assets | Where {$_ -notin $FilteredAssets}

<#
| Where-Object {$_ -notlike "RS1*"} `
| Where-Object {$_ -notlike "*RS2*"} `
| Where-Object {$_ -notlike "*RS3*"} `
| Where-Object {$_ -notlike "*RS5*"} `
| Where-Object {$_ -notlike "VC*"} `
| Where-Object {$_ -notlike "*CLUSTER*"}
#>

$TotalAssets = $Assets | Measure-object | Select-object -expand Count
$Count = 0

ForEach ($Asset in $Assets) {

    write-host "`r`n"
    write-host "$Count of $TotalAssets checked so far" -ForegroundColor Cyan
    write-host "___________________________________________________________"
    write-host "`r`n"
    
    write-host "Checking $Asset"
    
    $Ping = Ping-Asset $Asset

    If ($Ping -eq "Online") {
        
            write-host "$Asset is Online. Proceeding to capture Uptime.." -foregroundcolor GREEN

            $Uptime = Get-Uptime $Asset
            $UptimeDays  = [int]$Uptime[1]
            $UptimeHigh = $Uptime[2]

            #write-host "Collecting licensed OS days remaining"
            #$LicDaysLeft = Get-LicDaysRemain $Asset
            
            write-host "Checking C drive size/space free"
            $CDrive = Get-DrvSpace -Asset $Asset -Drv c:
            
            write-host "ID'ing hardware or VM type"
            $Type = Get-AssetType -Asset $Asset

            write-host "Get CPU type"
            $CPU = Get-CPU -Asset $Asset

            write-host "Get Memory"
            $Mem = Get-Mem -Asset $Asset

            write-host "Getting Operating System of $Asset"
            $OS = Get-OS -asset $Asset

            write-host "Collecting active power plan on $Asset"
            $PowerPlanActive = Get-PowerPlan -Asset $Asset

            write-host "Collecting most recent Hotfix"
            $HotFixRecent = Get-HotfixRecent -Asset $Asset           
 
    } #Ping        

    If ($Ping -eq "Offline") {
    
        write-host "$Asset offline" -ForegroundColor red
        $UptimeDays = "N/A"
        $UptimeHigh = "N/A"
        $CDrive = ""
        $Type = "N/A"
        $CPU = "N/A"
        $Mem = "N/A"
        $OS = "N/A"
        $PowerPlanActive = "N/A"
        $HotFixRecent = "N/A"
    }       

    $MainArray += New-Object PsObject -property @{
    Asset = $Asset
    PingResults = $Ping
    UptimeDays = $Uptimedays
    UptimeHigh = $UptimeHigh    
    CDriveSize = $CDrive[0]
    CDriveFree = $CDrive[1]
    Type = $Type
    CPU = $CPU
    Mem = $Mem
    OS = $OS
    PowerPlan = $PowerPlanActive
    HotFixRecent = $HotFixRecent

    } # OutArray New-Object

    $Count ++

} #ForEach on $MainArray

### End of Part 1 - main scan

### Part 2 - Scheduled tasks
write-host "Checking scheduled tasks on various servers"
### ID current FS owner

$FSOwner = (Get-DFSNFolderTarget -path $DFSPath | Where-Object {$_.state -eq "Online"} | Select-object -expand TargetPath).Split("\")[2]
$Section2 =  Get-SchedTasks -Asset $FSOwner

### Part XX - CTX XD scan

#write-host "Checking Citrix assets"
#$CTXSite1VDAS = @(invoke-command -ComputerName XDC1V -ScriptBlock {

 #   Add-PSSnapin Citrix*
 #   Get-BrokerMachine    

#} | Select-object @{E={$_.DNsname};Name="VDA"}, RegistrationState , DesktopGroupName , @{E={$_.ControllerDNSName};Name="CTX DDC"}, @{E={$_.AgentVersion};Name="VDA Binary version"})

# $SectionXX = $CTXSite1VDAS

### Part 5a/b - VMWARE vCenter asset scan

IF (Get-Module -name vmware.powercli -ListAvailable) {
    write-host "Loading VMWARE PowerCLI"
    Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue
    #Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $False -Confirm:$False
    Connect-VIServer -Server $vCenter -force

    write-host "Level set of VMs autostart"    
    Get-VM | Where {$_.name -notin $FilteredESXi} | Get-VMStartPolicy | Where StartOrder -eq $Null | Set-VMStartPolicy -StartAction PowerOn -StartDelay 30

    $ESXiVMS = Get-VM | Select-object Name, VMHost, @{N="Datastore";E={[string]::Join(',',(Get-Datastore -Id $_.DatastoreIdList | Select-object -ExpandProperty Name))}}, PowerState, UsedSpaceGB, NumCPU, MemoryGB
    $ESXiDS = Get-DataStore | Select-object Name, State, Datacenter, CapacityGB, FreeSpaceGB | Sort-Object Name
    $TotalESXiDS = $ESXiDS | Measure-Object | Select-object -ExpandProperty Count
    $TotalESXiVMs = $ESXiVMS | Measure-Object | Select-object -ExpandProperty Count    
    
    $ESXiVMHosts = Get-VMhost

    ForEach ($ESXiVMHost in $ESXiVMHosts) {
    
        write-host "Checking $ESXiVMHost.name"
        $ESXIVmCount = Get-VMhost -Name $ESXiVMHost.name  | Get-VM | Measure-Object | Select-Object -ExpandProperty Count
        $ESXiHostData = Get-VMHost -name $ESXiVMHost.name  | Select-object Name, ConnectionState, PowerState, Model, NumCPU, ProcessorType, Version, Build,`
        @{E={[math]::Round($_.MemoryTotalGB,2)};Label='Host Memory (GB)'}, @{E={[math]::Round($_.MemoryUsageGB,2)};Label="Host memory in use (GB)"}    
    
        $Props =@{
        "VM Count" = $ESXIVmCount
        ESXiHost = $ESXiHostData.Name   
        ConnectionState = $ESXiHostData.ConnectionState
        PowerState = $ESXiHostData.PowerState
        Model = $ESXiHostData.Model
        CPUType = $ESXiHostData.ProcessorType
        CPUCount = $ESXiHostData.NumCpu
        ESXiVer = $ESXiHostData.Version
        ESXiBuild = $ESXiHostData.Build
        "Host Memory Total (GB)" = $ESXiHostData."Host Memory (GB)"
        "Host Memory in use (GB)" = $ESXiHostData."Host memory in use (GB)"
        }

        $ESXiHostSummary += New-object PSObject -Property $Props | Select ESXiHost, PowerState, ConnectionState, Model, CPUType, CPUCount, "Host memory total (GB)", "Host memory in use (GB)", ESXIver, ESXIBuild, "VM Count"        

    } #ForEach $ESXihost
}

Else {

    $ESXiVMS = "PowerCLI not available on asset $Env:Computername"
    $ESXiDS = "PowerCLI not available on asset $Env:Computername"

}

### Data Summary
$Section1 = $MainArray | Select-object Asset, PingResults, UptimeDays, UptimeHigh, @{Expression={$_.cDriveSize};Label="C Drive Size (GB)"} , @{Expression={$_.CDriveFree};Label="C Drive Free (GB)"},`
Type, CPU, Mem, OS, PowerPlan, HotFixRecent | Sort-Object UptimeDays -Descending

$Section1 | Export-csv $ReportsPath\AssetScan-$Shortdate.csv -NoTypeInformation

### Reboots of assets with uptime over 14 days

write-host "Asset scan has completed at $(Get-date). Assets with 14 days or more will be rebooted"
write-host "`r`n"

$RebootPool = $Section1 | Where-Object {$_.UptimeHigh -eq "yes"} | Where-Object {$_.Asset -notin $FilteredReboot} | Select-object Asset

ForEach ($Asset in $RebootPool) {

    $Asset = $($Asset.Asset)
    write-warning "Rebooting $Asset now"
    start-sleep -s 30
    restart-computer -ComputerName $Asset -Force -Timeout 60 -wait
    add-content -Value "$Asset was rebooted on $(Get-date) by $Env:username" -path $ScriptLog
}

### Email code
$Head = Get-Content $CSS

### Section 1
$Pre1 = "<H2>Part 1 - Desktop, laptop, server overview data (ping, uptime, C drive free space, hot fix installs) - Data is from $(Get-Date)</H2>"
$Pre1 += "<br><br>"
$Section1HTML = $Section1 | ConvertTo-HTML -Head $Head -PreContent $Pre1 -As Table | Out-String

### Section 2
$Pre2 = "<br><br>"
$Pre2 += "<H2>Part 2 - Scheduled tasks report</H2>"
$Pre2 += "<br><br>"
$Section2HTML = $Section2 | ConvertTo-HTML -Head $Head -PreContent $Pre2 -As Table | Out-String

## Section 3a - Vmware assets  
$Pre3a = "<br><br>"
$Pre3a += "<H2>Part 3a - VMWARE vCenter asset report ($TotalESXIVMs VMS) </H2>"
$Pre3a += "<br><br>"
$Section3aHTML = $ESXiVMS | ConvertTo-HTML -Head $Head -PreContent $Pre3a -As Table | Out-String

## Section 3b - Vmware assets
$Pre3b = "<br><br>"
$Pre3b += "<H2>Part 3b - VMWARE vCenter DataStore report ($TotalESXiDS datastores)</H2>"
$Pre3b += "<br><br>"
$Section3bHTML = $ESXiDS | ConvertTo-HTML -Head $Head -PreContent $Pre3b -As Table | Out-String

## Section 3c - Vmware hosts
$Pre3c = "<br><br>"
$Pre3c += "<H2>Part 3c - VMWARE vCenter hosts</H2>"
$Pre3c += "<br><br>"
$Section3cHTML = $ESXiHostSummary | ConvertTo-HTML -Head $Head -PreContent $Pre3c -As Table | Out-String

### Section 4 - DFS
$DFSActive = (Get-DfsnFolderTarget -Path "\\Superdry.loc\DFS\Downloads" | Where-Object State -eq Online).Targetpath.Split("\\")[2]
$Pre4 = "<br><br>"
$Pre4 += "<H2>Part 4 - DFS Owner</H2>"
$Pre4 += "<br><br>"
$Section4HTML = $DFSActive | ConvertTo-HTML -Head $Head -PreContent $Pre4 -As Table | Out-String

### Section XX
#$Pre4 = "<br><br>"
#$Pre4 += "<H2>Part 4 - Citrix XenDesktop Report - data is from $(Get-Date)</H2>"
#$Pre4 += "<br><br>"
#$Section4HTML = $Section4 | ConvertTo-HTML -Head $Head -PreContent $Pre4 -As Table | Out-String

### Section  XX - DORMANT
#$Pre4 = "<br><br>"
#$Pre4 += "<H2>Part 3 - Performance Counters - data is from $(Get-Date)</H2>"
#$Pre4 += "<br><br>"
#$Section3HTML = $Section4 | ConvertTo-HTML -Head $Head -PreContent $Pre4 -As Table | Out-String

## Combine sections
$TSBody = ""
$TSBody += "$Section1HTML" + "$Section2HTML" + "$Section3aHTML" + "$Section3bHTML" + $Section3cHTML

# $TSBody | Out-File C:\inetpub\wwwroot\ServerScans\Current.htm

$Subject = "Daily systems report for $ShortDate"
Write-host "Sending message to $EmailTo" -ForegroundColor cyan
Send-MailMessage -From $EmailFrom -to $EmailTo -Subject $Subject -Body $TSBody -BodyAsHtml -SmtpServer $SMTPServer -UseSsl

$ScriptEnd = Get-Date

$TotalScriptTime = $ScriptEnd - $ScriptStart | Select-object Hours, Minutes, Seconds
$Hours = $TotalScriptTime | Select-object -expand Hours
$Mins = $TotalScriptTime | Select-object -expand Minutes
$Seconds = $TotalScriptTime | Select-object -expand Seconds

Add-content -Value "Script ended @: $ScriptEnd. Total processing time of $Hours hours, $Mins mins, $Seconds seconds" -Path $ScriptLog