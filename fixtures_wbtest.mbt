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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}}}",
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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h2\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}}}",
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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"changed\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}}}",
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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}},\"environment\":{\"MODE\":\"release\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint changed: environment\""),
  )
}

///|
test "executable digest invalidates" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}},\"executables\":{\"echo\":\"e1\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "0", "reason"]),
    parse("\"fingerprint changed: executable\""),
  )
  assert_eq(
    test_at(result, ["tasks", "0", "fingerprint", "executable"]),
    parse("\"e1\""),
  )
}

///|
test "executable digest round trip" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"digest\":\"bff1a7e5518e2896c7832b606da21a51fecbf6ba5703c424b9fb18f87b62bec3\",\"dependencies\":{},\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"executable\":\"e1\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"version\":2},\"outputs\":{\"a.txt\":\"ha\"}}},\"executables\":{\"echo\":\"e1\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"cached\""))
}

///|
test "executable digests must be strings" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"executables\":{\"echo\":1}}",
    ),
  )
}

///|
test "forged cache outputs rejected" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"tampered\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}}}",
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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"hashes\":{\"in.txt\":\"h\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}}}",
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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]},{\"id\":\"c\",\"command\":[\"echo\",\"c\"],\"deps\":[\"b\"],\"inputs\":[\"b.txt\"],\"outputs\":[\"c.txt\"]}],\"hashes\":{\"in.txt\":\"h2\",\"a.txt\":\"ha\",\"b.txt\":\"hb\",\"c.txt\":\"hc\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}}}",
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
test "fingerprint propagation rebuilds dependents of a rebuilt producer" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}],\"hashes\":{\"in.txt\":\"h2\",\"a.txt\":\"ha\",\"b.txt\":\"hb\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}},\"b\":{\"fingerprint\":{\"version\":2,\"command\":\"e70e2ac27552caa5e241886591183f7eda2a64080cf12a89e2bd91cd88103d10\",\"inputs\":\"cead3f8c7613b27789643b8871c4c1c4aa3452c59a7d1e98162ff1ba59b4e188\",\"outputs\":\"bcf50bedc636f90fe982fdae45c361415942ec6b912bc74392b808075f6bcfaf\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{\"a\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"digest\":\"0c509e213e951359247e01ac373d31743e322514b65a9c8f39f0c773a893c611\"},\"outputs\":{\"b.txt\":\"hb\"}}},\"completed\":{\"a\":\"success\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"success\""))
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "1", "reason"]),
    parse("\"fingerprint changed: dependencies\""),
  )
}

///|
test "content propagation stops at identical outputs" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}],\"hashes\":{\"in.txt\":\"h2\",\"a.txt\":\"ha\",\"b.txt\":\"hb\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}},\"b\":{\"fingerprint\":{\"version\":2,\"command\":\"e70e2ac27552caa5e241886591183f7eda2a64080cf12a89e2bd91cd88103d10\",\"inputs\":\"cead3f8c7613b27789643b8871c4c1c4aa3452c59a7d1e98162ff1ba59b4e188\",\"outputs\":\"bcf50bedc636f90fe982fdae45c361415942ec6b912bc74392b808075f6bcfaf\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"93b018d2a750b6faca5920a8ca021183d580ad9388a6b323a34f64eb4a281370\"},\"outputs\":{\"b.txt\":\"hb\"}}},\"completed\":{\"a\":\"success\"},\"propagate\":\"content\"}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"success\""))
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"cached\""))
  assert_eq(
    test_at(result, ["tasks", "1", "reason"]),
    parse("\"fingerprint and outputs verified\""),
  )
}

///|
test "unknown propagation mode" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"propagate\":\"magic\"}",
    ),
  )
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
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"]},{\"id\":\"c\",\"command\":[\"echo\",\"c\"],\"deps\":[\"b\"]}],\"hashes\":{\"in.txt\":\"h\",\"a.txt\":\"ha\"},\"cache\":{\"a\":{\"fingerprint\":{\"version\":2,\"command\":\"8660d5d12a2de6a799d4fbf13dd577991ccb2a84779b1c0502863eb599a186e4\",\"inputs\":\"c0a33e57511793ecf260f2ed34e72f52afccd5094212d877752c04d8d6e762e9\",\"outputs\":\"3169ba9e29527082ac0a22ae78e46eca5efc1f58ff2b47d42c36100b4d9252a8\",\"environment\":\"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"dependencies\":{},\"digest\":\"f74b7952fadcd18580b578ed9b34d3705ed4f833f7e37fbd69eba79d313c2e9c\"},\"outputs\":{\"a.txt\":\"ha\"}}},\"completed\":{\"b\":\"failed\"}}",
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
test "targets select a dependency closure" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"command\":[\"echo\",\"b\"],\"deps\":[\"a\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]},{\"id\":\"c\",\"command\":[\"echo\",\"c\"],\"deps\":[\"b\"],\"inputs\":[\"b.txt\"],\"outputs\":[\"c.txt\"]},{\"id\":\"d\",\"command\":[\"echo\",\"d\"]}],\"hashes\":{\"in.txt\":\"h\"},\"targets\":[\"b\"]}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"waiting\""))
  assert_eq(test_at(result, ["tasks", "2", "status"]), parse("\"skipped\""))
  assert_eq(
    test_at(result, ["tasks", "2", "reason"]),
    parse("\"not required by targets\""),
  )
  assert_eq(test_at(result, ["tasks", "3", "status"]), parse("\"skipped\""))
  assert_eq(test_at(result, ["summary", "skipped"]), parse("[\"c\",\"d\"]"))
  assert_eq(test_at(result, ["terminal"]), parse("false"))
}

///|
test "skipped tasks do not block completion" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"d\",\"command\":[\"echo\",\"d\"]}],\"hashes\":{\"in.txt\":\"h\"},\"targets\":[\"d\"],\"completed\":{\"d\":\"success\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"skipped\""))
  assert_eq(test_at(result, ["tasks", "1", "status"]), parse("\"success\""))
  assert_eq(test_at(result, ["terminal"]), parse("true"))
  assert_eq(test_at(result, ["success"]), parse("true"))
}

///|
test "unknown target" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]}],\"targets\":[\"ghost\"]}",
    ),
  )
}

///|
test "deep chain waits link by link" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"t0\",\"command\":[\"build\",\"0\"],\"inputs\":[\"src.txt\"],\"outputs\":[\"o0\"]},{\"id\":\"t1\",\"command\":[\"build\",\"1\"],\"deps\":[\"t0\"],\"inputs\":[\"o0\"],\"outputs\":[\"o1\"]},{\"id\":\"t2\",\"command\":[\"build\",\"2\"],\"deps\":[\"t1\"],\"inputs\":[\"o1\"],\"outputs\":[\"o2\"]},{\"id\":\"t3\",\"command\":[\"build\",\"3\"],\"deps\":[\"t2\"],\"inputs\":[\"o2\"],\"outputs\":[\"o3\"]},{\"id\":\"t4\",\"command\":[\"build\",\"4\"],\"deps\":[\"t3\"],\"inputs\":[\"o3\"],\"outputs\":[\"o4\"]},{\"id\":\"t5\",\"command\":[\"build\",\"5\"],\"deps\":[\"t4\"],\"inputs\":[\"o4\"],\"outputs\":[\"o5\"]},{\"id\":\"t6\",\"command\":[\"build\",\"6\"],\"deps\":[\"t5\"],\"inputs\":[\"o5\"],\"outputs\":[\"o6\"]},{\"id\":\"t7\",\"command\":[\"build\",\"7\"],\"deps\":[\"t6\"],\"inputs\":[\"o6\"],\"outputs\":[\"o7\"]}],\"hashes\":{\"src.txt\":\"h\"}}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["tasks", "1", "reason"]),
    parse("\"waiting for: t0\""),
  )
  assert_eq(
    test_at(result, ["tasks", "7", "reason"]),
    parse("\"waiting for: t6\""),
  )
  assert_eq(
    test_at(result, ["summary", "waiting"]),
    parse("[\"t1\",\"t2\",\"t3\",\"t4\",\"t5\",\"t6\",\"t7\"]"),
  )
  assert_eq(test_at(result, ["terminal"]), parse("false"))
}

///|
test "wide fan-in respects concurrency" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"p0\",\"command\":[\"make\",\"0\"],\"outputs\":[\"p0.out\"]},{\"id\":\"p1\",\"command\":[\"make\",\"1\"],\"outputs\":[\"p1.out\"]},{\"id\":\"p2\",\"command\":[\"make\",\"2\"],\"outputs\":[\"p2.out\"]},{\"id\":\"p3\",\"command\":[\"make\",\"3\"],\"outputs\":[\"p3.out\"]},{\"id\":\"p4\",\"command\":[\"make\",\"4\"],\"outputs\":[\"p4.out\"]},{\"id\":\"p5\",\"command\":[\"make\",\"5\"],\"outputs\":[\"p5.out\"]},{\"id\":\"join\",\"command\":[\"join\"],\"deps\":[\"p0\",\"p1\",\"p2\",\"p3\",\"p4\",\"p5\"],\"inputs\":[\"p0.out\",\"p1.out\",\"p2.out\",\"p3.out\",\"p4.out\",\"p5.out\"],\"outputs\":[\"joined\"]}],\"concurrency\":4}",
    ),
  )
  assert_eq(
    test_at(result, ["summary", "ready"]),
    parse("[\"p0\",\"p1\",\"p2\",\"p3\"]"),
  )
  assert_eq(
    test_at(result, ["tasks", "4", "reason"]),
    parse("\"concurrency limit reached\""),
  )
  assert_eq(test_at(result, ["tasks", "6", "id"]), parse("\"join\""))
  assert_eq(
    test_at(result, ["tasks", "6", "reason"]),
    parse("\"waiting for: p0, p1, p2, p3, p4, p5\""),
  )
}

///|
test "timeout upper bound accepted" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"timeout_ms\":86400000,\"retries\":10}],\"concurrency\":256}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(test_at(result, ["ready", "0", "timeout_ms"]), parse("86400000"))
  assert_eq(test_at(result, ["ready", "0", "retries"]), parse("10"))
}

///|
test "timeout above one day rejected" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"timeout_ms\":86400001}]}",
    ),
  )
}

///|
test "fractional timeout rejected" {
  assert_true(
    fails("{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"timeout_ms\":1.5}]}"),
  )
}

///|
test "concurrency above limit rejected" {
  assert_true(
    fails(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"]}],\"concurrency\":257}",
    ),
  )
}

///|
test "unicode ids order by code unit" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"b\",\"command\":[\"x\"]},{\"id\":\"构建\",\"command\":[\"x\"]},{\"id\":\"a\",\"command\":[\"x\"]},{\"id\":\"Ärger\",\"command\":[\"x\"]}]}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "id"]), parse("\"a\""))
  assert_eq(test_at(result, ["tasks", "1", "id"]), parse("\"b\""))
  assert_eq(test_at(result, ["tasks", "2", "id"]), parse("\"Ärger\""))
  assert_eq(test_at(result, ["tasks", "3", "id"]), parse("\"构建\""))
}

///|
test "nested output directories" {
  let result = run(
    parse(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"dist/a/b.txt\",\"dist/a/c.txt\"]}]}",
    ),
  )
  assert_eq(test_at(result, ["tasks", "0", "status"]), parse("\"ready\""))
  assert_eq(
    test_at(result, ["ready", "0", "outputs"]),
    parse("[\"dist/a/b.txt\",\"dist/a/c.txt\"]"),
  )
}

///|
test "self dependency rejected" {
  assert_true(
    fails("{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"deps\":[\"a\"]}]}"),
  )
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
