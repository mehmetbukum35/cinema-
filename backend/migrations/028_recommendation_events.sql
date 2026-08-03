CREATE TABLE recommendation_events (
  event_id CHAR(36) NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  impression_id CHAR(36) NOT NULL,
  movie_id INT NOT NULL,
  is_tv TINYINT(1) NOT NULL DEFAULT 0,
  action VARCHAR(32) NOT NULL,
  surface VARCHAR(32) NOT NULL,
  source VARCHAR(32) NOT NULL,
  model_version VARCHAR(64) NOT NULL,
  score_components TEXT NULL,
  metadata TEXT NULL,
  created_at BIGINT NOT NULL,
  received_at BIGINT NOT NULL,
  PRIMARY KEY (event_id),
  KEY idx_reco_events_user_created (user_id, created_at),
  KEY idx_reco_events_model_action (model_version, action),
  KEY idx_reco_events_impression (impression_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
