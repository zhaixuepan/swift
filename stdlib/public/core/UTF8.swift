//===--- UTF8.swift -------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
extension _Unicode {
  @_fixed_layout
  public enum UTF8 {
  case _swift3Buffer(_Unicode.UTF8.ForwardParser)
  }
}

extension _Unicode.UTF8 : UnicodeEncoding {
  public typealias CodeUnit = UInt8
  public typealias EncodedScalar = _UIntBuffer<UInt32, UInt8>

  public static var encodedReplacementCharacter : EncodedScalar {
    return EncodedScalar(_storage: 0xbdbfef, _bitCount: 24)
  }

  @inline(__always)
  @_inlineable
  public static func _isScalar(_ x: CodeUnit) -> Bool {
    return x & 0x80 == 0
  }

  @inline(__always)
  @_inlineable
  public static func decode(_ source: EncodedScalar) -> UnicodeScalar {
    let bits = source._storage
    switch source._bitCount {
    case 8:
      return UnicodeScalar(_unchecked: bits)
    case 16:
      var value = (bits & 0b0_______________________11_1111__0000_0000) &>> 8
      value    |= (bits & 0b0________________________________0001_1111) &<< 6
      return UnicodeScalar(_unchecked: value)
    case 24:
      var value = (bits & 0b0____________11_1111__0000_0000__0000_0000) &>> 16
      value    |= (bits & 0b0_______________________11_1111__0000_0000) &>> 2
      value    |= (bits & 0b0________________________________0000_1111) &<< 12
      return UnicodeScalar(_unchecked: value)
    default:
      _sanityCheck(source.count == 4)
      var value = (bits & 0b0_11_1111__0000_0000__0000_0000__0000_0000) &>> 24
      value    |= (bits & 0b0____________11_1111__0000_0000__0000_0000) &>> 10
      value    |= (bits & 0b0_______________________11_1111__0000_0000) &<< 4
      value    |= (bits & 0b0________________________________0000_0111) &<< 18
      return UnicodeScalar(_unchecked: value)
    }
  }
  
  @inline(__always)
  @_inlineable
  public static func encodeIfRepresentable(
    _ source: UnicodeScalar
  ) -> EncodedScalar? {
    var c = source.value
    if _fastPath(c < (1&<<7)) {
      return EncodedScalar(_storage: c, _bitCount: 8)
    }
    var o = c & 0b0__0011_1111
    c &>>= 6
    o &<<= 8
    if _fastPath(c < (1&<<5)) {
      return EncodedScalar(
        _storage: o | c | 0b0__1000_0000__1100_0000, _bitCount: 16)
    }
    o |= c & 0b0__0011_1111
    c &>>= 6
    o &<<= 8
    if _fastPath(c < (1&<<4)) {
      return EncodedScalar(
        _storage: o | c | 0b0__1000_0000__1000_0000__1110_0000, _bitCount: 24)
    }
    o |= c & 0b0__0011_1111
    c &>>= 6
    o &<<= 8
    return EncodedScalar(
      _storage: o | c | 0b0__1000_0000__1000_0000__1000_0000__1111_0000,
      _bitCount: 32)
  }

  @inline(__always)
  public static func transcodeIfRepresentable<FromEncoding : UnicodeEncoding>(
    _ content: FromEncoding.EncodedScalar, from _: FromEncoding.Type
  ) -> EncodedScalar? {
    if _fastPath(FromEncoding.self == UTF16.self) {
      let c = unsafeBitCast(content, to: UTF16.EncodedScalar.self)
      var u0 = UInt16(extendingOrTruncating: c._storage) 
      if _fastPath(u0 < 0x80) {
        return EncodedScalar(containing: UInt8(extendingOrTruncating: u0))
      }
      var r = UInt32(u0 & 0b0__11_1111)
      r &<<= 8
      u0 &>>= 6
      if _fastPath(u0 < (1&<<5)) {
        return EncodedScalar(
          _storage: UInt32(u0) | r | 0b0__1000_0000__1100_0000,
          _bitCount: 16)
      }
      r |= UInt32(u0 & 0b0__11_1111)
      r &<<= 8
      if _fastPath(u0 & (0xF800 &>> 6) != (0xD800 &>> 6)) {
        u0 &>>= 6
        return EncodedScalar(
          _storage: UInt32(u0)
            | r | 0b0__1000_0000__1000_0000__1000_0000__1110_0000,
          _bitCount: 24)
      }
    }
    else if _fastPath(FromEncoding.self == UTF8.self) {
      return unsafeBitCast(content, to: UTF8.EncodedScalar.self)
    }
    return encodeIfRepresentable(FromEncoding.decode(content))
  }

  @_fixed_layout
  public struct ForwardParser {
    public typealias _Buffer = _UIntBuffer<UInt32, UInt8>
    @inline(__always)
    @_inlineable
    public init() { _buffer = _Buffer() }
    public var _buffer: _Buffer
  }
  
  @_fixed_layout
  public struct ReverseParser {
    public typealias _Buffer = _UIntBuffer<UInt32, UInt8>
    @inline(__always)
    @_inlineable
    public init() { _buffer = _Buffer() }
    public var _buffer: _Buffer
  }
}

extension UTF8.ReverseParser : UnicodeParser, _UTFParser {
  public typealias Encoding = _Unicode.UTF8
  @inline(__always)
  @_inlineable
  public func _parseMultipleCodeUnits() -> (isValid: Bool, bitCount: UInt8) {
    _sanityCheck(_buffer._storage & 0x80 != 0) // this case handled elsewhere
    if _buffer._storage                & 0b0__1110_0000__1100_0000
                                      == 0b0__1100_0000__1000_0000 {
      // 2-byte sequence.  Top 4 bits of decoded result must be nonzero
      let top4Bits =  _buffer._storage & 0b0__0001_1110__0000_0000
      if _fastPath(top4Bits != 0) { return (true, 2*8) }
    }
    else if _buffer._storage     & 0b0__1111_0000__1100_0000__1100_0000
                                == 0b0__1110_0000__1000_0000__1000_0000 {
      // 3-byte sequence. The top 5 bits of the decoded result must be nonzero
      // and not a surrogate
      let top5Bits = _buffer._storage & 0b0__1111__0010_0000__0000_0000
      if _fastPath(
        top5Bits != 0 &&    top5Bits != 0b0__1101__0010_0000__0000_0000) {
        return (true, 3*8)
      }
    }
    else if _buffer._storage & 0b0__1111_1000__1100_0000__1100_0000__1100_0000
                            == 0b0__1111_0000__1000_0000__1000_0000__1000_0000 {
      // Make sure the top 5 bits of the decoded result would be in range
      let top5bits = _buffer._storage
                                  & 0b0__0111__0011_0000__0000_0000__0000_0000
      if _fastPath(
        top5bits != 0
        && top5bits <=              0b0__0100__0000_0000__0000_0000__0000_0000
      ) { return (true, 4*8) }
    }
    return (false, _invalidLength() &* 8)
  }

  /// Returns the length of the invalid sequence that ends with the LSB of
  /// buffer.
  @inline(never)
  @_versioned
  func _invalidLength() -> UInt8 {
    if _buffer._storage                 & 0b0__1111_0000__1100_0000
                                       == 0b0__1110_0000__1000_0000 {
      // 2-byte prefix of 3-byte sequence. The top 5 bits of the decoded result
      // must be nonzero and not a surrogate
      let top5Bits = _buffer._storage        & 0b0__1111__0010_0000
      if top5Bits != 0 &&          top5Bits != 0b0__1101__0010_0000 { return 2 }
    }
    else if _buffer._storage               & 0b1111_1000__1100_0000
                                          == 0b1111_0000__1000_0000
    {
      // 2-byte prefix of 4-byte sequence
      // Make sure the top 5 bits of the decoded result would be in range
      let top5bits =        _buffer._storage & 0b0__0111__0011_0000
      if top5bits != 0 &&          top5bits <= 0b0__0100__0000_0000 { return 2 }
    }
    else if _buffer._storage & 0b0__1111_1000__1100_0000__1100_0000
                            == 0b0__1111_0000__1000_0000__1000_0000 {
      // 3-byte prefix of 4-byte sequence
      // Make sure the top 5 bits of the decoded result would be in range
      let top5bits = _buffer._storage & 0b0__0111__0011_0000__0000_0000
      if top5bits != 0 &&   top5bits <= 0b0__0100__0000_0000__0000_0000 {
        return 3
      }
    }
    return 1
  }
  
  @inline(__always)
  @_inlineable
  public func _bufferedScalar(bitCount: UInt8) -> Encoding.EncodedScalar {
    return Encoding.EncodedScalar(
      _storage: _buffer._storage.byteSwapped &>> (32 - bitCount),
      _bitCount: bitCount
    )
  }
}

extension _Unicode.UTF8.ForwardParser : UnicodeParser, _UTFParser {
  public typealias Encoding = _Unicode.UTF8

  @inline(__always)
  @_inlineable
  public func _parseMultipleCodeUnits() -> (isValid: Bool, bitCount: UInt8) {
    _sanityCheck(_buffer._storage & 0x80 != 0) // this case handled elsewhere
    
    if _buffer._storage & 0b0__1100_0000__1110_0000
                       == 0b0__1000_0000__1100_0000 {
      // 2-byte sequence. At least one of the top 4 bits of the decoded result
      // must be nonzero.
      if _fastPath(_buffer._storage & 0b0_0001_1110 != 0) { return (true, 2*8) }
    }
    else if _buffer._storage         & 0b0__1100_0000__1100_0000__1111_0000
                                    == 0b0__1000_0000__1000_0000__1110_0000 {
      // 3-byte sequence. The top 5 bits of the decoded result must be nonzero
      // and not a surrogate
      let top5Bits =          _buffer._storage & 0b0___0010_0000__0000_1111
      if _fastPath(top5Bits != 0 && top5Bits != 0b0___0010_0000__0000_1101) {
        return (true, 3*8)
      }
    }
    else if _buffer._storage & 0b0__1100_0000__1100_0000__1100_0000__1111_1000
                            == 0b0__1000_0000__1000_0000__1000_0000__1111_0000 {
      // 4-byte sequence.  The top 5 bits of the decoded result must be nonzero
      // and no greater than 0b0__0100_0000
      let top5bits = UInt16(_buffer._storage       & 0b0__0011_0000__0000_0111)
      if _fastPath(
        top5bits != 0
        && top5bits.byteSwapped                   <= 0b0__0000_0100__0000_0000
      ) { return (true, 4*8) }
    }
    return (false, _invalidLength() &* 8)
  }

  /// Returns the length of the invalid sequence that starts with the LSB of
  /// buffer.
  @inline(never)
  @_versioned
  func _invalidLength() -> UInt8 {
    if _buffer._storage               & 0b0__1100_0000__1111_0000
                                     == 0b0__1000_0000__1110_0000 {
      // 2-byte prefix of 3-byte sequence. The top 5 bits of the decoded result
      // must be nonzero and not a surrogate
      let top5Bits = _buffer._storage & 0b0__0010_0000__0000_1111
      if top5Bits != 0 && top5Bits   != 0b0__0010_0000__0000_1101 { return 2 }
    }
    else if _buffer._storage                & 0b0__1100_0000__1111_1000
                                           == 0b0__1000_0000__1111_0000
    {
      // Prefix of 4-byte sequence. The top 5 bits of the decoded result
      // must be nonzero and no greater than 0b0__0100_0000
      let top5bits = UInt16(_buffer._storage & 0b0__0011_0000__0000_0111)
      if top5bits != 0 && top5bits.byteSwapped <= 0b0__0000_0100__0000_0000 {
        return _buffer._storage   & 0b0__1100_0000__0000_0000__0000_0000
                                 == 0b0__1000_0000__0000_0000__0000_0000 ? 3 : 2
      }
    }
    return 1
  }
  
  public func _bufferedScalar(bitCount: UInt8) -> Encoding.EncodedScalar {
    var r = _buffer
    r._bitCount = bitCount
    return r
  }
}

