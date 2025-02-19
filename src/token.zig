const std = @import("std");

pub const TokenTag = enum {
    illegal,
    eof,

    // identifiers + literals
    ident,
    int,

    assign,
    plus,
    minus,
    bang,
    asterisk,
    slash,

    lt,
    gt,

    equal,
    notEqual,

    // delimiters
    comma,
    semicolon,

    lparen,
    rparen,
    lbrace,
    rbrace,

    // keywords
    function,
    let,
    true_,
    false_,
    if_,
    else_,
    return_,
};

pub const Token = union(TokenTag) {
    illegal: u8,
    eof: void,

    // identifier / literal
    ident: []const u8,
    int: []const u8,

    // operators
    assign: void,
    plus: void,
    minus: void,
    bang: void,
    asterisk: void,
    slash: void,

    lt: void,
    gt: void,

    equal: void,
    notEqual: void,

    // delimiters
    comma: void,
    semicolon: void,

    lparen: void,
    rparen: void,
    lbrace: void,
    rbrace: void,

    // keywords
    function: void,
    let: void,
    true_: void,
    false_: void,
    if_: void,
    else_: void,
    return_: void,
};

pub fn printToken(tok: Token) void {
    std.debug.print("{s}", .{@tagName(tok)});
    switch (tok) {
        .ident, .int => |v| std.debug.print("={s}\n", .{v}),
        else => std.debug.print("\n", .{}),
    }
}
