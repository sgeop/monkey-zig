const std = @import("std");
const ast = @import("ast.zig");
const object = @import("object.zig");
const builtin = @import("builtin.zig");

pub const RuntimeError = error{
    OutOfMemory,
    IllegalValue,
    TypeMismatch,
    NotImplemented,
};

pub const Evaluator = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn new(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn eval(self: *Self, node: ast.Node) RuntimeError!*object.Object {
        switch (node) {
            .program => |program| return try self.evalProgram(program),
            .statement => |statement| return try self.evalStatement(statement),
            .expression => |expression| return try self.evalExpression(expression),
        }
    }

    pub fn evalProgram(self: *Self, program: *ast.Program) RuntimeError!*object.Object {
        var result: *object.Object = &builtin.NULL_OBJECT;
        var i: usize = 0;
        while (i < program.statements.items.len) : (i += 1) {
            const evaled = try self.evalStatement(&program.statements.items[i]);
            switch (evaled.*) {
                .return_ => |return_| return return_.value,
                else => result = evaled,
            }
        }

        return result;
    }

    pub fn evalStatement(self: *Self, statement: *ast.Statement) RuntimeError!*object.Object {
        switch (statement.*) {
            .expression_statement => |expression_statement| return self.evalExpression(expression_statement.expression),
            .return_ => |return_| {
                const value = try self.evalExpression(return_.value);

                const obj = self.allocator.create(object.Object) catch return RuntimeError.OutOfMemory;
                obj.* = object.Object{
                    .return_ = object.Return{
                        .value = value,
                    },
                };

                return obj;
            },
            else => return RuntimeError.IllegalValue,
        }
    }

    pub fn evalExpression(self: *Self, expression: *ast.Expression) RuntimeError!*object.Object {
        switch (expression.*) {
            .integer => |integer| {
                const obj = object.Integer.create(self.allocator, integer.value);
                return obj;
            },
            .prefix_expression => |prefix_expression| {
                const right = try self.evalExpression(prefix_expression.right);

                return try self.evalPrefixExpression(prefix_expression.operator, right);
            },
            .infix_expression => |infix_expression| {
                const right = try self.evalExpression(infix_expression.right);
                const left = try self.evalExpression(infix_expression.left);

                return try self.evalInfixExpression(&infix_expression.operator, left, right);
            },
            .if_ => |*if_| return try self.evalIfExpression(if_),
            else => return RuntimeError.IllegalValue,
        }
    }

    fn evalBlock(self: *Self, block: *ast.Block) RuntimeError!*object.Object {
        var result: *object.Object = &builtin.NULL_OBJECT;
        var i: usize = 0;
        while (i < block.statements.items.len) : (i += 1) {
            result = try self.evalStatement(&block.statements.items[i]);
        }

        return result;
    }

    fn evalIfExpression(self: *Self, ifexp: *ast.If) RuntimeError!*object.Object {
        const condition = try self.evalExpression(ifexp.*.condition);

        if (isTruthy(condition)) {
            return try self.evalBlock(&ifexp.*.then_branch);
        } else if (ifexp.*.else_branch) |*else_branch| {
            return try self.evalBlock(else_branch);
        } else {
            return &builtin.NULL_OBJECT;
        }
    }

    fn evalPrefixExpression(self: *Self, operator: ast.Operator, right: *object.Object) RuntimeError!*object.Object {
        switch (operator) {
            .bang => return evalBangOperatorExpression(right),
            .minus => return try self.evalMinusPrefixOperatorExpression(right),
            else => return RuntimeError.NotImplemented,
        }
    }

    fn evalInfixExpression(self: *Self, operator: *const ast.Operator, left: *object.Object, right: *object.Object) RuntimeError!*object.Object {
        switch (left.*) {
            .integer => |left_int| switch (right.*) {
                .integer => |right_int| return try self.evalIntegerInfixExpression(operator, &left_int, &right_int),
                else => return RuntimeError.TypeMismatch,
            },
            else => return RuntimeError.NotImplemented,
        }
    }

    fn evalMinusPrefixOperatorExpression(self: *Self, right: *object.Object) RuntimeError!*object.Object {
        switch (right.*) {
            .integer => |integer| return object.Integer.create(self.allocator, -integer.value) catch return RuntimeError.OutOfMemory,
            else => return RuntimeError.NotImplemented,
        }
    }

    fn evalIntegerInfixExpression(
        self: *Self,
        operator: *const ast.Operator,
        left: *const object.Integer,
        right: *const object.Integer,
    ) RuntimeError!*object.Object {
        switch (operator.*) {
            .plus => return object.Integer.create(self.allocator, left.*.value + right.*.value),
            .minus => return object.Integer.create(self.allocator, left.*.value - right.*.value),
            .asterisk => return object.Integer.create(self.allocator, left.*.value * right.*.value),
            .slash => return object.Integer.create(self.allocator, @divFloor(left.*.value, right.*.value)),
            .lt => return nativeBoolToBooleanObject(left.*.value < right.*.value),
            .gt => return nativeBoolToBooleanObject(left.*.value > right.*.value),
            .equal => return nativeBoolToBooleanObject(left.*.value == right.*.value),
            .not_equal => return nativeBoolToBooleanObject(left.*.value != right.*.value),
            else => return RuntimeError.NotImplemented,
        }
    }

    fn evalBangOperatorExpression(right: *object.Object) *object.Object {
        switch (right.*) {
            .boolean => |boolean| {
                return if (boolean.value) &builtin.FALSE_OBJECT else return &builtin.TRUE_OBJECT;
            },
            .null_ => return &builtin.TRUE_OBJECT,
            else => return &builtin.FALSE_OBJECT,
        }
    }

    fn nativeBoolToBooleanObject(input: bool) *object.Object {
        return if (input) &builtin.TRUE_OBJECT else &builtin.FALSE_OBJECT;
    }

    fn isTruthy(obj: *object.Object) bool {
        switch (obj.*) {
            .boolean => |boolean| return boolean.value,
            .null_ => return false,
            else => return true,
        }
    }
};

///////////////// TESTS //////////////////
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn testEvaluate(input: []const u8, alloc: std.mem.Allocator) !*object.Object {
    var lexer = Lexer.new(input);
    var parser = Parser.new(&lexer, alloc);
    var program = try parser.parseProgram();

    var evaluator = Evaluator.new(alloc);
    const result = evaluator.evalProgram(&program);
    return result;
    // const result = alloc.create(object.Object);
}

fn expectInteger(expected: i64, actual: *object.Object) !void {
    switch (actual.*) {
        .integer => |integer| try std.testing.expectEqual(expected, integer.value),
        else => return error.TypeMismatch,
    }
}

fn expectBoolean(expected: bool, actual: *object.Object) !void {
    switch (actual.*) {
        .boolean => |boolean| try std.testing.expectEqual(expected, boolean.value),
        else => return error.TypeMismatch,
    }
}

fn TestExpect(comptime T: type) type {
    return struct {
        input: []const u8,
        expected: T,
    };
}

test "Evaluate integers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_ints: []const TestExpect(i64) = &.{
        .{ .input = "200", .expected = 200 },
        .{ .input = "1", .expected = 1 },
        .{ .input = "1000", .expected = 1000 },
        .{ .input = "-50", .expected = -50 },
        .{ .input = "10 - 10", .expected = 0 },
        .{ .input = "50 / 2 * 2 + 10", .expected = 60 },
        .{ .input = "if (1 != 1) { 55 } else { 11 }", .expected = 11 },
        .{ .input = "if (10) { 2 } else { 1 }", .expected = 2 },
    };

    for (test_ints) |v| {
        const actual = try testEvaluate(v.input, arena.allocator());
        try expectInteger(v.expected, actual);
    }
    // switch (result.*) {
    //     .integer => |integer| try std.testing.expectEqual(@as(i64, integer.value), 1000),
    //     else => try std.testing.expect(false),
    // }
}

test "Evaluate booleans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_boolean: []const TestExpect(bool) = &.{
        .{ .input = "1000 > 100", .expected = true },
        .{ .input = "-22 != -22", .expected = false },
    };

    for (test_boolean) |v| {
        // try testval.evalExpect(arena.allocator());
        const actual = try testEvaluate(v.input, arena.allocator());
        try expectBoolean(v.expected, actual);
    }
}

test "Evaluate return stmt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_return_ints: []const TestExpect(i64) = &.{
        .{ .input = "return 10;", .expected = 10 },
        .{ .input = "return 2*2;", .expected = 4 },
        .{ .input = "return 2*2;", .expected = 4 },
        .{ .input = "return 2*5; 9;", .expected = 10 },
        .{ .input = "9; return 2*5;", .expected = 10 },
    };

    for (test_return_ints) |v| {
        const actual = try testEvaluate(v.input, arena.allocator());
        try expectInteger(v.expected, actual);
    }
}
