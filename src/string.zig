const std = @import("std");
const cloneList = @import("clone.zig").cloneArrayList;

pub const StringErrors = error{ InvalidArgument, EmptyString, ArgumentOutOfRange, NullArguement };

pub const empty_buffer = "";

pub fn string(T: type) type {
    return struct {
        const Self = @This();
        pub const sentinel: T = 0;
        pub const npos: i64 = -1;

        a: std.mem.Allocator,
        i: std.ArrayList(T) = .empty,
        raw: ?[]T = null,
        rawSentinel: ?[:0]T = null,

        _disposed: bool = false,

        pub fn init(a: std.mem.Allocator, initial: ?[]const T) Self {
            var s = Self{
                .a = a,
                .i = std.ArrayList(T).empty,
                ._disposed = false,
            };
            if (initial) |value| _ = s.i.appendSlice(a, value) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn copy(a: std.mem.Allocator, source: string(T)) Self {
            var s = Self{ .a = a, .i = .empty, ._disposed = false };
            const copy_buffer = a.dupe(T, source.i.items) catch unreachable;
            defer a.free(copy_buffer);
            s.i.appendSlice(a, copy_buffer) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn from_arrayList(a: std.mem.Allocator, list: std.ArrayList(T)) Self {
            return .init(a, list.items);
        }

        pub fn from_slice(a: std.mem.Allocator, buffer: []const T) Self {
            return .init(a, buffer);
        }

        pub fn deinit(s: *Self) void {
            if (!s._disposed) {
                s._disposed = true;

                s.i.deinit(s.a);
                if (s.raw) |buffer| s.a.free(buffer);
                s.raw = null;
                if (s.rawSentinel) |buffer| s.a.free(buffer);
                s.rawSentinel = null;
            }
        }

        pub fn clone(s: Self) Self {
            var c = Self{ .a = s.a, .i = std.ArrayList(T).empty, .raw = null, .rawSentinel = null, ._disposed = false };
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

        pub fn back(s: *Self) !?T {
            if (s.empty()) return StringErrors.EmptyString;
            return s.i.items[s.i.items.len - 1];
        }

        pub fn starts_with(s: *Self, buffer: []const T) !bool {
            if (buffer.len > s.length()) return false;

            return (try s.find(buffer, 0, @intCast(buffer.len))) == 0;
        }

        pub fn ends_with(s: *Self, buffer: []const T) !bool {
            if (buffer.len > s.length()) return false;

            const relevant = s.i.items[s.i.items.len - buffer.len .. s.i.items.len];

            return std.mem.eql(T, relevant, buffer);
        }

        pub fn contains(s: *Self, buffer: []const T) !bool {
            return try s.find(buffer, 0, @intCast(buffer.len)) != npos;
        }

        pub fn trimRight(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            const last: usize = @intCast(try s.find_last_not_of(charactersToTrim, @intCast(s.length()), npos));

            const trimmed = try s.a.dupe(T, s.i.items[0 .. last + 1]);
            defer s.a.free(trimmed);

            return s.set(trimmed).str();
        }

        pub fn trimLeft(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            const first: usize = @intCast(try s.find_first_not_of(charactersToTrim, 0, charactersToTrim.len));

            const trimmed = try s.a.dupe(T, s.i.items[first..s.i.items.len]);
            defer s.a.free(trimmed);

            return s.set(trimmed).str();
        }

        pub fn trim(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            const first: usize = @intCast(try s.find_first_not_of(charactersToTrim, 0, charactersToTrim.len));
            const last: usize = @intCast(try s.find_last_not_of(charactersToTrim, @intCast(s.length()), @as(i64, @intCast(charactersToTrim.len))) + 1);

            const trimmed = try s.a.dupe(T, s.i.items[first..last]);
            defer s.a.free(trimmed);

            //s.set sets internal buffers
            return s.set(trimmed).str();
        }

        pub fn substr(s: *Self, index: usize, count: i64) ![]T {
            if (index > s.i.items.len) return StringErrors.ArgumentOutOfRange;

            const char_count: usize = if (count == npos) s.i.items.len else @intCast(count);
            const start: usize = index;
            const end: usize = std.math.clamp(index + char_count, index, s.i.items.len);
            return try s.a.dupe(T, s.i.items[start..end]);
        }

        pub fn length(s: *Self) usize {
            return s.i.items.len;
        }

        pub fn size(s: *Self) usize {
            return s.length();
        }

        pub fn capacity(s: *Self) usize {
            return s.i.capacity;
        }

        pub fn compare(s: *Self, b: []const T) !i8 {
            return try s.comparen(0, s.i.items.len, b, -1);
        }

        pub fn comparen(s: *Self, pos: usize, len: usize, b: []const T, n: i32) !i8 {
            if (pos >= s.i.items.len) return StringErrors.ArgumentOutOfRange;
            const num_of_chars: usize = @intCast(if (n == npos) @max(s.i.items.len, b.len) else @as(u64, @intCast(n)));
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

        pub fn data(s: *Self) []const T {
            return s.str();
        }

        pub fn empty(s: *Self) bool {
            return s.i.items.len == 0;
        }

        pub fn fill(s: *Self, value: T, count: usize) *Self {
            var buffer = s.a.alloc(T, count) catch unreachable;
            _ = &buffer;
            defer s.a.free(buffer);

            if (T == u8) {
                @memset(buffer, value);
            } else {
                inline for (buffer) |element| {
                    element.* = value;
                }
            }

            return s.set(buffer);
        }

        pub fn clear(s: *Self) *Self {
            defer s.set_internal_buffers();
            return s.set(empty_buffer);
        }

        pub fn assign(s: *Self, buffer: []const T) *Self {
            return s.set(buffer);
        }

        pub fn at(s: *Self, pos: usize) !T {
            if (pos >= s.i.items.len) return StringErrors.InvalidArgument;
            return s.i.items[pos];
        }

        pub fn insert(s: *Self, pos: usize, value: []const T) *Self {
            const clampedPos = std.math.clamp(pos, 0, s.i.items.len);

            s.i.insertSlice(s.a, clampedPos, value) catch unreachable;

            s.set_internal_buffers();

            return s;
        }

        pub fn erase(s: *Self, pos: usize, len: i64) *Self {
            //could throw errors if pos is beyond string length, but won't.
            if (pos > s.i.items.len) return s;

            const erasure_len = if (len == npos) s.i.items.len else @as(usize, @intCast(len));
            const erasure_start = std.math.clamp(pos, 0, s.i.items.len);
            const erasure_end = @min(erasure_start + erasure_len, s.i.items.len);

            if (erasure_len == 0) return s;

            var remainder: std.ArrayList(T) = .empty;
            defer remainder.deinit(s.a);

            remainder.appendSlice(s.a, s.i.items[0..erasure_start]) catch unreachable;
            remainder.appendSlice(s.a, s.i.items[erasure_end..]) catch unreachable;

            const remaining = remainder.toOwnedSlice(s.a) catch unreachable;
            defer s.a.free(remaining);

            return s.set(remaining);
        }

        pub fn replace(s: *Self, pos: usize, len: i64, buffer: []const T) !*Self {
            return try replacen(s, pos, len, buffer, 0, @intCast(buffer.len));
        }

        pub fn replacen(s: *Self, pos: usize, len: i64, buffer: []const T, subpos: usize, sublen: i64) !*Self {
            if (pos > s.i.items.len) return StringErrors.ArgumentOutOfRange;
            if (subpos >= buffer.len) return StringErrors.ArgumentOutOfRange;

            const replacment_len = if (sublen == npos) buffer.len else @as(usize, @intCast(sublen));
            const replace_original_len: usize = if (len == npos) s.i.items.len - pos else @intCast(len);
            const replacement_buffer = buffer[subpos..std.math.clamp(subpos + replacment_len + 1, subpos, buffer.len)];
            const remainder_start = std.math.clamp(pos + replace_original_len, pos, s.i.items.len);

            var after: std.ArrayList(T) = .empty;
            defer after.deinit(s.a);

            // characters before replacement
            after.appendSlice(s.a, s.i.items[0..pos]) catch unreachable;
            // characters from replacement
            after.appendSlice(s.a, replacement_buffer) catch unreachable;
            // characters after replacement, and after len parameter to replace N characters from the original
            after.appendSlice(s.a, s.i.items[remainder_start..]) catch unreachable;

            s.i.deinit(s.a);
            s.i = cloneList(s.a, T, after) catch unreachable;

            s.set_internal_buffers();
            return s;
        }

        pub fn find(s: *Self, needle: []const T, index: usize, len: i64) !i64 {
            //if needle is empty, return index by cpp std standards
            if (needle.len == 0) return @intCast(index);

            if (index > s.i.items.len) return StringErrors.InvalidArgument;
            if (len > needle.len) return StringErrors.InvalidArgument;

            const needle_len = if (len == npos) needle.len else @as(usize, @intCast(len));
            const needle_ = needle[0..needle_len];
            const haystack_ = s.i.items[index..];

            if (needle_.len > haystack_.len) return -1;

            const found = std.mem.find(T, haystack_, needle_);

            return if (found) |value| @intCast(value) else @as(i64, npos);
        }

        pub fn rfind(s: *Self, needle: []const T, index: usize) !i64 {
            const haystack_ = s.i.items[0..std.math.clamp(index, 0, s.i.items.len)];
            const idx = std.mem.findLast(T, haystack_, needle);
            return if (idx) |i| @as(i64, @intCast(i)) else -1;
        }

        pub fn find_first_of(s: *Self, needle: []const T, index: usize, n: usize) !i64 {
            if (index >= s.i.items.len) return -1;

            const focus = s.i.items[index..];
            const needle_ = needle[0..std.math.clamp(n, 0, needle.len)];

            for (focus, 0..) |c, i| {
                if (std.mem.containsAtLeastScalar2(T, needle_, c, 1)) {
                    return @as(i64, @intCast(i + index));
                }
            }
            return -1;
        }

        pub fn find_last_of(s: *Self, needle: []const T, index: usize, n: usize) !i64 {
            const haystack_ = s.i.items[0..std.math.clamp(index, 0, s.i.items.len)];
            const needle_ = needle[0..std.math.clamp(n, 0, needle.len)];

            if (haystack_.len == 0) return npos;

            var idx: usize = haystack_.len - 1;
            while (idx >= 0) {
                if (std.mem.containsAtLeastScalar2(T, needle_, haystack_[idx], 1)) {
                    return @as(i64, @intCast(idx));
                }
                if (idx == 0) return -1;
                idx -= 1;
            }

            return -1;
        }

        pub fn find_first_not_of(s: *Self, notlist: []const T, index: usize, n: usize) !i64 {
            if (index >= s.i.items.len) return -1;

            const haystack_ = s.i.items[index..];
            const notlist_ = notlist[0..std.math.clamp(n, 0, notlist.len)];

            for (haystack_, 0..) |needle, i| {
                if (!std.mem.containsAtLeastScalar2(T, notlist_, needle, 1)) {
                    return @as(i64, @intCast(i + index));
                }
            }
            return -1;
        }

        pub fn find_last_not_of(s: *Self, needle: []const T, pos: i64, n: i64) !i64 {
            if (pos > s.length()) return StringErrors.ArgumentOutOfRange;
            if (n > needle.len) return StringErrors.ArgumentOutOfRange;

            const slen: usize = if (n == npos) needle.len else @as(usize, @intCast(n));

            const end: usize = if (pos == npos) s.i.items.len else @as(usize, @intCast(pos));
            const haystack_ = s.i.items[0..std.math.clamp(end, 0, s.i.items.len)];
            const needle_ = needle[0..slen];

            if (haystack_.len == 0) return npos;

            var idx: usize = haystack_.len - 1;
            while (idx >= 0) {
                if (!std.mem.containsAtLeastScalar2(T, needle_, haystack_[idx], 1)) {
                    return @as(i64, @intCast(idx));
                }
                if (idx == 0) return -1;
                idx -= 1;
            }

            return -1;
        }

        pub fn get_allocator(s: *Self) std.mem.Allocator {
            return s.a;
        }

        pub fn pop_back(s: *Self) ?T {
            const element = s.i.pop();
            s.set_internal_buffers();
            return element;
        }

        pub fn push_back(s: *Self, element: T) *Self {
            s.i.append(s.a, element) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn reserve(s: *Self, size: usize) *Self {
            s.i.ensureTotalCapacity(s.a, size) catch unreachable;
            return s;
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

        pub fn shrink_to_fit(s: *Self) *Self {
            s.i.shrinkToLen(s.a) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn span(s: *Self, index: usize, len: usize) ![]T {
            return s.slice(index, len);
        }

        pub fn slice(s: *Self, index: usize, len: usize) ![]T {
            if (index >= s.i.items.len) return StringErrors.ArgumentOutOfRange;
            return s.a.dupe(T, s.i.items[index..std.math.clamp(index + len, 0, s.i.items.len)]) catch unreachable;
        }

        pub fn swap(s: *Self, other: *Self) !void {
            const temp = s.a.dupe(T, s.i.items) catch unreachable;
            defer s.a.free(temp);
            //store the other buffer into a temp buffer in the case of swapping to self.  using the arrayList.items will fail the copy
            const temp_other = s.a.dupe(T, other.i.items) catch unreachable;
            defer s.a.free(temp_other);
            _ = s.set(temp_other);
            _ = other.set(temp);
        }

        inline fn set(s: *Self, value: []const T) *Self {
            s.i.clearRetainingCapacity();
            s.i.appendSlice(s.a, value) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn str(s: *Self) []T {
            s.set_internal_buffers();
            return s.raw.?;
        }

        pub fn strSentinel(s: *Self) [:sentinel]T {
            s.set_internal_buffers();
            return s.rawSentinel.?;
        }

        //set contents of buffer and return buffer length, caller is responsible for freeing buffer
        pub fn stru(s: *Self, a: std.mem.Allocator, buffer: *[]T) !usize {
            buffer.* = try a.dupe(T, s.i.items);
            return buffer.len;
        }

        pub fn c_str(s: *Self, a: std.mem.Allocator, buffer: *[]T) !usize {
            return try s.stru(a, buffer);
        }

        pub fn strSentinelu(s: *Self, a: std.mem.Allocator, buffer: *[:sentinel]T) !usize {
            buffer.* = try a.dupeSentinel(T, s.i.items, sentinel);
            return buffer.len;
        }

        inline fn set_internal_buffers(s: *Self) void {
            if (s.raw) |previous| {
                s.a.free(previous);
                s.raw = null;
            }
            s.raw = s.a.dupe(T, s.i.items[0..s.i.items.len]) catch unreachable;
            if (s.rawSentinel) |previous| {
                s.a.free(previous);
                s.rawSentinel = null;
            }
            s.rawSentinel = s.a.dupeSentinel(T, s.i.items[0..s.i.items.len], sentinel) catch unreachable;
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

test "fill" {
    const a = std.testing.allocator;

    const T = u8;

    var str_0 = string(T).init(a, empty_buffer);
    defer str_0.deinit();

    const test_count_0: usize = 200;
    const test_char_0 = 'c';
    _ = str_0.fill('c', test_count_0);

    const expected_0 = try a.alloc(u8, test_count_0);
    defer a.free(expected_0);
    @memset(expected_0, test_char_0);

    try std.testing.expectEqual(test_count_0, str_0.length());
    try std.testing.expectEqualStrings(expected_0, str_0.str());

    const test_count_1: usize = 0;
    const test_char_1 = 'c';
    _ = str_0.fill('c', test_count_1);

    var str_1 = string(T).init(a, empty_buffer);
    defer str_1.deinit();

    const expected_1 = try a.alloc(T, test_count_1);
    defer a.free(expected_1);
    @memset(expected_1, test_char_1);

    try std.testing.expectEqual(test_count_1, str_1.length());
    try std.testing.expectEqualStrings(expected_1, str_1.str());
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
    const a = std.testing.allocator;

    const T = u8;

    const toTrim = " \n\r ";

    var str = string(u8).init(std.testing.allocator, "starting\r\n");
    defer str.deinit();

    const trimmed = try str.trimRight(toTrim);
    try std.testing.expectEqualStrings("starting", trimmed);

    const test_base_1 = "      \r\tHi, I'm a test string of dubious intent. \r\n ";
    var str_1 = string(T).init(a, test_base_1);
    defer str_1.deinit();

    const trimmed_1 = try str_1.trimRight(toTrim);
    try std.testing.expectEqualStrings("      \r\tHi, I'm a test string of dubious intent.", trimmed_1);

    const test_base_2 = "      \r\tHi, I'm a test string of dubious intent. \r\n \t";
    var str_2 = string(T).init(a, test_base_2);
    defer str_2.deinit();

    const trimmed_2 = try str_2.trimRight(toTrim);
    try std.testing.expectEqualStrings("      \r\tHi, I'm a test string of dubious intent. \r\n \t", trimmed_2);
}

test "trimLeft" {
    const a = std.testing.allocator;

    const T = u8;

    var str = string(T).init(a, "\r\nstarting\r\n ");
    defer str.deinit();

    const toTrim = " \n\r";
    const trimmed = try str.trimLeft(toTrim);
    try std.testing.expectEqualStrings("starting\r\n ", trimmed);

    const test_base_1 = "      \r\tHi, I'm a test string of dubious intent.";
    var str_1 = string(T).init(a, test_base_1);
    defer str_1.deinit();

    const trimmed_1 = try str_1.trimLeft(toTrim);
    try std.testing.expectEqualStrings("\tHi, I'm a test string of dubious intent.", trimmed_1);

    const test_base_2 = "x x";
    var str_2 = string(T).init(a, test_base_2);
    defer str_2.deinit();

    const trimmed_2 = try str_2.trimLeft("x");
    try std.testing.expectEqualStrings(" x", trimmed_2);

    const test_base_3 = "x x ";
    var str_3 = string(T).init(a, test_base_3);
    defer str_3.deinit();

    const trimmed_3 = try str_2.trimLeft("x");
    try std.testing.expectEqualStrings(" x", trimmed_3);
}

test "trim" {
    var str = string(u8).init(std.testing.allocator, "\r\nstar\r\nting\r\n");
    defer str.deinit();

    const toTrim = "\n\r";
    const trimmed = try str.trim(toTrim);

    try std.testing.expectEqualStrings("star\r\nting", trimmed);
}

test "substr(index, length)" {
    const a = std.testing.allocator;

    const T = u8;

    var str_0 = string(T).init(a, "01234567");
    defer str_0.deinit();
    const sub = try str_0.substr(0, 5);
    defer a.free(sub);
    try std.testing.expectEqualStrings("01234", sub);

    var str_1 = string(T).init(a, "01234567");
    defer str_1.deinit();
    const sub_short = try str_1.substr(0, 8);
    defer a.free(sub_short);
    try std.testing.expectEqualStrings("01234567", sub_short);

    var str_2 = string(T).init(a, "01234567");
    defer str_2.deinit();
    try std.testing.expectError(StringErrors.ArgumentOutOfRange, str_2.substr(55, string(T).npos));

    var str_3 = string(T).init(a, "0123456789");
    defer str_3.deinit();
    const sub_beyond = try str_3.substr(0, 99);
    defer a.free(sub_beyond);
    try std.testing.expectEqualStrings("0123456789", sub_beyond);
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
    const T = u8;

    var str_0 = string(T).init(std.testing.allocator, "content for your pleasure");
    defer str_0.deinit();

    _ = str_0.erase(0, 8);

    try std.testing.expectEqualStrings("for your pleasure", str_0.str());

    var str_1 = string(T).init(std.testing.allocator, "content for your pleasure");
    defer str_1.deinit();

    _ = str_1.erase(50, 10);

    try std.testing.expectEqualStrings("content for your pleasure", str_1.str());

    var str_2 = string(T).init(std.testing.allocator, "content for your pleasure");
    defer str_2.deinit();

    _ = str_2.erase(5, 4);

    try std.testing.expectEqualStrings("conteor your pleasure", str_2.str());

    var str_3 = string(T).init(std.testing.allocator, "content for your pleasure");
    defer str_3.deinit();

    _ = str_3.erase(str_3.length() - 1, 1);

    try std.testing.expectEqualStrings("content for your pleasur", str_3.str());

    var str_4 = string(T).init(std.testing.allocator, "x x");
    defer str_4.deinit();

    _ = str_4.erase(1, 1);

    try std.testing.expectEqualStrings("xx", str_4.str());

    var str_5 = string(T).init(std.testing.allocator, "x x");
    defer str_5.deinit();

    _ = str_5.erase(0, 1);

    try std.testing.expectEqualStrings(" x", str_5.str());

    var str_6 = string(T).init(std.testing.allocator, "x x");
    defer str_6.deinit();

    _ = str_6.erase(2, 1);

    try std.testing.expectEqualStrings("x ", str_6.str());

    var str_7 = string(T).init(std.testing.allocator, "x x");
    defer str_7.deinit();

    _ = str_7.erase(str_7.length() - 1, 1);

    try std.testing.expectEqualStrings("x ", str_7.str());

    var str_8 = string(T).init(std.testing.allocator, "");
    defer str_8.deinit();

    _ = str_8.erase(str_8.length(), 1);

    try std.testing.expectEqualStrings("", str_8.str());

    var str_9 = string(T).init(std.testing.allocator, "xyz");
    defer str_9.deinit();

    _ = str_9.erase(0, 0);

    try std.testing.expectEqualStrings("xyz", str_9.str());

    // len = string(T).npos
    var str_10 = string(T).init(std.testing.allocator, "xyz");
    defer str_10.deinit();

    _ = str_10.erase(0, @intCast(string(T).npos));

    try std.testing.expectEqualStrings("", str_10.str());

    // pos == len
    var str_11 = string(T).init(std.testing.allocator, "xyu");
    defer str_11.deinit();

    _ = str_11.erase(str_11.length(), @intCast(string(T).npos));

    try std.testing.expectEqualStrings("xyu", str_11.str());

    //all but last character
    var str_12 = string(T).init(std.testing.allocator, "xyu");
    defer str_12.deinit();

    _ = str_12.erase(0, 2);

    try std.testing.expectEqualStrings("u", str_12.str());

    //all but first character
    var str_13 = string(T).init(std.testing.allocator, "xyu");
    defer str_13.deinit();

    _ = str_13.erase(1, 2);

    try std.testing.expectEqualStrings("x", str_13.str());

    //only erase middle character
    var str_14 = string(T).init(std.testing.allocator, "xyu");
    defer str_14.deinit();

    _ = str_14.erase(1, 1);

    try std.testing.expectEqualStrings("xu", str_14.str());
}

test "replace" {
    const original = "this is a test string.";

    //at beginning and within string
    var str_0 = string(u8).init(std.testing.allocator, original);
    defer str_0.deinit();

    _ = try str_0.replace(9, 5, "n example");

    try std.testing.expectEqualStrings("this is an example string.", str_0.str());
    try std.testing.expectEqual(26, str_0.length());

    //within string, substr beyond end of str
    var str_1 = string(u8).init(std.testing.allocator, original);
    defer str_1.deinit();

    _ = try str_1.replace(21, 5, " and example");

    try std.testing.expectEqualStrings("this is a test string and example", str_1.str());
    try std.testing.expectEqual(33, str_1.length());

    //within string, substr shorter than index + count
    var str_2 = string(u8).init(std.testing.allocator, original);
    defer str_2.deinit();

    _ = try str_2.replace(15, 10, "for you");

    try std.testing.expectEqualStrings("this is a test for you", str_2.str());
    try std.testing.expectEqual(22, str_2.length());

    //end of str, substr longer than index + count
    var str_3 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_3.deinit();

    _ = try str_3.replace(24, 5, "e and consumption");

    try std.testing.expectEqualStrings("content for your pleasure and consumption", str_3.str());
    try std.testing.expectEqual(41, str_3.length());

    //end of str, substr shorter than pos + count
    var str_4 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_4.deinit();

    _ = try str_4.replace(24, 5, "es");

    try std.testing.expectEqualStrings("content for your pleasures", str_4.str());
    try std.testing.expectEqual(26, str_4.length());

    try std.testing.expectError(StringErrors.ArgumentOutOfRange, str_4.replace(1234, 4, "position beyond string length"));
}
test "replacen" {
    const a = std.testing.allocator;

    const T = u8;

    const original = "this is a test string.";

    //at beginning and within string
    var str_0 = string(u8).init(std.testing.allocator, original);
    defer str_0.deinit();

    _ = try str_0.replacen(9, 5, "n example", 0, "n example".len);

    try std.testing.expectEqualStrings("this is an example string.", str_0.str());
    try std.testing.expectEqual(26, str_0.length());

    //within string, substr beyond end of str
    var str_1 = string(u8).init(std.testing.allocator, original);
    defer str_1.deinit();

    _ = try str_1.replacen(21, 5, "   and example", 2, "   and example".len - 2);
    try std.testing.expectEqualStrings("this is a test string and example", str_1.str());
    try std.testing.expectEqual(33, str_1.length());

    //within string, replacement string shorter than sublen
    var str_2 = string(u8).init(std.testing.allocator, original);
    defer str_2.deinit();

    _ = try str_2.replacen(15, 10, "    for you", 4, "    this is a test for you".len);

    try std.testing.expectEqualStrings("this is a test for you", str_2.str());
    try std.testing.expectEqual(22, str_2.length());

    //end of str, substr longer than index + count
    var str_3 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_3.deinit();

    _ = try str_3.replacen(24, 5, "e and consumption", 0, -1);

    try std.testing.expectEqualStrings("content for your pleasure and consumption", str_3.str());
    try std.testing.expectEqual(41, str_3.length());

    //end of str, substr shorter than pos + count
    var str_4 = string(u8).init(std.testing.allocator, "content for your pleasure");
    defer str_4.deinit();

    _ = try str_4.replacen(24, 5, "es", 0, -1);

    try std.testing.expectEqualStrings("content for your pleasures", str_4.str());
    try std.testing.expectEqual(26, str_4.length());

    var str_5 = string(T).init(a, "content for your pleasure");
    defer str_5.deinit();

    _ = try str_5.replacen(str_5.length(), string(T).npos, "s", 0, string(T).npos);

    try std.testing.expectEqualStrings("content for your pleasures", str_5.str());
    try std.testing.expectEqual("content for your pleasures".len, str_5.length());

    //replace retmaining string portion from pos with shorter string
    var str_6 = string(T).init(a, "content for your pleasure");
    defer str_6.deinit();

    _ = try str_6.replacen(17, string(T).npos, "butt", 0, "butt".len + 50);

    try std.testing.expectEqualStrings("content for your butt", str_6.str());
    try std.testing.expectEqual("content for your butt".len, str_6.length());

    try std.testing.expectError(StringErrors.ArgumentOutOfRange, str_4.replacen(1234, @intCast(str_4.length() + 1), "position beyond string length", 0, -1));
    try std.testing.expectError(StringErrors.ArgumentOutOfRange, str_4.replacen(1234, 4, "position beyond string length", 0, "position beyond string length".len));
}

test "find" {
    const a = std.testing.allocator;

    const T = u8;

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
    const found_3 = try str_3.find(needle_3, 0, needle_3.len);

    try std.testing.expectEqual(51, found_3);

    var str_4 = string(T).init(a, test_bed);
    defer str_4.deinit();

    const needle_4 = "";
    const found_4 = try str_4.find(needle_4, str_4.length(), needle_4.len);

    try std.testing.expectEqual(str_4.length(), @as(usize, @intCast(found_4)));

    var str_5 = string(T).init(a, test_bed);
    defer str_5.deinit();

    const needle_5 = "";
    const found_5 = try str_5.find(needle_5, 0, needle_5.len);

    try std.testing.expectEqual(0, @as(usize, @intCast(found_5)));

    var str_6 = string(T).init(a, test_bed);
    defer str_6.deinit();

    const needle_6 = "";
    const found_6 = try str_6.find(needle_6, 3, @as(usize, @intCast(needle_6.len)));

    try std.testing.expectEqual(3, found_6);

    var str_7 = string(T).init(a, empty_buffer);
    defer str_7.deinit();

    const needle_7 = ",";
    const found_7 = try str_6.find(needle_7, 0, string(T).npos);

    try std.testing.expectEqual(-1, found_7);
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

    var str_match_first_element = string(u8).init(a, test_base);
    defer str_match_first_element.deinit();
    const match_first = try str_match_first.find_last_of("A", test_base.len, 1);

    try std.testing.expectEqual(0, match_first);

    var str_match_last_element = string(u8).init(a, test_base);
    defer str_match_last_element.deinit();
    const match_last = try str_match_last_element.find_last_of(".", @intCast(test_base.len), 1);

    try std.testing.expectEqual(@as(i64, @intCast(test_base.len - 1)), match_last);

    var str_match_empty = string(u8).init(a, empty_buffer);
    defer str_match_empty.deinit();
    const match_empty_not_found = try str_match_empty.find_last_of(".", 0, 1);

    try std.testing.expectEqual(-1, match_empty_not_found);

    const match_empty_vs_empty = try str_match_empty.find_last_of("", 0, 1);

    try std.testing.expectEqual(-1, match_empty_vs_empty);
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
    const match_second = try str_match_second.find_first_not_of(match_second_needle, 4, match_second_needle.len);

    try std.testing.expectEqual(5, match_second);

    var str_match_second_none = string(u8).init(a, test_base);
    defer str_match_second_none.deinit();
    const match_second_none = try str_match_second_none.find_first_not_of(".", 29, 1);

    try std.testing.expectEqual(-1, match_second_none);

    var str_match_none_beyond = string(u8).init(a, test_base);
    defer str_match_none_beyond.deinit();
    const match_none_beyond = try str_match_none_beyond.find_first_not_of("t", 55, 1);

    try std.testing.expectEqual(-1, match_none_beyond);

    var str_match_case = string(u8).init(a, test_base);
    defer str_match_case.deinit();
    const match_case = try str_match_case.find_first_not_of("a", 0, 1);

    try std.testing.expectEqual(0, match_case);

    //find first character of the first character from the given string
    var str_match_slice_substr = string(u8).init(a, test_base);
    defer str_match_slice_substr.deinit();
    const match_slice_substr = try str_match_slice_substr.find_first_not_of("A test strin", 0, "A test strin".len - 3);

    try std.testing.expectEqual(@as(i64, @intCast("A test strin".len - 3)), match_slice_substr);

    // Passing in an empty notlist by n parameter of 0 means we are looking for characters not present
    // in a "none of the above" search set, which will cause it to return the index of the very first
    // character in your target string

    var str_match_empty_needle_by_n = string(u8).init(a, test_base);
    defer str_match_empty_needle_by_n.deinit();
    const needle_empty_needle_by_n = "A test strin";
    const match_empty_needle_by_n = try str_match_empty_needle_by_n.find_first_not_of(needle_empty_needle_by_n, 0, 0);

    try std.testing.expectEqual(0, match_empty_needle_by_n);

    var str_match_empty_needle = string(u8).init(a, test_base);
    defer str_match_empty_needle.deinit();
    const needle_empty_needle = "";
    const match_empty_needle = try str_match_empty_needle.find_first_not_of(needle_empty_needle, 0, 0);

    try std.testing.expectEqual(0, match_empty_needle);

    var str_match_empty_haystack = string(u8).init(a, empty_buffer);
    defer str_match_empty_haystack.deinit();
    const match_empty_haystack = str_match_slice_substr.find_first_not_of(",", 0, 0);

    try std.testing.expectEqual(0, match_empty_haystack);

    const match_empty_haystack_vs_empty_needle = try str_match_empty_haystack.find_first_not_of("", 0, 0);

    try std.testing.expectEqual(-1, match_empty_haystack_vs_empty_needle);
}

test "find_last_not_of" {
    const a = std.testing.allocator;

    const T = u8;

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
    const match_none_beyond = try str_match_none_beyond.find_last_not_of("A", 1, 1);

    try std.testing.expectEqual(-1, match_none_beyond);

    var str_match_case = string(u8).init(a, test_base);
    defer str_match_case.deinit();

    const test_base_uppercase = "A TEST STRING OF GREAT IMPORT.     \r\n ";
    const match_case = try str_match_case.find_last_not_of(test_base_uppercase, test_base.len, test_base_uppercase.len);

    try std.testing.expectEqual(28, match_case);

    var str_empty = string(u8).init(a, "");
    defer str_empty.deinit();

    var str_blank = string(u8).init(a, " ");
    defer str_blank.deinit();
    const match_empty = try str_blank.find_last_not_of(empty_buffer, string(T).npos, empty_buffer.len);

    try std.testing.expectEqual(0, match_empty);

    var str_match_empty_needle = string(u8).init(a, test_base);
    defer str_match_empty_needle.deinit();
    const needle_empty_needle = "";
    const match_empty_needle = try str_match_empty_needle.find_last_not_of(needle_empty_needle, 0, 0);

    try std.testing.expectEqual(-1, match_empty_needle);

    var str_match_empty_haystack = string(u8).init(a, empty_buffer);
    defer str_match_empty_haystack.deinit();
    const match_empty_haystack = str_match_empty_haystack.find_last_not_of(",", 0, 0);

    try std.testing.expectEqual(-1, match_empty_haystack);

    const match_empty_haystack_vs_empty_needle = try str_match_empty_haystack.find_last_not_of("", 0, 0);

    try std.testing.expectEqual(-1, match_empty_haystack_vs_empty_needle);
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

test "starts_with" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import. ";

    var str_0 = string(u8).init(a, test_base);
    defer str_0.deinit();

    try std.testing.expect(try str_0.starts_with("A test"));

    try std.testing.expect(try str_0.starts_with(""));

    try std.testing.expect(!(try str_0.starts_with(" ")));

    try std.testing.expect(!(try str_0.starts_with("A test bear.")));

    try std.testing.expect((try str_0.starts_with("A")));

    try std.testing.expect(!(try str_0.starts_with("test")));

    try std.testing.expect(!(try str_0.starts_with("import.")));
}

test "ends_with" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_0 = string(u8).init(a, test_base);
    defer str_0.deinit();

    try std.testing.expect(try str_0.ends_with("import."));

    try std.testing.expect(try str_0.ends_with(""));

    try std.testing.expect(!(try str_0.ends_with(" ")));

    try std.testing.expect(!(try str_0.ends_with("important bear.")));

    try std.testing.expect(!(try str_0.ends_with("t")));

    try std.testing.expect(!(try str_0.ends_with("ort")));

    try std.testing.expect(!(try str_0.ends_with("import")));
    const test_base_1 = "";

    var str_1 = string(u8).init(a, test_base_1);
    defer str_1.deinit();

    try std.testing.expect(try str_1.ends_with(""));
    try std.testing.expect(!(try str_1.ends_with(" ")));
}

test "contains" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_0 = string(u8).init(a, test_base);
    defer str_0.deinit();

    try std.testing.expect(try str_0.contains("import."));
    try std.testing.expect(try str_0.contains(""));
    try std.testing.expect(!try str_0.contains("x"));
    try std.testing.expect(!try str_0.contains("important"));
    try std.testing.expect(!try str_0.contains("import.ant"));
    try std.testing.expect(!try str_0.contains("\t"));
    try std.testing.expect(try str_0.contains(" "));
    try std.testing.expect(try str_0.contains("great"));

    const test_base_1 = "";

    var str_1 = string(u8).init(a, test_base_1);
    defer str_1.deinit();

    try std.testing.expect(try str_1.ends_with(""));
    try std.testing.expect(!(try str_1.ends_with(" ")));
}

test "span and slice" {
    const a = std.testing.allocator;

    const test_base = "A test string of great import.     \r\n ";

    var str_0 = string(u8).init(a, test_base);
    defer str_0.deinit();

    const slice = try str_0.slice(0, 4);
    defer a.free(slice);

    try std.testing.expectEqualStrings("A te", slice);
    try std.testing.expectEqual(4, slice.len);

    const slice_beyond = try str_0.slice(0, 55);
    defer a.free(slice_beyond);

    try std.testing.expectEqualStrings(test_base, slice_beyond);
    try std.testing.expectEqual(test_base.len, slice_beyond.len);

    const span = try str_0.span(0, 4);
    defer a.free(span);

    try std.testing.expectEqualStrings("A te", span);
    try std.testing.expectEqual(4, span.len);

    try std.testing.expectError(StringErrors.ArgumentOutOfRange, str_0.slice(50, test_base.len));
}

const Io = std.Io;

test "from_slice" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.     \r\n ";
    var str_0 = string(T).from_slice(a, empty_buffer);
    defer str_0.deinit();
    try std.testing.expectEqual(0, str_0.length());

    var str_1 = string(T).from_slice(a, test_base);
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
    var str_0 = string(T).from_arrayList(a, list_0);
    defer str_0.deinit();
    try std.testing.expectEqual(0, str_0.length());

    var list_1: std.ArrayList(T) = .empty;
    defer list_1.deinit(a);

    try list_1.appendSlice(a, test_base);
    var str_1 = string(T).from_arrayList(a, list_1);
    defer str_1.deinit();
    try std.testing.expectEqual(test_base.len, str_1.length());
    try std.testing.expectEqual(0, str_1.compare(test_base));
    try std.testing.expectEqualStrings(test_base, str_1.str());
}

test "pop_back" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();
    try std.testing.expectEqual(test_base.len, str_0.length());

    const last_char = str_0.pop_back();

    try std.testing.expect(last_char != null);
    try std.testing.expectEqual('.', last_char.?);
    try std.testing.expectEqualStrings("A test string of great import", str_0.str());

    var str_1 = string(T).init(a, empty_buffer);
    defer str_1.deinit();

    try std.testing.expectEqual(0, str_1.length());

    const empty_string_back_popped = str_1.pop_back();

    try std.testing.expectEqual(null, empty_string_back_popped);
}

test "push_back" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();
    try std.testing.expectEqual(test_base.len, str_0.length());

    _ = str_0.push_back('a');

    try std.testing.expect((try str_0.back()) != null);
    try std.testing.expectEqual('a', (try str_0.back()).?);
    try std.testing.expectEqualStrings(test_base ++ "a", str_0.str());

    _ = str_0.push_back('\n');
    try std.testing.expect((try str_0.back()) != null);
    try std.testing.expectEqual('\n', (try str_0.back()).?);
    try std.testing.expectEqualStrings(test_base ++ "a\n", str_0.str());

    var str_empty = string(T).init(a, empty_buffer);
    defer str_empty.deinit();

    _ = str_empty.push_back('b');
    try std.testing.expectEqualStrings("b", str_empty.str());
}

test "reserve" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();

    var capacity_before = str_0.capacity();

    _ = str_0.reserve(capacity_before + 1);

    try std.testing.expect(capacity_before + 1 <= str_0.capacity());

    capacity_before = str_0.capacity();

    _ = str_0.reserve(capacity_before - 1);

    //capacity only grows with reserve call
    try std.testing.expect(capacity_before - 1 <= str_0.capacity());
}

test "shrink_to_fit" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";
    const test_base_shorter = "A test.";

    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();

    var capacity_before = str_0.capacity();

    _ = str_0.shrink_to_fit();

    try std.testing.expectEqual(str_0.length(), str_0.length());
    try std.testing.expectEqual(test_base.len, str_0.capacity());

    _ = str_0.set(test_base_shorter);

    try std.testing.expectEqual(test_base.len, str_0.capacity());

    capacity_before = str_0.capacity();

    _ = str_0.shrink_to_fit();

    try std.testing.expect(capacity_before > str_0.capacity());

    try std.testing.expectEqual(test_base_shorter.len, str_0.length());
    try std.testing.expectEqual(test_base_shorter.len, str_0.capacity());
}

test "swap" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";
    const test_base_other = "A test string that is completely different.";

    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();

    var str_1 = string(T).init(a, test_base_other);
    defer str_1.deinit();

    var str_empty = string(T).init(a, empty_buffer);
    defer str_empty.deinit();

    try std.testing.expectEqual(test_base.len, str_0.length());
    try std.testing.expectEqualStrings(test_base, str_0.str());

    try std.testing.expectEqual(test_base_other.len, str_1.length());
    try std.testing.expectEqualStrings(test_base_other, str_1.str());

    try str_0.swap(@constCast(&str_1));

    try std.testing.expectEqual(test_base_other.len, str_0.length());
    try std.testing.expectEqualStrings(test_base_other, str_0.str());

    try std.testing.expectEqual(test_base.len, str_1.length());
    try std.testing.expectEqualStrings(test_base, str_1.str());

    try str_0.swap(@constCast(&str_empty));

    try std.testing.expectEqual(empty_buffer.len, str_0.length());
    try std.testing.expectEqualStrings(empty_buffer, str_0.str());

    try std.testing.expectEqual(test_base_other.len, str_empty.length());
    try std.testing.expectEqualStrings(test_base_other, str_empty.str());

    var str_null_0 = string(T).init(a, null);
    defer str_null_0.deinit();
    var str_null_1 = string(T).init(a, null);
    defer str_null_1.deinit();

    //empty strings are the default
    try str_null_0.swap(@constCast(&str_null_1));

    var str_self_2 = string(T).init(a, test_base);
    defer str_self_2.deinit();

    try str_self_2.swap(&str_self_2);
    try std.testing.expectEqualStrings(test_base, str_self_2.str());
}

test "deinit" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";
    var str_0 = string(T).init(a, test_base);

    str_0.deinit();

    try std.testing.expect(str_0._disposed);
    try std.testing.expect(str_0.raw == null);
    try std.testing.expect(str_0.rawSentinel == null);

    //deinit has a flag to protect subsequent deinit calls
    str_0.deinit();

    try std.testing.expect(true);
}

test "str" {
    const T = u8;

    const a = std.testing.allocator;

    const test_base = "A test string of great import.";

    //str, strsentinel, c_str, stru, strSentinelu
    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();

    try std.testing.expectEqualStrings(test_base, str_0.str());
    try std.testing.expectEqual(test_base.len, str_0.str().len);
    try std.testing.expectEqualStrings(test_base, str_0.strSentinel());
    try std.testing.expectEqual(test_base.len, str_0.strSentinel().len);

    var str_0_cstr: []T = undefined;
    _ = &str_0_cstr;
    defer a.free(str_0_cstr);
    const str_0_cstr_len = str_0.c_str(a, &str_0_cstr);

    try std.testing.expectEqual(test_base.len, str_0_cstr_len);
    try std.testing.expectEqualStrings(test_base, str_0_cstr);

    var str_0_stru: []T = undefined;
    _ = &str_0_stru;
    defer a.free(str_0_stru);
    const str_0_stru_len = str_0.stru(a, &str_0_stru);

    try std.testing.expectEqual(test_base.len, str_0_stru_len);
    try std.testing.expectEqualStrings(test_base, str_0_stru);

    var str_0_strSentinelu: []T = undefined;
    _ = &str_0_strSentinelu;
    defer a.free(str_0_strSentinelu);
    const str_0_sentinel_len = str_0.stru(a, &str_0_strSentinelu);

    try std.testing.expectEqual(test_base.len, str_0_sentinel_len);
    try std.testing.expectEqualStrings(test_base, str_0_strSentinelu);

    var str_1 = string(T).init(a, empty_buffer);
    defer str_1.deinit();

    try std.testing.expectEqualStrings(empty_buffer, str_1.str());
    try std.testing.expectEqual(empty_buffer.len, str_1.str().len);
    try std.testing.expectEqualStrings(empty_buffer, str_1.strSentinel());
    try std.testing.expectEqual(empty_buffer.len, str_1.strSentinel().len);

    var str_1_cstr: []T = undefined;
    _ = &str_1_cstr;
    defer a.free(str_1_cstr);
    const str_1_cstr_len = str_1.c_str(a, &str_1_cstr);

    try std.testing.expectEqual(empty_buffer.len, str_1_cstr_len);
    try std.testing.expectEqualStrings(empty_buffer, str_1_cstr);

    var str_1_stru: []T = undefined;
    _ = &str_1_stru;
    defer a.free(str_1_stru);
    const str_1_stru_len = str_1.stru(a, &str_1_stru);

    try std.testing.expectEqual(empty_buffer.len, str_1_stru_len);
    try std.testing.expectEqualStrings(empty_buffer, str_1_stru);

    var str_1_strSentinelu: [:string(T).sentinel]T = undefined;
    _ = &str_1_strSentinelu;
    defer a.free(str_1_strSentinelu);
    const str_1_sentinel_len = str_1.strSentinelu(a, &str_1_strSentinelu);

    try std.testing.expectEqual(empty_buffer.len, str_1_sentinel_len);
    try std.testing.expectEqualStrings(empty_buffer, str_1_strSentinelu);

    const test_length_big = 1024 * 10 * 1024;
    var test_string_big = try a.alloc(T, test_length_big);
    _ = &test_string_big;
    defer a.free(test_string_big);
    @memset(test_string_big, 'A');

    var str_2_big = string(T).init(a, test_string_big);
    defer str_2_big.deinit();

    try std.testing.expectEqualStrings(test_string_big, str_2_big.str());
    try std.testing.expectEqual(test_string_big.len, str_2_big.str().len);
    try std.testing.expectEqualStrings(test_string_big, str_2_big.strSentinel());
    try std.testing.expectEqual(test_string_big.len, str_2_big.strSentinel().len);

    var str_2_big_cstr: []T = undefined;
    defer a.free(str_2_big_cstr);
    const str_2_big_cstr_len = str_2_big.c_str(a, &str_2_big_cstr);

    try std.testing.expectEqual(test_string_big.len, str_2_big_cstr_len);
    try std.testing.expectEqualStrings(test_string_big, str_2_big_cstr);

    var str_2_big_stru: []T = undefined;
    defer a.free(str_2_big_stru);
    const str_2_big_stru_len = str_2_big.stru(a, &str_2_big_stru);

    try std.testing.expectEqual(test_string_big.len, str_2_big_stru_len);
    try std.testing.expectEqualStrings(test_string_big, str_2_big_stru);

    var test_string_big_z: [:string(T).sentinel]T = try a.allocSentinel(T, test_length_big, string(T).sentinel);
    _ = &test_string_big_z;
    defer a.free(test_string_big_z);
    @memset(test_string_big_z, 'A');

    var str_2_big_strSentinelu: [:string(T).sentinel]T = undefined;
    defer a.free(str_2_big_strSentinelu);
    const str_2_big_sentinel_len = str_2_big.strSentinelu(a, &str_2_big_strSentinelu);

    try std.testing.expectEqual(test_string_big_z.len, str_2_big_sentinel_len);
    try std.testing.expectEqualStrings(test_string_big_z, str_2_big_strSentinelu);
}

test "set" {
    const T = u8;

    const a = std.testing.allocator;

    //confirm our string buffer is not freed by the passed in parameter being freed
    const test_base = try a.dupe(T, "A test string of great import.");

    var str_0 = string(T).init(a, test_base);
    defer str_0.deinit();

    a.free(test_base);

    const buffer = str_0.str();

    try std.testing.expectEqualStrings("A test string of great import.", buffer);

    //confirm our buffer isn't freed by the string deinit
    const test_base_1 = try a.dupe(T, "A test string of great import.");
    defer a.free(test_base_1);

    var str_1 = string(T).init(a, test_base);

    str_1.deinit();

    try std.testing.expectEqualStrings("A test string of great import.", test_base_1);
}
//TODO: use string(T) as parameters instead of []const T
