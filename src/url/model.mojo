"""The parsed-URL data model, mirroring Python's `urllib.parse.ParseResult`.

A `ParseResult` holds the six components of the generic URI syntax
(`scheme://netloc/path;params?query#fragment`) exactly as Python's
`urlparse` splits them, plus the convenience accessors `username`,
`password`, `hostname`, and `port` that are derived from `netloc` on
demand.

Following Python, an absent component is the empty string (never a null),
so a bare path like `"a/b"` parses to every field empty except `path`.
The derived accessors return empty strings for absent user-info/host and
`-1` for an absent or non-numeric port (Python returns `None`; `-1` is
the Mojo-friendly sentinel), and `hostname` is lowercased with any IPv6
zone id after `%` preserved, matching Python.
"""


@fieldwise_init
struct QueryPair(Copyable, Movable, Writable, Equatable):
    """One `key=value` pair from a query string (decoded)."""

    var key: String
    var value: String

    def __eq__(self, other: Self) -> Bool:
        return self.key == other.key and self.value == other.value

    def write_to(self, mut writer: Some[Writer]):
        writer.write(self.key, "=", self.value)


@fieldwise_init
struct ParseResult(Copyable, Movable, Writable, Equatable):
    """The six-tuple split of a URL, plus netloc-derived accessors."""

    var scheme: String
    var netloc: String
    var path: String
    var params: String
    var query: String
    var fragment: String

    def __eq__(self, other: Self) -> Bool:
        return (
            self.scheme == other.scheme
            and self.netloc == other.netloc
            and self.path == other.path
            and self.params == other.params
            and self.query == other.query
            and self.fragment == other.fragment
        )

    def _hostinfo(self) -> String:
        """The `host[:port]` portion of netloc (after the last `@`)."""
        var at = self.netloc.rfind("@")
        if at == -1:
            return self.netloc.copy()
        var bytes = self.netloc.as_bytes()
        return String(StringSlice(unsafe_from_utf8=bytes[at + 1 :]))

    def username(self) -> String:
        """User portion of `user:pass@` userinfo, or empty if absent."""
        var at = self.netloc.rfind("@")
        if at == -1:
            return String()
        var bytes = self.netloc.as_bytes()
        var userinfo = String(StringSlice(unsafe_from_utf8=bytes[0:at]))
        var colon = userinfo.find(":")
        if colon == -1:
            return userinfo^
        var ubytes = userinfo.as_bytes()
        return String(StringSlice(unsafe_from_utf8=ubytes[0:colon]))

    def password(self) -> String:
        """Password portion of `user:pass@` userinfo, or empty if absent."""
        var at = self.netloc.rfind("@")
        if at == -1:
            return String()
        var bytes = self.netloc.as_bytes()
        var userinfo = String(StringSlice(unsafe_from_utf8=bytes[0:at]))
        var colon = userinfo.find(":")
        if colon == -1:
            return String()
        var ubytes = userinfo.as_bytes()
        return String(StringSlice(unsafe_from_utf8=ubytes[colon + 1 :]))

    def hostname(self) -> String:
        """Host from netloc, lowercased; IPv6 zone id (after `%`) preserved."""
        var hostinfo = self._hostinfo()
        var host: String
        if hostinfo.find("[") != -1:
            # Bracketed IPv6 literal: host is between '[' and ']'.
            var hb = hostinfo.as_bytes()
            var lb = hostinfo.find("[")
            var rb = hostinfo.find("]")
            if rb == -1:
                rb = len(hb)
            host = String(StringSlice(unsafe_from_utf8=hb[lb + 1 : rb]))
        else:
            var colon = hostinfo.find(":")
            if colon == -1:
                host = hostinfo^
            else:
                var hb = hostinfo.as_bytes()
                host = String(StringSlice(unsafe_from_utf8=hb[0:colon]))
        # Lowercase the host but not any '%zone' suffix (matches Python).
        var pct = host.find("%")
        if pct == -1:
            return host.lower()
        var hbytes = host.as_bytes()
        var name = String(StringSlice(unsafe_from_utf8=hbytes[0:pct]))
        var zone = String(StringSlice(unsafe_from_utf8=hbytes[pct:]))
        return name.lower() + zone

    def port(self) -> Int:
        """Numeric port from netloc, or -1 when absent or non-numeric."""
        var hostinfo = self._hostinfo()
        var port_str: String
        if hostinfo.find("]") != -1:
            var hb = hostinfo.as_bytes()
            var rb = hostinfo.find("]")
            var after = String(StringSlice(unsafe_from_utf8=hb[rb + 1 :]))
            var colon = after.find(":")
            if colon == -1:
                return -1
            var ab = after.as_bytes()
            port_str = String(StringSlice(unsafe_from_utf8=ab[colon + 1 :]))
        else:
            var colon = hostinfo.rfind(":")
            if colon == -1:
                return -1
            var hb = hostinfo.as_bytes()
            port_str = String(StringSlice(unsafe_from_utf8=hb[colon + 1 :]))
        if port_str.byte_length() == 0:
            return -1
        var value = 0
        for b in port_str.as_bytes():
            if b < UInt8(ord("0")) or b > UInt8(ord("9")):
                return -1
            value = value * 10 + Int(b) - ord("0")
        return value

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "ParseResult(scheme=",
            self.scheme,
            ", netloc=",
            self.netloc,
            ", path=",
            self.path,
            ", params=",
            self.params,
            ", query=",
            self.query,
            ", fragment=",
            self.fragment,
            ")",
        )
