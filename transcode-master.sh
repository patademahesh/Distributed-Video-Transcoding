#!/bin/bash

set -e
set -x
export PATH=$PATH:/root/bin

# Exit Traps
function finish {
	rm -fv /tmp/master
	rm -fv /srv/masters/$(hostname)
	echo "Error: Master Service Down" >> /var/log/master.log
}
trap finish EXIT

CPUNO=$(cat /proc/cpuinfo |grep processor|wc -l)
FORMAT="mp4"
BITRATE="128000 256000 512000 712000" # Used in Rsync command, if changed change in rsync also
DB_IP="172.18.10.111"
MYSQL="mysql --skip-column-names -utranscode -ptranscode -h ${DB_IP} transcoding -e"

while true; do
	mkdir -p /srv/masters
	date > /srv/masters/$(hostname)
	CURRENT_NODE=$(ls /srv/masters/ | grep -B99999 $(hostname) | wc -l)
	
	if [ ! -s /tmp/nodes ]; then
		echo "Master" > /tmp/master
		
		# look for work
		JOB_ID=$(${MYSQL} "SELECT jobid FROM jobs WHERE jobcomplete=nodecount AND error IS NULL AND master IS NULL LIMIT 1;")
		
		if [ ! -z ${JOB_ID} ]; then
			
			IPADDR=$(hostname -i)
			${MYSQL} "UPDATE jobs SET master = concat(ifnull(master,''), '${IPADDR},') where jobid = ${JOB_ID};"
			
			GETCURMASTER=$(${MYSQL} "SELECT master FROM jobs WHERE jobid = '${JOB_ID}'"| cut -d"," -f1);
			if [ ${GETCURMASTER} != ${IPADDR} ]; then
				rm -fv /tmp/master
				echo "JOB Already In process";
				sleep 5;
			else
				
				# Get Filename with extension and Filename w/o extension
				FILEWEXT=$(${MYSQL} "SELECT filename FROM jobs WHERE jobid = ${JOB_ID};")
				FILEWOEXT=${FILEWEXT%.*}
				CURDATE=$(${MYSQL} "SELECT starttime FROM jobs WHERE jobid = '${JOB_ID}'"| cut -d " " -f1)
				
				# Set job dirctory
				FILEPATH=$(${MYSQL} "SELECT filepath FROM jobs WHERE jobid = ${JOB_ID};")
				FTPPATH=$(echo ${FILEPATH} | cut -d"/" -f-4)
				#REMOTEPATH=$(echo ${FILEPATH} | cut -d"/" -f5- | sed 's/ /\\ /g')
				REMOTEPATH=$(echo ${FILEPATH} | cut -d"/" -f5-)
				
				# Check for Content Provider Details
				CONTPROVIDER=$(echo "${FILEPATH}"| cut -d"/" -f4)				
				
				# Set output directory and create it				
				#SHOWNAME=$(echo ${FILEPATH} | awk -F'/' {'print $9'})

				OUTPATH="/video-process/processed/${CONTPROVIDER}/${CURDATE}/${FILEWOEXT}/"
				mkdir -p "${OUTPATH}/LOGS/"
				
				ERROR=0;
				
				QUEUEID=$(${MYSQL} "SELECT id from queue WHERE jobid = ${JOB_ID} AND status = '2';")
				WORKERS=$(${MYSQL} "SELECT node from queue WHERE jobid = ${JOB_ID} AND status = '2';"|grep -v ${IPADDR} |sort -u)
				
				for i in ${WORKERS}; do
					IP=$(echo $i| cut -d','  -f1);
					echo "######### Syncing files back to master node from ${i} #########" >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1
					ESCOUTPATH=$(echo ${OUTPATH}|sed 's/ /\\ /g')
					
					if ! rsync --rsh="ssh -c arcfour256,arcfour128,blowfish-cbc,aes128-ctr,aes192-ctr,aes256-ctr" -av "${IP}:${ESCOUTPATH}" "${OUTPATH}"/ >> "${OUTPATH}${FILEWOEXT}-sync.log.txt" 2>&1 ; then
						ERROR=1
						ERRORLOG="File Sync To master Failed ,"
						break
					fi
				done				
				
				if [ $ERROR -ne '0' ]; then
					${MYSQL} "UPDATE jobs SET error = '${ERRORLOG}' where jobid = ${JOB_ID};"
					echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
					ERRORLOG=
					rm -fv /tmp/master
					sleep 5;
				else
					for i in ${WORKERS}; do
						IP=$(echo $i| cut -d','  -f1);
						ssh ${IP} "rm -fvr ${ESCOUTPATH}" >> "${OUTPATH}${FILEWOEXT}-delete.log.txt" 2>&1 || echo "OUTPATH remove from worker failed"
					done
					
					for b in ${BITRATE}; do
						CONCAT=;CONCAT="/dev/null"
						for i in ${QUEUEID}; do
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
					
					# .mp4 file
					cp -v "${OUTPATH}${FILEWOEXT}-512000.${FORMAT}" "${OUTPATH}${FILEWOEXT}.${FORMAT}" >> "${OUTPATH}${FILEWOEXT}.log.txt" 2>&1
					if ! /usr/local/bin/MP4Box -tmp /video-process/tmp/ -hint "${OUTPATH}${FILEWOEXT}.${FORMAT}" >> "${OUTPATH}${FILEWOEXT}.log.txt" 2>&1; then
						ERROR=1
						ERRORLOG="${ERRORLOG} MP4 Hinting Failed"
					fi
				
					if [ $ERROR -ne '0' ]; then
						${MYSQL} "UPDATE jobs SET error = '${ERRORLOG}' where jobid = ${JOB_ID};"
						echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
						ERRORLOG=
						rm -fv /tmp/master
					else						
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
						TMPVIDEOLEN=$(ffprobe  "${OUTPATH}${FILEWOEXT}.${FORMAT}" 2>&1 | /bin/grep Duration: | /bin/sed -e "s/^.*Duration: //" -e "s/\..*$//")
						VIDEOLEN=$(/bin/date -u -d "1970-01-01 ${TMPVIDEOLEN}" +"%s")
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
							${MYSQL} "UPDATE jobs SET error = '${ERRORLOG}' where jobid = ${JOB_ID};"
							echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
							ERRORLOG=
							rm -fv /tmp/master
						else
							# Update coversion end time
							${MYSQL} "UPDATE jobs SET conversiontime = current_timestamp where jobid = ${JOB_ID};"
							rm -fv /tmp/master
							
							# Cleaning all .ts and logs
							rm -f "${OUTPATH}"/*.ts >> "${OUTPATH}${FILEWOEXT}-delete.log.txt" 2>&1 || echo "removal of .ts failed"
							mv -f "${OUTPATH}"/*.txt "${OUTPATH}/LOGS/" || echo "Move log files to LOGS deirectory"
							
							# Start upload to akamai storage
							SYNCERROR=0;
							#while read line; do
							#	CPHOST=$(echo "$line"|awk '{print $4}');
							#	CPUSER=$(echo "$line"|awk '{print $2}');
							#	CPPASS=$(echo "$line"|awk '{print $3}');
							#	export RSYNC_PASSWORD=${CPPASS};
							#	
							#	echo '######### Syncing folder structure to CDN #########' >> "${OUTPATH}/LOGS/${FILEWOEXT}-sync.log.txt" 2>&1
							#	# Sync local folder structure to remote location
							#	if ! rsync --timeout=30  -f"+ */" -f"- *" -avz "${FTPPATH}"/ "${CPUSER}@${CPHOST}::${CPUSER}/" >> "${OUTPATH}/LOGS/${FILEWOEXT}-sync.log.txt" 2>&1; then
							#		SYNCERROR=1;
							#	fi
                            #
							#	echo '######### Syncing files to CDN #########' >> "${OUTPATH}/LOGS/${FILEWOEXT}-sync.log.txt" 2>&1
							#	if ! rsync --timeout=30 --progress --exclude=LOGS -avz "${OUTPATH}/" "${CPUSER}@${CPHOST}::${CPUSER}/${REMOTEPATH}/" >> "${OUTPATH}/LOGS/${FILEWOEXT}-sync.log.txt" 2>&1; then
							#		SYNCERROR=1;
							#	fi
							#done < <(${MYSQL} "SELECT * FROM cpdetails WHERE cp = '${CONTPROVIDER}';")
							
							if [ $SYNCERROR -ne '0' ]; then
								ERRORLOG="${ERRORLOG} Rsync Failed "
								${MYSQL} "UPDATE jobs SET error = '${ERRORLOG}' where jobid = ${JOB_ID};"
								echo "Error: Job Failed: ${JOB_ID} Log: ${ERRORLOG}" >> /var/log/master.log
								ERRORLOG=
								rm -fv /tmp/master
							else
								#rm -fv "${OUTPATH}"/*.mp4 >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .mp4 Failed"
								#rm -fv "${OUTPATH}"/*.3gp >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .3gp Failed"
								#rm -fv "${OUTPATH}"/*.flv >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .flv Failed"
								#rm -fv "${OUTPATH}"/*.jpg >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove .jpg Failed"
								#rm -fv "${FILEPATH}/${FILEWEXT}" >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Remove Source File Failed"
								
								for i in ${WORKERS}; do
									IP=$(echo $i| cut -d','  -f1);
									echo "######### Removing source file from ${i} #########" >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1
									#ssh ${IP} "rm -fv '${FILEPATH}/${FILEWEXT}'" >> "${OUTPATH}/LOGS/${FILEWOEXT}-delete.log.txt" 2>&1 || echo "Source file remove from worker failed"
								done
								
								# Clear previously failed job if exists
								#${MYSQL} "UPDATE jobs SET jobcomplete = 999 WHERE name LIKE '${FILEWEXT}' AND (error IS NOT NULL OR error IS NOT NULL);"
								# Update job status, so that the other workers know when its done
								${MYSQL} "UPDATE jobs SET jobcomplete=jobcomplete+1  WHERE jobid = ${JOB_ID};"
								# Update end time
								${MYSQL} "UPDATE jobs SET totaltime = current_timestamp where jobid = ${JOB_ID};"
								#${MYSQL} "UPDATE jobs SET jobcomplete = 999 WHERE name LIKE '${FILEWEXT}' AND (error IS NOT NULL OR error IS NOT NULL);"
								rm -fv /tmp/master
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
