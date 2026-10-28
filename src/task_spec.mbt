///|
/// Invalid task descriptions are rejected before filesystem access.
pub(all) suberror TaskContextError {
  InvalidTaskSpec
}

///|
/// A validated, bounded task set. Construct with `TaskContextSpec::from_json`.
/// The serialized description is retained privately to prevent mutable JSON or
/// arrays supplied by a caller from changing a validated request.
pub struct TaskContextSpec {
  max_tokens : Int32
  priv source : String
}

///|
priv struct TaskRequest {
  id : String
  required : Array[String]
  paths : Array[String]
}

///|
priv struct TaskCandidate {
  path : String
  mut required : Bool
  mut mode : String
  mut priority : Int32
}

///|
priv struct TaskDescription {
  max_tokens : Int32
  max_read_bytes : Int64
  max_attempts : Int32
  tasks : Array[TaskRequest]
  candidates : Array[TaskCandidate]
}

///|
fn task_fields(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise TaskContextError {
  guard value is Object(fields) else { raise InvalidTaskSpec }
  for key in fields.keys() {
    if !allowed.contains(key) {
      raise InvalidTaskSpec
    }
  }
  fields
}

///|
fn task_integer(
  value : Json,
  minimum : Int32,
  maximum : Int32,
) -> Int32 raise TaskContextError {
  guard value is Number(n, ..) &&
    n >= minimum.to_double() &&
    n <= maximum.to_double() &&
    n.to_int().to_double() == n else {
    raise InvalidTaskSpec
  }
  n.to_int()
}

///|
fn task_path(path : String) -> Bool {
  !path.is_empty() &&
  @utf8.encode(path).length() <= 4096 &&
  !path.contains("\\") &&
  !path.contains(":") &&
  !path.contains("\u0000") &&
  !path.split("/").any(part => part.is_empty() || part == "." || part == "..")
}

///|
fn parse_task_description(
  value : Json,
) -> TaskDescription raise TaskContextError {
  let fields = task_fields(value, [
    "maxTokens", "tasks", "maxReadBytes", "maxAttempts",
  ])
  let max_tokens = task_integer(
    fields.get("maxTokens").unwrap_or(Json::null()),
    1,
    2147483647,
  )
  let max_read_bytes = task_integer(
    fields.get("maxReadBytes").unwrap_or(Json(16777216)),
    1,
    16777216,
  ).to_int64()
  let max_attempts = task_integer(
    fields.get("maxAttempts").unwrap_or(Json(256)),
    2,
    256,
  )
  guard fields.get("tasks") is Some(Array(tasks)) &&
    tasks.length() > 0 &&
    tasks.length() <= 16 else {
    raise InvalidTaskSpec
  }
  let ids : Set[String] = Set([])
  let merged : Map[String, TaskCandidate] = Map([])
  let requests : Array[TaskRequest] = []
  for task in tasks {
    let task = task_fields(task, ["id", "required", "optional"])
    guard task.get("id") is Some(String(id)) &&
      !id.is_empty() &&
      @utf8.encode(id).length() <= 64 &&
      !id.contains("\u0000") &&
      !ids.contains(id) else {
      raise InvalidTaskSpec
    }
    ids.add(id)
    let required_paths : Array[String] = []
    let all_paths : Array[String] = []
    for (field, required) in [("required", true), ("optional", false)] {
      guard task.get(field).unwrap_or(([] : Json)) is Array(entries) &&
        entries.length() <= 128 else {
        raise InvalidTaskSpec
      }
      for entry in entries {
        let entry = task_fields(
          entry,
          if required {
            ["path", "mode"]
          } else {
            ["path", "mode", "priority"]
          },
        )
        guard entry.get("path") is Some(String(path)) && task_path(path) else {
          raise InvalidTaskSpec
        }
        guard entry.get("mode") is Some(String(mode)) &&
          (
            mode == "full" ||
            mode == "skeleton" ||
            (!required && mode == "either")
          ) else {
          raise InvalidTaskSpec
        }
        let priority = if required {
          0
        } else {
          task_integer(entry.get("priority").unwrap_or(Json(0)), 0, 100)
        }
        if !all_paths.contains(path) {
          all_paths.push(path)
        }
        if required && !required_paths.contains(path) {
          required_paths.push(path)
        }
        match merged.get(path) {
          None => merged[path] = { path, required, mode, priority, }
          Some(previous) => {
            previous.required = previous.required || required
            previous.priority = if previous.priority > priority {
              previous.priority
            } else {
              priority
            }
            previous.mode = if previous.mode == "full" || mode == "full" {
              "full"
            } else if previous.mode == "skeleton" || mode == "skeleton" {
              "skeleton"
            } else {
              "either"
            }
          }
        }
        if merged.length() > 128 {
          raise InvalidTaskSpec
        }
      }
    }
    required_paths.sort_by(@document.compare_path)
    all_paths.sort_by(@document.compare_path)
    requests.push({ id, required: required_paths, paths: all_paths, })
  }
  requests.sort_by((a, b) => @document.compare_path(a.id, b.id))
  let candidates : Array[TaskCandidate] = merged.values().collect()
  candidates.sort_by((a, b) => {
    if a.required != b.required {
      if a.required {
        -1
      } else {
        1
      }
    } else if !a.required && a.priority != b.priority {
      b.priority - a.priority
    } else {
      @document.compare_path(a.path, b.path)
    }
  })
  { max_tokens, max_read_bytes, max_attempts, tasks: requests, candidates, }
}

///|
/// Parse a strict task description without reading any files. Required entries
/// accept `full` or `skeleton`; optional entries also accept `either` and a
/// priority from 0 to 100 (default 0). Unknown fields are rejected.
pub fn TaskContextSpec::from_json(
  value : Json,
) -> TaskContextSpec raise TaskContextError {
  let parsed = parse_task_description(value)
  let source = value.stringify()
  if @utf8.encode(source).length() > max_context_text_bytes {
    raise InvalidTaskSpec
  }
  { max_tokens: parsed.max_tokens, source, }
}
