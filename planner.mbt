///|
pub(all) struct Task {
  id : String
  dependencies : Array[String]
  command : Array[String]
  inputs : Array[String]
  outputs : Array[String]
  timeout_ms : Int
  retries : Int
} derive(Eq)

///|
fn relative_path(path : String) -> Bool {
  path != "" &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.contains(":") &&
  !path.split("/").any(fn(p) { p == "" || p == "." || p == ".." })
}

///|
pub fn load_tasks(value : Value) -> Array[Task] raise {
  let tasks : Map[String, Task] = Map([])
  let output_owners : Map[String, String] = Map([])
  for item in arr(value) {
    let id = str(get(item, "id"))
    if id == "" || tasks.contains(id) {
      raise InputError("empty or duplicate task id")
    }
    let dependencies = if get(item, "deps") == Null {
      []
    } else {
      string_list(get(item, "deps"))
    }
    let command = string_list(get(item, "command"))
    if command.is_empty() || command[0] == "" {
      raise InputError("task command must be a nonempty argv array")
    }
    let inputs = if get(item, "inputs") == Null {
      []
    } else {
      string_list(get(item, "inputs"))
    }
    let outputs = if get(item, "outputs") == Null {
      []
    } else {
      string_list(get(item, "outputs"))
    }
    for path in inputs + outputs {
      if !relative_path(path) {
        raise InputError("unsafe task path: " + path)
      }
    }
    for path in outputs {
      let folded = path.to_lower()
      if output_owners
        .keys()
        .any(fn(other) {
          folded == other ||
          folded.has_prefix(other + "/") ||
          other.has_prefix(folded + "/")
        }) {
        raise InputError("task output paths conflict")
      }
      output_owners[folded] = id
    }
    let timeout = optional_num(get(item, "timeout_ms"), 60000.0)
    let retries = optional_num(get(item, "retries"), 0.0)
    if timeout < 1.0 ||
      timeout > 86400000.0 ||
      timeout.floor() != timeout ||
      retries < 0.0 ||
      retries > 10.0 ||
      retries.floor() != retries {
      raise InputError("invalid timeout or retries")
    }
    tasks[id] = Task::{
      id,
      dependencies,
      command,
      inputs,
      outputs,
      timeout_ms: timeout.to_int(),
      retries: retries.to_int(),
    }
  }
  for _, task in tasks {
    let seen : Map[String, Bool] = Map([])
    for dep in task.dependencies {
      if !tasks.contains(dep) || seen.contains(dep) {
        raise InputError("unknown or duplicate dependency for " + task.id)
      }
      seen[dep] = true
    }
  }
  let keys = tasks.keys().collect()
  keys.sort()
  let ordered : Array[Task] = []
  let done : Map[String, Bool] = Map([])
  while ordered.length() < tasks.size() {
    let mut progress = false
    for id in keys {
      let task = tasks[id]
      if !done.contains(id) &&
        task.dependencies.all(fn(dep) { done.contains(dep) }) {
        ordered.push(task)
        done[id] = true
        progress = true
      }
    }
    if !progress {
      raise InputError("task dependency cycle")
    }
  }
  // Produced inputs must declare their producer, directly or transitively.
  let ancestors : Map[String, Map[String, Bool]] = Map([])
  for task in ordered {
    let reachable : Map[String, Bool] = Map([])
    for dep in task.dependencies {
      reachable[dep] = true
      for ancestor, _ in ancestors[dep] {
        reachable[ancestor] = true
      }
    }
    for path in task.inputs {
      match output_owners.get(path.to_lower()) {
        Some(owner) =>
          if !reachable.contains(owner) {
            raise InputError("input producer is not a dependency: " + path)
          }
        None => ()
      }
    }
    ancestors[task.id] = reachable
  }
  ordered
}

///|
fn fingerprint(
  task : Task,
  hashes : Value,
  env : Value,
  dependencies : Map[String, Value],
) -> Value {
  let inputs = record(task.inputs.map(fn(path) { (path, get(hashes, path)) }))
  let deps = record(task.dependencies.map(fn(id) { (id, dependencies[id]) }))
  record([
    ("version", Number(1.0)),
    ("command", strings(task.command)),
    ("inputs", inputs),
    ("outputs", strings(task.outputs)),
    ("environment", env),
    ("dependencies", deps),
  ])
}

///|
pub fn run(request : Value) -> Value raise {
  let tasks = load_tasks(get(request, "tasks"))
  let hashes = if get(request, "hashes") == Null {
    Object(Map([]))
  } else {
    get(request, "hashes")
  }
  let cache = if get(request, "cache") == Null {
    Object(Map([]))
  } else {
    get(request, "cache")
  }
  let completed = if get(request, "completed") == Null {
    Object(Map([]))
  } else {
    get(request, "completed")
  }
  let env = if get(request, "environment") == Null {
    Object(Map([]))
  } else {
    get(request, "environment")
  }
  ignore(obj(hashes))
  ignore(obj(cache))
  ignore(obj(completed))
  ignore(obj(env))
  let concurrency = optional_num(get(request, "concurrency"), 4.0)
  if concurrency < 1.0 ||
    concurrency > 256.0 ||
    concurrency.floor() != concurrency {
    raise InputError("invalid concurrency")
  }
  let statuses : Map[String, String] = Map([])
  let fingerprints : Map[String, Value] = Map([])
  let refreshed : Map[String, Value] = Map([])
  let reports : Array[Value] = []
  let ready : Array[Value] = []
  let mut terminal = true
  let mut success = true
  for task in tasks {
    let fp = fingerprint(task, hashes, env, fingerprints)
    fingerprints[task.id] = fp
    let dependencies_ok = task.dependencies.all(fn(id) {
      ["success", "cached"].contains(statuses[id])
    })
    let dependencies_failed = task.dependencies.any(fn(id) {
      ["failed", "blocked"].contains(statuses[id])
    })
    let input_exists = task.inputs.all(fn(path) { get(hashes, path) != Null })
    let output_exists = !task.outputs.is_empty() &&
      task.outputs.all(fn(path) { get(hashes, path) != Null })
    let saved = get(cache, task.id)
    let output_hashes = record(
      task.outputs.map(fn(path) { (path, get(hashes, path)) }),
    )
    let cache_valid = dependencies_ok &&
      input_exists &&
      output_exists &&
      get(saved, "fingerprint") == fp &&
      get(saved, "outputs") == output_hashes
    let finished = get(completed, task.id)
    let status = if dependencies_failed {
      "blocked"
    } else if finished == String("failed") {
      "failed"
    } else if finished == String("success") {
      if !dependencies_ok ||
        !input_exists ||
        (!task.outputs.is_empty() && !output_exists) {
        raise InputError(
          "success reported before dependency/input/output verification: " +
          task.id,
        )
      }
      "success"
    } else if finished != Null {
      raise InputError("invalid completed status")
    } else if cache_valid {
      "cached"
    } else if dependencies_ok {
      if !input_exists {
        "failed"
      } else if ready.length() < concurrency.to_int() {
        "ready"
      } else {
        "waiting"
      }
    } else {
      "waiting"
    }
    statuses[task.id] = status
    if status == "ready" {
      ready.push(
        record([
          ("id", String(task.id)),
          ("command", strings(task.command)),
          ("outputs", strings(task.outputs)),
          ("timeout_ms", Number(task.timeout_ms.to_double())),
          ("retries", Number(task.retries.to_double())),
        ]),
      )
    }
    if status == "ready" || status == "waiting" {
      terminal = false
    }
    if status == "failed" || status == "blocked" {
      success = false
    }
    if (status == "success" || status == "cached") && output_exists {
      refreshed[task.id] = record([
        ("fingerprint", fp),
        ("outputs", output_hashes),
      ])
    }
    reports.push(
      record([
        ("id", String(task.id)),
        ("status", String(status)),
        ("fingerprint", fp),
      ]),
    )
  }
  record([
    ("tasks", Array(reports)),
    ("ready", Array(ready)),
    ("terminal", Bool(terminal)),
    ("success", Bool(terminal && success)),
    ("cache", Object(refreshed)),
  ])
}
