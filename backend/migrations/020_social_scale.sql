-- Social feed and public-profile access paths for larger datasets.
CREATE INDEX idx_friends_user_status
  ON friends (user_id, status, friend_id);

CREATE INDEX idx_ratings_social_feed
  ON ratings (user_id, deleted, is_private, updated_at);

CREATE INDEX idx_users_public_profiles
  ON users (is_public, id);
