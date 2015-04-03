#!/bin/bash

set -e
#set -x

# Exit Traps
function finish {
	rm -fv /tmp/master
	rm -fv /srv/masters/$(hostname)
	echo "Error: Master Service Down" >> /var/log/master.log
}
trap finish EXIT

CPUNO=$(/usr/bin/nproc)
FORMAT="mp4"
BITRATE="128000 256000 512000 712000" # Used in Rsync command, if changed change in rsync also
MASTER_NODE="192.168.92.73"
MYSQL="mysql --skip-column-names -utranscode -ptranscode -h ${MASTER_NODE} transcoding -e"
IPADDR=$(ifconfig eth0 | grep -v 'inet6'| grep 'addr:'| sed "s/Bcast.*//g"| cut -d ":" -f2|sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')

while true; do
	mkdir -p /srv/masters
	date > /srv/masters/$(hostname)
	CURRENT_NODE=$(ls /srv/masters/ | grep -B99999 $(hostname) | wc -l)
	#CURRENT_NODE=$((CURRENT_NODE-1))
	
	if [ ! -s /tmp/nodes ]; then
		echo "Master" > /tmp/master
		
		# look for work
		JOB_ID=$(${MYSQL} "SELECT job_id FROM jobs WHERE job_status=no_nodes AND node_failed IS NULL AND job_failed IS NULL AND curmaster IS NULL AND conversion_end_time IS NULL LIMIT 1;")
		
		if [ ! -z ${JOB_ID} ]; then
			
			IPADDR=$(ifconfig eth0 | grep -v 'inet6'| grep 'addr:'| sed "s/Bcast.*//g"| cut -d ":" -f2|sed -e 's/^[ \t]*//' -e 's/[ \t]*$//')
			${MYSQL} "UPDATE jobs SET curmaster = concat(ifnull(curmaster,''), '${IPADDR},') where job_id = ${JOB_ID};"
			
			GETCURMASTER=$(${MYSQL} "SELECT curmaster FROM jobs WHERE job_id = '${JOB_ID}'"| cut -d"," -f1)
			if [ ${GETCURMASTER} != ${IPADDR} ]; then
				rm -fv /tmp/master
				echo "JOB Already In process";
				sleep 5;
			else
				
				# Get Filename with extension and Filename w/o extension
				FILEWEXT=$(${MYSQL} "SELECT name FROM jobs WHERE job_id = ${JOB_ID};")
				FILEWOEXT=${FILEWEXT%.*}
				CURDATE=$(${MYSQL} "SELECT start_time FROM jobs WHERE job_id = '${JOB_ID}'"| cut -d " " -f1)
				
				# Set job dirctory
				FILEPATH=$(${MYSQL} "SELECT path FROM jobs WHERE job_id = ${JOB_ID};")
				FTPPATH=$(echo ${FILEPATH} | cut -d"/" -f-4)
				REMOTEPATH=$(echo ${FILEPATH} | cut -d"/" -f5-)
				
				# Check for Content Provider Details
				CONTPROVIDER=$(echo "${FILEPATH}"| cut -d"/" -f4)
				CPHOST=$(${MYSQL} "SELECT host FROM cpdetails WHERE cp = '${CONTPROVIDER}';")
				CPUSER=$(${MYSQL} "SELECT user FROM cpdetails WHERE cp = '${CONTPROVIDER}';")
				CPPASS=$(${MYSQL} "SELECT password FROM cpdetails WHERE cp = '${CONTPROVIDER}';")
				export RSYNC_PASSWORD=${CPPASS}
				
				# Set output directory and create it
				OUTPATH="/video-process/processed/${CONTPROVIDER}/${CURDATE}/${FILEWOEXT}/"
				mkdir -p "${OUTPATH}"
				mkdir -p "${OUTPATH}/LOGS/"

				# Get total number of nodes
				TOTAL_NODES_TMP=$(${MYSQL} "SELECT no_nodes FROM jobs WHERE job_id = ${JOB_ID};")
				TOTAL_NODES=$((TOTAL_NODES_TMP-1))
				
				# Kill off any previous running jobs
				# killall -9 ffmpeg 2>/dev/null || true
				ERROR=0;
				
				for i in $(ls /srv/workers/ | grep -v $(hostname)); do
					echo "######### Syncing files back to master node from ${i} #########" >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1
					rsync --timeout=30  -f"+ */" -f"- *" -rRvz "${i}:/${OUTPATH}" /  >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1 || echo "File Sync back to master failed"
					
					if ! rsync --rsh="ssh -c arcfour256,arcfour128,blowfish-cbc,aes128-ctr,aes192-ctr,aes256-ctr" -av "${i}:/${OUTPATH}"/ "${OUTPATH}"/ >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1 ; then
						ERROR=1
						ERRORLOG="File Sync To master Failed ,"
						break
					else
						ssh ${i} "rm -fvr ${OUTPATH}" >> "${OUTPATH}${FILEWOEXT}-delete.log.txt" 2>&1 || echo "OUTPATH remove from worker failed"
					fi
				done
				
				if [ $ERROR -ne '0' ]; then
					${MYSQL} "UPDATE jobs SET node_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
					echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
					ERRORLOG=
					rm -fv /tmp/master
					sleep 5;
				else					
					# Check for error
					if [ $ERROR -ne '0' ]; then
						${MYSQL} "UPDATE jobs SET node_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
						echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
						ERRORLOG=						
						rm -fv /tmp/master
					else
						# Concatenate the clips together
						for b in ${BITRATE}; do
							CONCAT=;CONCAT="/dev/null"
							for i in $(seq 0 ${TOTAL_NODES}); do
								if [ -e "${OUTPATH}${FILEWOEXT}.part${i}-${b}.ts" ]; then
									CONCAT="${CONCAT}|${OUTPATH}${FILEWOEXT}.part${i}-${b}.ts"
								fi
							done

							# Write the command to a log file
							echo "ffmpeg -i concat:${CONCAT} -c copy -bsf:a aac_adtstoasc -y ${OUTPATH}${FILEWOEXT}-${b}.${FORMAT}" > "${OUTPATH}${FILEWOEXT}-${b}.log.txt"
							
							# Concatenate the clips together
							if ! ffmpeg -i concat:"${CONCAT}" -c copy -bsf:a aac_adtstoasc -y "${OUTPATH}${FILEWOEXT}-${b}.${FORMAT}" >> "${OUTPATH}${FILEWOEXT}-${b}.log.txt" 2>&1; then
								ERROR=1
								ERRORLOG="${ERRORLOG} Concatenation Failed: ${b} Bitrate "
								break;
							fi
						done
					
						if [ $ERROR -ne '0' ]; then
							${MYSQL} "UPDATE jobs SET node_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
							echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
							ERRORLOG=
							rm -fv /tmp/master
						else
							# .mp4 file
							cp -v "${OUTPATH}${FILEWOEXT}-128000.${FORMAT}" "${OUTPATH}${FILEWOEXT}.${FORMAT}" >> "${OUTPATH}${FILEWOEXT}.log.txt" 2>&1
							
							# 3gp Conversion
							if ! ffmpeg -threads ${CPUNO} -i "${OUTPATH}${FILEWOEXT}-128000.${FORMAT}" -r 12.00 -b:v 128k -s 176x144 -vcodec h263 -acodec libfaac -ab 20k -ar 44100 -y "${OUTPATH}${FILEWOEXT}.3gp" >> "${OUTPATH}${FILEWOEXT}-3gp.log.txt" 2>&1; then
								ERROR=1
								ERRORLOG="${ERRORLOG} Conversion Failed: 3gp "
							fi
							
							# FLV Conversion
							echo "ffmpeg -threads ${CPUNO} -i ${OUTPATH}${FILEWOEXT}-128000.${FORMAT} -vcodec copy -acodec copy -y ${OUTPATH}${FILEWOEXT}.flv" > "${OUTPATH}${FILEWOEXT}-flv.log.txt"
											
							if ! ffmpeg -threads ${CPUNO} -i "${OUTPATH}${FILEWOEXT}-128000.${FORMAT}" -vcodec copy -acodec copy -y "${OUTPATH}${FILEWOEXT}.flv" >> "${OUTPATH}${FILEWOEXT}-flv.log.txt" 2>&1; then
								ERROR=1
								ERRORLOG="${ERRORLOG} Conversion Failed: flv "
							fi
							
							# Thumbnail generation
							VIDEOLEN=$(mplayer -identify "${OUTPATH}${FILEWOEXT}.${FORMAT}" 2>/dev/null | grep ID_LENGTH | cut -d= -f2 | cut -d. -f1)
							#VIDEOLEN=$(expr ${VIDEOLEN} - 10)
							MODVIDEOLEN=$((${VIDEOLEN} % 10))
							if [ ${MODVIDEOLEN} -ne 0 ]; then
								VIDEOLEN=$(((10 - ${VIDEOLEN} % 10) + ${VIDEOLEN}))
							fi
							
							TMPFRAME=$(expr ${VIDEOLEN} / 10)
							SNAPFRAME=$(expr ${TMPFRAME} + 1)
							
							TOTALFRAMES=$(ffprobe -select_streams v -show_streams "${OUTPATH}${FILEWOEXT}.${FORMAT}" 2>/dev/null | grep nb_frames | sed -e 's/nb_frames=//')
							THUMBNAILVAL=$(expr "${TOTALFRAMES} / ${SNAPFRAME}" | bc)
							
							if ! ffmpeg -threads ${CPUNO} -ss 10 -i "${OUTPATH}${FILEWOEXT}-712000.${FORMAT}" -f image2 -vf "thumbnail=${THUMBNAILVAL},scale=120:96,tile=12x10" -pix_fmt yuvj420p -an -vsync 0 -y "${OUTPATH}${FILEWOEXT}-120x69-thumb-%03d.jpg" >> "${OUTPATH}${FILEWOEXT}-snap.log.txt" 2>&1; then
								ERROR=1
								ERRORLOG="${ERRORLOG} Thumbnail generation Failed: 120x69 "
							fi
							
							if ! ffmpeg -threads ${CPUNO} -ss 10 -i "${OUTPATH}${FILEWOEXT}-712000.${FORMAT}" -f image2 -vf "thumbnail=${THUMBNAILVAL},scale=80:44,tile=12x10" -pix_fmt yuvj420p -an -vsync 0 -y "${OUTPATH}${FILEWOEXT}-80x44-thumb-%03d.jpg" >> "${OUTPATH}${FILEWOEXT}-snap.log.txt" 2>&1; then
								ERROR=1
								ERRORLOG="${ERRORLOG} Thumbnail generation Failed: 80x44 "
							fi
							
							# Check for error
							if [ $ERROR -ne '0' ]; then
								${MYSQL} "UPDATE jobs SET job_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
								echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
								ERRORLOG=
								rm -fv /tmp/master
							else
								# Update coversion end time
								${MYSQL} "UPDATE jobs SET conversion_end_time = current_timestamp where job_id = ${JOB_ID};"
								rm -fv /tmp/master
								
								echo '######### Syncing folder structure to akamai #########' >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1
								# Sync local folder structure to remote location
								if ! rsync --timeout=30  -f"+ */" -f"- *" -avz "${FTPPATH}"/ "${CPUSER}@${CPHOST}::${CPUSER}/" >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1 ; then
									ERRORLOG="${ERRORLOG} Rsync Failed "
									${MYSQL} "UPDATE jobs SET job_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
									echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
									ERRORLOG=
									rm -fv /tmp/master
								else
									# Cleaning all .ts and logs
									rm -f "${OUTPATH}"/*.ts >> "${OUTPATH}${FILEWOEXT}-delete.log.txt" 2>&1 || echo "removal of .ts failed"
									mv -f "${OUTPATH}"/*.txt "${OUTPATH}/LOGS/" || echo "Move log files to LOGS deirectory"
									
									echo '######### Syncing files to akamai #########' >> "${OUTPATH}/LOGS/${FILEWOEXT}-sync.log.txt" 2>&1
									# Start upload to akamai storage
									if ! rsync --timeout=30 --progress --exclude=LOGS -avz "${OUTPATH}"/ "${CPUSER}@${CPHOST}::${CPUSER}/${REMOTEPATH}/" >> "${OUTPATH}/LOGS/${FILEWOEXT}-sync.log.txt" 2>&1; then
										ERRORLOG="${ERRORLOG} Rsync Failed "
										${MYSQL} "UPDATE jobs SET job_failed = '${ERRORLOG}' where job_id = ${JOB_ID};"
										echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
										ERRORLOG=
										rm -fv /tmp/master
									else
										rm -fv "${OUTPATH}"/*.mp4 >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .mp4 Failed"
										rm -fv "${OUTPATH}"/*.3gp >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .3gp Failed"
										rm -fv "${OUTPATH}"/*.flv >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .flv Failed"
										rm -fv "${OUTPATH}"/*.jpg >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .jpg Failed"
										rm -fv "${FILEPATH}/${FILEWEXT}" >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove Source File Failed"
										
										# Clear previously failed job if exists
										${MYSQL} "DELETE FROM jobs WHERE name LIKE '${FILEWEXT}' AND (node_failed IS NOT NULL OR job_failed IS NOT NULL);"
										# Update job status, so that the other workers know when its done
										${MYSQL} "UPDATE jobs SET job_status=job_status+1  WHERE job_id = ${JOB_ID};"
										# Update end time
										${MYSQL} "UPDATE jobs SET end_time = current_timestamp where job_id = ${JOB_ID};"
										${MYSQL} "DELETE FROM jobs WHERE name LIKE '${FILEWEXT}' AND (conversion_end_time IS NULL OR end_time IS NULL);"
										rm -fv /tmp/master
									fi
								fi
							fi
						fi
					fi
				fi
			fi
		else
			rm -fv /tmp/master
			echo "Hooorrray.. No jobs to Process :)";
			sleep 5;
		fi
	else
		echo "Node process is running.."
		rm -fv /tmp/master
		sleep 5
	fi
done
exit 0
