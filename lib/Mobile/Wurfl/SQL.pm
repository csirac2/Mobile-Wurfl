package Mobile::Wurfl::SQL;
use strict;
use warnings;

my %SQL = (
    'pg' => <<'HERE'
-- Don't forget to re-run script/update_Mobile-Wurfl-SQL.pl script if you modify
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

HERE
    , 'generic' => <<'HERE'
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

HERE
    , 'mysql' => <<'HERE'
-- Don't forget to re-run script/update_Mobile-Wurfl-SQL.pl script if you modify
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

HERE
    , 'sqlite' => <<'HERE'
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
CREATE INDEX IF NOT EXISTS name_deviceid ON capability (name,deviceid);
DROP TABLE IF EXISTS device;
CREATE TABLE device (
        user_agent varchar(255) NOT NULL DEFAULT '',
        actual_device_root varchar(255),
        id varchar(255) NOT NULL DEFAULT '',
        fall_back varchar(255) NOT NULL DEFAULT '',
        ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS user_agent ON device (user_agent);
CREATE INDEX IF NOT EXISTS user_agent_idx
        ON device (user_agent COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS id ON device (id);

HERE
);

sub get {
    my ( $class, $driver ) = @_;
    my $sql;

    $driver = lc($driver);
    if (!defined $SQL{$driver}) {
        warn "No SQL found for driver '$driver', using 'generic' instead...\n";
        $sql = $SQL{generic};
    }
    else {
        $sql = $SQL{$driver};
    }

    return $sql;
}

1;
