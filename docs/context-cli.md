# Portable task and code context

Use the existing Root task/code specifications from a file or a serial JSONL
stream. These modes are not MCP and do not add repository permissions.

```sh
moon-repomix ./project --context-request request.json --tokenizer-path o200k_base.tiktoken
moon-repomix ./project --context-request request.json -o response.json
moon-repomix ./project --context-stdio --tokenizer-path o200k_base.tiktoken
```

The default destination is stdout, even when repository configuration names a
pack output file. File mode accepts explicit `-o FILE` (atomic replacement) or
`-o -` (stdout). Stdio mode forbids `-o`, including `-o -`. Request paths and
explicit output/config paths are relative to the working directory; paths
inside a specification are relative to the selected repository root.

## Portable request

Only four top-level fields are recognized:

```json
{
  "schemaVersion": 1,
  "operation": "plan_task_context",
  "spec": {
    "maxTokens": 6000,
    "tasks": [{
      "id": "implementation",
      "required": [{"path": "src/main.mbt", "mode": "full"}],
      "optional": [{"path": "src/util.mbt", "mode": "either", "priority": 80}]
    }]
  }
}
```

A fresh code request uses the same envelope:

```json
{
  "schemaVersion": 1,
  "operation": "read_code_context",
  "spec": {
    "maxTokens": 6000,
    "requests": [{"path": "src/main.mbt", "ranges": [{"startLine": 1, "endLine": 20}]}]
  }
}
```

`spec` is the existing `TaskContextSpec` or `CodeContextSpec`, not a CLI-specific
variant. Code requests select exactly one of `symbols`, `ranges`, `full: true`,
or `outline: true` per path; symbol requests may use `includeDependencies`.
Root determines supported definition languages, source lines, ambiguity and
availability. Task modes are `full`/`skeleton` for required paths and also
`either` for optional paths. Existing spec limits, `maxReadBytes`, task
`maxAttempts`, strict field validation and root-relative path validation apply.

`schemaVersion` must be integer 1. Unknown fields, directories, tokenizer paths
and host permissions are not portable request fields. Input must be strict
UTF-8 JSON, at most 65536 raw bytes and at most 65536 UTF-8 bytes after normalized
JSON serialization. Root `ContextRequest::from_json` validates and snapshots the
request; `spec_json()` and `to_json()` return fresh copies.

## Responses and accounting

Each request produces one newline-terminated JSON envelope on stdout (or the
explicit response file). Common fields are `schemaVersion`, `operation`, `ok`,
`status`; planned results also include `tokens`, `bytes`, `security`, `audit`
and `auditIncludedInText`. Successful results include **`text`, the exact Root
serialized body**. Parsing the envelope restores that string without rewriting
its newlines, paths or contents. No second rendering or per-file token sum is
used. Unavailable or over-budget results have no `text`; code over-budget may
include `requiredTokens`. Validation/transport errors use `status: "error"`
and a safe `error.category`, without echoing input, source or private paths.

- Task success is `complete` or `with_omissions`. Task audit is separate from
  the body: `auditIncludedInText: false`, with `auditText`, `auditTokens` and
  `auditBytes` reported independently.
- Code success is `complete`. The body already contains its audit:
  `auditIncludedInText: true`. The separate `audit` is a projection, not extra
  budgeted text. `tokens` counts the entire exact body, including embedded audit.
- Envelope/transport overhead is outside `spec.maxTokens`. Responses, including
  the terminating newline, are bounded to 16 MiB.

`--report-json` emits diagnostics only to stderr, one report per processed
request. Reports identify the operation, success/failure, exit code and
`publication` (`not_started`, `unknown`, or `committed`); `resultStatus`
distinguishes planned failures. A published failure envelope is still a failed
operation. File mode exits 0 for success, 1 for failure. Failed operations never
replace an existing response file. Successful file publication uses a sibling
temporary file and atomic replacement; links/non-regular output targets fail.

## Same-process continuation

In `--context-stdio`, write one request per line and wait for its response.
Successful code responses include `runId`, `round`, `sessionTokens`,
`remainingTokens`, `maxTokens` and `canContinue`. Send only the **latest successful
ID**, and omit `maxTokens` from the continuation spec:

```json
{"schemaVersion":1,"operation":"read_code_context","continueFrom":"<latest runId>","spec":{"requests":[{"path":"src/util.mbt","full":true}]}}
```

The initial `spec.maxTokens` is a cumulative whole-body budget across at most
three successful reads. Continuations receive only the remaining budget through
Root `CodeContextSession`; a failed read, invalid request, stale ID or failed
publication consumes no round or tokens and retains the previous successful ID.
Every successful read replaces the ID. A successful fresh code request starts a
new budget; a successful task invalidates the previous code session. A failed
fresh request or failed task leaves it intact.

There are no persistence files. **A new process cannot resume another process's
code request.** File mode rejects every `continueFrom` as stale and reports
`canContinue: false` even if its initial budget has room. IDs are not filesystem
paths or authorization tokens.

Stdio processes lines serially, reusing one runtime and its in-memory session.
Malformed JSON/UTF-8/spec lines produce safe failures and allow the next line.
An overlong line uses at most one oversize probe, emits a failure and stops
without draining the stream. EOF exits 0, even after recoverable per-line
failures; an overlong stream or publication failure exits 1. There is no startup
message on stdout. Clients must consume responses (normal pipe backpressure
applies).

## Configuration and permissions

Both modes preserve Root selection, ignore rules, full-source secret scanning,
input/file/read limits, templates and task presentation settings. An ignored,
excluded or unsafe path cannot become readable through a portable request.
Templates are scanned and budgeted as before. Code uses Root's fixed JSON body,
not a host display re-rendering.

These flags conflict with MCP/WebUI, stdin file lists, `--explain-path` and
`--init`. Remote/branch, split, ordinary pack token budgets, diff/log controls,
Git-only limits, global `--compress`/`--no-compress` (use spec modes instead),
pack summary counters, service-only options, `--no-files` and
`--parsable-style` are rejected when explicitly supplied; incompatible selected
JSON settings also fail rather than being silently ignored. Selection, scanning,
resource and template settings remain usable. Existing ordinary pack commands
and configuration precedence are unchanged.

## Focused regression aggregate

Build/freeze a Native binary outside the aggregate, then run:

```sh
moon run --target native scripts/context-entry-test.mbtx -- --ready /absolute/moon-repomix /absolute/o200k_base.tiktoken /absolute/new-log-directory
```

The aggregate uses synthetic fixtures and the supplied binary only. It archives
argv, stdin/stdout/stderr, exit codes and a result manifest. It never builds or
installs the product, and does not call MCP or HTTP.
