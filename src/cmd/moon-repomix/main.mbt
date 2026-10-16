///|
fn main {
  let args = @env.args()
  if args.contains("--version") {
    println("moon-repomix \{@repomix.version()}")
  } else {
    println(
      "moon-repomix — pack a local repository\nUsage: moon-repomix [directory] [options]\n  --help       Show help\n  --version    Show version",
    )
  }
}
