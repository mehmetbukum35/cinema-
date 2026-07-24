CREATE TABLE IF NOT EXISTS sync_origins (
    user_id BIGINT UNSIGNED NOT NULL,
    table_name VARCHAR(32) NOT NULL,
    record_key VARCHAR(255) NOT NULL,
    device_id VARCHAR(128) NOT NULL,
    PRIMARY KEY (user_id, table_name, record_key),
    CONSTRAINT fk_sync_origins_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
