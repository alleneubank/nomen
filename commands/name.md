---
description: Generate a memorable name using nomen
argument-hint: [strategy] [category]
allowed-tools: [Bash]
---

# /name — Generate a Name

Generate a memorable name using the nomen CLI.

## Arguments

$ARGUMENTS

## Instructions

1. Parse the arguments:
   - No args: `nomen generate --format human`
   - `phrase`: `nomen generate --strategy phrase --format human`
   - `mnemonic <input>`: `nomen generate --strategy mnemonic --input <input> --format human`
   - A category name (mountains, rivers, etc.): `nomen generate --category <name> --format human`
   - A number: `nomen generate --count <number> --format human`
   - Combinations work: `phrase 5` = `nomen generate --strategy phrase --count 5 --format human`

2. Run the nomen command and display the result.

## Examples

```
/name                    → one random themed name
/name phrase             → one adjective-noun phrase
/name phrase 5           → five phrases
/name mountains          → one mountain name
/name mnemonic 0xdead    → deterministic from hex
/name 10                 → ten random names
```
