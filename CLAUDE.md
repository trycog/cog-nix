# cog-nix

SCIP-based code intelligence for Nix files, written in Nix.

## Architecture

The tool is written entirely in Nix. The entry point is `bin/cog-nix` (a shell
script) which invokes `nix eval --impure` on `lib/default.nix`. The Nix code
tokenizes source files, analyzes them for definitions and references, encodes
the result as SCIP protobuf (as a hex string), and the shell script converts
hex to binary via `xxd -r -p`.

### Key files

- `lib/default.nix` — Entry point: orchestrates file processing, assembles SCIP index
- `lib/analyze.nix` — Tokenizer + analyzer: splits source into tokens, classifies definitions/references
- `lib/encode.nix` — Protobuf encoder: produces hex-encoded SCIP protobuf
- `lib/symbol.nix` — SCIP symbol string builder
- `bin/cog-nix` — Shell wrapper: CLI arg parsing, project root discovery, nix eval invocation

## Development

Prerequisites: Nix (with flakes enabled).

```bash
# Run on a file
bin/cog-nix --output /tmp/test.scip path/to/file.nix

# Run smoke tests
bash test/smoke.sh

# Decode output (requires protoc)
protoc --decode_raw < /tmp/test.scip
```

## Release process

Version is the single source of truth in `cog-extension.json`. To release:

1. Update `version` in `cog-extension.json`
2. Update `version` in `flake.nix`
3. Update `CHANGELOG.md`
4. Tag: `git tag v$(jq -r .version cog-extension.json)`
5. Push: `git push origin main --tags`

## Known limitations

- No string interpolation analysis (symbols inside `"${...}"` are not indexed)
- `with` scope is opaque (can't resolve injected names without evaluation)
- No cross-file resolution
- No evaluation-dependent patterns (callPackage, overlays, etc.)
- Dynamic attrs (`"${expr}" = value;`) cannot be indexed
