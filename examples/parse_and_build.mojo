"""Parse a URL, inspect its parts, tweak the query string, and rebuild it.

The everyday round-trip this library exists for: split a URL, read the
host/port/query, edit a parameter, and recompose a valid URL.

Usage:
    mojo run -I src examples/parse_and_build.mojo "https://user@host:8443/a/b?x=1&y=2#top"
"""

from std.sys import argv

from url import (
    urlparse,
    urlunparse,
    parse_qsl,
    urlencode,
    urljoin,
    ParseResult,
    QueryPair,
)


def main() raises:
    var args = argv()
    var url: String
    if len(args) > 1:
        url = String(args[1])
    else:
        url = String("https://user@host.example.com:8443/a/b?x=1&y=2#top")

    var r = urlparse(url)
    print("URL:      ", url)
    print("scheme:   ", r.scheme)
    print("netloc:   ", r.netloc)
    print("username: ", r.username())
    print("hostname: ", r.hostname())
    print("port:     ", r.port())
    print("path:     ", r.path)
    print("query:    ", r.query)
    print("fragment: ", r.fragment)

    print()
    print("query parameters:")
    for pair in parse_qsl(r.query):
        print(t"    {pair.key} = {pair.value}")

    # Add a parameter and rebuild the query string.
    var pairs = parse_qsl(r.query)
    pairs.append(QueryPair(String("added"), String("hello world")))
    var new_query = urlencode(pairs)
    var rebuilt = urlunparse(
        ParseResult(
            r.scheme.copy(),
            r.netloc.copy(),
            r.path.copy(),
            r.params.copy(),
            new_query^,
            r.fragment.copy(),
        )
    )
    print()
    print("rebuilt:  ", rebuilt)

    # Resolve a relative reference against the original URL.
    print("join ../c:", urljoin(url, String("../c/other.html")))
