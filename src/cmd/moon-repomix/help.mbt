///|
let help : String =
  #|moon-repomix — pack local or remote repository context
  #|Usage: moon-repomix [directory] [options]
  #|
  #|  -o, --output PATH              Output file; '-' writes stdout, './-' is a file
  #|      --stdout                   Write only the document to stdout
  #|      --stdin                    Read a literal UTF-8 file list, one path per line
  #|      --stdin0                   Read a NUL-separated file list (for git -z)
  #|      --style FORMAT             xml|markdown|json|plain (default: xml)
  #|      --compress / --no-compress  Syntax-tree code skeletons with source lines
  #|      --keep-full GLOBS          Keep matching files intact when compressing
  #|      --header-text TEXT         Add a scanned header (UTF-8, at most 1 MiB)
  #|      --instruction-file-path FILE  Add a scanned local instruction file (1 MiB)
  #|      --full-metadata            Full per-file records and source maps in any format
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
  #|Remote inputs use explicit local config only; filter paths with --include.
  #|Git is required only for diff/log/remote. Remote inputs keep enough log history.
  #|Default output: repomix-output.xml, .md, .json or .txt for the chosen format.
  #|Token reports use stderr and are hidden by --quiet.
  #|Place directory before --token-count-tree, or separate it with --.
  #|Directory token sums are not the final document count used for budgets.
  #|All formats use a metadata overview by default; --full-metadata keeps per-file records.
  #|Stdin modes are exclusive, bounded to 8 MiB, and never bypass ignore/scanning.
  #|Empty stdin selects zero files; paths are literal and relative to the input root.
  #|With --stdout, redirect outside the input root or explicitly ignore the target.
  #|
