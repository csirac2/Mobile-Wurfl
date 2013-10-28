-- Don't forget to re-run script/update_sql.pl script if you modify this
DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
    name varchar(255) NOT NULL default '',
    value varchar(255) default '',
    groupid varchar(255) NOT NULL default '',
    deviceid varchar(255) NOT NULL default '',
    ts timestamp DEFAULT CURRENT_TIMESTAMP,
    KEY groupid (groupid),
    KEY name_deviceid (name,deviceid)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS device;
CREATE TABLE device (
    user_agent varchar(255) NOT NULL default '',
    actual_device_root enum('true','false') default 'false',
    id varchar(255) NOT NULL default '',
    fall_back varchar(255) NOT NULL default '',
    ts timestamp NOT NULL,
    KEY user_agent (user_agent),
    KEY id (id)
) ENGINE=InnoDB;
