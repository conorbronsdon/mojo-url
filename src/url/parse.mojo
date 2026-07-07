"""URL parsing, building, percent-encoding, and query-string handling.

A pure-Mojo port of the daily-driver surface of Python's
`urllib.parse`, named the same so the functions read identically:
`urlparse`/`urlunparse`, `quote`/`quote_plus`/`unquote`/`unquote_plus`,
`urlencode`/`parse_qs`/`parse_qsl`, and `urljoin`.

Component-split and encoding behavior are matched byte-for-byte against
CPython's `urllib.parse` via the fixtures in `test/data/fixtures.txt`.
`urljoin` is a faithful port of CPython's `urllib.parse.urljoin` (RFC 3986
Section 5 reference resolution plus CPython's backward-compatible handling
of a same-scheme reference) and passes the RFC 3986 Section 5.4 conformance
table byte-for-byte against CPython.
"""

from url.model import ParseResult, QueryPair


comptime _HEX_UPPER = "0123456789ABCDEF"


def _uses_params(scheme: String) -> Bool:
    """Schemes for which urlparse splits `;params` off the path (CPython)."""
    var s = scheme
    return (
        s == ""
        or s == "ftp"
        or s == "hdl"
        or s == "prospero"
        or s == "http"
        or s == "imap"
        or s == "https"
        or s == "shttp"
        or s == "rtsp"
        or s == "rtsps"
        or s == "rtspu"
        or s == "sip"
        or s == "sips"
        or s == "mms"
        or s == "sftp"
        or s == "tel"
    )


def _uses_netloc(scheme: String) -> Bool:
    """Schemes for which urlunsplit synthesizes a `//` authority (CPython)."""
    var s = scheme
    return (
        s == ""
        or s == "ftp"
        or s == "http"
        or s == "gopher"
        or s == "nntp"
        or s == "telnet"
        or s == "imap"
        or s == "wais"
        or s == "file"
        or s == "mms"
        or s == "https"
        or s == "shttp"
        or s == "snews"
        or s == "prospero"
        or s == "rtsp"
        or s == "rtsps"
        or s == "rtspu"
        or s == "rsync"
        or s == "svn"
        or s == "svn+ssh"
        or s == "sftp"
        or s == "nfs"
        or s == "git"
        or s == "git+ssh"
        or s == "ws"
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

    Matches CPython's `errors="replace"` (the "substitution of maximal
    subparts of an ill-formed subsequence" from the Unicode standard, which
    is what `bytes.decode("utf-8", "replace")` implements). Two properties
    that a naive decoder gets wrong and that this reproduces:

    * The **second byte's** valid range is lead-byte-specific (RFC 3629 /
      Unicode Table 3-7), so overlong encodings (`E0 80..9F`), surrogates
      (`ED A0..BF`), and out-of-range 4-byte leads (`F0 80..8F`, `F4 90..BF`)
      are rejected instead of decoding to raw/invalid bytes.
    * When a sequence is ill-formed, exactly **one** U+FFFD is emitted and
      the decoder resumes at the first byte that is *not* part of the
      maximal valid subpart — a truncated 3-byte sequence yields one U+FFFD,
      not one per byte.
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
        # Sequence length and the *second* byte's valid range, which is
        # lead-byte-specific. Third/fourth bytes are always 0x80..0xBF.
        var seq_len = 0
        var lo2 = 0x80
        var hi2 = 0xBF
        if b >= 0xC2 and b <= 0xDF:
            seq_len = 2
        elif b == 0xE0:
            seq_len = 3
            lo2 = 0xA0
        elif b >= 0xE1 and b <= 0xEC:
            seq_len = 3
        elif b == 0xED:
            seq_len = 3
            hi2 = 0x9F
        elif b >= 0xEE and b <= 0xEF:
            seq_len = 3
        elif b == 0xF0:
            seq_len = 4
            lo2 = 0x90
        elif b >= 0xF1 and b <= 0xF3:
            seq_len = 4
        elif b == 0xF4:
            seq_len = 4
            hi2 = 0x8F
        # else: invalid lead byte (0x80..0xC1, 0xF5..0xFF) -> seq_len == 0.
        if seq_len == 0:
            out += "�"
            i += 1
            continue
        # Consume the maximal subpart: lead + each following byte that is
        # in range at its position. On the first out-of-range byte (or EOF)
        # emit a single U+FFFD and resume at that byte.
        var consumed = 1
        var valid = True
        for k in range(1, seq_len):
            if i + k >= n:
                valid = False
                break
            var c = data[i + k]
            var lo = UInt8(lo2) if k == 1 else UInt8(0x80)
            var hi = UInt8(hi2) if k == 1 else UInt8(0xBF)
            if c < lo or c > hi:
                valid = False
                break
            consumed += 1
        if not valid:
            out += "�"
            i += consumed
            continue
        out += String(StringSlice(unsafe_from_utf8=data[i : i + seq_len]))
        i += seq_len
    return out^


# ---------------------------------------------------------------------------
# Percent-encoding
# ---------------------------------------------------------------------------


def _is_always_safe(b: UInt8) -> Bool:
    """The characters percent-encoding never escapes (Python's `_ALWAYS_SAFE`).
    """
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
    out += String(_HEX_UPPER[byte=Int(b >> 4)])
    out += String(_HEX_UPPER[byte=Int(b & 0xF)])


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

    return ParseResult(scheme^, netloc^, work^, params^, query^, fragment^)


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


def parse_qsl(query: String, separator: String = "&") -> List[QueryPair]:
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


def _uses_relative(scheme: String) -> Bool:
    """Schemes for which urljoin resolves a reference relatively (CPython)."""
    var s = scheme
    return (
        s == ""
        or s == "ftp"
        or s == "http"
        or s == "gopher"
        or s == "nntp"
        or s == "imap"
        or s == "wais"
        or s == "file"
        or s == "https"
        or s == "shttp"
        or s == "mms"
        or s == "prospero"
        or s == "rtsp"
        or s == "rtspu"
        or s == "sftp"
        or s == "svn"
        or s == "svn+ssh"
        or s == "ws"
        or s == "wss"
    )


def urljoin(base: String, url: String) -> String:
    """Resolve `url` against `base`, mirroring `urllib.parse.urljoin` byte-for-byte.

    This is a faithful port of CPython's `urljoin`, which implements RFC 3986
    Section 5 reference resolution *plus* CPython's long-standing backward
    compatibility: a reference whose scheme equals the base scheme (and whose
    scheme uses relative resolution) is treated as relative. For example
    `urljoin("http://a/b/c/d;p?q", "http:g")` yields `http://a/b/c/g`, not the
    strict-RFC `http:g` — matching `urllib.parse`, which is this library's
    stated contract. Digit-led pseudo-schemes such as `10:30.html` are *not*
    schemes (the scheme must be alpha-led), so they resolve as relative paths.
    A reference with a different scheme is returned verbatim, without dot-
    segment removal, exactly as CPython does. Passes the RFC 3986 Section 5.4
    conformance table (see `test_urljoin_rfc3986_table`).
    """
    if base.byte_length() == 0:
        return url.copy()
    if url.byte_length() == 0:
        return base.copy()

    var b = urlparse(base)
    var r = urlparse(url)

    var scheme = r.scheme.copy()
    if scheme.byte_length() == 0:
        scheme = b.scheme.copy()
    var netloc = r.netloc.copy()
    var path = r.path.copy()
    var params = r.params.copy()
    var query = r.query.copy()
    var fragment = r.fragment.copy()

    # Different scheme, or a scheme that does not use relative resolution:
    # the reference is already absolute, return it unchanged.
    if scheme != b.scheme or not _uses_relative(scheme):
        return url.copy()

    if _uses_netloc(scheme):
        if netloc.byte_length() > 0:
            return urlunparse(
                ParseResult(scheme^, netloc^, path^, params^, query^, fragment^)
            )
        netloc = b.netloc.copy()

    # Reference with no path/params: inherit base path (and query if absent).
    if path.byte_length() == 0 and params.byte_length() == 0:
        path = b.path.copy()
        params = b.params.copy()
        if query.byte_length() == 0:
            query = b.query.copy()
        return urlunparse(
            ParseResult(scheme^, netloc^, path^, params^, query^, fragment^)
        )

    # Resolve the path against the base path (RFC 3986 Section 5.2, as CPython
    # implements it via segment lists).
    var base_parts = _split_all(b.path, "/")
    if base_parts[len(base_parts) - 1] != "":
        # The last base segment is a file, not a directory: drop it.
        _ = base_parts.pop()

    var segments: List[String]
    if path.startswith("/"):
        # Absolute-path reference: ignore the base path entirely.
        segments = _split_all(path, "/")
    else:
        segments = base_parts.copy()
        for seg in _split_all(path, "/"):
            segments.append(seg)
        # Drop empty interior segments so re-joining can't create `//`.
        var filtered = List[String]()
        for idx in range(len(segments)):
            var keep = (
                idx == 0
                or idx == len(segments) - 1
                or segments[idx].byte_length() > 0
            )
            if keep:
                filtered.append(segments[idx].copy())
        segments = filtered^

    var resolved = List[String]()
    for seg in segments:
        if seg == "..":
            if len(resolved) > 0:
                _ = resolved.pop()
        elif seg == ".":
            continue
        else:
            resolved.append(seg.copy())

    var last = segments[len(segments) - 1]
    if last == "." or last == "..":
        # A trailing relative dir needs its trailing slash back.
        resolved.append(String())

    var joined = String()
    for idx in range(len(resolved)):
        if idx > 0:
            joined += "/"
        joined += resolved[idx]
    if joined.byte_length() == 0:
        joined = String("/")

    return urlunparse(
        ParseResult(scheme^, netloc^, joined^, params^, query^, fragment^)
    )
