///|
test "code context public spec accepts explicit selectors and rejects authority changes" {
  for
    request in [
      (
        {
          "path": "lib/a.js",
          "symbols": ["res.render"],
          "includeDependencies": true,
        } : Json),
      { "path": "src/a.py", "ranges": [{ "startLine": 1, "endLine": 3 }] },
      { "path": "a.txt", "full": true },
      { "path": "a.ts", "outline": true },
    ] {
    let spec = @moon_repomix.CodeContextSpec::from_json({
      "maxTokens": 2000,
      "requests": [request],
    })
    assert_eq(spec.max_tokens, 2000)
  }
  for
    request in [
      ({ "path": "../a", "full": true } : Json),
      { "path": "/a", "full": true },
      { "path": "a\\b", "full": true },
      { "path": "a", "symbols": [] },
      { "path": "a", "symbols": ["x", "x"] },
      { "path": "a", "symbols": ["x\ny"] },
      { "path": "a", "symbols": ["x"], "full": true },
      { "path": "a", "ranges": [{ "startLine": 3, "endLine": 2 }] },
      { "path": "a", "outline": true, "includeDependencies": true },
      { "path": "a", "full": false },
      { "path": "a", "symbols": ["x"], "full": false },
      { "path": "a", "full": true, "securityCheck": false },
    ] {
    try
      @moon_repomix.CodeContextSpec::from_json({
        "maxTokens": 2000,
        "requests": [request],
      })
    catch {
      @moon_repomix.InvalidCodeSpec => ()
    } noraise {
      _ => fail("invalid code selector accepted")
    }
  }
  try
    @moon_repomix.CodeContextSpec::from_json({
      "maxTokens": 1,
      "requests": [],
      "root": "/tmp",
    })
  catch {
    @moon_repomix.InvalidCodeSpec => ()
  } noraise {
    _ => fail("invalid authority accepted")
  }
}

///|
test "code context rejects excessive input before reading" {
  let valid : Array[Json] = []
  for i in 0..<32 {
    valid.push({ "path": i.to_string() + ".js", "full": true })
  }
  let accepted = @moon_repomix.CodeContextSpec::from_json({
    "maxTokens": 2147483647,
    "requests": valid,
  })
  assert_eq(accepted.max_tokens, 2147483647)
  let too_many = valid.copy()
  too_many.push({ "path": "extra.js", "full": true })
  let too_large : Array[Json] = []
  for i in 0..<32 {
    too_large.push({ "path": "a".repeat(3000) + i.to_string(), "full": true })
  }
  for
    value in [
      ({ "maxTokens": 0, "requests": valid } : Json),
      { "maxTokens": 1.5, "requests": valid },
      { "maxTokens": 2147483648, "requests": valid },
      { "maxTokens": 1, "requests": too_many },
      { "maxTokens": 1, "requests": too_large },
      { "maxTokens": 1, "requests": [valid[0], valid[0]] },
      { "maxTokens": 1, "maxReadBytes": 16777217, "requests": valid },
    ] {
    try @moon_repomix.CodeContextSpec::from_json(value) catch {
      @moon_repomix.InvalidCodeSpec => ()
    } noraise {
      _ => fail("excessive code request accepted")
    }
  }
}
