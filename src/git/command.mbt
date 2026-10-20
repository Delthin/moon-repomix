///|
priv struct Budget {
  mut remaining : Int32
  filters : Array[String]
}

///|
fn null_device() -> String {
  if @platform.is_windows() {
    "NUL"
  } else {
    "/dev/null"
  }
}

///|
fn safe_arguments(
  directory : String,
  args : Array[String],
  budget : Budget,
) -> Array[String] {
  let null = null_device()
  let result = [
    "--no-pager",
    "--no-optional-locks",
    "--literal-pathspecs",
    "-c",
    "core.fsmonitor=false",
    "-c",
    "core.protectHFS=true",
    "-c",
    "core.protectNTFS=true",
    "-c",
    "core.hooksPath=" + null,
    "-c",
    "core.askPass=",
    "-c",
    "credential.helper=",
    "-c",
    "credential.interactive=false",
    "-c",
    "log.showSignature=false",
    "-c",
    "diff.external=",
    "-c",
    "protocol.allow=never",
    "-c",
    "protocol.https.allow=always",
    "-c",
    "http.followRedirects=false",
    "-c",
    "http.sslVerify=true",
    "-c",
    "http.extraHeader=",
    "-c",
    "fetch.recurseSubmodules=false",
    "-c",
    "submodule.recurse=false",
    "-c",
    "maintenance.auto=false",
    "-c",
    "gc.auto=0",
    "-c",
    "core.attributesFile=" + null,
    "-c",
    "core.excludesFile=" + null,
    "-c",
    "core.quotePath=true",
    "-C",
    directory,
  ]
  result.append(budget.filters)
  result.append(args)
  result
}

///|
fn safe_environment() -> Map[String, String] {
  let null = null_device()
  let environment = {
    "HOME": null,
    "XDG_CONFIG_HOME": null,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": null,
    "GIT_CONFIG_SYSTEM": null,
    "GIT_TERMINAL_PROMPT": "0",
    "GCM_INTERACTIVE": "never",
    "GIT_NO_REPLACE_OBJECTS": "1",
    "GIT_NO_LAZY_FETCH": "1",
    "GIT_ATTR_NOSYSTEM": "1",
    "GIT_LFS_SKIP_SMUDGE": "1",
    "LC_ALL": "C",
  }
  // Preserve executable discovery and OS runtime requirements, not arbitrary
  // GIT_*, proxy, shell, credential, preload or Git helper environment variables.
  for
    key in ["PATH", "SystemRoot", "WINDIR", "TEMP", "TMP", "TMPDIR", "PATHEXT"] {
    if @env.get_env_var(key) is Some(value) {
      environment[key] = value
    }
  }
  environment
}

///|
async fn read_bounded(
  reader : @process.ReadFromProcess,
  budget : Budget,
  keep~ : Bool,
) -> Bytes {
  defer reader.close()
  let buffer = @buffer.Buffer()
  while reader.read_some(max_len=8192) is Some(bytes) {
    if bytes.length() > budget.remaining {
      raise OutputLimit
    }
    budget.remaining -= bytes.length()
    if keep {
      buffer.write_bytes(bytes)
    }
  }
  buffer.to_bytes()
}

///|
// Every invocation, including probes/init/fetch/checkout, goes through here.
// Structured concurrency kills and waits for the child on timeout/cancellation
// or a pipe limit failure. Never include child diagnostics in an error.
async fn git_raw(
  directory : String,
  args : Array[String],
  budget : Budget,
) -> (Int32, String) {
  @async.with_timeout(30000, () => {
    let (stdout, out_pipe) = @process.read_from_process()
    defer stdout.close()
    let (stderr, err_pipe) = @process.read_from_process()
    defer stderr.close()
    let input = @process.redirect_from_file(null_device())
    @async.with_task_group(group => {
      let child = group.spawn(() => {
        @process.run(
          "git",
          safe_arguments(directory, args, budget),
          inherit_env=false,
          extra_env=safe_environment(),
          stdin=input,
          stdout=out_pipe,
          stderr=err_pipe,
          cancel_handler=@process.hard_cancel(),
        )
      })
      let output = group.spawn(() => read_bounded(stdout, budget, keep=true))
      group.spawn_bg(() => ignore(read_bounded(stderr, budget, keep=false)))
      let code = child.wait()
      let bytes = output.wait()
      let text = @utf8.decode(bytes, ignore_bom=true) catch {
        _ => raise InvalidOutput
      }
      (code, text)
    })
  })
}

///|
async fn git(
  directory : String,
  args : Array[String],
  budget : Budget,
) -> String {
  let (code, text) = git_raw(directory, args, budget)
  if code != 0 {
    raise CommandFailed(args[0], code)
  }
  text
}

///|
fn line(text : String) -> String raise {
  guard text.has_suffix("\n") else { raise InvalidOutput }
  text[:text.length() - 1].to_owned()
}

///|
fn nul_fields(text : String) -> Array[String] raise {
  if text.is_empty() {
    return []
  }
  guard text.has_suffix("\u0000") else { raise InvalidOutput }
  text[:text.length() - 1].split("\u0000").map(x => x.to_owned()).collect()
}

///|
fn changed_paths(text : String) -> Array[Array[String]] raise {
  let fields = nul_fields(text)
  let result = []
  for i = 0; i < fields.length(); {
    let status = fields[i]
    let count = if status.has_prefix("R") || status.has_prefix("C") {
      2
    } else {
      1
    }
    guard !status.is_empty() && i + count < fields.length() else {
      raise InvalidOutput
    }
    let paths = []
    for j in 1..<=count {
      let path = fields[i + j]
      guard !path.is_empty() &&
        !path.has_prefix("/") &&
        !path.split("/").any(p => p == "..") else {
        raise InvalidOutput
      }
      paths.push(path)
    }
    result.push(paths)
    continue i + count + 1
  }
  result
}
