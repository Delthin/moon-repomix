///|
fn make_index(original : @document.Document, volumes : Array[Volume]) -> Json {
  let summaries : Array[Json] = []
  let files : Map[String, Json] = Map([])
  let sections : Map[String, Json] = Map([])
  for volume in volumes {
    summaries.push({
      "id": volume.id,
      "tokens": volume.tokens,
      "bytes": volume.bytes,
      "fileIndices": volume.file_indices,
      "sectionIndices": volume.section_indices,
    })
    for i in volume.file_indices {
      files[original.files[i].path] = Json::string(volume.id)
    }
    for i in volume.section_indices {
      sections[i.to_string()] = Json::string(volume.id)
    }
  }
  {
    "schemaVersion": 1,
    "volumes": summaries,
    "files": files,
    "sections": sections,
    "metadata": original.metadata,
  }
}
