-- Mail-in-a-Box primary application schema (MariaDB only)
-- Fresh-install schema: no legacy compatibility tables.

CREATE TABLE IF NOT EXISTS domains (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	domain VARCHAR(255) NOT NULL,
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (id),
	UNIQUE KEY uq_domains_domain (domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	domain_id BIGINT UNSIGNED NOT NULL,
	localpart VARCHAR(128) NOT NULL,
	email VARCHAR(255) NOT NULL,
	password VARCHAR(255) NOT NULL,
	privileges TEXT NOT NULL,
	quota VARCHAR(32) NOT NULL DEFAULT '0',
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (id),
	UNIQUE KEY uq_users_email (email),
	KEY idx_users_domain_id (domain_id),
	KEY idx_users_localpart (localpart),
	CONSTRAINT fk_users_domain FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS aliases (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	domain_id BIGINT UNSIGNED NOT NULL,
	source_localpart VARCHAR(128) NOT NULL,
	source VARCHAR(255) NOT NULL,
	destination TEXT NOT NULL,
	permitted_senders TEXT NULL,
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (id),
	UNIQUE KEY uq_aliases_source (source),
	KEY idx_aliases_domain_id (domain_id),
	KEY idx_aliases_source_localpart (source_localpart),
	CONSTRAINT fk_aliases_domain FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS auto_aliases (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	domain_id BIGINT UNSIGNED NOT NULL,
	source_localpart VARCHAR(128) NOT NULL,
	source VARCHAR(255) NOT NULL,
	destination TEXT NOT NULL,
	permitted_senders TEXT NULL,
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (id),
	UNIQUE KEY uq_auto_aliases_source (source),
	KEY idx_auto_aliases_domain_id (domain_id),
	KEY idx_auto_aliases_source_localpart (source_localpart),
	CONSTRAINT fk_auto_aliases_domain FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mfa (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	user_id BIGINT UNSIGNED NOT NULL,
	type VARCHAR(32) NOT NULL,
	secret VARCHAR(255) NOT NULL,
	mru_token VARCHAR(64) NULL,
	label VARCHAR(255) NULL,
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (id),
	KEY idx_mfa_user_id (user_id),
	CONSTRAINT fk_mfa_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dns_records (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	qname VARCHAR(255) NOT NULL,
	rtype VARCHAR(16) NOT NULL,
	value TEXT NOT NULL,
	value_hash CHAR(64) NOT NULL,
	sort_order INT NOT NULL DEFAULT 0,
	created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (id),
	UNIQUE KEY uq_dns_records_exact (qname, rtype, value_hash),
	KEY idx_dns_records_qname_rtype (qname, rtype),
	KEY idx_dns_records_sort (qname, sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS settings (
	k VARCHAR(191) NOT NULL,
	value LONGTEXT NOT NULL,
	updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (k)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
