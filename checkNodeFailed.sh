#!/bin/bash
MYSQL="/usr/bin/mysql --skip-column-names -utranscode -ptranscode -h 172.18.10.111 transcoding -e"

JOB_ID=$(${MYSQL} "SELECT jobid FROM jobs WHERE jobcomplete<nodecount AND jobcount<=nodecount AND error IS NULL AND master IS NULL;")
if [ -n "${JOB_ID}" ]; then
	for j in ${JOB_ID}; do
		QUEUEID=$(${MYSQL} "SELECT id from queue WHERE jobid = ${j} AND status = '1';");

		for i in ${QUEUEID}; do
			NODEIP=$(${MYSQL} "SELECT node from queue WHERE id = ${i} AND node IS NOT NULL AND status = '1';" | cut -d','  -f1)
			if [ -n "${NODEIP}" ]; then
				HOST=$(ssh ${NODEIP} hostname)
				if [ -n "${HOST}" ] && [ ! -f /srv/workers/${HOST} ]; then
					echo "Changing Job status for failed node $HOST : ${i}" >> /var/log/failed-node.log
					${MYSQL} "UPDATE queue SET node=NULL,status=0 WHERE id = ${i};"
					${MYSQL} "UPDATE jobs SET jobcount=jobcount-1 WHERE jobid = ${j};"
				fi
			fi
		done
		sleep 2
	done
fi