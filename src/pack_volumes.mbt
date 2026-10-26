///|
/// Prepare one immutable context, then split it at file/section boundaries.
/// max_tokens bounds every complete rendered volume; index_tokens is separate.
/// Options.token_budget is the single-document pack budget and is not applied here.
/// Returned strings are the exact strings counted; this function writes no files.
pub async fn pack_volumes(
  options : Options,
  runtime : Runtime,
  max_tokens~ : Int32,
) -> VolumePackResult {
  if max_tokens <= 0 {
    raise @partition.PartitionError::InvalidCap(max_tokens)
  }
  let prepared = prepare_pack(options, runtime)
  let metadata = volume_metadata(prepared.document)
  @async.sleep(0)
  let partition = @partition.partition(
    prepared.document,
    max_tokens,
    render=document => {
      render_document(
        document,
        options.style,
        options.full_metadata,
        prepared.display,
      )
    },
    count=text => prepared.counter.count(text),
    project_metadata=(files, sections) => metadata.project(files, sections),
  )
  let (partition, file_names) = volume_names(partition, options.style, runtime)
  // A timeout/cancellation delivered during CPU work must not return success.
  @async.sleep(0)
  {
    partition,
    file_names,
    files: prepared.files,
    skipped: prepared.skipped,
    findings: prepared.findings,
    security: prepared.security,
  }
}
