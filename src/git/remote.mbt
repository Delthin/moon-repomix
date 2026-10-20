///|
// Only directories allocated by this package in this process may be deleted.
// Checkout has public fields, so a path prefix or a forged handle is not proof
// of ownership. Entries are removed only after successful deletion.
let owned_checkouts : Map[String, Unit] = Map([])

///|
fn ascii_alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

///|
fn hex_digit(c : UInt16) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn validate_url(url : String) -> Unit raise {
  let invalid = "expected a public HTTPS URL without credentials, query or fragment"
  guard url.has_prefix("https://") else { raise InvalidInput(invalid) }
  let rest = url[8:]
  let slash = rest.find("/").unwrap_or(rest.length())
  let authority = rest[:slash]
  let host_port = authority.split(":").collect()
  guard host_port.length() == 1 || host_port.length() == 2 else {
    raise InvalidInput(invalid)
  }
  let host = host_port[0]
  let labels = host.split(".").collect()
  guard labels.length() >= 2 else { raise InvalidInput(invalid) }
  for label in labels {
    guard !label.is_empty() &&
      !label.has_prefix("-") &&
      !label.has_suffix("-") &&
      label.iter().all(c => ascii_alnum(c) || c == '-') else {
      raise InvalidInput(invalid)
    }
  }
  // DNS names only: IP literals and local-only hostnames are not public origins.
  guard labels[labels.length() - 1]
    .iter()
    .any(c => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) else {
    raise InvalidInput(invalid)
  }
  let lower = host.to_owned().to_lower()
  guard !lower.has_suffix(".localhost") &&
    !lower.has_suffix(".local") &&
    !lower.has_suffix(".internal") else {
    raise InvalidInput(invalid)
  }
  if host_port.length() == 2 {
    let port = host_port[1]
    guard !port.is_empty() && port.length() <= 5 else {
      raise InvalidInput(invalid)
    }
    let mut value = 0
    for c in port.iter() {
      guard c >= '0' && c <= '9' else { raise InvalidInput(invalid) }
      value = value * 10 + c.to_int() - '0'.to_int()
    }
    guard value > 0 && value <= 65535 else { raise InvalidInput(invalid) }
  }
  // Reject option-like transport parameters, controls and alternate separators.
  for c in rest.iter() {
    guard c > ' ' && c <= '~' && c != '\\' && c != '?' && c != '#' else {
      raise InvalidInput(invalid)
    }
  }
  let path = rest[slash:]
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '%' {
      guard i + 2 < path.length() &&
        hex_digit(path[i + 1]) &&
        hex_digit(path[i + 2]) else {
        raise InvalidInput(invalid)
      }
      let escape = path[i + 1:i + 3].to_owned().to_lower()
      guard !escape.has_prefix("0") &&
        !escape.has_prefix("1") &&
        escape != "7f" &&
        escape != "5c" else {
        raise InvalidInput(invalid)
      }
    }
  }
}

///|
fn validate_revision(revision : String) -> Unit raise {
  guard !revision.is_empty() &&
    !revision.has_prefix("-") &&
    !revision.has_prefix("/") &&
    !revision.has_prefix(".") &&
    !revision.has_suffix(".") &&
    !revision.has_suffix("/") &&
    !revision.has_suffix(".lock") &&
    !revision.contains("..") &&
    !revision.contains("//") &&
    revision
    .iter()
    .all(c => ascii_alnum(c) || c == '/' || c == '-' || c == '_' || c == '.') else {
    raise InvalidInput(
      "revision must be a branch, tag or full commit ID, not an option or ref expression",
    )
  }
  for part in revision.split("/") {
    guard !part.has_prefix(".") && !part.has_suffix(".lock") else {
      raise InvalidInput("invalid revision component")
    }
  }
}

///|
/// Fetch a public HTTPS repository into an isolated temporary directory. Default
/// HEAD is shallow (depth 1); history>0 fetches full ancestry of the selected ref
/// so directory-limited collect(logs=history) is not cut off by shallow history.
/// Explicit revision accepts branch/tag names or full commit IDs. The returned
/// revision is the resolved HEAD, and .git is retained. Caller must defer cleanup.
pub async fn checkout(
  url : String,
  revision? : String,
  history~ : Int32 = 0,
) -> Checkout {
  validate_url(url)
  if history < 0 {
    raise InvalidInput("history must be nonnegative")
  }
  if revision is Some(value) {
    validate_revision(value)
  }
  temporary_checkout(url, directory => {
    let budget = { remaining: 8388608, filters: [], }
    ignore(
      git(
        directory,
        ["init", "--quiet", "--template=", "--initial-branch=checkout"],
        budget,
      ),
    )
    let args = [
      "fetch", "--quiet", "--no-tags", "--no-recurse-submodules", "--no-auto-maintenance",
    ]
    if history == 0 {
      args.push("--depth=1")
    }
    args.append(["--", url, revision.unwrap_or("HEAD")])
    ignore(git(directory, args, budget))
    ignore(
      git(
        directory,
        [
          "checkout", "--quiet", "--detach", "--force", "--no-recurse-submodules",
          "FETCH_HEAD", "--",
        ],
        budget,
      ),
    )
    line(git(directory, ["rev-parse", "--verify", "HEAD"], budget))
  })
}

///|
async fn temporary_checkout(
  url : String,
  operation : async (String) -> String,
) -> Checkout {
  let directory = @fs.tmpdir(prefix="moon-git-checkout-")
  let mut retained = false
  defer (if !retained {
    @async.protect_from_cancel(() => @fs.rmdir(directory, recursive=true))
  })
  let head = operation(directory)
  owned_checkouts[directory] = ()
  retained = true
  { directory, url, revision: head, }
}

///|
/// Delete only a checkout allocated by this process. Errors propagate; successful
/// cleanup invalidates the handle. Shields deletion even in an already cancelled
/// task, then resumes cancellation (does not turn cancellation into success).
pub async fn cleanup(checkout : Checkout) -> Unit {
  @async.protect_from_cancel(() => {
    guard owned_checkouts.contains(checkout.directory) else {
      raise InvalidInput(
        "checkout is not owned by this process or was already cleaned",
      )
    }
    @fs.rmdir(checkout.directory, recursive=true)
    owned_checkouts.remove(checkout.directory)
  })
}
