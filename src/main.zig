const std = @import("std");
const cbor = @import("./Cbor.zig");

pub const Cbor = cbor.Cbor;

const expect = std.testing.expect;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try expect(add(3, 7) == 10);
}


test "cbor uint" {

    try expect(
        switch ( Cbor{ .UInt = 42 } ) {
            Cbor.UInt => |n| n,
            Cbor.NegInt => 0,
            Cbor.Bytes => 0,
            Cbor.Text => 0,
            Cbor.Array => 0,
            Cbor.Map => 0,
            Cbor.Tag => 0,
            Cbor.Simple => 0,
        } == 42
    );

}

test "cbor negint" {

    try expect(
        switch ( Cbor{ .NegInt = 42 } ) {
            Cbor.UInt => |n| n,
            Cbor.NegInt => 0,
            Cbor.Bytes => 0,
            Cbor.Text => 0,
            Cbor.Array => 0,
            Cbor.Map => 0,
            Cbor.Tag => 0,
            Cbor.Simple => 0,
        } == 0
    );
    
}