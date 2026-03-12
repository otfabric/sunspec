package sunspec

import (
	"context"
	"fmt"

	"github.com/otfabric/modbus"
	"github.com/otfabric/sunspec/registry"
)

// Discover detects SunSpec and enumerates models, returning a Device ready for reading.
func Discover(ctx context.Context, client *modbus.ModbusClient, opts *DiscoverOptions) (*Device, error) {
	raw, err := client.DiscoverSunSpec(ctx, opts.toSunSpecOptions())
	if err != nil {
		return nil, err
	}
	if !raw.Detection.Detected {
		return nil, ErrNotSunSpec
	}

	var unitID uint8 = 1
	if opts != nil && opts.UnitID != 0 {
		unitID = opts.UnitID
	}

	result := &DiscoveryResult{
		BaseAddress: raw.Detection.BaseAddress,
		RegType:     raw.Detection.RegType,
		Raw:         raw,
	}

	for _, hdr := range raw.Models {
		if hdr.IsEndModel {
			continue
		}
		inst := ModelInstance{
			Header: hdr,
		}
		meta := registry.ByID(hdr.ID)
		if meta != nil {
			inst.Schema = meta
			inst.SchemaKnown = true
			inst.DecodingSupported = true
			inst.Name = meta.Label
			if inst.Name == "" {
				inst.Name = meta.Name
			}
		} else {
			inst.Name = fmt.Sprintf("unknown_%d", hdr.ID)
			result.Warnings = append(result.Warnings,
				fmt.Sprintf("model %d: no local schema definition", hdr.ID))
		}
		result.Models = append(result.Models, inst)
	}

	return NewDevice(client, unitID, result), nil
}

// Open is a convenience that discovers and returns a Device in one step.
func Open(ctx context.Context, client *modbus.ModbusClient, opts *DiscoverOptions) (*Device, error) {
	return Discover(ctx, client, opts)
}
