#!/bin/bash
if [ -z "${NONINTERACTIVE:-}" ]; then
	# Install 'dialog' so we can ask the user questions. The original motivation for
	# this was being able to ask the user for input even if stdin has been redirected,
	# e.g. if we piped a bootstrapping install script to bash to get started. In that
	# case, the nifty '[ -t 0 ]' test won't work. But with Vagrant we must suppress so we
	# use a shell flag instead. Really suppress any output from installing dialog.
	#
	# Also install dependencies needed to validate the email address.
	if [ ! -f /usr/bin/dialog ] || [ ! -f /usr/bin/python3 ] || [ ! -f /usr/bin/pip3 ]; then
		echo "Installing packages needed for setup..."
		apt-get -q -q update
		apt_get_quiet install dialog python3 python3-pip  || exit 1
	fi

	# Installing email_validator is repeated in setup/management.sh, but in setup/management.sh
	# we install it inside a virtualenv. In this script, we don't have the virtualenv yet
	# so we install the python package globally.
	hide_output pip3 install "email_validator>=1.0.0" || exit 1

	message_box "Mail-in-a-Box Installation" \
		"Hello and thanks for deploying a Mail-in-a-Box!
		\n\nI'm going to ask you a few questions.
		\n\nTo change your answers later, just run 'sudo mailinabox' from the command line.
		\n\nNOTE: You should only install this on a brand new Ubuntu installation 100% dedicated to Mail-in-a-Box. Mail-in-a-Box will, for example, remove apache2."
fi

# The box needs a name.
if [ -z "${PRIMARY_HOSTNAME:-}" ]; then
	if [ -z "${DEFAULT_PRIMARY_HOSTNAME:-}" ]; then
		# We recommend to use box.example.com as this hosts name. The
		# domain the user possibly wants to use is example.com then.
		# We strip the string "box." from the hostname to get the mail
		# domain. If the hostname differs, nothing happens here.
		DEFAULT_DOMAIN_GUESS=$(get_default_hostname | sed -e 's/^box\.//')

		# This is the first run. Ask the user for his email address so we can
		# provide the best default for the box's hostname.
		input_box "Your Email Address" \
"What email address are you setting this box up to manage?
\n\nThe part after the @-sign must be a domain name or subdomain
that you control. You can add other email addresses to this
box later (including email addresses on other domain names
or subdomains you control).
\n\nWe've guessed an email address. Backspace it and type in what
you really want.
\n\nEmail Address:" \
			"me@$DEFAULT_DOMAIN_GUESS" \
			EMAIL_ADDR

		if [ -z "$EMAIL_ADDR" ]; then
			# user hit ESC/cancel
			exit
		fi
		while ! python3 management/mailconfig.py validate-email "$EMAIL_ADDR"
		do
			input_box "Your Email Address" \
				"That's not a valid email address.\n\nWhat email address are you setting this box up to manage?" \
				"$EMAIL_ADDR" \
				EMAIL_ADDR
			if [ -z "$EMAIL_ADDR" ]; then
				# user hit ESC/cancel
				exit
			fi
		done

		# Take the part after the @-sign as the user's domain name, and add
		# 'box.' to the beginning to create a default hostname for this machine.
		DEFAULT_PRIMARY_HOSTNAME=box.$(echo "$EMAIL_ADDR" | sed 's/.*@//')
	fi

	input_box "Hostname" \
"This box needs a name, called a 'hostname'. The name will form a part of the box's web address.
\n\nWe recommend that the name be a subdomain of the domain in your email
address, so we're suggesting $DEFAULT_PRIMARY_HOSTNAME.
\n\nYou can change it, but we recommend you don't.
\n\nHostname:" \
		"$DEFAULT_PRIMARY_HOSTNAME" \
		PRIMARY_HOSTNAME

	if [ -z "$PRIMARY_HOSTNAME" ]; then
		# user hit ESC/cancel
		exit
	fi
fi

# Database deployment mode: local MariaDB or remote MariaDB.
if [ -z "${MARIADB_MODE:-}" ]; then
	MARIADB_MODE=$([[ -z "${DEFAULT_MARIADB_MODE:-}" ]] && echo "local" || echo "$DEFAULT_MARIADB_MODE")
fi

if [ -z "${NONINTERACTIVE:-}" ]; then
	input_box "MariaDB Deployment" \
"Mail-in-a-Box can either install and manage a local MariaDB instance,
or connect to an existing remote MariaDB server.

Enter one of:
- local
- remote

Database mode:" \
		"$MARIADB_MODE" \
		MARIADB_MODE

	if [ -z "$MARIADB_MODE" ]; then
		# user hit ESC/cancel
		exit
	fi
fi

MARIADB_MODE=$(echo "$MARIADB_MODE" | tr '[:upper:]' '[:lower:]')

if [[ "$MARIADB_MODE" != "local" && "$MARIADB_MODE" != "remote" ]]; then
	echo
	echo "Database mode must be either 'local' or 'remote'."
	exit 1
fi

if [ "$MARIADB_MODE" = "local" ]; then
	MAILINABOX_DB_HOST=127.0.0.1
	MAILINABOX_DB_PORT=3306
	MAILINABOX_DB_NAME=mailinabox
	MAILINABOX_DB_USER=mailinabox

	ROUNDCUBE_DB_HOST=127.0.0.1
	ROUNDCUBE_DB_PORT=3306
	ROUNDCUBE_DB_NAME=roundcube
	ROUNDCUBE_DB_USER=roundcube

	NEXTCLOUD_DB_HOST=127.0.0.1
	NEXTCLOUD_DB_PORT=3306
	NEXTCLOUD_DB_NAME=nextcloud
	NEXTCLOUD_DB_USER=nextcloud

	unset MAILINABOX_DB_PASSWORD ROUNDCUBE_DB_PASSWORD NEXTCLOUD_DB_PASSWORD
else
	# Seed defaults for remote mode from previous config if available.
	if [ -z "${MAILINABOX_DB_HOST:-}" ]; then MAILINABOX_DB_HOST="${DEFAULT_MAILINABOX_DB_HOST:-}"; fi
	if [ -z "${MAILINABOX_DB_PORT:-}" ]; then MAILINABOX_DB_PORT="${DEFAULT_MAILINABOX_DB_PORT:-3306}"; fi
	if [ -z "${MAILINABOX_DB_NAME:-}" ]; then MAILINABOX_DB_NAME="${DEFAULT_MAILINABOX_DB_NAME:-mailinabox}"; fi
	if [ -z "${MAILINABOX_DB_USER:-}" ]; then MAILINABOX_DB_USER="${DEFAULT_MAILINABOX_DB_USER:-mailinabox}"; fi

	if [ -z "${ROUNDCUBE_DB_HOST:-}" ]; then ROUNDCUBE_DB_HOST="${DEFAULT_ROUNDCUBE_DB_HOST:-$MAILINABOX_DB_HOST}"; fi
	if [ -z "${ROUNDCUBE_DB_PORT:-}" ]; then ROUNDCUBE_DB_PORT="${DEFAULT_ROUNDCUBE_DB_PORT:-$MAILINABOX_DB_PORT}"; fi
	if [ -z "${ROUNDCUBE_DB_NAME:-}" ]; then ROUNDCUBE_DB_NAME="${DEFAULT_ROUNDCUBE_DB_NAME:-roundcube}"; fi
	if [ -z "${ROUNDCUBE_DB_USER:-}" ]; then ROUNDCUBE_DB_USER="${DEFAULT_ROUNDCUBE_DB_USER:-roundcube}"; fi

	if [ -z "${NEXTCLOUD_DB_HOST:-}" ]; then NEXTCLOUD_DB_HOST="${DEFAULT_NEXTCLOUD_DB_HOST:-$MAILINABOX_DB_HOST}"; fi
	if [ -z "${NEXTCLOUD_DB_PORT:-}" ]; then NEXTCLOUD_DB_PORT="${DEFAULT_NEXTCLOUD_DB_PORT:-$MAILINABOX_DB_PORT}"; fi
	if [ -z "${NEXTCLOUD_DB_NAME:-}" ]; then NEXTCLOUD_DB_NAME="${DEFAULT_NEXTCLOUD_DB_NAME:-nextcloud}"; fi
	if [ -z "${NEXTCLOUD_DB_USER:-}" ]; then NEXTCLOUD_DB_USER="${DEFAULT_NEXTCLOUD_DB_USER:-nextcloud}"; fi

	if [ -z "${NONINTERACTIVE:-}" ]; then
		input_box "Remote MariaDB Host" "Enter the hostname or IP address of your remote MariaDB server." "$MAILINABOX_DB_HOST" MAILINABOX_DB_HOST
		if [ -z "$MAILINABOX_DB_HOST" ]; then exit; fi

		input_box "Remote MariaDB Port" "Enter the MariaDB port for your remote server." "$MAILINABOX_DB_PORT" MAILINABOX_DB_PORT
		if [ -z "$MAILINABOX_DB_PORT" ]; then exit; fi

		input_box "Mail-in-a-Box DB Name" "Enter the database name for Mail-in-a-Box core data." "$MAILINABOX_DB_NAME" MAILINABOX_DB_NAME
		if [ -z "$MAILINABOX_DB_NAME" ]; then exit; fi

		input_box "Mail-in-a-Box DB User" "Enter the database user for Mail-in-a-Box core data." "$MAILINABOX_DB_USER" MAILINABOX_DB_USER
		if [ -z "$MAILINABOX_DB_USER" ]; then exit; fi

		input_box "Mail-in-a-Box DB Password" "Enter the database password for Mail-in-a-Box core data." "${MAILINABOX_DB_PASSWORD:-}" MAILINABOX_DB_PASSWORD
		if [ -z "$MAILINABOX_DB_PASSWORD" ]; then exit; fi

		input_box "Roundcube DB Host" "Enter the remote MariaDB host for Roundcube." "$ROUNDCUBE_DB_HOST" ROUNDCUBE_DB_HOST
		if [ -z "$ROUNDCUBE_DB_HOST" ]; then exit; fi

		input_box "Roundcube DB Port" "Enter the remote MariaDB port for Roundcube." "$ROUNDCUBE_DB_PORT" ROUNDCUBE_DB_PORT
		if [ -z "$ROUNDCUBE_DB_PORT" ]; then exit; fi

		input_box "Roundcube DB Name" "Enter the database name for Roundcube." "$ROUNDCUBE_DB_NAME" ROUNDCUBE_DB_NAME
		if [ -z "$ROUNDCUBE_DB_NAME" ]; then exit; fi

		input_box "Roundcube DB User" "Enter the database user for Roundcube." "$ROUNDCUBE_DB_USER" ROUNDCUBE_DB_USER
		if [ -z "$ROUNDCUBE_DB_USER" ]; then exit; fi

		input_box "Roundcube DB Password" "Enter the database password for Roundcube." "${ROUNDCUBE_DB_PASSWORD:-}" ROUNDCUBE_DB_PASSWORD
		if [ -z "$ROUNDCUBE_DB_PASSWORD" ]; then exit; fi

		input_box "Nextcloud DB Host" "Enter the remote MariaDB host for Nextcloud." "$NEXTCLOUD_DB_HOST" NEXTCLOUD_DB_HOST
		if [ -z "$NEXTCLOUD_DB_HOST" ]; then exit; fi

		input_box "Nextcloud DB Port" "Enter the remote MariaDB port for Nextcloud." "$NEXTCLOUD_DB_PORT" NEXTCLOUD_DB_PORT
		if [ -z "$NEXTCLOUD_DB_PORT" ]; then exit; fi

		input_box "Nextcloud DB Name" "Enter the database name for Nextcloud." "$NEXTCLOUD_DB_NAME" NEXTCLOUD_DB_NAME
		if [ -z "$NEXTCLOUD_DB_NAME" ]; then exit; fi

		input_box "Nextcloud DB User" "Enter the database user for Nextcloud." "$NEXTCLOUD_DB_USER" NEXTCLOUD_DB_USER
		if [ -z "$NEXTCLOUD_DB_USER" ]; then exit; fi

		input_box "Nextcloud DB Password" "Enter the database password for Nextcloud." "${NEXTCLOUD_DB_PASSWORD:-}" NEXTCLOUD_DB_PASSWORD
		if [ -z "$NEXTCLOUD_DB_PASSWORD" ]; then exit; fi
	fi

	for required in \
		MAILINABOX_DB_HOST MAILINABOX_DB_PORT MAILINABOX_DB_NAME MAILINABOX_DB_USER MAILINABOX_DB_PASSWORD \
		ROUNDCUBE_DB_HOST ROUNDCUBE_DB_PORT ROUNDCUBE_DB_NAME ROUNDCUBE_DB_USER ROUNDCUBE_DB_PASSWORD \
		NEXTCLOUD_DB_HOST NEXTCLOUD_DB_PORT NEXTCLOUD_DB_NAME NEXTCLOUD_DB_USER NEXTCLOUD_DB_PASSWORD
	do
		if [ -z "${!required:-}" ]; then
			echo
			echo "Remote MariaDB mode requires $required."
			exit 1
		fi
	done
fi

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "${PUBLIC_IP:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 4)

	# On the first run, if we got an answer from the Internet then don't
	# ask the user.
	if [[ -z "${DEFAULT_PUBLIC_IP:-}" && -n "$GUESSED_IP" ]]; then
		PUBLIC_IP=$GUESSED_IP

	# Otherwise on the first run at least provide a default.
	elif [[ -z "${DEFAULT_PUBLIC_IP:-}" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 4)

	# On later runs, if the previous value matches the guessed value then
	# don't ask the user either.
	elif [ "${DEFAULT_PUBLIC_IP:-}" == "$GUESSED_IP" ]; then
		PUBLIC_IP=$GUESSED_IP
	fi

	if [ -z "${PUBLIC_IP:-}" ]; then
		input_box "Public IP Address" \
			"Enter the public IP address of this machine, as given to you by your ISP.
			\n\nPublic IP address:" \
			"${DEFAULT_PUBLIC_IP:-}" \
			PUBLIC_IP

		if [ -z "$PUBLIC_IP" ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "${PUBLIC_IPV6:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 6)
	MATCHED=0
	if [[ -z "${DEFAULT_PUBLIC_IPV6:-}" && -n "$GUESSED_IP" ]]; then
		PUBLIC_IPV6=$GUESSED_IP
	elif [[ "${DEFAULT_PUBLIC_IPV6:-}" == "$GUESSED_IP" ]]; then
		# No IPv6 entered and machine seems to have none, or what
		# the user entered matches what the Internet tells us.
		PUBLIC_IPV6=$GUESSED_IP
		MATCHED=1
	elif [[ -z "${DEFAULT_PUBLIC_IPV6:-}" ]]; then
		DEFAULT_PUBLIC_IP=$(get_default_privateip 6)
	fi

	if [[ -z "${PUBLIC_IPV6:-}" && $MATCHED == 0 ]]; then
		input_box "IPv6 Address (Optional)" \
			"Enter the public IPv6 address of this machine, as given to you by your ISP.
			\n\nLeave blank if the machine does not have an IPv6 address.
			\n\nPublic IPv6 address:" \
			"${DEFAULT_PUBLIC_IPV6:-}" \
			PUBLIC_IPV6

		if [ ! -n "$PUBLIC_IPV6_EXITCODE" ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi

# Get the IP addresses of the local network interface(s) that are connected
# to the Internet. We need these when we want to have services bind only to
# the public network interfaces (not loopback, not tunnel interfaces).
if [ -z "${PRIVATE_IP:-}" ]; then
	PRIVATE_IP=$(get_default_privateip 4)
fi
if [ -z "${PRIVATE_IPV6:-}" ]; then
	PRIVATE_IPV6=$(get_default_privateip 6)
fi
if [[ -z "$PRIVATE_IP" && -z "$PRIVATE_IPV6" ]]; then
	echo
	echo "I could not determine the IP or IPv6 address of the network interface"
	echo "for connecting to the Internet. Setup must stop."
	echo
	hostname -I
	route
	echo
	exit
fi

# Automatic configuration, e.g. as used in our Vagrant configuration.
if [ "$PUBLIC_IP" = "auto" ]; then
	# Use a public API to get our public IP address, or fall back to local network configuration.
	PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi
if [ "$PUBLIC_IPV6" = "auto" ]; then
	# Use a public API to get our public IPv6 address, or fall back to local network configuration.
	PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi
if [ "$PRIMARY_HOSTNAME" = "auto" ]; then
	PRIMARY_HOSTNAME=$(get_default_hostname)
fi

# Set STORAGE_USER and STORAGE_ROOT to default values (user-data and /home/user-data), unless
# we've already got those values from a previous run.
if [ -z "${STORAGE_USER:-}" ]; then
	STORAGE_USER=$([[ -z "${DEFAULT_STORAGE_USER:-}" ]] && echo "user-data" || echo "$DEFAULT_STORAGE_USER")
fi
if [ -z "${STORAGE_ROOT:-}" ]; then
	STORAGE_ROOT=$([[ -z "${DEFAULT_STORAGE_ROOT:-}" ]] && echo "/home/$STORAGE_USER" || echo "$DEFAULT_STORAGE_ROOT")
fi

# Show the configuration, since the user may have not entered it manually.
echo
echo "Primary Hostname: $PRIMARY_HOSTNAME"
echo "Public IP Address: $PUBLIC_IP"
if [ -n "$PUBLIC_IPV6" ]; then
	echo "Public IPv6 Address: $PUBLIC_IPV6"
fi
if [ "$PRIVATE_IP" != "$PUBLIC_IP" ]; then
	echo "Private IP Address: $PRIVATE_IP"
fi
if [ "$PRIVATE_IPV6" != "$PUBLIC_IPV6" ]; then
	echo "Private IPv6 Address: $PRIVATE_IPV6"
fi
if [ -f /usr/bin/git ] && [ -d .git ]; then
	echo "Mail-in-a-Box Version: $(git describe --always)"
fi
echo "MariaDB Mode: $MARIADB_MODE"
if [ "$MARIADB_MODE" = "remote" ]; then
	echo "Remote MariaDB (core): $MAILINABOX_DB_HOST:$MAILINABOX_DB_PORT/$MAILINABOX_DB_NAME"
fi
echo
