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

May 11, 2019
-Fixed sch tasks and email
-Used space (GB) rounded to 2 $ places

May 12, 2019
-Datastore total rounded to 2 decimal places

May 12, 2019
-$RunningPath created to find correct path to XML
-Write-CustomLog function added
-Write-EventLog used for key events

May 13, 2019
-$Running path captured in txt/evt logs

May 14, 2019
-Part 4 now XTRA, enabled code to capture current DFS owner
-Part 3b now captures VMWARE DRS events instead of data store info

May 15, 2019
-Amended logic for DRS section text
-Removed XTRA section, moved to newly re-named Part 2

June 21, 2019
-Changes to Write-CustomLog to include write-eventlog

June 26, 2019
-Get-VMhost | Get-VMHostStartPolicy | Where {$_.enabled -eq $False} | Set-VMHostStartPolicy -Enabled

July 25, 2019
-Re-added VMWARE datastore

July 26, 2019
-Corrected missing $True on Set-StartPolicy

July 28, 2019
-vSan activated on RS2/RS3 on July 27, 2019 means a lot more events, as such Get-VIEvent -MaxSamples changed to 10000 to accomodate 
-VMWARE Datastore capacity rounded

Sept 20, 2019
-Changed DRS events range

Aug 10, 2020
-Added check / install of Nuget module
-Added check / install of PowerCLI module

Aug 11, 2020
-Updated to include new variables for use with email via Gmail SMTP

Sept 2, 2020
-Various DFS node/owner code updates

Sept 27, 2020
-Updated to filter out AD objects with custom OS of "vmware" set

Nov 4, 2020
-Added AD Account info section: Showing account status, name and pw expiration date

Nov 11, 2020
-Updated to filter out vCLS objects

Feb 16, 2021
-Code to check check for remaining licensing days left added back

Feb 18, 2020
-Code hygiene

.DESCRIPTION
Author oreynolds@gmail.com

.EXAMPLE
./Get-AssetHealth.ps1

.NOTES

.Link
https://github.com/ovdamn/Get-AssetHealth

#>
### Functions

Function Write-CustomLog {
    Param(
    [String]$ScriptLog,    
    [String]$Message,
    [String]$Level
    )

    switch ($Level) { 
        'Error' 
            {
            $LevelText = 'ERROR:' 
            $Message = "$(Get-Date): $LevelText Ran from $Env:computername by $($Env:Username): $Message"
            Write-host $Message -ForegroundColor RED            
            } 
        
        'Warn'
            { 
            $LevelText = 'WARNING:' 
            $Message = "$(Get-Date): $LevelText Ran from $Env:computername by $($Env:Username): $Message"
            Write-host $Message -ForegroundColor YELLOW            
            } 

        'Info'
            { 
            $LevelText = 'INFO:' 
            $Message = "$(Get-Date): $LevelText Ran from $Env:computername by $($Env:Username): $Message"
            Write-host $Message -ForegroundColor GREEN            
            } 

        }
        
        Add-content -value "$Message" -Path $ScriptLog
}


Function Ping-Asset {
  	Param($Asset)
    
	$error.clear()

    try {
        
        Write-host -Object "Checking if $Asset is online"
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

Function Get-LicStatus {
    Param ($Asset)
    
    $LicDaysRem = Get-CimInstance SoftwareLicensingProduct -ComputerName $Asset -Filter "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'" | Where-Object -FilterScript {$_.LicenseFamily -like "*eval*"} `
    | Select-object -expand GracePeriodRemaining

    IF ($LicDaysRem -ne $Null) {  
    
        $LicDaysRem = new-timespan -minutes $LicDaysRem | Select-object -ExpandProperty Days    
        Write-warning "Remaining licensing days left = $LicDaysRem"

    }

    Else {

        $LicDaysRem = "Valid license installed"
        

    }
    
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

            Write-CustomLog -Message "Level-set of $Cluster resources performed" -Level WARN -ScriptLog $ScriptLog            
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
    Param($Asset, $SchTask)
    
    $AllTasks = invoke-command -computername $Asset {
        Param($SchTask)    
        Get-ScheduledTask -TaskPath $SchTask | Get-ScheduledTaskInfo 
    
    } -ArgumentList $SchTask | Select-object TaskName, LastTaskResult, LastRunTime
    
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
        }

    }
    
    $TasksSummary = $TasksSummary | Sort-Object TaskName
    Return $TasksSummary

} # End get-Tasks

IF (-not(Get-PackageProvider -ListAvailable -name NUget)) {

    Install-PackageProvider -Name NuGet -force -Confirm:$False
}

IF (-not(Get-Module -ListAvailable -name VMware.PowerCLI)) {

    Install-Module -Name VMware.PowerCLI -AllowClobber -force
}

### Non-XML variables, amend as required for your environment
$EventIDSrc = "Asset Scan"
$EventIDSection = "Application"
[Int32]$EventID = 0

$ShortDate = (Get-Date).ToString('MM-dd-yyyy')
$Yesterday = (Get-Date).AddDays(-1).ToString('MM-dd-yyyy')

$RunningPath = Split-Path $MyInvocation.MyCommand.Path -Parent

$ESXiHostSummary = @()
$MainArray = @()

If (-not([System.Diagnostics.EventLog]::SourceExists("$EventIDSrc"))) {
    
    write-host "Creating $EventIDSrc"
    New-EventLog -LogName $EventIDSection -Source $EventIDSrc

}

Remove-Variable XMLSet

[XML]$XMLSet = Get-Content ($RunningPath + "\Settings.xml")

$ScriptLog = $XMLSet.Properties.Global.ScriptLog

IF (-not($XMLSet)) {

    Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -EventId $EventID -EntryType Warning -Message "XML settings file not found under $RunningPath, script will now exit"
    write-warning -Message "XML settings file not found under $RunningPath, script will now exit"    
    EXIT
}

Else {

    Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -EventId $EventID -EntryType INFO -Message "Settings will be enumerated from XML settings file found under $RunningPath"
    Write-CustomLog -Message "Settings will be enumerated from XML settings file found under $RunningPath" -Level info -ScriptLog $ScriptLog

}

### Variables from XML
$EmailFrom = $XMLSet.Properties.Global.Email.From
$EmailTo = $XMLSet.Properties.Global.Email.To
$EmailSMTP = $XMLSet.Properties.Global.Email.SMTP
$EmailPort = $XMLSet.Properties.Global.EMail.Port
$EmailPassW = $XMLSet.Properties.Global.Email.PassW
$EmailCred = New-Object Management.Automation.PSCredential $EmailFrom, ($EmailPassW | ConvertTo-SecureString -AsPlainText -Force)

$CSS = $XMLSet.Properties.Global.CSS
$ReportsPath = $XMLSet.Properties.Global.ReportsPath
$FilteredAssets = $XMLSet.Properties.Global.FilteredAssets.Asset
$FilteredESXi = $XMLSet.Properties.Global.vMWARE.FilteredESXi.Asset
$vCenter = $XMLSet.Properties.Global.VMWARE.vCenter
$DFSPath = $XMLSet.Properties.Global.DFSPath
[String]$SchTask = $XMLSet.Properties.Global.SchTask

If (!(test-path $ScriptLog)) {

    Write-Warning "Creating log"
    new-item -ItemType File -path $ScriptLog
    Write-CustomLog -Message "$SciptLog created" -ScriptLog $ScriptLog -Level info    

}

### FUNCTIONS

### START ME UP
### Get list of servers

$ScriptStart = Get-Date
Write-CustomLog -Message "Script started" -Level INFO -ScriptLog $ScriptLog

If (Get-Module -ListAvailable ActiveDirectory) {
    
    Write-host "Importing AD module"
    import-module ActiveDirectory

}

Get-ADComputer -LDAPFilter "(OperatingSystem=vmware)"

$Assets = Get-ADComputer -Filter {OperatingSystem -ne 'vmware'} | Sort-Object DNSHostname | Select-object -Expand Name
$Assets = $Assets | Where-object {$_ -notin $FilteredAssets}

If (-not($Assets)) {

    Write-CustomLog -Message "The list of assets was not populated. As such, the script will exit" -Level ERROR -ScriptLog $ScriptLog
    Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -eventID $EventID -Message "The list of assets was not populated. As such, the script will exit" -EntryType Error
    EXIT
}

$TotalAssets = $Assets | Measure-object | Select-object -expand Count
$Count = 0

Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -EventID $EventID -Message "$TotalAssets assets will be checked" -EntryType Information

ForEach ($Asset in $Assets) {

    write-host "`r`n"
    write-host "$Count of $TotalAssets checked so far" -ForegroundColor Cyan
    write-host "___________________________________________________________"
    write-host "`r`n"    
    
    write-host "Checking $Asset"
    Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -eventID $EventID -Message "Checking $Asset" -EntryType Information
    
    $Ping = Ping-Asset $Asset -ScriptLog $ScriptLog

    If ($Ping -eq "Online") {
        
            write-host "$Asset is Online. Proceeding to capture Uptime.." -foregroundcolor GREEN

            $Uptime = Get-Uptime $Asset
            $UptimeDays  = [int]$Uptime[1]
            $UptimeHigh = $Uptime[2]

            write-host "Collecting licensed OS days remaining"
            $LicStatus = Get-LicStatus $Asset
            
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
        $LicStatus = "N/A"
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
    LicStatus = $LicStatus
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
Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -eventID $EventID -Message "Part 2 - collecting schedled tasks" -EntryType Information
write-host "Checking scheduled tasks on various servers"
### ID current FS owner

Remove-variable Items
$DFSOwner = (dfsutil.exe client property state \\ad.getvpro.com\DFS\Binaries) | ForEach {$items += $_.split("=")  }
$DFSOwner = $Items | Where-object {$_ -like "Active, Online*"}
$DFSOwner = ($Items | Where-object {$_ -like "Active, Online*"}).Split("\\")[2]
$Section2 =  Get-SchedTasks -Asset $DFSOwner -SchTask $SchTask

### Part 3a/b/c - VMWARE vCenter asset scan

Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -eventID $EventID -Message "Part 3 - vmware vCenter asset scan" -EntryType Information

IF (Get-Module -name vmware.powercli -ListAvailable) {
    write-host "Loading VMWARE PowerCLI"
    Import-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue
    
    #Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $False -Confirm:$False
    
    Connect-VIServer -Server $vCenter -force

    write-host "Level set of VMs autostart"
    Get-VMhost | Get-VMHostStartPolicy | Where-object {$_.enabled -eq $False} | Set-VMHostStartPolicy -Enabled:$True
    Get-VM | Where-object {$_.name -notin $FilteredESXi} | Where-object {$_.name -notlike "vCLS (*)"} | Get-VMStartPolicy | Where-object StartOrder -eq $Null | Set-VMStartPolicy -StartAction PowerOn -StartDelay 30
    $ESXiVMS = Get-VM | Where-object {$_.name -notlike "vCLS (*)"} | Select-object Name, VMHost, @{N="Datastore";E={[string]::Join(',',(Get-Datastore -Id $_.DatastoreIdList | Select-object -ExpandProperty Name))}},`
    PowerState, @{E={[math]::Round($_.UsedSpaceGB,2)};Name="Used Space (GB)"}, NumCPU, MemoryGB
    
    $ESXiDS = Get-DataStore | Select-object Name, State, @{E={[Math]::Round($_.CapacityGB,2)};Label="Capacity (GB"}, @{E={[Math]::Round($_.FreeSpaceGB,2)};Label="Free Space (GB)"} | Sort-Object Name
    
    $TotalESXiDS = $ESXiDS | Measure-Object | Select-object -ExpandProperty Count
    $TotalESXiVMs = $ESXiVMS | Measure-Object | Select-object -ExpandProperty Count    
    
    $ESXiVMHosts = Get-VMhost

    ForEach ($ESXiVMHost in $ESXiVMHosts) {
    
        write-host "Checking $ESXiVMHost.name"
        $ESXIVmCount = Get-VMhost -Name $ESXiVMHost.name  | Get-VM | Where-object {$_.name -notlike "vCLS (*)"} | Measure-Object | Select-Object -ExpandProperty Count
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

$DRSEventsToday = Get-VIEvent -MaxSamples 10000 -Start $Yesterday | Where-object {$_.FullFormattedMessage -like "*Migrating*"} `
| Where-object {$_.Objectname -ne $Null} | Select @{E={$_.Objectname};Name="VM"}, @{E={$_.CreatedTime};Name="Time"}, @{E={$_.FullFormattedMessage};Name="DRS vMotion detail"} | Sort VM -Unique

### Data Summary
$Section1 = $MainArray | Select-object Asset, PingResults, UptimeDays, UptimeHigh, LicStatus, @{Expression={$_.cDriveSize};Label="C Drive Size (GB)"} , @{Expression={$_.CDriveFree};Label="C Drive Free (GB)"},`
Type, CPU, Mem, OS, PowerPlan, HotFixRecent | Sort-Object UptimeDays -Descending

$Section1 | Export-csv $ReportsPath\AssetScan-$Shortdate.csv -NoTypeInformation

### Reboots of assets with uptime over 14 days
write-host "`r`n"
write-host "Asset scan has completed at $(Get-date). Assets with 14 days or more will be rebooted"
write-host "`r`n"

$RebootPool = $Section1 | Where-Object {$_.UptimeHigh -eq "yes"} | Where-Object {$_.Asset -notin $FilteredReboot} | Select-object Asset

ForEach ($Asset in $RebootPool) {

    $Asset = $($Asset.Asset)
    write-warning "Rebooting $Asset now"
    start-sleep -s 30
    restart-computer -ComputerName $Asset -Force -Timeout 60 -wait
    Write-CustomLog -message "$Asset was rebooted" -Level WARN -ScriptLog $ScriptLog
}

### HTML  code
### https://adamtheautomator.com/powershell-convertto-html/
$Head = Get-Content "\\ad.getvpro.com\DFS\BINARIES\Software\SCRIPTS\WINDOWS SERVER\Get-AssetHealth\CSS\CSS.XML"

<#
$Head = @"
<style>

    h1 {

        font-family: Arial, Helvetica, sans-serif;
        color: #e68a00;
        font-size: 28px;

    }

    
    h2 {

        font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 16px;

    }

    
    
   table {
		font-size: 12px;
		border: 0px; 
		font-family: Arial, Helvetica, sans-serif;
	} 
	
    td {
		padding: 4px;
		margin: 0px;
		border: 0;
	}
	
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 11px;
        text-transform: uppercase;
        padding: 10px 15px;
        vertical-align: middle;
	}

    tbody tr:nth-child(even) {        
        background: #a9a9a9;
    }
        
</style>
"@
#>

### Section 1
$Pre1 = "<H2>Part 1 - Desktop, laptop, server overview data (ping, uptime, C drive free space, hot fix installs) - Data is from $(Get-Date)</H2>"
$Pre1 += "<br><br>"
$Section1HTML = $Section1 | ConvertTo-HTML -Head $Head -PreContent $Pre1 -As Table | Out-String

### Section 2 - File server and related scheduled tasks
$Pre2 = "<br><br>"
$Pre2 += "<H2>Part 2 - File server and scheduled tasks info</H2>"
$Pre2 += "<H3>DFS Node Status: $DFSOwner</H3>"
$Section2HTML = $Section2 | ConvertTo-HTML -Head $Head -PreContent $Pre2 -As Table | Out-String

## Section 3a - Vmware assets  
$Pre3a = "<br><br>"
$Pre3a += "<H2>Part 3a - VMWARE vCenter asset report ($TotalESXIVMs VMS) </H2>"
$Section3aHTML = $ESXiVMS | ConvertTo-HTML -Head $Head -PreContent $Pre3a -As Table | Out-String

## Section 3b - Vmware Datastore (Dormant as of May 14, 2019)
$Pre3b = "<br><br>"
$Pre3b += "<H2>Part 3b - VMWARE vCenter DataStore report ($TotalESXiDS datastores)</H2>"
$Pre3b += "<br><br>"
$Section3bHTML = $ESXiDS | ConvertTo-HTML -Head $Head -PreContent $Pre3b -As Table | Out-String

## Section 3c - VMWARE DRS events
If (-not($DRSEventsToday)) {

    $Pre3c = "<br><br>"
    $Pre3c += "<H2>Part 3c - NO VMWARE vCenter DRS events from today</H2>"
    $Pre3c += "<br><br>"
    $Section3cHTML = $Pre3c
}

Else {

    $Pre3c = "<br><br>"
    $Pre3c += "<H2>Part 3c - VMWARE vCenter DRS events from today</H2>"
    $Pre3c += "<br><br>"    
    $Section3cHTML = $DRSEventsToday | ConvertTo-HTML -Head $Head -PreContent $Pre3c -As Table | Out-String

}

## Section 3d - Vmware hosts
$Pre3d = "<br><br>"
$Pre3d += "<H2>Part 3d - VMWARE vCenter hosts</H2>"
$Section3dHTML = $ESXiHostSummary | ConvertTo-HTML -Head $Head -PreContent $Pre3d -As Table | Out-String

## Section 4 - AD Account state, expiration

$ADAccounts = Get-ADUser -filter {PasswordNeverExpires -eq $False} –Properties "DisplayName", "msDS-UserPasswordExpiryTimeComputed" | Where-object {$_.DisplayName.Length -ne 0} `
| Select-Object -Property "Displayname", Enabled, @{Name="ExpiryDate";Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}} | Sort-Object ExpiryDate | `
 Select @{E={$_.DisplayName};Name='Account'}, @{E={$_.Enabled};Name='Account enabled'}, @{E={$_.ExpiryDate};Name='Password Expiration date'} 

$Pre4 = "<br><br>"
$Pre4 += "<H2>Part 4 - AD Account info</H2>"
$Section4HTML = $ADAccounts | ConvertTo-HTML -Head $Head -PreContent $Pre4 -As Table | Out-String

$Subject = "Daily systems report for $ShortDate"

## Combine sections
$HTMLReport = ""
#$HTMLReport = ConvertTo-HTML -Body "$Section1HTML $Section2HTML $Section3aHTML $Section3bHTML $Section3cHTML $Section3dHTML $Section4HTML" #-Title $Subject
$HTMLReport += "$Section1HTML" + "$Section2HTML" + "$Section3aHTML" + "$Section3bHTML" + "$Section3cHTML" + "$Section3dHTML" + "$Section4HTML"

<#
$HTMLReport | Out-file "c:\installs\Get-AssetHealth-Test-Report.html"
Write-Warning "TEMP EXIT"
EXIT
#>

Write-CustomLog -Message "Sending message to $EmailTo" -Level INFO -ScriptLog $ScriptLog

Send-MailMessage -From $EmailFrom -to $EmailTo -Subject $Subject -Body $HTMLReport -BodyAsHtml -SmtpServer $EmailSMTP -UseSsl -Credential $EmailCred -Port $EmailPort

$ScriptEnd = Get-Date

$TotalScriptTime = $ScriptEnd - $ScriptStart | Select-object Hours, Minutes, Seconds
$Hours = $TotalScriptTime | Select-object -expand Hours
$Mins = $TotalScriptTime | Select-object -expand Minutes
$Seconds = $TotalScriptTime | Select-object -expand Seconds

Write-EventLog -LogName $EventIDSection -Source $EventIDSrc -EventID $EventID -EntryType Information -Message "Script completed. Total processing time of $Hours hours, $Mins mins, $Seconds seconds"

Write-CustomLog -Message "Script completed. Total processing time of $Hours hours, $Mins mins, $Seconds seconds" -Level INFO -ScriptLog $ScriptLog