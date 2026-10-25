///|
let help : String =
  #|moon-repomix — pack repository context for AI
  #|Usage: moon-repomix [directory] [options]
  #|
  #|Quick start:
  #|  moon-repomix                            Current directory -> repomix-output.xml
  #|  moon-repomix ./project -f md -o context.md
  #|  moon-repomix ./project --compress -f md -o structure.md
  #|  moon-repomix ./project --budget 12000
  #|  moon-repomix ./project --split 12000 -o context-parts
  #|
  #|Export:
  #|  -o, --output PATH          Output file; '-' writes stdout
  #|  -f, --format FORMAT        xml|md|json|txt (default: xml)
  #|      --compress             Keep syntax-tree skeletons instead of implementations
  #|      --include GLOBS        Select paths, e.g. 'src/**,README.md'
  #|  -i, --ignore GLOBS         Exclude matching paths
  #|      --keep-full GLOBS      Keep selected files intact when compressing
  #|
  #|Budgets:
  #|      --budget N             Full-document limit; exceeded output is kept, exit 1
  #|      --split N              Hard cap per volume; -o names a NEW directory
  #|  Split output includes a separately counted index and conflicts with --budget/stdout.
  #|
  #|Other entry points:
  #|      --remote HTTPS_URL     Pack a public repository
  #|      --webui                Local browser workbench
  #|      --mcp                  Read-only MCP stdio server
  #|      --init                 Save configuration without overwriting
  #|  -c, --config PATH          Use a JSON configuration
  #|  -h, --help                 Show this quick reference
  #|      --help-all             Show every option, Git context and advanced controls
  #|  -v, --version              Show version
  #|
  #|Outputs and explicit config paths are relative to the working directory.
  #|Existing --style, --token-budget and --split-output spellings remain supported.
  #|

///|
let full_help : String =
  #|moon-repomix — complete command reference
  #|Usage: moon-repomix [directory] [options]
  #|Directory defaults to '.'; default output is repomix-output.xml.
  #|
  #|Output and input:
  #|  -o, --output PATH              Output file; '-' writes stdout, './-' is a file
  #|      --stdout                   Write only the document to stdout
  #|  -f, --format FORMAT            xml|md|json|txt; markdown|plain also accepted
  #|      --style FORMAT             Existing spelling of --format
  #|      --stdin                    Literal UTF-8 file list, one path per line
  #|      --stdin0                   NUL-separated file list (for git -z)
  #|      --explain-path PATH        Explain one literal local path; repeat up to 256
  #|
  #|Selection and compression:
  #|      --compress / --no-compress  Syntax-tree skeletons with source lines
  #|      --keep-full GLOBS          Keep matching selected files intact when compressing
  #|      --include GLOBS            Root-relative filters; supports {a,b} alternatives
  #|  -i, --ignore GLOBS             Comma-separated exclusion filters
  #|      --no-gitignore             Disable .gitignore and Git exclude rules
  #|      --no-dot-ignore            Disable .ignore; .repomixignore still applies
  #|      --no-default-patterns      Disable built-in excludes
  #|      --no-security-check        Disable secret scanning (warns)
  #|
  #|Budgets and limits:
  #|      --budget N                 Full-document limit; output kept if exceeded, exit 1
  #|      --token-budget N           Existing spelling of --budget
  #|      --split N                  Exact token cap per volume; -o names a NEW directory
  #|      --split-output N           Existing spelling of --split
  #|      --no-split-output          Disable configured volume output
  #|      --max-file-size N          Positive per-file byte limit (default: 52428800)
  #|      --max-files N              Nonnegative candidate limit (default: 20000)
  #|      --max-total-size N         Nonnegative raw-read limit (default: 209715200)
  #|      --max-git-bytes N          Aggregate Git text limit (default: 8388608)
  #|  Split conflicts with --stdout, -o -, and --budget; index is counted separately.
  #|  A split target must not exist; its existing parent stays under your control.
  #|
  #|Git and remote repositories:
  #|      --include-diffs / --no-include-diffs  Staged and unstaged Git patches
  #|      --include-logs / --no-include-logs    Recent commit messages and paths
  #|      --include-logs-count N     Commit limit (default: 50; max: 10000)
  #|      --remote HTTPS_URL         Fetch a public repository into a temporary root
  #|      --remote-branch REF        Remote branch, tag or revision
  #|  Git is required for diff/log/remote; log count alone does not enable logs.
  #|
  #|Templates and presentation:
  #|      --header-text TEXT         Scanned header (UTF-8, at most 1 MiB)
  #|      --instruction-file-path FILE  Scanned local instruction file (1 MiB)
  #|      --full-metadata / --no-full-metadata  Per-file records and source maps
  #|      --output-show-line-numbers / --no-output-show-line-numbers
  #|      --output-file-path-style STYLE  target-relative|cwd-relative|absolute
  #|      --file-summary / --no-file-summary
  #|      --directory-structure / --no-directory-structure
  #|      --files / --no-files
  #|      --git-sections / --no-git-sections
  #|      --metadata / --no-metadata
  #|  Display controls preserve canonical bodies, paths and source maps.
  #|  Final counts include templates, displayed paths, line prefixes and all sections.
  #|
  #|Reports and resources:
  #|      --report-json / --no-report-json  One machine-readable report on stderr
  #|      --top-files-len N          Top content-token files (default: 5; 0 hides)
  #|      --token-count-tree [N]     Content-token tree; optional minimum (>= 0)
  #|      --token-count-encoding NAME  Only o200k_base is supported
  #|      --tokenizer-path PATH      Explicit o200k_base.tiktoken resource
  #|      --quiet / --verbose        Diagnostic level (mutually exclusive)
  #|  --report-json overrides quiet. File/directory sums are not final document counts.
  #|  Place directory before --token-count-tree, or separate it with --.
  #|
  #|Local services:
  #|      --webui                    Read-only local Web UI on 127.0.0.1
  #|      --webui-port PORT          Port (default: 8765; range: 1..65535)
  #|      --mcp                      Authorized local context over MCP stdio
  #|      --mcp-max-tokens N         Host per-volume cap (default: 16000)
  #|      --mcp-max-output-bytes N    Cache cap (default: 16777216)
  #|      --mcp-max-volumes N        Volume count (default: 64; max: 256)
  #|  Web UI prints its URL; its startup directory is the authorized workspace.
  #|  Web UI accepts workspace, port, tokenizer and file/size limits; other flags fail.
  #|  MCP fixes root and limits; clients read only derived in-memory resources.
  #|  MCP conflicts with stdin/stdout/report-json, remote, split and single budgets.
  #|
  #|Configuration and actions:
  #|  -c, --config PATH              Select JSON configuration
  #|      --init                     Create configuration without overwriting
  #|      --parsable-style           Accepted compatibility option
  #|  -h, --help                     Show the quick reference
  #|      --help-all                 Show this complete reference
  #|  -v, --version                  Show version without loading resources
  #|  Default config: <directory>/repomix.config.json.
  #|  Remote and MCP load explicit local config only; Web UI ignores repository config.
  #|  Output and explicit config paths are relative to the working directory.
  #|  --key=value and separate values work; short options are not combined.
  #|  Same-setting aliases obey last-value-wins; JSON field names stay unchanged.
  #|  Stdin is explicit, bounded to 8 MiB, and preserves ignore/scanning checks.
  #|  Empty stdin selects zero files; literal paths are relative to the input root.
  #|  With stdout, redirect outside the input root or explicitly ignore the target.
  #|
