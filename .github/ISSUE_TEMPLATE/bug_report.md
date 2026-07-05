---
name: Bug report
about: Report a URL that parses/encodes incorrectly or otherwise misbehaves
---

## Failing input

Paste the URL, query string, or component values that trigger the bug.

## Expected output

What should the function have produced? If it should match Python, paste
the `urllib.parse` output (e.g. `python3 -c "import urllib.parse as u; print(u.urlparse('...'))"`).

## Actual output

What mojo-url actually produced (including any error/crash/hang).

## Mojo version

Output of `mojo --version`.
