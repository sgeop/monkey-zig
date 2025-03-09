const std = @import("std");
const ast = @import("ast.zig");
const Object = @import("value.zig").Object;
const Environment = @import("environment.zig").Environment;

pub const RuntimeError = error{
    OutOfMemory,
    IllegalValue,
    TypeMismatch,
    NotImplemented,
};

pub const Evaluator = struct {
    allocator: std.mem.Allocator,

    pub const Self = @This();

    pub fn new(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn eval(self: *Self, node: ast.Node, env: *Environment) RuntimeError!*Object {
        switch (node) {
            .program => |program| return try self.evalProgram(program, env),
            .statement => |statement| return try self.evalStatement(statement, env),
            .expression => |expression| return try self.evalExpression(expression, env),
        }
    }

    pub fn evalProgram(self: *Self, program: *ast.Program, env: *Environment) RuntimeError!*Object {
        var result: *Object = Object.Null;
        for (program.statements.items) |*statement| {
            const evaluated = try self.evalStatement(statement, env);
            switch (evaluated.*) {
                .return_ => |return_| return return_,
                .error_ => return evaluated,
                else => result = evaluated,
            }
        }

        return result;
    }

    pub fn evalStatement(self: *Self, statement: *ast.Statement, env: *Environment) RuntimeError!*Object {
        switch (statement.*) {
            .expression_statement => |expression_statement| return self.evalExpression(expression_statement.expression, env),
            .let => |let| {
                const value = try self.evalExpression(let.value, env);
                switch (value.*) {
                    .error_ => return value,
                    else => {},
                }

                try env.set(let.name.value, value);
                return Object.Null;
            },
            .block => |*block| return self.evalBlock(block, env),
            .return_ => |return_| {
                const result = try self.evalExpression(return_.value, env);
                return Object.new(self.allocator, Object{ .return_ = result });
            },
        }
    }

    fn evalBlock(self: *Self, block: *ast.Block, env: *Environment) RuntimeError!*Object {
        var result: *Object = Object.Null;
        for (block.statements.items) |*statement| {
            const evaluated = try self.evalStatement(statement, env);
            switch (evaluated.*) {
                .return_, .error_ => return evaluated,
                else => result = evaluated,
            }
        }

        return result;
    }

    pub fn evalExpression(self: *Self, expression: *ast.Expression, env: *Environment) RuntimeError!*Object {
        switch (expression.*) {
            .integer => |integer| return Object.new(self.allocator, Object{ .integer = integer.value }),
            .boolean => |boolean| return Object.new(self.allocator, Object{ .boolean = boolean.value }),
            .identifier => |identifier| return try self.evalIdentifier(&identifier, env),
            .prefix_expression => |prefix_expression| {
                const right = try self.evalExpression(prefix_expression.right, env);
                return self.evalPrefixExpression(prefix_expression.operator, right);
            },
            .infix_expression => |infix_expression| {
                const left = try self.evalExpression(infix_expression.left, env);
                if (left.isError()) {
                    return left;
                }

                const right = try self.evalExpression(infix_expression.right, env);
                if (right.isError()) {
                    return right;
                }

                return try self.evalInfixExpression(&infix_expression.operator, left, right);
            },
            .if_ => |*if_| return self.evalIfExpression(if_, env),
            else => return RuntimeError.NotImplemented,
        }
    }

    pub fn evalIfExpression(self: *Self, if_expr: *ast.If, env: *Environment) RuntimeError!*Object {
        const condition = try self.evalExpression(if_expr.*.condition, env);

        if (isTruthy(condition)) {
            return self.evalBlock(&if_expr.*.then_branch, env);
        } else if (if_expr.*.else_branch) |*else_branch| {
            return self.evalBlock(else_branch, env);
        } else {
            return Object.Null;
        }
    }

    pub fn evalIdentifier(self: *Self, identifier: *const ast.Identifier, env: *Environment) RuntimeError!*Object {
        const value = env.get(identifier.*.value);
        if (value) |val| {
            return val;
        }

        var identifiers = std.ArrayList(u8).init(self.allocator);
        var writer = identifiers.writer();
        var it = env.*.scope.iterator();
        while (it.next()) |kv| {
            try writer.print("Key: {s} Value: ", .{kv.key_ptr.*});
            try kv.value_ptr.*.repr(writer);
            try writer.print("\n", .{});
        }

        return self.newError("identifier not found: {s} in... {s}", .{ identifier.*.value, identifiers.items });
    }

    pub fn evalPrefixExpression(self: *Self, operator: ast.Operator, right: *Object) RuntimeError!*Object {
        switch (operator) {
            .bang => return evalBangOperatorExpression(right),
            .minus => return switch (right.*) {
                .integer => |integer| Object.new(self.allocator, Object{ .integer = -integer }),
                else => self.newError("unknown operator: -{s}", .{right.typeName()}),
            },
            else => {
                return self.newError("unknown operator: {s}{s}", .{ operator.str(), right.typeName() });
            },
        }
    }

    pub fn evalInfixExpression(self: *Self, operator: *const ast.Operator, left: *Object, right: *Object) RuntimeError!*Object {
        switch (left.*) {
            .integer => |left_int| switch (right.*) {
                .integer => |right_int| {
                    const result = try evalIntegerInfixExpression(operator, left_int, right_int);
                    return Object.new(self.allocator, result);
                },
                else => return self.newError("Type mismatch: {s} {s} {s}", .{ left.typeName(), operator.str(), right.typeName() }),
            },
            else => switch (operator.*) {
                .equal => return Object.new(self.allocator, .{ .boolean = left.compare(right.*) }),
                .not_equal => return Object.new(self.allocator, .{ .boolean = !left.compare(right.*) }),
                else => if (std.mem.eql(u8, left.typeName(), right.typeName())) {
                    return self.newError("unknown operator: {s} {s} {s}", .{ left.typeName(), operator.str(), right.typeName() });
                } else {
                    return self.newError("Type mismatch: {s} {s} {s}", .{ left.typeName(), operator.str(), right.typeName() });
                },
            },
        }
    }

    pub fn evalIntegerInfixExpression(
        operator: *const ast.Operator,
        left: i64,
        right: i64,
    ) RuntimeError!Object {
        return switch (operator.*) {
            .plus => .{ .integer = left + right },
            .minus => .{ .integer = left - right },
            .asterisk => .{ .integer = left * right },
            .slash => .{ .integer = @divFloor(left, right) },
            .lt => .{ .boolean = left < right },
            .gt => .{ .boolean = left > right },
            .equal => .{ .boolean = left == right },
            .not_equal => .{ .boolean = left != right },
            else => RuntimeError.IllegalValue,
        };
    }

    pub fn evalBangOperatorExpression(right: *Object) *Object {
        return switch (right.*) {
            .boolean => |boolean| if (boolean) Object.False else Object.True,
            .null_ => Object.True,
            else => Object.False,
        };
    }

    fn isTruthy(object: *Object) bool {
        return switch (object.*) {
            .boolean => |boolean| boolean,
            .null_ => false,
            else => true,
        };
    }

    fn newError(self: *Self, comptime fmt: []const u8, args: anytype) RuntimeError!*Object {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return RuntimeError.OutOfMemory;
        return Object.new(self.allocator, Object{ .error_ = message });
    }
};

//////////////// TESTS ////////////////
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

fn evaluate(input: []const u8, allocator: std.mem.Allocator) !*Object {
    var lexer = Lexer.new(input);
    var parser = Parser.new(&lexer, allocator);
    var program = try parser.parseProgram();
    var evaluator = Evaluator.new(allocator);
    var env = Environment.new(allocator);

    return evaluator.evalProgram(&program, &env);
}

test "evaluate expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const values: []const struct { input: []const u8, expected: Object } = &.{
        .{ .input = "11", .expected = .{ .integer = 11 } },
        .{ .input = "-100", .expected = .{ .integer = -100 } },
        .{ .input = "10 + 10", .expected = .{ .integer = 20 } },
        .{ .input = "10 * 10 - 18", .expected = .{ .integer = 82 } },
        .{ .input = "!(0 > 1)", .expected = .{ .boolean = true } },
        .{ .input = "if (1 != 1) { 400 } else { 200 }", .expected = .{ .integer = 200 } },
        .{ .input = "return 2*2; 2;", .expected = .{ .integer = 4 } },
        .{ .input = "2; return 2*2;", .expected = .{ .integer = 4 } },
        .{ .input = "10 + true", .expected = .{ .error_ = "Type mismatch: integer + boolean" } },
        .{ .input = "true == true", .expected = .{ .boolean = true } },
        .{ .input = "true - 1", .expected = .{ .error_ = "Type mismatch: boolean - integer" } },
    };

    for (values) |value| {
        var expected_repr = std.ArrayList(u8).init(arena.allocator());
        try value.expected.typedRepr(expected_repr.writer());

        const actual = try evaluate(value.input, arena.allocator());
        var actual_repr = std.ArrayList(u8).init(arena.allocator());
        try actual.typedRepr(actual_repr.writer());

        std.debug.print("input: {s}, expected: {s}, actual: {s}\n", .{ value.input, expected_repr.items, actual_repr.items });
        // compare object values
        try std.testing.expect(actual.compare(value.expected));
        // compare typed repr strings
        try std.testing.expectEqualStrings(expected_repr.items, actual_repr.items);
    }

    const object = try evaluate("11", arena.allocator());
    try std.testing.expectEqual(11, object.integer);
}

test "evaluate let statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const values: []const struct { input: []const u8, expected: Object } = &.{
        .{ .input = "let a = 5; a;", .expected = .{ .integer = 5 } },
        .{ .input = "let a = 5 * 5; a;", .expected = .{ .integer = 25 } },
        .{ .input = "let a = 5; let b = a + 1; b * 2;", .expected = .{ .integer = 12 } },
    };

    for (values) |value| {
        const actual = try evaluate(value.input, arena.allocator());
        std.debug.print("input: {s}, expecting: {}, actual {}\n", .{ value.input, value.expected, actual });
        try std.testing.expect(actual.compare(value.expected));
    }
}
