///|
/// A reading session cannot spend beyond its original whole-document budget or
/// commit more than three successful reads. Transport identifiers, directories,
/// resource lifetimes and final response publication belong to the adapter.
pub(all) suberror CodeSessionError {
  InvalidCodeSession
  CodeRoundLimit
  CodeBudgetExhausted
}

///|
/// Immutable accounting shared by SDK, command line, MCP and HTTP adapters.
/// Advance a candidate only when its result is ready to publish; a failed read
/// returns the same accounting and does not consume a successful round.
pub struct CodeContextSession {
  limit : Int32
  spent : Int32
  rounds : Int32
}

///|
pub fn CodeContextSession::new(
  max_tokens : Int32,
) -> CodeContextSession raise CodeSessionError {
  if max_tokens <= 0 {
    raise InvalidCodeSession
  }
  { limit: max_tokens, spent: 0, rounds: 0, }
}

///|
pub fn CodeContextSession::remaining(self : CodeContextSession) -> Int32 {
  self.limit - self.spent
}

///|
pub fn CodeContextSession::can_continue(self : CodeContextSession) -> Bool {
  self.rounds < 3 && self.spent < self.limit
}

///|
/// Validate a request with the remaining allowance. `value` contains `requests`
/// and optionally `maxReadBytes`; it must not replace the session's maxTokens.
///
/// ```mbt check
/// test {
///   let session = @moon_repomix.CodeContextSession::new(8000)
///   let spec = session.request({
///     "requests": [{ "path": "src/main.mbt", "full": true }],
///   })
///   ignore(spec)
/// }
/// ```
pub fn CodeContextSession::request(
  self : CodeContextSession,
  value : Json,
) -> CodeContextSpec raise {
  if self.rounds >= 3 {
    raise CodeRoundLimit
  }
  if self.spent >= self.limit {
    raise CodeBudgetExhausted
  }
  guard value is Object(fields) else { raise InvalidCodeSpec }
  if fields.contains("maxTokens") {
    raise InvalidCodeSpec
  }
  let fields = fields.copy()
  fields["maxTokens"] = Json(self.remaining())
  CodeContextSpec::from_json(Json::object(fields))
}

///|
pub fn CodeContextSession::advance(
  self : CodeContextSession,
  plan : CodeContextPlan,
) -> CodeContextSession raise CodeSessionError {
  if plan.status != "complete" || plan.text is None {
    return self
  }
  if self.rounds >= 3 {
    raise CodeRoundLimit
  }
  if self.spent >= self.limit {
    raise CodeBudgetExhausted
  }
  if plan.tokens < 0 || plan.tokens > self.remaining() {
    raise InvalidCodeSession
  }
  {
    limit: self.limit,
    spent: self.spent + plan.tokens,
    rounds: self.rounds + 1,
  }
}

///|
pub fn CodeContextSession::to_json(self : CodeContextSession) -> Json {
  {
    "limit": self.limit,
    "spent": self.spent,
    "remaining": self.remaining(),
    "rounds": self.rounds,
    "maxRounds": 3,
    "canContinue": self.can_continue(),
  }
}
