const std = @import("std");
const AllocFailed = @import("evaluator.zig").EvaluatorError.AllocFailed;

pub const Object = union(enum) {
    integer: Integer,
    boolean: Boolean,
    null_: Null,
    return_: Return,

    const Self = @This();

    pub fn inspect(self: *Self, writer: anytype) anyerror!void {
        switch (self.*) {
            .null_ => |null_| try null_.inspect(writer),
            .integer => |integer| try integer.inspect(writer),
            .boolean => |boolean| try boolean.inspect(writer),
            .return_ => unreachable,
        }
    }

    pub fn typeName(self: Self) []const u8 {
        return switch (self) {
            .null_ => "Null",
            .integer => "Integer",
            .boolean => "Boolean",
        };
    }

    // pub fn newInteger(allocator: std.mem.Allocator, value: i64) !*Object {
    //     const object = allocator.create(Object) catch return AllocFailed;
    //     object.* = Object{
    //         .integer = Integer.new(value),
    //     };
    //     return object;
    // }
};

pub const Integer = struct {
    value: i64,

    pub fn new(value: i64) Integer {
        return .{ .value = value };
    }

    pub fn inspect(self: Integer, writer: anytype) anyerror!void {
        try writer.print("{d}", .{self.value});
    }

    pub fn create(allocator: std.mem.Allocator, value: i64) !*Object {
        const object = allocator.create(Object) catch return AllocFailed;
        object.* = Object{
            .integer = Integer.new(value),
        };
        return object;
    }
};

pub const Boolean = struct {
    value: bool,

    pub fn new(value: bool) Boolean {
        return .{ .value = value };
    }

    pub fn inspect(self: Boolean, writer: anytype) anyerror!void {
        try writer.print("{}", .{self.value});
    }

    pub fn create(allocator: std.mem.Allocator, value: bool) !*Object {
        const object = allocator.create(Object) catch return AllocFailed;
        object.* = Object{
            .integer = Boolean.new(value),
        };
        return object;
    }
};

pub const Null = struct {
    pub fn inspect(writer: anytype) anyerror!void {
        try writer.print("null", .{});
    }
};

pub const Return = struct {
    value: *Object,
};
