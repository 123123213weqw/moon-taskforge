///|
test "inputs cannot alias by case or repetition" {
  for paths in [["a", "a"], ["A", "a"]] {
    let task = record([
      ("id", String("a")),
      ("command", strings(["echo", "a"])),
      ("inputs", strings(paths)),
    ])
    let bad = try {
      ignore(load_tasks(Array([task])))
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
}
