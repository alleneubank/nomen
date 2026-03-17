# nomen

Categorical name generator that produces memorable, themed names for devices, projects, and resources. Agent-first CLI and HTTP API.

## Install

Requires [Nix](https://nixos.org/download/) with flakes enabled.

```bash
nix develop    # enter dev shell with zig 0.15.2, zls, ziglint
zig build      # build
zig build test # run tests
```

## Usage

```bash
# Generate names
nomen generate                                    # one name (human in TTY, json otherwise)
nomen generate --count 5 --category rivers         # five river names
nomen generate --strategy phrase --format json      # two-word phrase as JSON
nomen generate --strategy phrase:verb_noun          # verb+noun pattern
nomen generate --strategy mnemonic --input 0xbeef   # mnemonic from hex
nomen generate --seed 42                            # deterministic output
nomen generate --fields value --format json         # filter output fields
nomen generate --dry-run                            # validate without generating

# List categories
nomen categories
nomen categories --format json

# HTTP API
nomen serve                    # start on port 8080
nomen serve --port 3000        # custom port
# GET /generate?count=3&category=mountains&seed=42
# GET /categories
# GET /health

# Agent discovery
nomen --llms                   # machine-readable manifest
nomen generate --help --format json  # structured help
```

## Categories

mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse

## Strategies

| Strategy | Description | Example |
|----------|-------------|---------|
| `thematic` | Single word from a category | `denali` |
| `phrase` | Adjective+Noun (default pattern) | `swift-ridge` |
| `phrase:noun_noun` | Noun+Noun | `stone-creek` |
| `phrase:verb_noun` | Verb+Noun | `climb-peak` |
| `mnemonic` | Deterministic pair from hex/numeric input | `wild-dune` |

## Agent-First Design

- Structured JSON output by default in non-TTY, human-readable in TTY
- `--format json|jsonl|human` on every command
- `--llms` manifest for agent discovery with schemas and examples
- `--help --format json` for machine-readable help on every subcommand
- `--dry-run` validates inputs without side effects
- `--fields` filters output keys
- Structured error responses with `code` and `message` fields
- stdout = data only, stderr = messages/errors

## Development

```bash
zig build test     # run all tests
zig build fmt      # check formatting
ziglint            # static analysis
lefthook install   # setup git hooks
zig build docs     # generate documentation
```

## License

MIT
