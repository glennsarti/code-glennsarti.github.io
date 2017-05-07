$ErrorActionPreference = 'Stop'

# Update all of the help files
Update-Help -Confirm:$false

# Import the modules into the session
Get-Module -List | Select-Object -Unique |% { 
  Write-Host "Importing $($_.Name)"
  $_ | Import-Module -ErrorAction Continue
}

# Import DLLs
Add-Type -Path "$PSScriptRoot\nuget\Neo4j.Driver.1.0.2\lib\dotnet\Neo4j.Driver.dll"
Add-Type -Path "$PSScriptRoot\nuget\rda.SocketsForPCL.1.2.2\lib\net45\Sockets.Plugin.Abstractions.dll"
Add-Type -Path "$PSScriptRoot\nuget\rda.SocketsForPCL.1.2.2\lib\net45\Sockets.Plugin.dll"

Function Invoke-Cypher($query) {
  $session.Run($query)
}

$authToken = [Neo4j.Driver.V1.AuthTokens]::Basic('neo4j','Password1')

$dbDriver = [Neo4j.Driver.V1.GraphDatabase]::Driver("bolt://localhost:7687",$authToken)
$session = $dbDriver.Session()

$moduleFilter = '.+'
$commandFilter = '.+'
try {
  # Kill everything ...
  $result = Invoke-Cypher("MATCH ()-[r]-() DELETE r")
  $result = Invoke-Cypher("MATCH (n) DELETE n")

  # Create all the cmdlets and modules
  Get-Module | ? { $_.Name -match $moduleFilter } | ForEach-Object -Process {
    $ModuleName = $_.name
    Write-Progress -Activity "Parsing $ModuleName" -Status "Importing Commands"
    Invoke-Cypher("CREATE (:Module { name:'$ModuleName'})")

    Get-Command -Module $_ | ? { $_.Name -match $commandFilter } | ForEach-Object -Process {
      $CommandName = $_.Name
      $query = "MATCH (m:Module { name:'$ModuleName'})`n" + `
               "CREATE (com:Command { name:'$CommandName'})`n" + `
               "  SET com.commandtype = '$($_.CommandType)'`n" + `
               "WITH m,com`n" + `
               "CREATE (m)-[:HAS_COMMAND]->(com)"
      Invoke-Cypher($query)
    }
  }

  # Create all the cmdlets and modules
  Get-Module | ? { $_.Name -match $moduleFilter } | ForEach-Object -Process {
    $ModuleName = $_.name
    Write-Progress -Activity "Parsing $ModuleName"
    Get-Command -Module $_ | ? { $_.Name -match $commandFilter } | ForEach-Object -Process {
      $ThisCommandName = $_.Name

      Write-Progress -Activity "Parsing $ModuleName" -Status "Creating links for $ThisCommandName"
      $thisURI = $null
      (Get-Help $_).relatedLinks.navigationLink | ForEach-Object -Process {
        $HelpLink = $_

        # Ignore anything that is a real URI
        if ($HelpLink.uri -eq '') {
          $ThatCommandName = $HelpLink.linkText

          $query = "MATCH (this:Command { name:'$ThisCommandName'})`n" + `
                   "MATCH (that:Command { name:'$ThatCommandName'})`n" + `
                   "CREATE (this)-[:RELATED_LINK]->(that)"
          Invoke-Cypher($query)
        } else {
          $thisURI = $HelpLink.uri
        }
      }

      if ($thisURI -ne $null) {
        $query = "MATCH (this:Command { name:'$ThisCommandName'})`n" + `
                 "SET this.uri = '$thisURI'`n"
        Invoke-Cypher($query)
      }
    }
  }
} finally {
  $session = $null
  $dbDriver = $null
}
