///|
/// Build and count a complete document. The caller decides where to write it.
pub async fn pack(options : Options, runtime : Runtime) -> PackResult {
  if options.max_file_size <= 0 ||
    options.encoding != "o200k_base" ||
    (options.token_budget is Some(n) && n <= 0) {
    raise ConfigurationError
  }
  let cwd = @env.current_dir().unwrap_or(".")
  let root = @platform.absolute(options.directory, cwd)
  let destination = if options.stdout {
    None
  } else {
    Some(
      @platform.output_path(options.output, cwd) catch {
        err => {
          if @async.is_cancellation_error(err) {
            raise err
          }
          raise ConfigurationError
        }
      },
    )
  }
  let selected = @selection.select(root, {
    include_patterns: options.include_patterns,
    ignore: options.ignore,
    use_gitignore: options.use_gitignore,
    use_dot_ignore: options.use_dot_ignore,
    use_default_patterns: options.use_default_patterns,
    output: destination,
  }) catch {
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      raise SelectionError
    }
  }
  let accepted : Array[@document.File] = []
  let files : Array[FileStats] = []
  let skipped = selected.skipped.copy()
  let findings : Array[Finding] = []
  for candidate in selected.files {
    // Yield between files to let pending cancellation stop the operation.
    @async.sleep(0)
    match @input.read(candidate.path, options.max_file_size) {
      Skipped(reason) => skipped.push({ path: candidate.relative, reason, })
      Loaded(snapshot) => {
        if options.security_check {
          let hits = @security.scan(
            candidate.relative,
            snapshot.text,
            snapshot.bom_bytes,
          ) catch {
            _ => raise ScanError
          }
          if !hits.is_empty() {
            findings.append(hits)
            skipped.push({
              path: candidate.relative,
              reason: "SecurityFinding",
            })
            continue
          }
        }
        if options.style is Xml &&
          (
            !@output.xml_representable(candidate.relative) ||
            !@output.xml_representable(snapshot.text)
          ) {
          skipped.push({
            path: candidate.relative,
            reason: "UnrepresentableText",
          })
          continue
        }
        let tokens = runtime.encoder.count(snapshot.text)
        accepted.push({ path: candidate.relative, text: snapshot.text, })
        files.push({
          path: candidate.relative,
          disk_bytes: snapshot.disk_bytes,
          tokens,
        })
      }
    }
  }
  let document = @document.create(accepted)
  let text = match options.style {
    Xml => @output.xml(document)
    Markdown => @output.markdown(document)
  }
  @async.sleep(0)
  let tokens = runtime.encoder.count(text)
  let budget = match options.token_budget {
    None => NotSet
    Some(limit) if tokens > limit => Exceeded(limit)
    Some(limit) => Within(limit)
  }
  {
    text,
    bytes: @utf8.encode(text).length(),
    tokens,
    files,
    skipped,
    findings,
    security: if !options.security_check {
      Disabled
    } else if findings.is_empty() {
      Passed
    } else {
      Excluded
    },
    budget,
  }
}
