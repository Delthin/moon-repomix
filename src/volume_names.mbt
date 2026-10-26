///|
/// Add storage names to the root SDK index, then count the final index exactly.
/// Volume strings are unchanged; no file I/O occurs here.
fn volume_names(
  partition : Partition,
  style : Style,
  counter : @metrics.CountSession,
) -> (Partition, Map[String, String]) raise {
  let extension = match style {
    Xml => ".xml"
    Markdown => ".md"
    Json => ".json"
    Plain => ".txt"
  }
  let names : Map[String, String] = Map([])
  for volume in partition.volumes {
    names[volume.id] = volume.id + extension
  }
  guard partition.index is Object(fields) else { raise ConfigurationError }
  guard fields.get("volumes") is Some(Array(rows)) else {
    raise ConfigurationError
  }
  let named_rows : Array[Json] = []
  for row in rows {
    guard row is Object(values) else { raise ConfigurationError }
    guard row is { "id": String(id), .. } else { raise ConfigurationError }
    guard names.get(id) is Some(name) else { raise ConfigurationError }
    let named = values.copy()
    named["fileName"] = Json(name)
    named_rows.push(Json(named))
  }
  let index_fields = fields.copy()
  index_fields["volumes"] = Json(named_rows)
  let index = Json(index_fields)
  let named = partition.with_index(index, count=text => counter.count(text))
  (named, names)
}
