"""Throughput benchmark for mojo-url's core paths.

Times `urlparse` + `urlunparse` round-trips over the URL corpus, and
`parse_qsl` + `urlencode` round-trips over the query-string corpus. Both
corpora are extracted from `test/data/fixtures.txt` — the same CPython
byte-match conformance fixtures the test suite uses — so the benchmark
measures the real parse/encode paths on representative inputs.

The corpus is tiny (dozens of short strings), so each benchmark iterates the
whole corpus many thousands of times for stable numbers. Run compiled for
meaningful results:
`mojo build -I src bench/bench_parse.mojo -o .bench_parse && ./.bench_parse`
(or `pixi run bench`).
"""
from std.time import perf_counter_ns

from url import parse_qsl, urlencode, urlparse, urlunparse


def _inputs_for(source: String, op: String) -> List[String]:
    """Collect the input column (field 1) of fixture lines tagged `op`."""
    var out = List[String]()
    for line in source.split("\n"):
        var fields = line.split("\t")
        if len(fields) >= 2 and String(fields[0]) == op:
            out.append(String(fields[1]))
    return out^


def bench_urlparse(urls: List[String], iterations: Int) raises:
    # Warmup + correctness anchor: round-trip once, require stability.
    var anchor = 0
    for url in urls:
        anchor += urlunparse(urlparse(url)).byte_length()
    var start = perf_counter_ns()
    for _ in range(iterations):
        var total = 0
        for url in urls:
            total += urlunparse(urlparse(url)).byte_length()
        if total != anchor:
            raise Error("inconsistent parse")
    var elapsed_ns = perf_counter_ns() - start
    var per_op_us = Float64(elapsed_ns) / Float64(iterations * len(urls)) / 1e3
    print(t"urlparse + urlunparse: {len(urls)} URLs x {iterations} iters")
    print(t"  {per_op_us} us/round-trip")


def bench_query(queries: List[String], iterations: Int) raises:
    # Warmup + correctness anchor: encode/decode once, require stability.
    var anchor = 0
    for query in queries:
        anchor += urlencode(parse_qsl(query)).byte_length()
    var start = perf_counter_ns()
    for _ in range(iterations):
        var total = 0
        for query in queries:
            total += urlencode(parse_qsl(query)).byte_length()
        if total != anchor:
            raise Error("inconsistent query round-trip")
    var elapsed_ns = perf_counter_ns() - start
    var count = iterations * len(queries)
    var per_op_us = Float64(elapsed_ns) / Float64(count) / 1e3
    print(t"parse_qsl + urlencode: {len(queries)} queries x {iterations} iters")
    print(t"  {per_op_us} us/round-trip")


def main() raises:
    var source = open("test/data/fixtures.txt", "r").read()
    var urls = _inputs_for(source, "urlparse")
    var queries = _inputs_for(source, "parse_qsl")
    if len(urls) == 0 or len(queries) == 0:
        raise Error("no fixture inputs found — run from the repo root")
    bench_urlparse(urls, 20000)
    bench_query(queries, 20000)
