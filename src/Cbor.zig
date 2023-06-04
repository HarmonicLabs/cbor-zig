const std = @import("std");
const Allocator = std.mem.Allocator;

const MajorType = @import("./CborMajorType.zig").MajorType;

const bl = @import("./ByteList.zig");
const ByteList = bl.ByteList;
const appendTypeAndLength = bl.appendTypeAndLength;
const appendBytes = bl.appendBytes;
const appendUint8 = bl.appendUint8;
const appendFloat64 = bl.appendFloat64;

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

pub const CborArray = struct {
    array: []*Cbor,
    indefinite: bool = false
};

pub const CborMapEntry = struct {
    k: *Cbor,
    v: *Cbor
};

pub const CborMap = struct {
    map: []CborMapEntry,
    indefinite: bool = false
};

pub fn cborNumToNegative( n: u64 ) i65
{
    return -@as( i65, n ) - 1;
}

pub const CborParserError = error {
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
        //         .simple = CborSimpleValue{
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

    fn parseObj( self: *Self, allocator: Allocator ) CborParserError ! CborValue
    {
        const header = self.getUint8();
        const major = MajorType.fromNumber( @truncate( u3, header >> 5 ) );
        const addInfos = @truncate( u5, header & 0b000_11111 );
        const len = try self.getCborLen( addInfos );

        return switch( major )
        {
            .unsigned =>    if (len) |n| CborValue{ .uint = n }   else CborParserError.UnexpectedIndefiniteLength,
            .negative =>    if (len) |n| CborValue{ .negint = n } else CborParserError.UnexpectedIndefiniteLength,
            .bytes =>       if (len) |l| CborValue{ .bytes = self.getBytesOfLength( l ) } else unreachable, // TODO this is not unreachable; I'm just lazy
            .text =>        if (len) |l| CborValue{ .text  = self.getBytesOfLength( l ) } else unreachable, // TODO this is not unreachable; I'm just lazy
            .array => {
                var arr = PtrCborArrList.initCapacity( allocator, len orelse 16 ) catch return CborParserError.AllocatorOutOfMemory;
                defer arr.deinit();
                if( len ) |_|
                {
                    for (arr.items) |_|
                    {
                        var tmp = Cbor{
                            .value = try self.parseObj( allocator )
                        };
                        arr.append( &tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                else
                {
                    while ( !self.incrementIfBreak() )
                    {
                        var tmp = Cbor{
                            .value = try self.parseObj( allocator )
                        };
                        arr.append( &tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                return CborValue{
                    .array = CborArray{
                        .array = arr.toOwnedSlice() 
                    }
                };
            },
            .map => {
                var map = PtrCborMapEntryArrList.initCapacity( allocator, len orelse 16 ) catch return CborParserError.AllocatorOutOfMemory;
                defer map.deinit();

                if( len ) |l|
                {
                    _ = l;
                    for (map.items) |_|
                    {
                        var tmpk = Cbor{ .value = try self.parseObj( allocator ) };
                        var tmpv = Cbor{ .value = try self.parseObj( allocator ) };
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
                        var tmpk = Cbor{ .value = try self.parseObj( allocator ) };
                        var tmpv = Cbor{ .value = try self.parseObj( allocator ) };
                        var tmp = CborMapEntry{
                            .k = &tmpk,
                            .v = &tmpv
                        };
                        map.append( tmp ) catch return CborParserError.AllocatorOutOfMemory;
                    }
                }
                return CborValue{
                    .map = CborMap{
                        .map = map.toOwnedSlice()
                    }
                };
            },
            .tag =>
                if( len ) |l|
                {
                    var tmp = Cbor{ .value = try self.parseObj( allocator ) };
                    return CborValue{ 
                        .tag = CborTag{ 
                            .tag = l, 
                            .data = &tmp
                        }
                    };
                }
                else return CborParserError.UnexpectedIndefiniteLength,
            .float_or_simple => 
                if( len ) |l| 
                {
                    if( l == 20 ) return CborValue{ .simple = CborSimpleValue{ .boolean = false } };
                    if( l == 21 ) return CborValue{ .simple = CborSimpleValue{ .boolean = true } };
                    if( l == 22 ) return CborValue{ .simple = CborSimpleValue{ .null = null } };
                    if( l == 23 ) return CborValue{ .simple = CborSimpleValue{ .undefined = null } };
                    if( l == 25 ) return CborValue{ .simple = CborSimpleValue{ .float = self.getFloat16() } };
                    if( l == 26 ) return CborValue{ .simple = CborSimpleValue{ .float = self.getFloat32() } };
                    if( l == 27 ) return CborValue{ .simple = CborSimpleValue{ .float = self.getFloat64() } };
                    return CborParserError.UnexpectedIndefiniteLength;
                }
                else return CborParserError.UnexpectedIndefiniteLength,
        };     

    }
};

pub const CborEnum = enum {
    uint,
    negint,
    bytes,
    text,
    array,
    map,
    tag,
    simple
};

pub const CborValue = union(CborEnum) {
    uint: u64,
    negint: u64,
    bytes: []u8,
    text: []u8,
    array: CborArray,
    map: CborMap,
    tag: CborTag,
    simple: CborSimpleValue,

    const Self = @This();

    /// frees the allocated memory for arrays and maps (if any)
    pub fn free( self: Self, allocator: Allocator ) void
    {
        switch ( self )
        {
            .uint => {},
            .negint => {},
            .bytes => {},
            .text  => {},
            .array => |cbor_arr| allocator.free( cbor_arr.array ),
            .map => |cbor_map| allocator.free( cbor_map.map ),
            .tag => |t| t.data.free( allocator ),
            .simple => {},
        }
    }
};

pub const Cbor = struct {
    /// modifying this field might cause unwanted behaviour
    /// **readonly**
    value: CborValue,
    /// modifying this field might cause unwanted behaviour
    /// use `size()` to read
    _size: ?u64 = null,

    const Self = @This();

    /// used to build an instance manually
    /// you likely will obtain an instance using `Cbor.parse`,
    /// but is nice to have the option
    pub fn init( value: CborValue ) Self
    {
        return Self{
            .value = value,
            ._size = switch (value)
            {
                .uint =>    |n| getCborNumSize( n ),
                .negint =>  |n| getCborNumSize( n ),
                .bytes =>   |b| getCborNumSize( b.len ) + b.len,
                .text =>    |t| getCborNumSize( t.len ) + t.len,
                else => null
            }
        };
    }

    /// frees the allocated memory for arrays and maps (if any)
    pub fn free( self: Self, allocator: Allocator ) Allocator.Error!void
    {
        try self.value.free( allocator ); 
    }

    pub fn uint( value: u64 ) Self
    {
        return Self{
            .value = .{ .uint = value },
            ._size = getCborNumSize( value )
        };
    }

    pub fn negint( value: u64 ) Self
    {
        return Self{
            .value = .{ .negint = value },
            .size  = getCborNumSize( value )
        };
    }

    pub fn bytes( value: []u8 ) Self
    {
        return Self{
            .value = .{ .bytes = value },
            .size  = getCborNumSize( value.len ) + value.len
        };
    }

    pub fn text( value: []u8 ) Self
    {
        return Self{
            .value = .{ .text = value },
            .size  = getCborNumSize( value.len ) + value.len
        };
    }

    pub fn array( value: []*Cbor ) Self
    {
        return Self.init(.{ .array = CborArray{ .array = value } });
    }

    pub fn map( value: []CborMapEntry ) Self
    {
        return Self.init(.{ .map = CborMap{ .map = value } });
    }

    pub fn tag( value: CborTag ) Self
    {
        return Self.init(.{ .tag = value });
    }

    pub fn simple( value: CborSimpleValue ) Self
    {
        return Self.init(.{ .simple = value });
    }

    /// parses the given bytes as CBOR
    pub fn parse( cbor: []u8, allocator: Allocator ) CborParserError!Self
    {
        var parser = CborParser.init( cbor );
        return Self{
            .value = try parser.parseObj( allocator ),
            ._size = cbor.len + (cbor.len / 10)
        };
    }

    /// encodes the CBOR as bytes; the caller has ownership of the result
    pub fn encode( self: *Self, allocator: Allocator ) Allocator.Error![]u8
    {
        // needs to be a `ArrayList(u8)` even if we know the size because
        // anyone whom uses the Cbor class *might* (even if they shouldn't)
        // modify the `_size` protpery
        var result = try ByteList.initCapacity( allocator, self.size() );
        defer result.deinit();

        const resultRef = &result;

        switch ( self.value )
        {
            .uint => |n|   try appendTypeAndLength( resultRef, MajorType.unsigned, n ),
            .negint => |n| try appendTypeAndLength( resultRef, MajorType.negative, n ),
            .bytes => |bs| {
                try appendTypeAndLength( resultRef, MajorType.bytes, bs.len );
                try appendBytes( resultRef, bs );
            },
            .text => |txt| {
                try appendTypeAndLength( resultRef, MajorType.text, txt.len );
                try appendBytes( resultRef, txt );
            },
            .array => |cborArr| {
                const arr = cborArr.array;

                if( cborArr.indefinite )
                    try appendUint8( resultRef, 0x9f )
                else 
                    try appendTypeAndLength( resultRef, MajorType.array, arr.len );

                for( arr ) | cbor | {
                    var encodedElem = try cbor.encode( allocator );
                    
                    try resultRef.appendSlice( encodedElem );
                    
                    // `appendSlice` allocates new memory (if necessary) and clones the elements
                    // se here we MUST free as we still have ownership of the bytes.
                    allocator.free( encodedElem );
                }

                if( cborArr.indefinite ) try appendUint8( resultRef,0xff );
            },
            .map => |cborMap| {
                const mp = cborMap.map;
                
                if( cborMap.indefinite )
                    try appendUint8( resultRef,0xbf )
                else 
                    try appendTypeAndLength( resultRef, MajorType.map, mp.len );

                for( mp ) |entry| {
                    var encodedElem = try entry.k.encode( allocator );

                    try resultRef.appendSlice( encodedElem );

                    // `appendSlice` allocates new memory (if necessary) and clones the elements
                    // se here we MUST free as we still have ownership of the bytes.
                    allocator.free( encodedElem );

                    encodedElem = try entry.v.encode( allocator );

                    try resultRef.appendSlice( encodedElem );

                    // see comment above
                    allocator.free( encodedElem );
                }

                if( cborMap.indefinite ) try appendUint8( resultRef, 0xff );
            },
            .tag => |t| {
                try appendTypeAndLength( resultRef, MajorType.tag, t.tag );
                try appendBytes( resultRef,try t.data.encode( allocator ) );
            },
            .simple => |simp| {
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

    pub fn size( self: *Self ) usize
    {
        if( self._size ) |sz| return sz;

        self._size = switch( self.value )
        {
            .uint => | n | getCborNumSize( n ),
            .negint => | n | getCborNumSize( n ),
            .bytes => | b | getCborNumSize( b.len ) + b.len,
            .text => |txt| getCborNumSize( txt.len ) + txt.len,
            .array => |cborArr| blk: {
                
                var s: usize = 0;

                if( cborArr.indefinite ) s += 2 // indefinite byte + 0xff marker
                else s += getCborNumSize( cborArr.array.len );

                for( cborArr.array ) |cbor| s += cbor.size();

                break :blk s;
            },
            .map => |cborMap| blk: {
                var s: usize = 0;

                if( cborMap.indefinite ) s += 2 // indefinite byte + 0xff marker
                else s += getCborNumSize( cborMap.map.len );

                for( cborMap.map ) |entry|
                {
                    s += entry.k.size() + entry.v.size();
                }

                break :blk s;
            },
            .tag => |t| getCborNumSize( t.tag ) + t.data.size(),
            .simple => |simp| switch( simp )
            {
                .boolean => 1,
                .undefined => 1,
                .null => 1,
                .float => 9
            }
        };

        return self._size orelse unreachable;
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
    var cbor = Cbor.init(.{ .uint = 23 });

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 1 );
    try expect( encoded[0] == 23 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch (parsed.value)
        {
            .uint => |n| n == 23,
            else => false
        }
    );
}

test "two bytes int" {
    var cbor = Cbor.init(.{ .uint = 24 });

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 2 );
    try expect( encoded[0] == 0x18 );
    try expect( encoded[1] == 0x18 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch( parsed.value )
        {
            .uint => |n| n == 24,
            .negint => false,
            .bytes => false,
            .text => false,
            .array => false,
            .map => false,
            .tag => false,
            .simple => false,
        }
    );
}

test "3 bytes int" {
    var cbor = Cbor.init(.{ .uint = 256 });

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 3 );
    try expect( encoded[0] == 0x19 );
    try expect( encoded[1] == 0x01 );
    try expect( encoded[2] == 0x00 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch( parsed.value )
        {
            .uint => |n| n == 256,
            else  => false
        }
    );
}

test "bytes" {

    const allocator: Allocator = std.testing.allocator;
    var bytes: []u8 = try allocator.alloc( u8, 3 );
    defer allocator.free( bytes );
    
    bytes[0] = 1;
    bytes[1] = 2;
    bytes[2] = 3;

    var cbor = Cbor.init(.{ .bytes = bytes });

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    try expect( encoded.len == 4 );
    try expect( encoded[1] == 1 );
    try expect( encoded[2] == 2 );
    try expect( encoded[3] == 3 );

    const parsed = try Cbor.parse( encoded, std.testing.allocator );
    
    try expect(
        switch( parsed.value )
        {
            .bytes => |b| blk: {

                try expect( b.len == 3 );
                try expect( b[0] == 1 );
                try expect( b[1] == 2 );
                try expect( b[2] == 3 );

                break :blk true;
            },
            else  => false
        }
    );
}

test "arr" {

    const allocator: Allocator = std.testing.allocator;
    
    var array: []*Cbor = try allocator.alloc( *Cbor, 1 );
    defer allocator.free( array );

    var elem: Cbor = Cbor.uint( 1 );
    array[0] = &elem;
    
    var cbor = Cbor.array( array );

    std.debug.print("\n{d}\n", .{ cbor.size() });

    const encoded = try cbor.encode( std.testing.allocator );
    defer std.testing.allocator.free( encoded );

    var parsed = try Cbor.parse( encoded, std.testing.allocator );
    defer parsed.value.free( allocator );
    
    try expect(
        switch( parsed.value )
        {
            .array => true,
            else   =>  false
        }
    );
}