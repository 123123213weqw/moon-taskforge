// Generated from tests/cases.json by scripts/fixtures.py; do not edit.

///|
fn test_at(value : Value, parts : Array[String]) -> Value raise {
  let mut current = value
  for part in parts {
    current = match current {
      Object(fields) =>
        match fields.get(part) {
          Some(v) => v
          None => raise InputError("test key missing: " + part)
        }
      Array(items) => items[num(parse(part)).to_int()]
      _ => raise InputError("invalid test traversal")
    }
  }
  current
}

///|
fn fails(request : String) -> Bool {
  try {
    ignore(run(parse(request)))
    false
  } catch {
    _ => true
  }
}

///|
test "initial ready wave" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}],\"hashes\":{\"in.txt\":\"h\"}}",
    ),
  )
  assert_eq(test_at(result, ["ready", "0", "id"]), parse("\"a\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"no cache entry\""),
  )
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"waiting\""))
  assert_eq(
    test_at(result, ["tasks", "1", "reason"]),
    parse("\"waiting for: a\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse("false"))
  assert_eq(test_at(result, ["summary", "ready"]), parse("[\"a\"]"))
  assert_eq(test_at(result, ["summary", "waiting"]), parse("[\"b\"]"))
}

///|
test "failure blocks downstream" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}],\"hashes\":{\"in.txt\":\"h\"},\"completed\":{\"a\":\"failed\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"failed\""))
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"blocked\""))
  assert_eq(
    test_at(result, ["tasks", "1", "reason"]),
    parse("\"dependency failed: a\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse("true"))
  assert_eq(test_at(result, ["success"]), parse("false"))
  assert_eq(test_at(result, ["summary", "rerun"]), parse("[\"a\",\"b\"]"))
}

///|
test "missing input fails" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}]}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"failed\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"missing input: in.txt\""),
  )
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"blocked\""))
  assert_eq(test_at(result, ["terminal"]), parse("true"))
}

///|
test "topological cycle" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"deps\":[\"b\"]},{\"id\":\"b\",\"command\":[\"x\"],\"deps\":[\"a\"]}]}",
    ),
  )
}

///|
test "output conflict" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"same\"]},{\"id\":\"b\",\"command\":[\"x\"],\"outputs\":[\"same\"]}]}",
    ),
  )
}

///|
test "case-insensitive output conflict" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"Out.txt\"]},{\"id\":\"b\",\"command\":[\"x\"],\"outputs\":[\"out.txt\"]}]}",
    ),
  )
}

///|
test "nested output conflict" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"dist\"]},{\"id\":\"b\",\"command\":[\"x\"],\"outputs\":[\"dist/index.html\"]}]}",
    ),
  )
}

///|
test "unsafe inputs" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"inputs\":[\"../x\"]}]}",
    ),
  )
}

///|
test "producer dependency required" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"a\"]},{\"id\":\"b\",\"command\":[\"x\"],\"inputs\":[\"a\"]}]}",
    ),
  )
}

///|
test "unknown dependency" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"deps\":[\"ghost\"]}]}",
    ),
  )
}

///|
test "empty command" {
  assert_true(fails("{\"tasks\":[{\"id\":\"a\",\"command\":[]}]}"))
}

///|
test "invalid timeout" {
  assert_true(
    fails("{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"timeout_ms\":0}]}"),
  )
}

///|
test "invalid retries" {
  assert_true(
    fails("{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"retries\":11}]}"),
  )
}

///|
test "invalid concurrency" {
  assert_true(
    fails("{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"]}],\"concurrency\":0}"),
  )
}

///|
test "concurrency bound" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"0\",\"command\":[\"x\"]},{\"id\":\"1\",\"command\":[\"x\"]},{\"id\":\"2\",\"command\":[\"x\"]},{\"id\":\"3\",\"command\":[\"x\"]}],\"concurrency\":2}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "2", "status"]), parse("\"waiting\""))
  assert_eq(
    test_at(result, ["tasks", "2", "reason"]),
    parse("\"concurrency limit reached\""),
  )
  assert_eq(test_at(result, ["ready", "1", "id"]), parse("\"1\""))
}

///|
test "deterministic order by id" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"b\",\"command\":[\"x\"]},{\"id\":\"10\",\"command\":[\"x\"]},{\"id\":\"a\",\"command\":[\"x\"]},{\"id\":\"9\",\"command\":[\"x\"]}]}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "id"]), parse("\"10\""))
  assert_eq(test_at(result, ["tasks", "1", "id"]), parse("\"9\""))
  assert_eq(test_at(result, ["tasks", "2", "id"]), parse("\"a\""))
  assert_eq(test_at(result, ["tasks", "3", "id"]), parse("\"b\""))
}

///|
test "cache hit verified" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"cached\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint and outputs verified\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse("true"))
  assert_eq(test_at(result, ["success"]), parse("true"))
  assert_eq(
    test_at(result, ["cache", "a", "outputs", "a.txt"]),
    parse("\"ha\""),
  )
}

///|
test "input change invalidates" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h2\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint changed: inputs\""),
  )
}

///|
test "command change invalidates" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"changed\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint changed: command\""),
  )
}

///|
test "environment change invalidates" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}},\"environment\":{\"MODE\":\"release\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint changed: environment\""),
  )
}

///|
test "forged cache outputs rejected" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"tampered\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"outputs changed\""),
  )
}

///|
test "outputs missing reruns" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"outputs missing\""),
  )
}

///|
test "no outputs always runs" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"lint\",\"command\":[\"echo\",\"lint\"],\"inputs\":[\"in.txt\"]}],\"hashes\":{\"in.txt\":\"h\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"no outputs declared\""),
  )
}

///|
test "transitive invalidation" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]},{\"id\":\"c\",\"command\":[\"echo\",\"c\"],\"deps\":[\"b\"],\"inputs\":[\"b.txt\"],\"outputs\":[\"c.txt\"]}],\"hashes\":{\"in.txt\":\"h2\",\"a.txt\":\"ha\",\"b.txt\":\"hb\",\"c.txt\":\"hc\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint changed: inputs\""),
  )
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"waiting\""))
  assert_eq(
    test_at(result, ["tasks", "1", "reason"]),
    parse("\"waiting for: a\""),
  )
  assert_eq(
    test_at(result, ["tasks", "2", "reason"]),
    parse("\"waiting for: b\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse("false"))
}

///|
test "paths with spaces" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"render\",\"command\":[\"render\"],\"inputs\":[\"my input.txt\"],\"outputs\":[\"out dir/result.txt\"]}],\"hashes\":{\"my input.txt\":\"h\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["ready", "0", "outputs", "0"]),
    parse("\"out dir/result.txt\""),
  )
}

///|
test "summary groups" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"]},{\"id\":\"c\",\"command\":[\"echo\",\"c\"],\"deps\":[\"b\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":1,\"command\":[\"echo\",\"a\"],\"inputs\":{\"in.txt\":\"h\"},\"outputs\":[\"a.txt\"],\"environment\":{},\"dependencies\":{}},\"outputs\":{\"a.txt\":\"ha\"}}},\"completed\":{\"b\":\"failed\"}}",
    ),
  )
  assert_eq(test_at(result, ["summary", "cached"]), parse("[\"a\"]"))
  assert_eq(test_at(result, ["summary", "failed"]), parse("[\"b\"]"))
  assert_eq(test_at(result, ["summary", "blocked"]), parse("[\"c\"]"))
  assert_eq(test_at(result, ["summary", "rerun"]), parse("[\"b\",\"c\"]"))
  assert_eq(test_at(result, ["terminal"]), parse("true"))
  assert_eq(test_at(result, ["success"]), parse("false"))
}

///|
test "environment values must be strings" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"]}],\"environment\":{\"N\":1}}",
    ),
  )
}

///|
test "hash values must be strings" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":1}}",
    ),
  )
}

///|
test "invalid completed status" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"]}],\"completed\":{\"a\":\"done\"}}",
    ),
  )
}

///|
test "success requires verified outputs" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\"},\"completed\":{\"a\":\"success\"}}",
    ),
  )
}
