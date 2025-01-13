const std = @import("std");

pub const Node = union(enum) {
    program: *Program,
    statement: *Statement,
    expression: *Expression,

    pub fn printStr(self: *Node, writer: anytype) !void {
        switch (self.*) {
            .program => |*program| try program.printStr(writer),
            .statement => |*statement| try statement.printStr(writer),
            .expression => |*expression| try expression.printStr(writer),
        }
    }
};

pub const Program = struct {
    statements: std.ArrayList(Statement),

    pub fn printStr(self: Program, writer: anytype) !void {
        for (self.statements) |stmt| {
            try stmt.printStr(writer);
        }
    }
};

pub const Statement = union(enum) {
    block: Block,
    let: Let,
    return_: Return,
    expression_statement: ExpressionStatement,

    pub fn printStr(self: *Statement, writer: anytype) !void {
        switch (self) {
            .block => |block| try block.printStr(writer),
            .let => |let| try let.printStr(writer),
            .return_ => |return_| try return_.printStr(writer),
            .expression_statement => |expression_statement| try expression_statement.printStr(writer),
        }
    }
};

pub const Expression = union(enum) {
    identifier: Identifier,
    boolean: Boolean,
    integer: Integer,
    prefix_expression: PrefixExpression,
    infix_expression: InfixExpression,
    if_: If,
    function: Function,
    call: Call,

    pub fn printStr(self: *Expression, writer: anytype) !void {
        switch (self.*) {
            .identifier => |identifier| try identifier.printStr(writer),
            .boolean => |boolean| try boolean.printStr(writer),
            .integer => |integer| try integer.printStr(writer),
            .prefix_expression => |prefix| try prefix.printStr(writer),
            .infix_expression => |infix| try infix.printStr(writer),
            .if_ => |if_| try if_.printStr(writer),
            .funciton => |function| try function.printStr(writer),
        }
    }
};

// statements

pub const Block = struct {
    statements: std.ArrayList(Statement),

    pub fn printStr(self: *Block, writer: anytype) !void {
        try writer.print("{ ");
        for (self.*.statements.items) |stmt| {
            try stmt.printStr(writer);
        }
        try writer.print(" }");
    }
};

pub const Let = struct {
    name: Identifier,
    value: Expression,

    pub fn printStr(self: *Let, writer: anytype) !void {
        try writer.print("let ");
        try self.name.printStr(writer);
        try writer.print(" = ");
        try self.value.printStr(writer);
    }
};

pub const Return = struct {
    value: *Expression,

    pub fn printStr(self: Return, writer: anytype) !void {
        self.expression.printStr(writer);
    }
};

pub const ExpressionStatement = struct {
    expression: *Expression,

    pub fn printStr(self: ExpressionStatement, writer: anytype) !void {
        try self.expression.printStr(writer);
    }
};

// expressions

pub const Identifier = struct {
    value: []const u8,

    pub fn printStr(self: Identifier, writer: anytype) !void {
        try writer.print(self.value);
    }
};

pub const Boolean = struct {
    value: bool,

    pub fn printStr(self: Boolean, writer: anytype) !void {
        if (self.value) {
            try writer.print("true");
        } else {
            try writer.print("false");
        }
    }
};

pub const Integer = struct {
    value: i64,

    pub fn printStr(self: Integer, writer: anytype) !void {
        try writer.writeInt(i64, self.value, .little);
    }
};

pub const Function = struct {
    parameters: std.ArrayList(Identifier),
    body: Block,
    name: []const u8,

    pub fn printStr(self: Function, writer: anytype) !void {
        const len = self.parameter.items.len;
        try writer.print("fn(");
        for (self.parameters.items, 1..) |ident, pos| {
            try ident.printStr(writer);
            if (pos < len) {
                try writer.print(", ");
            }
        }
        try writer.print(") ");
        try self.body.printStr(writer);
    }
};

pub const If = struct {
    condition: *Expression,
    thenBranch: Block,
    elseBranch: ?Block,

    pub fn printStr(self: If, writer: anytype) !void {
        try writer.print("if ");
        try self.condition.printStr(writer);
        try writer.print(" ");
        try self.thenBranch.printStr(writer);
        if (self.elseBranch) |*elseBranch| {
            try writer.print(" else ");
            try elseBranch.printStr(writer);
        }
    }
};

pub const Call = struct {
    callee: *Expression,
    arguments: std.ArrayList(Expression),

    pub fn printStr(self: *Call, writer: anytype) !void {
        try self.callee.printStr(writer);
        try writer.print("(");
        const len = self.arguments.items.len;
        for (self.arguments.items, 1..) |argument, pos| {
            try argument.printStr(writer);
            if (pos < len) {
                try writer.print(", ");
            }
        }
        try writer.print(")");
    }
};

pub const PrefixExpression = struct {
    operator: Operator,
    right: *Expression,

    pub fn printStr(self: PrefixExpression, writer: anytype) !void {
        try writer.print("{");
        try writer.print(self.operator.str());
        try self.right.printStr(writer);
        try writer.print(")");
    }
};

pub const InfixExpression = struct {
    left: *Expression,
    operator: Operator,
    right: *Expression,

    pub fn printStr(self: InfixExpression, writer: anytype) !void {
        try writer.print("(");
        try self.left.printStr(writer);
        try writer.print(" ");
        try writer.print(self.operator.str());
        try writer.print(" ");
        try self.right.printStr(writer);
        try writer.print(")");
    }
};

pub const Operator = enum {
    assign,
    plus,
    minus,
    bang,
    asterisk,
    slash,
    equal,
    notEqual,
    lt,
    gt,

    pub fn str(self: Operator) []const u8 {
        return switch (self) {
            .assign => "=",
            .plus => "+",
            .minus => "-",
            .bang => "!",
            .asterisk => "*",
            .slash => "/",
            .equal => "==",
            .notEqual => "!=",
            .lt => "<",
            .gt => ">",
        };
    }
};
