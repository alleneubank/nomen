# nomen

Categorical name generator. DNS-safe names from fourteen geographic and natural-history lists, plus construct techniques (portmanteau, compound, clip, affix, backform, phonosym, acronym).

CLI and HTTP API for humans and agents. Same seed and flags always produce the same name.

## Install

Requires [Zig 0.15](https://ziglang.org/download/) or Nix with flakes.

```bash
# Nix
nix run github:alleneubank/nomen -- generate --count 5

# from source
git clone https://github.com/alleneubank/nomen
cd nomen
zig build -Doptimize=ReleaseSafe
./zig-out/bin/nomen generate
```

Library consumers:

```bash
zig fetch --save git+https://github.com/alleneubank/nomen
```

Dev shell (Zig 0.15.2, zls, ziglint):

```bash
nix develop
zig build test
```

## Usage

```bash
nomen generate                                    # one name (human in TTY, json otherwise)
nomen generate --count 5 --category rivers
nomen generate --strategy phrase --format json
nomen generate --strategy phrase:alliterative --count 5
nomen generate --strategy triple --count 3
nomen generate --strategy mnemonic --input 0xdeadbeefcafe
nomen generate --seed 42
nomen generate --strategy construct:portmanteau --input "spell,master"
nomen generate --strategy construct:compound --input "storm,forge"
nomen generate --strategy construct:phonosym --input "sharp" --count 5
nomen generate --strategy construct:affix --input "quill"
nomen generate --strategy construct:acronym --input "spell,practice,app"
nomen generate --dry-run

nomen categories
nomen serve --port 8080
# GET /generate?count=3&category=mountains&seed=42
# GET /categories
# GET /health

nomen --llms
nomen generate --help --format json
```

## Categories

mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse, volcanoes, forests, oceans, storms

## Strategies

| Strategy | Description |
|----------|-------------|
| `thematic` | One word from a category |
| `phrase` | Adjective-noun (default pattern) |
| `phrase:noun_noun` | Noun-noun |
| `phrase:verb_noun` | Verb-noun |
| `phrase:alliterative` | Shared first letter, with fallback |
| `triple` | Three words |
| `mnemonic` | Deterministic pair or triple from hex/numeric input |
| `construct:portmanteau` | Blend two words at an overlap |
| `construct:compound` | Concatenate two words |
| `construct:clip` | First syllable + last syllable |
| `construct:affix` | Prefix or suffix |
| `construct:backform` | Strip a recognized suffix |
| `construct:phonosym` | Mood-tagged phonemes (`sharp`, `soft`, `rhythmic`) |
| `construct:acronym` | Pronounceable initials |

## Agent-first

- JSON on non-TTY stdout; `--format json|jsonl|human` on every command
- `--llms` manifest with schemas and examples
- `--help --format json` on every subcommand
- `--fields` filters output keys
- Structured errors with `code` and `message`
- stdout is data; stderr is messages

## Playground

The generator also compiles to WebAssembly:

```bash
zig build wasm
python3 -m http.server -d site 4173
```

Open `http://127.0.0.1:4173`. Visual system: `DESIGN.md`.

## Development

```bash
zig build test
zig build fmt
ziglint
lefthook install
zig build docs
```

## License

MIT
