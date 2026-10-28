///|
priv struct TaskChosen {
  file : @document.File
  mode : String
  transform : Json?
  fallback : String?
}

///|
// Pure, bounded greedy state. Root supplies screened candidates; this state
// never opens files, starts async work or estimates a whole by summing parts.
priv struct TaskBudget {
  cap : Int32
  max_attempts : Int32
  render : (Array[TaskChosen]) -> String
  count : (String) -> Int32
  selected : Array[TaskChosen]
  mut attempts : Int32
  mut text : String
  mut tokens : Int32
}

///|
fn TaskBudget::new(
  cap : Int32,
  max_attempts : Int32,
  required : Array[TaskChosen],
  render : (Array[TaskChosen]) -> String,
  count : (String) -> Int32,
) -> TaskBudget {
  let text = render(required)
  let tokens = count(text)
  {
    cap,
    max_attempts,
    render,
    count,
    selected: required.copy(),
    attempts: 1,
    text,
    tokens,
  }
}

///|
fn TaskBudget::can_try(self : TaskBudget) -> Bool {
  self.attempts < self.max_attempts - 1
}

///|
fn TaskBudget::try_add(self : TaskBudget, candidate : TaskChosen) -> Bool {
  if !self.can_try() {
    return false
  }
  let proposed = self.selected.copy()
  proposed.push(candidate)
  let text = (self.render)(proposed)
  let tokens = (self.count)(text)
  self.attempts += 1
  if tokens > self.cap {
    return false
  }
  self.selected.push(candidate)
  self.text = text
  self.tokens = tokens
  true
}

///|
fn TaskBudget::finish(self : TaskBudget) -> Bool {
  // One attempt is always reserved for the exact final returned serialization.
  if self.attempts >= self.max_attempts {
    return false
  }
  self.text = (self.render)(self.selected)
  self.tokens = (self.count)(self.text)
  self.attempts += 1
  self.tokens <= self.cap
}
