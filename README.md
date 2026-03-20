<div align="center">

# cog-nix

**Nix language extension for [Cog](https://github.com/trycog/cog-cli).**

SCIP-based code intelligence for Nix projects, including Nix Flake support.

[Installation](#installation) · [Code Intelligence](#code-intelligence) · [How It Works](#how-it-works) · [Development](#development)

</div>

---

## Installation

### Prerequisites

- [Nix](https://nixos.org/download) with flakes enabled
- [Cog](https://github.com/trycog/cog-cli) CLI installed

### Install

```sh
cog ext:install https://github.com/trycog/cog-nix.git
cog ext:install https://github.com/trycog/cog-nix --version=0.1.0
cog ext:update
cog ext:update cog-nix
```

Cog downloads the tagged GitHub release tarball, then runs the manifest build command locally. The extension version is defined once in `cog-extension.json`; release tags use `vX.Y.Z`, and the install flag uses the matching bare semver `X.Y.Z`.

---

## Code Intelligence

Add index patterns to your project's `.cog/settings.json`:

```json
{
  "code": {
    "index": [
      "**/*.nix"
    ]
  }
}
```

For a flake project you may want to be more specific:

```json
{
  "code": {
    "index": [
      "flake.nix",
      "lib/**/*.nix",
      "modules/**/*.nix",
      "pkgs/**/*.nix"
    ]
  }
}
```

Then index your project:

```sh
cog code:index
```

Once indexed, AI agents query symbols through Cog's MCP tools:

- `cog_code_explore` — Find symbols by name, returns full definition bodies and references
- `cog_code_query` — Low-level queries: find definitions, references, or list symbols in a file
- `cog_code_status` — Check index availability and coverage

The index is stored at `.cog/index.scip` and automatically kept up-to-date by Cog's file watcher after the initial build.

| File Type | Capabilities |
|-----------|--------------|
| `.nix` | Go-to-definition, find references, symbol search, project structure |
| `flake.nix` | All standard capabilities plus flake-aware input/output indexing |

### Indexing Features

The SCIP indexer supports:

- Attribute set bindings (`{ name = value; }`)
- Let bindings with mutual recursion (`let x = 1; y = x; in ...`)
- Lambda parameters — simple (`x: body`) and pattern (`{ a, b, ... }: body`)
- Inherit statements (`inherit x y z;`, `inherit (expr) x;`)
- Identifier reference resolution against known definitions
- Nested attrpaths (`services.nginx.enable = true`)
- Function detection (lambdas assigned to attribute names)
- Flake structure — `inputs` as modules, `outputs` as function, well-known output keys (`packages`, `devShells`, `nixosConfigurations`, `overlays`, `lib`, etc.) as modules
- Import detection (`import ./path.nix`)
- Comment and string skipping (tokens inside strings and comments are not indexed)

### Known Limitations

- **No string interpolation analysis** — symbols inside `"${...}"` are not indexed
- **`with` scope is opaque** — can't resolve which names `with pkgs;` injects without evaluation
- **No cross-file resolution** — can't follow imports into other files
- **No evaluation-dependent patterns** — `callPackage`, overlays, and other nixpkgs meta-programming requires evaluation
- **Dynamic attrs** — `"${expr}" = value;` cannot be statically indexed

---

## How It Works

Cog invokes `cog-nix` once per extension group. It expands the matched file paths directly onto argv, and the tool processes each file through a Nix-native analysis pipeline. As each file finishes, `cog-nix` emits structured progress events on stderr so Cog can advance its progress UI file by file.

```
cog invokes:  bin/cog-nix --output <output_path> <file_path> [file_path ...]
```

**Auto-discovery:**

| Step | Logic |
|------|-------|
| Workspace root | Walks up from each input file until a directory containing `flake.nix` or `default.nix` is found (fallback: `.git`, then file parent directory). |
| Project name | Parsed from `flake.nix` `description` field via regex. Falls back to workspace directory name. |
| Indexed target | Every file expanded from `{files}`; output is one SCIP protobuf containing one document per input file. |

### Architecture

The tool is written entirely in Nix. The shell wrapper invokes `nix eval --impure` on the Nix library, which returns hex-encoded protobuf converted to binary via `xxd`.

```
lib/
├── default.nix          # Entry point — orchestrates file processing, assembles SCIP index
├── analyze.nix          # Tokenizer + analyzer — regex-based tokenization, single-pass classification
├── encode.nix           # Protobuf encoder — hand-rolled wire format, outputs hex string
└── symbol.nix           # SCIP symbol string builder
bin/
└── cog-nix              # Shell wrapper — CLI args, project root discovery, nix eval, hex→binary
```

Tokenization uses `builtins.split` with a composite regex to extract identifiers, operators, and delimiters. A state machine skips string and comment contents. The analyzer walks the token list with `builtins.foldl'`, classifying identifiers as definitions or references based on surrounding context (lookahead/lookbehind). Protobuf encoding is implemented in pure Nix using a character-to-hex lookup table and varint encoding.

---

## Development

### Build from source

No compilation required — the tool runs directly from the repository:

```sh
chmod +x bin/cog-nix
```

Or build via Nix flake (bundles dependencies and wraps the script):

```sh
nix build
```

### Local install workflow

```sh
chmod +x bin/cog-nix
```

### Release

- Set the next version in `cog-extension.json` and `flake.nix`
- Tag releases as `vX.Y.Z` to match Cog's exact-version install flow
- Pushing a matching tag triggers GitHub Actions to verify the tag against `cog-extension.json`, run smoke tests, and create a GitHub Release
- Cog installs from the release source tarball

### Test

```sh
bash test/smoke.sh
```

Smoke tests run `cog-nix` against fixture files and verify the output is non-empty, valid protobuf (when `protoc` is available).

### Manual verification

```sh
bin/cog-nix --output /tmp/index.scip path/to/file.nix
protoc --decode_raw < /tmp/index.scip
```

---

<div align="center">
<sub>Built with <a href="https://nixos.org">Nix</a></sub>
</div>
