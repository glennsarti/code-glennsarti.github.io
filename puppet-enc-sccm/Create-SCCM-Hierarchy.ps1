# The SCCM Module is not in the usual Autoload location
Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'

# Set the location to the SCCM Site of this server
$sccmSite = (Get-PSDrive | ? { $_.Provider -like '*CMSite'} | Select -First 1).Name + ':'
Set-Location -Path $sccmSite

$puppetenc = (@"
{
  "config_mgr": {
    "environments_folder": "Puppet ENC\\Puppet Environments",
    "roles_folder": "Puppet ENC\\Puppet Roles",
    "profiles_folder": "Puppet ENC\\Puppet Profiles",
    "classes_folder": "Puppet ENC\\Puppet Classes",
    "root_limiting_collection": "All Systems",

    "environments_collection_prefix": "Puppet::Environment::",
    "roles_collection_prefix": "Puppet::Role::",
    "profiles_collection_prefix": "Puppet::Profile::",
    "Classes_collection_prefix": "Puppet::Class::"
  },
  
  "environments": [ "production","test" ],
  
  "roles": [
    {
      "name": "AdvWorks-Load-Balancer",
      "profiles" : [ "HAProxyService" ]
    },
    {
      "name": "AdvWorks-WebServer",
      "profiles" : [ "IISWebServer","IISBaselineSecurity","AdvWorksWebsite" ]
    },
    {
      "name": "AdvWorks-Database",
      "profiles" : [ "MSSQLServer","MSSQLServerBaselineSecurity","AdvWorksDatabase" ]
    }
  ],
  
  "profiles": [
    {
      "name": "HAProxyService",
      "classes": [ "haproxy" ]
    },
    {
      "name": "IISWebServer",
      "classes": [ "shared::iis","shared::iis::no_default_website" ]
    },
    {
      "name": "IISBaselineSecurity",
      "classes": [ "shared::iis::security" ]
    },
    {
      "name": "AdvWorksWebsite",
      "classes": [ "advworks::website" ]
    },
    {
      "name": "MSSQLServer",
      "classes": [ "shared::mssql" ]
    },
    {
      "name": "MSSQLServerBaselineSecurity",
      "classes": [ "shared::mssql::security" ]
    },
    {
      "name": "AdvWorksDatabase",
      "classes": [ "advworks::database" ]
    }
  ]
}
"@ | ConvertFrom-JSON -ErrorAction Stop)

if ($puppetenc -eq $null) { Throw "Invalid JSON" }

# Helper function for creating a collection refresh schedule
Function New-RandomSchedule()
{
  "01/01/2000 $((Get-Random -Min 0 -Max 23).ToString('00')):$((Get-Random -Min 0 -Max 59).ToString('00')):00"
}

Write-Host "Processing Collections..."

# Create the environments
$puppetenc.environments | % {
  $EnvName = $_
  $CollectionName = "$($puppetenc.config_mgr.environments_collection_prefix)$EnvName"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.environments_folder)" | Out-Null    
  }
}

# Create the roles
$puppetenc.roles | % {
  $Role = $_.name
  $CollectionName = "$($puppetenc.config_mgr.roles_collection_prefix)$Role"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.roles_folder)" | Out-Null    
  }
}

# Create the profiles
$puppetenc.profiles | % {
  $PupProfile = $_.name
  $CollectionName = "$($puppetenc.config_mgr.profiles_collection_prefix)$PupProfile"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.profiles_folder)" | Out-Null    
  }
}

# Generate the classes list
$puppetenc.profiles | % { $_.classes | % { Write-Output $_ } } | Select -Unique | % {
  $ClassName = $_
  $CollectionName = "$($puppetenc.config_mgr.classes_collection_prefix)$ClassName"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.classes_folder)" | Out-Null    
  }
}

Write-Host "Processing Collection Memberships..."
# Associate profiles to roles
$puppetenc.roles | % {
  $Role = $_.name
  $RoleCollectionName = "$($puppetenc.config_mgr.roles_collection_prefix)$Role"
  
  $roleColl = Get-CMDeviceCollection -Name $CollectionName
  if ($roleColl -eq $null) { throw "Missing Role"}

  $_.profiles | % { 
    $PupProfile = $_
    $ProfileCollectionName = "$($puppetenc.config_mgr.profiles_collection_prefix)$PupProfile"

    $includeRule = Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $ProfileCollectionName -IncludeCollectionName $RoleCollectionName

    if ($includeRule -eq $null) {
      Write-Host "Adding $Role to $PupProfile"
      Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $ProfileCollectionName -IncludeCollectionName $RoleCollectionName | Out-Null
    }
  }
}

$puppetenc.profiles | % {
  $PupProfile = $_.name
  $ProfileCollectionName = "$($puppetenc.config_mgr.profiles_collection_prefix)$PupProfile"
  
  $ProfileColl = Get-CMDeviceCollection -Name $CollectionName
  if ($ProfileColl -eq $null) { throw "Missing Profile"}

  $_.classes | % { 
    $ClassName = $_
    $ClassCollectionName = "$($puppetenc.config_mgr.classes_collection_prefix)$ClassName"

    $includeRule = Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $ClassCollectionName -IncludeCollectionName $ProfileCollectionName

    if ($includeRule -eq $null) {
      Write-Host "Adding $PupProfile to $ClassName"
      Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $ClassCollectionName -IncludeCollectionName $ProfileCollectionName | Out-Null
    }
  }
}
