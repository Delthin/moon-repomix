///|
extern "c" fn exit(code : Int32) -> Unit = "exit"

///|
async fn read_config(cli : @config.Cli, cwd : String) -> @config.Patch? {
  let explicit = cli.config_path is Some(_)
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
async fn run() -> Int32 {
  let argv = @env.args()
  let cli = @config.parse_cli(argv[1:].to_owned()) catch {
    _ => raise Configuration
  }
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
    @platform.create_new(
      path, "{\n  \"output\": { \"style\": \"xml\" },\n  \"security\": { \"enableSecurityCheck\": true }\n}\n",
    ) catch {
      _ => raise Write
    }
    if !cli.quiet {
      @stdio.stderr.write("Created configuration.\n")
    }
    return 0
  }
  let patch = read_config(cli, cwd)
  let resolved = @config.resolve(cli, patch) catch { _ => raise Configuration }
  let options = match read_stdin(cli.stdin_mode) {
    None => resolved
    Some(paths) => { ..resolved, file_paths: Some(paths), }
  }
  if !options.security_check {
    @stdio.stderr.write("Warning: secret scanning is disabled.\n")
  }
  let resource = match options.tokenizer_path {
    Some(path) => @platform.absolute(path, cwd)
    None => @platform.tokenizer_path() catch { _ => raise Resource }
  }
  let runtime = @repomix.Runtime::load(resource)
  let result = @repomix.pack(options, runtime)
  if options.stdout {
    @stdio.stdout.write(result.text) catch {
      _ => raise Write
    }
  } else {
    let path = @platform.output_path(options.output, cwd) catch {
      _ => raise Write
    }
    @platform.commit(path, result.text) catch {
      _ => raise Write
    }
  }
  report(result, options)
  if result.budget is Exceeded(_) {
    1
  } else {
    0
  }
}

///|
async fn main {
  let code = run() catch {
    err => {
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
          Resource | @repomix.ResourceError => "ResourceError"
          Write => "OutputError"
          InputList => "InputError"
          _ => "OperationError"
        }
      }
      @async.protect_from_cancel(
        () => {
          @stdio.stderr.write("moon-repomix: " + category + "\n") catch {
            _ => ()
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
