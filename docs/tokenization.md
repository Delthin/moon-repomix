# o200k_base tokenization

`delthin/moon_repomix/metrics` is a native, offline encoder for **o200k_base**,
matching **tiktoken 0.14.0 `encode_ordinary`**. Special-token spellings (including
`<|endoftext|>` and `<|endofprompt|>`) are ordinary text, never special IDs.
Text is not normalized. Input is a Unicode string; preprocessing/UTF-8 decoding
belongs to the caller.

## API and resource layout

```moonbit
pub async fn Encoder::load(path : String) -> Encoder
pub fn Encoder::encode(self : Encoder, text : String) -> Array[Int]
pub fn Encoder::count(self : Encoder, text : String) -> Int
```

`load` has MoonBit's implicit async `raise` effect. Pass an **absolute ranks
filename**, with this sibling layout:

```text
<resource-directory>/
  tokenizer-o200k_base.tiktoken
  tokenizer-unicode-16.0.0.txt
  LICENSES/
    tokenizer-tiktoken-MIT.txt
    tokenizer-Unicode.txt
    tokenizer-tokenizers-moonbit-Apache-2.0.txt
    tokenizer-Apache-2.0.txt
```

Both runtime files are checked against compiled-in SHA-256 digests **before
parsing**. Wrong digests and relative paths raise `ResourceError(String)`;
filesystem/decoding errors and async cancellation propagate without fallback or
retry. No file/network I/O occurs during `encode`/`count`. After loading,
instances are reusable and encoding does not mutate shared state.

The library does not search cwd, infer the executable location, or download
missing files. CLI integration must resolve its installed resource directory
and pass the absolute ranks filename. A missing/damaged resource is a failure,
not an estimate or an empty count.

The packaging helper copies and verifies the two runtime resources and copies
the redistribution notices. It deliberately does not build/install a CLI or
choose the CLI's layout:

```sh
moon run scripts/tokenizer-install-assets.mbtx --target native /absolute/repo /absolute/package/share/moon-repomix
```

Invoke it during packaging; a native executable alone is **not** a complete
installation. Re-running overwrites these named files; it does not remove other
files. `moon build` alone does not copy assets. `tokenizer-cases.json` and
`tokenizer-golden.json` are development fixtures, not runtime resources.

Count the **complete final rendered document once** for its total. Counts for
separate bodies/fragments cannot replace that total, because BPE and
pre-tokenization boundaries can change when text is concatenated. `count` uses
the same encoder as `encode` and currently allocates the ID array internally.

## Implementation choice

Evaluated `howtomakeaname/tokenizers-moonbit@0.16.3` before adapting it. Its native
BPE core already provides linked symbols, a priority queue, stale-merge
invalidation, and leftmost tie-breaking. Its public model is not directly an
OpenAI ranks encoder: it expects HF pair-merges, string vocabulary, and a
byte-to-character mapping; its generic o200k pre-tokenizer also approximates
Unicode categories and splits `Привет мир` character-by-character.

We vendor only that BPE core in `src/metrics/bpe.mbt` (Apache-2.0), rather than
pulling in the general tokenizer, JSON models, trainers, dropout, cache, or
extra byte mapping. Local changes use original UTF-8 byte spans and direct
`Map[Bytes, Int]` OpenAI ranks, and invalidate heap entries using span endpoints
and links. Lower rank wins; equal ranks merge the leftmost pair first. All
returned IDs are original OpenAI ranks. This is a project-specific metrics
adapter, not another general tokenizer library.

`src/metrics/pretokenize.mbt` implements the **ordered** alternatives of the
reference o200k regex, including greedy/backtracking behavior, contractions,
Unicode whitespace, CR/LF, and the three-number limit. It never approximates
categories with case conversion or locale APIs. Categories Lu/Ll/Lt/Lm/Lo/M/N
are loaded from the full Unicode data, including supplementary planes. `M`
includes Mn/Mc/Me; `N` includes Nd/Nl/No. Case-insensitive contractions include
long s (`ſ`), as in the reference. White_Space is the fixed Unicode property,
not an ASCII-only or host-language whitespace predicate.

The category version is **Unicode 16.0.0**, not the latest Unicode release:
tiktoken 0.14.0 declares `fancy-regex 0.19.0` and `regex 1.13.1`; regex 1.13.1's
[generated categories](https://github.com/rust-lang/regex/blob/1.13.1/regex-syntax/src/unicode_tables/general_category.rs)
and [White_Space](https://github.com/rust-lang/regex/blob/1.13.1/regex-syntax/src/unicode_tables/perl_space.rs)
use Unicode 16.0.0. The successful wheel-based ID comparison also checks this
choice against the released reference implementation.

## Sources, versions, hashes, licenses

Runtime resources are unmodified public upstream files, committed into this
repository (not fetched on first use).

| Local resource | Version/source | SHA-256 | Redistribution notice |
| --- | --- | --- | --- |
| `assets/tokenizer-o200k_base.tiktoken` | [OpenAI ranks](https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken), pinned by [tiktoken 0.14.0](https://github.com/openai/tiktoken/blob/0.14.0/tiktoken_ext/openai_public.py) | `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d` | OpenAI tiktoken MIT; `LICENSES/tokenizer-tiktoken-MIT.txt` |
| `assets/tokenizer-unicode-16.0.0.txt` | [Unicode 16.0.0 DerivedGeneralCategory](https://www.unicode.org/Public/16.0.0/ucd/extracted/DerivedGeneralCategory.txt) | `7676ab755a41ef82108460238569e60ad65c191ddafe61b36c6765ec1353f293` | Unicode License V3; `LICENSES/tokenizer-Unicode.txt` |
| `assets/tokenizer-golden.json` | tiktoken **0.14.0**, independently generated full IDs using `encode_ordinary` | `30d5225ce77d01f3a68d1cb2fc3ebd41a7f9cb9b48829103a78bdf59f6356f03` | Project fixtures; reference MIT notice retained |

Vendored source: [tokenizers-moonbit](https://github.com/howtomakeaname/tokenizers-moonbit),
Mooncakes release **0.16.3**, original `src/model/bpe.mbt` SHA-256
`00d3af2b82559086cbdb2ab7a82e6634381df04fe481ee25eeb2cf5fd13c072a`.
The original release notice is retained in
`LICENSES/tokenizer-tokenizers-moonbit-Apache-2.0.txt`, alongside the complete
Apache-2.0 text in `LICENSES/tokenizer-Apache-2.0.txt`. Adaptations are described
above and in the source header. The pre-tokenizer follows the
[tiktoken 0.14.0 definition](https://github.com/openai/tiktoken/blob/0.14.0/tiktoken_ext/openai_public.py)
under MIT. Unicode's [notice](https://www.unicode.org/license.txt) is retained
alongside the data. Direct product dependency added here:
`moonbitlang/x@0.5.5` (Apache-2.0), for SHA-256 and portable path operations;
filesystem I/O uses the project's `moonbitlang/async@0.19.2`.

## Validation and reproducing the golden

Two aggregated black-box tests cover:

- **104 complete ID sequences**, including the exact `Привет мир` regression,
  multilingual/case-overlap text, all requested categories, combining marks,
  supplementary characters, Unicode 16 additions, unassigned code points,
  emoji/ZWJ, all whitespace ranges, numbers, contractions, controls, special
  spellings, source code, XML/Markdown wrapping, and concatenation boundaries;
- **16,390 probes** on and next to every Unicode category range boundary,
  surrounded by cased letters/punctuation; eight seeded 2,048-scalar mixed
  cases; 4,096 spaces, an 8,192-byte BPE piece, and long newline sequences;
- repeated encoder use, non-additive fragment counts, absolute-path rejection,
  both checksum failures, missing-file error propagation, relocated resources,
  and initialization cancellation.

Expected IDs come from the released tiktoken wheel, not the MoonBit encoder or
a copy of its algorithm. `scripts/tokenizer-golden.mbtx` uses the existing
Python Fire CLI only as a public-API command bridge. It asserts the reference
version and calls `tiktoken.get_encoding("o200k_base").encode_ordinary`.
No custom Python/JS/shell program computes expectations. Development-only
reference tools are isolated from the product:

```sh
uv pip install --python 3.12 --target /absolute/reference tiktoken==0.14.0 fire==0.7.1
mkdir -p /absolute/reference/cache
cp assets/tokenizer-o200k_base.tiktoken /absolute/reference/cache/fb374d419588a4632f3f557e76b4b70aebbca790
moon run scripts/tokenizer-golden.mbtx --target native /absolute/repo /absolute/python3.12 /absolute/reference
moon test src/metrics --target native
moon check src/metrics --target native
moon fmt src/metrics scripts/tokenizer-golden.mbtx scripts/tokenizer-install-assets.mbtx --check
moon info src/metrics --target native
```

The cache key above is tiktoken's SHA-1 of the public ranks URL, not a security
hash; tiktoken and this library independently validate the SHA-256. The cached
file keeps golden generation offline after tooling setup. For tests launched
from another cwd, set `TOKENIZER_ASSETS` to the absolute fixture directory.
The loader itself needs only its absolute ranks path, not this test variable.

The reference fixtures target MoonBit `moonc v0.10.15+943464bfa`.
Standalone `.mbtx` helpers resolve their own dependencies; product tests use
those pinned in `moon.mod`. The native CI matrix also exercises installed
resources and extracted distributions from an unrelated working directory.
