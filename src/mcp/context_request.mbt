///|
fn context_request_tool() -> Json {
  {
    "name": "execute_context_request",
    "title": "Execute a portable context request",
    "description": "Execute the versioned request JSON shared by the SDK, native CLI and WebUI. It contains schemaVersion:1, operation:plan_task_context or read_code_context, and the existing operation's spec. For code continuation, supply the latest continueFrom outside spec and omit spec.maxTokens. All host scope, whole-file screening, exact budgets, three-success accounting and resource publication rules of the named tools apply. Does not import source contents or authorize another directory.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "schemaVersion": { "type": "integer", "const": 1 },
        "operation": {
          "type": "string",
          "enum": ["plan_task_context", "read_code_context"],
        },
        "spec": {
          "type": "object",
          "description": "The existing plan_task_context or read_code_context spec. maxTokens is required for a new request and forbidden on code continuation.",
        },
        "continueFrom": { "type": "string", "minLength": 1, "maxLength": 128 },
      },
      "required": ["schemaVersion", "operation", "spec"],
      "additionalProperties": false,
    },
    "annotations": {
      "readOnlyHint": true,
      "destructiveHint": false,
      "idempotentHint": false,
      "openWorldHint": false,
    },
  }
}

///|
fn capabilities_tool() -> Json {
  {
    "name": "context_capabilities",
    "description": "Inspect shared request schemas, supported definition extensions and limits without reading source. Host limits can only narrow these capabilities.",
    "inputSchema": {
      "type": "object",
      "properties": {},
      "additionalProperties": false,
    },
    "annotations": {
      "readOnlyHint": true,
      "destructiveHint": false,
      "idempotentHint": true,
      "openWorldHint": false,
    },
  }
}

///|
fn capabilities(state : State, value : Json) -> Json raise {
  ignore(fields(value, []))
  let response : Json = {
    "content": [
      { "type": "text", "text": "Context capabilities and host limits." },
    ],
    "structuredContent": {
      "capabilities": @repomix.context_capabilities(),
      "host": {
        "maxTokens": state.max_tokens,
        "maxOutputBytes": state.max_output_bytes,
        "maxFiles": state.options.max_files,
        "maxTotalBytes": state.options.max_total_size.to_string(),
      },
    },
    "isError": false,
  }
  let bytes = @utf8.encode(response.stringify()).length()
  if bytes > state.max_output_bytes || bytes > 4194304 {
    return error_result("ResourceLimit")
  }
  response
}

///|
async fn execute_context_request(state : State, value : Json) -> Json {
  let request = @repomix.ContextRequest::from_json(value) catch {
    _ => return invalid()
  }
  match request.operation {
    Task => plan_tasks(state, request.spec_json())
    Code => {
      guard request.spec_json() is Object(fields) else { return invalid() }
      let fields = fields.copy()
      if request.continue_from is Some(id) {
        fields["continueFrom"] = Json(id)
      }
      read_code(state, Json::object(fields))
    }
  }
}
