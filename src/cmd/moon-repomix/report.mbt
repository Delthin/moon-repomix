///|
/// JSON quoting keeps file names from injecting terminal lines or control codes.
fn quote(path : String) -> String {
  Json::string(path).stringify()
}

///|
async fn report_volumes(
  result : @repomix.VolumePackResult,
  options : @config.Options,
  cap : Int32,
) -> Unit {
  if result.files.is_empty() {
    @stdio.stderr.write("Warning: no files were accepted.\n")
  }
  if options.quiet {
    return
  }
  @stdio.stderr.write(
    "Packed \{result.files.length()} files into \{result.partition.volumes.length()} volumes, \{result.partition.total_tokens} tokens including index (o200k_base); per-volume limit \{cap}.\n",
  )
  @stdio.stderr.write(
    "Skipped \{result.skipped.length()} entries; secret findings: \{result.findings.length()}.\n",
  )
  for volume in result.partition.volumes {
    @stdio.stderr.write(
      "Volume " +
      quote(result.file_names[volume.id]) +
      ": \{volume.bytes} bytes, \{volume.tokens} tokens\n",
    )
  }
  for item in result.skipped {
    @stdio.stderr.write(
      "Skipped " + quote(item.path) + ": " + quote(item.reason) + "\n",
    )
  }
  for hit in result.findings {
    @stdio.stderr.write(
      "Security " +
      hit.rule +
      " " +
      quote(hit.path) +
      ":\{hit.line} bytes [\{hit.start}, \{hit.end})\n",
    )
  }
  let top = top_files(result.files, options.top_files_length)
  if !top.is_empty() {
    @stdio.stderr.write(top)
  }
  if options.token_count_tree is Enabled(threshold) {
    @stdio.stderr.write(token_tree(result.files, threshold))
  }
}

///|
async fn report(
  result : @repomix.PackResult,
  options : @config.Options,
) -> Unit {
  if result.files.is_empty() {
    @stdio.stderr.write("Warning: no files were accepted.\n")
  }
  if !options.quiet {
    @stdio.stderr.write(
      "Packed \{result.files.length()} files, \{result.bytes} bytes, \{result.tokens} tokens (o200k_base).\n",
    )
    @stdio.stderr.write(
      "Skipped \{result.skipped.length()} entries; secret findings: \{result.findings.length()}.\n",
    )
    if options.compress {
      let mut original = 0L
      let mut rendered = 0L
      for file in result.files {
        original += file.original_tokens.to_int64()
        rendered += file.tokens.to_int64()
      }
      @stdio.stderr.write(
        "File-body tokens: \{original} original -> \{rendered} processed.\n",
      )
    }
    if !result.document.sections.is_empty() {
      @stdio.stderr.write(
        "Git context: \{result.document.sections.length()} sections.\n",
      )
    }
    for item in result.skipped {
      @stdio.stderr.write(
        "Skipped " + quote(item.path) + ": " + quote(item.reason) + "\n",
      )
    }
    for hit in result.findings {
      @stdio.stderr.write(
        "Security " +
        hit.rule +
        " " +
        quote(hit.path) +
        ":\{hit.line} bytes [\{hit.start}, \{hit.end})\n",
      )
    }
    let top = top_files(result.files, options.top_files_length)
    if !top.is_empty() {
      @stdio.stderr.write(top)
    }
    if options.token_count_tree is Enabled(threshold) {
      @stdio.stderr.write(token_tree(result.files, threshold))
    }
    if options.verbose {
      for file in result.files {
        @stdio.stderr.write(
          "File " +
          quote(file.path) +
          ": \{file.disk_bytes} bytes, \{file.tokens} tokens\n",
        )
      }
    }
  }
  if result.budget is Exceeded(limit) {
    @stdio.stderr.write(
      "Token budget exceeded: \{result.tokens} > \{limit}; complete output retained.\n",
    )
  }
}
