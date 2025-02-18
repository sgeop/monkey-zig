const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const Parser = @import("parser.zig").Parser;

const PROMPT = ">> ";

var line_buf: [65536]u8 = undefined;

pub fn start(reader: anytype, writer: anytype, allocator: std.mem.Allocator) !void {
    while (true) {
        writer.print("{s}", .{PROMPT}) catch unreachable;
        // const line = (reader.readUntilDelimiterOrEof(&line_buf, '\n') catch unreachable) orelse break;
        // var lexer = Lexer.new(line);
        // while (true) {
        //     const token = lexer.nextToken();
        //     if (token == Token.eof) {
        //         break;
        //     }
        //     writer.print("{any}\n", .{token}) catch unreachable;
        // }
        if (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
            var lexer = Lexer.new(line);
            var parser = Parser.new(&lexer, allocator);
            var program = parser.parseProgram() catch |err| {
                try writer.print("Failed to parse input: {}\n", .{err});
                continue;
            };

            try writer.print("\nGot: ", .{});
            try program.printStr(writer);
            try writer.print("\n", .{});
        } else {
            break;
        }
    }
}
