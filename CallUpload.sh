#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
echo "${1}" > /tmp/filename

DB_IP="TO BE CHANGED"

MYSQL="/usr/bin/mysql --skip-column-names -utranscode -ptranscode -h ${DB_IP} transcoding -e"

NUMBER_NODE=$(ls /srv/workers/ | wc -l)
FILE=${1}
FILENAME=$(basename ${FILE})
FILEPATH=${FILE%/*}
CONTPROVIDER=$(echo "${FILE}"| cut -d"/" -f4);

#Sync Source file to all live nodes/workers
for i in $(ls /srv/workers/); do
	rsync --timeout=30  -f"+ */" -f"- *" -rRvz "${FILEPATH}" ${i}:/
	rsync --rsh="ssh -c arcfour256,arcfour128,blowfish-cbc,aes128-ctr,aes192-ctr,aes256-ctr" -Rv ${FILE} ${i}:/ ;
done

# Determine the duration (length) of the video
HHMMSS=$(/usr/local/bin/ffprobe "${FILE}" 2>&1 | /bin/grep Duration: | /bin/sed -e "s/^.*Duration: //" -e "s/\..*$//")

# Convert that HH:MM:SS.xxx to seconds
SECONDS=$(/bin/date -u -d "1970-01-01 ${HHMMSS}" +"%s")

# Round up, to take care of the .xxx microseconds
DURATION=$((SECONDS+1))

# Insert into jobs table
$MYSQL "INSERT INTO transcoding.jobs (name, path, duration, no_nodes, cp) VALUES ('${FILENAME}', '${FILEPATH}/', '${DURATION}', '${NUMBER_NODE}', '${CONTPROVIDER}');"
