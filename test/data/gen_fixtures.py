#!/usr/bin/env python3
"""Generate correctness fixtures from Python's stdlib urllib.parse.

Emits `fixtures.txt`: a line-oriented, tab-separated file the Mojo test
suite reads and byte-matches against. Every expected value here is
exactly what CPython's urllib.parse produces, so the Mojo library's job
is to reproduce these bytes.

Record format (fields tab-separated, one record per line):

    urlparse   <url>   <scheme>|<netloc>|<path>|<params>|<query>|<fragment>|<username>|<password>|<hostname>|<port>
    urlunparse <scheme>|<netloc>|<path>|<params>|<query>|<fragment>   <result>
    quote      <safe>  <input>   <output>
    quote_plus <input> <output>
    unquote    <input> <output>
    unquote_plus <input> <output>
    urlencode  <k1=v1;k2=v2;...>   <output>          (pairs ';'-joined, k/v raw)
    parse_qsl  <query>  <k1=v1|k2=v2|...>            ('|'-joined, empty => "")
    urljoin    <base>   <ref>   <result>

Values that could contain a tab or newline are not used in fixtures.
Empty optional fields (username/password/hostname/port) render as the
empty string; port renders as its integer or "" when None.
"""

import sys
import urllib.parse as up

SEP = "\t"


def esc(s):
    # Fixtures are line-oriented; forbid embedded control chars in inputs.
    assert "\t" not in s and "\n" not in s and "\r" not in s, repr(s)
    return s


def emit(out, *fields):
    out.write(SEP.join(esc(f) for f in fields))
    out.write("\n")


def port_str(p):
    return "" if p is None else str(p)


def rec_urlparse(out, url):
    r = up.urlparse(url)
    packed = "|".join([
        r.scheme, r.netloc, r.path, r.params, r.query, r.fragment,
        r.username or "", r.password or "", r.hostname or "", port_str(r.port),
    ])
    emit(out, "urlparse", url, packed)


def rec_urlunparse(out, parts):
    # parts: (scheme, netloc, path, params, query, fragment)
    res = up.urlunparse(parts)
    packed = "|".join(parts)
    emit(out, "urlunparse", packed, res)


def rec_quote(out, s, safe):
    emit(out, "quote", safe, s, up.quote(s, safe=safe))


def rec_quote_plus(out, s):
    emit(out, "quote_plus", s, up.quote_plus(s))


def rec_unquote(out, s):
    emit(out, "unquote", s, up.unquote(s))


def rec_unquote_plus(out, s):
    emit(out, "unquote_plus", s, up.unquote_plus(s))


def rec_urlencode(out, pairs):
    packed_in = ";".join(f"{k}={v}" for k, v in pairs)
    emit(out, "urlencode", packed_in, up.urlencode(pairs))


def rec_parse_qsl(out, query):
    pairs = up.parse_qsl(query)
    packed = "|".join(f"{k}={v}" for k, v in pairs)
    emit(out, "parse_qsl", query, packed)


def rec_urljoin(out, base, ref):
    emit(out, "urljoin", base, ref, up.urljoin(base, ref))


# RFC 3986 Section 5.4 reference-resolution examples. Base is fixed.
RFC3986_BASE = "http://a/b/c/d;p?q"

RFC3986_NORMAL = [
    ("g:h", "g:h"),
    ("g", "http://a/b/c/g"),
    ("./g", "http://a/b/c/g"),
    ("g/", "http://a/b/c/g/"),
    ("/g", "http://a/g"),
    ("//g", "http://g"),
    ("?y", "http://a/b/c/d;p?y"),
    ("g?y", "http://a/b/c/g?y"),
    ("#s", "http://a/b/c/d;p?q#s"),
    ("g#s", "http://a/b/c/g#s"),
    ("g?y#s", "http://a/b/c/g?y#s"),
    (";x", "http://a/b/c/;x"),
    ("g;x", "http://a/b/c/g;x"),
    ("g;x?y#s", "http://a/b/c/g;x?y#s"),
    ("", "http://a/b/c/d;p?q"),
    (".", "http://a/b/c/"),
    ("./", "http://a/b/c/"),
    ("..", "http://a/b/"),
    ("../", "http://a/b/"),
    ("../g", "http://a/b/g"),
    ("../..", "http://a/"),
    ("../../", "http://a/"),
    ("../../g", "http://a/g"),
]

RFC3986_ABNORMAL = [
    ("../../../g", "http://a/g"),
    ("../../../../g", "http://a/g"),
    ("/./g", "http://a/g"),
    ("/../g", "http://a/g"),
    ("g.", "http://a/b/c/g."),
    (".g", "http://a/b/c/.g"),
    ("g..", "http://a/b/c/g.."),
    ("..g", "http://a/b/c/..g"),
    ("./../g", "http://a/b/g"),
    ("./g/.", "http://a/b/c/g/"),
    ("g/./h", "http://a/b/c/g/h"),
    ("g/../h", "http://a/b/c/h"),
    ("g;x=1/./y", "http://a/b/c/g;x=1/y"),
    ("g;x=1/../y", "http://a/b/c/y"),
    ("g?y/./x", "http://a/b/c/g?y/./x"),
    ("g?y/../x", "http://a/b/c/g?y/../x"),
    ("g#s/./x", "http://a/b/c/g#s/./x"),
    ("g#s/../x", "http://a/b/c/g#s/../x"),
]


def main():
    out = sys.stdout

    # ---- urlparse ----
    urlparse_inputs = [
        "http://www.example.com/path;params?query=1#frag",
        "https://user:pass@host.example.com:8080/a/b?c=d#e",
        "http://[::1]:8080/path",
        "http://[2001:db8::1]/",
        "//netloc/path",
        "path/only",
        "/absolute/path",
        "scheme:opaque",
        "http://host",
        "http://host/",
        "",
        "#fragonly",
        "?queryonly",
        ";paramsonly",
        "HTTP://Example.COM/Path",
        "http://user@host",
        "http://:pass@host",
        "ftp://ftp.example.com/file.txt",
        "mailto:user@example.com",
        "http://host:80/p?a=b&c=d",
        "http://host/p;q=1;r=2?x#y",
        "https://a.b.c/d/e/f?g=h;i=j#k",
        "http://192.168.0.1:3000/x",
        "http://[fe80::1%25eth0]:80/",
        "urn:isbn:0451450523",
        "news:comp.infosystems",
        "http://host/path?a=1&a=2&b=3",
    ]
    for u in urlparse_inputs:
        rec_urlparse(out, u)

    # ---- urlunparse (round-trip components) ----
    urlunparse_inputs = [
        ("http", "www.example.com", "/path", "params", "query=1", "frag"),
        ("https", "user:pass@host:8080", "/a/b", "", "c=d", "e"),
        ("http", "[::1]:8080", "/path", "", "", ""),
        ("", "netloc", "/path", "", "", ""),
        ("", "", "path/only", "", "", ""),
        ("scheme", "", "opaque", "", "", ""),
        ("http", "host", "", "", "", ""),
        ("mailto", "", "user@example.com", "", "", ""),
        ("http", "host", "/p", "", "a=b&c=d", ""),
        ("http", "host", "/p", "q=1", "x", "y"),
    ]
    for parts in urlunparse_inputs:
        rec_urlunparse(out, parts)

    # ---- quote ----
    quote_inputs = [
        ("hello world", "/"),
        ("café", "/"),
        ("a/b/c", "/"),
        ("a/b/c", ""),
        ("100% sure", "/"),
        ("path with spaces/and/slashes", "/"),
        ("~user/file.txt", "/"),
        ("a+b=c&d", "/"),
        ("safe-._~", "/"),
        ("Ünïcödé", "/"),
        ("日本語", "/"),
        ("emoji😀here", "/"),
        ("!*'();:@&=+$,/?#[]", "/"),
        ("!*'();:@&=+$,/?#[]", "/:@"),
        ("", "/"),
        ("AZaz09", "/"),
        ("tab\tless", "/"),  # will assert-fail; removed below
    ]
    # Drop any input with control chars (fixtures are line-oriented).
    quote_inputs = [(s, sf) for (s, sf) in quote_inputs if "\t" not in s]
    for s, safe in quote_inputs:
        rec_quote(out, s, safe)

    # ---- quote_plus ----
    quote_plus_inputs = [
        "hello world",
        "café au lait",
        "a b c",
        "a+b",
        "key=value&other=thing",
        "100% done",
        "日本語 test",
        "path/with/slash",
        "",
        "no_encoding_needed",
    ]
    for s in quote_plus_inputs:
        rec_quote_plus(out, s)

    # ---- unquote ----
    unquote_inputs = [
        "hello%20world",
        "caf%C3%A9",
        "%E6%97%A5%E6%9C%AC%E8%AA%9E",
        "100%25%20sure",
        "no_encoding",
        "a%2Fb%2Fc",
        "%41%42%43",
        "incomplete%2",
        "incomplete%",
        "bad%zzhex",
        "%C3%28",          # invalid UTF-8 (lone continuation) -> replace
        "trailing%",
        "mixed%20and%2Bplus",
        "%F0%9F%98%80",    # emoji
        "plus+stays+plus",
        "",
        "%2500",
    ]
    for s in unquote_inputs:
        rec_unquote(out, s)

    # ---- unquote_plus ----
    unquote_plus_inputs = [
        "hello+world",
        "caf%C3%A9+bar",
        "a+b+c",
        "100%25+done",
        "no+change%20here",
        "%2Bliteral+plus",
        "",
        "plus+and%20space",
    ]
    for s in unquote_plus_inputs:
        rec_unquote_plus(out, s)

    # ---- urlencode ----
    urlencode_inputs = [
        [("a", "1"), ("b", "2")],
        [("q", "hello world"), ("lang", "en")],
        [("name", "café"), ("city", "São Paulo")],
        [("k", "a+b"), ("x", "c&d")],
        [("empty", ""), ("full", "value")],
        [("repeated", "1"), ("repeated", "2")],
        [("special", "!*'()")],
        [("unicode", "日本語")],
    ]
    for pairs in urlencode_inputs:
        rec_urlencode(out, pairs)

    # ---- parse_qsl ----
    parse_qsl_inputs = [
        "a=1&b=2",
        "a=1&a=2&b=3",
        "q=hello+world&lang=en",
        "name=caf%C3%A9",
        "flag&other=x",       # blank value dropped by default
        "x=&y=2",             # explicit empty value kept
        "a=1;b=2",            # ';' not a separator by default in modern py
        "",
        "onlykey",
        "k=a%26b",
        "space=a+b+c",
        "eq=a=b=c",
    ]
    for q in parse_qsl_inputs:
        rec_parse_qsl(out, q)

    # ---- urljoin: RFC 3986 tables ----
    for ref, _expected in RFC3986_NORMAL:
        rec_urljoin(out, RFC3986_BASE, ref)
    for ref, _expected in RFC3986_ABNORMAL:
        rec_urljoin(out, RFC3986_BASE, ref)

    # ---- urljoin: extra practical cases ----
    urljoin_extra = [
        ("http://a/b/c/d;p?q", "https://other/x"),
        ("http://example.com/dir/page.html", "sibling.html"),
        ("http://example.com/dir/page.html", "../up.html"),
        ("http://example.com/dir/page.html", "/root.html"),
        ("http://example.com/dir/page.html", "//cdn.example.com/lib.js"),
        ("http://example.com/dir/page.html", "?newquery"),
        ("http://example.com/dir/page.html", "#frag"),
        ("http://example.com/dir/", "sub/page.html"),
        ("http://example.com", "path"),
        ("http://example.com/a/b", ""),
        ("http://example.com/a/b/c", "../../x"),
        ("http://example.com/a/b/c", "./d/./e"),
    ]
    for base, ref in urljoin_extra:
        rec_urljoin(out, base, ref)


if __name__ == "__main__":
    main()
