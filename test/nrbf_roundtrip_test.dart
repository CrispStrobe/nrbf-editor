import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nrbf_editor/nrbf/nrbf.dart';

/// Encoder/decoder round-trip fidelity — the property a save *editor* lives or
/// dies by: loading a file (decode) and saving it back (encode) must not corrupt
/// it. The encoder normalises the header's HeaderId to -1 (the spec-standard
/// value real .NET BinaryFormatter output already uses), so a first pass may
/// differ there; but the pipeline is otherwise faithful and, crucially, a
/// *fixed point* — once encoded, re-encoding is byte-identical.
void main() {
  Uint8List i32(int v) =>
      Uint8List(4)..buffer.asByteData().setInt32(0, v, Endian.little);

  Uint8List reencode(Uint8List bytes) {
    final decoder = NrbfDecoder(bytes);
    final record = decoder.decode();
    return NrbfEncoder().encode(record, decoder: decoder);
  }

  test('encode(decode(bytes)) re-decodes and is a byte-stable fixed point', () {
    final header = <int>[0x00, ...i32(1), ...i32(0), ...i32(1), ...i32(0)];
    final samples = <String, List<int>>{
      'string': [...header, 0x06, ...i32(1), 0x02, 0x48, 0x69, 0x0B],
      'object-array with a null': [
        ...header,
        16,
        ...i32(1),
        ...i32(1),
        10,
        0x0B
      ],
    };
    samples.forEach((name, seed) {
      final once = reencode(Uint8List.fromList(seed));
      // The re-encoded bytes must decode again (a valid file, not corrupt).
      expect(() => NrbfDecoder(once).decode(), returnsNormally,
          reason: '$name did not re-decode');
      // ...and encoding is idempotent: a second pass is byte-identical.
      final twice = reencode(once);
      expect(twice, once, reason: '$name is not a byte-stable fixed point');
    });
  });

  test('a System.Guid class record round-trips through encode + decode', () {
    const guidStr = '12345678-1234-5678-9abc-def012345678';
    final guid = ClassRecord.createGuidRecord(1, guidStr);

    // Encode the freshly-built record, decode it back, and re-encode.
    final enc1 = NrbfEncoder().encode(guid);
    final decoder = NrbfDecoder(enc1);
    final back = decoder.decode();
    expect(back, isA<ClassRecord>());
    expect(ClassRecord.reconstructGuid(back as ClassRecord), guidStr);

    final enc2 = NrbfEncoder().encode(back, decoder: decoder);
    expect(enc2, enc1, reason: 'class-record encode is not a fixed point');
  });
}
