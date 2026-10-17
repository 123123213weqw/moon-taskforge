///|
pub(all) struct Task {
  id : String
  dependencies : Array[String]
  command : Array[String]
  inputs : Array[String]
  outputs : Array[String]
  timeout_ms : Int32
  grace_ms : Int32
  retries : Int32
} derive(Eq)

///|
let fingerprint_version : Double = 2.0

///|
let fingerprint_fields : Array[String] = [
  "inputs", "command", "executable", "environment", "dependencies", "outputs",
]

///|
fn relative_path(path : String) -> Bool {
  path != "" &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.contains(":") &&
  !path.split("/").any(p => p == "" || p == "." || p == "..")
}

///|
fn integer_in(
  value : Value,
  fallback : Double,
  low : Double,
  high : Double,
  what : String,
) -> Int32 raise {
  let n = optional_num(value, fallback)
  if n < low || n > high || n.floor() != n {
    raise InputError("invalid " + what)
  }
  n.to_int()
}

///|
/// Validates the task graph and returns it in execution order: every task
/// follows all of its dependencies, ties are broken by task id in UTF-16
/// code unit order.
pub fn load_tasks(value : Value) -> Array[Task] raise {
  let tasks : Map[String, Task] = Map([])
  let output_owners : Map[String, String] = Map([])
  for item in arr(value) {
    let id = str(get(item, "id"))
    if id == "" || tasks.contains(id) {
      raise InputError("empty or duplicate task id")
    }
    let dependencies = optional_strings(get(item, "deps"))
    let command = string_list(get(item, "command"))
    if command.is_empty() || command[0] == "" {
      raise InputError("task command must be a nonempty argv array")
    }
    let inputs = optional_strings(get(item, "inputs"))
    let outputs = optional_strings(get(item, "outputs"))
    for path in inputs + outputs {
      if !relative_path(path) {
        raise InputError("unsafe task path: " + path)
      }
    }
    for path in outputs {
      let folded = path.to_lower()
      if output_owners
        .keys()
        .any(other => {
          folded == other ||
          folded.has_prefix(other + "/") ||
          other.has_prefix(folded + "/")
        }) {
        raise InputError("task output paths conflict: " + path)
      }
      output_owners[folded] = id
    }
    tasks[id] = Task::{
      id,
      dependencies,
      command,
      inputs,
      outputs,
      timeout_ms: integer_in(
        get(item, "timeout_ms"),
        60000.0,
        1.0,
        86400000.0,
        "timeout_ms",
      ),
      grace_ms: integer_in(get(item, "grace_ms"), 0.0, 0.0, 60000.0, "grace_ms"),
      retries: integer_in(get(item, "retries"), 0.0, 0.0, 10.0, "retries"),
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
  sort_lexical(keys)
  let ordered : Array[Task] = []
  let done : Map[String, Bool] = Map([])
  while ordered.length() < tasks.length() {
    let mut progress = false
    for id in keys {
      let task = tasks[id]
      if !done.contains(id) && task.dependencies.all(dep => done.contains(dep)) {
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
/// A fingerprint is a Merkle node: every field is the digest of its
/// canonical JSON, dependencies contribute only their digests, and the node
/// carries its own digest, so size stays constant however deep the graph.
/// The executable digest is included only when the host supplied one for
/// the task's program.
fn fingerprint(
  task : Task,
  hashes : Value,
  executables : Value,
  env : Value,
  dependencies : Map[String, Value],
  by_content : Bool,
) -> Value {
  let fields = [
    ("version", Number(fingerprint_version)),
    ("command", String(digest(canonical(strings(task.command))))),
    (
      "inputs",
      String(
        digest(
          canonical(record(task.inputs.map(path => (path, get(hashes, path))))),
        ),
      ),
    ),
  ]
  match get(executables, task.command[0]) {
    Null => ()
    program => fields.push(("executable", program))
  }
  fields.push(("outputs", String(digest(canonical(strings(task.outputs))))))
  fields.push(("environment", String(digest(canonical(env)))))
  // With content propagation a dependency only schedules; invalidation then
  // follows the declared files alone, so an identical rebuild stops there.
  fields.push(
    (
      "dependencies",
      if by_content {
        record([])
      } else {
        record(
          task.dependencies.map(id => (id, get(dependencies[id], "digest"))),
        )
      },
    ),
  )
  fields.push(("digest", String(digest(canonical(record(fields))))))
  record(fields)
}

///|
/// Explains why a task cannot reuse its cache entry.
fn stale_reason(
  task : Task,
  saved : Value,
  current : Value,
  output_hashes : Value,
  output_exists : Bool,
) -> String {
  if task.outputs.is_empty() {
    return "no outputs declared"
  }
  if saved == Null {
    return "no cache entry"
  }
  let previous = get(saved, "fingerprint")
  if previous != current {
    for field in fingerprint_fields {
      if get(previous, field) != get(current, field) {
        return "fingerprint changed: " + field
      }
    }
    return "fingerprint changed: version"
  }
  if !output_exists {
    return "outputs missing"
  }
  if get(saved, "outputs") != output_hashes {
    return "outputs changed"
  }
  "cache entry rejected"
}

///|
fn string_map(value : Value, what : String) -> Map[String, Value] raise {
  let fields = if value == Null { Map([]) } else { obj(value) }
  for key, item in fields {
    match item {
      String(_) => ()
      _ => raise InputError(what + " values must be strings: " + key)
    }
  }
  fields
}

///|
pub fn run(request : Value) -> Value raise {
  let tasks = load_tasks(get(request, "tasks"))
  let hashes = Object(string_map(get(request, "hashes"), "hash"))
  let executables = Object(
    string_map(get(request, "executables"), "executable digest"),
  )
  let env = Object(string_map(get(request, "environment"), "environment"))
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
  ignore(obj(cache))
  ignore(obj(completed))
  let concurrency = integer_in(
    get(request, "concurrency"),
    4.0,
    1.0,
    256.0,
    "concurrency",
  )
  // Targets restrict the run to the named tasks and their transitive
  // dependencies; everything else is reported as skipped.
  let required : Map[String, Bool] = Map([])
  let targets = optional_strings(get(request, "targets"))
  if get(request, "targets") != Null {
    let by_id : Map[String, Task] = Map([])
    for task in tasks {
      by_id[task.id] = task
    }
    let pending = targets.copy()
    while pending.length() > 0 {
      let id = pending.pop().unwrap()
      match by_id.get(id) {
        None => raise InputError("unknown target: " + id)
        Some(task) =>
          if !required.contains(id) {
            required[id] = true
            for dep in task.dependencies {
              pending.push(dep)
            }
          }
      }
    }
  }
  let propagate = optional_str(get(request, "propagate"), "fingerprint")
  if propagate != "fingerprint" && propagate != "content" {
    raise InputError("unknown propagation mode: " + propagate)
  }
  let statuses : Map[String, String] = Map([])
  let fingerprints : Map[String, Value] = Map([])
  let refreshed : Map[String, Value] = Map([])
  let reports : Array[Value] = []
  let ready : Array[Value] = []
  let groups : Map[String, Array[String]] = Map([])
  for
    status in [
      "cached", "success", "failed", "blocked", "ready", "waiting", "skipped",
    ] {
    groups[status] = []
  }
  let rerun : Array[String] = []
  let mut terminal = true
  let mut success = true
  for task in tasks {
    let fp = fingerprint(
      task,
      hashes,
      executables,
      env,
      fingerprints,
      propagate == "content",
    )
    fingerprints[task.id] = fp
    let pending = task.dependencies.filter(id => {
      !["success", "cached"].contains(statuses[id])
    })
    let failed_dependency = task.dependencies.filter(id => {
      ["failed", "blocked"].contains(statuses[id])
    })
    let dependencies_ok = pending.is_empty()
    let missing_inputs = task.inputs.filter(path => get(hashes, path) == Null)
    let output_exists = !task.outputs.is_empty() &&
      task.outputs.all(path => get(hashes, path) != Null)
    let saved = get(cache, task.id)
    let output_hashes = record(
      task.outputs.map(path => (path, get(hashes, path))),
    )
    let cache_valid = dependencies_ok &&
      missing_inputs.is_empty() &&
      output_exists &&
      get(saved, "fingerprint") == fp &&
      get(saved, "outputs") == output_hashes
    let finished = get(completed, task.id)
    let selected = get(request, "targets") == Null || required.contains(task.id)
    let (status, reason) = if !selected {
      ("skipped", "not required by targets")
    } else if !failed_dependency.is_empty() {
      ("blocked", "dependency failed: " + failed_dependency.join(", "))
    } else if finished == String("failed") {
      ("failed", "reported failed by executor")
    } else if finished == String("success") {
      if !dependencies_ok ||
        !missing_inputs.is_empty() ||
        (!task.outputs.is_empty() && !output_exists) {
        raise InputError(
          "success reported before dependency/input/output verification: " +
          task.id,
        )
      }
      ("success", "reported success by executor")
    } else if finished != Null {
      raise InputError("invalid completed status for " + task.id)
    } else if cache_valid {
      ("cached", "fingerprint and outputs verified")
    } else if dependencies_ok {
      if !missing_inputs.is_empty() {
        ("failed", "missing input: " + missing_inputs.join(", "))
      } else if ready.length() < concurrency {
        ("ready", stale_reason(task, saved, fp, output_hashes, output_exists))
      } else {
        ("waiting", "concurrency limit reached")
      }
    } else {
      ("waiting", "waiting for: " + pending.join(", "))
    }
    statuses[task.id] = status
    groups[status].push(task.id)
    if status == "ready" {
      ready.push(
        record([
          ("id", String(task.id)),
          ("command", strings(task.command)),
          ("outputs", strings(task.outputs)),
          ("timeout_ms", Number(task.timeout_ms.to_double())),
          ("grace_ms", Number(task.grace_ms.to_double())),
          ("retries", Number(task.retries.to_double())),
        ]),
      )
    }
    if status == "ready" || status == "waiting" {
      terminal = false
    }
    if status == "failed" || status == "blocked" {
      success = false
      rerun.push(task.id)
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
        ("reason", String(reason)),
        ("fingerprint", fp),
      ]),
    )
  }
  let summary = groups.map((_, ids) => strings(ids))
  summary["rerun"] = strings(rerun)
  record([
    ("tasks", Array(reports)),
    ("ready", Array(ready)),
    ("terminal", Bool(terminal)),
    ("success", Bool(terminal && success)),
    ("summary", Object(summary)),
    ("cache", Object(refreshed)),
  ])
}
