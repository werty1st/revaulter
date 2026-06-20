package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/italypaleale/go-sql-utils/adapter"
)

// PushSubscription represents a stored Web Push subscription
type PushSubscription struct {
	ID        string
	UserID    string
	Endpoint  string
	P256DH    string
	Auth      string
	CreatedAt time.Time
}

// PushSubscriptionStore provides operations on push_subscriptions
type PushSubscriptionStore struct {
	db adapter.Querier
}

// NewPushSubscriptionStore creates a new PushSubscriptionStore
func NewPushSubscriptionStore(db adapter.Querier) (*PushSubscriptionStore, error) {
	if db == nil {
		return nil, errors.New("db is nil")
	}
	return &PushSubscriptionStore{db: db}, nil
}

// UpsertPushSubscription inserts or updates a push subscription by endpoint
func (s *PushSubscriptionStore) UpsertPushSubscription(ctx context.Context, sub PushSubscription) error {
	id, err := uuid.NewRandom()
	if err != nil {
		return err
	}
	now := time.Now().Unix()
	_, err = s.db.Exec(ctx,
		`INSERT INTO push_subscriptions (id, user_id, endpoint, p256dh, auth, created_at)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (endpoint) DO UPDATE
			SET user_id = excluded.user_id,
				p256dh = excluded.p256dh,
				auth = excluded.auth`,
		id.String(), sub.UserID, sub.Endpoint, sub.P256DH, sub.Auth, now,
	)
	return err
}

// DeletePushSubscription removes a subscription by endpoint
func (s *PushSubscriptionStore) DeletePushSubscription(ctx context.Context, endpoint string) error {
	_, err := s.db.Exec(ctx,
		`DELETE FROM push_subscriptions WHERE endpoint = $1`,
		endpoint,
	)
	return err
}

// ListPushSubscriptions returns all stored push subscriptions
func (s *PushSubscriptionStore) ListPushSubscriptions(ctx context.Context) ([]PushSubscription, error) {
	rows, err := s.db.Query(ctx,
		`SELECT id, user_id, endpoint, p256dh, auth, created_at FROM push_subscriptions`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subs []PushSubscription
	for rows.Next() {
		var sub PushSubscription
		var createdAt int64
		err = rows.Scan(&sub.ID, &sub.UserID, &sub.Endpoint, &sub.P256DH, &sub.Auth, &createdAt)
		if err != nil {
			return nil, err
		}
		sub.CreatedAt = time.Unix(createdAt, 0)
		subs = append(subs, sub)
	}
	return subs, rows.Err()
}
