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

