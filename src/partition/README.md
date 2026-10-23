# Exact-token document partitions

`Delthin/moon_repomix/partition` partitions an accepted `@document.Document` into whole-file and whole-section volumes. Supply a deterministic renderer, an exact token counter, and a metadata projection. All three callbacks may raise; their errors propagate unchanged.

```mbt nocheck
let result = @partition.partition(
  document,
  max_tokens,
  render=doc => @output.xml(doc),
  count=text => encoder.count(text),
  project_metadata=(file_indices, section_indices) =>
    project_metadata(file_indices, section_indices),
)
```

Wrap pure functions in lambdas when passing them as raising callbacks. The package's production imports are limited to `document`; renderers and encoders are chosen by the caller.

## Ordering and token limits

Files are ordered by UTF-8 path bytes, followed by sections in their original order. `file_indices` and `section_indices` always refer to the input document, even when its files were unsorted. Empty files remain atoms, and sections with identical titles remain distinct. Paths and bodies are preserved verbatim.

Every volume repeats `header_text` and `instruction_text`. Its document contains only its own files and sections, so renderers derive a volume-local tree. `Volume.text` is the exact string counted; `tokens` is its nonnegative count and `bytes` is its UTF-8 byte length. IDs start at `part-0001`, in output order, with at least four digits.

The algorithm renders and counts a whole candidate. If it exceeds the cap, it recursively halves that candidate by atom count. It does not assume additive or monotonic token counts, and does not promise the minimum number of volumes. Each atom participates in at most O(log n) candidate renders. An empty document returns one counted template volume.

The metadata projection receives owned copies of the original indices for each candidate, including the empty template and rejected candidates. It may be called more often than there are returned volumes. It must explicitly select all volume metadata; global custom metadata is not copied automatically. The index retains the input metadata unchanged.

## Index schema v1

`Partition.index` has these fields:

- `schemaVersion`: `1`.
- `volumes`: ordered summaries with `id`, `tokens`, `bytes`, `fileIndices`, and `sectionIndices`.
- `files`: object mapping each original canonical file path to its volume ID.
- `sections`: object mapping each original section index, as a decimal string, to its volume ID.
- `metadata`: the complete original global metadata.

The index contains no file or section bodies. `index_text` is the compact JSON serialization followed by exactly one LF. It is counted independently as `index_tokens`, without applying the volume cap. `total_tokens : Int64` sums the counts of the independently encoded volume texts and index text, not an encoding of their concatenation.

## Failures

`PartitionError` reports:

- `InvalidCap(cap)` for a nonpositive cap, before any callbacks.
- `DuplicatePath(path)` before template rendering.
- `TemplateTooLarge(actual)` if the projected empty template exceeds the cap.
- `UnitTooLarge(FilePath(path), actual)` or `UnitTooLarge(SectionIndex(original_index), actual)` if an unsplit atom still exceeds it.
- `InvalidCount(actual)` for a negative counter result, including an index count.
- `Overflow(field)` for sizes or totals that cannot fit their declared integer types.
- `InvalidTextEncoding` for malformed UTF-16 paths or rendered text that cannot be encoded as UTF-8.

Token fields and caps use `Int32`; total tokens use `Int64`. A failed callback or validation returns no partial partition.
