const std = @import("std");
const testing = std.testing;

pub fn parseJson(json: []const u8, thing: anytype, allocator: std.mem.Allocator) !void {
    const type_info = @typeInfo(@TypeOf(thing));
    switch (type_info) {
        .Pointer => {
            const strct = type_info.Pointer.child;
            try parseInto(strct, json, thing, allocator);
        },
        else => @compileError("not a pointer inside of a json parser"),
    }
}

fn setThing(T: type, thing: *T, value: JSONValue, allocator: std.mem.Allocator) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Struct => {
            switch (value) {
                .J_Object => {
                    var obj_iter = value.J_Object;
                    const first = try obj_iter.first(allocator);
                    if (first) |v| inline for (info.Struct.fields) |field| {
                        if (std.mem.eql(u8, field.name, v.key)) {
                            try setThing(field.type, &@field(thing, field.name), v.value.*, allocator);
                            break;
                        }
                    };

                    while (try obj_iter.more()) {
                        const v = try obj_iter.next(allocator);
                        inline for (info.Struct.fields) |field| {
                            if (std.mem.eql(u8, field.name, v.key)) {
                                try setThing(field.type, &@field(thing, field.name), v.value.*, allocator);
                                break;
                            }
                        }
                    }
                },
                else => return JSONParseError.BadType,
            }
        },
        .Pointer => {
            switch (info.Pointer.size) {
                .Slice, .Many => {
                    if (info.Pointer.child == u8) {
                        if (info.Pointer.is_const) {
                            thing.* = value.J_String;
                        } else {
                            const copied_string = try allocator.alloc(u8, value.J_String.len);
                            @memcpy(copied_string, value.J_String);
                            thing.* = copied_string;
                        }
                    } else {
                        switch (value) {
                            .J_Array => {
                                const arr_iter = value.J_Array;
                                var arr_list = std.ArrayList(info.Pointer.child).init(allocator);
                                const first = try arr_iter.first(allocator);
                                if (first) |v|
                                    try setThing(info.Pointer.child, try arr_list.addOne(), v, allocator);

                                while (try arr_iter.more()) try setThing(
                                    info.Pointer.child,
                                    try arr_list.addOne(),
                                    try arr_iter.next(allocator),
                                    allocator,
                                );
                                thing.* = arr_list.items;
                            },
                            else => return JSONParseError.ExpectedArray,
                        }
                    }
                },
                .One => {
                    const copy = try allocator.create(info.Pointer.child);
                    try setThing(info.Pointer.child, copy, value, allocator);
                    thing.* = copy;
                },
                .C => @compileError("bad pointer type"),
            }
        },
        .Int => {
            switch (value) {
                .J_Number => thing.* = try std.fmt.parseInt(T, value.J_Number, 0),
                else => @panic("bad thing"),
            }
        },
        .Float => {
            switch (value) {
                .J_Number => thing.* = try std.fmt.parseFloat(T, value.J_Number),
                else => @panic("bad thing"),
            }
        },
        .Bool => {
            switch (value) {
                .J_Bool => thing.* = value.J_Bool,
                else => @panic("bad thing"),
            }
        },
        else => {
            std.debug.panic("type: {}\n", .{info});
        },
    }
}

fn parseInto(T: type, json: []const u8, thing: *T, allocator: std.mem.Allocator) !void {
    var iter = JSONIterator{
        .text = json,
    };
    const val = try iter.next(false, allocator);
    try setThing(T, thing, val, allocator);
}

const JSONValueType = enum {
    J_Object,
    J_Key_Value,
    J_Array,
    J_Number,
    J_String,
    J_Null,
    J_Bool,
};

const JSONKeyValue = struct {
    key: []const u8,
    value: *JSONValue,
};

const JSONValue = union(JSONValueType) {
    J_Object: JSONObjectIterator,
    J_Key_Value: JSONKeyValue,
    J_Array: JSONArrayIterator,
    J_Number: []const u8,
    J_String: []const u8,
    J_Null: void,
    J_Bool: bool,
};

pub const JSONParseError = error{
    BadToken,
    BadType,
    UnexpectedEOF,
    ExpectedEOF,
    ExpectedArray,
};

const JSONArrayIterator = struct {
    iter: *JSONIterator,

    pub fn next(self: JSONArrayIterator, allocator: std.mem.Allocator) !JSONValue {
        return try self.iter.next(false, allocator);
    }

    pub fn first(self: JSONArrayIterator, allocator: std.mem.Allocator) !?JSONValue {
        if (self.iter.peek(0)) |c| {
            if (c == ']') return null;
        } else return JSONParseError.UnexpectedEOF;

        return try self.iter.next(false, allocator);
    }

    pub fn more(self: JSONArrayIterator) !bool {
        self.iter.trimLeft();
        if (self.iter.peek(0)) |c| {
            switch (c) {
                ',' => {
                    _ = self.iter.advanceChar() orelse return JSONParseError.BadToken;
                    return true;
                },
                ']' => {
                    _ = self.iter.advanceChar() orelse return JSONParseError.BadToken;
                    return false;
                },
                else => {
                    std.debug.print("token more: {c}\n", .{c});
                    return JSONParseError.BadToken;
                },
            }
        } else return JSONParseError.UnexpectedEOF;
    }
};

const JSONObjectIterator = struct {
    iter: *JSONIterator,

    pub fn next(self: JSONObjectIterator, allocator: std.mem.Allocator) !JSONKeyValue {
        return try self.iter.next(true, allocator);
    }
    pub fn first(self: JSONObjectIterator, allocator: std.mem.Allocator) !?JSONKeyValue {
        if (self.iter.peek(0)) |c| {
            if (c == '}') return null;
        } else return JSONParseError.UnexpectedEOF;

        return try self.iter.next(true, allocator);
    }

    pub fn more(self: JSONObjectIterator) !bool {
        self.iter.trimLeft();
        if (self.iter.peek(0)) |c| {
            switch (c) {
                ',' => {
                    _ = self.iter.advanceChar() orelse return JSONParseError.BadToken;
                    return true;
                },
                '}' => {
                    _ = self.iter.advanceChar() orelse return JSONParseError.BadToken;
                    return false;
                },
                else => {
                    std.debug.print("token more: {c}\n", .{c});
                    return JSONParseError.BadToken;
                },
            }
        } else return JSONParseError.UnexpectedEOF;
    }
};

const JSONIterator = struct {
    cursor: usize = 0,
    text: []const u8,

    inline fn trimLeft(self: *JSONIterator) void {
        while (std.ascii.isWhitespace(self.peek(0) orelse return))
            self.cursor += 1;
    }

    fn expectEOF(self: *JSONIterator) !void {
        if (self.advanceChar()) |_|
            return JSONParseError.ExpectedEOF;
    }

    fn expectColon(self: *JSONIterator) !void {
        if (self.advanceChar()) |c| if (c != ':')
            return JSONParseError.BadToken;
    }

    fn peek(self: *JSONIterator, num: usize) ?u8 {
        if (self.cursor + num < self.text.len)
            return self.text[self.cursor + num];
        return null;
    }

    fn advanceChar(self: *JSONIterator) ?u8 {
        if (self.cursor != self.text.len) {
            defer self.cursor += 1;
            return self.text[self.cursor];
        }
        return null;
    }

    pub fn next(self: *JSONIterator, comptime expect_keyval: bool, allocator: std.mem.Allocator) !if (expect_keyval) JSONKeyValue else JSONValue {
        self.trimLeft();
        if (expect_keyval) {
            const key = try self.next(false, allocator);
            switch (key) {
                .J_String => {
                    try self.expectColon();
                    const value_box = try allocator.create(JSONValue);
                    value_box.* = try self.next(false, allocator);
                    return JSONKeyValue{
                        .key = key.J_String,
                        .value = value_box,
                    };
                },
                else => return JSONParseError.BadToken,
            }
        } else if (self.advanceChar()) |cur| switch (cur) {
            '[' => return JSONValue{ .J_Array = JSONArrayIterator{ .iter = self } },
            '{' => return JSONValue{ .J_Object = JSONObjectIterator{ .iter = self } },
            '"' => {
                if (self.peek(0) == null)
                    return JSONParseError.BadToken;
                const start = self.cursor;
                _ = self.advanceChar();
                while (true) if (self.peek(0)) |c| {
                    _ = self.advanceChar();
                    if (c == '"') return JSONValue{
                        .J_String = self.text[start .. self.cursor - 1],
                    };
                } else return JSONParseError.BadToken;
            },
            '0'...'9' => {
                const start = self.cursor - 1;
                var is_float = false;
                while (true) if (self.peek(0)) |char| switch (char) {
                    '0'...'9' => _ = self.advanceChar(),
                    '.' => {
                        if (is_float) return JSONParseError.BadToken;
                        is_float = true;
                        _ = self.advanceChar();
                    },
                    else => {
                        return JSONValue{
                            .J_Number = self.text[start..self.cursor],
                        };
                    },
                } else return JSONValue{
                    .J_Number = self.text[start..self.cursor],
                };
            },
            't' => {
                if (self.cursor + 3 < self.text.len and
                    self.text[self.cursor] == 'r' and
                    self.text[self.cursor + 1] == 'u' and
                    self.text[self.cursor + 2] == 'e')
                {
                    self.cursor += 3;
                    return JSONValue{ .J_Bool = true };
                } else return JSONParseError.BadToken;
            },
            'f' => {
                if (self.cursor + 4 < self.text.len and
                    self.text[self.cursor] == 'a' and
                    self.text[self.cursor + 1] == 'l' and
                    self.text[self.cursor + 2] == 's' and
                    self.text[self.cursor + 3] == 'e')
                {
                    self.cursor += 4;
                    return JSONValue{ .J_Bool = false };
                } else return JSONParseError.BadToken;
            },
            else => {
                std.debug.print("kek: {c}\n", .{cur});
                return JSONParseError.BadToken;
            },
        } else return JSONParseError.UnexpectedEOF;
    }
};
