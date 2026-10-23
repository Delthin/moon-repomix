///|
priv enum Frame {
  End
  Line(Bytes)
  TooLong
}

///|
priv struct Framer {
  input : &@io.Reader
  limit : Int32
  mut chunk : Bytes
  mut offset : Int32
}

///|
// Never use read_until/read_all for untrusted stdin: both can allocate before
// checking the host limit. Oversize frames are discarded in bounded chunks.
async fn Framer::next(self : Framer) -> Frame {
  let line = @buffer.Buffer(size_hint=256)
  let mut too_long = false
  for ;; {
    if self.offset == self.chunk.length() {
      match self.input.read_some(max_len=4096) {
        None => return End // EOF drops any unterminated frame.
        Some(chunk) => {
          self.chunk = chunk
          self.offset = 0
        }
      }
    }
    let byte = self.chunk[self.offset]
    self.offset += 1
    if byte == b'\n' {
      return if too_long { TooLong } else { Line(line.to_bytes()) }
    }
    if !too_long {
      if line.length() == self.limit {
        too_long = true
        line.reset()
      } else {
        line.write_byte(byte)
      }
    }
  }
}

///|
fn parse_frame(bytes : Bytes) -> Json? {
  Some(@json.parse(@utf8.decode(bytes))) catch {
    _ => None
  }
}
