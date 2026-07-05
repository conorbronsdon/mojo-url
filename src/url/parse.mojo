"""URL parsing, building, percent-encoding, and query-string handling.

A pure-Mojo port of the daily-driver surface of Python's
`urllib.parse`, named the same so the functions read identically:
`urlparse`/`urlunparse`, `quote`/`quote_plus`/`unquote`/`unquote_plus`,
`urlencode`/`parse_qs`/`parse_qsl`, and `urljoin`.

Component-split and encoding behavior are matched byte-for-byte against
CPython's `urllib.parse` via the fixtures in `test/data/fixtures.txt`.
`urljoin` implements the RFC 3986 Section 5 reference-resolution
algorithm ("Transform References" plus "Remove Dot Segments") and passes
the full RFC 3986 Section 5.4 conformance table.
"""

from url.model import ParseResult, QueryPair


comptime _HEX_UPPER = "0123456789ABCDEF"


def _uses_params(scheme: String) -> Bool:
    """Schemes for which urlparse splits `;params` off the path (CPython)."""
    var s = scheme
    return (
        s == "" or s == "ftp" or s == "hdl" or s == "prospero" or s == "http"
        or s == "imap" or s == "https" or s == "shttp" or s == "rtsp"
        or s == "rtsps" or s == "rtspu" or s == "sip" or s == "sips"
        or s == "mms" or s == "sftp" or s == "tel"
    )


def _uses_netloc(scheme: String) -> Bool:
    """Schemes for which urlunsplit synthesizes a `//` authority (CPython)."""
    var s = scheme
    return (
        s == "" or s == "ftp" or s == "http" or s == "gopher" or s == "nntp"
        or s == "telnet" or s == "imap" or s == "wais" or s == "file"
        or s == "mms" or s == "https" or s == "shttp" or s == "snews"
        or s == "prospero" or s == "rtsp" or s == "rtsps" or s == "rtspu"
        or s == "rsync" or s == "svn" or s == "svn+ssh" or s == "sftp"
        or s == "nfs" or s == "git" or s == "git+ssh" or s == "ws"
        or s == "wss"
    )


# ---------------------------------------------------------------------------
# Small byte helpers
# ---------------------------------------------------------------------------


def _sub(s: String, start: Int, end: Int) -> String:
    """`s[start:end]` on byte offsets (no String slice syntax in Mojo)."""
    return String(StringSlice(unsafe_from_utf8=s.as_bytes()[start:end]))


def _from(s: String, start: Int) -> String:
    """`s[start:]` on byte offsets."""
    return String(StringSlice(unsafe_from_utf8=s.as_bytes()[start:]))


def _is_alpha(b: UInt8) -> Bool:
    return (b >= UInt8(ord("a")) and b <= UInt8(ord("z"))) or (
        b >= UInt8(ord("A")) and b <= UInt8(ord("Z"))
    )


def _is_digit(b: UInt8) -> Bool:
    return b >= UInt8(ord("0")) and b <= UInt8(ord("9"))


def _is_scheme_char(b: UInt8) -> Bool:
    return (
        _is_alpha(b)
        or _is_digit(b)
        or b == UInt8(ord("+"))
        or b == UInt8(ord("-"))
        or b == UInt8(ord("."))
    )


def _is_hex(b: UInt8) -> Bool:
    return (
        _is_digit(b)
        or (b >= UInt8(ord("a")) and b <= UInt8(ord("f")))
        or (b >= UInt8(ord("A")) and b <= UInt8(ord("F")))
    )


def _hex_val(b: UInt8) -> Int:
    if _is_digit(b):
        return Int(b) - ord("0")
    if b >= UInt8(ord("a")) and b <= UInt8(ord("f")):
        return Int(b) - ord("a") + 10
    return Int(b) - ord("A") + 10


def _utf8_lossy(data: Span[UInt8, _]) -> String:
    """Decode bytes as UTF-8, emitting U+FFFD for invalid sequences.

    Matches Python's `errors="replace"` behavior for the sequences the
    fixtures exercise (e.g. a lead byte followed by a non-continuation).
    """
    var out = String()
    var i = 0
    var n = len(data)
    while i < n:
        var b = data[i]
        if b < 0x80:
            var run_start = i
            while i < n and data[i] < 0x80:
                i += 1
            out += String(StringSlice(unsafe_from_utf8=data[run_start:i]))
            continue
        var seq_len = 0
        var cp = 0
        if b >= 0xC2 and b <= 0xDF:
            seq_len = 2
            cp = Int(b) & 0x1F
        elif b >= 0xE0 and b <= 0xEF:
            seq_len = 3
            cp = Int(b) & 0x0F
        elif b >= 0xF0 and b <= 0xF4:
            seq_len = 4
            cp = Int(b) & 0x07
        if seq_len == 0 or i + seq_len > n:
            out += "�"
            i += 1
            continue
        var ok = True
        for k in range(1, seq_len):
            var c = data[i + k]
            if c < 0x80 or c > 0xBF:
                ok = False
                break
            cp = (cp << 6) | (Int(c) & 0x3F)
        if not ok or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
            out += "�"
            i += 1
            continue
        out += String(StringSlice(unsafe_from_utf8=data[i : i + seq_len]))
        i += seq_len
    return out^


# ---------------------------------------------------------------------------
# Percent-encoding
# ---------------------------------------------------------------------------


def _is_always_safe(b: UInt8) -> Bool:
    """The characters percent-encoding never escapes (Python's `_ALWAYS_SAFE`)."""
    return (
        _is_alpha(b)
        or _is_digit(b)
        or b == UInt8(ord("_"))
        or b == UInt8(ord("."))
        or b == UInt8(ord("-"))
        or b == UInt8(ord("~"))
    )


def _byte_in(s: String, b: UInt8) -> Bool:
    for x in s.as_bytes():
        if x == b:
            return True
    return False


def _pct_byte(mut out: String, b: UInt8):
    out += "%"
    out += String(_HEX_UPPER[byte = Int(b >> 4)])
    out += String(_HEX_UPPER[byte = Int(b & 0xF)])


def quote(string: String, safe: String = "/") -> String:
    """Percent-encode `string` (RFC 3986), leaving `safe` chars unescaped.

    Always-unreserved characters (`A-Z a-z 0-9 _ . - ~`) are never
    escaped; `safe` (default `/`) adds more. Every other byte of the
    UTF-8 encoding becomes `%XX` with uppercase hex, exactly as
    `urllib.parse.quote`.
    """
    var out = String()
    var bytes = string.as_bytes()
    for i in range(len(bytes)):
        var b = bytes[i]
        if _is_always_safe(b) or _byte_in(safe, b):
            out += String(StringSlice(unsafe_from_utf8=bytes[i : i + 1]))
        else:
            _pct_byte(out, b)
    return out^


def quote_plus(string: String, safe: String = "") -> String:
    """Like `quote`, but encode space as `+` (`application/x-www-form`).

    `/` is *not* safe here (matching `urllib.parse.quote_plus`, whose
    default `safe` is empty), so a space becomes `+` and everything else
    unreserved-or-`safe` stays literal.
    """
    var out = String()
    var bytes = string.as_bytes()
    for i in range(len(bytes)):
        var b = bytes[i]
        if b == UInt8(ord(" ")):
            out += "+"
        elif _is_always_safe(b) or _byte_in(safe, b):
            out += String(StringSlice(unsafe_from_utf8=bytes[i : i + 1]))
        else:
            _pct_byte(out, b)
    return out^


def _is_escape_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    return (
        i + 2 < len(bytes)
        and bytes[i] == UInt8(ord("%"))
        and _is_hex(bytes[i + 1])
        and _is_hex(bytes[i + 2])
    )


def unquote(string: String) -> String:
    """Decode `%XX` escapes (UTF-8 aware) back to text.

    Runs of consecutive `%XX` bytes are decoded together as UTF-8 with
    invalid sequences replaced by U+FFFD (Python's `errors="replace"`);
    a `%` that is not followed by two hex digits passes through
    literally. `+` is left as-is (use `unquote_plus` for form data).
    """
    var bytes = string.as_bytes()
    var n = len(bytes)
    if string.find("%") == -1:
        return string.copy()
    var out = String()
    var pending = List[UInt8]()
    var i = 0
    while i < n:
        if _is_escape_at(bytes, i):
            pending.append(
                UInt8(_hex_val(bytes[i + 1]) * 16 + _hex_val(bytes[i + 2]))
            )
            i += 3
            continue
        if len(pending) > 0:
            out += _utf8_lossy(Span(pending))
            pending.clear()
        var run_start = i
        while i < n and not _is_escape_at(bytes, i):
            i += 1
        out += String(StringSlice(unsafe_from_utf8=bytes[run_start:i]))
    if len(pending) > 0:
        out += _utf8_lossy(Span(pending))
    return out^


def unquote_plus(string: String) -> String:
    """Decode form-encoded text: `+` becomes space, then `%XX` decoding."""
    var swapped = String()
    var bytes = string.as_bytes()
    for i in range(len(bytes)):
        if bytes[i] == UInt8(ord("+")):
            swapped += " "
        else:
            swapped += String(StringSlice(unsafe_from_utf8=bytes[i : i + 1]))
    return unquote(swapped)


# ---------------------------------------------------------------------------
# urlparse / urlunparse
# ---------------------------------------------------------------------------


def _remove_unsafe(string: String) -> String:
    """Strip leading C0-control-or-space and remove all tab/CR/LF (Python)."""
    var bytes = string.as_bytes()
    var n = len(bytes)
    var start = 0
    while start < n and bytes[start] <= 0x20:
        start += 1
    var out = String()
    for i in range(start, n):
        var b = bytes[i]
        if b == 0x09 or b == 0x0A or b == 0x0D:
            continue
        out += String(StringSlice(unsafe_from_utf8=bytes[i : i + 1]))
    return out^


def _netloc_end(url: String, start: Int) -> Int:
    """Byte offset where a `//`-authority ends (first of /?# or end)."""
    var delim = url.byte_length()
    for c in [String("/"), String("?"), String("#")]:
        var idx = url.find(c, start)
        if idx != -1 and idx < delim:
            delim = idx
    return delim


def urlparse(url: String) -> ParseResult:
    """Split a URL into its six components, mirroring `urllib.parse.urlparse`.

    Follows CPython's `urlsplit` (leading control/space stripped, tab/CR/LF
    removed, ASCII-alpha-led scheme lowercased, `//netloc` recognized,
    `#fragment` and `?query` peeled off) and then splits `;params` from
    the last path segment for schemes that use params.
    """
    var work = _remove_unsafe(url)
    var scheme = String()
    var netloc = String()
    var query = String()
    var fragment = String()

    # Scheme: alpha-led run of scheme chars followed by ':'.
    var colon = work.find(":")
    if colon > 0 and _is_alpha(work.as_bytes()[0]):
        var all_scheme = True
        for k in range(colon):
            if not _is_scheme_char(work.as_bytes()[k]):
                all_scheme = False
                break
        if all_scheme:
            scheme = _sub(work, 0, colon).lower()
            work = _from(work, colon + 1)

    # Authority.
    if work.startswith("//"):
        var end = _netloc_end(work, 2)
        netloc = _sub(work, 2, end)
        work = _from(work, end)

    # Fragment then query.
    var hash_idx = work.find("#")
    if hash_idx != -1:
        fragment = _from(work, hash_idx + 1)
        work = _sub(work, 0, hash_idx)
    var q_idx = work.find("?")
    if q_idx != -1:
        query = _from(work, q_idx + 1)
        work = _sub(work, 0, q_idx)

    # Params: only for schemes in _USES_PARAMS, split from the last segment.
    var params = String()
    if _uses_params(scheme) and work.find(";") != -1:
        var slash = work.rfind("/")
        var semi: Int
        if slash != -1:
            semi = work.find(";", slash)
        else:
            semi = work.find(";")
        if semi != -1:
            params = _from(work, semi + 1)
            work = _sub(work, 0, semi)

    return ParseResult(
        scheme^, netloc^, work^, params^, query^, fragment^
    )


def urlunparse(components: ParseResult) -> String:
    """Recompose a `ParseResult` into a URL string (`urllib`-compatible).

    Round-trips `urlparse`: re-attaches `;params`, synthesizes `//netloc`
    when a netloc is present (or the scheme uses one), and prefixes an
    absolute path onto a synthesized authority as CPython's `urlunsplit`
    does.
    """
    var scheme = components.scheme
    var netloc = components.netloc
    var path = components.path.copy()
    var params = components.params
    var query = components.query
    var fragment = components.fragment

    if params.byte_length() > 0:
        path = path + ";" + params

    var url = path^
    var has_netloc = netloc.byte_length() > 0
    var scheme_netloc = (
        scheme.byte_length() > 0
        and _uses_netloc(scheme)
        and not url.startswith("//")
    )
    if has_netloc or scheme_netloc:
        if url.byte_length() > 0 and not url.startswith("/"):
            url = "/" + url
        url = "//" + netloc + url
    if scheme.byte_length() > 0:
        url = scheme + ":" + url
    if query.byte_length() > 0:
        url = url + "?" + query
    if fragment.byte_length() > 0:
        url = url + "#" + fragment
    return url^


# ---------------------------------------------------------------------------
# Query strings
# ---------------------------------------------------------------------------


def _split_all(s: String, sep: String) -> List[String]:
    """Split `s` on every occurrence of single-char `sep` (empties kept)."""
    var parts = List[String]()
    var bytes = s.as_bytes()
    var sep_b = sep.as_bytes()[0]
    var start = 0
    var i = 0
    while i < len(bytes):
        if bytes[i] == sep_b:
            parts.append(String(StringSlice(unsafe_from_utf8=bytes[start:i])))
            start = i + 1
        i += 1
    parts.append(String(StringSlice(unsafe_from_utf8=bytes[start:])))
    return parts^


def parse_qsl(
    query: String, separator: String = "&"
) -> List[QueryPair]:
    """Parse a query string into ordered `(key, value)` pairs.

    Mirrors `urllib.parse.parse_qsl` defaults: fields split on `separator`
    (default `&`), each split once on `=`, `+` decoded to space and `%XX`
    decoded in both key and value. Blank values are dropped (a bare key
    with no `=`, or `key=` with an empty value), matching
    `keep_blank_values=False`.
    """
    var result = List[QueryPair]()
    if query.byte_length() == 0:
        return result^
    var fields = _split_all(query, separator)
    for field in fields:
        if field.byte_length() == 0:
            continue
        var eq = field.find("=")
        if eq == -1:
            continue  # no '=' → blank value dropped by default
        var value_raw = _from(field, eq + 1)
        if value_raw.byte_length() == 0:
            continue  # empty value dropped by default
        var key_raw = _sub(field, 0, eq)
        result.append(QueryPair(unquote_plus(key_raw), unquote_plus(value_raw)))
    return result^


def parse_qs(
    query: String, separator: String = "&"
) raises -> Dict[String, List[String]]:
    """Parse a query string into `{key: [values...]}`, preserving repeats.

    Same field/decoding rules as `parse_qsl`; repeated keys accumulate
    their values in order, mirroring `urllib.parse.parse_qs`.
    """
    var pairs = parse_qsl(query, separator)
    var out = Dict[String, List[String]]()
    for pair in pairs:
        if pair.key in out:
            out[pair.key].append(pair.value.copy())
        else:
            var vals = List[String]()
            vals.append(pair.value.copy())
            out[pair.key] = vals^
    return out^


def urlencode(pairs: List[QueryPair]) -> String:
    """Build a query string from pairs; keys and values are `quote_plus`'d."""
    var out = String()
    for pair in pairs:
        if out.byte_length() > 0:
            out += "&"
        out += quote_plus(pair.key) + "=" + quote_plus(pair.value)
    return out^


# ---------------------------------------------------------------------------
# urljoin (RFC 3986 Section 5)
# ---------------------------------------------------------------------------


@fieldwise_init
struct _Uri(Copyable, Movable):
    """A URI reference split into RFC 3986 components with `defined` flags."""

    var scheme: String
    var scheme_def: Bool
    var authority: String
    var authority_def: Bool
    var path: String
    var query: String
    var query_def: Bool
    var fragment: String
    var fragment_def: Bool


def _uri_split(url: String) -> _Uri:
    """Split per RFC 3986 Appendix B (no `;params` handling — RFC has none)."""
    var rest = url.copy()

    var scheme = String()
    var scheme_def = False
    var authority = String()
    var authority_def = False
    var query = String()
    var query_def = False
    var fragment = String()
    var fragment_def = False

    var h = rest.find("#")
    if h != -1:
        fragment = _from(rest, h + 1)
        fragment_def = True
        rest = _sub(rest, 0, h)
    var q = rest.find("?")
    if q != -1:
        query = _from(rest, q + 1)
        query_def = True
        rest = _sub(rest, 0, q)

    var colon = rest.find(":")
    var slash = rest.find("/")
    if colon > 0 and (slash == -1 or colon < slash):
        scheme = _sub(rest, 0, colon)
        scheme_def = True
        rest = _from(rest, colon + 1)

    if rest.startswith("//"):
        var body = _from(rest, 2)
        var s2 = body.find("/")
        if s2 == -1:
            authority = body^
            rest = String()
        else:
            authority = _sub(body, 0, s2)
            rest = _from(body, s2)
        authority_def = True

    return _Uri(
        scheme^, scheme_def, authority^, authority_def,
        rest^, query^, query_def, fragment^, fragment_def,
    )


def _remove_last_segment(mut output: String):
    var slash = output.rfind("/")
    if slash == -1:
        output = String()
    else:
        output = _sub(output, 0, slash)


def _remove_dot_segments(path: String) -> String:
    """RFC 3986 Section 5.2.4 — collapse `.`/`..` segments in a path."""
    var input = path.copy()
    var output = String()
    while input.byte_length() > 0:
        if input.startswith("../"):
            input = _from(input, 3)
        elif input.startswith("./"):
            input = _from(input, 2)
        elif input.startswith("/./"):
            input = "/" + _from(input, 3)
        elif input == "/.":
            input = String("/")
        elif input.startswith("/../"):
            input = "/" + _from(input, 4)
            _remove_last_segment(output)
        elif input == "/..":
            input = String("/")
            _remove_last_segment(output)
        elif input == "." or input == "..":
            input = String()
        else:
            var bytes = input.as_bytes()
            var j = 1 if (len(bytes) > 0 and bytes[0] == UInt8(ord("/"))) else 0
            while j < len(bytes) and bytes[j] != UInt8(ord("/")):
                j += 1
            output += _sub(input, 0, j)
            input = _from(input, j)
    return output^


def _merge(base: _Uri, ref_path: String) -> String:
    """RFC 3986 Section 5.2.3 — merge a relative path onto the base path."""
    if base.authority_def and base.path.byte_length() == 0:
        return "/" + ref_path
    var slash = base.path.rfind("/")
    if slash == -1:
        return ref_path.copy()
    return _sub(base.path, 0, slash + 1) + ref_path


def urljoin(base: String, url: String) -> String:
    """Resolve `url` against `base` per RFC 3986 Section 5 ("Transform References").

    Implements the full reference-resolution algorithm — absolute,
    network-path, absolute-path, and relative-path references, plus
    `Remove Dot Segments` — and passes the RFC 3986 Section 5.4
    conformance table. Empty `base`/`url` short-circuit as in
    `urllib.parse.urljoin`.
    """
    if base.byte_length() == 0:
        return url.copy()
    if url.byte_length() == 0:
        return base.copy()

    var b = _uri_split(base)
    var r = _uri_split(url)

    var t_scheme: String
    var t_scheme_def: Bool
    var t_authority: String
    var t_authority_def: Bool
    var t_path: String
    var t_query: String
    var t_query_def: Bool

    if r.scheme_def:
        t_scheme = r.scheme.copy()
        t_scheme_def = True
        t_authority = r.authority.copy()
        t_authority_def = r.authority_def
        t_path = _remove_dot_segments(r.path)
        t_query = r.query.copy()
        t_query_def = r.query_def
    else:
        if r.authority_def:
            t_authority = r.authority.copy()
            t_authority_def = True
            t_path = _remove_dot_segments(r.path)
            t_query = r.query.copy()
            t_query_def = r.query_def
        else:
            if r.path.byte_length() == 0:
                t_path = b.path.copy()
                if r.query_def:
                    t_query = r.query.copy()
                    t_query_def = True
                else:
                    t_query = b.query.copy()
                    t_query_def = b.query_def
            else:
                if r.path.startswith("/"):
                    t_path = _remove_dot_segments(r.path)
                else:
                    t_path = _remove_dot_segments(_merge(b, r.path))
                t_query = r.query.copy()
                t_query_def = r.query_def
            t_authority = b.authority.copy()
            t_authority_def = b.authority_def
        t_scheme = b.scheme.copy()
        t_scheme_def = b.scheme_def

    # Recompose (RFC 3986 Section 5.3).
    var result = String()
    if t_scheme_def:
        result += t_scheme + ":"
    if t_authority_def:
        result += "//" + t_authority
    result += t_path
    if t_query_def:
        result += "?" + t_query
    if r.fragment_def:
        result += "#" + r.fragment
    return result^
