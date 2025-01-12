const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;

const PROMPT = ">> ";

var line_buf: [4096]u8 = undefined;

pub fn start(reader: anytype, writer: anytype) void {
    while (true) {
        writer.print("{s}", .{PROMPT}) catch unreachable;
        const line = (reader.readUntilDelimiterOrEof(&line_buf, '\n') catch unreachable) orelse break;
        var lexer = Lexer.new(line);
        while (true) {
            const token = lexer.nextToken();
            if (token == Token.eof) {
                break;
            }
            writer.print("{any}\n", .{token}) catch unreachable;
        }
    }
}
