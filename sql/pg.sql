-- Don't forget to re-run script/update_sql.pl script if you modify this
DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
    name char(255) NOT NULL default '',
    value char(255) default '',
    groupid char(255) NOT NULL default '',
    deviceid char(255) NOT NULL default '',
    ts DATETIME default CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS groupid ON capability (groupid);
CREATE INDEX IF NOT EXISTS name_deviceid ON capability (name,deviceid);
DROP TABLE IF EXISTS device;
CREATE TABLE device (
    user_agent varchar(255) NOT NULL default '',
    actual_device_root char(255),
    id char(255) NOT NULL default '',
    fall_back char(255) NOT NULL default '',
    ts DATETIME default CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS user_agent ON device (user_agent);
CREATE INDEX IF NOT EXISTS user_agent_idx
    ON device (user_agent varchar_pattern_ops);
CREATE INDEX IF NOT EXISTS id ON device (id);
