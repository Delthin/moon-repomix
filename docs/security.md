# Secret scanning

`delthin/moon_repomix/security` exposes:

```text
pub(all) struct Finding { rule:String, path:String, start:Int, end:Int, line:Int }
pub fn scan(path:String, text:String, bom_bytes:Int) -> Array[Finding] raise ScanError
```

Scan the same decoded snapshot that will be rendered. Pass `bom_bytes=3` only
when the reader stripped an initial UTF-8 BOM, otherwise `0`. Findings contain
no original value or preview. `start`/`end` are zero-based, half-open **disk
UTF-8 byte** offsets; `line` is one-based (CRLF counts once; bare CR and LF also
advance the line). The caller excludes the entire file on any finding.

The engine is `123123213weqw/moon_scrub@0.5.2`, using
`ScanConfig::secrets_only()`. Its `String.length()`/index-based detectors return
UTF-16 code-unit offsets, not codepoint offsets. A synthetic regression checks
that directly and verifies conversion after Chinese, emoji, a combining mark,
CRLF and a stripped BOM. Surrogate-interior ranges fail closed.

## Verified coverage

| Rule ID | Shapes / policy verified with synthetic data |
| --- | --- |
| `github-token` | `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`: total 40 units; `github_pat_`: total 93 |
| `aws-access-key` | `AKIA` / `ASIA`: total 20 uppercase ASCII letters/digits |
| `openai-key` | Legacy `sk-`: total 51; `sk-proj-` / `sk-svcacct-`: total 48–256 |
| `pem-private-key` | Engine private-key BEGIN markers, through footer or remaining text; not certificates/public keys |
| `credential-assignment` | Engine sensitive-key assignments; values at least 8 units with a letter and a digit or credential punctuation |
| `access-token`, `bearer-token`, `jwt`, `url-credential` | Other engine secrets-only credential families retained |

The adapter tightens the engine's permissive GitHub/AWS/OpenAI minimum lengths
and filters common placeholders and code-valued assignments. No upstream source
is modified or vendored. Placeholder suppression includes example/placeholder,
changeme, your_/your-, replace_me, redacted, dummy and repeated-character values.
Generic assignments suppress bare identifiers/types, process/env/config lookups,
interpolations and expression brackets. Ordinary code and contact details are
negative regression cases; emails, IPs and phone numbers are not scanned.

This is a bounded heuristic policy, not proof of absence of secrets, format
validation with service providers, or full Secretlint parity. In particular,
short/password-only literals and new token formats may not be detected. Literal
values containing placeholder words are intentionally suppressed. The engine
merges overlapping findings before adapter filtering, so the result is not an
exhaustive list of every rule at a location. No Secretlint differential run is
claimed.

`ScanError` carries only stable variants: `InvalidBomOffset`, `InvalidText`,
`InvalidEngineRange`, `InputTooLarge`; no source text, engine message or preview
is included. The pinned engine API is synchronous and non-raising; native
runtime aborts (including out-of-memory) are not recoverable MoonBit errors.
Scanning performs no I/O and emits no logs. Callers must not log snapshot text
on failure. Explicitly disabling scanning is a separate caller policy and must
be recorded as disabled, not passed.
