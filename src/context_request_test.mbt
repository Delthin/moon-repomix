///|
test "portable request validates operation and takes immutable snapshots" {
  let input : Json = {
    "schemaVersion": 1,
    "operation": "read_code_context",
    "spec": {
      "maxTokens": 2048,
      "requests": [{ "path": "src/main.mbt", "full": true }],
    },
  }
  let request = @moon_repomix.ContextRequest::from_json(input)
  assert_true(request.operation is Code)
  assert_eq(request.continue_from, None)
  let snapshot = request.to_json().stringify()
  if input is Object(fields) {
    fields["operation"] = Json("INVALID")
  }
  let exported = request.to_json()
  if exported is Object(fields) {
    fields["spec"] = Json::null()
  }
  let spec = request.spec_json()
  if spec is Object(fields) {
    fields["requests"] = Json::null()
  }
  assert_eq(request.to_json().stringify(), snapshot)
  let continued = @moon_repomix.ContextRequest::from_json({
    "schemaVersion": 1,
    "operation": "read_code_context",
    "continueFrom": "latest",
    "spec": {
      "requests": [
        { "path": "src/main.mbt", "ranges": [{ "startLine": 1, "endLine": 2 }] },
      ],
    },
  })
  assert_eq(continued.continue_from, Some("latest"))
  let task = @moon_repomix.ContextRequest::from_json({
    "schemaVersion": 1,
    "operation": "plan_task_context",
    "spec": {
      "maxTokens": 2048,
      "tasks": [
        {
          "id": "read",
          "required": [{ "path": "src/main.mbt", "mode": "full" }],
        },
      ],
    },
  })
  assert_true(task.operation is Task)
}

///|
test "portable request rejects foreign permissions budgets and malformed specs" {
  let base : Json = {
    "schemaVersion": 1,
    "operation": "read_code_context",
    "spec": {
      "maxTokens": 2048,
      "requests": [{ "path": "src/main.mbt", "full": true }],
    },
  }
  let bad : Array[Json] = [
    Json::null(),
    {},
    { "schemaVersion": 1.5 },
    { "schemaVersion": 2 },
  ]
  for
    (field, value) in [
      ("schemaVersion", Json(1.5)),
      ("schemaVersion", Json(2)),
      ("operation", Json("pack")),
      ("root", Json("/tmp")),
      ("continueFrom", Json("")),
      ("continueFrom", Json("中".repeat(43))),
      ("continueFrom", Json("latest")),
      ("spec", Json::null()),
    ] {
    guard @json.parse(base.stringify()) is Object(fields) else {
      abort("object")
    }
    fields[field] = value
    bad.push(Json::object(fields))
  }
  bad.push({
    "schemaVersion": 1,
    "operation": "plan_task_context",
    "continueFrom": "latest",
    "spec": {},
  })
  bad.push({
    "schemaVersion": 1,
    "operation": "read_code_context",
    "spec": {
      "maxTokens": 1,
      "requests": [{ "path": "../outside", "full": true }],
    },
  })
  guard @json.parse(base.stringify()) is Object(fields) else { abort("object") }
  fields["padding"] = Json("x".repeat(65536))
  bad.push(Json::object(fields))
  for value in bad {
    try @moon_repomix.ContextRequest::from_json(value) catch {
      @moon_repomix.InvalidContextRequest => ()
    } noraise {
      _ => fail("invalid portable request accepted")
    }
  }
}
