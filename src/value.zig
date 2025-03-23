const std = @import("std");

const ast = @import("ast.zig");
const Environment = @import("environment.zig").Environment;
const RuntimeError = @import("eval.zig").RuntimeError;

pub const Object = union(enum) {
    integer: i64,
    boolean: bool,
    null_,
    return_: *Object,
    error_: []const u8,
    function: Function,

    var null_object = Object{ .null_ = {} };
    var true_object = Object{ .boolean = true };
    var false_object = Object{ .boolean = false };

    pub const Null = &null_object;
    pub const True = &true_object;
    pub const False = &false_object;

    pub const Function = struct {
        parameters: std.ArrayList(ast.Identifier),
        body: *ast.Block,
        env: *Environment,

        pub fn print(self: Function, writer: anytype) !void {
            try writer.print("fn(", .{});
            for (self.parameters.items, 1..) |param, i| {
                try writer.print("{s}", .{param.value});
                if (i < self.parameters.items.len) {
                    try writer.print(", ", .{});
                }
            }
            try writer.print(")", .{});
        }
    };

    pub fn typeName(self: Object) []const u8 {
        return @tagName(self);
    }

    pub fn repr(self: Object, writer: anytype) !void {
        switch (self) {
            .null_ => try writer.print("null", .{}),
            .integer => |integer| try writer.print("{d}", .{integer}),
            .boolean => |boolean| {
                const str = if (boolean) "true" else "false";
                try writer.print("{s}", .{str});
            },
            .error_ => |error_| try writer.print("\"{s}\"", .{error_}),
            .function => |function| try function.print(writer),
            .return_ => unreachable,
        }
    }

    pub fn typedRepr(self: Object, writer: anytype) !void {
        try writer.print("{s}(", .{self.typeName()});
        try self.repr(writer);
        try writer.print(")", .{});
    }

    pub fn new(allocator: std.mem.Allocator, object: Object) RuntimeError!*Object {
        const ptr = allocator.create(Object) catch return RuntimeError.OutOfMemory;
        ptr.* = object;
        return ptr;
    }

    pub fn create(allocator: std.mem.Allocator) RuntimeError!*Object {
        const ptr = allocator.create(Object) catch return RuntimeError.OutOfMemory;
        return ptr;
    }

    pub fn compare(self: Object, other: Object) bool {
        return switch (self) {
            .null_ => other == .null_,
            .integer => |a| switch (other) {
                .integer => |b| a == b,
                else => false,
            },
            .boolean => |a| switch (other) {
                .boolean => |b| a == b,
                else => false,
            },
            .error_ => |a| switch (other) {
                .error_ => |b| std.mem.eql(u8, a, b),
                else => false,
            },
            else => @panic("illegal comparison"),
        };
    }

    pub fn isError(self: Object) bool {
        return switch (self) {
            .error_ => true,
            else => false,
        };
    }
};
