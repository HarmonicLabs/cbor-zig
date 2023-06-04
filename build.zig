const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const cbor_zig = b.addModule("cbor_zig", .{
        .source_file = .{ .path = "src/index.zig" },
    });
    
    try b.modules.put(b.dupe("zbor"), cbor_zig);

    // Creates a step for unit testing.
    const lib_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/Cbor.zig" },
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
}
