const std = @import("std");
const Io = std.Io;
const string = @import("string").string;

pub fn main(init: std.process.Init) !void {
    var dummy: string(u8) = .init(init.arena.allocator(), "hello");
    std.debug.print("dummy string: {s}\n", .{dummy.str()});
    std.debug.print("dummy string sentinel: {s}\n", .{dummy.strSentinel()});
}
