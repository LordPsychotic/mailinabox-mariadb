#!/usr/local/lib/mailinabox/env/bin/python

import hashlib
import json
import os

import pymysql

DB_CONFIG_FILE = "/etc/mailinabox-db.conf"

IntegrityError = pymysql.err.IntegrityError


class DatabaseError(Exception):
	pass


class DatabaseConnection:
	def __init__(self, connection):
		self._connection = connection

	def cursor(self):
		return DatabaseCursor(self._connection.cursor())

	def commit(self):
		self._connection.commit()

	def rollback(self):
		self._connection.rollback()

	def close(self):
		self._connection.close()


class DatabaseCursor:
	def __init__(self, cursor):
		self._cursor = cursor

	def execute(self, query, params=None):
		query = _rewrite_placeholders(query)
		if params is None:
			return self._cursor.execute(query)
		return self._cursor.execute(query, params)

	def executemany(self, query, params):
		query = _rewrite_placeholders(query)
		return self._cursor.executemany(query, params)

	def fetchone(self):
		return self._cursor.fetchone()

	def fetchall(self):
		return self._cursor.fetchall()

	@property
	def rowcount(self):
		return self._cursor.rowcount

	@property
	def lastrowid(self):
		return self._cursor.lastrowid


# SQLite-style placeholder compatibility in existing code paths.
def _rewrite_placeholders(query):
	return query.replace("?", "%s")


def _parse_env_file(fn):
	config = {}
	with open(fn, encoding="utf-8") as f:
		for line in f:
			line = line.strip()
			if line == "" or line.startswith("#"):
				continue
			if "=" not in line:
				continue
			k, v = line.split("=", 1)
			config[k.strip()] = v.strip()
	return config


def load_db_config():
	if not os.path.exists(DB_CONFIG_FILE):
		msg = f"Database config file not found: {DB_CONFIG_FILE}"
		raise DatabaseError(msg)

	cfg = _parse_env_file(DB_CONFIG_FILE)
	required = (
		"MAILINABOX_DB_HOST",
		"MAILINABOX_DB_PORT",
		"MAILINABOX_DB_NAME",
		"MAILINABOX_DB_USER",
		"MAILINABOX_DB_PASSWORD",
	)
	for key in required:
		if key not in cfg or cfg[key] == "":
			msg = f"Missing required database setting: {key}"
			raise DatabaseError(msg)
	return cfg


def connect():
	cfg = load_db_config()
	connection = pymysql.connect(
		host=cfg["MAILINABOX_DB_HOST"],
		port=int(cfg["MAILINABOX_DB_PORT"]),
		user=cfg["MAILINABOX_DB_USER"],
		password=cfg["MAILINABOX_DB_PASSWORD"],
		database=cfg["MAILINABOX_DB_NAME"],
		charset="utf8mb4",
		autocommit=False,
	)
	return DatabaseConnection(connection)


def _query_one(query, params=()):
	conn = connect()
	try:
		cursor = conn.cursor()
		cursor.execute(query, params)
		return cursor.fetchone()
	finally:
		conn.close()


def _query_all(query, params=()):
	conn = connect()
	try:
		cursor = conn.cursor()
		cursor.execute(query, params)
		return cursor.fetchall()
	finally:
		conn.close()


def _execute(query, params=()):
	conn = connect()
	try:
		cursor = conn.cursor()
		cursor.execute(query, params)
		conn.commit()
		return cursor.rowcount
	except:
		conn.rollback()
		raise
	finally:
		conn.close()


def get_user(email):
	row = _query_one(
		"SELECT id, email, password, privileges, quota FROM users WHERE email=?",
		(email,),
	)
	if not row:
		return None
	return {
		"id": row[0],
		"email": row[1],
		"password": row[2],
		"privileges": row[3],
		"quota": row[4],
	}


def create_user(email, password_hash, privileges="", quota="0"):
	conn = connect()
	try:
		cursor = conn.cursor()
		localpart, domain = email.split("@", 1)
		domain_id = ensure_domain(domain, cursor=cursor)
		cursor.execute(
			"INSERT INTO users (domain_id, localpart, email, password, privileges, quota) VALUES (?, ?, ?, ?, ?, ?)",
			(domain_id, localpart, email, password_hash, privileges, quota),
		)
		conn.commit()
		return cursor.rowcount
	except:
		conn.rollback()
		raise
	finally:
		conn.close()


def list_domains():
	rows = _query_all("SELECT domain FROM domains ORDER BY domain")
	return [row[0] for row in rows]


def ensure_domain(domain, cursor=None):
	# This helper supports caller-managed transactions via cursor.
	if cursor is not None:
		cursor.execute("INSERT IGNORE INTO domains (domain) VALUES (?)", (domain,))
		cursor.execute("SELECT id FROM domains WHERE domain=?", (domain,))
		row = cursor.fetchone()
		if not row:
			raise DatabaseError(f"Failed to resolve domain id for {domain}")
		return row[0]

	_execute("INSERT IGNORE INTO domains (domain) VALUES (?)", (domain,))
	row = _query_one("SELECT id FROM domains WHERE domain=?", (domain,))
	if not row:
		raise DatabaseError(f"Failed to resolve domain id for {domain}")
	return row[0]


def rebuild_domains(connection):
	cursor = connection.cursor()
	cursor.execute(
		"""
		INSERT IGNORE INTO domains (domain)
		SELECT DISTINCT domain
		FROM (
			SELECT SUBSTRING_INDEX(email, '@', -1) AS domain FROM users
			UNION
			SELECT SUBSTRING_INDEX(source, '@', -1) AS domain FROM aliases WHERE source LIKE '%@%'
			UNION
			SELECT SUBSTRING_INDEX(source, '@', -1) AS domain FROM auto_aliases WHERE source LIKE '%@%'
		) AS all_domains
		WHERE domain <> ''
		"""
	)
	cursor.execute(
		"""
		DELETE d
		FROM domains d
		LEFT JOIN users u ON u.domain_id = d.id
		LEFT JOIN aliases a ON a.domain_id = d.id
		LEFT JOIN auto_aliases aa ON aa.domain_id = d.id
		WHERE u.id IS NULL AND a.id IS NULL AND aa.id IS NULL
		"""
	)


def get_setting(key, default=None):
	row = _query_one("SELECT value FROM settings WHERE k=?", (key,))
	if not row:
		return default
	try:
		return json.loads(row[0])
	except (TypeError, json.JSONDecodeError):
		return default


def set_setting(key, value):
	value_json = json.dumps(value)
	_execute(
		"""
		INSERT INTO settings (k, value)
		VALUES (?, ?)
		ON DUPLICATE KEY UPDATE value=VALUES(value), updated_at=CURRENT_TIMESTAMP
		""",
		(key, value_json),
	)


def delete_setting(key):
	_execute("DELETE FROM settings WHERE k=?", (key,))


def list_dns_records(include_internal=True):
	if include_internal:
		rows = _query_all(
			"SELECT qname, rtype, value FROM dns_records ORDER BY sort_order, id"
		)
	else:
		rows = _query_all(
			"SELECT qname, rtype, value FROM dns_records WHERE qname <> '_secondary_nameserver' ORDER BY sort_order, id"
		)
	return [(row[0], row[1], row[2]) for row in rows]


def replace_dns_records(records):
	conn = connect()
	try:
		cursor = conn.cursor()
		cursor.execute("DELETE FROM dns_records")
		for idx, (qname, rtype, value) in enumerate(records):
			value_hash = hashlib.sha256(value.encode("utf-8")).hexdigest()
			cursor.execute(
				"INSERT INTO dns_records (qname, rtype, value, value_hash, sort_order) VALUES (?, ?, ?, ?, ?)",
				(qname, rtype, value, value_hash, idx),
			)
		conn.commit()
	except:
		conn.rollback()
		raise
	finally:
		conn.close()
