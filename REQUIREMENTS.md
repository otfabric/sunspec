# REQUIREMENTS

## 1. Purpose

Build a Go library to interact with **SunSpec-enabled Modbus devices** using `github.com/otfabric/modbus` as the Modbus transport and register access layer.

The library must:

- detect whether a Modbus device is SunSpec-enabled
- discover and print the SunSpec models exposed by the device
- fetch and decode data for available SunSpec models
- leverage the synchronized SunSpec JSON model definitions as much as possible
- expose a reusable Go API for other applications and tools
- keep CLI concerns strictly separated from the library API

A small command-line tool may be provided as a proof-of-use of the library, but the CLI must remain a thin wrapper around the reusable library.

---

## 2. Scope

### In scope

- SunSpec discovery over Modbus
- SunSpec model chain parsing
- loading and using synchronized JSON model definitions
- decoding model points from device registers
- exposing a reusable Go API
- code generation from JSON model definitions where useful
- read-only interaction for the first phase
- support for Modbus TCP / RTU / RTU-over-TCP / TLS indirectly via `otfabric/modbus`

### Out of scope for first phase

- SunSpec write operations for writable points
- full SunSpec conformance certification tooling
- vendor-specific non-SunSpec Modbus map decoding
- UI concerns
- Cobra command design beyond a thin demonstration CLI
- persistent storage
- polling scheduler / historian / time-series collection
- automatic support for every possible SunSpec edge case on day one

---

## 3. High-Level Goals

The solution must provide:

1. A **library-first architecture**
2. A **data-driven model system** based on SunSpec JSON definitions
3. A **clean separation** between:
   - Modbus transport
   - SunSpec discovery
   - model/schema loading
   - decoding
   - high-level API
   - CLI presentation
4. A design that is suitable for reuse by:
   - command-line tools
   - OT Scanner / OT Fabric services
   - inventory enrichment tools
   - future protocol abstraction layers

---

## 4. Functional Requirements

## 4.1 Device discovery

The library must be able to determine whether a target Modbus device is SunSpec-enabled.

### Requirements

- The library must probe candidate SunSpec base addresses.
- The library must check for the SunSpec marker `SunS`.
- The library must support the standard SunSpec candidate base addresses:
  - `0`
  - `40000`
  - `50000`
- The library must allow callers to override or extend candidate base addresses.
- The library must support configurable Modbus unit ID.
- The library must return a structured result indicating:
  - whether SunSpec was detected
  - the discovered base address
  - the register type used
  - any evidence collected
  - any errors encountered

### Notes

- First phase should assume SunSpec is exposed in **holding registers**.
- The API should be designed so alternate register spaces could be supported later if needed.

---

## 4.2 Model chain discovery

Once SunSpec is detected, the library must walk the contiguous model chain.

### Requirements

- The library must read model headers sequentially starting after the `SunS` marker.
- For each model instance, the library must read:
  - `ID`
  - `L`
- The library must calculate:
  - model start address
  - model end address
  - next model start address
- The library must stop at the SunSpec end model:
  - `ID = 0xFFFF`
  - `L = 0`
- The library must return the discovered model list in order.
- The library must support unknown model IDs without failing the entire scan.
- The library must identify whether a model definition is known locally from the synced JSON definitions.

### Output per discovered model

At minimum:

- model ID
- model name if known
- absolute start register
- absolute end register
- model length
- whether schema is known
- whether decoding is supported
- raw header values

---

## 4.3 Fetching model data

The library must allow callers to fetch data from one or more discovered models.

### Requirements

- The caller must be able to request:
  - all discovered models
  - one model by ID
  - one model instance by absolute start address
  - selected points within a model
- The library must read registers in efficient batches.
- The library must decode model data using the synchronized JSON definitions.
- The library must return both:
  - raw register values
  - decoded semantic point values
- The library must preserve enough metadata to trace every decoded point back to:
  - model ID
  - model instance start address
  - point definition
  - absolute Modbus register address
  - raw register slice used

---

## 4.4 Point decoding

The library must decode SunSpec points according to the JSON model definitions.

### Requirements

The decoder must support, at minimum, the core SunSpec point types needed for common models:

- `int16`
- `uint16`
- `int32`
- `uint32`
- `int64`
- `uint64`
- `acc16`
- `acc32`
- `acc64`
- `enum16`
- `bitfield16`
- `bitfield32`
- `sunssf`
- `string`
- `ipaddr`
- `ipv6addr`
- `eui48`
- `float32` if present in model definitions
- raw / unknown fallback

### Additional requirements

- The library must support SunSpec scale factors.
- The library must resolve dynamic `sunssf` references within the same model instance.
- The library must expose both:
  - raw value
  - scaled value
- The library must preserve “not implemented” and sentinel values where relevant.
- The decoder must not silently lose information.

---

## 4.5 Repeating blocks and arrays

The library must support SunSpec repeating blocks where defined in the JSON model definitions.

### Requirements

- The schema loader must understand fixed block vs repeating block structure.
- The decoder must be able to decode:
  - fixed points
  - repeating group instances
- The API must expose repeated groups in a structured form.
- The CLI may flatten repeated groups for display, but the library API must preserve structure.

---

## 4.6 Raw access and evidence

The library must remain useful for scanners and inventory tools, not only for pretty printing.

### Requirements

The API must expose raw evidence such as:

- raw registers read
- exact address ranges read
- model headers
- unknown models
- unknown points
- decode warnings
- partial read results when possible

This is important so the library can support:
- fingerprinting
- troubleshooting
- inventory enrichment
- future schema improvements

---

## 5. Non-Functional Requirements

## 5.1 Library-first design

The SunSpec implementation must be a reusable library, not a CLI-centered tool.

### Requirements

- No Cobra dependencies inside the library packages.
- No stdout/stderr printing inside library packages.
- No CLI formatting assumptions in the library API.
- The library API must return structured Go types and errors.
- The CLI must be a thin adapter layer only.

---

## 5.2 Separation of concerns

The solution must be split into clear layers.

### Required separation

- **transport layer**: `otfabric/modbus`
- **session/device access layer**: opens and uses a Modbus client
- **discovery layer**: detects SunSpec marker and model chain
- **schema layer**: loads generated/embedded model metadata
- **decoder layer**: decodes register data into typed values
- **high-level API layer**: exposes ergonomic operations
- **CLI layer**: Cobra / flags / rendering only

---

## 5.3 Extensibility

The design must support future expansion.

### Future-proofing requirements

- add write support later
- add vendor extensions later
- add model-specific helpers later
- add polling later
- add alternate schema sources later
- add generated typed wrappers for popular models later
- add integration with OT Fabric inventory / scanner pipelines later

---

## 5.4 Robustness

The library must behave predictably against imperfect devices.

### Requirements

- tolerate unknown model IDs
- tolerate missing local JSON schema for a discovered model
- tolerate partial read failures where possible
- return structured warnings
- distinguish transport errors from protocol/decode errors
- avoid panics on malformed schema or malformed device data

---

## 5.5 Performance

The library should be efficient enough for scanning and inventory enrichment.

### Requirements

- avoid one-register-at-a-time reads where possible
- batch reads when decoding model payloads
- avoid repeated reparsing of JSON model definitions at runtime
- prefer generated Go structures over runtime schema walking where practical
- support reuse of a provided `modbus.ModbusClient`

---

## 6. Modbus Integration Requirements

The library must leverage `github.com/otfabric/modbus` and not reimplement Modbus transport logic.

### Requirements

- use `modbus.NewClient` / `Open` / `Close`
- support caller-provided `*modbus.ModbusClient`
- support caller-provided context
- support configurable unit ID
- use `ReadRegisters` / `ReadUint16s` style APIs for block reads
- assume default SunSpec register ordering compatible with SunSpec spec
- use `modbus.HoldingRegister` for first phase
- integrate cleanly with existing timeout / retry / metrics / logging support in `otfabric/modbus`

### Nice to have

- helper constructor that creates a SunSpec client from `modbus.ClientConfiguration`
- helper support for shared pooled Modbus clients

---

## 7. JSON Model Synchronization and Code Generation

The synced JSON definitions are the source of truth for model schemas and should be leveraged heavily.

## 7.1 Source of truth

The repository-local synchronized SunSpec JSON files under `models/` are the authoritative schema input for this library build.

### Requirements

- the build must consume local synchronized JSON files
- the runtime library must not depend on internet access
- the library must not parse remote GitHub resources at runtime

---

## 7.2 Code generation

Code generation should be used where it meaningfully improves safety, performance, and maintainability.

### Generation goals

Generate Go artifacts from the JSON model definitions, such as:

- model registry metadata
- point definitions
- offsets and lengths
- block structure
- type mappings
- scale factor linkage metadata
- enums / bitfield metadata where available

### Requirements

- provide a code generation step, e.g. `go generate` or `make generate`
- generated code must be checked into git or reproducibly generated; team must choose one policy explicitly
- generated artifacts must be deterministic
- generated code must be separated from handwritten logic
- generated code must be human-inspectable enough for debugging

### Recommended approach

Generate:
- a compact schema registry in Go
- strongly typed metadata structs
- embedded schema tables

Do **not** generate one giant pile of model-specific business logic in v1.

---

## 7.3 Runtime use of generated schema

At runtime, the library should rely primarily on generated Go metadata rather than reparsing every JSON file dynamically.

### Requirements

- runtime should load schema from generated Go structures
- optional debug tooling may still inspect raw JSON files
- unknown or newly synced models should be easy to regenerate into the registry

---

## 8. API Requirements

## 8.1 Public API principles

The public API must be:

- idiomatic Go
- context-aware
- structured
- reusable
- testable
- transport-agnostic beyond depending on the provided Modbus client

---

## 8.2 Core use cases

The public API must support these core flows:

### A. Detect SunSpec

```go
result, err := sunspec.Detect(ctx, client, unitID, nil)
```

### B. Discover models

```go
device, err := sunspec.Discover(ctx, client, unitID, nil)
```

### C. Read all model data

```go
data, err := device.ReadAll(ctx)
```

### D. Read one model instance

```go
m, err := device.ReadModel(ctx, modelInstance)
```

### E. Read one point

```go
v, err := device.ReadPoint(ctx, modelInstance, "W")
```

Exact signatures may vary, but these capabilities must exist.

---

## 8.3 Required public concepts

The library API must expose structured concepts for:

- `Detector`
- `DiscoveryResult`
- `Device`
- `ModelInstance`
- `ModelDefinition`
- `PointDefinition`
- `DecodedModel`
- `DecodedPoint`
- `Warning`
- `ReadEvidence`

Names may vary, but these concepts must exist.

---

## 8.4 Error model

The API must define clear error categories.

### Errors should distinguish at least:

- transport / connectivity errors
- Modbus protocol errors
- SunSpec not detected
- invalid model chain
- unknown model definition
- decode errors
- partial read errors
- unsupported point type

Where useful, errors should wrap underlying `otfabric/modbus` errors.

---

## 9. CLI Proof Tool Requirements

A small CLI proof tool may be included to validate and demonstrate the library.

## 9.1 Purpose

The CLI is only a demonstration and utility layer over the reusable library.

## 9.2 Requirements

The CLI should support commands like:

- `detect`
- `models`
- `read`
- `read-model`
- `read-point`

### Example behavior

- `detect` prints whether SunSpec was found and at which base address
- `models` prints discovered models in order with addresses
- `read` prints decoded values for all models
- `read-model --id 101` prints one model instance
- `read-point --model 101 --point W` prints one point

### Constraints

- Cobra/parsing/rendering must remain outside the library
- the CLI must consume the same public API as any other Go caller
- the CLI must not access internal packages directly unless intentionally allowed

---

## 10. Package Structure Requirements

A package structure along these lines is required:

```text
/sunspec
  /cmd/...                 # thin CLI(s)
  /internal/gen/...        # code generation logic
  /internal/schemajson/... # raw schema ingestion helpers if needed
  /pkg or root packages    # public reusable API
```

A more Go-idiomatic version is preferred, for example:

```text
/cmd/sunspecctl
/internal/gen
/internal/schema
/discovery
/decode
/models
```

or a flatter public API such as:

```text
sunspec/
  detect.go
  discover.go
  read.go
  types.go
  errors.go
  schema_registry_gen.go
```

### Mandatory rule

The public reusable library must not live under `cmd`.

---

## 11. Testing Requirements

## 11.1 Unit tests

The project must include unit tests for:

- SunSpec marker detection
- model chain walking
- address calculations
- schema registry lookup
- type decoding
- scale factor resolution
- string decoding
- unknown model handling
- unknown point handling
- generated schema integrity

---

## 11.2 Integration tests

Integration tests must be possible against:

- a fake/stub Modbus server using `otfabric/modbus`
- captured register fixtures
- optionally real devices later

### Requirements

- test SunSpec discovery against known fixture maps
- test multiple model chains
- test vendor extension presence
- test partial / malformed maps
- test different base addresses

---

## 11.3 Golden tests

Golden tests are recommended for:

- generated schema output
- discovered model lists
- decoded JSON output from fixture devices

---

## 12. Observability Requirements

The library should support observability without forcing logging behavior.

### Requirements

- library should not print directly
- caller may pass logger through underlying Modbus client configuration
- library should expose structured warnings
- library may optionally expose debug hooks or trace callbacks later

---

## 13. Compatibility Requirements

## 13.1 Go compatibility

- target a clearly defined supported Go version
- follow idiomatic Go module layout
- support reproducible builds

## 13.2 Modbus compatibility

The library must work with the transport modes supported by `otfabric/modbus`, subject to device behavior:

- Modbus TCP
- Modbus TCP over TLS
- Modbus RTU
- RTU over TCP
- RTU over UDP
- UDP where applicable

---

## 14. Deliverables

The implementation effort must produce:

1. reusable Go SunSpec library
2. separated proof CLI
3. code generation pipeline for synced JSON model definitions
4. tests
5. developer documentation
6. examples

---

## 15. Minimum Viable Feature Set

The first usable milestone must include:

- SunSpec detection
- model chain discovery
- known/unknown model reporting
- decoding of common model data
- decoding of at least common inverter/meter-oriented primitive points
- reusable library API
- thin CLI demo
- code generation from synced JSON model definitions

---

## 16. Recommended Implementation Approach

## Phase 1 — Foundation

- define public API types
- implement detection
- implement model chain walking
- build schema loader / generator
- generate registry from JSON definitions

## Phase 2 — Decoding

- implement point type decoding
- implement scale factor resolution
- implement decoded model output
- add unknown/fallback behavior

## Phase 3 — CLI proof

- add thin CLI commands
- add text and JSON output modes
- verify API usability

## Phase 4 — Hardening

- integration tests
- fixture coverage
- malformed map handling
- performance cleanup

---

## 17. Acceptance Criteria

The work is accepted when all of the following are true:

1. A Go developer can use the library without the CLI.
2. The library can detect SunSpec on a target device.
3. The library can discover and list model instances with addresses.
4. The library can decode at least a representative subset of standard models using the synced JSON definitions.
5. The JSON definitions are leveraged through a reproducible generation workflow.
6. The CLI is demonstrably a thin wrapper, not the primary implementation.
7. Tests cover discovery and decoding paths.
8. Unknown models do not break discovery.
9. Errors are structured and useful.
10. The design is suitable for reuse inside OT Fabric tools.

---

## 18. Nice-to-Have Enhancements

These are not required for v1 but should be considered in the design:

- writable point support
- model-specific typed helper APIs
- JSON schema export of discovered device data
- inventory/fingerprint summary helpers
- vendor extension plug-in mechanism
- batch polling planner
- caching of model reads
- direct OT Scanner integration
