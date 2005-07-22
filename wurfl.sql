# MySQL dump 8.16
#
# Host: localhost    Database: wurfl
#--------------------------------------------------------
# Server version	4.0.21-max

#
# Table structure for table 'capability'
#

DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
  name varchar(100) NOT NULL default '',
  value varchar(100) default '',
  groupid varchar(100) NOT NULL default '',
  deviceid varchar(100) NOT NULL default '',
  KEY groupid (groupid),
  KEY name_deviceid (name,deviceid)
) TYPE=InnoDB;

#
# Table structure for table 'device'
#

DROP TABLE IF EXISTS device;
CREATE TABLE device (
  user_agent varchar(100) NOT NULL default '',
  actual_device_root enum('true','false') default 'false',
  id varchar(100) NOT NULL default '',
  fall_back varchar(100) NOT NULL default '',
  KEY user_agent (user_agent),
  KEY id (id)
) TYPE=InnoDB;

