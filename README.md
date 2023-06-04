# cbor-zig

<small> with ❤️ by Harmonic Labs </small>

## Getting started

To use this library you can either add it directly as a module in your project
or use the Zig package manager to fetch it as dependency.

### Zig package manager

First add this library as dependency to your `build.zig.zon` file:

```zon
.{
    .name = "your-project",
    .version = 0.0.1,

    .dependencies = .{
        .cbor_zig = .{
            .url = "https://github.com/HarmonicLabs/cbor-zig",
            .hash = "check the release hash on github",
        }
    },
}
```

### As a module

First add the library to your project, e.g., as a submodule:

```shell
mkdir libs
git submodule add https://github.com/r4gus/cbor_zig.git libs/cbor_zig
```

Then add the following line to your `build.zig` file.

```zig
// Create a new module
var cbor_zig_module = b.createModule(.{
    .source_file = .{ .path = "libs/cbor_zig/src/main.zig" },
});

// create your exe ...

// Add the module to your exe/ lib
exe.addModule("cbor_zig", cbor_zig_module);
```