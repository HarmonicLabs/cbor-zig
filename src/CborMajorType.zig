
pub const MajorType = enum(u3) {
    unsigned,
    negative,
    bytes,
    text,
    array,
    map,
    tag,
    float_or_simple,

    const Self = @This();
    pub fn toNumber( self: Self ) u8
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

    pub fn fromNumber( n: u3 ) Self
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
