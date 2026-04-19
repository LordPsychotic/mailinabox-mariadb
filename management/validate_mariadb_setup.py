#!/usr/local/lib/mailinabox/env/bin/python

import os
import sys

import db

REQUIRED_TABLES = {
	"domains",
	"users",
	"aliases",
	"auto_aliases",
	"mfa",
	"dns_records",
	"settings",
}


def read_file(fn):
	with open(fn, encoding="utf-8") as f:
		return f.read()


def check_tables():
	conn = db.connect()
	try:
		c = conn.cursor()
		c.execute("SHOW TABLES")
		tables = {row[0] for row in c.fetchall()}
		missing = sorted(REQUIRED_TABLES - tables)
		if missing:
			return [f"Missing required tables: {', '.join(missing)}"]
		return []
	finally:
		conn.close()


def check_dovecot_config():
	errors = []
	fn = "/etc/dovecot/dovecot-sql.conf.ext"
	if not os.path.exists(fn):
		return [f"Missing {fn}"]
	content = read_file(fn)
	if "driver = mysql" not in content:
		errors.append("Dovecot SQL driver is not mysql")
	if "connect = host=" not in content:
		errors.append("Dovecot SQL connect string is missing")
	return errors


def check_postfix_config():
	errors = []
	main_cf = "/etc/postfix/main.cf"
	if not os.path.exists(main_cf):
		return [f"Missing {main_cf}"]
	main_content = read_file(main_cf)
	for needle in (
		"smtpd_sender_login_maps=mysql:/etc/postfix/sender-login-maps.cf",
		"virtual_mailbox_domains=mysql:/etc/postfix/virtual-mailbox-domains.cf",
		"virtual_mailbox_maps=mysql:/etc/postfix/virtual-mailbox-maps.cf",
		"virtual_alias_maps=mysql:/etc/postfix/virtual-alias-maps.cf",
	):
		if needle not in main_content:
			errors.append(f"Postfix main.cf missing: {needle}")

	for fn in (
		"/etc/postfix/sender-login-maps.cf",
		"/etc/postfix/virtual-mailbox-domains.cf",
		"/etc/postfix/virtual-mailbox-maps.cf",
		"/etc/postfix/virtual-alias-maps.cf",
	):
		if not os.path.exists(fn):
			errors.append(f"Missing {fn}")
			continue
		content = read_file(fn)
		for required in ("hosts =", "user =", "password =", "dbname =", "query ="):
			if required not in content:
				errors.append(f"{fn} missing '{required}'")
	return errors


def check_data_access_paths():
	errors = []
	if not isinstance(db.get_setting("system", default={}), dict):
		errors.append("settings table access failed")
	if not isinstance(db.list_dns_records(include_internal=True), list):
		errors.append("dns_records table access failed")
	return errors


def main():
	errors = []
	errors.extend(check_tables())
	errors.extend(check_dovecot_config())
	errors.extend(check_postfix_config())
	errors.extend(check_data_access_paths())

	if errors:
		for e in errors:
			print(f"ERROR: {e}")
		return 1

	print("OK: MariaDB schema and Mail-in-a-Box SQL integration checks passed.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
