#!/bin/bash

set -e
set -x
export PATH=$PATH:/root/bin

# Exit Traps
function finish {
	rm -f "/srv/workers/$(hostname)"
	rm -fv /tmp/nodes
	echo "Error: Nodes Service Down" >> /var/log/nodes.log
}
trap finish EXIT

CPUNO=$(cat /proc/cpuinfo |grep processor|wc -l)
FORMAT="mp4"
BITRATE="128 256 512 712" # Used in Rsync command, if changed change in rsync also
DB_IP="172.18.10.111"
MYSQL="mysql --skip-column-names -utranscode -ptranscode -h ${DB_IP} transcoding -e"
IPADDR=$(hostname -i)

while true; do
	mkdir -p /srv/workers
	date > /srv/workers/$(hostname)
	CURRENT_NODE=$(ls /srv/workers/ | grep -B99999 $(hostname) | wc -l)
	CURRENT_NODE=$((CURRENT_NODE-1))
	
	if [ ! -s /tmp/master ]; then
		# look for work	
		JOB_ID=$(${MYSQL} "SELECT jobid FROM jobs WHERE jobcomplete<nodecount AND jobcount!=nodecount AND error IS NULL AND master IS NULL LIMIT 1;")
		
		[ ! -z ${JOB_ID} ] && QUEUEID=$(${MYSQL} "SELECT id from queue WHERE jobid = ${JOB_ID} AND status = '0' limit 1;")
		
		if [ ! -z ${JOB_ID} ] && [ ! -z ${QUEUEID} ]; then
		
			echo "${JOB_ID}" > /tmp/nodes
			# Update current node number to node_id field
			#UPDATECNT=${MYSQL} "UPDATE queue SET node = '${IPADDR}',status = '1' WHERE id = ${QUEUEID} AND status = '0' limit 1;SELECT ROW_COUNT();"
			UPDATECNT=$(${MYSQL} "UPDATE queue SET node = concat(ifnull(node,''), '${IPADDR},'),status = '1' WHERE id = ${QUEUEID} AND status = '0' limit 1;SELECT ROW_COUNT();")
			
			if [ ${UPDATECNT} -eq 1 ]; then
				# Check if this is first node to pick job for processing, If yes then update start time
				TMP1=$(${MYSQL} "SELECT jobcount FROM jobs WHERE jobid = ${JOB_ID};")
				if [ "${TMP1}" = "0" ]; then
					${MYSQL} "UPDATE jobs SET starttime = current_timestamp where jobid = ${JOB_ID};"
				fi				
				${MYSQL} "UPDATE jobs SET jobcount=jobcount+1 where jobid = ${JOB_ID};"
				
				CURDATE=$(date +%F)				
				# Get Filename with extension and Filename w/o extension
				FILEPATH=$(${MYSQL} "SELECT filepath FROM jobs WHERE jobid = ${JOB_ID};")
				FILEWEXT=$(${MYSQL} "SELECT filename FROM jobs WHERE jobid = ${JOB_ID};")
				FILEWOEXT=${FILEWEXT%.*}	# filename only w/o extension
				
				# Get Content Provider
				CONTPROVIDER=$(echo "${FILEPATH}"| cut -d"/" -f4)
				
				# Set output directory and create it
				if echo ${FILEPATH} | grep -q '/mc_gujrati_videos/'; then
					SHOWNAME=$(echo ${FILEPATH} | awk -F'/' {'print $10'})
				else
					SHOWNAME=$(echo ${FILEPATH} | awk -F'/' {'print $9'})
				fi

				OUTPATH="/video-process/processed/${CONTPROVIDER}/${CURDATE}/${FILEWOEXT}/"
				mkdir -p "${OUTPATH}"
				
				# Check if source file exists
				if [ -f "${FILEPATH}/${FILEWEXT}" ]; then
					
					# Set source file with full filepath
					FILENAME="${FILEPATH}/${FILEWEXT}"
					
					# Get file duration in seconds
					START_TIME=$(${MYSQL} "SELECT starttime FROM queue WHERE id = ${QUEUEID};")
					LENGTH=$(${MYSQL} "SELECT length FROM queue WHERE id = ${QUEUEID};")
					
					# Write the command to a log file
					echo "ffmpeg -threads ${CPUNO} -ss ${START_TIME} -i ${FILENAME} -t ${LENGTH} -r 29.97 -vcodec libx264 -acodec aac -bsf:v h264_mp4toannexb -f mpegts -strict experimental -y ${OUTPATH}${FILEWOEXT}.part${QUEUEID}.ts >> ${OUTPATH}${FILEWOEXT}.part${QUEUEID}.log.txt 2>&1" > "${OUTPATH}${FILEWOEXT}.part${QUEUEID}.log.txt"
					
					ERROR=0;
					ERRORLOG=;
					
					streams_stream_0_width= ; streams_stream_0_height=
					
					eval $(ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=height,width "${FILENAME}")
					SIZE=${streams_stream_0_width}x${streams_stream_0_height}
					
					REOLVIDEO=$(echo ${SIZE} |sed 's#x#*#g' | bc)
					RESOLUTION=$(echo "scale=1; $streams_stream_0_width/$streams_stream_0_height" | bc)
					
					transcode() {
						declare -a BITRATE=('128' '256' '512' '712');
						ARRAYCNT=0
						for i in $@; do
							if [ ${REOLVIDEO} -gt $(echo  ${i}|sed 's#x#*#g' |bc) ]; then
								VDR="$i"; VBR=${BITRATE[$ARRAYCNT]}
								if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -s ${VDR} -movflags rtphint -b:v ${VBR}k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${QUEUEID}-${VBR}000.ts" >> "${OUTPATH}${FILEWOEXT}.part${QUEUEID}-${VBR}000.log.txt" 2>&1; then
									ERROR=1
									ERRORLOG="${ERRORLOG}Failed: ${VBR} Bitrate Conversion"
								fi
							else
								VBR=${BITRATE[$ARRAYCNT]}
								if ! ffmpeg -threads ${CPUNO} -ss ${START_TIME} -t ${LENGTH} -i "${FILENAME}" -movflags rtphint -b:v ${VBR}k -vcodec libx264 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.part${QUEUEID}-${VBR}000.ts" >> "${OUTPATH}${FILEWOEXT}.part${QUEUEID}-${VBR}000.log.txt" 2>&1; then
									ERROR=1
									ERRORLOG="${ERRORLOG}Failed: ${VBR} Bitrate Conversion"
								fi
							fi
							ARRAYCNT=$(expr $ARRAYCNT + 1)
						done
					}
					
					if [ ${RESOLUTION} = '1.3' ]; then 
						transcode 320x240 480x360 640x480 1024x768
					elif [ ${RESOLUTION} = '1.7' ]; then 
						transcode 384x216 512x288 640x360 1024x576
					else 
						transcode 384x216 512x288 640x360 1024x576
					fi

					if [ $ERROR -ne '0' ]; then
						${MYSQL} "UPDATE jobs SET error = '${ERRORLOG}' where jobid = ${JOB_ID};"
						echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/nodes.log
						ERRORLOG=
						rm -fv /tmp/nodes
						sleep 5
					else
						#rm -fv "${FILENAME}"
						# Update job status, so that the other workers know when its done
						${MYSQL} "UPDATE jobs SET jobcomplete=jobcomplete+1  WHERE jobid = ${JOB_ID};"
						${MYSQL} "UPDATE queue SET status=status+1 WHERE id = ${QUEUEID};"
						rm -fv /tmp/nodes
						sleep 5
					fi
				else
					${MYSQL} "UPDATE jobs SET error = 'Source file does not exists' where jobid = ${JOB_ID};"
					echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/nodes.log
					rm -fv /tmp/nodes
					sleep 5
				fi
			else
				echo "Job is already in process :(";
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
