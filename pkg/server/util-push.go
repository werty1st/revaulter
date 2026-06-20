package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"

	webpush "github.com/SherClockHolmes/webpush-go"

	"github.com/italypaleale/revaulter/pkg/config"
	"github.com/italypaleale/revaulter/pkg/db"
	"github.com/italypaleale/revaulter/pkg/utils/logging"
)

type pushPayload struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// sendPushNotifications delivers a Web Push notification to all subscribed clients.
// It runs in its own goroutine and does not block the calling request handler.
func (s *Server) sendPushNotifications(ctx context.Context, item *db.V2RequestListItem) {
	cfg := config.Get()
	if cfg.VAPIDPublicKey == "" || cfg.VAPIDPrivateKey == "" {
		return
	}

	go func() {
		log := logging.LogFromContext(ctx)

		subs, err := s.db.PushSubscriptionStore().ListPushSubscriptions(ctx)
		if err != nil {
			log.Error("push: failed to list subscriptions", slog.Any("err", err))
			return
		}
		if len(subs) == 0 {
			return
		}

		subject := cfg.VAPIDSubject
		if subject == "" {
			subject = "mailto:admin@localhost"
		}

		payload, err := json.Marshal(pushPayload{
			Title: "Revaulter",
			Body:  fmt.Sprintf("New %s request for key %s", item.Operation, item.KeyLabel),
		})
		if err != nil {
			log.Error("push: failed to marshal payload", slog.Any("err", err))
			return
		}

		for _, sub := range subs {
			resp, sendErr := webpush.SendNotification(payload, &webpush.Subscription{
				Endpoint: sub.Endpoint,
				Keys: webpush.Keys{
					P256dh: sub.P256DH,
					Auth:   sub.Auth,
				},
			}, &webpush.Options{
				VAPIDPublicKey:  cfg.VAPIDPublicKey,
				VAPIDPrivateKey: cfg.VAPIDPrivateKey,
				Subscriber:      subject,
				TTL:             300,
			})
			if sendErr != nil {
				log.Error("push: failed to send notification", slog.String("endpoint", sub.Endpoint), slog.Any("err", sendErr))
				continue
			}
			resp.Body.Close()

			// 410 Gone means the subscription is no longer valid; remove it
			if resp.StatusCode == http.StatusGone {
				delErr := s.db.PushSubscriptionStore().DeletePushSubscription(ctx, sub.Endpoint)
				if delErr != nil {
					log.Error("push: failed to delete stale subscription", slog.String("endpoint", sub.Endpoint), slog.Any("err", delErr))
				}
			}
		}
	}()
}
