///|
extern "c" fn exit(code : Int32) -> Unit = "exit"

///|
async fn read_config(cli : @config.Cli, cwd : String) -> @config.Patch? {
  let explicit = cli.config_path is Some(_)
  if cli.mcp && !explicit {
    return None
  }
  if !explicit && cli.patch.remote is Some(_) {
    return None
  }
  let path = match cli.config_path {
    Some(path) => @platform.absolute(path, cwd)
    None =>
      @platform.join(
        @platform.absolute(cli.directory, cwd),
        "repomix.config.json",
      )
  }
  let kind = @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_, context=_) as err if !explicit && err.is_ENOENT() =>
      return None
    _ => raise Configuration
  }
  if kind != @fs.Regular {
    raise Configuration
  }
  let text = @fs.read_file(path).text() catch { _ => raise Configuration }
  let patch = @config.parse_json(text) catch { _ => raise Configuration }
  if !explicit && patch.remote is Some(_) {
    raise Configuration
  }
  Some(patch)
}

///|
suberror CliError {
  Configuration
  Resource
  Write
  InputList
}

///|
priv struct RunState {
  mut report_json : Bool
  mut publication : String
}

///|
async fn run(cli : @config.Cli, state : RunState) -> Int32 {
  match cli.action {
    Help => {
      @stdio.stdout.write(help)
      return 0
    }
    Version => {
      @stdio.stdout.write("moon-repomix " + @repomix.version() + "\n")
      return 0
    }
    _ => ()
  }
  let cwd = @env.current_dir().unwrap_or(".")
  if cli.action is Init {
    if cli.patch.remote is Some(_) {
      raise Configuration
    }
    let path = match cli.config_path {
      Some(path) => @platform.absolute(path, cwd)
      None =>
        @platform.join(
          @platform.absolute(cli.directory, cwd),
          "repomix.config.json",
        )
    }
    state.publication = "unknown"
    @platform.create_new(
      path, "{\n  \"output\": { \"style\": \"xml\" },\n  \"security\": { \"enableSecurityCheck\": true }\n}\n",
    ) catch {
      err => {
        if @async.is_cancellation_error(err) {
          raise err
        }
        raise Write
      }
    }
    state.publication = "committed"
    @async.protect_from_cancel(
      () => {
        if cli.report_json {
          write_json_report({
            "schemaVersion": 1,
            "status": "ok",
            "operation": "init",
            "publication": "committed",
            "exitCode": 0,
          })
        } else if !cli.quiet {
          @stdio.stderr.write("Created configuration.\n")
        }
      },
      resume_on_cancel=false,
    )
    return 0
  }
  let patch = read_config(cli, cwd)
  let resolved = @config.resolve(cli, patch) catch { _ => raise Configuration }
  if cli.mcp &&
    (
      resolved.remote is Some(_) ||
      resolved.stdout ||
      resolved.split_output is Enabled(_) ||
      resolved.token_budget is Some(_)
    ) {
    raise Configuration
  }
  let directory_target = match resolved.split_output {
    Disabled => None
    Enabled(_) =>
      Some(
        @platform.directory_output_path(resolved.output, cwd) catch {
          err => {
            if @async.is_cancellation_error(err) {
              raise err
            }
            raise Write
          }
        },
      )
  }
  let options = match read_stdin(cli.stdin_mode) {
    None => resolved
    Some(paths) => { ..resolved, file_paths: Some(paths), }
  }
  if !options.security_check && !cli.report_json {
    @stdio.stderr.write("Warning: secret scanning is disabled.\n")
  }
  let resource = match options.tokenizer_path {
    Some(path) => @platform.absolute(path, cwd)
    None => @platform.tokenizer_path() catch { _ => raise Resource }
  }
  let runtime = @repomix.Runtime::load(resource)
  if cli.mcp {
    @mcp.serve(
      options,
      runtime,
      max_tokens=cli.mcp_max_tokens,
      max_output_bytes=cli.mcp_max_output_bytes,
      max_volumes=cli.mcp_max_volumes,
    )
    return 0
  }
  if options.split_output is Enabled(cap) {
    let target = directory_target.unwrap()
    let split_options = { ..options, output: target, }
    let result = @repomix.pack_volumes(split_options, runtime, max_tokens=cap)
    let entries : Array[@platform.DirectoryEntry] = []
    for volume in result.partition.volumes {
      entries.push({ name: result.file_names[volume.id], text: volume.text, })
    }
    entries.push({ name: "index.json", text: result.partition.index_text, })
    state.publication = "unknown"
    @platform.commit_directory(target, entries) catch {
      err => {
        if @async.is_cancellation_error(err) {
          raise err
        }
        raise Write
      }
    }
    state.publication = "committed"
    @async.protect_from_cancel(
      () => {
        if cli.report_json {
          write_json_report(volumes_report(result, split_options, cap))
        } else {
          report_volumes(result, split_options, cap)
        }
      },
      resume_on_cancel=false,
    )
    return 0
  }
  let result = @repomix.pack(options, runtime)
  if options.stdout {
    state.publication = "unknown"
    @stdio.stdout.write(result.text) catch {
      err => {
        if @async.is_cancellation_error(err) {
          raise err
        }
        raise Write
      }
    }
  } else {
    let path = @platform.output_path(options.output, cwd) catch {
      err => {
        if @async.is_cancellation_error(err) {
          raise err
        }
        raise Write
      }
    }
    state.publication = "unknown"
    @platform.commit(path, result.text) catch {
      err => {
        if @async.is_cancellation_error(err) {
          raise err
        }
        raise Write
      }
    }
  }
  state.publication = "committed"
  @async.protect_from_cancel(
    () => {
      if cli.report_json {
        write_json_report(single_report(result, options))
      } else {
        report(result, options)
      }
    },
    resume_on_cancel=false,
  )
  if result.budget is Exceeded(_) {
    1
  } else {
    0
  }
}

///|
async fn main {
  let argv = @env.args()
  // Preserve machine diagnostics even when a later option fails to parse.
  let state = { report_json: false, publication: "not_started", }
  for arg in argv[1:] {
    if arg == "--" {
      break
    }
    if arg == "--report-json" {
      state.report_json = true
    }
    if arg == "--no-report-json" {
      state.report_json = false
    }
  }
  let code = try {
    let cli = @config.parse_cli(argv[1:].to_owned()) catch {
      _ => raise Configuration
    }
    state.report_json = cli.report_json
    run(cli, state)
  } catch {
    err => {
      let mut field : String? = None
      let mut limit : Int64? = None
      match err {
        @repomix.ContextTextError(value)
        | @repomix.ContextSecurityFinding(value) => field = Some(value)
        @repomix.InputLimitExceeded(kind~, limit=maximum) => {
          field = Some("input." + kind)
          limit = Some(maximum)
        }
        _ => ()
      }
      let category = if @async.is_cancellation_error(err) {
        "Cancelled"
      } else {
        match err {
          Configuration | @repomix.ConfigurationError => "ConfigurationError"
          @repomix.ContextTextError(field) => "ContextTextError (" + field + ")"
          @repomix.ContextSecurityFinding(field) =>
            "ContextSecurityError (" + field + ")"
          @repomix.SelectionError => "SelectionError"
          @repomix.ScanError => "ScanError"
          @repomix.GitError => "GitError"
          @repomix.RemoteError => "RemoteError"
          @repomix.InputLimitExceeded(kind~, limit=maximum) =>
            "InputLimitError (input." +
            kind +
            "; limit=" +
            maximum.to_string() +
            ")"
          @repomix.PartitionError::InvalidCap(_)
          | @repomix.PartitionError::DuplicatePath(_)
          | @repomix.PartitionError::TemplateTooLarge(_)
          | @repomix.PartitionError::UnitTooLarge(_, _)
          | @repomix.PartitionError::InvalidCount(_)
          | @repomix.PartitionError::Overflow(_)
          | @repomix.PartitionError::InvalidTextEncoding => "SplitError"
          Resource | @repomix.ResourceError => "ResourceError"
          Write => "OutputError"
          InputList => "InputError"
          _ =>
            if state.publication == "not_started" {
              "OperationError"
            } else {
              "OutputError"
            }
        }
      }
      @async.protect_from_cancel(
        () => {
          if state.report_json {
            let safe_category = match err {
              @repomix.ContextTextError(_) => "ContextTextError"
              @repomix.ContextSecurityFinding(_) => "ContextSecurityError"
              @repomix.InputLimitExceeded(kind=_, limit=_) => "InputLimitError"
              _ => category
            }
            write_json_report(
              error_report(safe_category, field, limit, state.publication),
            ) catch {
              _ => ()
            }
          } else {
            let output_note = match state.publication {
              "committed" => "; complete output already published"
              "unknown" => "; output publication state unknown"
              _ => ""
            }
            @stdio.stderr.write(
              "moon-repomix: " + category + output_note + "\n",
            ) catch {
              _ => ()
            }
          }
        },
        resume_on_cancel=false,
      )
      1
    }
  }
  if code != 0 {
    exit(code)
  }
}
