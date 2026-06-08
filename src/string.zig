const std = @import("std");
const cloneList = @import("clone.zig").cloneArrayList;

const StringErrors = error{ InvalidArgument, EmptyString, ArgumentOutOfRange };

pub const empty_buffer = "";

pub fn string(T: type) type {
    return struct {
        const Self = @This();
        const sentinel: T = 0;

        a: std.mem.Allocator,
        i: std.ArrayList(T) = .empty,
        raw: ?[]T = null,
        rawSentinel: ?[:0]T = null,

        pub fn init(a: std.mem.Allocator, initial: ?[]const T) Self {
            var s = Self{
                .a = a,
                .i = std.ArrayList(T).empty,
            };
            if (initial) |value| _ = s.i.appendSlice(a, value) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn copy(a: std.mem.Allocator, source: string(T)) Self {
            var s = Self{ .a = a, .i = .empty };
            const copy_buffer = a.dupe(T, source.i.items) catch unreachable;
            defer a.free(copy_buffer);
            s.i.appendSlice(a, copy_buffer) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn from_arrayList(a: std.mem.Allocator, U: type, list: std.ArrayList(U)) string(U) {
            return .init(a, list.items);
        }

        pub fn from_slice(a: std.mem.Allocator, U: type, buffer: []const U) string(U) {
            return .init(a, buffer);
        }

        pub fn deinit(s: *Self) void {
            s.i.deinit(s.a);
            if (s.raw) |buffer| s.a.free(buffer);
            s.raw = null;
            if (s.rawSentinel) |buffer| s.a.free(buffer);
            s.rawSentinel = null;
        }

        pub fn clone(s: Self) Self {
            var c = Self{ .a = s.a, .i = std.ArrayList(T).empty, .raw = null, .rawSentinel = null };
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

        pub fn capacity(s: *Self) usize {
            return s.i.capacity;
        }

        pub fn data(s: *Self) []const T {
            return s.str();
        }

        pub fn empty(s: *Self) bool {
            return s.i.items.len == 0;
        }

        pub fn clear(s: *Self) *Self {
            defer s.set_internal_buffers();
            return s.set(empty_buffer);
        }

        pub fn resize(s: *Self, size: usize, value: ?T) *Self {
            if (size > s.i.items.len and value != null) {
                const growth = size - s.i.items.len;
                const slice_ = s.i.addManyAsSlice(s.a, growth) catch unreachable;
                if (value) |c| @memset(slice_, c);
            } else if (size < s.i.items.len) {
                s.i.shrinkAndFree(s.a, size);
            }
            s.set_internal_buffers();
            return s;
        }

        pub fn assign(s: *Self, buffer: []const T) *Self {
            return s.set(buffer);
        }

        pub fn at(s: *Self, pos: usize) !T {
            if (pos > s.i.items.len - 1) return StringErrors.InvalidArgument;
            return s.i.items[pos];
        }

        pub fn insert(s: *Self, pos: usize, value: []const T) *Self {
            const clampedPos = std.math.clamp(pos, 0, s.i.items.len);

            s.i.insertSlice(s.a, clampedPos, value) catch unreachable;

            s.set_internal_buffers();

            return s;
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

        pub fn find(s: *Self, needle: []const u8, index: usize, needle_len: usize) !i64 {
            if (index >= s.i.items.len) return StringErrors.InvalidArgument;
            if (needle_len > needle.len) return StringErrors.InvalidArgument;

            const needle_ = needle[0..needle_len];
            const haystack_ = s.i.items[index..];

            if (needle_.len > haystack_.len) return -1;

            const found = std.mem.find(T, haystack_, needle_);

            return if (found != null) @intCast(found.?) else @as(i64, -1);
        }

        pub fn rfind(s: *Self, needle: []const u8, index: usize) !i64 {
            const haystack_ = s.i.items[0..std.math.clamp(index, 0, s.i.items.len)];
            const idx = std.mem.findLast(T, haystack_, needle);
            return if (idx) |i| @as(i64, @intCast(i)) else -1;
        }

        pub fn find_first_of(s: *Self, needle: []const u8, index: usize, n: usize) !i64 {
            if (index >= s.i.items.len) return -1;

            const focus = s.i.items[index..];
            const needle_ = needle[0..n];

            for (focus, 0..) |c, i| {
                if (std.mem.containsAtLeastScalar2(T, needle_, c, 1)) {
                    return @as(i64, @intCast(i + index));
                }
            }
            return -1;
        }

        pub fn find_last_of(s: *Self, needle: []const u8, index: usize, n: usize) !i64 {
            const haystack_ = s.i.items[0..std.math.clamp(index, 0, s.i.items.len)];
            const needle_ = needle[0..n];

            var idx: usize = haystack_.len - 1;
            while (idx > 0) : (idx -= 1) {
                if (std.mem.containsAtLeastScalar2(T, needle_, haystack_[idx], 1)) {
                    return @as(i64, @intCast(idx));
                }
            }

            return -1;
        }

        pub fn find_first_not_of(s: *Self, notlist: []const u8, index: usize, n: usize) !i64 {
            if (index >= s.i.items.len) return -1;

            const haystack_ = s.i.items[index..];
            const notlist_ = notlist[0..n];

            for (haystack_, 0..) |needle, i| {
                if (!std.mem.containsAtLeastScalar2(T, notlist_, needle, 1)) {
                    return @as(i64, @intCast(i + index));
                }
            }
            return -1;
        }

        pub fn find_last_not_of(s: *Self, needle: []const u8, index: usize, n: usize) !i64 {
            const haystack_ = s.i.items[0..std.math.clamp(index, 0, s.i.items.len)];
            const needle_ = needle[0..n];

            var idx: usize = haystack_.len - 1;
            while (idx > 0) : (idx -= 1) {
                if (!std.mem.containsAtLeastScalar2(T, needle_, haystack_[idx], 1)) {
                    return @as(i64, @intCast(idx));
                }
            }

            return -1;
        }

        pub fn compare(s: *Self, b: []const T) !i8 {
            return try s.comparen(0, s.i.items.len, b, -1);
        }

        pub fn comparen(s: *Self, pos: usize, len: usize, b: []const T, n: i32) !i8 {
            if (pos >= s.i.items.len) return StringErrors.ArgumentOutOfRange;
            const num_of_chars: usize = @intCast(if (n < 0) @max(s.i.items.len, b.len) else @as(u64, @intCast(n)));
            const compared = s.i.items[pos..std.math.clamp(pos + len, pos, s.i.items.len)];
            const comparing = b[0..std.math.clamp(num_of_chars, 0, b.len)];

            var idx: usize = 0;
            while (idx < comparing.len and idx < compared.len and idx < num_of_chars) : (idx += 1) {
                const c = compared[idx];
                // compare characters from  each string
                if (c > comparing[idx]) {
                    return 1;
                } else if (comparing[idx] > c) {
                    return -1;
                }
            }

            if (idx == num_of_chars) {
                return 0;
            }

            //if we run out of characters in both strings at the same length
            if (idx == compared.len and idx == comparing.len) {
                return 0;
            }

            //haven't reached n, exhausted comparedcharacters
            if (idx == compared.len and idx < comparing.len) {
                return -1;
            }

            //haven't reached n, exhausted comparing characters
            if (idx == comparing.len and idx < compared.len) {
                return 1;
            }
            return 0;
        }

        pub fn span(s: *Self, index: usize, len: usize) string(T) {
            return s.slice(index, len);
        }

        pub fn slice(s: *Self, index: usize, len: usize) string(T) {
            if (index >= s.i.items.len) return string(T).init(s.a, empty_buffer);
            const span_ = s.a.dupe(T, s.i.items[index..std.math.clamp(len, 0, s.i.items.len)]) catch unreachable;
            defer s.a.free(span_);
            const str_span = string(T).init(s.a, span_);
            return str_span;
        }

        inline fn set(s: *Self, value: []T) *Self {
            s.i.clearRetainingCapacity();
            const copy_buffer = s.a.dupe(T, value) catch unreachable;
            defer s.a.free(copy_buffer);
            s.i.appendSlice(s.a, copy_buffer) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        //caller gets a newly allocated []const T that they must free
        pub fn str(s: *Self) []T {
            s.set_internal_buffers();
            return s.raw.?;
        }

        pub fn strSentinel(s: *Self) [:sentinel]T {
            s.set_internal_buffers();
            return s.rawSentinel.?;
        }

        //set contents of buffer and return buffer length, caller is responsible for freeing buffer
        pub fn stru(s: *Self, buffer: []T) usize {
            buffer = s.a.dupe(T, s.i.items);
            return buffer.len;
        }

        //set contents of buffer with sentinel value and return buffer length, caller is responsible for freeing buffer
        pub fn strSentinelu(s: *Self, buffer: []T) usize {
            buffer = s.a.dupeSentinel(T, s.i.items, sentinel);
            return buffer.len;
        }

        inline fn set_internal_buffers(s: *Self) void {
            if (s.raw) |previous| s.a.free(previous);
            s.raw = s.a.dupe(T, s.i.items) catch unreachable;
            if (s.rawSentinel) |previous| s.a.free(previous);
            s.rawSentinel = s.a.dupeSentinel(T, s.i.items, sentinel) catch unreachable;
        }
    };
}

test "instantiation" {
    var str = string(u8).init(std.testing.allocator, empty_buffer);
    defer str.deinit();
    _ = &str;
}

test "copy constructor" {
    const a = std.testing.allocator;

    var str_0 = string(u8).init(a, "first");
    defer str_0.deinit();

    try std.testing.expectEqualStrings("first", str_0.str());

    var str_1 = string(u8).copy(a, str_0);
    defer str_1.deinit();

    try std.testing.expectEqualStrings("first", str_1.str());
    try std.testing.expectEqual(str_0.length(), str_1.length());
}

test "empty string error" {
    var str = string(u8).init(std.testing.allocator, empty_buffer);
    defer str.deinit();
    const toTrim = "\n\r";
    try std.testing.expectError(StringErrors.EmptyString, str.trimRight(toTrim));
}

test "empty string" {
    try std.testing.expectEqualStrings("", empty_buffer);
    try std.testing.expectEqual(0, empty_buffer.len);
}

test "append" {
    var str = string(u8).init(std.testing.allocator, empty_buffer);
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
    try std.testing.expectEqualStrings(empty_buffer, sub_beyond);
}

test "length" {
    const a = std.testing.allocator;

    var str_0 = string(u8).init(a, empty_buffer);
    defer str_0.deinit();

    try std.testing.expectEqual(0, str_0.length());

    _ = str_0.append("1234567");
    try std.testing.expectEqual(7, str_0.length());
}

test "capacity" {
    const a = std.testing.allocator;

    var str_0 = string(u8).init(a, "some content");
    defer str_0.deinit();

    try std.testing.expect(str_0.capacity() > 0);
}

test "is_empty" {
    var str_0 = string(u8).init(std.testing.allocator, empty_buffer);
    defer str_0.deinit();

    try std.testing.expectEqual(0, str_0.length());
    try std.testing.expect(str_0.empty());
}

test "clear" {
    var str_0 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    try std.testing.expectEqual("content for your pleasure".len, str_0.length());
    try std.testing.expect(!str_0.empty());

    _ = str_0.clear();

    try std.testing.expectEqual(0, str_0.length());
    try std.testing.expect(str_0.empty());
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

    const sentineled = str_0.strSentinel();
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

test "find" {
    const a = std.testing.allocator;

    const test_bed = "There are two needles in this haystack with needles.";

    const needle_0 = "needle";

    // from str beginning, find first needle
    var str_0 = string(u8).init(a, test_bed);
    defer str_0.deinit();

    const found_0 = try str_0.find(needle_0, 0, needle_0.len);

    try std.testing.expect(found_0 >= 0);
    try std.testing.expectEqual(14, found_0);

    // starting from after first needle, find second needle
    var str_2 = string(u8).init(a, test_bed);
    defer str_2.deinit();

    const found_2 = str_2.find(needle_0, @as(usize, @intCast(found_0)) + 1, needle_0.len);

    try std.testing.expectEqual(29, found_2);

    // starting from str beginning, find the first 6 characters of the needle
    var str_1 = string(u8).init(a, test_bed);
    defer str_1.deinit();

    const needle_1 = "needles are small";
    const found_1 = try str_1.find(needle_1, 0, 6);

    try std.testing.expectEqual(14, found_1);

    var str_3 = string(u8).init(a, test_bed);
    defer str_3.deinit();

    const needle_3 = ".";
    const found_3 = str_3.find(needle_3, 0, needle_3.len);

    try std.testing.expectEqual(51, found_3);
}

test "rfind" {
    const a = std.testing.allocator;

    const test_base = "The sixth sick sheik's sixth sheep's sick.";

    var str_matchsecond = string(u8).init(a, test_base);
    defer str_matchsecond.deinit();

    const key_matchsecond = "sixth";
    const found_secondmatch = try str_matchsecond.rfind(key_matchsecond, str_matchsecond.length() - 1);

    try std.testing.expectEqual(23, found_secondmatch);

    var str_nomatch = string(u8).init(a, test_base);
    defer str_nomatch.deinit();

    const key_nomatch = "seventh";
    const found_nomatch = try str_nomatch.rfind(key_nomatch, str_nomatch.length());

    try std.testing.expectEqual(-1, found_nomatch);

    // search before the first match from the end
    var str_earlier = string(u8).init(a, test_base);
    defer str_earlier.deinit();

    const key_earlier = "sixth";
    const found_earlier = try str_nomatch.rfind(key_earlier, @as(usize, @intCast(found_secondmatch)));

    try std.testing.expectEqual(4, found_earlier);
}

test "find_first_of" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_match_first = string(u8).init(a, test_base);
    defer str_match_first.deinit();

    const first_match = str_match_first.find_first_of("t", 0, 1);

    try std.testing.expectEqual(2, first_match);

    var str_match_none = string(u8).init(a, test_base);
    defer str_match_none.deinit();
    const match_none = str_match_none.find_first_of("u", 0, 1);

    try std.testing.expectEqual(-1, match_none);

    var str_match_second = string(u8).init(a, test_base);
    defer str_match_second.deinit();
    const match_second = str_match_second.find_first_of("t", 3, 1);

    try std.testing.expectEqual(5, match_second);

    var str_match_second_none = string(u8).init(a, test_base);
    defer str_match_second_none.deinit();
    const match_second_none = str_match_second_none.find_first_of("t", 29, 1);

    try std.testing.expectEqual(-1, match_second_none);

    var str_match_none_beyond = string(u8).init(a, test_base);
    defer str_match_none_beyond.deinit();
    const match_none_beyond = str_match_none_beyond.find_first_of("t", 55, 1);

    try std.testing.expectEqual(-1, match_none_beyond);

    var str_match_slice = string(u8).init(a, test_base);
    defer str_match_slice.deinit();
    const match_slice = str_match_slice.find_first_of("ga", 0, 2);

    try std.testing.expectEqual(12, match_slice);

    var str_match_case = string(u8).init(a, test_base);
    defer str_match_case.deinit();
    const match_case = str_match_case.find_first_of("a", 0, 1);

    try std.testing.expectEqual(20, match_case);

    //find first character of the first character from the given string
    var str_match_slice_substr = string(u8).init(a, test_base);
    defer str_match_slice_substr.deinit();
    const match_slice_substr = str_match_slice_substr.find_first_of("ag", 0, 1);

    try std.testing.expectEqual(20, match_slice_substr);
}

test "find_last_of" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_match_first = string(u8).init(a, test_base);
    defer str_match_first.deinit();

    const first_match = try str_match_first.find_last_of("t", test_base.len, 1);

    try std.testing.expectEqual(28, first_match);

    var str_match_none = string(u8).init(a, test_base);
    defer str_match_none.deinit();
    const match_none = try str_match_none.find_last_of("u", test_base.len, 1);

    try std.testing.expectEqual(-1, match_none);

    var str_match_second = string(u8).init(a, test_base);
    defer str_match_second.deinit();
    const match_second = try str_match_second.find_last_of("t", test_base.len - 6, 1);

    try std.testing.expectEqual(@as(i64, @intCast(test_base.len - 9)), match_second);

    var str_match_second_none = string(u8).init(a, test_base);
    defer str_match_second_none.deinit();
    const match_second_none = try str_match_second_none.find_last_of("t", 2, 1);

    try std.testing.expectEqual(-1, match_second_none);

    var str_match_none_beyond = string(u8).init(a, test_base);
    defer str_match_none_beyond.deinit();
    const match_none_beyond = try str_match_none_beyond.find_last_of("t", 1, 1);

    try std.testing.expectEqual(-1, match_none_beyond);

    var str_match_slice = string(u8).init(a, test_base);
    defer str_match_slice.deinit();
    const match_slice = try str_match_slice.find_last_of("ga", test_base.len, 2);

    try std.testing.expectEqual(20, match_slice);

    var str_match_case = string(u8).init(a, test_base);
    defer str_match_case.deinit();
    const match_case = try str_match_case.find_last_of("a", test_base.len, 1);

    try std.testing.expectEqual(20, match_case);
}

test "find_first_not_of" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_match_first = string(u8).init(a, test_base);
    defer str_match_first.deinit();

    const first_match = str_match_first.find_first_not_of("t", 0, 1);

    try std.testing.expectEqual(0, first_match);

    var str_match_none = string(u8).init(a, test_base);
    defer str_match_none.deinit();
    const match_none = str_match_none.find_first_not_of(test_base, 0, test_base.len);

    try std.testing.expectEqual(-1, match_none);

    var str_match_second = string(u8).init(a, test_base);
    defer str_match_second.deinit();

    const match_second_needle = "A es";
    const match_second = str_match_second.find_first_not_of(match_second_needle, 4, match_second_needle.len);

    try std.testing.expectEqual(5, match_second);

    var str_match_second_none = string(u8).init(a, test_base);
    defer str_match_second_none.deinit();
    const match_second_none = str_match_second_none.find_first_not_of(".", 29, 1);

    try std.testing.expectEqual(-1, match_second_none);

    var str_match_none_beyond = string(u8).init(a, test_base);
    defer str_match_none_beyond.deinit();
    const match_none_beyond = str_match_none_beyond.find_first_not_of("t", 55, 1);

    try std.testing.expectEqual(-1, match_none_beyond);

    var str_match_case = string(u8).init(a, test_base);
    defer str_match_case.deinit();
    const match_case = str_match_case.find_first_not_of("a", 0, 1);

    try std.testing.expectEqual(0, match_case);

    //find first character of the first character from the given string
    var str_match_slice_substr = string(u8).init(a, test_base);
    defer str_match_slice_substr.deinit();
    const match_slice_substr = str_match_slice_substr.find_first_not_of("A test strin", 0, "A test strin".len - 3);

    try std.testing.expectEqual(@as(i64, @intCast("A test strin".len - 3)), match_slice_substr);

    // Passing in an empty notlist by n parameter of 0 means we are looking for characters not present
    // in a "none of the above" search set, which will cause it to return the index of the very first
    // character in your target string

    var str_match_empty_needle_by_n = string(u8).init(a, test_base);
    defer str_match_empty_needle_by_n.deinit();
    const needle_empty_needle_by_n = "A test strin";
    const match_empty_needle_by_n = str_match_slice_substr.find_first_not_of(needle_empty_needle_by_n, 0, 0);

    try std.testing.expectEqual(0, match_empty_needle_by_n);

    var str_match_empty_needle = string(u8).init(a, test_base);
    defer str_match_empty_needle.deinit();
    const needle_empty_needle = "";
    const match_empty_needle = str_match_slice_substr.find_first_not_of(needle_empty_needle, 0, 0);

    try std.testing.expectEqual(0, match_empty_needle);
}

test "find_last_not_of" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.     \r\n ";

    var str_match_last = string(u8).init(a, test_base);
    defer str_match_last.deinit();

    const first_match = try str_match_last.find_last_not_of("t", test_base.len, 1);

    try std.testing.expectEqual(@as(i64, @intCast(test_base.len - 1)), first_match);

    var str_match_nonwhitespace = string(u8).init(a, test_base);
    defer str_match_nonwhitespace.deinit();
    const match_nonwhitespace = try str_match_nonwhitespace.find_last_not_of(" \t\r\n", test_base.len, 4);

    try std.testing.expectEqual(29, match_nonwhitespace);

    var str_match_second = string(u8).init(a, test_base);
    defer str_match_second.deinit();
    const match_second = try str_match_second.find_last_not_of("t.", test_base.len - 10, 2);

    try std.testing.expectEqual(27, match_second);

    var str_match_second_none = string(u8).init(a, test_base);
    defer str_match_second_none.deinit();
    const match_second_none = try str_match_second_none.find_last_not_of(test_base, test_base.len, test_base.len);

    try std.testing.expectEqual(-1, match_second_none);

    var str_match_none_beyond = string(u8).init(a, test_base);
    defer str_match_none_beyond.deinit();
    const match_none_beyond = try str_match_none_beyond.find_last_not_of("t", 1, 1);

    try std.testing.expectEqual(-1, match_none_beyond);

    var str_match_case = string(u8).init(a, test_base);
    defer str_match_case.deinit();

    const test_base_uppercase = "A TEST STRING OF GREAT IMPORT.     \r\n ";
    const match_case = try str_match_case.find_last_not_of(test_base_uppercase, test_base.len, test_base_uppercase.len);

    try std.testing.expectEqual(28, match_case);
}

test "compare" {
    const a = std.testing.allocator;

    const test_base_a = "A test string of great import.     \r\n ";
    const test_base_b = "A test string of lesser import.     \r\n ";

    var str_a = string(u8).init(a, test_base_a);
    defer str_a.deinit();
    var str_b = string(u8).init(a, test_base_b);
    defer str_b.deinit();

    try std.testing.expectEqual(-1, str_a.compare(str_b.str()));

    try std.testing.expectEqual(0, str_a.compare(str_a.str()));

    try std.testing.expectEqual(1, str_b.compare(str_a.str()));

    const test_base_a_longer = "A test string of great import.     \r\n 111111111111";

    var str_a_longer = string(u8).init(a, test_base_a_longer);
    defer str_a_longer.deinit();

    try std.testing.expectEqual(-1, str_a.compare(str_a_longer.str()));

    try std.testing.expectEqual(1, str_a_longer.compare(str_a.str()));
}

test "comparen" {
    const a = std.testing.allocator;

    const test_base_a = "A test string of great import.     \r\n ";
    const test_base_b = "A test string of lesser import.     \r\n ";

    var str_a = string(u8).init(a, test_base_a);
    defer str_a.deinit();
    var str_b = string(u8).init(a, test_base_b);
    defer str_b.deinit();

    // Given equal inputs, when comparing full ranges, then expect equality.
    try std.testing.expectEqual(0, str_a.comparen(0, str_a.length(), str_a.str(), @intCast(str_a.length())));

    // symmetry: forward mismatch (a vs b) should be negative.
    try std.testing.expectEqual(-1, str_a.comparen(0, str_a.length(), str_b.str(), @intCast(str_b.length())));

    // Given equal inputs, when repeated for stability, then result remains equal.
    try std.testing.expectEqual(0, str_a.comparen(0, str_a.length(), str_a.str(), @intCast(str_a.length())));

    // symmetry: reverse mismatch (b vs a) should be positive.
    try std.testing.expectEqual(1, str_b.comparen(0, str_b.length(), str_a.str(), @intCast(str_a.length())));

    const test_base_a_longer = "A test string of great import.     \r\n 111111111111";

    var str_a_longer = string(u8).init(a, test_base_a_longer);
    defer str_a_longer.deinit();

    // Given shared prefix with different total lengths, when n exceeds lhs window, then lhs exhaustion decides ordering.
    try std.testing.expectEqual(-1, str_a.comparen(0, str_a.length(), str_a_longer.str(), @intCast(str_a_longer.length())));

    // long compared to shorter, only comparing shorter's length of characters
    try std.testing.expectEqual(0, str_a_longer.comparen(0, str_a_longer.length(), str_a.str(), @intCast(str_a.length())));

    // boundary: pos out of range should return ArgumentOutOfRange.
    try std.testing.expectError(StringErrors.ArgumentOutOfRange, str_a.comparen(str_a.length() + 1, str_a.length(), str_a.str(), 1));

    // boundary: n longer than compared slice keeps exhaustion behavior stable.
    try std.testing.expectEqual(-1, str_a.comparen(0, str_a.length(), str_a_longer.str(), @intCast(str_a.length() + 1)));

    // boundary: non-zero pos changes the lhs comparison window.
    try std.testing.expectEqual(-1, str_a.comparen(1, str_a.length(), str_a_longer.str(), @intCast(str_b.length())));

    // regression: equal 5-byte prefix must compare as equal regardless of longer suffix.
    try std.testing.expectEqual(0, str_a.comparen(0, 5, str_a_longer.str(), 5));

    var str_small = string(u8).init(a, "abc");
    defer str_small.deinit();

    // len == 0 and n == 0 yields two empty windows.
    try std.testing.expectEqual(0, str_small.comparen(0, 0, "xyz", 0));

    // len == 0 but n > 0 means compared window exhausts first.
    try std.testing.expectEqual(-1, str_small.comparen(0, 0, "xyz", 2));

    // n == 0 but len > 0 means comparing window exhausts first.
    try std.testing.expectEqual(0, str_small.comparen(0, 2, "xyz", 0));

    // n > b.len should clamp to b.len and compare only available rhs bytes, but still exhaust rhs
    try std.testing.expectEqual(1, str_small.comparen(0, 3, "ab", 9));

    // a->substr(pos, len).compare(b(s, n))
    var str_cpp = string(u8).init(a, "apples");
    defer str_cpp.deinit();

    // equal prefixes over n chars should compare equal.
    try std.testing.expectEqual(0, str_cpp.comparen(0, str_cpp.length(), "applecore", 5));

    // len extending past end should clamp compared substring and still compare equal.
    try std.testing.expectEqual(0, str_cpp.comparen(1, 99, "pplesauce", 5));

    var str_cpp_shorter = string(u8).init(a, "apple");
    defer str_cpp_shorter.deinit();

    try std.testing.expectEqual(-1, str_cpp_shorter.comparen(0, str_cpp_shorter.length(), "applepie", 8));
}

test "span and slice" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.     \r\n ";

    var str_0 = string(u8).init(a, test_base);
    defer str_0.deinit();

    var slice = str_0.slice(0, 4);
    defer slice.deinit();
    try std.testing.expectEqualStrings("A te", slice.str());
    try std.testing.expectEqual(4, slice.length());

    var span = str_0.span(0, 4);
    defer span.deinit();
    try std.testing.expectEqualStrings("A te", span.str());
    try std.testing.expectEqual(4, span.length());
}

test "from_writer" {}

test "from_slice" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.     \r\n ";
    var str_0 = string(T).from_slice(a, T, empty_buffer);
    defer str_0.deinit();
    try std.testing.expectEqual(0, str_0.length());

    var str_1 = string(T).from_slice(a, T, test_base);
    defer str_1.deinit();
    try std.testing.expectEqual(test_base.len, str_1.length());
    try std.testing.expectEqual(0, str_1.compare(test_base));
    try std.testing.expectEqualStrings(test_base, str_1.str());
}

test "from_arrayList" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.     \r\n ";

    var list_0: std.ArrayList(T) = .empty;
    defer list_0.deinit(a);
    var str_0 = string(T).from_arrayList(a, T, list_0);
    defer str_0.deinit();
    try std.testing.expectEqual(0, str_0.length());

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    try list_1.appendSlice(a, test_base);
    var str_1 = string(T).from_arrayList(a, T, list_1);
    defer str_1.deinit();
    try std.testing.expectEqual(test_base.len, str_1.length());
    try std.testing.expectEqual(0, str_1.compare(test_base));
    try std.testing.expectEqualStrings(test_base, str_1.str());
}

//TODO: use string(T) as parameters instead of []const T
