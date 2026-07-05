"""Fuzz target: exercise the parser on argv[1]; raising is fine, crashing is not.

Round-trips the input through `urlparse`/`urlunparse` and through
`quote`/`unquote` and `quote_plus`/`unquote_plus`, printing what it
found. The point is robustness: any input — however malformed — must
terminate without crashing or hanging.
"""

from std.sys import argv

from url import urlparse, urlunparse, quote, unquote, quote_plus, unquote_plus


def main():
    try:
        var raw = open(String(argv()[1]), "r").read()
        var r = urlparse(raw)
        var rebuilt = urlunparse(r)
        print("scheme:", r.scheme, "netloc:", r.netloc, "path:", r.path)
        print("host:", r.hostname(), "port:", r.port())
        print("unparse:", rebuilt)
        # Encode/decode round-trips must not crash on arbitrary bytes.
        var q = quote(raw)
        print("quote->unquote stable:", unquote(q) == raw)
        var qp = quote_plus(raw)
        print("quote_plus->unquote_plus stable:", unquote_plus(qp) == raw)
    except e:
        print("raised:", e)
