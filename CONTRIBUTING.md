# Contributing

## Setup

```bash
nix develop
# or install Zig 0.15.2 and ziglint by hand
```

`direnv` loads `.envrc` if you use it. Do not run `direnv allow` from an agent session.

## Checks

```bash
zig build test
zig build fmt
ziglint
zig build wasm
```

`lefthook install` runs fmt, lint, and test on pre-commit.

## Playground

```bash
zig build wasm
python3 -m http.server -d site 4173
```

Visual rules live in `DESIGN.md`. Taste floors live in `site/BRIEF.md`. Run `npx impeccable detect site/` before shipping CSS or copy.

## Scope

Behavioral changes need a `REQ-*` in `SPEC.md` and a test. Word lists stay lowercase, alphabetic, and at most 12 characters. Construct seed words stay lowercase alphabetic, at most 20 characters, at most five words.
