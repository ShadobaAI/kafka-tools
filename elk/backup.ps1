# Back up a volume
docker run --rm -v elk_elastic_data:/data -v C:/docker-backups/elk:/backup ubuntu bash -c "tar cvf /backup/elastic_data.tar /data"
