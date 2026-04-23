const std = @import("std");

const Object = @import("value.zig").Object;
const RuntimeError = @import("evaluator.zig").RuntimeError;

pub const Environment = struct {
    outer: ?*Environment,
    store: std.StringHashMap(*Object),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn new(allocator: std.mem.Allocator) Self {
        return .{
            .outer = null,
            .store = std.StringHashMap(*Object).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn newEnclosed(allocator: std.mem.Allocator, outer: *Environment) Self {
        return .{
            .outer = outer,
            .store = std.StringHashMap(*Object).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn get(self: Self, key: []const u8) ?*Object {
        const value = self.store.get(key);
        if (value != null) {
            return value;
        }

        if (self.outer) |env| {
            return env.get(key);
        }

        return null;
    }

    pub fn set(self: *Self, key: []const u8, value: *Object) RuntimeError!void {
        self.store.put(key, value) catch return RuntimeError.OutOfMemory;
    }
};

test "get" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var env = Environment.new(arena.allocator());

    {
        const object = try Object.new(arena.allocator(), .{ .boolean = true });
        try env.set("test_bool", object);

        var object2 = Object{ .boolean = true };
        try env.set("test_bool_2", &object2);
    }

    const res = env.get("test_bool");
    try std.testing.expectEqual(true, res.?.boolean);

    const res2 = env.get("test_bool_2");
    try std.testing.expectEqual(true, res2.?.boolean);
}

test "get enclosed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var outer_val = Object{ .integer = 1 };
    var inner_val = Object{ .integer = 2 };

    var outer_env = Environment.new(arena.allocator());
    var inner_env = Environment.newEnclosed(arena.allocator(), &outer_env);

    try outer_env.set("object", &outer_val);
    try inner_env.set("object", &inner_val);

    try std.testing.expectEqual(inner_val, inner_env.get("object").?.*);
}
