# Layout Benchmark Corpus v1

Version: 1.0 (Frozen Seed Baseline)
Specification: `docs/plans/03-comparative-false-positive-benchmark.md`
Source commit: `b8471649300162827cc4053d553c14a895820e8b`

## Overview

This directory contains the frozen 200-trial seed corpus for the SwitchFix comparative layout reliability benchmark:
- `development.jsonl`: 100 trials used during development and regression testing
- `holdout.jsonl`: 100 trials reserved for generalization evaluation
- `manifest.json`: Cryptographic integrity hashes and split distributions

## Split Structure (Per Split)

Each split contains exactly 100 trials:
- **20 Repair** trials: Intentional layout errors requiring automatic repair (10 English → Ukrainian, 10 Ukrainian → English)
- **60 Preserve** trials: Intentional correct text requiring preservation with no modifications (30 typed under ABC, 30 typed under Ukrainian)
- **20 Abstain** trials: Ambiguous or unsupported inputs requiring no automatic action (10 typed under ABC, 10 typed under Ukrainian)

Base group IDs (`groupID`) are completely disjoint across the development and holdout splits.

## Trial Schema & Provenance

Every row in the JSONL files is an independent JSON object:
- `schemaVersion`: 1
- `id`: Unique identifier across all splits
- `groupID`: Base entity / sentence group (disjoint across splits)
- `split`: `"development"` or `"holdout"`
- `languages`: Array of relevant language codes (e.g. `["en", "uk"]`)
- `category`: Strata label (e.g. `single-word`, `capitalized`, `code-token`, `acronym`, `ambiguous-short`, etc.)
- `label`: Target behavior (`repair`, `preserve`, or `abstain`)
- `provenance`: Synthetic generation metadata with `"review": "pending-human"`
- `initial`: Starting editor state (sourceID, language, text, caretUTF16, preferredCyrillic, keyboardType)
- `events`: Array of physical key and boundary events (keyCode, modifiers, rendered)
- `expected`: Target outcome (text, language, sourceID, allowedAutomaticActions, checkpoints)

## Deterministic Rendering

Events are rendered using the frozen layout tables in `Benchmarks/layout-tables/v1/`. The `rendered` field in each event is verified against the table output for the given keyCode and modifiers.