const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const Parser = @import("parser.zig").Parser;
const Environment = @import("environment.zig").Environment;
const Evaluator = @import("eval.zig").Evaluator;

const PROMPT = ">> ";

var line_buf: [65536]u8 = undefined;
var buf_offset: usize = 0;

pub fn start(reader: anytype, writer: anytype, allocator: std.mem.Allocator) !void {
    var env = Environment.new(allocator);
    var evaluator = Evaluator.new(allocator);
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
        if (try reader.readUntilDelimiterOrEof(line_buf[buf_offset..], '\n')) |line| {
            buf_offset += line.len;
            var lexer = Lexer.new(line);
            var parser = Parser.new(&lexer, allocator);
            var program = parser.parseProgram() catch |err| {
                try writer.print("Failed to parse input: {}\n", .{err});
                continue;
            };

            const object = evaluator.evalProgram(&program, &env) catch |err| {
                try writer.print("Evaluation error: {}\n", .{err});
                continue;
            };
            switch (object.*) {
                .error_ => |msg| {
                    try writer.print("Error: {s}\n", .{msg});
                },
                else => {
                    try writer.print("\nGot: ", .{});
                    try object.repr(writer);
                    try writer.print("\n", .{});
                },
            }
        } else {
            break;
        }
    }
}
