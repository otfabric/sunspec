package sunspec

import (
	"context"

	"github.com/otfabric/modbus"
)

// Detect checks whether a device is SunSpec-enabled.
// Returns ErrNotSunSpec if the device does not have a SunSpec marker.
func Detect(ctx context.Context, client *modbus.ModbusClient, opts *DiscoverOptions) (*modbus.SunSpecDetectionResult, error) {
	result, err := client.DetectSunSpec(ctx, opts.toSunSpecOptions())
	if err != nil {
		return nil, err
	}
	if !result.Detected {
		return result, ErrNotSunSpec
	}
	return result, nil
}
