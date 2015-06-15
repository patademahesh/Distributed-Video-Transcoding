# Simple Scalable, Parallel, Multi-bitrate Video Transcoding
Simple Scalable, Parallel, Multi-bitrate Video Transcoding On Centos / Ubuntu / Suse / RedHat (Bash Scripts)

Multi-bitrate Video processing requires lots of computing power and time to process full movie. There are different open source video transcoding and processing tools freely available in Linux, like libav-tools, ffmpeg, mencoder, and handbrake. However, none of these tools support **PARALLEL** computing easily.

After some research, I found amazing [solution](http://blog.dustinkirkland.com/2014/07/scalable-parallel-video-transcoding-on.html) designed by '[Dustin Kirkland](http://blog.dustinkirkland.com/2014/07/scalable-parallel-video-transcoding-on.html)' based on Ubuntu JUJU and [avconv](https://libav.org/avconv.html). But our requirement was little bit diffrent from Dustins's solution. Our requirement was to convert single video in Multi-bitrate and in formats like 3gp, flv and upload them to single or multiple CDN(like Akamai or tata). Also we want to build this solution on top of CentOS and ffmpeg. So I decided to  develop "Simple Scalable, Parallel, Multi-bitrate Video Transcoding System" by myself. Here is my solution.

The Algorithm is same as Dustin's solution but with some changes:

  1. Upload file to FTP. After a successful upload CallUploadScript(pure-ftpd function) will call script:
      - Script is responsible for syncing files to all nodes(Disabled ssh encryptions to speed up transfer)
      - Updating duration, file path, filename of video and number of nodes available currently for transcoding to MYSQL
  2. Transcode Nodes will split the work into even sized chunks for each node
  3. Each Node will then process their segments of video and raise a flag when done
  4. Master nodes will wait for each of the all-done flags, and then any master will pick the job to concatenate the result
  5. Upload converted files to different CDN

# Pre-requisites:
  1. bc
  2. nproc
  3. ffmpeg
  4. mysql
  5. mysql-server(For master node)
  6. mplayer
  7. rsync
  8. Password less ssh login
  9. nfs server and client
  10. supervisord
  11. ffprobe

# Installation:

1. Install ffmpeg(Click [here](http://wiki.razuna.com/display/ecp/FFMpeg+Installation+on+CentOS+and+RedHat) for instruction)
2. Download and copy all scripts(.sh files) to /srv directory
3. Change file permission to 755
4. Install Pure-FTPD and change CallUploadscript directive to yes in /etc/pure-ftpd.conf file
5. Create test user for FTP and set password

   `# useradd -m ftptest; passwd ftptest`
   
6. Run below commands to change pure-ftpd init script

   `# sed -i 's#start() {#start() {\n\t/usr/sbin/pure-uploadscript -B -r /srv/CallUpload.sh#g' /etc/init.d/pure-ftpd`

   `# sed -i 's#stop() {#stop() {\n\tkillall -9 pure-uploadscript#g' /etc/init.d/pure-ftpd`

7. restart pure-ftp service
8. Make sure to Change Database IP in all three scripts (DB_IP variable)
9. Install mysql-server and import SQL file 'transcoding.sql'. Create 'transcode' user with password same as username. Make sure user is able to connect from all of the worker nodes.
10. NFS Export /srv directory and mount it on all nodes with NFS client option "lookupcache=none"

11. On all servers install supervisord and copy supervisord.conf from download directory to /etc/supervisord.conf. Restart supervisord service.

12. To check the status of jobs you may use the dashboard. Copy frontend folder to your apache DocumentRoot. In my case its /var/www/html/

    `# cp -a frontend/ /var/www/html/ `
