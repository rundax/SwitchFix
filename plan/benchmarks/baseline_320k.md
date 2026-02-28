# Baseline 320K (Current Text-Fallback Path)

Date: 2026-02-26
Environment: local debug run via `swift run TestRunner`

## Measurements

- cold load time (`uk_UA`): `27615.37 ms`
- warm load time: not captured in this run
- RSS before load: `63.20 MB`
- RSS after load: `28.89 MB`
- exact lookup latency: `avg 0.0138 ms`, `p95 0.0243 ms`, `p99 0.1751 ms`

## Notes

- This baseline was measured on text dictionary fallback (`.txt`) in TestRunner.
- Release app builds now package `.bin` dictionaries via `scripts/build-app.sh`, so runtime numbers are expected to improve in production path.
