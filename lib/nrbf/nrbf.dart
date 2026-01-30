// lib/nrbf/nrbf.dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;

// ============================================================================
// ENUMS
// ============================================================================

enum RecordType {
  serializedStreamHeader(0),
  classWithId(1),
  systemClassWithMembers(2),
  classWithMembers(3),
  systemClassWithMembersAndTypes(4),
  classWithMembersAndTypes(5),
  binaryObjectString(6),
  binaryArray(7),
  memberPrimitiveTyped(8),
  memberReference(9),
  objectNull(10),
  messageEnd(11),
  binaryLibrary(12),
  objectNullMultiple256(13),
  objectNullMultiple(14),
  arraySinglePrimitive(15),
  arraySingleObject(16),
  arraySingleString(17);

  final int value;
  const RecordType(this.value);

  static RecordType fromValue(int value) {
    return RecordType.values.firstWhere((e) => e.value == value,
        orElse: () => throw Exception('Invalid RecordType value: $value'));
  }
}

enum BinaryType {
  primitive(0),
  string(1),
  object(2),
  systemClass(3),
  classType(4),
  objectArray(5),
  stringArray(6),
  primitiveArray(7);

  final int value;
  const BinaryType(this.value);

  static BinaryType fromValue(int value) {
    return BinaryType.values.firstWhere((e) => e.value == value,
        orElse: () => throw Exception('Invalid BinaryType value: $value'));
  }
}

enum PrimitiveType {
  boolean(1),
  byte(2),
  char(3),
  decimal(5),
  double(6),
  int16(7),
  int32(8),
  int64(9),
  sByte(10),
  single(11),
  timeSpan(12),
  dateTime(13),
  uInt16(14),
  uInt32(15),
  uInt64(16),
  nullType(17),
  string(18);

  final int value;
  const PrimitiveType(this.value);

  static PrimitiveType fromValue(int value) {
    return PrimitiveType.values.firstWhere((e) => e.value == value,
        orElse: () => throw Exception('Invalid PrimitiveType value: $value'));
  }
}

enum BinaryArrayType {
  single(0),
  jagged(1),
  rectangular(2),
  singleOffset(3),
  jaggedOffset(4),
  rectangularOffset(5);

  final int value;
  const BinaryArrayType(this.value);

  static BinaryArrayType fromValue(int value) {
    return BinaryArrayType.values.firstWhere((e) => e.value == value,
        orElse: () => throw Exception('Invalid BinaryArrayType value: $value'));
  }
}

// ============================================================================
// TYPE INFO CLASSES
// ============================================================================

abstract class AdditionalTypeInfo {
  const AdditionalTypeInfo();
}

class PrimitiveTypeInfo extends AdditionalTypeInfo {
  final PrimitiveType primitiveType;
  const PrimitiveTypeInfo(this.primitiveType);
}

class SystemClassTypeInfo extends AdditionalTypeInfo {
  final String className;
  const SystemClassTypeInfo(this.className);
}

class ClassTypeInfo extends AdditionalTypeInfo {
  final String className;
  final int libraryId;
  const ClassTypeInfo(this.className, this.libraryId);
}

class NoneTypeInfo extends AdditionalTypeInfo {
  const NoneTypeInfo();
}

class MemberTypeInfo {
  final List<BinaryType> binaryTypes;
  final List<AdditionalTypeInfo> additionalInfos;

  MemberTypeInfo(this.binaryTypes, this.additionalInfos);
}

class ClassInfo {
  final int objectId;
  final String name;
  final int memberCount;
  final List<String> memberNames;

  ClassInfo(this.objectId, this.name, this.memberCount, this.memberNames);
}

// ============================================================================
// RECORD CLASSES
// ============================================================================

abstract class NrbfRecord {
  RecordType get recordType;
  int? get objectId;
}

class SerializationHeader extends NrbfRecord {
  final int rootId;
  final int headerId;
  final int majorVersion;
  final int minorVersion;

  SerializationHeader(
      this.rootId, this.headerId, this.majorVersion, this.minorVersion);

  @override
  RecordType get recordType => RecordType.serializedStreamHeader;

  @override
  int? get objectId => null;
}

class BinaryLibrary extends NrbfRecord {
  final int libraryId;
  final String libraryName;

  BinaryLibrary(this.libraryId, this.libraryName);

  @override
  RecordType get recordType => RecordType.binaryLibrary;

  @override
  int? get objectId => libraryId;
}

class ClassRecord extends NrbfRecord {
  final ClassInfo classInfo;
  final MemberTypeInfo? memberTypeInfo;
  final int? libraryId;
  final RecordType recordTypeValue;
  final int? metadataId;
  final Map<String, dynamic> memberValues = {};

  ClassRecord(
    this.classInfo,
    this.memberTypeInfo,
    this.libraryId,
    this.recordTypeValue, {
    this.metadataId,
  });

  @override
  RecordType get recordType => recordTypeValue;

  @override
  int? get objectId => classInfo.objectId;

  String get typeName => classInfo.name;
  List<String> get memberNames => classInfo.memberNames;

  dynamic getValue(String memberName) => memberValues[memberName];

  void setValue(String memberName, dynamic value) {
    if (!classInfo.memberNames.contains(memberName)) {
      throw Exception(
          'Member "$memberName" does not exist in class "${classInfo.name}"');
    }
    memberValues[memberName] = value;
  }

  static String reconstructGuid(ClassRecord guidRecord) {
    final a = guidRecord.getValue('_a') as int;
    final b = guidRecord.getValue('_b') as int;
    final c = guidRecord.getValue('_c') as int;
    final d = guidRecord.getValue('_d') as int;
    final e = guidRecord.getValue('_e') as int;
    final f = guidRecord.getValue('_f') as int;
    final g = guidRecord.getValue('_g') as int;
    final h = guidRecord.getValue('_h') as int;
    final i = guidRecord.getValue('_i') as int;
    final j = guidRecord.getValue('_j') as int;
    final k = guidRecord.getValue('_k') as int;

    final bytes = Uint8List.fromList([
      a & 0xFF,
      (a >> 8) & 0xFF,
      (a >> 16) & 0xFF,
      (a >> 24) & 0xFF,
      b & 0xFF,
      (b >> 8) & 0xFF,
      c & 0xFF,
      (c >> 8) & 0xFF,
      d,
      e,
      f,
      g,
      h,
      i,
      j,
      k
    ]);

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static ClassRecord createGuidRecord(int objectId, String guidString) {
    final hex = guidString.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }

    final classInfo = ClassInfo(
      objectId,
      'System.Guid',
      11,
      ['_a', '_b', '_c', '_d', '_e', '_f', '_g', '_h', '_i', '_j', '_k'],
    );

    final memberTypeInfo = MemberTypeInfo(
      List.filled(11, BinaryType.primitive),
      [
        const PrimitiveTypeInfo(PrimitiveType.int32),
        const PrimitiveTypeInfo(PrimitiveType.int16),
        const PrimitiveTypeInfo(PrimitiveType.int16),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
        const PrimitiveTypeInfo(PrimitiveType.byte),
      ],
    );

    final record = ClassRecord(
      classInfo,
      memberTypeInfo,
      null,
      RecordType.systemClassWithMembersAndTypes,
    );

    final view = ByteData.sublistView(bytes);
    record.setValue('_a', view.getInt32(0, Endian.little));
    record.setValue('_b', view.getInt16(4, Endian.little));
    record.setValue('_c', view.getInt16(6, Endian.little));
    record.setValue('_d', bytes[8]);
    record.setValue('_e', bytes[9]);
    record.setValue('_f', bytes[10]);
    record.setValue('_g', bytes[11]);
    record.setValue('_h', bytes[12]);
    record.setValue('_i', bytes[13]);
    record.setValue('_j', bytes[14]);
    record.setValue('_k', bytes[15]);

    return record;
  }
}

class BinaryArrayRecord extends NrbfRecord {
  final int arrayObjectId;
  final BinaryArrayType binaryArrayTypeEnum;
  final int rank;
  final List<int> lengths;
  final List<int>? lowerBounds;
  final BinaryType typeEnum;
  final AdditionalTypeInfo additionalTypeInfo;
  final List<dynamic> elementValues;

  BinaryArrayRecord(
    this.arrayObjectId,
    this.binaryArrayTypeEnum,
    this.rank,
    this.lengths,
    this.lowerBounds,
    this.typeEnum,
    this.additionalTypeInfo,
    this.elementValues,
  );

  @override
  RecordType get recordType => RecordType.binaryArray;

  @override
  int? get objectId => arrayObjectId;

  List<dynamic> getArray() => elementValues;

  int getTotalLength() => lengths.reduce((a, b) => a * b);
}

class ArraySinglePrimitiveRecord extends NrbfRecord {
  final int arrayObjectId;
  final int length;
  final PrimitiveType primitiveTypeEnum;
  final List<dynamic> elementValues;

  ArraySinglePrimitiveRecord(
    this.arrayObjectId,
    this.length,
    this.primitiveTypeEnum,
    this.elementValues,
  );

  @override
  RecordType get recordType => RecordType.arraySinglePrimitive;

  @override
  int? get objectId => arrayObjectId;

  List<dynamic> getArray() => elementValues;
}

class ArraySingleObjectRecord extends NrbfRecord {
  final int arrayObjectId;
  final int length;
  final List<dynamic> elementValues;

  ArraySingleObjectRecord(
      this.arrayObjectId, this.length, this.elementValues);

  @override
  RecordType get recordType => RecordType.arraySingleObject;

  @override
  int? get objectId => arrayObjectId;

  List<dynamic> getArray() => elementValues;
}

class ArraySingleStringRecord extends NrbfRecord {
  final int arrayObjectId;
  final int length;
  final List<dynamic> elementValues;

  ArraySingleStringRecord(
      this.arrayObjectId, this.length, this.elementValues);

  @override
  RecordType get recordType => RecordType.arraySingleString;

  @override
  int? get objectId => arrayObjectId;

  List<dynamic> getArray() => elementValues;
}

class BinaryObjectStringRecord extends NrbfRecord {
  final int stringObjectId;
  final String value;

  BinaryObjectStringRecord(this.stringObjectId, this.value);

  @override
  RecordType get recordType => RecordType.binaryObjectString;

  @override
  int? get objectId => stringObjectId;
}

class MemberPrimitiveTypedRecord extends NrbfRecord {
  final PrimitiveType primitiveTypeEnum;
  final dynamic value;

  MemberPrimitiveTypedRecord(this.primitiveTypeEnum, this.value);

  @override
  RecordType get recordType => RecordType.memberPrimitiveTyped;

  @override
  int? get objectId => null;
}

class MemberReferenceRecord extends NrbfRecord {
  final int idRef;

  MemberReferenceRecord(this.idRef);

  @override
  RecordType get recordType => RecordType.memberReference;

  @override
  int? get objectId => null;
}

class ObjectNullRecord extends NrbfRecord {
  static final instance = ObjectNullRecord._internal();
  ObjectNullRecord._internal();

  factory ObjectNullRecord() => instance;

  @override
  RecordType get recordType => RecordType.objectNull;

  @override
  int? get objectId => null;
}

class ObjectNullMultipleRecord extends NrbfRecord {
  final int nullCount;

  ObjectNullMultipleRecord(this.nullCount);

  @override
  RecordType get recordType => RecordType.objectNullMultiple;

  @override
  int? get objectId => null;
}

class ObjectNullMultiple256Record extends NrbfRecord {
  final int nullCount;

  ObjectNullMultiple256Record(this.nullCount);

  @override
  RecordType get recordType => RecordType.objectNullMultiple256;

  @override
  int? get objectId => null;
}

class MessageEndRecord extends NrbfRecord {
  static final instance = MessageEndRecord._internal();
  MessageEndRecord._internal();

  factory MessageEndRecord() => instance;

  @override
  RecordType get recordType => RecordType.messageEnd;

  @override
  int? get objectId => null;
}

// ============================================================================
// BINARY READER
// ============================================================================

class BinaryReader {
  final ByteData _data;
  int _position = 0;

  BinaryReader(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  int get position => _position;
  int get remaining => _data.lengthInBytes - _position;
  bool get hasMore => _position < _data.lengthInBytes;

  int readByte() {
    if (_position >= _data.lengthInBytes) {
      throw Exception('Attempted to read beyond end of buffer');
    }
    return _data.getUint8(_position++);
  }

  int readSByte() {
    if (_position >= _data.lengthInBytes) {
      throw Exception('Attempted to read beyond end of buffer');
    }
    return _data.getInt8(_position++);
  }

  int readInt16() {
    final value = _data.getInt16(_position, Endian.little);
    _position += 2;
    return value;
  }

  int readUInt16() {
    final value = _data.getUint16(_position, Endian.little);
    _position += 2;
    return value;
  }

  int readInt32() {
    final value = _data.getInt32(_position, Endian.little);
    _position += 4;
    return value;
  }

  int readUInt32() {
    final value = _data.getUint32(_position, Endian.little);
    _position += 4;
    return value;
  }

  int readInt64() {
    final value = _data.getInt64(_position, Endian.little);
    _position += 8;
    return value;
  }

  int readUInt64() {
    final value = _data.getUint64(_position, Endian.little);
    _position += 8;
    return value;
  }

  double readSingle() {
    final value = _data.getFloat32(_position, Endian.little);
    _position += 4;
    return value;
  }

  double readDouble() {
    final value = _data.getFloat64(_position, Endian.little);
    _position += 8;
    return value;
  }

  bool readBoolean() {
    return readByte() != 0;
  }

  String readChar() {
    final byte = readByte();
    return String.fromCharCode(byte);
  }

  int readDateTime() {
    return readUInt64();
  }

  int readTimeSpan() {
    return readInt64();
  }

  String readDecimal() {
    final bytes = List.generate(16, (_) => readByte());
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  int readVariableLengthInt() {
    int value = 0;
    int shift = 0;

    while (shift < 35) {
      final b = readByte();
      value |= (b & 0x7F) << shift;

      if ((b & 0x80) == 0) {
        return value;
      }

      shift += 7;
    }

    throw Exception('Variable length int too long');
  }

  String readLengthPrefixedString() {
    final length = readVariableLengthInt();

    if (length == 0) return '';

    if (length < 0) {
      throw Exception('Invalid string length');
    }

    final startPos = _position;
    final bytes = Uint8List.view(_data.buffer, _data.offsetInBytes + startPos, length);
    _position += length;

    return utf8.decode(bytes);
  }
}

// ============================================================================
// BINARY WRITER
// ============================================================================

class BinaryWriter {
  final List<int> _bytes = [];

  Uint8List toBytes() => Uint8List.fromList(_bytes);

  void writeByte(int value) {
    _bytes.add(value & 0xFF);
  }

  void writeSByte(int value) {
    final signed = value < 0 ? value + 256 : value;
    _bytes.add(signed & 0xFF);
  }

  void writeInt16(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
  }

  void writeUInt16(int value) {
    writeInt16(value);
  }

  void writeInt32(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
    _bytes.add((value >> 16) & 0xFF);
    _bytes.add((value >> 24) & 0xFF);
  }

  void writeUInt32(int value) {
    writeInt32(value);
  }

  void writeInt64(int value) {
    for (int i = 0; i < 8; i++) {
      _bytes.add((value >> (i * 8)) & 0xFF);
    }
  }

  void writeUInt64(int value) {
    writeInt64(value);
  }

  void writeSingle(double value) {
    final data = ByteData(4);
    data.setFloat32(0, value, Endian.little);
    for (int i = 0; i < 4; i++) {
      _bytes.add(data.getUint8(i));
    }
  }

  void writeDouble(double value) {
    final data = ByteData(8);
    data.setFloat64(0, value, Endian.little);
    for (int i = 0; i < 8; i++) {
      _bytes.add(data.getUint8(i));
    }
  }

  void writeBoolean(bool value) {
    writeByte(value ? 1 : 0);
  }

  void writeChar(String char) {
    if (char.isEmpty) {
      writeByte(0);
    } else {
      writeByte(char.codeUnitAt(0));
    }
  }

  void writeDateTime(int ticks) {
    writeUInt64(ticks);
  }

  void writeTimeSpan(int ticks) {
    writeInt64(ticks);
  }

  void writeDecimal(String hexString) {
    for (int i = 0; i < 32; i += 2) {
      writeByte(int.parse(hexString.substring(i, i + 2), radix: 16));
    }
  }

  void writeVariableLengthInt(int value) {
    int remaining = value;
    while (remaining >= 0x80) {
      writeByte((remaining & 0x7F) | 0x80);
      remaining >>= 7;
    }
    writeByte(remaining);
  }

  void writeLengthPrefixedString(String str) {
    final bytes = utf8.encode(str);
    writeVariableLengthInt(bytes.length);
    _bytes.addAll(bytes);
  }
}

// ============================================================================
// NRBF DECODER
// ============================================================================

class NrbfDecoder {
  final BinaryReader _reader;
  final Map<int, NrbfRecord> _recordMap = {};
  final Map<int, String> _libraryMap = {};
  final Map<int, _MetadataInfo> _metadataMap = {};
  final List<NrbfRecord> _allRecordsInOrder = []; // Track all records
  final bool verbose;

  NrbfDecoder(Uint8List bytes, {this.verbose = false})
      : _reader = BinaryReader(bytes);

  void _log(String message) {
    if (verbose) {
      developer.log('[NRBF] $message', name: 'NrbfDecoder');
      print('[NRBF] $message');
    }
  }

  NrbfRecord decode() {
    _log('Starting decode, buffer size: ${_reader._data.lengthInBytes} bytes');
    _log('Position: 0x${_reader.position.toRadixString(16)}');

    // Read header byte
    final headerByte = _reader.readByte();
    _log(
        'Header byte: 0x${headerByte.toRadixString(16)} (expected 0x00 for SerializationHeader)');

    if (headerByte != RecordType.serializedStreamHeader.value) {
      throw Exception(
          'Invalid header: expected 0x00, got 0x${headerByte.toRadixString(16)}');
    }

    // Read header fields
    final rootId = _reader.readInt32();
    final headerId = _reader.readInt32();
    final majorVersion = _reader.readInt32();
    final minorVersion = _reader.readInt32();

    _log(
        'Header: rootId=$rootId, headerId=$headerId, version=$majorVersion.$minorVersion');
    _log('Position after header: 0x${_reader.position.toRadixString(16)}');

    final header =
        SerializationHeader(rootId, headerId, majorVersion, minorVersion);

    int count = 0;
    NrbfRecord? record;

    // Read all records until MessageEnd
    do {
      final pos = _reader.position;
      _log('\nRecord #$count at offset 0x${pos.toRadixString(16)}');

      record = _decodeNext();
      
      // Store ALL records in order (including BinaryLibrary!)
      _allRecordsInOrder.add(record);

      _log(
          '  -> ${record.runtimeType}${record.objectId != null ? ' (ID: ${record.objectId})' : ''}');
      count++;

      if (count > 100000) {
        throw Exception('Too many records - possible infinite loop');
      }
    } while (record is! MessageEndRecord);

    _log('\nTotal records decoded: $count');
    _log('Root ID from header: ${header.rootId}');
    _log(
        'Available record IDs: ${_recordMap.keys.toList()..sort((a, b) => a.compareTo(b))}');

    final root = _recordMap[header.rootId];
    if (root == null) {
      throw Exception('Root object with ID ${header.rootId} not found');
    }

    return root;
  }

  List<NrbfRecord> getAllRecordsInOrder() => _allRecordsInOrder;

  // Resolve references during member reading
  dynamic _resolveMemberValue(dynamic value) {
    if (value is MemberReferenceRecord) {
      final resolved = _recordMap[value.idRef];
      if (resolved != null) {
        _log('      -> Resolved reference ${value.idRef} to ${resolved.runtimeType}');
        return resolved;
      } else {
        _log('      -> WARNING: Could not resolve reference ${value.idRef}');
        return value; // Return the reference if we can't resolve it
      }
    }
    return value;
  }

  NrbfRecord _decodeNext() {
    final pos = _reader.position;
    final recordTypeByte = _reader.readByte();

    _log(
        '  Offset 0x${pos.toRadixString(16)}: RecordType byte = 0x${recordTypeByte.toRadixString(16)}');

    // Validate record type
    final validTypes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17];
    if (!validTypes.contains(recordTypeByte)) {
      throw Exception(
          'Unsupported record type: $recordTypeByte (0x${recordTypeByte.toRadixString(16)}) at offset 0x${pos.toRadixString(16)}');
    }

    switch (recordTypeByte) {
      case 0:
        _log('    -> SerializedStreamHeader');
        return _decodeSerializationHeader();
      case 12:
        _log('    -> BinaryLibrary');
        return _decodeBinaryLibrary();
      case 5:
        _log('    -> ClassWithMembersAndTypes');
        return _decodeClassWithMembersAndTypes();
      case 4:
        _log('    -> SystemClassWithMembersAndTypes');
        return _decodeSystemClassWithMembersAndTypes();
      case 2:
        _log('    -> SystemClassWithMembers');
        return _decodeSystemClassWithMembers();
      case 3:
        _log('    -> ClassWithMembers');
        return _decodeClassWithMembers();
      case 1:
        _log('    -> ClassWithId');
        return _decodeClassWithId();
      case 6:
        _log('    -> BinaryObjectString');
        return _decodeBinaryObjectString();
      case 7:
        _log('    -> BinaryArray');
        return _decodeBinaryArray();
      case 15:
        _log('    -> ArraySinglePrimitive');
        return _decodeArraySinglePrimitive();
      case 16:
        _log('    -> ArraySingleObject');
        return _decodeArraySingleObject();
      case 17:
        _log('    -> ArraySingleString');
        return _decodeArraySingleString();
      case 8:
        _log('    -> MemberPrimitiveTyped');
        return _decodeMemberPrimitiveTyped();
      case 9:
        _log('    -> MemberReference');
        return _decodeMemberReference();
      case 10:
        _log('    -> ObjectNull');
        return ObjectNullRecord();
      case 14:
        _log('    -> ObjectNullMultiple');
        return _decodeObjectNullMultiple();
      case 13:
        _log('    -> ObjectNullMultiple256');
        return _decodeObjectNullMultiple256();
      case 11:
        _log('    -> MessageEnd');
        return MessageEndRecord();
      default:
        throw Exception('Unhandled record type: $recordTypeByte');
    }
  }

  SerializationHeader _decodeSerializationHeader() {
    final rootId = _reader.readInt32();
    final headerId = _reader.readInt32();
    final majorVersion = _reader.readInt32();
    final minorVersion = _reader.readInt32();

    _log(
        '      rootId=$rootId, headerId=$headerId, version=$majorVersion.$minorVersion');

    return SerializationHeader(rootId, headerId, majorVersion, minorVersion);
  }

  BinaryLibrary _decodeBinaryLibrary() {
    final libraryId = _reader.readInt32();
    final libraryName = _reader.readLengthPrefixedString();

    _log('      libraryId=$libraryId, libraryName="$libraryName"');

    final record = BinaryLibrary(libraryId, libraryName);
    _libraryMap[libraryId] = libraryName;

    return record;
  }

  ClassInfo _readClassInfo() {
    final objectId = _reader.readInt32();
    final name = _reader.readLengthPrefixedString();
    final memberCount = _reader.readInt32();
    final memberNames = <String>[];

    for (int i = 0; i < memberCount; i++) {
      memberNames.add(_reader.readLengthPrefixedString());
    }

    _log(
        '      ClassInfo: objectId=$objectId, name="$name", memberCount=$memberCount');
    _log('      Members: ${memberNames.join(", ")}');

    return ClassInfo(objectId, name, memberCount, memberNames);
  }

  MemberTypeInfo _readMemberTypeInfo(int memberCount) {
    final binaryTypeEnums = <BinaryType>[];

    for (int i = 0; i < memberCount; i++) {
      binaryTypeEnums.add(BinaryType.fromValue(_reader.readByte()));
    }

    final additionalInfos = <AdditionalTypeInfo>[];

    for (int i = 0; i < memberCount; i++) {
      final binaryType = binaryTypeEnums[i];

      switch (binaryType) {
        case BinaryType.primitive:
          additionalInfos
              .add(PrimitiveTypeInfo(PrimitiveType.fromValue(_reader.readByte())));
          break;
        case BinaryType.systemClass:
          additionalInfos
              .add(SystemClassTypeInfo(_reader.readLengthPrefixedString()));
          break;
        case BinaryType.classType:
          final className = _reader.readLengthPrefixedString();
          final libraryId = _reader.readInt32();
          additionalInfos.add(ClassTypeInfo(className, libraryId));
          break;
        default:
          additionalInfos.add(const NoneTypeInfo());
      }
    }

    _log('      BinaryTypes: ${binaryTypeEnums.map((e) => e.name).join(", ")}');

    return MemberTypeInfo(binaryTypeEnums, additionalInfos);
  }

  ClassRecord _decodeClassWithMembersAndTypes() {
    final classInfo = _readClassInfo();
    final memberTypeInfo = _readMemberTypeInfo(classInfo.memberCount);
    final libraryId = _reader.readInt32();

    _log('      libraryId=$libraryId');

    final record = ClassRecord(
      classInfo,
      memberTypeInfo,
      libraryId,
      RecordType.classWithMembersAndTypes,
    );

    _metadataMap[classInfo.objectId] =
        _MetadataInfo(classInfo, memberTypeInfo, libraryId);
    _recordMap[classInfo.objectId] = record;

    _readMemberValues(record, classInfo.memberNames, memberTypeInfo);

    return record;
  }

  ClassRecord _decodeSystemClassWithMembersAndTypes() {
    final classInfo = _readClassInfo();
    final memberTypeInfo = _readMemberTypeInfo(classInfo.memberCount);

    final record = ClassRecord(
      classInfo,
      memberTypeInfo,
      null,
      RecordType.systemClassWithMembersAndTypes,
    );

    _metadataMap[classInfo.objectId] =
        _MetadataInfo(classInfo, memberTypeInfo, null);
    _recordMap[classInfo.objectId] = record;

    _readMemberValues(record, classInfo.memberNames, memberTypeInfo);

    return record;
  }

  ClassRecord _decodeSystemClassWithMembers() {
    final classInfo = _readClassInfo();

    final record = ClassRecord(
      classInfo,
      null,
      null,
      RecordType.systemClassWithMembers,
    );

    _metadataMap[classInfo.objectId] = _MetadataInfo(classInfo, null, null);
    _recordMap[classInfo.objectId] = record;

    _log('      Reading ${classInfo.memberCount} member values (no type info)');
    for (final memberName in classInfo.memberNames) {
      var value = _decodeNext();
      // Keep the reference as-is
      record.memberValues[memberName] = value;
      _log('        $memberName = ${_formatValueForLog(value)}');
    }

    return record;
  }

  ClassRecord _decodeClassWithMembers() {
    final classInfo = _readClassInfo();
    final libraryId = _reader.readInt32();

    _log('      libraryId=$libraryId');

    final record = ClassRecord(
      classInfo,
      null,
      libraryId,
      RecordType.classWithMembers,
    );

    _metadataMap[classInfo.objectId] = _MetadataInfo(classInfo, null, libraryId);
    _recordMap[classInfo.objectId] = record;

    _log('      Reading ${classInfo.memberCount} member values (no type info)');
    for (final memberName in classInfo.memberNames) {
      var value = _decodeNext();
      // Keep the reference as-is
      record.memberValues[memberName] = value;
      _log('        $memberName = ${_formatValueForLog(value)}');
    }

    return record;
  }

  ClassRecord _decodeClassWithId() {
    final objectId = _reader.readInt32();
    final metadataId = _reader.readInt32();

    _log('      objectId=$objectId, metadataId=$metadataId');

    final metadata = _metadataMap[metadataId];
    if (metadata == null) {
      throw Exception('Metadata not found for ID $metadataId');
    }

    final classInfo = ClassInfo(
      objectId,
      metadata.classInfo.name,
      metadata.classInfo.memberCount,
      metadata.classInfo.memberNames,
    );

    final record = ClassRecord(
      classInfo,
      metadata.memberTypeInfo,
      metadata.libraryId,
      RecordType.classWithId,
      metadataId: metadataId,
    );

    _recordMap[objectId] = record;

    if (metadata.memberTypeInfo != null) {
      _readMemberValues(
          record, classInfo.memberNames, metadata.memberTypeInfo!);
    } else {
      _log('      Reading ${classInfo.memberCount} member values (no type info)');
      for (final memberName in classInfo.memberNames) {
        final value = _decodeNext();
        record.memberValues[memberName] = value;
        _log('        $memberName = ${_formatValueForLog(value)}');
      }
    }

    return record;
  }

  void _readMemberValues(
      ClassRecord record, List<String> memberNames, MemberTypeInfo memberTypeInfo) {
    _log('      Reading ${memberNames.length} member values:');
    for (int i = 0; i < memberNames.length; i++) {
      final memberName = memberNames[i];
      final binaryType = memberTypeInfo.binaryTypes[i];
      final additionalInfo = memberTypeInfo.additionalInfos[i];

      var value = _readObjectValue(binaryType, additionalInfo);
      
      // DON'T auto-resolve here - keep the reference!
      // The UI/encoder will resolve when needed
      
      record.memberValues[memberName] = value;
      _log('        $memberName = ${_formatValueForLog(value)}');
    }
  }

  dynamic _readObjectValue(
      BinaryType binaryType, AdditionalTypeInfo additionalInfo) {
    if (binaryType == BinaryType.primitive &&
        additionalInfo is PrimitiveTypeInfo) {
      return _readPrimitiveValue(additionalInfo.primitiveType);
    } else {
      return _decodeNext();
    }
  }

  dynamic _readPrimitiveValue(PrimitiveType primitiveType) {
    switch (primitiveType) {
      case PrimitiveType.boolean:
        return _reader.readBoolean();
      case PrimitiveType.byte:
        return _reader.readByte();
      case PrimitiveType.sByte:
        return _reader.readSByte();
      case PrimitiveType.char:
        return _reader.readChar();
      case PrimitiveType.int16:
        return _reader.readInt16();
      case PrimitiveType.uInt16:
        return _reader.readUInt16();
      case PrimitiveType.int32:
        return _reader.readInt32();
      case PrimitiveType.uInt32:
        return _reader.readUInt32();
      case PrimitiveType.int64:
        return _reader.readInt64();
      case PrimitiveType.uInt64:
        return _reader.readUInt64();
      case PrimitiveType.single:
        return _reader.readSingle();
      case PrimitiveType.double:
        return _reader.readDouble();
      case PrimitiveType.decimal:
        return _reader.readDecimal();
      case PrimitiveType.dateTime:
        return _reader.readDateTime();
      case PrimitiveType.timeSpan:
        return _reader.readTimeSpan();
      case PrimitiveType.string:
        return _reader.readLengthPrefixedString();
      case PrimitiveType.nullType:
        return null;
    }
  }

  BinaryObjectStringRecord _decodeBinaryObjectString() {
    final objectId = _reader.readInt32();
    final value = _reader.readLengthPrefixedString();

    _log('      objectId=$objectId, value="$value"');

    final record = BinaryObjectStringRecord(objectId, value);
    _recordMap[objectId] = record;

    return record;
  }

  BinaryArrayRecord _decodeBinaryArray() {
    final objectId = _reader.readInt32();
    final binaryArrayTypeEnum =
        BinaryArrayType.fromValue(_reader.readByte());
    final rank = _reader.readInt32();

    final lengths = <int>[];
    for (int i = 0; i < rank; i++) {
      lengths.add(_reader.readInt32());
    }

    List<int>? lowerBounds;
    if (binaryArrayTypeEnum == BinaryArrayType.singleOffset ||
        binaryArrayTypeEnum == BinaryArrayType.jaggedOffset ||
        binaryArrayTypeEnum == BinaryArrayType.rectangularOffset) {
      lowerBounds = [];
      for (int i = 0; i < rank; i++) {
        lowerBounds.add(_reader.readInt32());
      }
    }

    final typeEnum = BinaryType.fromValue(_reader.readByte());
    final additionalTypeInfo = _readAdditionalTypeInfo(typeEnum);

    final totalElements = lengths.reduce((a, b) => a * b);
    _log(
        '      objectId=$objectId, arrayType=${binaryArrayTypeEnum.name}, rank=$rank, lengths=$lengths, totalElements=$totalElements');

    final elementValues = _readAllElements(totalElements, typeEnum, additionalTypeInfo);

    final record = BinaryArrayRecord(
      objectId,
      binaryArrayTypeEnum,
      rank,
      lengths,
      lowerBounds,
      typeEnum,
      additionalTypeInfo,
      elementValues,
    );

    _recordMap[objectId] = record;
    return record;
  }

  AdditionalTypeInfo _readAdditionalTypeInfo(BinaryType binaryType) {
    switch (binaryType) {
      case BinaryType.primitive:
        return PrimitiveTypeInfo(PrimitiveType.fromValue(_reader.readByte()));
      case BinaryType.systemClass:
        return SystemClassTypeInfo(_reader.readLengthPrefixedString());
      case BinaryType.classType:
        final className = _reader.readLengthPrefixedString();
        final libraryId = _reader.readInt32();
        return ClassTypeInfo(className, libraryId);
      default:
        return const NoneTypeInfo();
    }
  }

  List<dynamic> _readAllElements(
      int count, BinaryType binaryType, AdditionalTypeInfo additionalInfo) {
    final elements = <dynamic>[];
    int i = 0;

    while (i < count) {
      final val = _readObjectValue(binaryType, additionalInfo);

      if (val is ObjectNullMultipleRecord) {
        for (int j = 0; j < val.nullCount; j++) {
          elements.add(null);
        }
        i += val.nullCount;
        continue;
      } else if (val is ObjectNullMultiple256Record) {
        for (int j = 0; j < val.nullCount; j++) {
          elements.add(null);
        }
        i += val.nullCount;
        continue;
      } else if (val is ObjectNullRecord) {
        elements.add(null);
      } else {
        elements.add(val);
      }

      i++;
    }

    return elements;
  }

  ArraySinglePrimitiveRecord _decodeArraySinglePrimitive() {
    final objectId = _reader.readInt32();
    final length = _reader.readInt32();
    final primitiveTypeEnum = PrimitiveType.fromValue(_reader.readByte());

    _log(
        '      objectId=$objectId, length=$length, primitiveType=${primitiveTypeEnum.name}');

    final elements = <dynamic>[];
    for (int i = 0; i < length; i++) {
      elements.add(_readPrimitiveValue(primitiveTypeEnum));
    }

    final record =
        ArraySinglePrimitiveRecord(objectId, length, primitiveTypeEnum, elements);
    _recordMap[objectId] = record;
    return record;
  }

  ArraySingleObjectRecord _decodeArraySingleObject() {
    final objectId = _reader.readInt32();
    final length = _reader.readInt32();

    _log('      objectId=$objectId, length=$length');

    final elements =
        _readAllElements(length, BinaryType.object, const NoneTypeInfo());

    final record = ArraySingleObjectRecord(objectId, length, elements);
    _recordMap[objectId] = record;
    return record;
  }

  ArraySingleStringRecord _decodeArraySingleString() {
    final objectId = _reader.readInt32();
    final length = _reader.readInt32();

    _log('      objectId=$objectId, length=$length');

    final elements =
        _readAllElements(length, BinaryType.string, const NoneTypeInfo());

    final record = ArraySingleStringRecord(objectId, length, elements);
    _recordMap[objectId] = record;
    return record;
  }

  MemberPrimitiveTypedRecord _decodeMemberPrimitiveTyped() {
    final primitiveTypeEnum = PrimitiveType.fromValue(_reader.readByte());
    final value = _readPrimitiveValue(primitiveTypeEnum);

    _log(
        '      primitiveType=${primitiveTypeEnum.name}, value=${_formatValueForLog(value)}');

    return MemberPrimitiveTypedRecord(primitiveTypeEnum, value);
  }

  MemberReferenceRecord _decodeMemberReference() {
    final idRef = _reader.readInt32();

    _log('      idRef=$idRef');

    return MemberReferenceRecord(idRef);
  }

  ObjectNullMultipleRecord _decodeObjectNullMultiple() {
    final nullCount = _reader.readInt32();
    _log('      nullCount=$nullCount');
    return ObjectNullMultipleRecord(nullCount);
  }

  ObjectNullMultiple256Record _decodeObjectNullMultiple256() {
    final nullCount = _reader.readByte();
    _log('      nullCount=$nullCount');
    return ObjectNullMultiple256Record(nullCount);
  }

  NrbfRecord? getRecord(int objectId) => _recordMap[objectId];

  Map<int, NrbfRecord> getAllRecords() => _recordMap;

  Map<int, String> getLibraries() => _libraryMap;

  NrbfRecord resolveReference(MemberReferenceRecord ref) {
    final record = _recordMap[ref.idRef];
    if (record == null) {
      throw Exception('Cannot resolve reference to ID ${ref.idRef}');
    }
    return record;
  }

  String _formatValueForLog(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is NrbfRecord) return value.runtimeType.toString();
    if (value is bool || value is num) return value.toString();
    return value.runtimeType.toString();
  }
}

class _MetadataInfo {
  final ClassInfo classInfo;
  final MemberTypeInfo? memberTypeInfo;
  final int? libraryId;

  _MetadataInfo(this.classInfo, this.memberTypeInfo, this.libraryId);
}

// ============================================================================
// NRBF ENCODER
// ============================================================================

class NrbfEncoder {
  final BinaryWriter _writer = BinaryWriter();
  final Set<int> _writtenRecords = {};
  NrbfDecoder? _decoder;

  Uint8List encode(NrbfRecord root, {NrbfDecoder? decoder, int? rootId}) {
    final actualRootId = rootId ?? root.objectId ?? 1;

    _decoder = decoder;
    _writer._bytes.clear();
    _writtenRecords.clear();

    // Write header
    _writer.writeByte(RecordType.serializedStreamHeader.value);
    _writer.writeInt32(actualRootId);
    _writer.writeInt32(-1);
    _writer.writeInt32(1);
    _writer.writeInt32(0);

    if (_decoder != null) {
      // CRITICAL: Write records in THE EXACT SAME ORDER as they were decoded!
      final allRecords = _decoder!.getAllRecordsInOrder();
      
      for (final record in allRecords) {
        // Skip MessageEndRecord - we'll write it at the end
        if (record is MessageEndRecord) continue;
        
        // Write BinaryLibrary records as they appear
        if (record is BinaryLibrary) {
          _encodeBinaryLibrary(record);
          continue;
        }
        
        // Write other records
        if (record.objectId != null) {
          if (!_writtenRecords.contains(record.objectId!)) {
            _encodeRecord(record);
          }
        }
      }
    } else {
      // Fallback: If no decoder, collect records from graph
      final allRecords = _collectAllRecords(root);
      for (final record in allRecords) {
        if (record.objectId != null && !_writtenRecords.contains(record.objectId!)) {
          _encodeRecord(record);
        }
      }
    }

    _writer.writeByte(RecordType.messageEnd.value);

    return _writer.toBytes();
  }

  // Keep the old collectAllRecords for when there's no decoder
  List<NrbfRecord> _collectAllRecords(NrbfRecord root) {
    final collected = <NrbfRecord>[];
    final seen = <int>{};

    void collect(dynamic record) {
      if (record == null) return;

      if (record is! NrbfRecord) return;

      if (record.objectId != null && seen.contains(record.objectId!)) return;
      if (record.objectId != null) seen.add(record.objectId!);

      if (record is MemberReferenceRecord) {
        if (_decoder != null) {
          final target = _decoder!.getRecord(record.idRef);
          if (target != null) {
            collect(target);
          }
        }
        return;
      }

      collected.add(record);

      if (record is ClassRecord) {
        for (final memberName in record.memberNames) {
          collect(record.getValue(memberName));
        }
      }

      if (record is BinaryArrayRecord ||
          record is ArraySinglePrimitiveRecord ||
          record is ArraySingleObjectRecord ||
          record is ArraySingleStringRecord) {
        for (final element in (record as dynamic).getArray()) {
          collect(element);
        }
      }
    }

    collect(root);
    return collected;
  }

  void _encodeRecord(NrbfRecord record) {
    if (record.objectId != null && _writtenRecords.contains(record.objectId!)) {
      return;
    }

    if (record is ClassRecord) {
      _encodeClassRecord(record);
    } else if (record is BinaryArrayRecord) {
      _encodeBinaryArrayRecord(record);
    } else if (record is ArraySinglePrimitiveRecord) {
      _encodeArraySinglePrimitive(record);
    } else if (record is ArraySingleObjectRecord) {
      _encodeArraySingleObject(record);
    } else if (record is ArraySingleStringRecord) {
      _encodeArraySingleString(record);
    } else if (record is BinaryObjectStringRecord) {
      _encodeBinaryObjectString(record);
    } else if (record is MemberPrimitiveTypedRecord) {
      _encodeMemberPrimitiveTyped(record);
    } else if (record is ObjectNullRecord) {
      _writer.writeByte(RecordType.objectNull.value);
    } else if (record is ObjectNullMultipleRecord) {
      _encodeObjectNullMultiple(record);
    } else if (record is ObjectNullMultiple256Record) {
      _encodeObjectNullMultiple256(record);
    }

    if (record.objectId != null) {
      _writtenRecords.add(record.objectId!);
    }
  }

  void _encodeClassRecord(ClassRecord record) {
    final rt = record.recordType;

    // Special handling for ClassWithId
    if (rt == RecordType.classWithId && record.metadataId != null) {
      _writer.writeByte(RecordType.classWithId.value);
      _writer.writeInt32(record.classInfo.objectId);
      _writer.writeInt32(record.metadataId!);

      // Write member values
      for (int i = 0; i < record.classInfo.memberNames.length; i++) {
        final memberName = record.classInfo.memberNames[i];
        final value = record.memberValues[memberName];

        BinaryType? binaryType;
        AdditionalTypeInfo? additionalInfo;

        if (record.memberTypeInfo != null) {
          binaryType = record.memberTypeInfo!.binaryTypes[i];
          additionalInfo = record.memberTypeInfo!.additionalInfos[i];
        }

        _writeObjectValue(value, binaryType, additionalInfo);
      }
      return;
    }

    // For other class record types, write full definition
    _writer.writeByte(rt.value);
    _writeClassInfo(record.classInfo);

    if (rt == RecordType.classWithMembersAndTypes ||
        rt == RecordType.systemClassWithMembersAndTypes) {
      _writeMemberTypeInfo(record.memberTypeInfo!);
    }

    if (rt == RecordType.classWithMembersAndTypes ||
        rt == RecordType.classWithMembers) {
      _writer.writeInt32(record.libraryId!);
    }

    // Write member values
    for (int i = 0; i < record.classInfo.memberNames.length; i++) {
      final memberName = record.classInfo.memberNames[i];
      final value = record.memberValues[memberName];

      BinaryType? binaryType;
      AdditionalTypeInfo? additionalInfo;

      if (record.memberTypeInfo != null) {
        binaryType = record.memberTypeInfo!.binaryTypes[i];
        additionalInfo = record.memberTypeInfo!.additionalInfos[i];
      }

      _writeObjectValue(value, binaryType, additionalInfo);
    }
  }

  void _writeClassInfo(ClassInfo classInfo) {
    _writer.writeInt32(classInfo.objectId);
    _writer.writeLengthPrefixedString(classInfo.name);
    _writer.writeInt32(classInfo.memberCount);

    for (final memberName in classInfo.memberNames) {
      _writer.writeLengthPrefixedString(memberName);
    }
  }

  void _writeMemberTypeInfo(MemberTypeInfo memberTypeInfo) {
    for (final bt in memberTypeInfo.binaryTypes) {
      _writer.writeByte(bt.value);
    }

    for (final info in memberTypeInfo.additionalInfos) {
      if (info is PrimitiveTypeInfo) {
        _writer.writeByte(info.primitiveType.value);
      } else if (info is SystemClassTypeInfo) {
        _writer.writeLengthPrefixedString(info.className);
      } else if (info is ClassTypeInfo) {
        _writer.writeLengthPrefixedString(info.className);
        _writer.writeInt32(info.libraryId);
      }
    }
  }

  void _encodeBinaryArrayRecord(BinaryArrayRecord record) {
    _writer.writeByte(RecordType.binaryArray.value);
    _writer.writeInt32(record.arrayObjectId);
    _writer.writeByte(record.binaryArrayTypeEnum.value);
    _writer.writeInt32(record.rank);

    for (final length in record.lengths) {
      _writer.writeInt32(length);
    }

    if (record.lowerBounds != null) {
      for (final bound in record.lowerBounds!) {
        _writer.writeInt32(bound);
      }
    }

    _writer.writeByte(record.typeEnum.value);
    _writeAdditionalTypeInfo(record.additionalTypeInfo);

    for (final element in record.elementValues) {
      _writeObjectValue(element, record.typeEnum, record.additionalTypeInfo);
    }
  }

  void _writeAdditionalTypeInfo(AdditionalTypeInfo info) {
    if (info is PrimitiveTypeInfo) {
      _writer.writeByte(info.primitiveType.value);
    } else if (info is SystemClassTypeInfo) {
      _writer.writeLengthPrefixedString(info.className);
    } else if (info is ClassTypeInfo) {
      _writer.writeLengthPrefixedString(info.className);
      _writer.writeInt32(info.libraryId);
    }
  }

  void _encodeArraySinglePrimitive(ArraySinglePrimitiveRecord record) {
    _writer.writeByte(RecordType.arraySinglePrimitive.value);
    _writer.writeInt32(record.arrayObjectId);
    _writer.writeInt32(record.length);
    _writer.writeByte(record.primitiveTypeEnum.value);

    for (final element in record.elementValues) {
      _writePrimitiveValue(element, record.primitiveTypeEnum);
    }
  }

  void _encodeArraySingleObject(ArraySingleObjectRecord record) {
    _writer.writeByte(RecordType.arraySingleObject.value);
    _writer.writeInt32(record.arrayObjectId);
    _writer.writeInt32(record.length);

    for (final element in record.elementValues) {
      _writeObjectValue(element, null, null);
    }
  }

  void _encodeArraySingleString(ArraySingleStringRecord record) {
    _writer.writeByte(RecordType.arraySingleString.value);
    _writer.writeInt32(record.arrayObjectId);
    _writer.writeInt32(record.length);

    for (final element in record.elementValues) {
      _writeObjectValue(element, null, null);
    }
  }

  void _encodeBinaryObjectString(BinaryObjectStringRecord record) {
    _writer.writeByte(RecordType.binaryObjectString.value);
    _writer.writeInt32(record.stringObjectId);
    _writer.writeLengthPrefixedString(record.value);
  }

  void _encodeBinaryLibrary(BinaryLibrary record) {
    _writer.writeByte(RecordType.binaryLibrary.value);
    _writer.writeInt32(record.libraryId);
    _writer.writeLengthPrefixedString(record.libraryName);
  }

  void _encodeMemberPrimitiveTyped(MemberPrimitiveTypedRecord record) {
    _writer.writeByte(RecordType.memberPrimitiveTyped.value);
    _writer.writeByte(record.primitiveTypeEnum.value);
    _writePrimitiveValue(record.value, record.primitiveTypeEnum);
  }

  void _encodeMemberReference(MemberReferenceRecord record) {
    _writer.writeByte(RecordType.memberReference.value);
    _writer.writeInt32(record.idRef);
  }

  void _encodeObjectNullMultiple(ObjectNullMultipleRecord record) {
    _writer.writeByte(RecordType.objectNullMultiple.value);
    _writer.writeInt32(record.nullCount);
  }

  void _encodeObjectNullMultiple256(ObjectNullMultiple256Record record) {
    _writer.writeByte(RecordType.objectNullMultiple256.value);
    _writer.writeByte(record.nullCount);
  }

  void _writeObjectValue(
      dynamic value, BinaryType? binaryType, AdditionalTypeInfo? additionalInfo) {
    if (value == null) {
      _writer.writeByte(RecordType.objectNull.value);
      return;
    }

    if (binaryType == BinaryType.primitive &&
        additionalInfo is PrimitiveTypeInfo) {
      _writePrimitiveValue(value, additionalInfo.primitiveType);
      return;
    }

    // For MemberReference, ONLY write the reference - don't encode the target!
    if (value is MemberReferenceRecord) {
      _encodeMemberReference(value);
      return;
    }

    if (value is NrbfRecord) {
      _encodeRecord(value);
      return;
    }

    if (value is bool) {
      _writer.writeBoolean(value);
    } else if (value is int) {
      _writer.writeInt32(value);
    } else if (value is double) {
      _writer.writeDouble(value);
    } else if (value is String) {
      throw Exception(
          'Cannot encode bare string without object ID - internal error');
    } else {
      throw Exception(
          'Cannot encode value of type ${value.runtimeType} without type information');
    }
  }

  void _writePrimitiveValue(dynamic value, PrimitiveType type) {
    if (value == null) return;

    switch (type) {
      case PrimitiveType.boolean:
        _writer.writeBoolean(value as bool);
        break;
      case PrimitiveType.byte:
        _writer.writeByte(value as int);
        break;
      case PrimitiveType.sByte:
        _writer.writeSByte(value as int);
        break;
      case PrimitiveType.char:
        _writer.writeChar(value as String);
        break;
      case PrimitiveType.int16:
        _writer.writeInt16(value as int);
        break;
      case PrimitiveType.uInt16:
        _writer.writeUInt16(value as int);
        break;
      case PrimitiveType.int32:
        _writer.writeInt32(value as int);
        break;
      case PrimitiveType.uInt32:
        _writer.writeUInt32(value as int);
        break;
      case PrimitiveType.int64:
        _writer.writeInt64(value as int);
        break;
      case PrimitiveType.uInt64:
        _writer.writeUInt64(value as int);
        break;
      case PrimitiveType.single:
        _writer.writeSingle(value as double);
        break;
      case PrimitiveType.double:
        _writer.writeDouble(value as double);
        break;
      case PrimitiveType.decimal:
        _writer.writeDecimal(value as String);
        break;
      case PrimitiveType.dateTime:
        _writer.writeDateTime(value as int);
        break;
      case PrimitiveType.timeSpan:
        _writer.writeTimeSpan(value as int);
        break;
      case PrimitiveType.string:
        _writer.writeLengthPrefixedString(value as String);
        break;
      case PrimitiveType.nullType:
        break;
    }
  }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

class NrbfUtils {
  static bool startsWithPayloadHeader(Uint8List buffer) {
    if (buffer.length < 17) return false;

    if (buffer[0] != RecordType.serializedStreamHeader.value) {
      return false;
    }

    final expectedSuffix = [1, 0, 0, 0, 0, 0, 0, 0];
    for (int i = 0; i < 8; i++) {
      if (buffer[9 + i] != expectedSuffix[i]) {
        return false;
      }
    }

    return true;
  }

  static String parseGuid(ClassRecord guidRecord) {
    return ClassRecord.reconstructGuid(guidRecord);
  }

  static ClassRecord createGuidRecord(int objectId, String guidString) {
    return ClassRecord.createGuidRecord(objectId, guidString);
  }

  static dynamic getNestedValue(
      NrbfRecord record, String path, NrbfDecoder? decoder) {
    final parts = path.split('.');
    dynamic current = record;

    for (final part in parts) {
      // Resolve references if we hit a MemberReferenceRecord
      if (current is MemberReferenceRecord) {
        if (decoder != null) {
          current = decoder.getRecord(current.idRef);
          if (current == null) return null;
        } else {
          return null;
        }
      }

      if (current is ClassRecord) {
        current = current.getValue(part);
      } else if ((current is ArraySingleObjectRecord ||
              current is ArraySinglePrimitiveRecord ||
              current is ArraySingleStringRecord ||
              current is BinaryArrayRecord) &&
          int.tryParse(part) != null) {
        current = (current as dynamic).getArray()[int.parse(part)];
      } else {
        return null;
      }

      if (current == null) return null;
    }

    // Final resolution if we ended on a reference
    if (current is MemberReferenceRecord && decoder != null) {
      current = decoder.getRecord(current.idRef);
    }

    return current;
  }

  static List<int> findGuidInBinary(Uint8List buffer, String guidString) {
    final hex = guidString.replaceAll('-', '');
    final pattern = Uint8List(16);

    for (int i = 0; i < 16; i++) {
      pattern[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }

    final matches = <int>[];
    for (int i = 0; i <= buffer.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (buffer[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) matches.add(i);
    }

    return matches;
  }

  static Uint8List replaceGuidAtOffset(
      Uint8List buffer, int offset, String newGuidString) {
    final hex = newGuidString.replaceAll('-', '');
    final data = Uint8List.fromList(buffer);

    for (int i = 0; i < 16; i++) {
      data[offset + i] =
          int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }

    return data;
  }
}