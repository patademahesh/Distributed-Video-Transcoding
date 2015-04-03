# Scalable-Parallel-Video-Transcoding
Simple Scalable, Parallel, Multi-bitrate Video Transcoding On Centos / Ubuntu / Suse / RedHat (Bash Scripts)

Multi-bitrate Video processing requires lots of computing power to process full movie and its a time consuming job. There are numerous, excellent, open source video transcoding and processing tools freely available in Linux, including libav-tools, ffmpeg, mencoder, and handbrake.  Surprisingly, however, none of these tools support PARALLEL computing easily.

After some research, I found amazing solution designed/developed by 'Dustin Kirkland' based on Ubuntu JUJU and avconv (http://blog.dustinkirkland.com/2014/07/scalable-parallel-video-transcoding-on.html). But our requirement was little bit diffrent from Dustins's solution. Our requirement was to convert single video in Multi-bitrate and in format like 3gp, flv and also in our organization we prefer using CentOS and ffmpeg. So I decided to design and develop "Simple Scalable, Parallel, Multi-bitrate Video Transcoding System" myself. I'm happy to share the result with you today.

The Algorithm is same as Dustin's solution but with some changes:

  1. Upload file to FTP. After a successful upload CallUploadScript(pure-ftpd function) will call script:
      - Script is responsible for syncing files to all nodes
      - Updating duration, file path, filename of video and number of nodes available currently for transcoding to MYSQL
  2. Transcode Nodes will split the work into even sized chunks for each node
  3. Each Node will then process their segments of video and raise a flag when done
  4. Master node will wait for each of the all-done flags, and then any free master-process will pick the job to concatenate the result
  5. Upload converted files to different CDN

Pre-requisites:
  1. bc
  2. nproc
  3. ffmpeg
  4. mysql
  5. mysql-server(For master node)
  6. mplayer
  7. rsync
  8. Password less ssh login
  9. nfs server and client
