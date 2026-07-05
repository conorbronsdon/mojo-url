"""mojo-url: URL parsing, building, and percent/query-string encoding.

A pure-Mojo mirror of Python's `urllib.parse` — same function names, same
byte-for-byte output — with an RFC 3986 Section 5 conformant `urljoin`.
"""

from url.model import ParseResult, QueryPair
from url.parse import (
    urlparse,
    urlunparse,
    quote,
    quote_plus,
    unquote,
    unquote_plus,
    urlencode,
    parse_qs,
    parse_qsl,
    urljoin,
)
