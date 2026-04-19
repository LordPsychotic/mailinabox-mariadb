#!/bin/bash
#
# MariaDB Database Server
# -----------------------
#
# Installs MariaDB and creates the databases and users used by
# Mail-in-a-Box: the main mail user/alias database, the Roundcube
# webmail database, and the Nextcloud database.

source setup/functions.sh # load our functions
# Note: /etc/mailinabox.conf does not exist yet on first install.
# All variables we need (MAIL_DB_PASS, etc.) are already exported
# by the calling script (start.sh).

DB_CONFIG_FILE=/etc/mailinabox-db.conf

if [ -f "$DB_CONFIG_FILE" ]; then
	source "$DB_CONFIG_FILE"
fi

echo "Installing MariaDB (database server)..."
echo "This can take a few minutes on first install."

# Prevent MariaDB from auto-starting during package installation.
# We'll start it explicitly below after installation completes.
POLICY_RC_CREATED=0
cleanup_policy_rc() {
	if [ "$POLICY_RC_CREATED" = "1" ]; then
		rm -f /usr/sbin/policy-rc.d
	fi
}
trap cleanup_policy_rc EXIT

# Respect an existing policy-rc.d and avoid overwriting it.
if [ ! -e /usr/sbin/policy-rc.d ]; then
	cat > /usr/sbin/policy-rc.d << EOF
#!/bin/sh
# Prevent MariaDB from starting during apt install.
case "\$1" in
	mariadb|mysql) exit 101 ;;
esac
exit 0
EOF
	chmod +x /usr/sbin/policy-rc.d
	POLICY_RC_CREATED=1
fi

# Show apt output for this long-running step so setup doesn't look hung.
DEBIAN_FRONTEND=noninteractive apt-get -y \
	-o DPkg::Lock::Timeout=600 \
	-o Dpkg::Options::="--force-confdef" \
	-o Dpkg::Options::="--force-confnew" \
	install mariadb-server mariadb-client

cleanup_policy_rc
trap - EXIT

# Ensure MariaDB is running.
echo "Starting MariaDB service..."
if ! service mariadb restart > /dev/null 2>&1; then
	service mysql restart
fi

# Wait until the server is responsive before issuing SQL statements.
for _ in $(seq 1 30); do
	if mysqladmin --defaults-file=/etc/mysql/debian.cnf ping > /dev/null 2>&1; then
		break
	fi
	sleep 1
done
if ! mysqladmin --defaults-file=/etc/mysql/debian.cnf ping > /dev/null 2>&1; then
	echo "MariaDB failed to start."
	exit 1
fi

# Generate passwords for each database user if they are not already set
# (i.e. during a re-install we keep the existing passwords).
if [ -z "${MAIL_DB_PASS:-}" ] && [ -n "${MAILINABOX_DB_PASSWORD:-}" ]; then
	MAIL_DB_PASS=$MAILINABOX_DB_PASSWORD
fi
if [ -z "${ROUNDCUBE_DB_PASS:-}" ] && [ -n "${ROUNDCUBE_DB_PASSWORD:-}" ]; then
	ROUNDCUBE_DB_PASS=$ROUNDCUBE_DB_PASSWORD
fi
if [ -z "${NEXTCLOUD_DB_PASS:-}" ] && [ -n "${NEXTCLOUD_DB_PASSWORD:-}" ]; then
	NEXTCLOUD_DB_PASS=$NEXTCLOUD_DB_PASSWORD
fi

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
GRANT SELECT, INSERT, UPDATE, DELETE ON mailinabox.* TO 'mailinabox'@'127.0.0.1';

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

# Initialize the Mail-in-a-Box schema on the application database.
mysql --defaults-file=/etc/mysql/debian.cnf mailinabox < "$PWD/setup/mailinabox-schema.sql"

# Persist database credentials in a dedicated root-only config file.
cat > "$DB_CONFIG_FILE" << EOF
MAILINABOX_DB_HOST=127.0.0.1
MAILINABOX_DB_PORT=3306
MAILINABOX_DB_NAME=mailinabox
MAILINABOX_DB_USER=mailinabox
MAILINABOX_DB_PASSWORD=$MAIL_DB_PASS
ROUNDCUBE_DB_HOST=127.0.0.1
ROUNDCUBE_DB_PORT=3306
ROUNDCUBE_DB_NAME=roundcube
ROUNDCUBE_DB_USER=roundcube
ROUNDCUBE_DB_PASSWORD=$ROUNDCUBE_DB_PASS
NEXTCLOUD_DB_HOST=127.0.0.1
NEXTCLOUD_DB_PORT=3306
NEXTCLOUD_DB_NAME=nextcloud
NEXTCLOUD_DB_USER=nextcloud
NEXTCLOUD_DB_PASSWORD=$NEXTCLOUD_DB_PASS
EOF
chmod 600 "$DB_CONFIG_FILE"

# Export so that subsequent setup scripts can use these values.
export MAIL_DB_PASS
export ROUNDCUBE_DB_PASS
export NEXTCLOUD_DB_PASS
