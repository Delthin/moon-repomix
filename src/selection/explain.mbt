///|
// paths is the sorted query set; allowed_paths is the independent host list.
// Both have already passed exact_paths before any filesystem/rule access.
async fn select_exact(
  root : String,
  options : SelectionOptions,
  paths : Array[String],
  allowed_paths : Array[String]?,
  max_files : Int32,
) -> SelectionExplanation {
  let filter = make_path_filter(root, options, allowed_paths)
  let files : Array[Candidate] = []
  let skipped : Array[Skipped] = []
  let decisions : Array[PathDecision] = []
  for relative in paths {
    match filter.decision(relative, true) {
      Some(exclusion) => {
        skipped.push({ path: relative, reason: exclusion.reason(), })
        decisions.push(exclusion.decision(root, relative))
      }
      None => {
        if files.length() >= max_files {
          raise SelectionError::FileLimitExceeded(limit=max_files)
        }
        files.push({ path: join(root, relative), relative, })
        decisions.push(candidate_decision(relative))
      }
    }
  }
  { selection: { root, files, skipped, }, decisions, }
}

///|
/// Explain only literal requested paths, without recursion or candidate reads.
/// file_paths remains an independent host allowlist; Some([]) allows nothing.
/// Returns the same candidates for the caller to read once, without reselecting.
/// Decisions expose safe provenance; selection.skipped retains legacy diagnostics.
pub async fn explain(
  root : String,
  options : SelectionOptions,
  paths : Array[String],
  file_paths~ : Array[String]? = None,
  max_files~ : Int32 = 2147483647,
) -> SelectionExplanation {
  if max_files < 0 {
    raise SelectionError::FileLimitExceeded(limit=max_files)
  }
  let paths = exact_paths(Some(paths)).unwrap()
  let allowed_paths = exact_paths(file_paths)
  let root = selection_root(root)
  select_exact(root, options, paths, allowed_paths, max_files)
}
