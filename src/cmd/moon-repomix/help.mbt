///|
let help : String =
  #|moon-repomix — pack local or remote repository context
  #|Usage: moon-repomix [directory] [options]
  #|
  #|  -o, --output PATH              Output file (relative to working directory)
  #|      --stdout                   Write only the document to stdout
  #|      --style FORMAT             xml|markdown|json|plain (default: xml)
  #|      --compress / --no-compress  Syntax-tree code skeletons with source lines
  #|      --full-metadata            Full file/source maps in Markdown or plain
  #|      --include-diffs            Export staged and unstaged Git patches
  #|      --include-logs             Export recent Git commit messages and paths
  #|      --include-logs-count N     Commit limit (default: 50; max: 10000)
  #|      --remote HTTPS_URL         Fetch a public repository into a temporary root
  #|      --remote-branch REF        Remote branch, tag or revision
  #|      --max-git-bytes N          Aggregate Git text limit (default: 8388608)
  #|      --include GLOBS            Comma-separated positive filters
  #|  -i, --ignore GLOBS             Comma-separated exclusion filters
  #|      --no-gitignore             Disable .gitignore and Git exclude rules
  #|      --no-dot-ignore            Disable .ignore and .repomixignore
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
  #|Markdown/plain use a metadata overview by default; JSON/XML keep full records.
  #|With --stdout, redirect outside the input root or explicitly ignore the target.
  #|
