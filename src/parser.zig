const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Token = @import("token.zig").Token;
const TokenTag = @import("token.zig").TokenTag;
const Lexer = @import("lexer.zig").Lexer;
const ast = @import("ast.zig");

pub const ParseError = error{
    InvalidProgram,
    AllocFailed,
    ExpectPeek,
    Panic,
    InvalidInteger,
    ExpectedInteger,
};

const Precedence = enum(u8) {
    lowest = 0,
    equals = 1,
    lessgreater = 2,
    sum = 3,
    product = 4,
    prefix = 5,
    call = 6,

    fn lessThan(self: Precedence, other: Precedence) bool {
        return @intFromEnum(self) < @intFromEnum(other);
    }

    fn fromToken(token: Token) Precedence {
        return switch (token) {
            .equal, .notEqual => .equals,
            .lt, .gt => .lessgreater,
            .plus, .minus => .sum,
            .slash, .asterisk => .product,
            .lparen => .call,
            else => .lowest,
        };
    }
};

pub const Parser = struct {
    lexer: *Lexer,
    cur_token: Token,
    peek_token: Token,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn new(lexer: *Lexer, allocator: std.mem.Allocator) Self {
        const cur_token = lexer.nextToken();
        const peek_token = lexer.nextToken();

        return .{ .lexer = lexer, .cur_token = cur_token, .peek_token = peek_token, .allocator = allocator };
    }

    fn nextToken(self: *Self) void {
        self.cur_token = self.peek_token;
        self.peek_token = self.lexer.nextToken();
    }

    fn currentTokenIs(self: *Self, token: TokenTag) bool {
        return self.cur_token == token;
    }

    fn peekTokenIs(self: *Self, token: TokenTag) bool {
        return self.peek_token == token;
    }

    fn expectPeek(self: *Self, token: TokenTag) ParseError!void {
        if (self.peekTokenIs(token)) {
            self.nextToken();
        } else {
            return ParseError.ExpectPeek;
        }
    }

    fn parseProgram(self: *Self) ParseError!ast.Program {
        var statements = std.ArrayList(ast.Statement).init(self.allocator);

        while (!self.currentTokenIs(Token.eof)) {
            const statement = try self.parseStatement();
            statements.append(statement) catch return ParseError.InvalidProgram;
            self.nextToken();
        }

        return ast.Program{ .statements = statements };
    }

    fn parseStatement(self: *Self) ParseError!ast.Statement {
        return switch (self.cur_token) {
            .let => ast.Statement{ .let = try self.parseLetStatement() },
            else => ParseError.Panic,
            // .return_ => ast.Statement{ .return_ = try .self.parseReturnStatement() },
            // else => ast.Statement{ .expression_statement = try self.parseExpressionStatement() },
        };
    }

    fn parseLetStatement(self: *Self) ParseError!ast.Let {
        try self.expectPeek(.ident);

        const name = ast.Identifier{ .value = self.cur_token.ident };

        try self.expectPeek(.assign);
        self.nextToken();

        var expression = try self.parseExpression(.lowest);
        if (self.peekTokenIs(.semicolon)) {
            self.nextToken();
        }

        switch (expression) {
            .function => |*function| {
                function.*.name = name.value;
            },
            else => {},
        }

        const expressionPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
        expressionPtr.* = expression;
        return ast.Let{ .name = name, .value = expressionPtr };
    }

    fn parseExpression(self: *Self, precedence: Precedence) ParseError!ast.Expression {
        std.debug.print("{}", .{precedence});
        return ast.Expression{ .integer = try self.parseInteger() };
    }

    fn parseInteger(self: Self) ParseError!ast.Integer {
        return switch (self.cur_token) {
            .int => |value| ast.Integer{ .value = std.fmt.parseInt(i64, value, 10) catch return ParseError.InvalidInteger },
            else => ParseError.ExpectedInteger,
        };
    }

    // fn parseExpression(self: *Self, precedence: Precedence) ParseError!ast.Expression {
    //     var leftExpression = try self.parseExpressionByPrefixToken(self.cur_token);

    //     while (!self.peekTokenIs(.semicolon) and precedence.lessThan(Precedence.fromToken(self.peek_token))) {
    //         const leftExpressionPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
    //         leftExpressionPtr.* = leftExpression;
    //
    //         leftExpression = try self.parseInfixExpressionByToken(self.peek_token, leftExpressionPtr);
    //     }

    //     return leftExpression;
    // }

    // fn parseExpressionByPrefixToken()
};

test "Parser.new" {
    var lexer = Lexer.new(";;");
    const parser = Parser.new(&lexer, std.testing.allocator);
    try expectEqual(Token.semicolon, parser.cur_token);
    try expectEqual(Token.semicolon, parser.peek_token);
}

test "Parse let expression" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var lexer = Lexer.new("let five = 5;");
    var parser = Parser.new(&lexer, allocator.allocator());
    const program = try parser.parseProgram();

    var list = std.ArrayList(u8).init(allocator.allocator());

    const stmts = program.statements.items;
    std.debug.print("statements: {any}", .{stmts});
    try expectEqual(stmts.len, 1);

    try program.printStr(list.writer());
    std.debug.print("program: {s}", .{list.items});
}
