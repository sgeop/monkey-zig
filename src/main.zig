const std = @import("std");
const token = @import("token.zig");
const repl = @import("repl.zig");
const Lexer = @import("lexer.zig").Lexer;

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Hello, welcome to the monkey language", .{});
    repl.start(stdin, stdout);
}

pub fn printOutput() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
    //
    const input =
        \\ let five = 5;
        \\ let ten = 10;
        \\ let add = fn(x, y) {
        \\   x + y;
        \\ }
        \\
        \\ let result = add(five, ten);
        \\ if (result < 13) {
        \\   return true;
        \\ } else {
        \\   return false;
        \\ }
    ;

    var lexer = Lexer.new(input);

    while (true) {
        const tok = lexer.nextToken();
        token.printToken(tok);
        if (tok == token.Token.eof) {
            std.debug.print("recieved EOF!", .{});
            return;
        }
    }
}

const expect = std.testing.expect;

test "try readNextToken" {
    const input = "==";
    var lexer = Lexer.new(input);

    const tok = lexer.nextToken();
    const tag = @tagName(tok);

    try expect(std.mem.eql(u8, tag, "equal"));
}
