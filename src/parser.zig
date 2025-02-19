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
    InvalidBlockStatement,
    InvalidFunctionParam,
    InvalidExpressionList,
    InvalidInfix,
    InvalidPrefix,
    InvalidInteger,
    InvalidBooleanLiteral,
    AllocFailed,
    ExpectPeek,
    Panic,
    ExpectedInteger,
    ExpectedIdentifier,
    ExpectedOperator,
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

fn getOperatorFromToken(token: Token) !ast.Operator {
    return switch (token) {
        .assign => .assign,
        .plus => .plus,
        .minus => .minus,
        .bang => .bang,
        .asterisk => .asterisk,
        .slash => .slash,
        .equal => .equal,
        .notEqual => .notEqual,
        .lt => .lt,
        .gt => .gt,
        else => ParseError.ExpectedOperator,
    };
}

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

    pub fn parseProgram(self: *Self) ParseError!ast.Program {
        var statements = std.ArrayList(ast.Statement).init(self.allocator);

        while (!self.currentTokenIs(Token.eof)) {
            const statement = try self.parseStatement();
            statements.append(statement) catch return ParseError.InvalidProgram;
            self.nextToken();
        }

        return ast.Program{ .statements = statements };
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

    fn parseStatement(self: *Self) ParseError!ast.Statement {
        return switch (self.cur_token) {
            .let => ast.Statement{ .let = try self.parseLetStatement() },
            .return_ => ast.Statement{ .return_ = try self.parseReturnStatement() },
            else => ast.Statement{ .expression_statement = try self.parseExpressionStatement() },
        };
    }

    fn parseLetStatement(self: *Self) ParseError!ast.Let {
        try self.expectPeek(.ident);

        // TODO: fix this panic
        const name = switch (self.cur_token) {
            .ident => |ident| ast.Identifier{ .value = ident },
            else => return ParseError.Panic,
        };

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

    fn parseExpressionTest(self: *Self, precedence: Precedence) ParseError!ast.Expression {
        std.debug.print("{}", .{precedence});
        return ast.Expression{ .integer = try self.parseInteger() };
    }

    fn parseReturnStatement(self: *Self) ParseError!ast.Return {
        self.nextToken();

        const returnValue = try self.parseExpression(.lowest);
        if (self.peekTokenIs(.semicolon)) {
            self.nextToken();
        }

        const returnValuePtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
        returnValuePtr.* = returnValue;
        return ast.Return{ .value = returnValuePtr };
    }

    fn parseBlockStatement(self: *Self) ParseError!ast.Block {
        var statements = std.ArrayList(ast.Statement).init(self.allocator);
        self.nextToken();

        while (!self.currentTokenIs(.rbrace) and !self.currentTokenIs(.eof)) {
            const statement = try self.parseStatement();
            statements.append(statement) catch return ParseError.InvalidBlockStatement;
            self.nextToken();
        }

        return ast.Block{ .statements = statements };
    }

    fn parseExpressionStatement(self: *Self) ParseError!ast.ExpressionStatement {
        const expression = try self.parseExpression(.lowest);
        if (self.peekTokenIs(.semicolon)) {
            self.nextToken();
        }

        const expressionPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
        expressionPtr.* = expression;
        return ast.ExpressionStatement{ .expression = expressionPtr };
    }

    fn parseExpression(self: *Self, precedence: Precedence) ParseError!ast.Expression {
        // TODO: replace with var
        var leftExpression = try self.parseExpressionByPrefixToken(self.cur_token);

        while (!self.peekTokenIs(.semicolon) and precedence.lessThan(Precedence.fromToken(self.peek_token))) {
            const leftExpressionPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
            leftExpressionPtr.* = leftExpression;

            leftExpression = try self.parseInfixExpressionByToken(self.peek_token, leftExpressionPtr);
        }

        return leftExpression;
    }

    fn parseIdentifier(self: Self) ParseError!ast.Identifier {
        return switch (self.cur_token) {
            .ident => |value| ast.Identifier{ .value = value },
            else => return ParseError.ExpectedIdentifier,
        };
    }

    fn parseInteger(self: Self) ParseError!ast.Integer {
        return switch (self.cur_token) {
            .int => |value| ast.Integer{ .value = std.fmt.parseInt(i64, value, 10) catch return ParseError.InvalidInteger },
            else => ParseError.ExpectedInteger,
        };
    }

    fn parseBoolean(self: Self) ParseError!ast.Boolean {
        return switch (self.cur_token) {
            .true_ => ast.Boolean{ .value = true },
            .false_ => ast.Boolean{ .value = false },
            else => ParseError.InvalidBooleanLiteral,
        };
    }

    fn parseGroupedExpression(self: *Self) ParseError!ast.Expression {
        self.nextToken();
        const expression = try self.parseExpression(.lowest);
        try self.expectPeek(.rparen);
        return expression;
    }

    fn parsePrefixExpression(self: *Self) ParseError!ast.PrefixExpression {
        const op = try getOperatorFromToken(self.cur_token);
        self.nextToken();

        const right = try self.parseExpression(.prefix);
        const rightPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
        rightPtr.* = right;

        return ast.PrefixExpression{ .operator = op, .right = rightPtr };
    }

    fn parseInfixExpression(self: *Self, left: *ast.Expression) ParseError!ast.InfixExpression {
        const op = try getOperatorFromToken(self.cur_token);
        const precedence = Precedence.fromToken(self.cur_token);

        self.nextToken();

        const right = try self.parseExpression(precedence);
        const rightPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
        rightPtr.* = right;

        return ast.InfixExpression{ .operator = op, .left = left, .right = rightPtr };
    }

    fn parseIfExpression(self: *Self) ParseError!ast.If {
        try self.expectPeek(.lparen);
        self.nextToken();

        const condition = try self.parseExpression(.lowest);
        const conditionPtr = self.allocator.create(ast.Expression) catch return ParseError.AllocFailed;
        conditionPtr.* = condition;

        try self.expectPeek(.rparen);
        try self.expectPeek(.lbrace);

        const thenBlock = try self.parseBlockStatement();
        var elseBlock: ?ast.Block = null;
        if (self.peekTokenIs(.else_)) {
            self.nextToken();
            try self.expectPeek(.lbrace);
            elseBlock = try self.parseBlockStatement();
        }

        return ast.If{ .condition = conditionPtr, .thenBranch = thenBlock, .elseBranch = elseBlock };
    }

    fn parseFunctionLiteral(self: *Self) ParseError!ast.Function {
        try self.expectPeek(.lparen);

        const parameters = try self.parseFunctionParameters();
        try self.expectPeek(.lbrace);

        const body = try self.parseBlockStatement();

        return ast.Function{ .parameters = parameters, .body = body, .name = "" };
    }

    fn parseFunctionParameters(self: *Self) ParseError!std.ArrayList(ast.Identifier) {
        var parameters = std.ArrayList(ast.Identifier).init(self.allocator);
        if (self.peekTokenIs(.rparen)) {
            self.nextToken();
            return parameters;
        }
        self.nextToken();
        parameters.append(try self.parseIdentifier()) catch return ParseError.InvalidFunctionParam;

        while (self.peekTokenIs(.comma)) {
            self.nextToken();
            self.nextToken();
            parameters.append(try self.parseIdentifier()) catch return ParseError.InvalidFunctionParam;
        }
        try self.expectPeek(.rparen);

        return parameters;
    }

    fn parseCallExpression(self: *Self, callee: *ast.Expression) ParseError!ast.Call {
        return ast.Call{ .callee = callee, .arguments = try self.parseExpressionList(.rparen) };
    }

    fn parseExpressionList(self: *Self, end_token: TokenTag) ParseError!std.ArrayList(ast.Expression) {
        var list = std.ArrayList(ast.Expression).init(self.allocator);
        if (self.peekTokenIs(end_token)) {
            self.nextToken();
            return list;
        }
        self.nextToken();
        list.append(try self.parseExpression(.lowest)) catch return ParseError.InvalidExpressionList;

        while (self.peekTokenIs(.comma)) {
            self.nextToken();
            self.nextToken();
            list.append(try self.parseExpression(.lowest)) catch return ParseError.InvalidExpressionList;
        }
        try self.expectPeek(end_token);

        return list;
    }

    fn parseExpressionByPrefixToken(self: *Self, token: TokenTag) ParseError!ast.Expression {
        return switch (token) {
            .ident => ast.Expression{ .identifier = try self.parseIdentifier() },
            .int => ast.Expression{ .integer = try self.parseInteger() },
            .bang, .minus => ast.Expression{ .prefix_expression = try self.parsePrefixExpression() },
            .true_, .false_ => ast.Expression{ .boolean = try self.parseBoolean() },
            .lparen => try self.parseGroupedExpression(),
            .if_ => ast.Expression{ .if_ = try self.parseIfExpression() },
            .function => ast.Expression{ .function = try self.parseFunctionLiteral() },
            else => ParseError.InvalidPrefix,
        };
    }

    fn parseInfixExpressionByToken(self: *Self, token: TokenTag, left: *ast.Expression) ParseError!ast.Expression {
        self.nextToken();
        return switch (token) {
            .plus, .minus, .asterisk, .slash, .equal, .notEqual, .gt, .lt => ast.Expression{ .infix_expression = try self.parseInfixExpression(left) },
            .lparen => ast.Expression{ .call = try self.parseCallExpression(left) },
            else => ParseError.InvalidInfix,
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

/// testing
fn expectParsedOutput(source: []const u8, expected: []const u8) !void {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var lexer = Lexer.new(source);
    var parser = Parser.new(&lexer, allocator.allocator());
    const program = try parser.parseProgram();

    var output = std.ArrayList(u8).init(allocator.allocator());
    try program.printStr(output.writer());
    try expectEqualStrings(expected, output.items);
}

test "Parser.new" {
    var lexer = Lexer.new(";;");
    const parser = Parser.new(&lexer, std.testing.allocator);
    try expectEqual(Token.semicolon, parser.cur_token);
    try expectEqual(Token.semicolon, parser.peek_token);
}

test "Parse expression precedence" {
    try expectParsedOutput("-a * b", "((-a) * b)");
    try expectParsedOutput("!-a", "(!(-a))");
    try expectParsedOutput("a + b + c", "((a + b) + c)");
    try expectParsedOutput("a + b - c", "((a + b) - c)");
    try expectParsedOutput("a + b * c", "(a + (b * c))");
    try expectParsedOutput("a * b * c", "((a * b) * c)");
    try expectParsedOutput("a + b / c", "(a + (b / c))");
    try expectParsedOutput("3 + 4; -5 * 5", "(3 + 4)((-5) * 5)");
    try expectParsedOutput("5 > 4 == 3 < 4", "((5 > 4) == (3 < 4))");
}
