# Progress

Tracks implementation progress against [PLAN.md](PLAN.md).

## Phase 1 — Project Bootstrap & Code Generation

- [x] `go.mod` + Makefile
- [x] `internal/schema/` — JSON model ingestion types + parser
- [x] `internal/gen/` — code generator
- [x] `registry/` — generated metadata types + lookup helpers
- [x] Run generator, verify output compiles
- [x] Unit tests for registry lookups

## Phase 2 — Schema-Enriched Discovery

- [x] Public types (`types.go`, `errors.go`)
- [x] `Detect()` wrapper
- [x] `Discover()` + enriched `ModelInstance`
- [x] Unit tests

## Phase 3 — Point Decoding & Scale Factors

- [x] Decoded result types
- [x] Per-type point decoders
- [x] Scale factor resolution
- [x] Sentinel detection
- [x] Model-level decoder with repeating blocks
- [x] Unit tests

## Phase 4 — High-Level Device Read API

- [x] Batch register reader
- [x] `Device` type + `ReadAll` / `ReadModel` / `ReadPoint`
- [x] Convenience constructors (`Open`)
- [x] Unit tests

## Phase 5 — Integration Testing

- [x] Test fixture server (`testutil/`)
- [x] End-to-end integration tests
- [x] Golden tests

## Phase 6 — CLI Proof Tool

- [x] `cmd/sunspecctl` with Cobra
- [x] `detect`, `models`, `read`, `read-model`, `read-point` commands
- [x] Build verification
