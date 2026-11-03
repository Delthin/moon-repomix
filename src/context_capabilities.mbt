///|
/// Transport-independent operation, selector and schema limits. An adapter can
/// impose smaller host-authorized limits; these values do not grant access.
pub fn context_capabilities() -> Json {
  {
    "schemaVersion": 1,
    "portableRequest": {
      "schemaVersion": 1,
      "maxBytes": 65536,
      "operations": ["plan_task_context", "read_code_context"],
    },
    "code": {
      "selectors": ["symbols", "ranges", "full", "outline"],
      "definitionExtensions": @compression.definition_extensions(),
      "maxRequests": 32,
      "maxSymbols": 16,
      "maxRanges": 16,
      "maxSymbolBytes": 256,
      "maxPathBytes": 4096,
      "maxReadBytes": 16777216,
      "maxRounds": CodeContextSession::max_rounds(),
      "auditIncludedInDocument": true,
    },
    "task": {
      "maxTasks": 16,
      "maxUniquePaths": 128,
      "requiredModes": ["full", "skeleton"],
      "optionalModes": ["full", "skeleton", "either"],
      "maxPriority": 100,
      "maxReadBytes": 16777216,
      "maxAttempts": 256,
      "auditIncludedInDocument": false,
    },
    "tokenizer": "o200k_base",
    "securityBeforeProjection": true,
  }
}
