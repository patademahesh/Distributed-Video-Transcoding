<?php
$host = '192.168.92.73';
$user = 'transcode';
$pass = 'transcode';
$db = 'transcoding';

$_Link = mysqli_connect($host,$user,$pass);
mysqli_select_db($_Link,$db);

