package process_alerts

import (
	"fmt"
)

var ShowDebug bool

func LogPayload(payloadParams interface{}, jsonPayload string) {
	fmt.Printf("PUSH to frontend %+v\n payload=%s\n", payloadParams, jsonPayload) // ,
}
