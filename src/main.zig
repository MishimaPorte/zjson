const std = @import("std");
const zjson = @import("zjson.zig");

const MyType = struct {
    id: *struct {
        sub_id: bool,
        sub_name: []u8,
    },
    auf: f64,
    kekers: []struct { name: []u8, age: usize, auf: f64 },
};

pub fn main() !void {
    var buffer: [100000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var kek: MyType = undefined;
    try zjson.parseJson(
        \\{
        \\  "id": {
        \\    "sub_id": false,
        \\    "sub_name": "kekov kek"
        \\  },
        \\  "auf": 12.12,
        \\  "name": "asca",
        \\  "kekers": [{"name":"auf", "age": 12, "auf": 123},{"name":"auf2", "age": 123, "auf": 123.123}]
        \\}
    , &kek, allocator);
    std.debug.print("thing: {any:}, kek.id: {any}\n", .{ kek.kekers, kek });
}
