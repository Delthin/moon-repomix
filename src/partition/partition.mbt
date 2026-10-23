///|
priv enum Atom {
  File(Int32)
  Section(Int32)
}

///|
fn make_candidate(
  original : @document.Document,
  atoms : ArrayView[Atom],
  project_metadata : (Array[Int32], Array[Int32]) -> Json raise,
) -> (@document.Document, Array[Int32], Array[Int32]) raise {
  let file_indices : Array[Int32] = []
  let section_indices : Array[Int32] = []
  for atom in atoms {
    match atom {
      File(i) => file_indices.push(i)
      Section(i) => section_indices.push(i)
    }
  }
  let metadata = project_metadata(file_indices.copy(), section_indices.copy())
  let document : @document.Document = {
    files: file_indices.map(i => original.files[i]),
    sections: section_indices.map(i => original.sections[i]),
    metadata,
    header_text: original.header_text,
    instruction_text: original.instruction_text,
  }
  (document, file_indices, section_indices)
}

///|
fn split_candidate(
  original : @document.Document,
  atoms : ArrayView[Atom],
  max_tokens : Int32,
  render : (@document.Document) -> String raise,
  count : (String) -> Int32 raise,
  project_metadata : (Array[Int32], Array[Int32]) -> Json raise,
  volumes : Array[Volume],
) -> Unit raise {
  let (document, file_indices, section_indices) = make_candidate(
    original, atoms, project_metadata,
  )
  let text = render(document)
  let bytes = byte_length(text)
  let tokens = checked_count(text, count)
  if tokens <= max_tokens {
    if volumes.length() == 2147483647 {
      raise Overflow("volume ID")
    }
    volumes.push({
      id: volume_id(volumes.length() + 1),
      document,
      text,
      tokens,
      bytes,
      file_indices,
      section_indices,
    })
  } else if atoms.length() == 1 {
    let identity = match atoms[0] {
      File(i) => FilePath(original.files[i].path)
      Section(i) => SectionIndex(i)
    }
    raise UnitTooLarge(identity, tokens)
  } else {
    let middle = atoms.length() / 2
    split_candidate(
      original,
      atoms[:middle],
      max_tokens,
      render,
      count,
      project_metadata,
      volumes,
    )
    split_candidate(
      original,
      atoms[middle:],
      max_tokens,
      render,
      count,
      project_metadata,
      volumes,
    )
  }
}

///|
/// Partition by complete files and sections using exact rendered counts.
///
/// Callbacks must be deterministic. Metadata projection receives original input
/// indices, including on the empty template and on rejected candidates. Each
/// candidate is counted as a whole; an oversized candidate is halved by atom
/// count, without assuming additive or monotonic token counts.
///
/// ```mbt check
/// test {
///   let result = @partition.partition(
///     @document.create([]),
///     3,
///     render=_ => "ctx",
///     count=text => text.length(),
///     project_metadata=(_, _) => Json::null(),
///   )
///   assert_eq(result.volumes[0].id, "part-0001")
///   assert_eq(result.volumes[0].text, "ctx")
///   assert_eq(result.volumes[0].tokens, 3)
/// }
/// ```
pub fn partition(
  document : @document.Document,
  max_tokens : Int32,
  render~ : (@document.Document) -> String raise,
  count~ : (String) -> Int32 raise,
  project_metadata~ : (Array[Int32], Array[Int32]) -> Json raise,
) -> Partition raise {
  if max_tokens <= 0 {
    raise InvalidCap(max_tokens)
  }
  if document.files.length().to_int64() + document.sections.length().to_int64() >
    2147483647L {
    raise Overflow("atom count")
  }
  // Validate before compare_path allocates UTF-8 encodings.
  for file in document.files {
    ignore(byte_length(file.path))
  }
  let sorted = Array::makei(document.files.length(), i => i)
  sorted.sort_by((a, b) => {
    @document.compare_path(document.files[a].path, document.files[b].path)
  })
  for i in 1..<sorted.length() {
    let path = document.files[sorted[i]].path
    if path == document.files[sorted[i - 1]].path {
      raise DuplicatePath(path)
    }
  }
  let (template, _, _) = make_candidate(document, [], project_metadata)
  let template_text = render(template)
  let template_bytes = byte_length(template_text)
  let template_tokens = checked_count(template_text, count)
  if template_tokens > max_tokens {
    raise TemplateTooLarge(template_tokens)
  }
  let atoms : Array[Atom] = sorted.map(i => File(i))
  for i in 0..<document.sections.length() {
    atoms.push(Section(i))
  }
  let volumes : Array[Volume] = []
  if atoms.is_empty() {
    volumes.push({
      id: volume_id(1),
      document: template,
      text: template_text,
      tokens: template_tokens,
      bytes: template_bytes,
      file_indices: [],
      section_indices: [],
    })
  } else {
    split_candidate(
      document,
      atoms[:],
      max_tokens,
      render,
      count,
      project_metadata,
      volumes,
    )
  }
  let index = make_index(document, volumes)
  let index_text = index.stringify() + "\n"
  ignore(byte_length(index_text))
  let index_tokens = checked_count(index_text, count)
  let mut total_tokens = index_tokens.to_int64()
  for volume in volumes {
    total_tokens = add_tokens(total_tokens, volume.tokens)
  }
  { volumes, index, index_text, index_tokens, total_tokens, }
}
