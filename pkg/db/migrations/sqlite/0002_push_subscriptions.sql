CREATE TABLE IF NOT EXISTS push_subscriptions (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL REFERENCES v2_users(id) ON DELETE CASCADE,
	endpoint TEXT NOT NULL UNIQUE,
	p256dh TEXT NOT NULL,
	auth TEXT NOT NULL,
	created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON push_subscriptions(user_id);
