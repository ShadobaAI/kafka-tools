# Back up a volume
docker run --rm -v elk_elastic_data:/data -v C:/docker-backups/elk:/backup ubuntu bash -c "tar cvf /backup/elastic_data.tar /data"

# Restore volume from a backup
docker run --rm --volumes-from elasticsearch -v C:/docker-backups/elk:/backup ubuntu bash -c "rm -rf /usr/share/elasticsearch/data/* && cd /usr/share/elasticsearch/data && tar xvf /backup/elastic_data.tar --strip 1"