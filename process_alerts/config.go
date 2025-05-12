package process_alerts

import (
	"fmt"
)

var ShowDebug bool

func LogPushSubscription(UserSubId int, jsonPayload string) {
	fmt.Printf("PUSH user_sub %d\npayload=%s\n", UserSubId, jsonPayload) // ,
}
