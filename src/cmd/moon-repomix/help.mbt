///|
let help : String =
  #|moon-repomix — pack a local repository
  #|Usage: moon-repomix [directory] [options]
  #|
  #|  -o, --output PATH              Output file (relative to working directory)
  #|      --stdout                   Write only the document to stdout
  #|      --style FORMAT             xml|markdown|json|plain (default: xml)
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
  #|Default output: repomix-output.xml, .md, .json or .txt for the chosen format.
  #|Token reports use stderr and are hidden by --quiet.
  #|Place directory before --token-count-tree, or separate it with --.
  #|Directory token sums are not the final document count used for budgets.
  #|With --stdout, redirect outside the input root or explicitly ignore the target.
  #|
