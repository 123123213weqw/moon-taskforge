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
      Array(items) => items[num(parse_value(part)).to_int()]
      _ => raise InputError("invalid test traversal")
    }
  }
  current
}

///|
test "initial ready wave" {
  let result = run(
    parse_value(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"deps\":[\"a\"],\"command\":[\"echo\",\"b\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}],\"hashes\":{\"in.txt\":\"h\"}}",
    ),
  )
  assert_eq(test_at(result, ["ready", "0", "id"]), parse_value("\"a\""))
  assert_eq(
    test_at(result, ["tasks", "1", "status"]),
    parse_value("\"waiting\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse_value("false"))
}

///|
test "failure blocks downstream" {
  let result = run(
    parse_value(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"deps\":[\"a\"],\"command\":[\"echo\",\"b\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}],\"hashes\":{\"in.txt\":\"h\"},\"completed\":{\"a\":\"failed\"}}",
    ),
  )
  assert_eq(
    test_at(result, ["tasks", "0", "status"]),
    parse_value("\"failed\""),
  )
  assert_eq(
    test_at(result, ["tasks", "1", "status"]),
    parse_value("\"blocked\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse_value("true"))
  assert_eq(test_at(result, ["success"]), parse_value("false"))
}

///|
test "missing input fails" {
  let result = run(
    parse_value(
      "{\"tasks\":[{\"id\":\"a\",\"command\":[\"echo\",\"a\"],\"inputs\":[\"in.txt\"],\"outputs\":[\"a.txt\"]},{\"id\":\"b\",\"deps\":[\"a\"],\"command\":[\"echo\",\"b\"],\"inputs\":[\"a.txt\"],\"outputs\":[\"b.txt\"]}]}",
    ),
  )
  assert_eq(
    test_at(result, ["tasks", "0", "status"]),
    parse_value("\"failed\""),
  )
  assert_eq(
    test_at(result, ["tasks", "1", "status"]),
    parse_value("\"blocked\""),
  )
  assert_eq(test_at(result, ["terminal"]), parse_value("true"))
}

///|
test "topological cycle" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"tasks\":[{\"id\":\"a\",\"deps\":[\"b\"],\"command\":[\"x\"]},{\"id\":\"b\",\"deps\":[\"a\"],\"command\":[\"x\"]}]}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "output conflict" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"same\"]},{\"id\":\"b\",\"command\":[\"x\"],\"outputs\":[\"same\"]}]}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "unsafe inputs" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"inputs\":[\"../x\"]}]}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "producer dependency required" {
  let failed = try {
    ignore(
      run(
        parse_value(
          "{\"tasks\":[{\"id\":\"a\",\"command\":[\"x\"],\"outputs\":[\"a\"]},{\"id\":\"b\",\"command\":[\"x\"],\"inputs\":[\"a\"]}]}",
        ),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "concurrency bound" {
  let result = run(
    parse_value(
      "{\"tasks\":[{\"id\":\"0\",\"command\":[\"x\"]},{\"id\":\"1\",\"command\":[\"x\"]},{\"id\":\"2\",\"command\":[\"x\"]},{\"id\":\"3\",\"command\":[\"x\"]}],\"concurrency\":2}",
    ),
  )
  assert_eq(
    test_at(result, ["tasks", "2", "status"]),
    parse_value("\"waiting\""),
  )
  assert_eq(test_at(result, ["ready", "1", "id"]), parse_value("\"1\""))
}
