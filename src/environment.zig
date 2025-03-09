const std = @import("std");

const Object = @import("value.zig").Object;
const RuntimeError = @import("eval.zig").RuntimeError;

pub const Environment = struct {
    scope: std.StringHashMap(*Object),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn new(allocator: std.mem.Allocator) Self {
        return .{
            .scope = std.StringHashMap(*Object).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn get(self: Self, key: []const u8) ?*Object {
        return self.scope.get(key);
    }

    pub fn set(self: *Self, key: []const u8, value: *Object) RuntimeError!void {
        self.scope.put(key, value) catch return RuntimeError.OutOfMemory;
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
