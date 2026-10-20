///|
/// Build and count a complete document. Remote inputs are fetched and cleaned here.
/// The caller decides where to write the result.
pub async fn pack(options : Options, runtime : Runtime) -> PackResult {
  if options.max_file_size <= 0 ||
    options.max_git_bytes <= 0 ||
    options.include_logs_count <= 0 ||
    options.include_logs_count > 10000 ||
    options.encoding != "o200k_base" ||
    (options.token_budget is Some(n) && n <= 0) ||
    (options.remote is None && options.remote_branch is Some(_)) {
    raise ConfigurationError
  }
  match options.remote {
    None => pack_directory(options, runtime, Json::null())
    Some(url) => {
      if options.directory != "." {
        raise ConfigurationError
      }
      let history = if options.include_logs {
        options.include_logs_count
      } else {
        0
      }
      let checkout = try {
        match options.remote_branch {
          None => @git.checkout(url, history~)
          Some(revision) => @git.checkout(url, revision~, history~)
        }
      } catch {
        err => {
          if @async.is_cancellation_error(err) {
            raise err
          }
          raise RemoteError
        }
      }
      defer @git.cleanup(checkout)
      let local_options = {
        ..options,
        directory: checkout.directory,
        remote: None,
        remote_branch: None,
      }
      pack_directory(local_options, runtime, {
        "kind": "remote",
        "url": checkout.url,
        "revision": checkout.revision,
      })
    }
  }
}

///|
async fn pack_directory(
  options : Options,
  runtime : Runtime,
  remote_source : Json,
) -> PackResult {
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
  let selection_options : @selection.SelectionOptions = {
    include_patterns: options.include_patterns,
    ignore: options.ignore,
    use_gitignore: options.use_gitignore,
    use_dot_ignore: options.use_dot_ignore,
    use_default_patterns: options.use_default_patterns,
    output: destination,
  }
  let selected = @selection.select(root, selection_options) catch {
    err => {
      if @async.is_cancellation_error(err) {
        raise err
      }
      raise SelectionError
    }
  }
  let accepted : Array[@document.File] = []
  let files : Array[FileStats] = []
  let transforms : Array[Json] = []
  let excluded : Set[String] = Set([])
  let skipped = selected.skipped.copy()
  let findings : Array[Finding] = []
  for candidate in selected.files {
    @async.sleep(0)
    match @input.read(candidate.path, options.max_file_size) {
      Skipped(reason) => {
        skipped.push({ path: candidate.relative, reason, })
        excluded.add(context_path_key(candidate.relative))
      }
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
            excluded.add(context_path_key(candidate.relative))
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
          excluded.add(context_path_key(candidate.relative))
          continue
        }
        let original_tokens = runtime.encoder.count(snapshot.text)
        let mut text = snapshot.text
        let mut tokens = original_tokens
        if options.compress {
          let result = @compression.compress(candidate.relative, snapshot.text)
          let compressed_tokens = if result.applied {
            runtime.encoder.count(result.text)
          } else {
            original_tokens
          }
          let applied = result.applied && compressed_tokens < original_tokens
          if applied {
            text = result.text
            tokens = compressed_tokens
          }
          let ranges : Array[Json] = if applied {
            context_ranges(result.ranges)
          } else {
            []
          }
          let reason : Json = if result.applied && !applied {
            Json("not-fewer-tokens")
          } else {
            match result.reason {
              None => Json::null()
              Some(reason) => Json(reason)
            }
          }
          let language : Json = match result.language {
            None => Json::null()
            Some(name) => Json(name)
          }
          transforms.push({
            "path": candidate.relative,
            "language": language,
            "applied": applied,
            "reason": reason,
            "ranges": ranges,
            "originalTokens": original_tokens,
            "outputTokens": tokens,
          })
        }
        accepted.push({ path: candidate.relative, text, })
        files.push({
          path: candidate.relative,
          disk_bytes: snapshot.disk_bytes,
          tokens,
          original_tokens,
        })
      }
    }
  }
  let git = git_context(
    selected.root,
    options,
    selection_options,
    excluded,
    skipped,
    findings,
  )
  let metadata : Json = if options.compress ||
    options.include_diffs ||
    options.include_logs ||
    remote_source != Json::null() {
    let source : Json = if remote_source != Json::null() {
      remote_source
    } else {
      let revision : Json = match git.revision {
        None => Json::null()
        Some(id) => Json(id)
      }
      { "kind": "local", "revision": revision }
    }
    { "source": source, "compression": transforms, "git": git.metadata }
  } else {
    Json::null()
  }
  if options.style is Xml &&
    metadata != Json::null() &&
    !@output.xml_representable(metadata.stringify()) {
    raise ConfigurationError
  }
  let document = @document.create(accepted, sections=git.sections, metadata~)
  let text = match options.style {
    Xml => @output.xml(document)
    Markdown => @output.markdown(document, full_metadata=options.full_metadata)
    Json => @output.json(document)
    Plain => @output.plain(document, full_metadata=options.full_metadata)
  }
  @async.sleep(0)
  let tokens = runtime.encoder.count(text)
  let budget = match options.token_budget {
    None => NotSet
    Some(limit) if tokens > limit => Exceeded(limit)
    Some(limit) => Within(limit)
  }
  {
    document,
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
