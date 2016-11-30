FROM microsoft/nanoserver

MAINTAINER glennsarti

LABEL Description="Neo4j Enterprise" Vendor="Neo Technologies" Version="3.0.6"

ENTRYPOINT ["powershell.exe","C:/neo4j/docker-entrypoint.ps1"]
CMD ["neo4j"]

COPY neo4j C:/neo4j

# Note - As we're using a transparent network, exposing ports isn't really required.  They are here
# for when we will use a different network driver.

# 7474 = HTTP Neo4j Connector
# 7473 = HTTPS Neo4j Connector
# 7687 = Bolt Connector
# 1337 = Neo4j Shell Port

EXPOSE 7474 7473 7687 1337
