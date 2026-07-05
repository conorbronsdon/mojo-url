# Security Policy

mojo-url is a pure-Mojo URL parsing and encoding library with no network
access, no authentication, and no secrets handling — it takes a URL or
query string and returns structured data (or the reverse). The main risk
surface is malformed or adversarial input causing a crash or hang, which
the fuzz target (`test/fuzz_runner.mojo`) specifically exercises.

A related class of concern for any URL library is parsing *differentials* —
splitting a URL differently than the consumer expects (host confusion,
scheme confusion), which can enable SSRF or access-control bypass in code
that trusts the parse. mojo-url deliberately matches CPython's
`urllib.parse` semantics byte-for-byte (verified by the fixture suite) so
its behavior is predictable and auditable, but it does **not** perform
WHATWG-URL normalization or validation. Do not rely on it alone for
security decisions about untrusted URLs.

If you find an input that crashes, hangs, or parses in a way that looks
security-relevant (out-of-bounds access, unbounded memory growth, or a
dangerous divergence from `urllib.parse`), please report it via a
[GitHub issue](https://github.com/conorbronsdon/mojo-url/issues),
including the offending input or a minimal reproduction.

This is a personal open-source project maintained on a best-effort
basis — there's no formal SLA for response time, but reports are welcome
and taken seriously.
