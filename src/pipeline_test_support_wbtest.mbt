///|
// Async root tests share the process-wide native worker leases. Admission and
// teardown tests need exclusive ownership to assert that all four are available;
// each test still exercises concurrent native jobs within its own scope.
let pipeline_test_mutex : @async.Mutex = @async.Mutex()
