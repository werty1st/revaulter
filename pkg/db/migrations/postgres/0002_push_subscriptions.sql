CREATE TABLE IF NOT EXISTS push_subscriptions (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id text NOT NULL REFERENCES v2_users(id) ON DELETE CASCADE,
	endpoint text NOT NULL UNIQUE,
	p256dh text NOT NULL,
	auth text NOT NULL,
	created_at bigint NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON push_subscriptions(user_id);
