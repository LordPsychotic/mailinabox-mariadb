#!/bin/bash
#
# MariaDB Database Server
# -----------------------
#
# Installs MariaDB and creates the databases and users used by
# Mail-in-a-Box: the main mail user/alias database, the Roundcube
# webmail database, and the Nextcloud database.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

echo "Installing MariaDB (database server)..."
apt_install mariadb-server mariadb-client

# Ensure MariaDB is running.
restart_service mariadb

# Generate passwords for each database user if they are not already set
# (i.e. during a re-install we keep the existing passwords).
if [ -z "${MAIL_DB_PASS:-}" ]; then
	MAIL_DB_PASS=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
fi
if [ -z "${ROUNDCUBE_DB_PASS:-}" ]; then
	ROUNDCUBE_DB_PASS=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
fi
if [ -z "${NEXTCLOUD_DB_PASS:-}" ]; then
	NEXTCLOUD_DB_PASS=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
fi

# Create databases and users. Using IF NOT EXISTS ensures idempotent re-runs.
mysql --defaults-file=/etc/mysql/debian.cnf << EOF
CREATE DATABASE IF NOT EXISTS mailinabox CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'mailinabox'@'127.0.0.1' IDENTIFIED BY '$MAIL_DB_PASS';
GRANT ALL PRIVILEGES ON mailinabox.* TO 'mailinabox'@'127.0.0.1';

CREATE USER IF NOT EXISTS 'roundcube'@'127.0.0.1' IDENTIFIED BY '$ROUNDCUBE_DB_PASS';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'127.0.0.1';

CREATE USER IF NOT EXISTS 'nextcloud'@'127.0.0.1' IDENTIFIED BY '$NEXTCLOUD_DB_PASS';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'127.0.0.1';

-- Update passwords on existing users (handles re-installs where the password changed).
ALTER USER 'mailinabox'@'127.0.0.1' IDENTIFIED BY '$MAIL_DB_PASS';
ALTER USER 'roundcube'@'127.0.0.1' IDENTIFIED BY '$ROUNDCUBE_DB_PASS';
ALTER USER 'nextcloud'@'127.0.0.1' IDENTIFIED BY '$NEXTCLOUD_DB_PASS';

FLUSH PRIVILEGES;
EOF

# Export so that subsequent setup scripts can use these values.
export MAIL_DB_PASS
export ROUNDCUBE_DB_PASS
export NEXTCLOUD_DB_PASS
