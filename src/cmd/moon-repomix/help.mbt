///|
let help : String =
  #|moon-repomix — pack local or remote repository context
  #|Usage: moon-repomix [directory] [options]
  #|
  #|  -o, --output PATH              Output file; '-' writes stdout, './-' is a file
  #|      --stdout                   Write only the document to stdout
  #|      --stdin                    Read a literal UTF-8 file list, one path per line
  #|      --stdin0                   Read a NUL-separated file list (for git -z)
  #|      --explain-path PATH        Explain one literal local path; repeat up to 256
  #|      --style FORMAT             xml|markdown|json|plain (default: xml)
  #|      --compress / --no-compress  Syntax-tree code skeletons with source lines
  #|      --keep-full GLOBS          Keep matching files intact when compressing
  #|      --header-text TEXT         Add a scanned header (UTF-8, at most 1 MiB)
  #|      --instruction-file-path FILE  Add a scanned local instruction file (1 MiB)
  #|      --full-metadata            Full per-file records and source maps in any format
  #|      --output-show-line-numbers Prefix each displayed file line with its number
  #|      --output-file-path-style STYLE  target-relative|cwd-relative|absolute
  #|      --no-file-summary          Hide the introductory notice
  #|      --no-directory-structure   Hide the directory tree
  #|      --no-files                 Hide file bodies; keep accepted-file context
  #|      --no-git-sections          Hide Git section bodies, not collection or metadata
  #|      --no-metadata              Hide the metadata section
  #|      --include-diffs            Export staged and unstaged Git patches
  #|      --include-logs             Export recent Git commit messages and paths
  #|      --include-logs-count N     Commit limit (default: 50; max: 10000)
  #|      --remote HTTPS_URL         Fetch a public repository into a temporary root
  #|      --remote-branch REF        Remote branch, tag or revision
  #|      --max-git-bytes N          Aggregate Git text limit (default: 8388608)
  #|      --include GLOBS            Root-relative filters; supports {a,b} alternatives
  #|  -i, --ignore GLOBS             Comma-separated exclusion filters
  #|      --no-gitignore             Disable .gitignore and Git exclude rules
  #|      --no-dot-ignore            Disable .ignore; .repomixignore still applies
  #|      --no-default-patterns      Disable built-in excludes
  #|      --no-security-check        Disable secret scanning (warns)
  #|      --token-count-encoding NAME  Only o200k_base is supported
  #|      --token-budget N           Positive limit; output is kept if exceeded
  #|      --split-output N           Exact token cap per volume; -o names a new directory
  #|      --no-split-output          Disable configured volume output
  #|      --report-json              One machine-readable report on stderr
  #|      --mcp                      Serve authorized local context over MCP stdio
  #|      --mcp-max-tokens N         Host per-volume cap (default: 16000)
  #|      --mcp-max-output-bytes N   Cached context cap (default: 16777216)
  #|      --mcp-max-volumes N        Cached volume count (default: 64; max: 256)
  #|      --max-files N              Nonnegative candidate limit (default: 20000)
  #|      --max-total-size N         Nonnegative raw-read byte limit (default: 209715200)
  #|      --top-files-len N          Top content-token files (default: 5; 0 hides)
  #|      --token-count-tree [N]     Content-token tree; optional minimum (>= 0)
  #|      --tokenizer-path PATH      Explicit o200k_base.tiktoken resource
  #|  -c, --config PATH              Select JSON configuration
  #|      --init                     Create configuration without overwriting
  #|      --parsable-style           Accepted compatibility option
  #|      --quiet / --verbose        Diagnostic level (mutually exclusive)
  #|  -h, --help                     Show this help without loading resources
  #|  -v, --version                  Show version without loading resources
  #|
  #|Default config: <directory>/repomix.config.json.
  #|Remote inputs and MCP use explicit local config only; filter paths with --include.
  #|MCP fixes the startup root and limits; clients only read derived in-memory resources.
  #|MCP conflicts with stdin/stdout/report-json, remote, split output and single budgets.
  #|Git is required only for diff/log/remote. Remote inputs keep enough log history.
  #|Default output: repomix-output.xml, .md, .json or .txt for the chosen format.
  #|Token reports use stderr and are hidden by --quiet; --report-json overrides quiet.
  #|Split output conflicts with --stdout, -o -, and --token-budget; index is counted separately.
  #|A split target must not exist; its existing parent stays under your control.
  #|Place directory before --token-count-tree, or separate it with --.
  #|Directory token sums are not the final document count used for budgets.
  #|All formats use a metadata overview by default; --full-metadata keeps per-file records.
  #|Positive chapter flags restore JSON false values; --no-output-show-line-numbers clears numbering.
  #|Display controls keep canonical library bodies/paths and source maps unchanged.
  #|Final budgets include displayed paths, line prefixes and all rendered sections.
  #|Stdin modes are exclusive, bounded to 8 MiB, and never bypass ignore/scanning.
  #|Empty stdin selects zero files; paths are literal and relative to the input root.
  #|With --stdout, redirect outside the input root or explicitly ignore the target.
  #|
