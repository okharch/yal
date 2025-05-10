package model

type Subscription struct {
	ID       int
	Name     string
	ViewName string
}

type FlightTarget struct {
	FlightID      int
	SourceAirport int
	DestAirport   int
}

type ConditionTemplate struct {
	ID         int
	TargetType string
	Threshold  int
	Name       string
}
