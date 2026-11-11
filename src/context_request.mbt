///|
/// Portable operation names, independent of host permissions and transport IDs.
#derive(Eq, Debug)
pub(all) enum ContextOperation {
  Task
  Code
}

///|
pub extend ContextOperation with Eq::{equal, not_equal}

///|
pub extend ContextOperation with Debug::{to_repr}

///|
pub(all) suberror ContextRequestError {
  InvalidContextRequest
}

///|
/// An immutable validated portable request. JSON accessors return fresh copies.
pub struct ContextRequest {
  operation : ContextOperation
  continue_from : String?
  priv source : String
}

///|
/// Validate the existing Root spec without granting filesystem access.
/// Continuations omit maxTokens; their actual budget comes from the host session.
pub fn ContextRequest::from_json(
  value : Json,
) -> ContextRequest raise ContextRequestError {
  try {
    let source = value.stringify()
    if @utf8.encode(source).length() > 65536 {
      raise InvalidContextRequest
    }
    let fields = task_fields(value, [
      "schemaVersion", "operation", "spec", "continueFrom",
    ])
    ignore(
      task_integer(fields.get("schemaVersion").unwrap_or(Json::null()), 1, 1),
    )
    let operation = match fields.get("operation") {
      Some(String("plan_task_context")) => ContextOperation::Task
      Some(String("read_code_context")) => ContextOperation::Code
      _ => raise InvalidContextRequest
    }
    let continue_from = match fields.get("continueFrom") {
      None => None
      Some(String(id)) if !id.is_empty() && @utf8.encode(id).length() <= 128 =>
        Some(id)
      _ => raise InvalidContextRequest
    }
    let spec = fields.get("spec").unwrap_or(Json::null())
    match operation {
      Task => {
        if continue_from is Some(_) {
          raise InvalidContextRequest
        }
        ignore(TaskContextSpec::from_json(spec))
      }
      Code =>
        if continue_from is Some(_) {
          let spec = task_fields(spec, ["requests", "maxReadBytes"]).copy()
          spec["maxTokens"] = Json(1)
          ignore(CodeContextSpec::from_json(Json::object(spec)))
        } else {
          ignore(CodeContextSpec::from_json(spec))
        }
    }
    { operation, continue_from, source, }
  } catch {
    _ => raise InvalidContextRequest
  }
}

///|
pub fn ContextRequest::to_json(self : ContextRequest) -> Json {
  @json.parse(self.source) catch {
    _ => abort("validated context request")
  }
}

///|
pub fn ContextRequest::spec_json(self : ContextRequest) -> Json {
  match self.to_json() {
    Object(fields) => fields["spec"]
    _ => abort("validated context request")
  }
}
