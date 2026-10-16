# Configuration and argument parsing

Package: `delthin/moon_repomix/config`. This package is pure: it does not inspect
cwd, read or create files, load tokenizer resources, print diagnostics, or run a
pack operation. Relative paths are returned unchanged.

## Integration API

```moonbit
pub fn parse_cli(args : Array[String]) -> Cli raise ConfigError
pub fn parse_json(text : String) -> Patch raise ConfigError
pub fn resolve(cli : Cli, json : Patch?) -> Options raise ConfigError
pub fn Patch::empty() -> Patch
```

Pass arguments **without argv[0]**. `Cli` has `directory` (default `.`),
`config_path : String?`, `action : Action`, `stdout`, `quiet`, `verbose`, and
`patch : Patch`. `Action` is `Pack | Init | Help | Version`; `Style` is
`Xml | Markdown`. No action is executed during parsing. Different explicit
actions conflict; repeated identical actions are harmless.

The caller selects at most one JSON file: the explicit `config_path`, or
`repomix.config.json` under the input root. The caller owns cwd-relative path
resolution, missing/default versus explicit-file error policy, reading JSON,
help/version output, and safe initialization without overwriting existing files.
An absent file is passed as `None`, not an empty string. The caller can handle
help/version/init before loading configuration or tokenizer resources.

`Options` fields:

| Field | Type / default |
| --- | --- |
| `directory` | `String`, `.` |
| `output` | `String`, style-dependent filename |
| `stdout` | `Bool`, false |
| `style` | `Style`, `Xml` |
| `include_patterns`, `ignore` | `Array[String]`, empty |
| `use_gitignore`, `use_dot_ignore`, `use_default_patterns` | `Bool`, true |
| `security_check` | `Bool`, true |
| `encoding` | `String`, `o200k_base` only |
| `token_budget` | `Int?`, `None` (unlimited) |
| `max_file_size` | `Int`, 52428800 disk bytes |
| `tokenizer_path` | `String?`, `None` |
| `quiet`, `verbose` | `Bool`, false |

`Patch` has the same configuration fields (not directory/stdout/quiet/verbose),
with optional scalars and additive arrays. Its fields are mutable to support
programmatic construction from `Patch::empty()`. `resolve` validates both
patches, even fields subsequently overridden, and does not mutate either patch
or its lists. `Options` arrays are newly allocated.

Precedence is defaults → selected JSON → explicit CLI scalar values. Missing
booleans remain `None`, so JSON `false` survives. Include and custom-ignore lists
append JSON first, CLI second, and deduplicate exact strings in first-occurrence
order (no case folding or normalization).

## CLI subset

| Arguments | Effect |
| --- | --- |
| `[directory]` | One directory, default `.` |
| `-o, --output PATH` | Explicit output filename |
| `--stdout` | Request body-only stdout; caller sends diagnostics to stderr |
| `--style xml\|markdown` | XML or Markdown; default filenames `repomix-output.xml` / `repomix-output.md` |
| `--include GLOBS` | Append comma-separated include patterns |
| `-i, --ignore GLOBS` | Append comma-separated custom-ignore patterns |
| `--no-gitignore` | Set `use_gitignore=false` |
| `--no-dot-ignore` | Set `use_dot_ignore=false` |
| `--no-default-patterns` | Set `use_default_patterns=false` |
| `--no-security-check` | Set `security_check=false`; caller must warn and record disabled status |
| `--token-count-encoding o200k_base` | Only supported encoding |
| `--token-budget N` | Positive integer token limit; caller enforces budget, equality passes |
| `--tokenizer-path PATH` | Explicit tokenizer resource path, returned unchanged; caller loads and verifies it |
| `-c, --config PATH` | Explicit JSON config path, queryable on `Cli` |
| `--init` | Initialization action only |
| `--parsable-style` | Accepted compatibility no-op; output is always parseable |
| `--quiet`, `--verbose` | Mutually exclusive diagnostic modes |
| `-h, --help` | Help action |
| `-v, --version` | Version action (**not** verbose) |

Short names were checked against the fixed Repomix 1.18.1 CLI; `-h` is its
Commander help alias. Only the listed subset is accepted. In particular, quiet
and verbose have no short aliases. Value options accept `--key=value` as well as
separate values (`-o=PATH` also works). Separate values beginning with `-` must
use the equals form. Short-option clustering and attached `-oPATH` are not
supported. `--` ends option parsing, allowing a directory beginning with `-`.
CSV entries are trimmed; empty entries are errors. Repeated scalar options use
the last value; repeated list options append and deduplicate.

`--stdout` conflicts with an explicit CLI `--output` in either order. A filename
from JSON is not a CLI output request and does not conflict. `Options.output`
still contains the resolved filename in stdout mode; the caller must obey
`stdout` and not create that file. No implicit stdout behavior is attached to a
filename of `-`; use `--stdout` explicitly.

## Strict JSON subset

```json
{
  "output": {
    "filePath": "context.md",
    "style": "markdown",
    "tokenBudget": 200000
  },
  "include": ["src/**", "docs/*.md"],
  "ignore": {
    "customPatterns": ["tmp/**"],
    "useGitignore": true,
    "useDotIgnore": true,
    "useDefaultPatterns": true
  },
  "security": { "enableSecurityCheck": true },
  "tokenCount": { "encoding": "o200k_base" },
  "input": { "maxFileSize": 52428800 }
}
```

Every shown field is optional. Every other field is rejected, at every nesting
level; unsupported upstream fields are not silently ignored. JSON must have an
object root and the exact field types shown. `null` is not absence. Lists must
contain strings. Budget and max-file-size values must be positive integral
numbers in `1..2147483647`; CLI budget uses decimal digits only. Empty paths and
NUL-containing paths are invalid. An omitted output filename is chosen after
resolving style, not while parsing a patch. `tokenizer_path` is CLI/programmatic
only, not a JSON extension.

Both parsers and `resolve` reject empty glob patterns, leading `!`, absolute
paths, backslashes, colons, braces, and `..` path segments in custom include or
ignore patterns. This is **not** the `.gitignore` grammar: negation remains the
selection package's responsibility when reading ignore files. Supported glob
syntax includes `*`, `?`, `**`, character classes and directory patterns; deeper
glob syntax validation/compilation belongs to selection.

`ConfigError` variants are `InvalidJson`, `UnknownField(String)`,
`InvalidValue(String)`, `UnknownOption(String)`, `MissingValue(String)`,
`Conflict(String)`, `MultipleDirectories`. String payloads identify fields or
options, not supplied values or JSON text. Exceptions from JSON parsing are
normalized to `InvalidJson`; errors are not ignored or retried.

## Verification boundary

Three aggregate native tests cover defaults and precedence (including explicit
false/true), stable list merging without input mutation, CLI options/actions,
strict nested JSON types/unknown fields, integer bounds, conflicts, and unsafe
glob rejection. Actual CLI I/O, config discovery, diagnostics, resource loading,
initialization safety and end-to-end execution belong to the integrating CLI.
