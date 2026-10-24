///|
fn report(result : @repomix.PackResult, budget : Int32) -> Json {
  {
    "status": "ok",
    "counts": {
      "acceptedFiles": result.files.length(),
      "skippedEntries": result.skipped.length(),
    },
    "tokens": { "total": result.tokens.to_string() },
    "bytes": { "total": result.bytes.to_string() },
    "security": {
      "enabled": true,
      "status": if result.security is Excluded {
        "excluded"
      } else {
        "passed"
      },
      "findings": result.findings.length(),
    },
    "budget": { "limit": budget, "exceeded": result.tokens > budget },
  }
}

///|
fn packed_json(result : @repomix.PackResult, budget : Int32) -> Json raise {
  {
    "document": @json.parse(result.text),
    "serialized": result.text,
    "report": report(result, budget),
  }
}

///|
async fn build(state : State, request : PackRequest) -> Json {
  if state.busy {
    raise PublicError(409, "pack_busy", "A pack operation is already running.")
  }
  state.busy = true
  defer {
    state.busy = false
  }
  let response = @async.with_timeout(
    60000,
    () => {
      let directory = scoped_directory(
        state.options.directory,
        request.directory,
      )
      // No startup selection/template/output settings are reinterpreted relative
      // to a child root. Only host resource ceilings cross this boundary.
      let clean = @repomix.options(
        directory,
        style=Json,
        max_files=state.options.max_files,
        max_total_size=state.options.max_total_size,
      )
      let raw : @repomix.Options = {
        ..clean,
        stdout: true,
        max_file_size: state.options.max_file_size,
        include_patterns: request.includes,
        token_budget: Some(request.budget),
        output_file_path_style: TargetRelative,
        full_metadata: true,
        quiet: true,
      }
      let baseline = @repomix.pack(raw, state.runtime)
      // These are independent scanned reads, not an atomic filesystem snapshot.
      let selected = if request.profile == "raw" {
        baseline
      } else {
        @repomix.pack(
          {
            ..raw,
            compress: true,
            keep_full_patterns: if request.profile == "mixed" {
              request.keep_full
            } else {
              []
            },
          },
          state.runtime,
        )
      }
      @async.sleep(0)
      let value : Json = {
        "profile": request.profile,
        "directory": request.directory,
        "result": packed_json(selected, request.budget),
        "baseline": packed_json(baseline, request.budget),
      }
      if @utf8.encode(value.stringify()).length() > 16777216 {
        raise PublicError(
          413, "output_too_large", "Combined response exceeds 16 MiB.",
        )
      }
      value
    },
    error=PublicError(
      422, "pack_timeout", "Pack operation exceeded 60 seconds.",
    ),
  )
  response
}
