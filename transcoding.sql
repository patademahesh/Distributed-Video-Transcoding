-- phpMyAdmin SQL Dump
-- version 4.0.10.7
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Generation Time: Apr 18, 2015 at 11:54 AM
-- Server version: 5.6.21-70.1
-- PHP Version: 5.3.3

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `transcoding`
--
CREATE DATABASE IF NOT EXISTS `transcoding` DEFAULT CHARACTER SET latin1 COLLATE latin1_swedish_ci;
USE `transcoding`;

-- --------------------------------------------------------

--
-- Table structure for table `cpdetails`
--

CREATE TABLE IF NOT EXISTS `cpdetails` (
  `cp` varchar(100) NOT NULL,
  `user` varchar(100) NOT NULL,
  `password` varchar(100) NOT NULL,
  `host` varchar(100) NOT NULL,
  UNIQUE KEY `cp` (`cp`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `jobs`
--

CREATE TABLE IF NOT EXISTS `jobs` (
  `job_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `path` varchar(255) NOT NULL,
  `duration` int(11) NOT NULL,
  `node_status` int(11) NOT NULL,
  `no_nodes` int(11) NOT NULL,
  `job_status` int(11) NOT NULL,
  `node_failed` varchar(255) DEFAULT NULL,
  `job_failed` varchar(255) DEFAULT NULL,
  `start_time` varchar(100) NOT NULL,
  `conversion_end_time` varchar(100) DEFAULT NULL,
  `end_time` varchar(100) DEFAULT NULL,
  `node_id` varchar(10) NOT NULL,
  `cp` varchar(50) DEFAULT NULL,
  `curmaster` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`job_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 AUTO_INCREMENT=5959 ;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
