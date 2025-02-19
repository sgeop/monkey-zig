const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const token = @import("token.zig");

pub const Lexer = struct {
    input: []const u8,
    position: usize,
    readPosition: usize,
    char: ?u8,

    const Self = @This();

    pub fn new(input: []const u8) Lexer {
        var lexer = Lexer{
            .input = input,
            .position = 0,
            .readPosition = 0,
            .char = null,
        };
        lexer.readChar();

        return lexer;
    }

    pub fn nextTokenOld(self: *Self) token.Token {
        self.skipWhitespace();

        const parsedToken = self.resolveNextToken();

        return parsedToken;
    }

    pub fn nextToken(self: *Self) token.Token {
        self.skipWhitespace();

        const ch = self.char orelse 0;
        const tok: token.Token = switch (ch) {
            '=' => blk: {
                if (self.peekCharIs('=')) {
                    self.readChar();
                    break :blk token.Token.equal;
                }
                break :blk token.Token.assign;
            },
            '+' => token.Token.plus,
            '-' => token.Token.minus,
            '!' => blk: {
                if (self.peekCharIs('=')) {
                    self.readChar();
                    break :blk token.Token.notEqual;
                }
                break :blk token.Token.bang;
            },
            '/' => token.Token.slash,
            '*' => token.Token.asterisk,
            '<' => token.Token.lt,
            '>' => token.Token.gt,
            ';' => token.Token.semicolon,
            ',' => token.Token.comma,
            '{' => token.Token.lbrace,
            '}' => token.Token.rbrace,
            '(' => token.Token.lparen,
            ')' => token.Token.rparen,
            0 => token.Token.eof,
            else => blk: {
                if (isLetter(ch)) {
                    return lookupIdent(self.readIdentifier());
                } else if (isDigit(ch)) {
                    return token.Token{ .int = self.readNumber() };
                } else {
                    break :blk token.Token{ .illegal = ch };
                }
            },
        };

        self.readChar();
        return tok;
    }

    fn resolveNextToken(self: *Self) token.Token {
        if (self.charIs('=')) {
            if (self.peekCharIs('=')) {
                self.readChar();
                self.readChar();

                return token.Token.equal;
            }
            self.readChar();
            return token.Token.assign;
        } else if (self.charIs('+')) {
            self.readChar();
            return token.Token.plus;
        } else if (self.charIs('-')) {
            self.readChar();
            return token.Token.minus;
        } else if (self.charIs('!')) {
            if (self.peekCharIs('=')) {
                self.readChar();
                self.readChar();
                return token.Token.notEqual;
            }
            self.readChar();
            return token.Token.bang;
        } else if (self.charIs('*')) {
            self.readChar();
            return token.Token.asterisk;
        } else if (self.charIs('/')) {
            self.readChar();
            return token.Token.slash;
        } else if (self.charIs('<')) {
            self.readChar();
            return token.Token.lt;
        } else if (self.charIs('>')) {
            self.readChar();
            return token.Token.gt;
        } else if (self.charIs(',')) {
            self.readChar();
            return token.Token.comma;
        } else if (self.charIs(';')) {
            self.readChar();
            return token.Token.semicolon;
        } else if (self.charIs('(')) {
            self.readChar();
            return token.Token.lparen;
        } else if (self.charIs(')')) {
            self.readChar();
            return token.Token.rparen;
        } else if (self.charIs('{')) {
            self.readChar();
            return token.Token.lbrace;
        } else if (self.charIs('}')) {
            self.readChar();
            return token.Token.rbrace;
        } else {
            if (self.char) |char| {
                if (isLetter(char)) {
                    return lookupIdent(self.readIdentifier());
                } else if (isDigit(char)) {
                    return token.Token{ .int = self.readNumber() };
                } else {
                    self.readChar();
                    return token.Token{ .illegal = char };
                }
            } else {
                self.readChar();
                return token.Token.eof;
            }
        }
    }

    fn charIs(self: Self, expected: u8) bool {
        if (self.char) |char| {
            return char == expected;
        } else {
            return false;
        }
    }

    fn peekCharIs(self: Self, expected: u8) bool {
        if (self.peekChar()) |peekCh| {
            return peekCh == expected;
        } else {
            return false;
        }
    }

    fn isLetter(char: u8) bool {
        return (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z') or char == '_';
    }

    fn isDigit(char: u8) bool {
        return char >= '0' and char <= '9';
    }

    fn readChar(self: *Self) void {
        self.char = self.peekChar();
        self.position = self.readPosition;
        self.readPosition += 1;
    }

    fn peekChar(self: Self) ?u8 {
        if (self.readPosition >= self.input.len) {
            return null;
        } else {
            return self.input[self.readPosition];
        }
    }

    fn readRange(self: Self, start: usize, end: usize) []const u8 {
        return self.input[start..end];
    }

    fn readIdentifier(self: *Self) []const u8 {
        const prevPosition = self.position;
        while (true) {
            if (self.char) |char| {
                if (isLetter(char)) {
                    self.readChar();
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        return self.readRange(prevPosition, self.position);
    }

    fn readNumber(self: *Self) []const u8 {
        const prevPosition = self.position;
        while (true) {
            if (self.char) |char| {
                if (isDigit(char)) {
                    self.readChar();
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        return self.readRange(prevPosition, self.position);
    }

    fn skipWhitespace(self: *Self) void {
        while (true) {
            if (self.char) |char| {
                switch (char) {
                    '\t', '\n', '\x0C', '\r', ' ' => {
                        self.readChar();
                    },
                    else => {
                        break;
                    },
                }
            } else {
                break;
            }
        }
    }
};

fn lookupIdent(ident: []const u8) token.Token {
    if (std.mem.eql(u8, ident, "fn")) {
        return token.Token.function;
    } else if (std.mem.eql(u8, ident, "let")) {
        return token.Token.let;
    } else if (std.mem.eql(u8, ident, "true")) {
        return token.Token.true_;
    } else if (std.mem.eql(u8, ident, "false")) {
        return token.Token.false_;
    } else if (std.mem.eql(u8, ident, "if")) {
        return token.Token.if_;
    } else if (std.mem.eql(u8, ident, "else")) {
        return token.Token.else_;
    } else if (std.mem.eql(u8, ident, "return")) {
        return token.Token.return_;
    } else {
        return token.Token{ .ident = ident };
    }
}

// test utils
fn expectStringInnerToken(expected: []const u8, actual: token.Token) !void {
    switch (actual) {
        token.Token.ident, token.Token.int => |value| try expectEqualStrings(expected, value),
        else => unreachable,
    }
}

fn expectIdent(expected: []const u8, actual: token.Token) !void {
    try expect(actual == .ident);
    try expectStringInnerToken(expected, actual);
}

fn expectInt(expected: []const u8, actual: token.Token) !void {
    try expect(actual == .int);
    try expectStringInnerToken(expected, actual);
}

fn expectStringLiteral(expected: []const u8, actual: token.Token) !void {
    try expect(actual == .stringLiteral);
    try expectStringInnerToken(expected, actual);
}

test "lexer" {
    const input =
        \\ let five = 5;
        \\ let ten = 10;
        \\ 
        \\ let add = fn(x, y) {
        \\   x + y;
        \\ };
        \\ 
        \\ let result = add(five, ten);
        \\ !-/*5;
        \\ 5 < 10 > 5;
        \\ 
        \\ if(5 < 10) {
        \\   return true;
        \\ } else {
        \\   return false;
        \\ }
        \\ 
        \\ 10 == 10;
        \\ 10 != 9;
    ;

    var lexer = Lexer.new(input);
    try expectEqual(token.Token.let, lexer.nextToken());
    try expectIdent("five", lexer.nextToken());
    try expectEqual(token.Token.assign, lexer.nextToken());
    try expectInt("5", lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.let, lexer.nextToken());
    try expectIdent("ten", lexer.nextToken());
    try expectEqual(token.Token.assign, lexer.nextToken());
    try expectInt("10", lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.let, lexer.nextToken());
    try expectIdent("add", lexer.nextToken());
    try expectEqual(token.Token.assign, lexer.nextToken());
    try expectEqual(token.Token.function, lexer.nextToken());
    try expectEqual(token.Token.lparen, lexer.nextToken());
    try expectIdent("x", lexer.nextToken());
    try expectEqual(token.Token.comma, lexer.nextToken());
    try expectIdent("y", lexer.nextToken());
    try expectEqual(token.Token.rparen, lexer.nextToken());
    try expectEqual(token.Token.lbrace, lexer.nextToken());
    try expectIdent("x", lexer.nextToken());
    try expectEqual(token.Token.plus, lexer.nextToken());
    try expectIdent("y", lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.rbrace, lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.let, lexer.nextToken());
    try expectIdent("result", lexer.nextToken());
    try expectEqual(token.Token.assign, lexer.nextToken());
    try expectIdent("add", lexer.nextToken());
    try expectEqual(token.Token.lparen, lexer.nextToken());
    try expectIdent("five", lexer.nextToken());
    try expectEqual(token.Token.comma, lexer.nextToken());
    try expectIdent("ten", lexer.nextToken());
    try expectEqual(token.Token.rparen, lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.bang, lexer.nextToken());
    try expectEqual(token.Token.minus, lexer.nextToken());
    try expectEqual(token.Token.slash, lexer.nextToken());
    try expectEqual(token.Token.asterisk, lexer.nextToken());
    try expectInt("5", lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectInt("5", lexer.nextToken());
    try expectEqual(token.Token.lt, lexer.nextToken());
    try expectInt("10", lexer.nextToken());
    try expectEqual(token.Token.gt, lexer.nextToken());
    try expectInt("5", lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.if_, lexer.nextToken());
    try expectEqual(token.Token.lparen, lexer.nextToken());
    try expectInt("5", lexer.nextToken());
    try expectEqual(token.Token.lt, lexer.nextToken());
    try expectInt("10", lexer.nextToken());
    try expectEqual(token.Token.rparen, lexer.nextToken());
    try expectEqual(token.Token.lbrace, lexer.nextToken());
    try expectEqual(token.Token.return_, lexer.nextToken());
    try expectEqual(token.Token.true_, lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.rbrace, lexer.nextToken());
    try expectEqual(token.Token.else_, lexer.nextToken());
    try expectEqual(token.Token.lbrace, lexer.nextToken());
    try expectEqual(token.Token.return_, lexer.nextToken());
    try expectEqual(token.Token.false_, lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectEqual(token.Token.rbrace, lexer.nextToken());
    try expectInt("10", lexer.nextToken());
    try expectEqual(token.Token.equal, lexer.nextToken());
    try expectInt(
        "10",
        lexer.nextToken(),
    );
    try expectEqual(token.Token.semicolon, lexer.nextToken());
    try expectInt("10", lexer.nextToken());
    try expectEqual(token.Token.notEqual, lexer.nextToken());
    try expectInt("9", lexer.nextToken());
    try expectEqual(token.Token.semicolon, lexer.nextToken());
}
