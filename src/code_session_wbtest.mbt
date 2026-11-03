///|
fn session_test_plan(
  tokens : Int32,
  status~ : String = "complete",
) -> CodeContextPlan {
  {
    status,
    text: if status == "complete" {
      Some("{}\n")
    } else {
      None
    },
    tokens,
    bytes: if status == "complete" {
      3
    } else {
      0
    },
    required_tokens: None,
    audit: {},
    security: Passed,
  }
}

///|
test "shared code session accounts only committed successful documents" {
  let initial = CodeContextSession::new(20)
  let request : Json = { "requests": [{ "path": "api.mbt", "full": true }] }
  assert_eq(initial.request(request).max_tokens, 20)
  let first = initial.advance(session_test_plan(7))
  assert_eq(first.remaining(), 13)
  assert_eq(initial.remaining(), 20)
  assert_eq(
    first.advance(session_test_plan(0, status="unavailable")).to_json(),
    first.to_json(),
  )
  assert_eq(
    first.advance(session_test_plan(0, status="over_budget")).to_json(),
    first.to_json(),
  )
  let second = first.advance(session_test_plan(6))
  assert_eq(second.request(request).max_tokens, 7)
  let third = second.advance(session_test_plan(7))
  assert_eq(third.spent, 20)
  assert_eq(third.rounds, 3)
  assert_false(third.can_continue())
  try third.request(request) catch {
    CodeRoundLimit => ()
    _ => fail("Expected successful round limit")
  } noraise {
    _ => fail("Expected successful round limit")
  }
  let exhausted = initial.advance(session_test_plan(20))
  try exhausted.request(request) catch {
    CodeBudgetExhausted => ()
    _ => fail("Expected exhausted budget")
  } noraise {
    _ => fail("Expected exhausted budget")
  }
  try first.advance(session_test_plan(14)) catch {
    InvalidCodeSession => ()
    _ => fail("Expected accounting overflow rejection")
  } noraise {
    _ => fail("Expected accounting overflow rejection")
  }
  try initial.request({ "maxTokens": 20, "requests": [] }) catch {
    InvalidCodeSpec => ()
    _ => fail("Expected fixed session budget")
  } noraise {
    _ => fail("Expected fixed session budget")
  }
  try CodeContextSession::new(0) catch {
    InvalidCodeSession => ()
    _ => fail("Expected positive session budget")
  } noraise {
    _ => fail("Expected positive session budget")
  }
}
