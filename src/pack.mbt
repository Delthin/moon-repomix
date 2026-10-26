///|
priv struct PreparedPack {
  document : Document
  display : @output.Display
  files : Array[FileStats]
  skipped : Array[Skipped]
  findings : Array[Finding]
  security : SecurityStatus
}

///|
/// Build and count a complete document. Remote inputs are fetched and cleaned here.
/// The caller decides where to write the result.
pub async fn pack(options : Options, runtime : Runtime) -> PackResult {
  let prepared = prepare_pack(options, runtime)
  let text = render_document(
    prepared.document,
    options.style,
    options.full_metadata,
    prepared.display,
  )
  @async.sleep(0)
  let tokens = runtime.encoder.count(text)
  let budget = match options.token_budget {
    None => NotSet
    Some(limit) if tokens > limit => Exceeded(limit)
    Some(limit) => Within(limit)
  }
  {
    document: prepared.document,
    text,
    bytes: @utf8.encode(text).length(),
    tokens,
    files: prepared.files,
    skipped: prepared.skipped,
    findings: prepared.findings,
    security: prepared.security,
    budget,
  }
}

///|
async fn prepare_pack(options : Options, runtime : Runtime) -> PreparedPack {
  validate_source_limits(options)
  if options.max_git_bytes <= 0 ||
    options.include_logs_count <= 0 ||
    options.include_logs_count > 10000 ||
    options.encoding != "o200k_base" ||
    (options.token_budget is Some(n) && n <= 0) ||
    (options.remote is None && options.remote_branch is Some(_)) {
    raise ConfigurationError
  }
  let keep_full = @selection.file_matcher(options.keep_full_patterns) catch {
    _ => raise ConfigurationError
  }
  let context = prepare_context_texts(options)
  match options.remote {
    None => pack_directory(options, runtime, Json::null(), keep_full, context)
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
      pack_directory(
        local_options,
        runtime,
        { "kind": "remote", "url": checkout.url, "revision": checkout.revision },
        keep_full,
        context,
      )
    }
  }
}

///|
async fn pack_directory(
  options : Options,
  runtime : Runtime,
  remote_source : Json,
  keep_full : @selection.FileMatcher,
  context : ContextTexts,
) -> PreparedPack {
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
  let selected = @selection.select(
    root,
    selection_options,
    file_paths=options.file_paths,
    max_files=options.max_files,
  ) catch {
    @selection.SelectionError::FileLimitExceeded(limit~) =>
      raise InputLimitExceeded(kind="maxFiles", limit=limit.to_int64())
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
  let pipeline = FilePipeline::new(
    runtime,
    options.compress,
    accepted,
    files,
    transforms,
  )
  defer pipeline.close()
  let mut since_timer_poll = 0
  let mut read_bytes = 0L
  for candidate in selected.files {
    // pause keeps the task cancellable without creating an OS timer per file.
    // Periodically poll timers as well, including when filesystem calls finish
    // synchronously, so a busy ready queue cannot starve timeout cancellation.
    if since_timer_poll >= 32 {
      @async.sleep(0)
      since_timer_poll = 0
    } else {
      @async.pause()
      since_timer_poll += 1
    }
    let screened = read_screened(
      candidate,
      options,
      options.max_total_size - read_bytes,
    )
    read_bytes += screened.read_bytes
    findings.append(screened.findings)
    match screened.result {
      Skipped(reason) => {
        skipped.push({ path: candidate.relative, reason, })
        excluded.add(context_path_key(candidate.relative))
      }
      Loaded(snapshot) =>
        pipeline.push(
          candidate.relative,
          snapshot,
          options.compress && keep_full.matches(candidate.relative),
        )
    }
  }
  pipeline.flush()
  pipeline.close()
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
  let document = @document.create(
    accepted,
    sections=git.sections,
    metadata~,
    header_text=context.header,
    instruction_text=context.instructions,
  )
  let display = display_for(options, selected.root, cwd)
  {
    document,
    display,
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
  }
}
