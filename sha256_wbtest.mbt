// FIPS 180-4 test vectors plus a multi-byte UTF-8 input cross-checked with
// Python's hashlib.

///|
test "sha256 vectors" {
  assert_eq(
    digest(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    digest("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  assert_eq(
    digest("The quick brown fox jumps over the lazy dog"),
    "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
  )
  assert_eq(
    digest("键 é"),
    "061b8f9d813476a98c8990cbdd550ce0926d06f1de76bf26c93d68355e62f871",
  )
  // 55, 56 and 64 bytes exercise the padding boundaries around one block.
  assert_eq(
    digest("a".repeat(55)),
    "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
  )
  assert_eq(
    digest("a".repeat(56)),
    "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
  )
  assert_eq(
    digest("a".repeat(64)),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
  )
  assert_eq(
    digest("a".repeat(1000000)),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}
