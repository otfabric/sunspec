# Development Plan

## Context

This plan implements the library described in [REQUIREMENTS.md](REQUIREMENTS.md).

### What `otfabric/modbus` v0.2.0 already provides

The modbus library now includes transport-level SunSpec discovery — **read-only, schema-free** helpers that handle the wire protocol:

| Modbus API | What it does |
|---|---|
| `DetectSunSpec(ctx, opts)` | Probes candidate base addresses for the `SunS` marker. Returns `SunSpecDetectionResult` with detected flag, base address, probe attempts. "Not SunSpec" is not an error. |
| `ReadSunSpecModelHeaders(ctx, opts, base)` | Walks the model chain from `base+2`, returning `[]SunSpecModelHeader` (ID, length, start/end address). Stops at end marker `0xFFFF/0` or guards. |
| `DiscoverSunSpec(ctx, opts)` | Convenience: detection + model-header enumeration in one call. Returns `SunSpecDiscoveryResult`. |
| `SunSpecOptions` | Configures `UnitID`, `RegType`, `BaseAddresses`, `MaxModels`, `MaxAddressSpan`. |
| `ReadIPAddr` / `ReadIPv6Addr` / `ReadEUI48` | Typed reads for IP and MAC addresses (wire order, no `SetEncoding`). |
| `ReadAsciiFixed` | ASCII read preserving trailing spaces. |
| `ReadUint16Pair` | Exactly two registers as `[2]uint16`. |
| `ReadUint8s` | Raw bytes in wire order. |
| Error sentinels | `ErrSunSpecModelChainInvalid`, `ErrSunSpecModelChainLimitExceeded`. |

Default probe addresses: `0, 1, 39999, 40000, 40001, 49999, 50000, 50001`.

**Not in modbus** (responsibility of this library): point decoding, scale factors, model names, JSON schema, repeating blocks, high-level read API, CLI.

### What this library builds on top

This library adds the **semantic layer**: schema registry generated from the SunSpec JSON definitions, point decoding, scale factor resolution, an ergonomic Device read API, and a thin CLI proof tool. It delegates all wire-level operations to `otfabric/modbus`.

---

## Phase 1 — Project Bootstrap & Code Generation

**Goal**: Establish project structure, parse JSON model definitions, generate a Go schema registry.

### Steps

1. Initialize `go.mod` (`github.com/otfabric/sunspec`), require `github.com/otfabric/modbus` v0.2.0.
2. Create directory structure:
   ```
   go.mod
   Makefile
   internal/gen/main.go        # code generator (reads models/, writes registry/)
   internal/gen/emit.go        # Go source emitter
   internal/schema/types.go    # JSON model ingestion structs
   internal/schema/parse.go    # JSON file loading
   registry/registry.go        # metadata types + lookup helpers
   registry/models_gen.go      # generated model data (output of gen)
   ```
3. Define JSON ingestion types in `internal/schema/` — Go structs mirroring `models/schema.json`:
   - `ModelDef` (id, group, label, desc)
   - `GroupDef` (name, type, count, points, groups)
   - `PointDef` (name, type, size, sf, units, access, mandatory, static, value, symbols)
   - `SymbolDef` (name, value, label, desc)
   - `Parse(dir string) ([]ModelDef, error)` — loads all `models/model_*.json` files.
4. Build code generator in `internal/gen/`:
   - Reads `models/`, outputs Go source into `registry/models_gen.go`.
   - Generated content:
     - Model registry map keyed by model ID (`uint16 → *ModelMeta`)
     - Per model: ID, name/label, fixed block points, repeating block definition
     - Per point: name, type, size (registers), offset within block, SF reference name, units, access, mandatory flag, symbols (for enum/bitfield)
     - Per group: name, type (fixed/repeating), length, nested points
   - Output must be deterministic (sorted keys, stable formatting).
5. Define public metadata types in `registry/registry.go`:
   - `ModelMeta` — ID, Name, Label, FixedBlock `*GroupMeta`, RepeatingBlock `*GroupMeta`
   - `GroupMeta` — Name, Length (registers), Points `[]PointMeta`
   - `PointMeta` — Name, Type, Size, Offset, SF (reference name), Units, Access, Mandatory, Symbols `[]SymbolMeta`
   - `SymbolMeta` — Name, Value, Label
   - Lookup helpers: `ByID(id uint16) *ModelMeta`, `Known(id uint16) bool`, `All() map[uint16]*ModelMeta`
6. Add `//go:generate go run ./internal/gen` directive and `Makefile` targets:
   - `make generate` — runs the code generator
   - `make build` — `go build ./...`
   - `make test` — `go test ./...`
   - `make lint` — `go vet ./...`

### Verification

- `make generate` produces deterministic, `go vet`-clean output.
- `go build ./...` succeeds.
- Unit test: `registry.ByID(1)` returns Common model with correct point names and sizes.
- Unit test: `registry.ByID(101)` returns Single Phase Inverter with scale factor links (`A` → `A_SF`).
- Unit test: `registry.Known(99999)` returns `false`.
- Unit test: point offsets sum correctly to group length.

---

## Phase 2 — Schema-Enriched Discovery

**Goal**: Wrap `modbus.DiscoverSunSpec` results with schema metadata from the generated registry, producing the enriched types the rest of the library operates on.

### Rationale

`modbus.DiscoverSunSpec` returns model **headers** only (ID, length, addresses). This phase adds model **names**, **schema availability**, **point definitions**, and the `Device` handle that higher phases use for reading.

### Steps

1. Define core public types in root package files:

   **`types.go`** — enriched discovery types:
   - `ModelInstance` — wraps `modbus.SunSpecModelHeader`, adds: Name (from registry), Schema `*registry.ModelMeta` (nil if unknown), SchemaKnown bool, DecodingSupported bool.
   - `DiscoveryResult` — BaseAddress, RegType, Models `[]ModelInstance`, Warnings, raw `modbus.SunSpecDiscoveryResult` preserved for evidence.
   - `Device` — holds `*modbus.ModbusClient`, UnitID, `DiscoveryResult`. Entry point for read operations (Phase 4).
   - `DetectOptions` / `DiscoverOptions` — thin wrappers or type aliases over `modbus.SunSpecOptions` where useful; pass through to modbus without reimplementing logic.

   **`errors.go`** — library error types:
   - `ErrNotSunSpec` — detection returned `Detected: false`
   - `ErrUnknownModel` — model ID has no local schema
   - `ErrDecode` — point/model decoding failure
   - `ErrPartialRead` — some registers could not be read
   - `ErrUnsupportedPointType` — point type not handled by decoder
   - Transport and chain errors: re-export or wrap `modbus.ErrSunSpecModelChainInvalid`, `modbus.ErrSunSpecModelChainLimitExceeded`, and standard modbus errors. Do not define duplicates.

2. Implement `Detect(ctx, client, opts) (*modbus.SunSpecDetectionResult, error)` in `detect.go`:
   - Thin convenience wrapper: builds `modbus.SunSpecOptions` from `opts`, calls `client.DetectSunSpec(ctx, sunspecOpts)`.
   - Returns `ErrNotSunSpec` when `Detected == false` (requirements say detection failure is an error at this layer, unlike modbus where it's a non-error result — this is the semantic difference).
   - Callers who prefer the modbus non-error pattern can call `client.DetectSunSpec` directly.

3. Implement `Discover(ctx, client, opts) (*Device, error)` in `discover.go`:
   - Calls `client.DiscoverSunSpec(ctx, sunspecOpts)`.
   - Enriches each `SunSpecModelHeader` with registry lookup → `ModelInstance`.
   - Builds `DiscoveryResult` and returns a `Device` ready for reading.
   - Unknown model IDs: `SchemaKnown = false`, no error (warning only).

### Verification

- Unit test: `Discover` with mock that returns headers for model 1 + 101 + 0xFFFF → enriched `ModelInstance` list with correct names and schema refs.
- Unit test: unknown model ID in chain → `SchemaKnown: false`, no error, warning present.
- Unit test: `Detect` with mock returning `Detected: false` → `ErrNotSunSpec`.
- Unit test: modbus chain error propagates wrapped.

---

## Phase 3 — Point Decoding & Scale Factors

**Goal**: Decode SunSpec register data into typed, scaled values using the generated schema. This phase is independent of live device reads — it operates on `[]uint16` register slices.

### Steps

1. Define decoded result types in `decode_types.go`:
   - `DecodedModel` — ModelID, InstanceAddress, FixedBlock `DecodedBlock`, RepeatingBlocks `[]DecodedBlock`, RawRegisters `[]uint16`, Warnings.
   - `DecodedBlock` — GroupIndex (0 for fixed, 1..N for repeating instances), Points `[]DecodedPoint`.
   - `DecodedPoint` — Name, Type, RawValue `any`, ScaledValue `*float64` (nil when no SF or not implemented), Units, SFName, SFRawValue `*int16`, RegisterOffset, RegisterCount, Implemented bool, Symbols `[]string` (active enum/bitfield symbol names).

2. Implement model-level decoder in `decode.go`:
   - `DecodeModel(regs []uint16, meta *registry.ModelMeta) (*DecodedModel, error)`
   - Slices registers into fixed block, then computes repeating instance count: `(totalRegs - fixedLen) / repeatLen`.
   - Decodes fixed block, then each repeating instance.
   - Collects warnings (unknown types, short slices) without aborting.

3. Implement per-type point decoders in `decode_point.go`:

   | SunSpec Type | Registers | Go raw type | Notes |
   |---|---|---|---|
   | `int16` | 1 | `int16` | Sentinel `0x8000` |
   | `uint16` | 1 | `uint16` | Sentinel `0xFFFF` |
   | `int32` | 2 | `int32` | Sentinel `0x80000000` |
   | `uint32` | 2 | `uint32` | Sentinel `0xFFFFFFFF` |
   | `int64` | 4 | `int64` | Sentinel `0x8000000000000000` |
   | `uint64` | 4 | `uint64` | Sentinel `0xFFFFFFFFFFFFFFFF` |
   | `acc16` | 1 | `uint16` | Accumulator semantics, 0 may be not-implemented |
   | `acc32` | 2 | `uint32` | Same |
   | `acc64` | 4 | `uint64` | Same |
   | `enum16` | 1 | `uint16` | + symbol lookup from `PointMeta.Symbols` |
   | `enum32` | 2 | `uint32` | + symbol lookup |
   | `bitfield16` | 1 | `uint16` | + list of active bit symbol names |
   | `bitfield32` | 2 | `uint32` | Same |
   | `bitfield64` | 4 | `uint64` | Same |
   | `sunssf` | 1 | `int16` | Scale factor value itself |
   | `count` | 1 | `uint16` | Repeating block count hint |
   | `string` | N | `string` | Big-endian, 2 chars/register, trim NULs/spaces |
   | `float32` | 2 | `float32` | IEEE 754 |
   | `float64` | 4 | `float64` | IEEE 754 |
   | `ipaddr` | 2 | `string` | Delegate to `modbus.ReadIPAddr` register layout |
   | `ipv6addr` | 8 | `string` | Delegate to `modbus.ReadIPv6Addr` register layout |
   | `eui48` | 4 | `string` | Delegate to `modbus.ReadEUI48` register layout |
   | `pad` | 1 | — | Skip |
   | unknown | N | `[]uint16` | Raw fallback + warning |

   For `ipaddr`, `ipv6addr`, `eui48`: decode from raw `[]uint16` using the same byte layout that the modbus read helpers use (big-endian wire order). No live modbus call needed — these are pure register-to-value conversions.

4. Implement scale factor resolution in `decode_sf.go`:
   - After decoding all points in a block, resolve SF references.
   - SF point must be in the same model instance's fixed block.
   - Apply: `scaledValue = float64(rawValue) × 10^sfValue`.
   - If SF point is not-implemented or not found → `ScaledValue = nil`, warning.

5. Implement sentinel/"not implemented" detection:
   - Per-type sentinel constants (see table above).
   - When sentinel detected: `Implemented = false`, `ScaledValue = nil`, `RawValue` still populated.

### Verification

- Unit test each point type decoder with known register values.
- Unit test `int16` sentinel `0x8000` → `Implemented: false`.
- Unit test scale factor: point `W` with `W_SF = -2` → `ScaledValue = rawW × 0.01`.
- Unit test repeating block: 3 instances decoded correctly with correct group indices.
- Unit test enum16: symbol name resolved from `PointMeta.Symbols`.
- Unit test bitfield32: multiple active bits → correct symbol name list.
- Unit test string: multi-register big-endian decode, NUL trimming.
- Unit test unknown type → raw `[]uint16` + warning.
- Golden test: decode model_1 fixture registers → expected JSON.
- Golden test: decode model_101 fixture registers → expected JSON with scale factors applied.

---

## Phase 4 — High-Level Device Read API

**Goal**: Read model data from live devices through the `Device` type, using the decoder from Phase 3.

### Steps

1. Implement batch register reading in `read.go`:
   - `readRegisters(ctx, client, unitID, addr, quantity, regType) ([]uint16, error)` — splits reads >125 registers into Modbus-compliant chunks (`client.ReadRegisters` with max 125 per call), concatenates results. Handles partial failure.
   - This is an internal helper; not exported.

2. Implement `Device` read methods in `device.go`:

   ```go
   // Read and decode all discovered models with known schema.
   // Unknown models included with raw registers only.
   func (d *Device) ReadAll(ctx context.Context) ([]*DecodedModel, error)

   // Read and decode a specific model instance by its ModelInstance reference.
   func (d *Device) ReadModel(ctx context.Context, inst ModelInstance) (*DecodedModel, error)

   // Read and decode a specific model by ID.
   // If multiple instances exist, reads the first.
   func (d *Device) ReadModelByID(ctx context.Context, modelID uint16) (*DecodedModel, error)

   // Read a single point from a model instance.
   // v1: reads the full model, returns the named point.
   func (d *Device) ReadPoint(ctx context.Context, inst ModelInstance, pointName string) (*DecodedPoint, error)
   ```

3. Add `ReadEvidence` to all read results:
   - Raw registers, exact address ranges read, per-model warnings.
   - Preserved in `DecodedModel.RawRegisters` and `DecodedModel.Warnings`.

4. Add convenience constructors:
   ```go
   // Create a Device from a pre-existing modbus client + discovery result.
   func NewDevice(client *modbus.ModbusClient, unitID uint8, discovery *DiscoveryResult) *Device

   // Discover and return a ready-to-read Device in one step.
   func Open(ctx context.Context, client *modbus.ModbusClient, opts *DiscoverOptions) (*Device, error)
   ```

### Verification

- Integration test: stub Modbus server with full SunSpec register map → `Open` → `ReadAll` → verify decoded values match fixture.
- Unit test: batch reader splits 200-register span into 125+75 correctly.
- Unit test: `ReadModelByID(101)` returns decoded inverter data.
- Unit test: `ReadPoint(inst, "W")` returns correct watt value with scale factor applied.
- Unit test: unknown model in `ReadAll` → included with raw registers, `SchemaKnown: false`.

---

## Phase 5 — Integration Testing Infrastructure

**Goal**: Build reusable test fixtures using `otfabric/modbus` server for realistic end-to-end tests.

### Steps

1. Create `testutil/` package (test-only):
   - `sunspecserver.go` — implements `modbus.RequestHandler`:
     - Configurable register map backing a SunSpec device.
     - `NewSunSpecFixture(baseAddr uint16, models ...FixtureModel)` — builds the register map with `SunS` marker, model headers, and register payloads from fixture data.
     - Each `FixtureModel` contains model ID, register values for fixed + repeating blocks.
   - `helpers.go` — starts a `modbus.ModbusServer` + `modbus.ModbusClient` pair for integration tests (TCP loopback).

2. Create fixture data in `testdata/`:
   - `common_model1.json` — register values for model 1 (manufacturer="TestMfg", model="TestInv", etc.).
   - `inverter_model101.json` — register values for model 101 with known decoded values.
   - `multi_model_chain.json` — fixture with models 1 + 101 + 201 + end marker.
   - Golden output files for comparison.

3. Write integration tests:
   - End-to-end: `Open` → `ReadAll` → compare decoded output against golden JSON.
   - Detection at different base addresses (0, 40000, 50000).
   - Unknown model in chain → included without decode error.
   - Model chain with only model 1 → single model decoded.
   - Large chain (many models) → all decoded.
   - Partial read failure (server returns error for some addresses) → partial result + error.
   - Repeating block model → instances decoded with correct group indices.

4. Golden tests:
   - `Discover` output → golden JSON.
   - `ReadAll` decoded output → golden JSON.
   - Generated registry snapshot test (detect drift from JSON definitions).

### Verification

- `go test ./...` passes.
- Golden diffs are clean after `make generate`.

---

## Phase 6 — CLI Proof Tool

**Goal**: Thin Cobra CLI demonstrating the library API.

### Steps

1. Set up `cmd/sunspecctl/main.go` with Cobra root command.
   - Global flags: `--url` (modbus URL), `--unit-id`, `--timeout`.
   - Creates `modbus.ModbusClient` from flags, defers `Close`.

2. Implement subcommands:

   | Command | Library call | Output |
   |---|---|---|
   | `detect` | `sunspec.Detect(ctx, client, opts)` | Base address, register type, probe evidence |
   | `models` | `sunspec.Discover(ctx, client, opts)` | Table: ID, name, address range, schema known |
   | `read` | `device.ReadAll(ctx)` | All decoded model data |
   | `read-model --id 101` | `device.ReadModelByID(ctx, 101)` | Single model decoded data |
   | `read-point --model 101 --point W` | `device.ReadPoint(ctx, inst, "W")` | Single point value |

3. Output formatting:
   - Default: human-readable table.
   - `--json` flag: structured JSON output.
   - `--raw` flag (for `read` commands): include raw register hex alongside decoded values.

### Verification

- `go build ./cmd/sunspecctl` succeeds.
- `sunspecctl detect --url tcp://localhost:5020 --unit-id 1` against test fixture produces expected output.
- `sunspecctl models --url tcp://localhost:5020 --json` produces valid JSON.
- CLI consumes only the public API — no `internal/` imports.

---

## Summary

| Phase | Depends on | Delivers |
|---|---|---|
| **1 — Bootstrap & Codegen** | — | `go.mod`, JSON parser, code generator, `registry/` package with all 127 models |
| **2 — Enriched Discovery** | 1 | `Detect`, `Discover`, `Device` type, enriched `ModelInstance` with schema metadata |
| **3 — Decoding** | 1 | `DecodeModel`, all point type decoders, scale factor resolution, sentinel detection |
| **4 — Read API** | 2 + 3 | `Device.ReadAll`, `ReadModel`, `ReadPoint`, batch register reading |
| **5 — Integration Tests** | 4 | Test fixtures, stub server, end-to-end tests, golden tests |
| **6 — CLI** | 4 | `sunspecctl` with `detect`, `models`, `read`, `read-model`, `read-point` |

Phases 2 and 3 can proceed in parallel after Phase 1 is complete.

---

## Key Decisions

| Decision | Rationale |
|---|---|
| **Delegate detection + chain walking to modbus v0.2.0** | Already implemented and tested at the transport level. No reimplementation. |
| **Generated code checked into git** | Enables `go install` without running generator. Regenerate after `sync-models.sh`. |
| **Read-only in all phases** | Write support explicitly out of scope per requirements. |
| **Flat package at repo root** for main API | Cleaner import path (`github.com/otfabric/sunspec`). `registry` and `internal/*` as subpackages. |
| **`ReadPoint` reads full model in v1** | Simpler implementation. Optimize to partial reads later if needed. |
| **Repeating blocks from Phase 3** | Not deferred — required for meter models (201+). |
| **Reuse modbus error sentinels** | Wrap, don't duplicate. `ErrSunSpecModelChainInvalid` etc. propagated directly. |
| **Batch reading lives in sunspec** | Internal helper splitting >125 register reads. Not upstreamed to modbus unless more projects need it. |

---

## `otfabric/modbus` — Changes Identified

**None required.** The v0.2.0 API covers all needs for this library:

| Modbus capability | SunSpec usage |
|---|---|
| `DetectSunSpec` / `DiscoverSunSpec` | Detection + model header enumeration |
| `ReadRegisters` | Batch reading model payloads |
| `ReadIPAddr` / `ReadIPv6Addr` / `ReadEUI48` | Register layout reference for point decoding |
| `ReadAsciiFixed` | String point register layout reference |
| `SunSpecOptions` | Configuration passthrough |
| Error sentinels | Wrapped in sunspec error types |
| `ModbusServer` + `RequestHandler` | Integration test fixtures |

**Previously desired**: `ReadRegistersLarge` helper for transparently batching >125 register reads. The sunspec library handles this internally. If other projects need the same pattern, consider upstreaming at that point.
