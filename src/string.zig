const std = @import("std");
const cloneList = @import("clone.zig").cloneArrayList;

const StringErrors = error{ InvalidArgument, EmptyString };

pub const empty = "";

pub fn string(T: type) type {
    return struct {
        const Self = @This();

        a: std.mem.Allocator,
        i: std.ArrayList(T) = .empty,
        raw: ?[]T = null,
        rawSentinel: ?[:0]T = null,

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
            if (s.raw) |buffer| s.a.free(buffer);
            s.raw = null;
            if (s.rawSentinel) |buffer| s.a.free(buffer);
            s.rawSentinel = null;
        }

        pub fn clone(s: Self) Self {
            var c = Self{
                .a = s.a,
                .i = std.ArrayList(T).empty,
            };
            if (s.raw) |raw| c.raw = s.a.dupe(T, raw) catch unreachable;
            if (s.rawSentinel) |rawSentinel| c.rawSentinel = s.a.dupeSentinel(T, rawSentinel, 0) catch unreachable;
            c.i = s.i.clone(s.a) catch unreachable;
            return c;
        }

        pub fn append(s: *Self, suffix: []const T) *Self {
            s.i.appendSlice(s.a, suffix) catch unreachable;
            s.set_internal_buffers();
            return s;
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

            s.set_internal_buffers();
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

            //s.set sets internal buffers
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

            //s.set sets internal buffers
            return s.set(subString).str();
        }

        pub fn length(s: *Self) usize {
            return s.i.items.len;
        }

        pub fn is_empty(s: *Self) bool {
            return s.i.items.len == 0;
        }

        pub fn clear(s: *Self) *Self {
            defer s.set_internal_buffers();
            return s.set(empty);
        }

        pub fn resize(s: *Self, size: usize, value: ?T) *Self {
            if (size > s.i.items.len and value != null) {
                const growth = size - s.i.items.len;
                const slice = s.i.addManyAsSlice(s.a, growth) catch unreachable;
                @memset(slice, value.?);
            } else if (size < s.i.items.len) {
                s.i.shrinkAndFree(s.a, size);
            }
            s.set_internal_buffers();
            return s;
        }

        pub fn at(s: *Self, pos: usize) !T {
            if (pos > s.i.items.len - 1) return StringErrors.InvalidArgument;
            return s.i.items[pos];
        }

        pub fn insert(s: *Self, pos: usize, slice: []const T) *Self {
            const clampedPos = std.math.clamp(pos, 0, s.i.items.len);

            s.i.insertSlice(s.a, clampedPos, slice) catch unreachable;

            s.set_internal_buffers();

            return s;
        }

        //caller gets a newly allocated []const T that they must free
        pub fn str(s: *Self) []T {
            s.set_internal_buffers();
            return s.raw.?;
        }

        pub fn strSentinel(s: *Self) ![:0]T {
            s.set_internal_buffers();
            return s.rawSentinel.?;
        }

        pub fn erase(s: *Self, index: usize, count: usize) *Self {
            const start = std.math.clamp(index, 0, s.i.items.len - 1);
            const end = @min(start + count, s.i.items.len - 1);

            var after: std.ArrayList(T) = .empty;
            defer after.deinit(s.a);

            for (s.i.items, 0..) |item, i| {
                if (i < start or i >= end) {
                    after.append(s.a, item) catch unreachable;
                }
            }

            s.i.deinit(s.a);
            s.i = cloneList(s.a, T, after) catch unreachable;

            s.set_internal_buffers();
            return s;
        }

        pub fn replace(s: *Self, index: usize, count: usize, buffer: []const u8) *Self {
            var after: std.ArrayList(T) = .empty;
            defer after.deinit(s.a);

            var s_idx: usize = 0;
            while (s_idx <= s.i.items.len) : (s_idx += 1) {
                //if we are before the index of replacement
                if (s_idx < index or
                    // if we are after the substr replacement and still have str left
                    (s_idx >= index + @min(buffer.len, count)) and s_idx < s.i.items.len)
                {
                    after.append(s.a, s.i.items[s_idx]) catch unreachable;
                } else if (s_idx == index) {
                    //insert substr at index
                    after.appendSlice(s.a, buffer) catch unreachable;
                }
            }

            s.i.deinit(s.a);
            s.i = cloneList(s.a, T, after) catch unreachable;

            s.set_internal_buffers();
            return s;
        }

        fn set(s: *Self, new: []const T) *Self {
            s.i.clearAndFree(s.a);
            s.i.appendSlice(s.a, new) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        inline fn set_internal_buffers(s: *Self) void {
            if (s.raw) |previous| s.a.free(previous);
            s.raw = s.a.dupe(T, s.i.items) catch unreachable;
            if (s.rawSentinel) |previous| s.a.free(previous);
            s.rawSentinel = s.a.dupeSentinel(T, s.i.items, 0) catch unreachable;
        }
    };
}

test "instantiation" {
    var str = string(u8).init(std.testing.allocator, empty);
    defer str.deinit();
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
    _ = str.append("hi");
    try std.testing.expectEqualStrings("hi", str.str());

    _ = str.append("hi");
    try std.testing.expectEqualStrings("hihi", str.str());
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

    _ = str_0.append("1234567");
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

test "resize" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    var resized = str_0.resize(5, 'A');

    try std.testing.expectEqualStrings("conte", resized.str());
    try std.testing.expectEqual(5, resized.length());

    var str_1 = string(u8).init(std.testing.allocator, "12345");
    defer str_1.deinit();
    var resizedAdd = str_1.resize(9, 'a');

    try std.testing.expectEqualStrings("12345aaaa", resizedAdd.str());
    try std.testing.expectEqual(9, resizedAdd.length());
}

test "at" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    try std.testing.expectEqual('c', try str_0.at(0));
    try std.testing.expectEqual('e', try str_0.at(4));
    try std.testing.expectError(StringErrors.InvalidArgument, str_0.at(555));
}

test "strSentinel" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    const sentineled = try str_0.strSentinel();
    const expectedSentineled = "content for your pleasure".*;
    try std.testing.expectEqualStrings(&expectedSentineled, sentineled);
    try std.testing.expectEqual('e', sentineled[24]);
    try std.testing.expectEqual('e', sentineled[24]);
    try std.testing.expectEqual(25, std.mem.indexOfSentinel(u8, 0, sentineled));
}

test "insert" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    var inserted_before = str_0.insert(0, "you look like you need some insurance");

    try std.testing.expectEqual(62, inserted_before.length());
    try std.testing.expectEqualStrings("you look like you need some insurancecontent for your pleasure", inserted_before.str());

    var str_1 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_1.deinit();

    var inserted_middle = str_1.insert(10, "you look like you need some insurance");

    try std.testing.expectEqual(62, inserted_middle.length());
    try std.testing.expectEqualStrings("content foyou look like you need some insurancer your pleasure", inserted_middle.str());

    var str_2 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_2.deinit();

    var inserted_after = str_2.insert(27, "you look like you need some insurance");

    try std.testing.expectEqual(62, inserted_after.length());
    try std.testing.expectEqualStrings("content for your pleasureyou look like you need some insurance", inserted_after.str());
}

test "erase" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    _ = str_0.erase(0, 8);

    try std.testing.expectEqualStrings("for your pleasure", str_0.str());

    var str_1 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_1.deinit();

    _ = str_1.erase(50, 10);

    try std.testing.expectEqualStrings("content for your pleasure", str_1.str());

    var str_2 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_2.deinit();

    _ = str_2.erase(5, 4);

    try std.testing.expectEqualStrings("conteor your pleasure", str_2.str());
}

test "replace" {
    const original = "this is a test string.";

    //at beginning and within string
    var str_0 = string(u8).init(std.testing.allocator, original);
    defer str_0.deinit();

    _ = str_0.replace(9, 5, "n example");

    try std.testing.expectEqualStrings("this is an example string.", str_0.str());
    try std.testing.expectEqual(26, str_0.length());

    //within string, substr beyond end of str
    var str_1 = string(u8).init(std.testing.allocator, original);
    defer str_1.deinit();

    _ = str_1.replace(21, 5, " and example");

    try std.testing.expectEqualStrings("this is a test string and example", str_1.str());
    try std.testing.expectEqual(33, str_1.length());

    //within string, substr shorter than index + count
    var str_2 = string(u8).init(std.testing.allocator, original);
    defer str_2.deinit();

    _ = str_2.replace(15, 10, "for you");

    try std.testing.expectEqualStrings("this is a test for you", str_2.str());
    try std.testing.expectEqual(22, str_2.length());

    //end of str, substr longer than index + count
    var str_3 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_3.deinit();

    _ = str_3.replace(25, 5, " and consumption");

    try std.testing.expectEqualStrings("content for your pleasure and consumption", str_3.str());
    try std.testing.expectEqual(41, str_3.length());

    //end of str, substr shorter than index + count
    var str_4 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_4.deinit();

    _ = str_4.replace(25, 5, "s");

    try std.testing.expectEqualStrings("content for your pleasures", str_4.str());
    try std.testing.expectEqual(26, str_4.length());
}

test "find" {}

test "rfind" {}

test "compare" {}

test "fromWriter" {}

test "fromSlice" {}

test "fromArrayList" {}
