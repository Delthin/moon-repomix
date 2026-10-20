///|
/// A retained source fragment's 1-based inclusive line bounds. Fragments may
/// cover partial lines, so consecutive ranges can share a line number.
pub(all) struct LineRange {
  start_line : Int32
  end_line : Int32
} derive(Debug, Eq)

///|
pub extend LineRange with Eq::{equal, not_equal}

///|
pub extend LineRange with Debug::{to_repr}

///|
/// An AST outline, or the unchanged input when compression was not applied.
/// Ranges describe retained original fragments, excluding synthetic omission
/// markers. A fallback has no selection ranges.
pub(all) struct Outcome {
  text : String
  language : String?
  applied : Bool
  reason : String?
  ranges : Array[LineRange]
} derive(Debug, Eq)

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend Outcome with Debug::{to_repr}
