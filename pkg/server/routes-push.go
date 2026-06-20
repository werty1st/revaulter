package server

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/italypaleale/revaulter/pkg/config"
	"github.com/italypaleale/revaulter/pkg/db"
)

type pushSubscribeRequest struct {
	Endpoint string `json:"endpoint" binding:"required"`
	P256DH   string `json:"p256dh" binding:"required"`
	Auth     string `json:"auth" binding:"required"`
}

type pushUnsubscribeRequest struct {
	Endpoint string `json:"endpoint" binding:"required"`
}

// RouteV2PushVAPIDKey is the handler for GET /v2/api/push/vapid-public-key
func (s *Server) RouteV2PushVAPIDKey(c *gin.Context) {
	cfg := config.Get()
	if cfg.VAPIDPublicKey == "" {
		c.Status(http.StatusNotFound)
		return
	}
	c.JSON(http.StatusOK, gin.H{"key": cfg.VAPIDPublicKey})
}

// RouteV2PushSubscribe is the handler for POST /v2/api/push/subscribe
func (s *Server) RouteV2PushSubscribe(c *gin.Context) {
	cfg := config.Get()
	if cfg.VAPIDPublicKey == "" {
		c.Status(http.StatusNotFound)
		return
	}

	userID := c.GetString(contextKeyUserID)

	var body pushSubscribeRequest
	err := c.ShouldBindJSON(&body)
	if err != nil {
		AbortWithErrorJSON(c, NewResponseErrorf(http.StatusBadRequest, "Invalid request body: %v", err))
		return
	}

	err = s.db.PushSubscriptionStore().UpsertPushSubscription(c.Request.Context(), db.PushSubscription{
		UserID:   userID,
		Endpoint: body.Endpoint,
		P256DH:   body.P256DH,
		Auth:     body.Auth,
	})
	if err != nil {
		AbortWithErrorJSON(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}

// RouteV2PushUnsubscribe is the handler for DELETE /v2/api/push/subscribe
func (s *Server) RouteV2PushUnsubscribe(c *gin.Context) {
	var body pushUnsubscribeRequest
	err := c.ShouldBindJSON(&body)
	if err != nil {
		AbortWithErrorJSON(c, NewResponseErrorf(http.StatusBadRequest, "Invalid request body: %v", err))
		return
	}

	err = s.db.PushSubscriptionStore().DeletePushSubscription(c.Request.Context(), body.Endpoint)
	if err != nil {
		AbortWithErrorJSON(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}
