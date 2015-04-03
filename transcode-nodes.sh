#!/bin/bash

set -e
#set -x

# Exit Traps
function finish {
	rm -f "/srv/workers/$(hostname)"
	rm -fv /tmp/nodes
	echo "Error: Nodes Service Down" >> /var/log/nodes.log
}
trap finish EXIT

CPUNO=$(/usr/bin/nproc)
FORMAT="mp4"
BITRATE="128 256 512 712" # Used in Rsync command, if changed change in rsync also
MASTER_NODE="192.168.92.73"
MYSQL="mysql --skip-column-names -utranscode -ptranscode -h ${MASTER_NODE} transcoding -e"
IPADDR=$(ifconfig eth0 | grep -v 'inet6'| grep 'addr:'| sed "s/Bcast.*//g"| cut -d ":" -f2|sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')

while true; do
	mkdir -p /srv/workers
	date > /srv/workers/$(hostname)
	CURRENT_NODE=$(ls /srv/workers/ | grep -B99999 $(hostname) | wc -l)
	CURRENT_NODE=$((CURRENT_NODE-1))
	
	if [ ! -s /tmp/master ]; then
		# look for work	
		JOB_ID=$(${MYSQL} "SELECT job_id FROM jobs WHERE node_status!=no_nodes AND node_id NOT LIKE '%${CURRENT_NODE}%' AND node_failed IS NULL AND job_failed IS NULL LIMIT 1;")
	
		if [ ! -z ${JOB_ID} ]; then
		
			echo "${JOB_ID}" > /tmp/nodes
			# Update current node number to node_id field
			${MYSQL} "UPDATE jobs SET node_id = concat(ifnull(node_id,''), ',${CURRENT_NODE}') WHERE job_id = ${JOB_ID};"
			
			CURDATE=$(date +%F)
			
			# Get Filename with extension and Filename w/o extension
			FILEPATH=$(${MYSQL} "SELECT path FROM jobs WHERE job_id = ${JOB_ID};")
			FILEWEXT=$(${MYSQL} "SELECT name FROM jobs WHERE job_id = ${JOB_ID};")
			FILEWOEXT=${FILEWEXT%.*}	# filename only w/o extension
			
			# Get Content Provider
			CONTPROVIDER=$(echo "${FILEPATH}"| cut -d"/" -f4)
			
			# Set output directory and create it
			OUTPATH="/video-process/processed/${CONTPROVIDER}/${CURDATE}/${FILEWOEXT}/"
			mkdir -p "${OUTPATH}"
			
			# Check if source file exists
			if [ -f "${FILEPATH}/${FILEWEXT}" ]; then
				# Check if this is first node to pick job for processing, If yes then update start time
				TMP1=$(${MYSQL} "SELECT node_status FROM jobs WHERE job_id = ${JOB_ID};")
				if [ "${TMP1}" = "0" ]; then
					${MYSQL} "UPDATE jobs SET start_time = current_timestamp where job_id = ${JOB_ID};"
				fi
				
				${MYSQL} "UPDATE jobs SET node_status=node_status+1 where job_id = ${JOB_ID};"
				
				# Set source file with full path
				FILENAME="${FILEPATH}/${FILEWEXT}"
				
				# Get file duration in seconds
				DURATION=$(${MYSQL} "SELECT duration FROM jobs WHERE job_id = ${JOB_ID};")
				
				# The length of each segment is the total length, divided by the total number of worker nodes
				TOTAL_NODES=$(${MYSQL} "SELECT no_nodes FROM jobs WHERE job_id = ${JOB_ID};")
				LENGTH=$((DURATION/${TOTAL_NODES}))
				
				MODDURATION=$((${DURATION} % ${TOTAL_NODES}))
				if [ ${MODDURATION} -ne 0 ]; then
					LENGTH=$((1 + ${LENGTH}))
				fi
				
				# Calculate each node's start time
				START_TIME=$((LENGTH*CURRENT_NODE))
				
				# Kill off any previous running jobs
				# killall -9 ffmpeg 2>/dev/null || true
				
				# Write the command to a log file
				echo "ffmpeg -threads ${CPUNO} -ss ${START_TIME} -i ${FILENAME} -t ${LENGTH} -r 29.97 -vcodec libx264 -acodec aac -bsf:v h264_mp4toannexb -f mpegts -strict experimental -y ${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}.ts >> ${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}.log.txt 2>&1" > "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}.log.txt"	
				
				ERROR=0;
				ERRORLOG=;
				
				streams_stream_0_width= ; streams_stream_0_height=
				
				eval $(ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=height,width "${FILENAME}")
				SIZE=${streams_stream_0_width}x${streams_stream_0_height}
				
				REOLVIDEO=$(echo ${SIZE} |sed 's#x#*#g' | bc)
				RESOLUTION=$(echo "scale=1; $streams_stream_0_width/$streams_stream_0_height" | bc)
				
				transcode() {
					# 128 Bitrate
					MULBIT128=$(echo  ${1}|sed 's#x#*#g' |bc)
					if [ ${REOLVIDEO} -gt ${MULBIT128} ]; then
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -s $1 -movflags rtphint -b:v 128k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-128000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-128000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 128 Bitrate Conversion"
						fi
					else
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -movflags rtphint -b:v 128k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-128000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-128000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 128 Bitrate Conversion"
						fi
					fi
					
					# 256 Bitrate
					MULBIT256=$(echo  ${2}|sed 's#x#*#g' |bc)
					if [ ${REOLVIDEO} -gt ${MULBIT256} ]; then
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -s $2 -movflags rtphint -b:v 256k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-256000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-256000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 256 Bitrate Conversion"
						fi
					else
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -movflags rtphint -b:v 256k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-256000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-256000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 256 Bitrate Conversion"
						fi
					fi
					
					# 512 Bitrate
					MULBIT512=$(echo  ${3}|sed 's#x#*#g' |bc)
					if [ ${REOLVIDEO} -gt ${MULBIT512} ]; then
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -s $3 -movflags rtphint -b:v 512k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-512000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-512000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 512 Bitrate Conversion"
						fi
					else
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -movflags rtphint -b:v 512k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-512000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-512000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 512 Bitrate Conversion"
						fi
					fi
					
					# 712 Bitrate
					MULBIT712=$(echo  ${4}|sed 's#x#*#g' |bc)
					if [ ${REOLVIDEO} -gt ${MULBIT712} ]; then
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -s $4 -movflags rtphint -b:v 712k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-712000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-712000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 712 Bitrate Conversion"
						fi
					else
						if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -movflags rtphint -b:v 712k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-712000.ts" >> "${OUTPATH}${FILEWOEXT}.part${CURRENT_NODE}-712000.log.txt" 2>&1; then
							ERROR=1
							ERRORLOG="${ERRORLOG}Failed: 712 Bitrate Conversion"
						fi
					fi
				}
				
				if [ ${RESOLUTION} = '1.3' ]; then 
					transcode 320x240 480x360 640x480 1024x768
				elif [ ${RESOLUTION} = '1.7' ]; then 
					transcode 384x216 512x288 640x360 1024x576
				else 
					transcode 384x216 512x288 640x360 1024x576
				fi

				if [ $ERROR -ne '0' ]; then
					${MYSQL} "UPDATE jobs SET node_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
					echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/nodes.log
					ERRORLOG=
					rm -fv /tmp/nodes
					sleep 5
				else
					rm -fv "${FILENAME}"
					# Update job status, so that the other workers know when its done
					${MYSQL} "UPDATE jobs SET job_status=job_status+1  WHERE job_id = ${JOB_ID};"
					rm -fv /tmp/nodes
					sleep 5
				fi
			else
				${MYSQL} "UPDATE jobs SET node_failed = 'Source file does not exists' where job_id = ${JOB_ID};"
				echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/nodes.log
				rm -fv /tmp/nodes
				sleep 5
			fi
		else
			echo "Hooorrray.. No jobs to Process :)";
			rm -fv /tmp/nodes
			sleep 5
		fi
	else
		echo "Master process is running.."
		rm -fv /tmp/nodes
		sleep 5
	fi
done
exit 0
