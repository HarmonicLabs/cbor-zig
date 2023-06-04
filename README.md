# cbor-zig

<small> with ❤️ by Harmonic Labs </small>

## Installation

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

## Getting started

The main export of the package is the `Cbor` struct; you can import it as follows:

```zig
const cbor = @import("cbor_zig");
const Cbor = cbor.Cbor;
```

`Cbor`'s instance interface looks like this

```zig
pub const Cbor = struct {
    /// modifying this field might cause undefined behaviour
    /// **readonly**
    value: CborValue,
    /// modifying this field might cause undefined behaviour
    /// use `size()` to read
    _size: ?u64 = null,

    const Self = @This();

    /// used to build an instance manually
    /// you likely will obtain an instance using `Cbor.parse`,
    /// but is nice to have the option
    pub fn init( value: CborValue ) Self

    /// frees the allocated memory for arrays and maps (if any)
    pub fn free( self: Self, allocator: Allocator ) Allocator.Error!void

    // utilites to build an instance manually
    // all of them use `init` internally, but you only specify the value
    pub fn uint( value: u64 ) Self
    pub fn negint( value: u64 ) Self
    pub fn bytes( value: []u8 ) Self
    pub fn text( value: []u8 ) Self
    pub fn array( value: []*Cbor ) Self
    pub fn map( value: []CborMapEntry ) Self
    pub fn tag( value: CborTag ) Self
    pub fn simple( value: CborSimpleValue ) Self

    /// parses the given bytes as CBOR
    pub fn parse( cbor: []u8, allocator: Allocator ) CborParserError!Self

    /// encodes the CBOR as bytes; the caller has ownership of the result
    pub fn encode( self: *Self, allocator: Allocator ) Allocator.Error![]u8
};
```

as you see, internally the `Cbor` struct keeps track of a `CborValue` and the (estimated) size of the encoded result.

A `CborValue` will also be needed if ever you'll find yourself building CBOR manually; the definition is a simple union.

```zig
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
    simple: CborSimpleValue
};

// non-trivial types definitions: 

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
```