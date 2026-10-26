///|
/// Immutable text and disk-byte facts obtained by strict UTF-8 decoding.
/// Private fields prevent attaching this validation to a different String.
struct Text {
  text : String
  disk_bytes : Int32
  bom_bytes : Int32
}

///|
/// Decode an entire UTF-8 snapshot, stripping exactly one leading UTF-8 BOM.
/// Noncharacters, CR/LF and any further BOMs are preserved.
pub fn decode(bytes : Bytes) -> Text raise {
  let bom = if bytes is [0xef, 0xbb, 0xbf, ..] { 3 } else { 0 }
  let text = @utf8.decode(bytes[bom:], ignore_bom=false)
  { text, disk_bytes: bytes.length(), bom_bytes: bom, }
}

///|
pub fn Text::text(self : Text) -> String {
  self.text
}

///|
pub fn Text::disk_bytes(self : Text) -> Int32 {
  self.disk_bytes
}

///|
pub fn Text::bom_bytes(self : Text) -> Int32 {
  self.bom_bytes
}
