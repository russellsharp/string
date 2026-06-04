const std = @import("std");
const clone = @import("clone.zig");

const StringErrors = error{ InvalidArgument, EmptyString };

pub const empty = "";

pub fn string(T: type) type {
    return struct {
        const Self = @This();

        a: std.mem.Allocator,
        i: std.ArrayList(T) = .empty,
        raw: ?[]T = null,

        pub fn init(a: std.mem.Allocator, initial: ?[]const T) Self {
            var s = Self{
                .a = a,
                .i = std.ArrayList(T).empty,
            };
            if (initial) |value| _ = s.set(value);
            return s;
        }

        pub fn deinit(s: *Self) void {
            s.i.deinit(s.a);
            if (s.raw) |in| s.a.free(in);
        }

        pub fn clone(s: Self) Self {
            var c = Self{
                .a = s.a,
                .i = std.ArrayList.empty,
            };
            c.raw = s.a.dupe(s.raw);
            c.i = s.i.clone(s.a);
        }

        pub fn append(s: *Self, suffix: []const T) !*Self {
            try s.i.appendSlice(s.a, suffix);
            return s;
        }

        //caller gets a newly allocated []const T that they must free
        pub fn str(s: *Self) ![]T {
            if (s.raw) |previous| s.a.free(previous);
            s.raw = try s.a.dupe(T, s.i.items);
            return s.raw.?;
        }

        pub fn trimRight(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;
            var idx = s.i.items.len - 1;
            var last: usize = s.i.items.len;

            while (idx > 0) : (idx -= 1) {
                if (std.mem.containsAtLeastScalar2(T, charactersToTrim, s.i.items[idx], 1)) {
                    s.i.items[idx] = 0;
                    if (idx < last) last = idx;
                    continue;
                }
                break;
            }

            s.i.shrinkAndFree(s.a, last);

            return s.str();
        }

        pub fn trimLeft(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            var idx: usize = 0;
            var first: usize = 0;
            while (idx < s.i.items.len) : (idx += 1) {
                if (std.mem.containsAtLeastScalar2(T, charactersToTrim, s.i.items[idx], 1)) {
                    s.i.items[idx] = 0;
                    first = idx + 1;
                    continue;
                }
                break;
            }

            const trimmed = try s.a.dupe(T, s.i.items[first .. s.i.items.len - 1]);
            defer s.a.free(trimmed);

            return s.set(trimmed).str();
        }

        pub fn trim(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            var idx = s.i.items.len - 1;
            var first: usize = idx;
            var last: usize = idx;

            while (idx > 0) : (idx -= 1) {
                if (std.mem.containsAtLeastScalar2(T, charactersToTrim, s.i.items[idx], 1)) {
                    s.i.items[idx] = 0;
                    last = idx;
                    continue;
                }
                break;
            }
            idx = 0;
            while (idx < s.i.items.len) : (idx += 1) {
                if (std.mem.containsAtLeastScalar2(T, charactersToTrim, s.i.items[idx], 1)) {
                    s.i.items[idx] = 0;
                    first = idx + 1;
                    continue;
                }
                break;
            }

            const trimmed = try s.a.dupe(T, s.i.items[first..last]);
            defer s.a.free(trimmed);

            return s.set(trimmed).str();
        }

        pub fn substr(s: *Self, index: usize, count: usize) ![]T {
            if (count > s.i.items.len) return StringErrors.InvalidArgument;

            var i: usize = index;
            var subList: std.ArrayList(T) = .empty;
            while (i < s.i.items.len and i < count) : (i += 1) {
                try subList.append(s.a, s.i.items[i]);
            }

            const subString = try subList.toOwnedSlice(s.a);
            defer s.a.free(subString);

            return s.set(subString).str();
        }

        pub fn length(s: *Self) usize {
            return s.i.items.len;
        }

        pub fn is_empty(s: *Self) bool {
            return s.i.items.len == 0;
        }

        pub fn clear(s: *Self) *Self {
            return s.set(empty);
        }

        fn set(s: *Self, new: []const T) *Self {
            s.i.clearAndFree(s.a);
            s.i.appendSlice(s.a, new) catch unreachable;
            _ = s.str() catch unreachable;
            return s;
        }
    };
}

test "instantiation" {
    var str = string(u8).init(std.testing.allocator, empty);
    _ = &str;
}

test "empty string error" {
    var str = string(u8).init(std.testing.allocator, empty);
    defer str.deinit();
    const toTrim = "\n\r";
    try std.testing.expectError(StringErrors.EmptyString, str.trimRight(toTrim));
}

test "empty string" {
    try std.testing.expectEqualStrings("", empty);
    try std.testing.expectEqual(0, empty.len);
}

test "append" {
    var str = string(u8).init(std.testing.allocator, empty);
    defer str.deinit();
    _ = try str.append("hi");
    try std.testing.expectEqualStrings("hi", try str.str());

    _ = try str.append("hi");
    try std.testing.expectEqualStrings("hihi", try str.str());
}

test "trimRight" {
    var str = string(u8).init(std.testing.allocator, "starting\r\n");
    defer str.deinit();

    const toTrim = "\n\r";
    const trimmed = try str.trimRight(toTrim);
    try std.testing.expectEqualStrings("starting", trimmed);
}

test "trimLeft" {
    var str = string(u8).init(std.testing.allocator, "\r\nstarting\r\n ");
    defer str.deinit();

    const toTrim = "\n\r";
    const trimmed = try str.trimLeft(toTrim);
    try std.testing.expectEqualStrings("starting\r\n", trimmed);
}

test "trim" {
    var str = string(u8).init(std.testing.allocator, "\r\nstar\r\nting\r\n");
    defer str.deinit();

    const toTrim = "\n\r";
    const trimmed = try str.trim(toTrim);

    try std.testing.expectEqualStrings("star\r\nting", trimmed);
}

test "substr(index, length)" {
    var str_0 = string(u8).init(std.testing.allocator, "01234567");
    defer str_0.deinit();
    const sub = try str_0.substr(0, 5);
    try std.testing.expectEqualStrings("01234", sub);

    var str_1 = string(u8).init(std.testing.allocator, "01234567");
    defer str_1.deinit();
    const sub_short = try str_1.substr(0, 8);
    try std.testing.expectEqualStrings("01234567", sub_short);

    var str_2 = string(u8).init(std.testing.allocator, "01234567");
    defer str_2.deinit();
    const sub_beyond = try str_2.substr(55, 8);
    try std.testing.expectEqualStrings(empty, sub_beyond);
}

test "length" {
    var str_0 = string(u8).init(std.testing.allocator, empty);
    defer str_0.deinit();

    try std.testing.expectEqual(0, str_0.length());

    _ = try str_0.append("1234567");
    try std.testing.expectEqual(7, str_0.length());
}

test "is_empty" {
    var str_0 = string(u8).init(std.testing.allocator, empty);
    defer str_0.deinit();

    try std.testing.expectEqual(0, str_0.length());
    try std.testing.expect(str_0.is_empty());
}

test "clear" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    try std.testing.expectEqual("content for your pleasure".len, str_0.length());
    try std.testing.expect(!str_0.is_empty());

    _ = str_0.clear();

    try std.testing.expectEqual(0, str_0.length());
    try std.testing.expect(str_0.is_empty());
}

test "resize" {}

test "at" {}

test "strSentinel" {}

test "insert" {}

test "erase" {}

test "replace" {}

test "find" {}

test "rfind" {}

test "compare" {}

test "fromWriter" {}

test "fromSlice" {}

test "fromArrayList" {}
