-- Don't forget to re-run script/update_Mobile-Wurfl-SQL.pl script if you modify
DROP TABLE IF EXISTS capability;
CREATE TABLE capability (
        name varchar(255) NOT NULL DEFAULT '',
        value varchar(255) DEFAULT '',
        groupid varchar(255) NOT NULL DEFAULT '',
        deviceid varchar(255) NOT NULL DEFAULT '',
        ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS groupid ON capability (groupid);
CREATE INDEX IF NOT EXISTS name_deviceid ON capability (name, deviceid);
DROP TABLE IF EXISTS device;
CREATE TABLE device (
        user_agent varchar(255) NOT NULL DEFAULT '',
        actual_device_root varchar(255),
        id varchar(255) NOT NULL DEFAULT '',
        fall_back varchar(255) NOT NULL DEFAULT '',
        ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS user_agent ON device (user_agent);
CREATE INDEX IF NOT EXISTS id ON device (id);
