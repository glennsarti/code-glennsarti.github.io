# Import DLLs
Add-Type -Path "$PSScriptRoot\nuget\Neo4j.Driver.1.0.2\lib\dotnet\Neo4j.Driver.dll"
Add-Type -Path "$PSScriptRoot\nuget\rda.SocketsForPCL.1.2.2\lib\net45\Sockets.Plugin.Abstractions.dll"
Add-Type -Path "$PSScriptRoot\nuget\rda.SocketsForPCL.1.2.2\lib\net45\Sockets.Plugin.dll"

Function Invoke-Cypher($title, $query = $null) {
  if ($query -eq $null) {
    $query = $title
    Write-Host "-----------------" -ForegroundColor Green
    Write-Host $query -ForegroundColor Yellow
  } else {
    Write-Host ''
    Write-Host $title -ForegroundColor Green
    Write-Host "-----------------" -ForegroundColor Green
    Write-Host $query -ForegroundColor Yellow
  }

  $result = $session.Run($query)

  $result | ForEach-Object -Process {
    $record = $_
    
    $props = @{}
    $record.keys | ForEach-Object -Process {
      $key = $_
      $value = $record[$key]
      
      switch ($value.GetType().ToString()) {
        "Neo4j.Driver.Internal.Node" {
          $props.Add($key,($record[$key] | ConvertTo-JSON -Depth 3))
          break
        }
        default {
          $props.Add($key,$record[$key])
        }
      }
    }

    Write-Output (New-Object -TypeName PSObject -Property $props)
  }
}

$authToken = [Neo4j.Driver.V1.AuthTokens]::Basic('neo4j','Password1')

$dbDriver = [Neo4j.Driver.V1.GraphDatabase]::Driver("bolt://localhost:7687",$authToken)
$session = $dbDriver.Session()


Invoke-Cypher 'List the entities' @"
MATCH (m:Module)
WITH COUNT(m) AS ModuleCount
MATCH (c:Command)
WITH ModuleCount,COUNT(c) AS CommandCount
RETURN ModuleCount,CommandCount, SIZE(()-[:RELATED_LINK]->()) AS LinkCount
"@ | Format-Table

Read-Host -Prompt "Hit enter"
Clear-Host

Invoke-Cypher 'List all modules' @"
MATCH (m:Module)-[:HAS_COMMAND]->(com:Command)
RETURN m.name AS ModuleName, Count(com) AS Commands
ORDER BY Count(com) DESC
LIMIT 10
"@ | Format-Table

Read-Host -Prompt "Hit enter"
Clear-Host

Invoke-Cypher 'Commands that link themselves' @"
MATCH (this:Command)-[:RELATED_LINK]->(that:Command)
WHERE this = that
RETURN this.name
LIMIT 10
"@ | Format-Table

Read-Host -Prompt "Hit enter"
Clear-Host

Invoke-Cypher 'Commands that have no links at all (Hermits)' @"
MATCH (this:Command)
WHERE NOT ( (this)-[:RELATED_LINK]-(:Command) )
RETURN this.name
LIMIT 10
"@ | Format-Table

Read-Host -Prompt "Hit enter"
Clear-Host

Invoke-Cypher 'Popular Commands.  More inbound links than outbound' @"
MATCH (this:Command)
WHERE SIZE( (this)<-[:RELATED_LINK]-(:Command) ) >
      SIZE( (this)-[:RELATED_LINK]->(:Command) )
RETURN
  this.name,
  SIZE( (this)<-[:RELATED_LINK]-(:Command) ) AS InboundLinks,
  SIZE( (this)-[:RELATED_LINK]->(:Command) ) AS OutboundLinks,
  (SIZE( (this)<-[:RELATED_LINK]-(:Command) ) - SIZE( (this)-[:RELATED_LINK]->(:Command) )) AS LinksDiff
ORDER BY LinksDiff DESC
LIMIT 10 
"@ | Format-Table

Read-Host -Prompt "Hit enter"
Clear-Host

# Invoke-Cypher 'Top 10 most related Commands' @"
# MATCH (this:Command)-[r:RELATED_LINK]->(that:Command)
# WHERE (this <> that)
# RETURN this.name, COUNT(r) As NumLinks
# ORDER BY COUNT(r) DESC
# LIMIT 10
# "@ | Format-Table

# Read-Host -Prompt "Hit enter"

# Invoke-Cypher 'Modules with Commands with no Online Reference' @"
# MATCH (m:Module)-[:HAS_COMMAND]->(c:Command)
# WHERE NOT EXIST(c.uri)
# RETURN m.name AS ModuleName, COUNT(c) AS CommandCount
# "@ | Format-Table

# Read-Host -Prompt "Hit enter"

Invoke-Cypher 'Links across Modules' @"
MATCH (thismodule:Module)-[:HAS_COMMAND]->(this:Command)-[r:RELATED_LINK]->(that:Command)<-[:HAS_COMMAND]-(thatmodule:Module)
WHERE (this <> that) AND (thismodule <> thatmodule)
RETURN
  ("(" + thismodule.name + ") " + this.name) AS From,
  ("(" + thatmodule.name + ") " + that.name) AS To
LIMIT 10
"@ | Format-Table -Property From,To

Read-Host -Prompt "Hit enter"
Clear-Host

Invoke-Cypher @"
MATCH (that:Command {name: 'New-JobTrigger'})
MERGE (mod:Module { name: 'Glenn'})-[:HAS_COMMAND]->(glenn:Command {name: 'Invoke-Glenn'})
MERGE (glenn)-[:RELATED_LINK]->(that)
"@

$commandName = 'Invoke-Glenn'
Invoke-Cypher 'Recommendation Engine (New-JobTrigger)' @"
MATCH
  (this:Command)-[:RELATED_LINK*2..4]->(recommend:Command)
WHERE
  (this.name = '$commandName')
  AND (this <> recommend)
  AND NOT ( (this)-[:RELATED_LINK]->(recommend) )
WITH
  recommend, COUNT(recommend) AS Popularity
RETURN
  recommend.name AS CommandName,Popularity
ORDER BY Popularity DESC
LIMIT 5
"@ | Format-Table
