[CmdletBinding()]
Param
(
[parameter(Mandatory=$false)]
  [Switch]$Force
) 

$PrivateJavaVersion = "8.0.92.14"

function Invoke-InstallPrivateJRE($Destination) {
  # Adpated from the server-jre8 chocolatey package
  # https://github.com/rgra/choco-packages/tree/master/server-jre8

  Write-Host "Downloading Server JRE $privateJavaVersion to $Destination"

  #8.0.xx to jdk1.8.0_xx
  $versionArray = $privateJavaVersion.Split(".")
  $majorVersion = $versionArray[0]
  $minorVersion = $versionArray[1]
  $updateVersion = $versionArray[2]
  $buildNumber = $versionArray[3]
  $folderVersion = "jdk1.$majorVersion.$($minorVersion)_$updateVersion"

  $fileNameBase = "server-jre-$($majorVersion)u$($updateVersion)-windows-x64"
  $fileName = "$fileNameBase.tar.gz"

  $url = "http://download.oracle.com/otn-pub/java/jdk/$($majorVersion)u$($updateVersion)-b$buildNumber/$fileName"

  # Download location info
  $tarGzFile = "$Destination"

  $webClient = New-Object System.Net.WebClient
  $result = $webClient.headers.Add('Cookie','gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie')
  Write-Host "Downloading $url ..."
  $result = $webClient.DownloadFile($url, $tarGzFile)
}

$tempDir = "$($PSScriptRoot)\temp"
If (-not (Test-Path -Path $tempDir)) { New-Item -Path $tempDir -ItemType 'Directory' | Out-Null } 

# Grab Neo4j Enterprise ZIP
$neo4jEnt = "$($tempDir)\neo4j.zip"
if (-not (Test-Path -Path $neo4jEnt)) {
  Write-Host "Downloading Neo4j Enterprise..."
  Invoke-WebRequest -Uri 'http://neo4j.com/artifact.php?name=neo4j-enterprise-3.0.6-windows.zip' -OutFile $neo4jEnt
}

# Extract Neo4j Enterprise ZIP
$neo4jEntSourceDir = "$($tempDir)\neo4j"
if (-not (Test-Path -Path $neo4jEntSourceDir)) {
  $tempExtractDir = "$($tempDir)\neo4jtemp"
  if (Test-Path -Path $tempExtractDir) { Remove-Item -Path $tempExtractDir -Recurse -Confirm:$false -Force | Out-Null }
  & 7z x "`"-o$tempExtractDir`"" $neo4jEnt
  Move-Item -Path (Get-ChildItem -Path $tempExtractDir | Select -First 1).Fullname -Destination $neo4jEntSourceDir -Force -Confirm:$false | Out-Null 
  # Cleanup
  if (Test-Path -Path $tempExtractDir) { Remove-Item -Path $tempExtractDir -Recurse -Confirm:$false -Force | Out-Null }
}

# Grab Java Server JRE tar.gz
$serverJRE = "$($tempDir)\jre.tar.gz"
if (-not (Test-Path -Path $serverJRE)) {
  Invoke-InstallPrivateJRE -Destination $serverJRE
}

# Extract JRE
$jreSourceDir = "$($tempDir)\jre"
if (-not (Test-Path -Path $jreSourceDir)) {
  $tarFile = "$($tempDir)\jre.tar"
  $untar = "$($tempDir)\jretemp"
  & 7z e "`"-o$tempDir`"" $serverJRE
  & 7z x "`"-o$untar`"" $tarFile

  Move-Item -Path (Get-ChildItem -Path $untar | Select -First 1).Fullname -Destination $jreSourceDir -Force -Confirm:$false | Out-Null 
  # Cleanup
  if (Test-Path -Path $tarFile) { Remove-Item -Path $tarFile -Confirm:$false -Force | Out-Null }
  if (Test-Path -Path $untar) { Remove-Item -Path $untar -Recurse -Confirm:$false -Force | Out-Null }
}

# Generate Docker Context files
$contextDir = "$($PSScriptRoot)\context"
# If -Force is set, remove current content directory
if ($Force) {
  If (Test-Path -Path $contextDir) { Remove-Item -path $contextDir -Recurse -Force -Confirm:$false | Out-Null }
  New-Item -Path $contextDir -ItemType Directory | Out-Null
}

# Copy the Neo4j and Java files
if (-not (Test-Path -Path "$($contextDir)\neo4j")) {
  # Copy Neo4j
  & robocopy /s /e /w:1 /r:1 /copy:dat "`"$($neo4jEntSourceDir)`"" "`"$($contextDir)\neo4j`""
  # Copy JRE
  & robocopy /s /e /w:1 /r:1 /copy:dat "`"$($jreSourceDir)`"" "`"$($contextDir)\neo4j\java`""

  # Copy extra source files
  Copy-Item -Path "$($PSScriptRoot)\docker-entrypoint.ps1" -Destination "$($contextDir)\neo4j" -Force -Confirm:$false

  # Copy DockerFile
  Copy-Item -Path "$($PSScriptRoot)\DockerFile" -Destination "$($contextDir)\DockerFile" -Force -Confirm:$false
}
