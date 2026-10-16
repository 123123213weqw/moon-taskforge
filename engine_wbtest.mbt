// Property-style tests that build their inputs programmatically; the
// example-driven cases live in fixtures_wbtest.mbt.

///|
/// Deterministic pseudo-random generator for reproducible graphs.
fn next(state : Ref[Int32]) -> Int32 {
  state.val = (state.val * 1103515245 + 12345) & 0x7fffffff
  state.val >> 8
}

///|
fn flag(value : Value) -> Bool {
  value == Bool(true)
}

///|
/// A task graph where task i may depend on earlier tasks only, so the graph is
/// acyclic by construction and every produced input names its producer.
fn graph(count : Int32, seed : Int32) -> Value {
  let state : Ref[Int32] = Ref(seed)
  let tasks : Array[Value] = []
  for i = 0; i < count; i = i + 1 {
    let deps : Array[String] = []
    let inputs : Array[String] = ["src" + i.to_string() + ".txt"]
    let limit = if i < 3 { i } else { 3 }
    for d = 0; d < limit; d = d + 1 {
      let candidate = next(state) % i
      let id = "t" + candidate.to_string()
      if !deps.contains(id) {
        deps.push(id)
        inputs.push("out" + candidate.to_string() + ".txt")
      }
    }
    tasks.push(
      record([
        ("id", String("t" + i.to_string())),
        ("deps", strings(deps)),
        ("command", strings(["build", i.to_string()])),
        ("inputs", strings(inputs)),
        ("outputs", strings(["out" + i.to_string() + ".txt"])),
      ]),
    )
  }
  Array(tasks)
}

///|
fn ids(value : Value) -> Array[String] raise {
  arr(value).map(item => str(get(item, "id")))
}

///|
fn dependencies_of(tasks : Value) -> Map[String, Array[String]] raise {
  let result : Map[String, Array[String]] = Map([])
  for task in arr(tasks) {
    result[str(get(task, "id"))] = string_list(get(task, "deps"))
  }
  result
}

///|
fn output_of(id : String) -> String {
  "out" + id[1:].to_owned() + ".txt"
}

///|
/// Drives the planner to a terminal state by reporting every ready task as
/// successful with its outputs present, and returns the completion order.
fn drive(tasks : Value, concurrency : Int32) -> Array[String] raise {
  let hashes : Map[String, Value] = Map([])
  for task in arr(tasks) {
    for input in string_list(get(task, "inputs")) {
      if input.has_prefix("src") {
        hashes[input] = String("h")
      }
    }
  }
  let completed : Map[String, Value] = Map([])
  let order : Array[String] = []
  let mut waves = 0
  while true {
    let plan = run(
      record([
        ("tasks", tasks),
        ("hashes", Object(hashes)),
        ("completed", Object(completed)),
        ("concurrency", Number(concurrency.to_double())),
      ]),
    )
    if flag(get(plan, "terminal")) {
      assert_true(flag(get(plan, "success")))
      break
    }
    let ready = ids(get(plan, "ready"))
    assert_true(ready.length() >= 1 && ready.length() <= concurrency)
    for id in ready {
      order.push(id)
      completed[id] = String("success")
      hashes[output_of(id)] = String("o")
    }
    waves += 1
    if waves > 1000 {
      abort("scheduler did not terminate")
    }
  }
  order
}

///|
test "execution order respects dependencies for generated graphs" {
  for seed in [1, 7, 42] {
    let tasks = graph(60, seed)
    let deps = dependencies_of(tasks)
    for concurrency in [1, 3, 8] {
      let order = drive(tasks, concurrency)
      assert_eq(order.length(), 60)
      let position : Map[String, Int32] = Map([])
      for i = 0; i < order.length(); i = i + 1 {
        position[order[i]] = i
      }
      for id, needed in deps {
        for dep in needed {
          assert_true(position[dep] < position[id])
        }
      }
    }
  }
}

///|
/// Tasks that transitively depend on `root`, computed by reverse traversal.
fn dependents(
  deps : Map[String, Array[String]],
  root : String,
) -> Array[String] {
  let affected : Array[String] = [root]
  let mut changed = true
  while changed {
    changed = false
    for id, needed in deps {
      if !affected.contains(id) && needed.any(dep => affected.contains(dep)) {
        affected.push(id)
        changed = true
      }
    }
  }
  sort_lexical(affected)
  affected
}

///|
test "cache reuse and invalidation closure after an input change" {
  let tasks = graph(40, 99)
  let deps = dependencies_of(tasks)
  let hashes : Map[String, Value] = Map([])
  let completed : Map[String, Value] = Map([])
  for id in ids(tasks) {
    hashes["src" + id[1:].to_owned() + ".txt"] = String("h")
    hashes[output_of(id)] = String("o")
    completed[id] = String("success")
  }
  let done = run(
    record([
      ("tasks", tasks),
      ("hashes", Object(hashes)),
      ("completed", Object(completed)),
    ]),
  )
  let cache = get(done, "cache")
  let replay = run(
    record([("tasks", tasks), ("hashes", Object(hashes)), ("cache", cache)]),
  )
  for report in arr(get(replay, "tasks")) {
    assert_eq(get(report, "status"), String("cached"))
  }
  assert_true(flag(get(replay, "terminal")))
  hashes["src5.txt"] = String("changed")
  let invalidated = run(
    record([("tasks", tasks), ("hashes", Object(hashes)), ("cache", cache)]),
  )
  let stale : Array[String] = []
  for report in arr(get(invalidated, "tasks")) {
    if get(report, "status") != String("cached") {
      stale.push(str(get(report, "id")))
    }
  }
  sort_lexical(stale)
  assert_eq(stale, dependents(deps, "t5"))
  for report in arr(get(invalidated, "tasks")) {
    if get(report, "id") == String("t5") {
      assert_eq(get(report, "reason"), String("fingerprint changed: inputs"))
    }
  }
}

///|
test "plans are reproducible" {
  let tasks = graph(30, 5)
  let request = record([("tasks", tasks), ("concurrency", Number(2.0))])
  assert_eq(run(request).stringify(), run(request).stringify())
}
