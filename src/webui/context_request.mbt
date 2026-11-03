///|
fn validated_context_request(value : Json) -> @repomix.ContextRequest raise {
  @repomix.ContextRequest::from_json(value) catch {
    _ => raise PublicError(400, "invalid_request", "Invalid portable request.")
  }
}

///|
/// Validate only the portable request. This does not inspect a repository, read
/// source, change the selected directory, or commit a reading session.
fn validate_context_request(value : Json) -> Json raise {
  let request = validated_context_request(value)
  { "request": request.to_json() }
}

///|
async fn execute_context_request(state : State, value : Json) -> Json {
  let values = fields(value, ["directory", "request"])
  let directory = directory_field(values)
  let request = validated_context_request(
    values.get("request").unwrap_or(Json::null()),
  )
  match request.operation {
    Task =>
      task_context(state, {
        "directory": directory,
        "spec": request.spec_json(),
      })
    Code => {
      let fields : Map[String, Json] = {
        "directory": Json(directory),
        "spec": request.spec_json(),
      }
      if request.continue_from is Some(id) {
        fields["runId"] = Json(id)
      }
      code_context(state, Json::object(fields))
    }
  }
}
