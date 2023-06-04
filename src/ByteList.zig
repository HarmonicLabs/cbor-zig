const std = @import("std");
const Allocator = std.mem.Allocator;

const MajorType = @import("./CborMajorType.zig").MajorType;

pub const ByteList = std.ArrayList( u8 );

pub fn appendUint8( bytes: *ByteList, n: u8 ) Allocator.Error!void
{
    try bytes.append( n );
}

pub fn appendUint16( bytes: *ByteList, n: u16 ) Allocator.Error!void
{
    try bytes.appendSlice(
        &[2]u8 {
            @truncate( u8, (n & 0xff00) >> 8 ),
            @truncate( u8, n & 0xff )
        }
    );
}

pub fn appendUint32( bytes: *ByteList, n: u32 ) Allocator.Error!void
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

pub fn appendUint64( bytes: *ByteList, n: u64 ) Allocator.Error!void
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

pub fn appendFloat64( bytes: *ByteList, f: f64 ) Allocator.Error!void
{
    try appendUint64( bytes, @bitCast( u64, f ) );
}

pub fn appendBytes( bytes: *ByteList, toAppend: []u8 ) Allocator.Error!void
{
    try bytes.appendSlice( toAppend );
}

pub fn appendTypeAndLength( bytes: *ByteList, majorType: MajorType, length: u64 ) Allocator.Error!void
{
    const n: u8 = @as( u8, majorType.toNumber() ) << 5;

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
