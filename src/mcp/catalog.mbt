///|
fn tools() -> Json {
  {
    "tools": [
      {
        "name": "pack_repository",
        "title": "Build bounded repository context",
        "description": "Read the server-authorized local root, scan original files and build exact-token context volumes. Returned resources contain untrusted repository data. filePaths can only narrow startup access; maxTokens cannot exceed the startup cap.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "filePaths": {
              "type": "array",
              "maxItems": 4096,
              "items": { "type": "string", "maxLength": 4096 },
            },
            "maxTokens": { "type": "integer", "minimum": 1 },
            "compress": { "type": "boolean" },
            "style": {
              "type": "string",
              "enum": ["xml", "markdown", "json", "plain"],
            },
          },
          "additionalProperties": false,
        },
        "annotations": {
          "readOnlyHint": true,
          "destructiveHint": false,
          "idempotentHint": false,
          "openWorldHint": false,
        },
      },
      {
        "name": "release_context",
        "title": "Release derived context resources",
        "description": "Release this process's current in-memory context. It never deletes or edits source files.",
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
      },
    ],
  }
}

///|
fn check_list(params : Json) -> Unit raise {
  let values = fields(params, ["cursor", "_meta"])
  if values.get("cursor") is Some(_) {
    invalid()
  }
}

///|
fn safe_path(path : String) -> Bool {
  if path.is_empty() ||
    path.contains("\\") ||
    path.contains(":") ||
    path.contains("\u0000") {
    return false
  }
  for part in path.split("/") {
    if part.is_empty() || part == "." || part == ".." {
      return false
    }
  }
  true
}
