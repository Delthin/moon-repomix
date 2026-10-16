# Output and file handling

The packer reads complete regular-file snapshots as strict UTF-8, removes an initial UTF-8 BOM, and preserves all other newline bytes. NUL-bearing, invalid UTF-8, unreadable and oversized files are skipped. The default maximum file size is 52,428,800 bytes; reading enforces the limit even if a file grows after the initial size check.

XML preserves accepted body text and relative paths after XML parsing. Carriage returns are character references; path attributes also encode line feeds and tabs. Files whose path or body contains an XML 1.0 forbidden character are omitted from XML output. Markdown uses a backtick fence longer than any run in the body and escapes the file heading. Markdown may add a final newline before a closing fence. Both formats contain an accepted-file directory outline and a reminder that repository contents are untrusted data.

Paths are sorted by their UTF-8 byte representation. No Unicode normalization or case folding is performed.

File output is written to a new sibling temporary file, synchronized, closed, then renamed over the destination. Links and non-regular destinations are rejected. Failure before replacement keeps the previous file; temporary-file cleanup also runs during task cancellation. stdout is written only after packing and token counting complete, but cannot be rolled back once writing starts.

The executable locates its vocabulary at `../share/moon-repomix/o200k_base.tiktoken` relative to its resolved executable path. Platform code uses the operating system's executable-path API, so resource discovery does not depend on the working directory.

Filesystem type checks and later opens are separate operations. Concurrent path replacement can race those checks; this is a local packer, not an operating-system sandbox. Windows replacement and reparse-point handling require verification on the Windows runner.
