# Native MCP stdio transport

`Delthin/moon_repomix/mcp_rpc` depends only on MoonBit core and async 0.19.2.
It owns JSON-RPC framing, protocol validation, legacy lifecycle, concurrent
application dispatch, cancellation and serialized stdout. It does not read
files, run programs, access HTTP, or implement application tools/resources.

## API

```mbt
pub(all) struct Info {
  name : String
  version : String
  capabilities : Json
  instructions : String
}
pub(all) struct Limits {
  max_line_bytes : Int
  max_in_flight : Int
  timeout_ms : Int
}
pub fn Limits::default() -> Limits
pub(all) suberror RpcError {
  Protocol(code~ : Int, message~ : String, data~ : Json)
}
pub async fn serve(
  info : Info,
  handler~ : async (String, Json) -> Json,
  limits? : Limits = Limits::default(),
) -> Unit
```

`Int` is this compiler's 32-bit integer. Defaults are 1,048,576 input bytes
(excluding LF), four concurrent application requests and 60,000 ms per handler.
All limits must be positive and may only lower these defaults. Input limits do
**not** cap output: a valid resource response may exceed 1 MiB. The embedding
application must bound its results and advertise only capabilities it implements.

The handler receives the method name and an object `params` (empty when omitted).
Only `Protocol` errors are forwarded with their code/message/data; these must be
safe fixed application errors. Other handler exceptions become `-32603`,
`Internal error`, without exception text, paths or source information. Handler
timeout is `-32000`, `Request timed out`; overload is `-32000`, `Server busy`.
Handlers must cooperate with cancellation through async IO or periodic
`@async.pause()`; this is not preemptive CPU isolation.

## Protocol

- Modern calls have no initialize handshake. Each request independently supplies
  `params._meta["io.modelcontextprotocol/protocolVersion"]` as a string and
  `params._meta["io.modelcontextprotocol/clientCapabilities"]` as an object.
  Missing/malformed metadata is `-32602`. Unsupported versions are `-32022`,
  with `data: {supported: ["2026-07-28"], requested: ...}`. Only `2026-07-28`
  is valid in modern per-request metadata; legacy versions require initialize.
- `server/discover` returns `resultType: "complete"`, `supportedVersions`
  (`2026-07-28`, `2025-11-25`, `2025-06-18`), supplied capabilities,
  `_meta["io.modelcontextprotocol/serverInfo"]` and supplied instructions.
  All modern application object results gain `resultType: "complete"`;
  non-object results are unchanged. Discovery never authorizes later requests
  without metadata. `ping` is handled locally, with no application callback.
- Legacy `initialize` requires protocolVersion, capabilities and clientInfo;
  supported legacy versions are `2025-11-25` and `2025-06-18`. Other proposed
  versions negotiate `2025-11-25`. Only after `notifications/initialized` can
  application requests omit modern metadata. Legacy `ping` without modern keys
  is allowed before initialize and during initialization, returning `{}` without
  authorizing application methods. Requests containing modern metadata are still
  independently validated, even inside a legacy session. Before readiness,
  missing application-request metadata is `-32602`. Legacy results do not gain
  resultType.
- There are no subscriptions, logging, sampling, roots, elicitation or
  server-to-client requests. Unknown methods reach the application handler;
  unknown notifications are ignored and receive no response.

## Framing, scheduling and shutdown

Native stdin is consumed in bounded chunks, not `read_all`/unbounded
`read_until`. Each LF-terminated frame must contain one UTF-8 JSON-RPC 2.0
object. Batch arrays are unsupported. Request IDs are strings or integral JSON
numbers in [-9,007,199,254,740,991, 9,007,199,254,740,991], including zero and
negative integers; null, booleans, objects, fractional and unsafe integers are
rejected. Malformed JSON/UTF-8 produces
`-32700`; invalid envelopes/batches produce `-32600`. Error messages never
include the rejected input (the valid request ID is still echoed).

An oversized line is discarded through its LF with bounded storage, emits
`-32600`, `Frame too large`, then parsing resumes. EOF discards an unterminated
frame and cancels all outstanding tasks, waiting for cancellation cleanup.
A duplicate in-flight ID receives `-32600`, `Duplicate request ID`, without
replacing the original task or changing the lifecycle. Numeric spellings such
as `1`, `1.0` and `1e0` share an ID, distinct from the string `"1"`; `-0` and `0`
also share an ID. Cancelled IDs remain
reserved until their task cleanup completes.

`notifications/cancelled` uses `params.requestId`. Cancelling a running handler
or a response queued for the output lock cancels the task and suppresses its
response. Output frames are serialized by a cancellation-safe mutex. Acquiring
the output lock commits the frame: cancellation cannot retract bytes already
being sent, so that single committed frame is shielded until completion.
A committed write has a fixed 1,000 ms deadline; stalled/broken output terminates
the transport rather than leaving partial JSON and continuing or blocking EOF
indefinitely. Transport errors propagate as a fixed `Protocol(-32603,
"Transport failure", null)`; external cancellation propagates as cancellation.
No diagnostics are written to stdout.

## Verification and sources

Four aggregate tests cover dispatch/version/lifecycle/IDs; real native OS pipe
bounded framing, exact-boundary UTF-8 splitting and recovery; cancellation,
EOF cleanup, duplicates, busy/timeout/safe errors; and fragmented concurrent
writes including queued-response cancellation and responses larger than the
input cap. These exercise the same reader/writer implementation used by stdio,
not a spawned CLI or an official SDK client; end-to-end application/SDK checks
belong to the embedding executable.

```text
moon fmt src/mcp_rpc
moon info src/mcp_rpc --target native
moon check src/mcp_rpc --target native --deny-warn
moon test src/mcp_rpc --target native --deny-warn
```

Protocol sources (2026-07-28 modern; 2025-11-25 legacy):

- https://modelcontextprotocol.io/specification/2026-07-28/basic/index
- https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio
- https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning
- https://modelcontextprotocol.io/specification/2026-07-28/server/discover
- https://modelcontextprotocol.io/specification/2026-07-28/server/tools
- https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
