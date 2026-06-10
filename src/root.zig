//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const string = @import("string");

test {
    _ = @import("string.test.zig");
}
