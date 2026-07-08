# Changelog

## Unreleased

- New `url.errors` module — the position-aware parse-error pattern shared
  across the mojo-* parser suite: `line_col` maps a byte offset in a
  source buffer to a 1-based (line, byte-column) pair, and `parse_error`
  builds an `Error` reading `<msg> at line <L>, column <C>: '<snippet>'`
  with a whitespace-trimmed, ~30-byte, UTF-8-safe snippet of the
  offending line. Exported as `url.line_col` / `url.parse_error`.
  The library itself mirrors `urllib.parse`'s permissive behavior and has
  no raising parse paths today, so no existing messages changed; the
  helpers are ready for future strict/validating APIs. 21 new unit tests
  in `test/test_errors.mojo` cover every documented edge case.

## 0.1.0 — 2026-07-05

Initial release. A pure-Mojo mirror of Python's `urllib.parse`:

- `urlparse` / `urlunparse` — six-component split
  (`scheme://netloc/path;params?query#fragment`) with netloc-derived
  `username` / `password` / `hostname` / `port` accessors, IPv6 and zone-id
  handling, scheme lowercasing, and CPython's control-char stripping.
- `quote` / `quote_plus` / `unquote` / `unquote_plus` — RFC 3986
  percent-encoding, UTF-8 aware, with `errors="replace"` decoding of
  invalid sequences and `+`/`%20` space conventions.
- `urlencode` / `parse_qs` / `parse_qsl` — query-string build and parse,
  handling repeated keys, blank-value dropping, and `+` decoding.
- `urljoin` — the full RFC 3986 Section 5 reference-resolution algorithm
  ("Transform References" plus "Remove Dot Segments").

Correctness is anchored to CPython: `test/data/gen_fixtures.py` emits the
exact output of `urllib.parse` for a spread of inputs, and the test suite
byte-matches all 161 fixtures. `urljoin` passes the full RFC 3986
Section 5.4 conformance table, 41/41. 38 tests total; fuzz-tested against
600 mutated inputs with zero crashes and zero hangs.
