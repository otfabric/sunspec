package sunspec

import (
	"github.com/otfabric/modbus"
	"github.com/otfabric/sunspec/registry"
)

// ModelInstance represents one discovered model instance enriched with schema metadata.
type ModelInstance struct {
	Header            modbus.SunSpecModelHeader
	Name              string
	Schema            *registry.ModelMeta
	SchemaKnown       bool
	DecodingSupported bool
}

// DiscoveryResult holds the enriched discovery output.
type DiscoveryResult struct {
	BaseAddress uint16
	RegType     modbus.RegType
	Models      []ModelInstance
	Warnings    []string
	Raw         *modbus.SunSpecDiscoveryResult
}

// Device holds a modbus client and discovery result, ready for reading.
type Device struct {
	Client    *modbus.ModbusClient
	UnitID    uint8
	RegType   modbus.RegType
	Discovery *DiscoveryResult
}

// NewDevice creates a Device from an existing client and discovery result.
func NewDevice(client *modbus.ModbusClient, unitID uint8, discovery *DiscoveryResult) *Device {
	return &Device{
		Client:    client,
		UnitID:    unitID,
		RegType:   discovery.RegType,
		Discovery: discovery,
	}
}

// ModelByID returns the first ModelInstance with the given model ID, or nil.
func (d *Device) ModelByID(id uint16) *ModelInstance {
	for i := range d.Discovery.Models {
		if d.Discovery.Models[i].Header.ID == id {
			return &d.Discovery.Models[i]
		}
	}
	return nil
}

// DiscoverOptions configures discovery behavior.
type DiscoverOptions struct {
	UnitID         uint8
	RegType        modbus.RegType
	BaseAddresses  []uint16
	MaxModels      int
	MaxAddressSpan uint16
}

func (o *DiscoverOptions) toSunSpecOptions() *modbus.SunSpecOptions {
	if o == nil {
		return nil
	}
	return &modbus.SunSpecOptions{
		UnitID:         o.UnitID,
		RegType:        o.RegType,
		BaseAddresses:  o.BaseAddresses,
		MaxModels:      o.MaxModels,
		MaxAddressSpan: o.MaxAddressSpan,
	}
}
