const std = @import("std");
const Io = std.Io;
const string = @import("string");
pub fn main(init: std.process.Init) !void {
    const dummy: string(u8) = .init(init.arena.allocator(), "hello");
    _ = dummy;
}
