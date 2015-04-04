#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
echo "${1}" > /tmp/filename

MASTER_NODE="192.168.92.73"
WORKERS="blade01.vodserver.com blade02.vodserver.com blade03.vodserver.com blade04.vodserver.com blade05.vodserver.com"

MYSQL="/usr/bin/mysql --skip-column-names -utranscode -ptranscode -h ${MASTER_NODE} transcoding -e"

NUMBER_NODE=$(ls /srv/workers/ | wc -l)
FILE=${1}
FILENAME=$(basename ${FILE})
FILEPATH=${FILE%/*}
CONTPROVIDER=$(echo "${FILE}"| cut -d"/" -f4);

#Sync Source file to all nodes/workers
for i in ${WORKERS}; do
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
