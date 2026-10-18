///|
fn impact_request(request : Value) -> Value raise {
  let tasks = load_tasks(get(request, "tasks"))
  let changed = string_list(get(request, "changed_inputs"))
  let paths : Map[String, Bool] = Map([])
  for path in changed {
    if !relative_path(path) {
      raise InputError("unsafe changed input path")
    }
    paths[path.to_lower()] = true
  }
  let affected : Map[String, Bool] = Map([])
  let output : Array[Value] = []
  let unaffected : Array[String] = []
  for task in tasks {
    let inputs = task.inputs.filter(path => paths.contains(path.to_lower()))
    let upstream = task.dependencies.filter(id => affected.contains(id))
    if !inputs.is_empty() || !upstream.is_empty() {
      affected[task.id] = true
      output.push(
        record([
          ("id", String(task.id)),
          ("changed_inputs", strings(inputs)),
          ("affected_dependencies", strings(upstream)),
        ]),
      )
    } else {
      unaffected.push(task.id)
    }
  }
  record([
    ("affected", Array(output)),
    ("unaffected", strings(unaffected)),
    ("plan_only", Bool(true)),
    (
      "scope",
      String(
        "potential dependency closure; content cutoff and cache may reduce actual work",
      ),
    ),
  ])
}
