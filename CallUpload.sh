#!/bin/bash -x

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
echo "${1}" > /tmp/filename
MYSQL="/usr/bin/mysql --skip-column-names -utranscode -ptranscode -h 172.18.10.111 transcoding -e"

FILE="${1}"
FILENAME=$(basename "${FILE}")
FILEPATH=${FILE%/*}
PRODUCT=$(echo "${FILE}"| cut -d"/" -f4);

for i in $(ls /srv/workers/ | grep -v $(hostname)); do
	rsync --timeout=30  -f"+ */" -f"- *" -rRvz "${FILEPATH}" ${i}:/
	rsync --rsh="ssh -c arcfour256,arcfour128,blowfish-cbc,aes128-ctr,aes192-ctr,aes256-ctr" -Rv "${FILE}" ${i}:/ ;
done

# The length of each segment is the total length, divided by the total number of worker nodes
TOTALNODES=$(ls /srv/workers/ | wc -l)
#TOTALNODES=4

# Determine the duration (length) of the video
#echo ORIGINIAL VIDEO LENGTH IS: $TIME
#HHMMSS=$(ffprobe "${FILE}" 2>&1 | /bin/grep Duration: | /bin/sed -e "s/^.*Duration: //" -e "s/\..*$//")
TIME=$(mplayer -identify -frames 0 -vo null -nosound "${FILE}" 2>&1 | awk -F= '/LENGTH/{print $2}')

## First MS
MS=$(echo $TIME |cut -d'.' -f2)
SECONDS=$(echo $TIME |cut -d'.' -f1)

if [ ${MS} -gt 0 ]; then
	MS1=$(echo "0.${MS} * 1000000" | bc)
fi

## Main Seconds
SEC1=$(echo "scale = 3; ${SECONDS} / ${TOTALNODES}" | bc)

SEC1MS=$(echo ${SEC1} |cut -d'.' -f2)
SEC1SECONDS=$(echo ${SEC1} |cut -d'.' -f1)

if [ ${SEC1MS} -gt 0 ]; then
	SEC1MS1=$(echo "0.${SEC1MS} * 1000000" | bc |cut -d'.' -f1)
fi

MSPERNODE=$(echo "${MS1} / ${TOTALNODES}" | bc | cut -d'.' -f1)

if [ ! -z ${MSPERNODE} ] && [ ! -z ${SEC1MS1} ]; then
	FINALMICRO=$(echo "${MSPERNODE} + ${SEC1MS1}" | bc)
else
	[ ! -z ${MSPERNODE} ] &&  FINALMICRO=$(echo ${MSPERNODE}|cut -d'.' -f1)
	[ ! -z ${SEC1MS1} ] &&  FINALMICRO=$(echo ${SEC1MS1}|cut -d'.' -f1)
fi

NODELENGTH="${SEC1SECONDS}.${FINALMICRO}"
#echo TOTAL VIDEO LENGTH IS: $(echo "${LENGTH} * 4" |bc)

LENGTH="$(date -d@${SEC1SECONDS} -u +%H:%M:%S).${FINALMICRO}"

# Convert that HH:MM:SS.xxx to seconds
#SECOND=$(/bin/date -u -d "1970-01-01 ${HHMMSS}" +"%s")

# Calculate each node's start time
if [ ${SEC1SECONDS} -gt 0 ]; then
	JOBID=$($MYSQL "INSERT INTO transcoding.jobs (filename, filepath, duration, nodecount, product) VALUES ('${FILENAME}', '${FILEPATH}/', '${DURATION}', '${TOTALNODES}', '${PRODUCT}');SELECT LAST_INSERT_ID();")
	TOTALNODES=$((TOTALNODES-1))
	for i in $(seq 0 $TOTALNODES); do
		#STIME=$(echo "${NODELENGTH} * ${i}" | bc)
		STARTTIME="$(date -d@$(echo "${NODELENGTH} * ${i}" | bc |cut -d'.' -f1) -u +%H:%M:%S).$(echo "${NODELENGTH} * ${i}" | bc |cut -d'.' -f2)"
		# Insert into jobs table
		$MYSQL "INSERT INTO transcoding.queue (jobid, starttime, length) VALUES ('${JOBID}', '${STARTTIME}', '${LENGTH}');"
	done
fi
echo "${1}" >> /tmp/abrt_filename