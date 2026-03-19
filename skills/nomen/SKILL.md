---
name: nomen
description: Generate memorable, themed names using the nomen CLI. Must use when the user needs to name anything — resources, branches, containers, sessions, releases, deployments, servers, environments, projects, or any entity that needs a human-friendly identifier. Also use when the user says "name this", "give it a name", "what should I call this", "pick a codename", "generate a name", "I need a name for", or asks about naming conventions for infrastructure. Even if the user doesn't explicitly mention "nomen", if they need a memorable identifier for something, this skill applies.
---

# nomen — Categorical Name Generator

Generate memorable, DNS-safe names from themed word lists via the `nomen` CLI.

## Prerequisite

```bash
command -v nomen >/dev/null || echo "nomen not found — install from https://github.com/0xbigboss/nomen"
```

## Choosing a Strategy

- **Thematic** (default) — single evocative word from a themed category. Best for: server names, environment names, release codenames. Pass `--category` to match a theme, or omit for random.

- **Phrase** — two-word combination (adjective-noun, noun-noun, verb-noun). Best for: branch names, container names, project codenames. Tonal coherence and syllable rhythm are applied automatically. ~13K curated combos.

- **Phrase (alliterative)** — two-word phrase that retries up to 50 times to find words sharing the same first letter (e.g., "crystal-cobra", "solar-sphinx"). Falls back to a non-alliterative pair if no match found. Best for: memorable codenames, marketing names. Use `--strategy phrase:alliterative`.

- **Triple** — three-word combination, randomly choosing adjective-adjective-noun or adjective-noun-noun. Best for: when two words aren't distinct enough, or you want extra flavor. Use `--strategy triple`.

- **Mnemonic** — deterministic word pair (or triple for long inputs) from a numeric/hex input. Same input always produces the same name. Best for: giving stable aliases to ugly identifiers (SHAs, IPs, UUIDs). Uses FNV-1a hash for good distribution across ~4.4M combos.

## Always Use `--format json` for Programmatic Use

```bash
nomen generate --format json | jq -r '.value'
nomen generate --count 3 --format json | jq -r '.[].value'
```

## Quick Reference

```bash
nomen generate                                          # random themed name
nomen generate -c mountains --count 3                   # three mountain names
nomen generate --strategy phrase --count 5              # five adjective-noun phrases
nomen generate --strategy phrase:alliterative --count 5  # mostly alliterative phrases
nomen generate --strategy phrase:verb_noun              # verb-noun phrase
nomen generate --strategy triple --count 3              # three-word names
nomen generate --strategy mnemonic --input 0xABC        # deterministic from hex
nomen generate --strategy mnemonic --input 0xdeadbeefcafe  # 3-word for long input
nomen generate --seed 42                                # reproducible output
nomen categories                                        # list 14 categories
```

**Categories:** mountains, rivers, deserts, canyons, islands, passes, moons, raptors, minerals, norse, volcanoes, forests, oceans, storms

## Common Patterns

```bash
# Name a git branch
git checkout -b "feat/$(nomen generate -f human)"

# Alliterative codename for a release
nomen generate -s phrase:alliterative -f human

# Codename from commit SHA
nomen generate -s mnemonic --input "$(git rev-parse --short HEAD)" -f human

# Name a container
docker run --name "$(nomen generate -s phrase -f human)" nginx

# Deterministic name from any string
nomen generate -s mnemonic --input "0x$(echo -n 'my-string' | md5 | head -c 8)" -f human

# Stable daily name
nomen generate --seed "$(date +%Y%m%d)" -f human

# Three-word project codename
nomen generate -s triple -f human
```

## Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--count N` | `-n` | Number of names (default: 1) |
| `--category NAME` | `-c` | Restrict to category |
| `--strategy NAME` | `-s` | thematic, phrase[:pattern], triple, mnemonic |
| `--seed N` | | Deterministic output |
| `--input TEXT` | `-i` | Input for mnemonic (numeric/hex) |
| `--format FMT` | `-f` | json, jsonl, human |
| `--fields LIST` | | Comma-separated output fields |
| `--dry-run` | | Validate without generating |

## Output Fields

- `value` — the name string (DNS-safe: `[a-z0-9-]`)
- `category` — source category (null for phrase/triple/mnemonic)
- `strategy` — generation method used
