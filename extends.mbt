// Promotion policy follows moonbitlang/core: `equal` and `to_string` stay
// regular methods; operator derivatives and `Debug::to_repr` go through
// the trait.

///|
pub extend Value with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Value with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend InputError with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend InputError with Eq::{not_equal}

///|
pub extend InputError with Show::{to_string}

///|
#deprecated("Use `to_string` instead", skip_current_package=true)
#doc(hidden)
pub extend InputError with Show::{output}

///|
pub extend Task with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend Task with Eq::{not_equal}
