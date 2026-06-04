const std = @import("std");

var asdf: string(u8) = .init(std.testing.allocator);

const StringErrors = error{ InvalidArgument, EmptyString };

pub const empty = "";

pub fn string(T: type) type {
    return struct {
        const Self = @This();

        a: std.mem.Allocator,
        i: std.ArrayList(T) = .empty,
        inner: ?[]T = null,

        pub const empty = "";

        pub fn init(a: std.mem.Allocator, initial: ?[]const T) Self {
            var s = Self{
                .a = a,
                .i = std.ArrayList(T).empty,
            };
            if (initial) |value| s.append(value) catch unreachable;
            return s;
        }

        pub fn deinit(s: *Self) void {
            s.i.deinit(s.a);
            if (s.inner) |in| s.a.free(in);
        }

        pub fn clone(s: Self) Self {
            var c = Self{
                .a = s.a,
                .i = std.ArrayList.empty,
            };
            c.inner = s.a.dupe(s.inner);
            c.i = s.i.clone(s.a);
        }

        pub fn append(s: *Self, suffix: []const T) !void {
            try s.i.appendSlice(s.a, suffix);
        }

        pub fn str(s: *Self) ![]T {
            if (s.inner) |previous| s.a.free(previous);
            s.inner = try s.a.dupe(T, s.i.items);
            return s.inner.?;
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

            s.i.clearAndFree(s.a);
            try s.i.appendSlice(s.a, trimmed);

            return s.str();
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

            s.i.clearAndFree(s.a);
            try s.i.appendSlice(s.a, trimmed);

            return s.str();
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
    try str.append("hi");
    try std.testing.expectEqualStrings("hi", try str.str());

    try str.append("hi");
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

test "substr(index, length)" {}

test "length" {}

test "empty" {}

test "clear" {}

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

fn cloneArrayList(a: std.mem.Allocator, T: type, source: std.ArrayList(T)) !std.ArrayList(T) {
    var clone: std.ArrayList(T) = .empty;
    if (comptime std.meta.hasMethod(T, "clone")) {
        if (comptime hasParameter(T, "clone", std.mem.Allocator, 1)) {
            clone = try cloneListA(a, T, source);
        } else {
            clone = try cloneList(a, T, source);
        }
    } else {
        clone = try source.clone(a);
    }
    return clone;
}

fn hasParameter(comptime T: type, comptime method: []const u8, comptime P: type, comptime position: usize) bool {
    if (!std.meta.hasMethod(T, method)) return false;

    const method_type = @TypeOf(@field(T, method));
    const fn_info = @typeInfo(method_type).@"fn";

    if (fn_info.params.len < position + 1) return false;
    if (fn_info.params[position].type != P) return false;

    return true;
}

pub fn cloneListA(a: std.mem.Allocator, T: type, source: std.ArrayList(T)) !std.ArrayList(T) {
    var copy: std.ArrayList(T) = .empty;
    for (source.items) |item| {
        var item_clone = item;
        try copy.append(a, item_clone.clone(a));
    }
    return copy;
}

pub fn cloneList(a: std.mem.Allocator, T: type, source: std.ArrayList(T)) !std.ArrayList(T) {
    var copy: std.ArrayList(T) = .empty;
    for (source.items) |item| {
        var item_clone = item;
        try copy.append(a, item_clone.clone());
    }
    return copy;
}

const testStructClone = struct {
    const Self = @This();

    inner: usize,

    pub fn clone(s: *Self, a: std.mem.Allocator) Self {
        _ = a;
        return Self{ .inner = s.inner };
    }
};

const testStructCloneNoAllocator = struct {
    const Self = @This();

    inner: usize,

    pub fn clone(s: *Self) Self {
        return Self{ .inner = s.inner };
    }
};

const testStructNoClone = struct {
    const Self = @This();

    inner: usize,
};

test "cloneArrayList u8" {
    const a = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(a);
    try list.append(a, 5);
    var copy = try cloneArrayList(std.testing.allocator, u8, list);
    defer copy.deinit(a);
    try std.testing.expectEqual(1, copy.items.len);
    try std.testing.expectEqual(5, copy.items[0]);
}

test "cloneArrayList []const u8" {
    const T = []const u8;
    const a = std.testing.allocator;
    var list: std.ArrayList(T) = .empty;
    defer list.deinit(a);
    try list.append(a, "testEntry");
    var copy = try cloneArrayList(std.testing.allocator, T, list);
    defer copy.deinit(a);
    try std.testing.expectEqual(1, copy.items.len);
    try std.testing.expectEqual("testEntry", copy.items[0]);
}

test "cloneArrayList struct has clone(allocator)" {
    const T = testStructClone;
    const a = std.testing.allocator;
    var list: std.ArrayList(T) = .empty;
    defer list.deinit(a);
    try list.append(a, T{ .inner = 523 });
    var copy = try cloneArrayList(std.testing.allocator, T, list);
    defer copy.deinit(a);
    try std.testing.expectEqual(1, copy.items.len);
    try std.testing.expectEqual(T{ .inner = 523 }, copy.items[0]);
}

test "cloneArrayList struct has clone() with no allocator parameter" {
    const T = testStructCloneNoAllocator;
    const a = std.testing.allocator;
    var list: std.ArrayList(T) = .empty;
    defer list.deinit(a);
    try list.append(a, T{ .inner = 523 });
    var copy = try cloneArrayList(std.testing.allocator, T, list);
    defer copy.deinit(a);
    try std.testing.expectEqual(1, copy.items.len);
    try std.testing.expectEqual(T{ .inner = 523 }, copy.items[0]);
}

test "cloneArrayList struct no clone()" {
    const T = testStructNoClone;
    const a = std.testing.allocator;
    var list: std.ArrayList(T) = .empty;
    defer list.deinit(a);
    try list.append(a, T{ .inner = 523 });
    var copy = try cloneArrayList(std.testing.allocator, T, list);
    defer copy.deinit(a);
    try std.testing.expectEqual(1, copy.items.len);
    try std.testing.expectEqual(T{ .inner = 523 }, copy.items[0]);
}

test "hasParameter" {
    //has clone with allocator parameter at position 1
    try std.testing.expect(hasParameter(testStructClone, "clone", std.mem.Allocator, 1));

    //beyond the parameter list
    try std.testing.expect(!hasParameter(testStructClone, "clone", std.mem.Allocator, 3));

    //wrong parameter position
    try std.testing.expect(!hasParameter(testStructClone, "clone", std.mem.Allocator, 0));

    //has clone method but no allocator parameter
    try std.testing.expect(!hasParameter(testStructCloneNoAllocator, "clone", std.mem.Allocator, 1));

    //no clone method
    try std.testing.expect(!hasParameter(u8, "clone", std.mem.Allocator, 0));
}
