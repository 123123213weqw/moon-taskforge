///|
pub(all) suberror InputError {
  InputError(String)
} derive(Eq)

///|
pub impl Show for InputError with fn output(self, logger) {
  match self {
    InputError(message) => logger.write_string(message)
  }
}

///|
fn get(value : Value, key : String) -> Value {
  match value {
    Object(obj) => obj.get(key).unwrap_or(Null)
    _ => Null
  }
}

///|
fn str(value : Value) -> String raise InputError {
  match value {
    String(s) => s
    _ => raise InputError("expected string")
  }
}

///|
fn arr(value : Value) -> Array[Value] raise InputError {
  match value {
    Array(items) => items
    _ => raise InputError("expected array")
  }
}

///|
fn obj(value : Value) -> Map[String, Value] raise InputError {
  match value {
    Object(fields) => fields
    _ => raise InputError("expected object")
  }
}

///|
fn num(value : Value) -> Double raise InputError {
  match value {
    Number(n) if !n.is_nan() && !n.is_inf() => n
    _ => raise InputError("expected finite number")
  }
}

///|
fn optional_num(value : Value, fallback : Double) -> Double raise InputError {
  match value {
    Null => fallback
    _ => num(value)
  }
}

///|
fn record(fields : Array[(String, Value)]) -> Value {
  let result : Map[String, Value] = Map([])
  for (key, value) in fields {
    result[key] = value
  }
  Object(result)
}

///|
fn strings(items : Array[String]) -> Value {
  Array(items.map(s => String(s)))
}

///|
fn string_list(value : Value) -> Array[String] raise InputError {
  arr(value).map(item => str(item))
}

///|
fn optional_strings(value : Value) -> Array[String] raise {
  if value == Null {
    []
  } else {
    string_list(value)
  }
}

///|
/// Deterministic identifier order is UTF-16 code unit order, not the
/// length-first order that `Compare for String` provides.
fn sort_lexical(items : Array[String]) -> Unit {
  items.sort_by(String::lexical_compare)
}
