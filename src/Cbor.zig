const std = @import("std");

const Allocator = std.mem.Allocator;

const CborEnum = enum {
    UInt,
    NegInt,
    Bytes,
    Text,
    Array,
    Map,
    Tag,
    Simple
};

pub const CborMapEntry = struct {
    k: *Cbor,
    v: *Cbor
};

pub const CborTag = struct {
    tag: u64,
    data: *Cbor
};

pub const CborSimpleValue = union(enum) {
    boolean: bool,
    undefined: ?void,
    null: ?void,
    float: f64
};

const MajorType = enum(u3) {
    unsigned,
    negative,
    bytes,
    text,
    array,
    map,
    tag,
    float_or_simple,

    const Self = @This();
    fn toNumber( self: Self ) u8
    {
        return switch ( self )
        {
            .unsigned           => 0,
            .negative           => 1,
            .bytes              => 2,
            .text               => 3,
            .array              => 4,
            .map                => 5,
            .tag                => 6,
            .float_or_simple    => 7
        };
    }

    fn fromNumber( n: u3 ) Self
    {
        return switch ( n )
        {
            0 => Self.unsigned,
            1 => Self.negative,
            2 => Self.bytes,
            3 => Self.text,
            4 => Self.array,
            5 => Self.map,
            6 => Self.tag,
            7 => Self.float_or_simple
        };
    }
};

const ByteList = std.ArrayList( u8 );

fn appendUint8( bytes: *ByteList, n: u8 ) Allocator.Error!void
{
    try bytes.append( n );
}

fn appendUint16( bytes: *ByteList, n: u16 ) Allocator.Error!void
{
    try bytes.appendSlice(
        &[2]u8 {
            @truncate( u8, (n & 0xff00) >> 8 ),
            @truncate( u8, n & 0xff )
        }
    );
}

fn appendUint32( bytes: *ByteList, n: u32 ) Allocator.Error!void
{
    try bytes.appendSlice(
        &[4]u8 {
            @truncate( u8, (n & 0xff_00_00_00) >> 24 ),
            @truncate( u8, (n & 0x00_ff_00_00) >> 16 ),
            @truncate( u8, (n & 0x00_00_ff_00) >> 8  ),
            @truncate( u8,  n & 0x00_00_00_ff        )
        }
    );
}

fn appendUint64( bytes: *ByteList, n: u64 ) Allocator.Error!void
{
    try bytes.appendSlice(
        &[8]u8 {
            @truncate( u8, (n & 0xff_00_00_00_00_00_00_00) >> 56 ),
            @truncate( u8, (n & 0x00_ff_00_00_00_00_00_00) >> 48 ),
            @truncate( u8, (n & 0x00_00_ff_00_00_00_00_00) >> 40 ),
            @truncate( u8, (n & 0x00_00_00_ff_00_00_00_00) >> 32 ),
            @truncate( u8, (n & 0x00_00_00_00_ff_00_00_00) >> 24 ),
            @truncate( u8, (n & 0x00_00_00_00_00_ff_00_00) >> 16 ),
            @truncate( u8, (n & 0x00_00_00_00_00_00_ff_00) >> 8  ),
            @truncate( u8, (n & 0x00_00_00_00_00_00_00_ff)       ),
        }
    );
}

fn appendFloat64( bytes: *ByteList, f: f64 ) Allocator.Error!void
{
    try appendUint64( bytes, @bitCast( u64, f ) );
}

fn appendBytes( bytes: *ByteList, toAppend: []u8 ) Allocator.Error!void
{
    try bytes.appendSlice( toAppend );
}

fn appendTypeAndLength( bytes: *ByteList, majorType: MajorType, length: u64 ) Allocator.Error!void
{
    const n: u8 = majorType.toNumber() << 5;

    if( length > 0xffff_ffff )
    {
        try appendUint8( bytes, n | 27 );
        try appendUint64( bytes, length );
        return;
    }

    if( length < 24 )
    {
        try appendUint8( bytes, n | @truncate( u8, length & 0xff ) );
        return;
    }

    if( length < 0x100 )
    {
        try appendUint8( bytes, n | 24 );
        try appendUint8( bytes, @truncate( u8, length ) );
        return;
    }

    if( length < 0x10000 )
    {
        try appendUint8( bytes, n | 25 );
        try appendUint16( bytes, @truncate( u16, length ) );
        return;
    }

    // if (length < 0x100000000)
    try appendUint8( bytes, n | 26 );
    try appendUint32( bytes, @truncate( u32, length ) );
    return;
}

pub const CborArray = struct {
    array: [] const *Cbor,
    indefinite: bool = false
};

pub const CborMap = struct {
    map: []CborMapEntry,
    indefinite: bool = false
};

pub fn cborNumToNegative( n: u64 ) i65
{
    return -@as( i65, n ) - 1;
}

const CborParserError = error {
    InvalidAddtionalInfos,
    UnknownMajoType,
    UnexpectedIndefiniteLength,
    AllocatorOutOfMemory
};

const PtrCborArrList = std.ArrayList(*Cbor); 
const PtrCborMapEntryArrList = std.ArrayList(CborMapEntry); 

const CborParser = struct {
    bytes: []u8,
    offset: usize,

    const Self = @This();

    fn init( bytes: []u8 ) CborParser
    {
        return Self {
            .bytes = bytes,
            .offset = 0
        };
    }

    fn getBytesOfLength( self: *Self, len: usize ) []u8
    {
        self.offset += len;
        return self.bytes[(self.offset - len)..self.offset];
    }

    fn getUint8( self: *Self ) u8
    {
        self.offset += 1;
        return self.bytes[self.offset - 1];
    }

    fn getUint16( self: *Self ) u16
    {
        self.offset += 2;
        var result: u16 = @as( u16, self.bytes[self.offset - 2] ) << 8;
        result |= self.bytes[self.offset - 1];
        return result;
    }

    fn getUint32( self: *Self ) u32
    {
        self.offset += 4;
        var result: u32 = @as( u32, self.bytes[self.offset - 4] ) << 24;
        result |= @as( u32, self.bytes[self.offset - 3] ) << 16;
        result |= @as( u32, self.bytes[self.offset - 2] ) << 8;
        result |= self.bytes[self.offset - 1];
        return result;
    }

    fn getUint64( self: *Self ) u64
    {
        self.offset += 8;
        var result: u64 = @as( u64, self.bytes[self.offset - 8] ) << 56;
        result |= @as( u64, self.bytes[self.offset - 7] ) << 48;
        result |= @as( u64, self.bytes[self.offset - 6] ) << 40;
        result |= @as( u64, self.bytes[self.offset - 5] ) << 32;
        result |= @as( u64, self.bytes[self.offset - 4] ) << 24;
        result |= @as( u64, self.bytes[self.offset - 3] ) << 16;
        result |= @as( u64, self.bytes[self.offset - 2] ) << 8;
        result |= self.bytes[self.offset - 1];
        return result;
    }

    fn getFloat16( self: *Self ) f16
    {
        return @bitCast( f16, self.getUint16() );

        // as f32 below

        // const floatBits: u32 = self.getUint16();
        //
        // const sign =      floatBits & 0b1_00000_0000000000;
        // const exponent =  floatBits & 0b0_11111_0000000000;
        // const fraction =  floatBits & 0b0_00000_1111111111;
        //
        // if (exponent == 0x7c00)
        //     exponent = 0xff << 10
        // else if (exponent != 0)
        //     exponent += (127 - 15) << 10
        // else if (fraction != 0)
        //     return Cbor{
        //         .Simple = CborSimpleValue{
        //             .float = 
        //                 (if( sign != 0) -1 else 1)
        //                 * fraction 
        //                 * 5.960464477539063e-8
        //         } 
        //     };
    }

    fn getFloat32( self: *Self ) f32
    {
        return @bitCast( f32, self.getUint32() );
    }

    fn getFloat64( self: *Self ) f64
    {
        return @bitCast( f64, self.getUint64() );
    }

    fn incrementIfBreak( self: *Self ) bool
    {
        if( self.bytes[ self.offset ] == 0xff ) return false;
        self.offset += 1;
        return true;
    }

    fn getCborLen( self: *Self, headerAddInfos: u5 ) CborParserError!?u64
    {
        if( headerAddInfos <  24 ) return headerAddInfos  ;
        if( headerAddInfos == 24 ) return self.getUint8() ;
        if( headerAddInfos == 25 ) return self.getUint16();
        if( headerAddInfos == 26 ) return self.getUint32();
        if( headerAddInfos == 27 ) return self.getUint64();
        if( headerAddInfos == 31 ) return null;
        return CborParserError.InvalidAddtionalInfos;
    }

    // fn getIndefiniteElemLengthOfType( self: *Self, majorType: MajorType ) CborLen
    // {
    //     _ = majorType;
    //     const headerByte = self.getUint8();
    //     if(  )
    //     return self.getCborLen( @truncate( u5, headerByte ) );
    // }

    fn parseObj( self: *Self, allocator: Allocator ) CborParserError ! Cbor
    {
        const header = self.getUint8();
        const major = MajorType.fromNumber( @truncate( u3, header >> 5 ) );
        const addInfos = @truncate( u5, header & 0b000_11111 );
        const len = try self.getCborLen( addInfos );

        return switch( major )
        {
            .unsigned =>    if (len) |n| Cbor{ .UInt = n }   else CborParserError.UnexpectedIndefiniteLength,
            .negative =>    if (len) |n| Cbor{ .NegInt = n } else CborParserError.UnexpectedIndefiniteLength,
            .bytes =>       if (len) |l| Cbor{ .Bytes = self.getBytesOfLength( l ) } else unreachable, // TODO unreachable
            .text =>        if (len) |l| Cbor{ .Text  = self.getBytesOfLength( l ) } else unreachable, // TODO unreachable,
            .array => {
                var arr = PtrCborArrList.initCapacity( allocator, len orelse 16 ) catch return CborParserError.AllocatorOutOfMemory;
                if( len ) |_|
                {
                    for (arr.items) |_|
                    {
                        var tmp = try self.parseObj( allocator);
                        arr.append( &tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                else
                {
                    while ( !self.incrementIfBreak() )
                    {
                        var tmp = try self.parseObj( allocator);
                        arr.append( &tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                return Cbor{
                    .Array = CborArray{
                        .array = arr.toOwnedSlice() 
                    }
                };
            },
            .map => {
                var map = PtrCborMapEntryArrList.initCapacity( allocator, len orelse 16 ) catch return CborParserError.AllocatorOutOfMemory;
                if( len ) |l|
                {
                    _ = l;
                    for (map.items) |_|
                    {
                        var tmpk = try self.parseObj( allocator );
                        var tmpv = try self.parseObj( allocator );
                        var tmp = CborMapEntry{
                            .k = &tmpk,
                            .v = &tmpv
                        };
                        map.append( tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                else
                {
                    while ( !self.incrementIfBreak() )
                    {
                        var tmpk = try self.parseObj( allocator );
                        var tmpv = try self.parseObj( allocator );
                        var tmp = CborMapEntry{
                            .k = &tmpk,
                            .v = &tmpv
                        };
                        map.append( tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                return Cbor{
                    .Map = CborMap{
                        .map = map.toOwnedSlice()
                    }
                };
            },
            .tag =>
                if( len ) |l|
                {
                    var tmp = try self.parseObj( allocator );
                    return Cbor{ 
                        .Tag = CborTag{ 
                            .tag = l, 
                            .data = &tmp
                        }
                    };
                }
                else return CborParserError.UnexpectedIndefiniteLength,
            .float_or_simple => 
                if( len ) |l| 
                {
                    if( l == 20 ) return Cbor{ .Simple = CborSimpleValue{ .boolean = false } };
                    if( l == 21 ) return Cbor{ .Simple = CborSimpleValue{ .boolean = true } };
                    if( l == 22 ) return Cbor{ .Simple = CborSimpleValue{ .null = null } };
                    if( l == 23 ) return Cbor{ .Simple = CborSimpleValue{ .undefined = null } };
                    if( l == 25 ) return Cbor{ .Simple = CborSimpleValue{ .float = self.getFloat16() } };
                    if( l == 26 ) return Cbor{ .Simple = CborSimpleValue{ .float = self.getFloat32() } };
                    if( l == 27 ) return Cbor{ .Simple = CborSimpleValue{ .float = self.getFloat64() } };
                    return CborParserError.UnexpectedIndefiniteLength;
                }
                else return CborParserError.UnexpectedIndefiniteLength,
        };     

    }
};

pub const Cbor = union(CborEnum) {
    UInt: u64,
    NegInt: u64,
    Bytes: []u8,
    Text: []u8,
    Array: CborArray,
    Map: CborMap,
    Tag: CborTag,
    Simple: CborSimpleValue,

    const Self = @This();

    fn parse( cbor: []u8, allocator: Allocator ) CborParserError!Self
    {
        var parser = CborParser.init( cbor );
        return try parser.parseObj( allocator );
    }

    fn encode( self: Self, allocator: std.mem.Allocator ) Allocator.Error![]u8
    {
        var result = try ByteList.initCapacity( allocator, self.size() );
        defer result.deinit();

        const resultRef = &result;

        switch ( self )
        {
            .UInt => |n| try appendTypeAndLength( resultRef, MajorType.unsigned, n ),
            .NegInt => |n| try appendTypeAndLength( resultRef, MajorType.negative, n ),
            .Bytes => |bs| {
                try appendTypeAndLength( resultRef, MajorType.bytes, bs.len );
                try appendBytes( resultRef, bs );
            },
            .Text => |text| {
                try appendTypeAndLength( resultRef, MajorType.text, text.len );
                try appendBytes( resultRef,text );
            },
            .Array => |cborArr| {
                const arr = cborArr.array;

                if( cborArr.indefinite )
                    try appendUint8( resultRef, 0x9f )
                else 
                    try appendTypeAndLength( resultRef, MajorType.array, arr.len );

                for( arr ) | cbor | {
                    try appendBytes( resultRef,try cbor.encode( allocator )  );
                }

                if( cborArr.indefinite ) try appendUint8( resultRef,0xff );
            },
            .Map => |cborMap| {
                const map = cborMap.map;
                
                if( cborMap.indefinite )
                    try appendUint8( resultRef,0xbf )
                else 
                    try appendTypeAndLength( resultRef, MajorType.map, map.len );

                for( map ) |entry| {
                    try appendBytes( resultRef,try entry.k.encode( allocator ) );
                    try appendBytes( resultRef,try entry.v.encode( allocator ) );
                }

                if( cborMap.indefinite ) try appendUint8( resultRef,0xff );
            },
            .Tag => |tag| {
                try appendTypeAndLength( resultRef, MajorType.tag, tag.tag );
                try appendBytes( resultRef,try tag.data.encode( allocator ) );
            },
            .Simple => |simp| {
                switch( simp )
                {
                    .boolean => |b| if (b) try appendUint8( resultRef, 0xf5 ) else try appendUint8( resultRef,0xf4 ),
                    .undefined => try appendUint8( resultRef, 0xf7 ) ,
                    .null => try appendUint8( resultRef, 0xf6 ) ,
                    .float => |f| {
                        try appendUint8( resultRef, 0xfb ); // (MajorType.float_or_simple << 5) | 27 (double precidison float)
                        try appendFloat64( resultRef, f );
                    },
                }
            }
        }
        
        const slice = result.toOwnedSlice();
        return slice;
    }

    fn size( self: Self ) usize
    {
        return switch( self )
        {
            .UInt => | n | getCborNumSize( n ),
            .NegInt => | n | getCborNumSize( n ),
            .Bytes => | b | getCborNumSize( b.len ) + b.len,
            .Text => |text| getCborNumSize( text.len ) + text.len,
            .Array => |cborArr| {
                
                var s: usize = 0;

                if( cborArr.indefinite ) s += 2 // indefinite byte + 0xff marker
                else s += getCborNumSize( cborArr.array.len );

                for( cborArr.array ) |cbor| s += cbor.size();

                return s;
            },
            .Map => |cborMap| {
                var s: usize = 0;

                if( cborMap.indefinite ) s += 2 // indefinite byte + 0xff marker
                else s += getCborNumSize( cborMap.map.len );

                for( cborMap.map ) |entry|
                {
                    s += entry.k.size() + entry.v.size();
                }

                return s;
            },
            .Tag => |tag| getCborNumSize( tag.tag ) + tag.data.size(),
            .Simple => |simp| {
                return switch( simp )
                {
                    .boolean => 1,
                    .undefined => 1,
                    .null => 1,
                    .float => 9
                };
            }
        };
    }
};

fn getCborNumSize( n: u64 ) usize
{
    if( n <= 23 ) return 1;
    if( n <= 0xff ) return 2;
    if( n <= 0xffff ) return 3;
    if( n <= 0xffffffff ) return 5;
    return 9;
}

const expect = std.testing.expect;

test "simple int" {
    const cbor = Cbor{ .UInt = 23 };

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 1 );
    try expect( encoded[0] == 23 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch (parsed)
        {
            .UInt => |n| n == 23,
            .NegInt => false,
            .Bytes => false,
            .Text => false,
            .Array => false,
            .Map => false,
            .Tag => false,
            .Simple => false,
        }
    );
}

test "two bytes int" {
    const cbor = Cbor{ .UInt = 24 };

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 2 );
    try expect( encoded[0] == 0x18 );
    try expect( encoded[1] == 0x18 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch (parsed)
        {
            .UInt => |n| n == 24,
            .NegInt => false,
            .Bytes => false,
            .Text => false,
            .Array => false,
            .Map => false,
            .Tag => false,
            .Simple => false,
        }
    );
}

test "3 bytes int" {
    const cbor = Cbor{ .UInt = 256 };

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 3 );
    try expect( encoded[0] == 0x19 );
    try expect( encoded[1] == 0x01 );
    try expect( encoded[2] == 0x00 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch (parsed)
        {
            .UInt => |n| n == 256,
            .NegInt => false,
            .Bytes => false,
            .Text => false,
            .Array => false,
            .Map => false,
            .Tag => false,
            .Simple => false,
        }
    );
}