# Release v0.1.0

**Date:** 2026-03-12

## Summary

Initial release of the `otfabric/sunspec` Go library and `sunspecctl` CLI tool for reading SunSpec devices over Modbus.

## Highlights

- **Auto-discovery** — detect SunSpec presence and enumerate all models on a device
- **Full decoding** — all standard SunSpec point types: int, uint, float, string, enum, bitfield, IP addresses, accumulators, scale factors
- **Scale factor resolution** — automatic SF resolution for both point-reference and literal scale factors
- **Repeating blocks** — full support for meters, MPPTs, and other models with repeating groups
- **Registry** — compiled metadata for 112 SunSpec models, generated from upstream JSON definitions
- **Batch reading** — transparent splitting of reads >125 registers
- **`sunspecctl` CLI** — `detect`, `models`, `read`, `read-model`, `read-point` commands with `--json` and `--raw` output

## What's Included

### Library (`github.com/otfabric/sunspec`)
- `Detect()` / `Discover()` / `Open()` — device discovery
- `Device.ReadAll()` / `ReadModel()` / `ReadModelByID()` / `ReadPoint()` — read API
- `DecodeModel()` — standalone model decoder
- `registry` package — model metadata lookups (`ByID`, `Known`, `All`, `Count`)

### CLI (`cmd/sunspecctl`)
- Cross-platform binaries: linux/amd64, linux/arm64, linux/armv7, darwin/amd64, darwin/arm64
- Shell completion: bash, zsh, fish, powershell

### Testing
- 21 unit tests covering all point type decoders and scale factor resolution
- 7 integration tests with in-process Modbus server fixtures
- 5 registry tests

## Dependencies

- Go 1.21+
- [otfabric/modbus](https://github.com/otfabric/modbus) v0.2.0+
- [spf13/cobra](https://github.com/spf13/cobra) v1.10.2 (CLI only)

---
