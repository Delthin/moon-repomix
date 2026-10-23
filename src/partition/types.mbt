///|
/// Identity in the input document, independent of section titles.
pub(all) enum UnitIdentity {
  FilePath(String)
  SectionIndex(Int32)
} derive(Debug, Eq)

///|
pub extend UnitIdentity with Eq::{equal, not_equal}

///|
pub extend UnitIdentity with Debug::{to_repr}

///|
/// Callback errors propagate unchanged; these errors describe partition failures.
pub(all) suberror PartitionError {
  InvalidCap(Int32)
  DuplicatePath(String)
  TemplateTooLarge(Int32)
  UnitTooLarge(UnitIdentity, Int32)
  InvalidCount(Int32)
  Overflow(String)
  InvalidTextEncoding
} derive(Debug, Eq)

///|
pub extend PartitionError with Eq::{equal, not_equal}

///|
pub extend PartitionError with Debug::{to_repr}

///|
/// `text` is exactly the rendered string passed to the counter.
pub struct Volume {
  id : String
  document : @document.Document
  text : String
  tokens : Int32
  bytes : Int32
  file_indices : Array[Int32]
  section_indices : Array[Int32]
}

///|
/// Total tokens include each independent volume and the independent index.
pub struct Partition {
  volumes : Array[Volume]
  index : Json
  index_text : String
  index_tokens : Int32
  total_tokens : Int64
}
