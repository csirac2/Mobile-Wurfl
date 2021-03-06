-- Don't forget to re-run script/update_Mobile-Wurfl-SQL.pl script if you modify
DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
    name VARCHAR(255) NOT NULL DEFAULT '',
    value VARCHAR(255) DEFAULT '',
    groupid VARCHAR(255) NOT NULL DEFAULT '',
    deviceid VARCHAR(255) NOT NULL DEFAULT '',
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX groupid ON capability (groupid);
CREATE INDEX name_deviceid ON capability (name, deviceid);
DROP TABLE IF EXISTS device;
CREATE TABLE device (
    user_agent VARCHAR(255) NOT NULL DEFAULT '',
    actual_device_root VARCHAR(255),
    id VARCHAR(255) NOT NULL DEFAULT '',
    fall_back VARCHAR(255) NOT NULL DEFAULT '',
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX id ON device (id);
CREATE INDEX user_agent ON device (user_agent);
CREATE INDEX user_agent_idx
    ON device (user_agent varchar_pattern_ops);
