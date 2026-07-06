<div align="center">

# mojo-url

**URL parsing, building, and encoding in pure Mojo — a urllib.parse mirror.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Mojo](https://img.shields.io/badge/Mojo-1.0.0b3%2B_nightly-orange?style=flat-square)](https://mojolang.org)
[![Podcast](https://img.shields.io/badge/Podcast-Chain_of_Thought-purple?style=flat-square)](https://chainofthought.show)
[![X](https://img.shields.io/badge/X-@ConorBronsdon-black?style=flat-square&logo=x)](https://x.com/ConorBronsdon)

<img src="docs/social-preview.png" width="800">

<img src="docs/demo.gif" width="800">

</div>

`urllib.parse` is the module every Python dev reaches for to parse a URL,
split out its host and query string, and rebuild it with a parameter
changed. As of mid-2026 the Mojo ecosystem has no equivalent, so mojo-url
fills that gap: same function names, same arguments, byte-for-byte
matching output, so a Python developer can pick it up without a second
manual.

### Coming from Python

If you know Python's `urllib.parse`, the names line up almost exactly:

| Python (`urllib.parse`)             | mojo-url                              |
| ----------------------------------- | ------------------------------------- |
| `r = urlparse(url)`                 | `var r = urlparse(url)`               |
| `r.scheme` / `r.netloc` / `r.path`  | `r.scheme` / `r.netloc` / `r.path`    |
| `parse_qsl(r.query)`                | `parse_qsl(r.query)`                  |
| `quote(s)` / `unquote(s)`           | `quote(s)` / `unquote(s)`             |
| `urljoin(base, rel)`                | `urljoin(base, rel)`                  |

One shape difference: `urlencode` takes a `List[QueryPair]` here (not a dict),
so build pairs with `QueryPair(key, value)` and pass the list to
`urlencode(pairs)`.

## What it handles

- **`urlparse` / `urlunparse`**: the six-component split
  (`scheme://netloc/path;params?query#fragment`), with netloc-derived
  `username()`, `password()`, `hostname()`, and `port()` accessors.
  IPv6 literals (`[::1]`), IPv6 zone IDs, userinfo, and non-numeric or
  absent ports are all handled the way CPython's `urlsplit` handles them.
- **`quote` / `quote_plus` / `unquote` / `unquote_plus`**: RFC 3986
  percent-encoding, UTF-8 aware in both directions, with invalid `%XX`
  sequences recovered as U+FFFD on decode (`errors="replace"`) and the
  `/`-safe-by-default vs. `+`-for-space conventions of `quote` and
  `quote_plus` kept distinct.
- **`urlencode` / `parse_qs` / `parse_qsl`**: build a query string from
  pairs, or parse one back into ordered pairs or a `{key: [values...]}`
  grouping, with repeated keys and blank-value dropping matching
  `urllib.parse` defaults.
- **`urljoin`**: the full RFC 3986 Section 5 reference-resolution
  algorithm ("Transform References" plus "Remove Dot Segments"), passing
  the canonical Section 5.4 conformance table 41/41.

## What it deliberately does NOT do

- **WHATWG-URL normalization or validation.** This mirrors `urllib.parse`
  semantics, not the browser URL Standard: no host normalization, no
  idna, no scheme-specific validation beyond what `urllib.parse` itself
  does.
- **Return `(key, value)` tuples from query parsing.** `parse_qsl`
  returns `List[QueryPair]` instead, because Mojo's `List` can't hold
  Python-style anonymous tuples; `QueryPair` has the same `.key`/`.value`
  fields a tuple unpack would give you.
- **Loosen `urljoin`'s scheme check.** A reference with a scheme
  (`g:h`) is always treated as absolute per RFC 3986, matching CPython
  on the conformance suite; there's no "guess it's actually relative"
  fallback some browsers apply.

## Install

With [pixi](https://pixi.prefix.dev):

```bash
pixi install
pixi run test
pixi run demo
```

Or with uv:

```bash
uv venv
uv pip install mojo --index https://whl.modular.com/nightly/simple/ --prerelease allow
.venv/bin/mojo run -I src test/test_url.mojo
```

Requires a Mojo nightly (`>=1.0.0b3`).

## Usage

```mojo
from url import (
    urlparse, urlunparse, quote, quote_plus, unquote, unquote_plus,
    urlencode, parse_qs, parse_qsl, urljoin, ParseResult, QueryPair,
)

def main() raises:
    var r = urlparse(String("https://user:pass@host.example.com:8080/a/b?c=d#e"))
    print(r.scheme, r.hostname(), r.port())   # https host.example.com 8080

    print(quote(String("café / a")))          # caf%C3%A9%20/%20a
    print(unquote(String("caf%C3%A9")))       # café

    var grouped = parse_qs(String("a=1&a=2&b=3"))
    print(grouped["a"])                       # [1, 2]

    print(urljoin(String("http://a/b/c/d;p?q"), String("../../g")))  # http://a/g
```

## Tests

```bash
pixi run fixtures   # regenerate test/data/fixtures.txt from CPython
pixi run test
```

38 tests: hand-written behavioral checks per function, the RFC 3986
Section 5.4 conformance table (41/41), and a fixture harness that
byte-matches all 161 `urllib.parse` fixtures generated fresh from
CPython. `test/fuzz_runner.mojo` is the robustness target: 600 mutated
inputs through `urlparse`/`urlunparse` and both quote/unquote pairs,
zero crashes and zero hangs.

## Part of a pure-Mojo library suite

Eleven pure-Mojo libraries that mirror familiar Python stdlib and PyPI APIs,
filling gaps in the native Mojo ecosystem:

- [mojo-xml](https://github.com/conorbronsdon/mojo-xml) — general-purpose XML
  parsing, an ElementTree-shaped DOM (Python's `xml.etree.ElementTree`)
- [mojo-feed](https://github.com/conorbronsdon/mojo-feed) — RSS, Atom, and
  JSON Feed parsing (Python's `feedparser`)
- [mojo-captions](https://github.com/conorbronsdon/mojo-captions) — SRT and
  WebVTT subtitle/transcript parsing (no Python stdlib parallel)
- [mojo-html](https://github.com/conorbronsdon/mojo-html) — HTML parsing and
  article extraction (Python's readability)
- [mojo-markdown](https://github.com/conorbronsdon/mojo-markdown) —
  CommonMark markdown parsing (Python's `markdown`)
- [mojo-unicodedata](https://github.com/conorbronsdon/mojo-unicodedata) —
  Unicode normalization and case folding (Python's `unicodedata`)
- [mojo-diff](https://github.com/conorbronsdon/mojo-diff) — text diffing
  (Python's `difflib`)
- [mojo-template](https://github.com/conorbronsdon/mojo-template) — a
  Jinja-flavored template engine (Python's `jinja2`)
- [mojo-tar](https://github.com/conorbronsdon/mojo-tar) — tar archive
  reading and writing (Python's `tarfile`)
- [mojo-redis](https://github.com/conorbronsdon/mojo-redis) — a Redis
  client (Python's `redis-py`)

## Contributing

Issues and PRs welcome, especially real-world URLs that parse differently
than `urllib.parse` (attach the URL) and `urljoin` edge cases outside the
RFC 3986 table. Run `pixi run test` before sending a PR.

## About

Built by [Conor Bronsdon](https://conorbronsdon.com) — host of
[Chain of Thought](https://chainofthought.show), a podcast about AI agents,
infrastructure, and engineering. This library exists because every other
tool in this suite eventually needs to parse a feed link, rewrite a query
parameter, or resolve a relative URL. Find me on
[X](https://x.com/ConorBronsdon) or
[LinkedIn](https://www.linkedin.com/in/conorbronsdon).


---

## Disclaimer

*All views, opinions, and statements expressed on this account/in this repo are solely my own and are made in my personal capacity. They do not reflect, and should not be construed as reflecting, the views, positions, or policies of Modular. This account is not affiliated with, authorized by, or endorsed by my employer in any way.*

## License

Licensed under the [MIT License](LICENSE).
