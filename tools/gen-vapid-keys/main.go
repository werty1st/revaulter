package main

import (
	"fmt"
	"log"

	webpush "github.com/SherClockHolmes/webpush-go"
)

func main() {
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		log.Fatalf("failed to generate VAPID keys: %v", err)
	}
	fmt.Println("VAPID keys generated. Add these to your environment or config.yaml:")
	fmt.Println()
	fmt.Printf("VAPIDPUBLICKEY=%s\n", publicKey)
	fmt.Printf("VAPIDPRIVATEKEY=%s\n", privateKey)
	fmt.Printf("VAPIDSUBJECT=mailto:admin@example.com\n")
}
