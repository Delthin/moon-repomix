///|
fn token_char(c : UInt16) -> Bool {
  c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' | '-')
}

///|
fn placeholder(value : String) -> Bool {
  let lower = value.to_lower()
  if lower.contains("example") ||
    lower.contains("placeholder") ||
    lower.contains("changeme") ||
    lower.contains("your_") ||
    lower.contains("your-") ||
    lower.contains("replace_me") ||
    lower.contains("redacted") ||
    lower.contains("dummy") {
    return true
  }
  let tail = if value.has_prefix("sk-proj-") {
    value[8:]
  } else if value.has_prefix("github_pat_") {
    value[11:]
  } else if value.has_prefix("AKIA") ||
    value.has_prefix("ASIA") ||
    value.has_prefix("ghp_") {
    value[4:]
  } else if value.has_prefix("sk-") {
    value[3:]
  } else {
    value[:]
  }
  tail.length() > 0 && tail.iter().all(c => c == tail.get_char(0).unwrap())
}

///|
fn assignment_value(value : String) -> Bool {
  if value.length() < 8 || placeholder(value) {
    return false
  }
  let lower = value.to_lower()
  if lower.has_prefix("process.") ||
    lower.has_prefix("os.") ||
    lower.has_prefix("env.") ||
    lower.has_prefix("config.") ||
    lower.has_prefix("std::") ||
    lower.has_prefix("getenv") ||
    lower.has_prefix("string") ||
    lower.has_prefix("option[") ||
    lower.has_prefix("${") ||
    lower.has_prefix("{{") {
    return false
  }
  // A bare identifier or type is not evidence of a hard-coded credential.
  let mut letters = false
  let mut other = false
  for c in value {
    if c is ('a'..<='z' | 'A'..<='Z') {
      letters = true
    }
    if c
      is ('0'..<='9'
      | '+'
      | '/'
      | '='
      | '!'
      | '@'
      | '#'
      | '$'
      | '%'
      | '^'
      | '&'
      | '*'
      | '-') {
      other = true
    }
    if c is ('(' | ')' | '[' | ']' | '{' | '}' | '<' | '>') {
      return false
    }
  }
  letters && other
}

///|
// The engine can read the closing quote in `"token=" + value + "\n"`
// as the opening quote of a credential. Filter only a concatenated reference
// whose preceding quote demonstrably closes a string on the same line.
fn concatenated_reference(text : String, start : Int32, end : Int32) -> Bool {
  if start == 0 || end >= text.length() {
    return false
  }
  let quote_at = start - 1
  let quote = text[quote_at]
  if !(quote is ('\'' | '"')) || text[end] != quote {
    return false
  }
  let value = text[start:end].trim()
  if value.length() < 3 || !value.has_prefix("+") || !value.has_suffix("+") {
    return false
  }
  let reference = value[1:value.length() - 1].trim()
  for part in reference.split(".") {
    if part.is_empty() || !(part[0] is ('a'..<='z' | 'A'..<='Z' | '_' | '$')) {
      return false
    }
    for c in part {
      if !(c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' | '$')) {
        return false
      }
    }
  }
  if reference.is_empty() {
    return false
  }
  let mut line_start = quote_at
  while line_start > 0 && !(text[line_start - 1] is ('\r' | '\n')) {
    line_start -= 1
  }
  let mut active : UInt16? = None
  let mut escaped = false
  for i in line_start..<(quote_at + 1) {
    let c = text[i]
    match active {
      Some(q) =>
        if escaped {
          escaped = false
        } else if c == '\\' {
          escaped = true
        } else if c == q {
          if i == quote_at {
            return true
          }
          active = None
        }
      None => if c is ('\'' | '"') { active = Some(c) }
    }
  }
  false
}

///|
fn rule_for(text : String, hit : @moon_scrub.Finding) -> String? {
  let value = text[hit.start:hit.end].to_owned()
  match hit.kind {
    AccessToken => {
      if (hit.start > 0 && token_char(text[hit.start - 1])) ||
        placeholder(value) {
        return None
      }
      if value.has_prefix("github_pat_") {
        if value.length() == 93 {
          Some("github-token")
        } else {
          None
        }
      } else if value.has_prefix("ghp_") ||
        value.has_prefix("gho_") ||
        value.has_prefix("ghu_") ||
        value.has_prefix("ghs_") ||
        value.has_prefix("ghr_") {
        if value.length() == 40 {
          Some("github-token")
        } else {
          None
        }
      } else if value.has_prefix("AKIA") || value.has_prefix("ASIA") {
        if value.length() == 20 &&
          value.iter().all(c => c is ('A'..<='Z' | '0'..<='9')) {
          Some("aws-access-key")
        } else {
          None
        }
      } else if value.has_prefix("sk-proj-") || value.has_prefix("sk-svcacct-") {
        if value.length() >= 48 && value.length() <= 256 {
          Some("openai-key")
        } else {
          None
        }
      } else if value.has_prefix("sk-") && !value.has_prefix("sk-ant-") {
        if value.length() == 51 {
          Some("openai-key")
        } else {
          None
        }
      } else {
        Some("access-token")
      }
    }
    CredentialAssignment =>
      if assignment_value(value) &&
        !concatenated_reference(text, hit.start, hit.end) {
        Some("credential-assignment")
      } else {
        None
      }
    PrivateKey => Some("pem-private-key")
    BearerToken => if placeholder(value) { None } else { Some("bearer-token") }
    Jwt => Some("jwt")
    UrlCredential =>
      if placeholder(value) {
        None
      } else {
        Some("url-credential")
      }
    _ => None
  }
}
