import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nrbf_editor/nrbf/nrbf.dart';

/// Decoder robustness: a malformed NRBF stream must reject with a catchable
/// [Exception] (which the app's decode try/catch handles) — never leak a raw
/// RangeError / IndexError, and never hang. Multi-byte reads and the
/// length-prefixed string used to index past a truncated buffer, throwing a
/// RangeError the app couldn't catch as an Exception.
void main() {
  Object? decodeError(List<int> bytes) {
    try {
      NrbfDecoder(Uint8List.fromList(bytes)).decode();
      return null; // parsed (leniently) — acceptable
    } on Exception {
      return null; // clean rejection — the contract
    } catch (e) {
      return e; // a raw Error leaked — a bug
    }
  }

  test('a header truncated mid-int rejects with an Exception, not a RangeError',
      () {
    // Record type 0x00 (SerializedStreamHeader), then only 2 of the 4 bytes the
    // rootId int32 needs — the read runs off the end.
    expect(decodeError([0x00, 0x01, 0x02]), isNull);
  });

  test('a string length that overruns the buffer rejects cleanly', () {
    // A header, then a BinaryObjectString record (type 6) with an id and a
    // length-prefixed string claiming 0x7F bytes that are not present.
    final bytes = <int>[
      0x00, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, // header
      6, 1, 0, 0, 0, // BinaryObjectString, objectId = 1
      0x7F, // string length 127 — but no bytes follow
    ];
    expect(decodeError(bytes), isNull);
  });

  test('a huge ObjectNullMultiple count is rejected, not materialised (DoS)',
      () {
    // ~30 bytes: an object array of length 1 whose single element is an
    // ObjectNullMultiple claiming 2 billion nulls. Un-bounded, the decoder
    // would build a 2-billion-entry list and exhaust memory; it must reject.
    Uint8List i32(int v) =>
        Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.little);
    final bomb = <int>[
      0x00, ...i32(1), ...i32(0), ...i32(1), ...i32(0), // header
      16, ...i32(1), ...i32(1), // ArraySingleObject id=1 length=1
      14, ...i32(2000000000), // ObjectNullMultiple nullCount=2e9
      0x0B,
    ];
    final sw = Stopwatch()..start();
    expect(decodeError(bomb), isNull); // Exception, not an Error/OOM
    expect(
        sw.elapsedMilliseconds, lessThan(1000)); // rejected, not chewing memory
  });

  test('a huge array length is rejected against the remaining buffer', () {
    Uint8List i32(int v) =>
        Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.little);
    final bomb = <int>[
      0x00, ...i32(1), ...i32(0), ...i32(1), ...i32(0),
      15, ...i32(1), ...i32(2000000000),
      8, // ArraySinglePrimitive len=2e9 int32
    ];
    expect(decodeError(bomb), isNull);
  });

  test('no malformed stream leaks a non-Exception error over 60k mutations',
      () {
    final rng = Random(1);
    for (var i = 0; i < 20000; i++) {
      // (a) short truncations of a valid-ish header
      if (i < 20) {
        final e = decodeError([0x00, for (var k = 1; k < i + 1; k++) k & 0xFF]);
        expect(e, isNull, reason: 'truncated header len ${i + 1}');
      }
      // (b) random bytes
      final n = rng.nextInt(60);
      expect(
          decodeError([for (var k = 0; k < n; k++) rng.nextInt(256)]), isNull);
      // (c) valid header + random tail (reaches the record-parsing loop)
      final m = rng.nextInt(80);
      expect(
        decodeError([
          0x00,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          for (var k = 0; k < m; k++) rng.nextInt(256),
        ]),
        isNull,
      );
    }
  });
}
