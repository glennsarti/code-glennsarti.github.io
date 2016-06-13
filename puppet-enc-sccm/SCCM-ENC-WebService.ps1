[cmdletBinding(SupportsShouldProcess=$false,ConfirmImpact='Low')]
param(
  [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
  $HTTPEndPoint = 'http://*:8080/'

  # SCCM Info
  ,[Parameter(Mandatory=$true,ValueFromPipeline=$false)]
  $ConfigMgrSite

  # SCCM Database Settings
  ,[Parameter(Mandatory=$true,ValueFromPipeline=$false)]
  $DatabaseServer

  ,[Parameter(Mandatory=$true,ValueFromPipeline=$false)]
  $DatabaseUsername

  ,[Parameter(Mandatory=$true,ValueFromPipeline=$false)]
  $DatabasePassword
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

$DatabaseName = "CM_$($ConfigMgrSite)"
# SCCM Collection Settings
$EnvironmentCollectionPrefix = 'Puppet::Environment::'
$RoleCollectionPrefix = 'Puppet::Role::'
$ProfileCollectionPrefix = 'Puppet::Profile::'
$ClassCollectionPrefix = 'Puppet::Class::'
# Configuration
$HostnameRegex = '^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'

function Get-MSSQLQuery {
  [cmdletBinding(SupportsShouldProcess=$false,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [Alias("Connection")]
    [object]$ConnectionObject,

    [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Query,
  
    [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [Alias("Timeout")]
    [int]$QueryTimeout = 120
  )
  Process {
    if ($ConnectionObject.State -ne "Closed")
    {
      Throw "Connection is not a closed state"
      return $null
	  }
    $ConnectionObject.Open()
    $cmd = new-object system.Data.SqlClient.SqlCommand($Query,$ConnectionObject)
    $cmd.CommandTimeout = $QueryTimeout
    $ds = New-Object system.Data.DataSet
    $da = New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
    [void] $da.fill($ds)
    $ConnectionObject.Close()
    $ds.Tables    
  }
}
function Get-MSSQLConnection {
  [cmdletBinding(SupportsShouldProcess=$false,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [Alias("Server")]
    [string]$ServerInstance,

    [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Database,

    [Parameter(ParameterSetName="IntegratedSecurity",Mandatory=$true,ValueFromPipeline=$false)]
    [switch]$IntegratedSecurity,
  
    [Parameter(ParameterSetName="SQLSecurity",Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Username,
    [Parameter(ParameterSetName="SQLSecurity",Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Password,
  
    [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [switch]$OpenConnection = $false,

    [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [Alias("Timeout")]
    [int]$ConnectionTimeout = 30
  )
  Process {
    $conn = new-object System.Data.SqlClient.SQLConnection
    $ConnectionString = ""
    
    switch ($PsCmdlet.ParameterSetName)
    {
      "IntegratedSecurity" { $ConnectionString = "Server={0};Database={1};Integrated Security=SSPI;Connect Timeout={2}" -f $ServerInstance,$Database,$ConnectionTimeout; break; }
      "SQLSecurity"        { $ConnectionString = "Server={0};Database={1};User Id={2};Password={3};Connect Timeout={4}" -f $ServerInstance,$Database,$Username,$Password,$ConnectionTimeout; break; }
      default { Throw "Unknown ParameterSet"; return $null; }
    }
    if ($ConnectionString -ne "")
    {
      $conn.ConnectionString = $ConnectionString
      if ($OpenConnection) { $conn.Open() }
      
      $conn
    }
    else
    {
      Throw "Bad connection string"
      return $null;
	  }
  }
}
function Confirm-DBConnectivity() {
  try {
    $sqlConn = Get-MSSQLConnection -ServerInstance $DatabaseServer `
        -Database $DatabaseName -Username $DatabaseUsername -Password $DatabasePassword
    
    $dbQuery = Get-MSSQLQuery -ConnectionObject $sqlConn -Query "SELECT TOP 1 ResourceID FROM v_RA_System_ResourceNames"
    return $true
  }
  catch [System.Exception] {
     Write-Verbose $_
     return $false 
  }
}

function Get-NodeResponse($NodeName) {
  try
  {
    Write-Verbose "Querying $NodeName ..."
    $sqlConn = Get-MSSQLConnection -ServerInstance $DatabaseServer `
        -Database $DatabaseName -Username $DatabaseUsername -Password $DatabasePassword
    
    # Get the list of all collections for this node...
    $query = "SELECT" + `
             " v_FullCollectionMembership.CollectionID As 'CollectionID'," + `
             " v_Collection.Name As 'CollectionName'" + `
             " FROM v_FullCollectionMembership " + `
             " JOIN v_RA_System_ResourceNames on v_FullCollectionMembership.ResourceID = v_RA_System_ResourceNames.ResourceID" + ` 
             " JOIN v_Collection on v_FullCollectionMembership.CollectionID = v_Collection.CollectionID " + `
             " WHERE v_RA_System_ResourceNames.Resource_Names0 like '$($NodeName)'"
    
    $nodeEnv = ''
    $nodeProfiles = @{}
    $nodeRoles = @{}
    $nodeClasses = @{}

    $dbResult = Get-MSSQLQuery -ConnectionObject $sqlConn -Query $query

    $dbResult.Rows | % {
      $collID = $_.CollectionID.ToString()
      $collName = $_.CollectionName.ToString()
      
      # Environment type collection
      if ($collName.StartsWith($EnvironmentCollectionPrefix)) {
        Write-Verbose "Found Environment collection $collName"
        $nodeEnv = $collName.SubString($EnvironmentCollectionPrefix.Length)
      }
      # Role type collection
      if ($collName.StartsWith($RoleCollectionPrefix)) {
        Write-Verbose "Found Role collection $collName"
        $nodeRoles.Add($collID,$collName)
      }
      # Profile type collection
      if ($collName.StartsWith($ProfileCollectionPrefix)) {
        Write-Verbose "Found Profile collection $collName"
        $nodeProfiles.Add($collID,$collName)
      }
      # Module type collection
      if ($collName.StartsWith($ClassCollectionPrefix)) {
        Write-Verbose "Found Class collection $collName"
        $nodeClasses.Add($collID,$collName)
      }
    }
    
    if ($nodeEnv -eq '') {
      Write-Verbose "Unable to find any environments"
      return ""
    }
    
    If ($nodeRoles.Count -gt 1) {
      Write-Verbose "Node is a member of more than one role"
      return ""
    }
    
    # Get the Classes List
    $ClassNames = $nodeClasses.GetEnumerator() | % {
      Write-Output $_.Value.Substring($ClassCollectionPrefix.Length)
    } | Select-Object -Unique
     
    # Generate Response
    $response = "---`nclasses:`n"
    $ClassNames | % {
      $response += "    $($_):`n"
    }
    $response += "environment: $nodeEnv`n"
  
    Write-Output $response  
  }
  catch [System.Exception] {
    Write-Verbose "ERROR: $($_)"
    return ""
  }
}

If (-not (Confirm-DBConnectivity)) {
  throw "Error while connecting to the Database"
}

$url = $HTTPEndPoint
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()

Write-Verbose "Listening at $url..."

while ($listener.IsListening)
{
  $context = $listener.GetContext()
  $requestUrl = $context.Request.Url
  $response = $context.Response

  try {    
    $localPath = $requestUrl.LocalPath
    if ($localPath -eq '/kill') { $listener.Close(); break; }

    # Example Node request URI for (hostname.domain.com);
    #   http://10.1.1.1/hostname.domain.com    
    if ($localPath.LastIndexOf('/') -eq 0) {
      $computerName = $localPath.SubString(1).Trim()
      if ($computerName -match $HostnameRegex) {
        Write-Verbose "Request: NodeName = $computerName"
        $content = (Get-NodeResponse -NodeName $computerName)
        Write-Verbose "Response: $content"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)        
      } else {
        $response.StatusCode = 400
      }
    } else {
      $response.StatusCode = 404
    }
  } catch {
    $response.StatusCode = 500
  }
  
  $response.Close()

  # DEBUG
  # $listener.Close(); break;
}