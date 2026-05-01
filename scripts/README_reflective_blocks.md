# Reflective Block Generator

This generator creates a managed block of `block.<materialId>=...` entries in
`shaders/block.properties` from regex rules.

## Usage

Create or export a text file with one block id per line, for example:

```text
gregtech:machine_casing_clean_stainless_steel
gregtech:machine_hull_mv
gregtech:bronze_pipe
```

Run:

```sh
python3 scripts/generate_reflective_blocks.py path/to/block-list.txt
```

Preview without writing:

```sh
python3 scripts/generate_reflective_blocks.py path/to/block-list.txt --dry-run
```

## Rules

Rules live in `scripts/reflective_block_rules.json`. The first matching rule
wins, so put more specific rules above broader ones.

The generated section is fully replaced every run. Removing a rule or changing
the input list removes the old generated mappings on the next run.
