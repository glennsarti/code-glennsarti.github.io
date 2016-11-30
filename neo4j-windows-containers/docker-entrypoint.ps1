[CmdletBinding()]
Param
(
[parameter(Mandatory=$false,ValueFromRemainingArguments=$true)]
  [String[]]$Command = @('neo4j')
) 
$ErrorActionPreference = 'Stop'

# Example docker entrypoint from Neo4j
# https://github.com/neo4j/docker-neo4j-publish/blob/56ac90c26a96f570ba8090c37b8dfcd613fd537f/3.0.7/enterprise/docker-entrypoint.sh

Function Get-FromEnv($Name, $Default) {
  $envValue = Get-ChildItem -Path Env: |
    Where-Object { $_.Name.ToUpper() -eq "NEO4J_$Name".ToUpper() } |
    Select-Object -First 1 |
    ForEach-Object { $_.Value } 
  if ($envValue -eq $null) {
    Write-Output $Default
  } else {
    Write-Host "Detected environment variable NEO4J_$Name"
    Write-Output $envValue
  }
}

$localIP = '127.0.0.1'
try {
  $localIP = (Get-NetIPAddress | ? { ($_.AddressFamily -eq 'IPv4') -and ($_.IPAddress -ne '127.0.0.1') } | Select -First 1).IPAddress
  Write-Host "Container IP Address is $localIP"
} catch {
  Write-Host "Error determining container IP.  Defaulting to 127.0.0.1"
}

$NEO4J_dbms_txLog_rotation_retentionPolicy = '100M size'
$NEO4J_dbms_memory_pagecache_size = '512M'
$NEO4J_dbms_unmanagedExtensionClasses = ''
$NEO4J_dbms_allowFormatMigration = 'false'

$NEO4J_dbms_mode = Get-FromEnv 'dbms_mode' 'SINGLE'
$NEO4J_ha_serverId = Get-FromEnv 'ha_serverId' '1'
$NEO4J_ha_host_data = Get-FromEnv 'ha_host_data' "$($localIP):6001"
$NEO4J_ha_host_coordination = Get-FromEnv 'ha_host_coordination' "$($localIP):5001"
$NEO4J_ha_initialHosts = Get-FromEnv 'ha_initialHosts' $NEO4J_ha_host_coordination

# TODO Midufy neo4j-wrapper.conf - Not sure if this is applicable in Windows
#setting "wrapper.java.additional=-Dneo4j.ext.udc.source" "${NEO4J_UDC_SOURCE:-docker}" neo4j-wrapper.conf
#setting "dbms.memory.heap.initial_size" "${NEO4J_dbms_memory_heap_maxSize:-512}" neo4j-wrapper.conf
#setting "dbms.memory.heap.max_size" "${NEO4J_dbms_memory_heap_maxSize:-512}" neo4j-wrapper.conf

if ($Command -eq 'neo4j') {
  # Implement a start delay
  $startDelay = 0
  try {
    $startDelay = [Int](Get-FromEnv 'startup_delay' '0')
  } catch {
    $startDelay = 0
  }
  While ($startDelay -gt 0) {
    Write-Host "Delaying start: $($startDelay)"
    Start-Sleep -Seconds 1
    $startDelay--
  }

  $ENV:JAVA_HOME = 'C:\neo4j\java'
  $ENV:NEO4J_HOME= 'C:\neo4j'

  Push-Location C:\Neo4j

  $neo4jConf = @"
#*****************************************************************
# Neo4j configuration
#*****************************************************************

# The name of the database to mount
#dbms.active_database=graph.db

# Paths of directories in the installation.
#dbms.directories.data=data
#dbms.directories.plugins=plugins
#dbms.directories.certificates=certificates
#dbms.directories.logs=logs

# This setting constrains all `LOAD CSV` import files to be under the `import` directory. Remove or uncomment it to
# allow files to be loaded from anywhere in filesystem; this introduces possible security problems. See the `LOAD CSV`
# section of the manual for details.
dbms.directories.import=import

# Whether requests to Neo4j are authenticated.
# To disable authentication, uncomment this line
#dbms.security.auth_enabled=false

# Enable this to be able to upgrade a store from an older version.
dbms.allow_format_migration=$NEO4J_dbms_allowFormatMigration

# The amount of memory to use for mapping the store files, in bytes (or
# kilobytes with the 'k' suffix, megabytes with 'm' and gigabytes with 'g').
# If Neo4j is running on a dedicated server, then it is generally recommended
# to leave about 2-4 gigabytes for the operating system, give the JVM enough
# heap to hold all your transaction state and query context, and then leave the
# rest for the page cache.
# The default page cache memory assumes the machine is dedicated to running
# Neo4j, and is heuristically set to 50% of RAM minus the max Java heap size.
dbms.tx_log.rotation.retention_policy=$NEO4J_dbms_memory_pagecache_size

# Enable online backups to be taken from this database.
#dbms.backup.enabled=true

# To allow remote backups, uncomment this line:
#dbms.backup.address=0.0.0.0:6362

#*****************************************************************
# Network connector configuration
#*****************************************************************

# Bolt connector
dbms.connector.bolt.type=BOLT
dbms.connector.bolt.enabled=true
dbms.connector.bolt.tls_level=OPTIONAL
# To have Bolt accept non-local connections, uncomment this line
dbms.connector.bolt.address=0.0.0.0:7687

# HTTP Connector
dbms.connector.http.type=HTTP
dbms.connector.http.enabled=true
# To accept non-local HTTP connections, uncomment this line
dbms.connector.http.address=0.0.0.0:7474

# HTTPS Connector
dbms.connector.https.type=HTTP
dbms.connector.https.enabled=true
dbms.connector.https.encryption=TLS
# To accept non-local HTTPS connection, change 'localhost' to '0.0.0.0'
dbms.connector.https.address=0.0.0.0:7473

# Number of Neo4j worker threads.
#dbms.threads.worker_count=

#*****************************************************************
# Logging configuration
#*****************************************************************

# Debug logging
dbms.logs.debug.level=DEBUG

# To enable HTTP logging, uncomment this line
#dbms.logs.http.enabled=true

# Number of HTTP logs to keep.
#dbms.logs.http.rotation.keep_number=5

# Size of each HTTP log that is kept.
#dbms.logs.http.rotation.size=20m

# To enable GC Logging, uncomment this line
#dbms.logs.gc.enabled=true

# GC Logging Options
# see http://docs.oracle.com/cd/E19957-01/819-0084-10/pt_tuningjava.html#wp57013 for more information.
#dbms.logs.gc.options=-XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime -XX:+PrintPromotionFailure -XX:+PrintTenuringDistribution

# Number of GC logs to keep.
#dbms.logs.gc.rotation.keep_number=5

# Size of each GC log that is kept.
#dbms.logs.gc.rotation.size=20m

# Size threshold for rotation of the debug log. If set to zero then no rotation will occur. Accepts a binary suffix "k",
# "m" or "g".
#dbms.logs.debug.rotation.size=20m

# Maximum number of history files for the internal log.
#dbms.logs.debug.rotation.keep_number=7

# Log executed queries that takes longer than the configured threshold. Enable by uncommenting this line.
#dbms.logs.query.enabled=true

# If the execution of query takes more time than this threshold, the query is logged. If set to zero then all queries
# are logged.
#dbms.logs.query.threshold=0

# The file size in bytes at which the query log will auto-rotate. If set to zero then no rotation will occur. Accepts a
# binary suffix "k", "m" or "g".
#dbms.logs.query.rotation.size=20m

# Maximum number of history files for the query log.
#dbms.logs.query.rotation.keep_number=7

#*****************************************************************
# HA configuration
#*****************************************************************

# Uncomment and specify these lines for running Neo4j in High Availability mode.
# See the High availability setup tutorial for more details on these settings
# http://neo4j.com/docs/operations-manual/current/#tutorials

# Database mode
# Allowed values:
# HA - High Availability
# SINGLE - Single mode, default.
# To run in High Availability mode uncomment this line:
dbms.mode=$NEO4J_dbms_mode

# ha.server_id is the number of each instance in the HA cluster. It should be
# an integer (e.g. 1), and should be unique for each cluster instance.
ha.server_id=$NEO4J_ha_serverId

# ha.initial_hosts is a comma-separated list (without spaces) of the host:port
# where the ha.host.coordination of all instances will be listening. Typically
# this will be the same for all cluster instances.
ha.initial_hosts=$NEO4J_ha_initialHosts

# IP and port for this instance to listen on, for communicating cluster status
# information iwth other instances (also see ha.initial_hosts). The IP
# must be the configured IP address for one of the local interfaces.
ha.host.coordination=$NEO4J_ha_host_coordination

# IP and port for this instance to listen on, for communicating transaction
# data with other instances (also see ha.initial_hosts). The IP
# must be the configured IP address for one of the local interfaces.
ha.host.data=$NEO4J_ha_host_data

# The interval at which slaves will pull updates from the master. Comment out
# the option to disable periodic pulling of updates. Unit is seconds.
ha.pull_interval=10

# Amount of slaves the master will try to push a transaction to upon commit
# (default is 1). The master will optimistically continue and not fail the
# transaction even if it fails to reach the push factor. Setting this to 0 will
# increase write performance when writing through master but could potentially
# lead to branched data (or loss of transaction) if the master goes down.
#ha.tx_push_factor=1

# Strategy the master will use when pushing data to slaves (if the push factor
# is greater than 0). There are three options available "fixed_ascending" (default),
# "fixed_descending" or "round_robin". Fixed strategies will start by pushing to
# slaves ordered by server id (accordingly with qualifier) and are useful when
# planning for a stable fail-over based on ids.
#ha.tx_push_strategy=fixed_ascending

# Policy for how to handle branched data.
#ha.branched_data_policy=keep_all

# How often heartbeat messages should be sent. Defaults to ha.default_timeout.
#ha.heartbeat_interval=5s

# Timeout for heartbeats between cluster members. Should be at least twice that of ha.heartbeat_interval.
#ha.heartbeat_timeout=11s

# If you are using a load-balancer that doesn't support HTTP Auth, you may need to turn off authentication for the
# HA HTTP status endpoint by uncommenting the following line.
#dbms.security.ha_status_auth_enabled=false

# Whether this instance should only participate as slave in cluster. If set to
# true, it will never be elected as master.
#ha.slave_only=false

#*****************************************************************
# Miscellaneous configuration
#*****************************************************************

# Enable this to specify a parser other than the default one.
#cypher.default_language_version=3.0

# Determines if Cypher will allow using file URLs when loading data using
# `LOAD CSV`. Setting this value to `false` will cause Neo4j to fail `LOAD CSV`
# clauses that load data from the file system.
#dbms.security.allow_csv_import_from_file_urls=true

# Retention policy for transaction logs needed to perform recovery and backups.
dbms.tx_log.rotation.retention_policy=$NEO4J_dbms_txLog_rotation_retentionPolicy

# Limit the number of IOs the background checkpoint process will consume per second.
# This setting is advisory, is ignored in Neo4j Community Edition, and is followed to
# best effort in Enterprise Edition.
# An IO is in this case a 8 KiB (mostly sequential) write. Limiting the write IO in
# this way will leave more bandwidth in the IO subsystem to service random-read IOs,
# which is important for the response time of queries when the database cannot fit
# entirely in memory. The only drawback of this setting is that longer checkpoint times
# may lead to slightly longer recovery times in case of a database or system crash.
# A lower number means lower IO pressure, and consequently longer checkpoint times.
# The configuration can also be commented out to remove the limitation entirely, and
# let the checkpointer flush data as fast as the hardware will go.
# Set this to -1 to disable the IOPS limit.
# dbms.checkpoint.iops.limit=1000

# Enable a remote shell server which Neo4j Shell clients can log in to.
#dbms.shell.enabled=true
# The network interface IP the shell will listen on (use 0.0.0.0 for all interfaces).
#dbms.shell.host=127.0.0.1
# The port the shell will listen on, default is 1337.
#dbms.shell.port=1337

# Only allow read operations from this Neo4j instance. This mode still requires
# write access to the directory for lock purposes.
#dbms.read_only=false

# Comma separated list of JAX-RS packages containing JAX-RS resources, one
# package name for each mountpoint. The listed package names will be loaded
# under the mountpoints specified. Uncomment this line to mount the
# org.neo4j.examples.server.unmanaged.HelloWorldResource.java from
# neo4j-server-examples under /examples/unmanaged, resulting in a final URL of
# http://localhost:7474/examples/unmanaged/helloworld/{nodeId}
dbms.unmanaged_extension_classes=$NEO4J_dbms_unmanagedExtensionClasses

# Specified comma separated list of id types (like node or relationship) that should be reused.
# When some type is specified database will try to reuse corresponding ids as soon as it will be safe to do so.
# Currently only 'node' and 'relationship' types are supported.
# This settings is ignored in Neo4j Community Edition.
#dbms.ids.reuse.types.override=node,relationship
"@

  $neo4jConf | Set-Content -Path 'C:\neo4j\conf\neo4j.conf' -Encoding UTF8

  Import-Module .\bin\Neo4j-Management.psd1

  # Run Neo4j in Console mode
  Invoke-Neo4j console -Verbose
} elseif ($Command -eq 'dump-config') {
  Write-Host "-- Begin neo4j.conf"
  Get-Content 'C:\neo4j\conf\neo4j.conf' -ErrorAction Continue
  Write-Host "-- End neo4j.conf"

  Write-Host "-- Begin neo4j-wrapper.conf"
  Get-Content 'C:\neo4j\conf\neo4j-wrapper.conf' -ErrorAction Continue
  Write-Host "-- End neo4j-wrapper.conf"
} else {
  & $Command
}
