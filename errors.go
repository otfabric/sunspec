package sunspec

import (
	"errors"

	"github.com/otfabric/modbus"
)

var (
	// ErrNotSunSpec indicates the device does not expose a SunSpec marker.
	ErrNotSunSpec = errors.New("sunspec: device is not SunSpec-enabled")

	// ErrUnknownModel indicates a model ID has no local schema definition.
	ErrUnknownModel = errors.New("sunspec: unknown model ID")

	// ErrDecode indicates a point or model decoding failure.
	ErrDecode = errors.New("sunspec: decode error")

	// ErrPartialRead indicates some registers could not be read.
	ErrPartialRead = errors.New("sunspec: partial read")

	// ErrUnsupportedPointType indicates a point type is not handled by the decoder.
	ErrUnsupportedPointType = errors.New("sunspec: unsupported point type")

	// Re-export modbus chain errors for convenience.
	ErrModelChainInvalid       = modbus.ErrSunSpecModelChainInvalid
	ErrModelChainLimitExceeded = modbus.ErrSunSpecModelChainLimitExceeded
)
