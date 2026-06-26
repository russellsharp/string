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

        pub const contained_type: type = T;

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

        pub fn clone(s: *const Self, a: std.mem.Allocator) Self {
            var c = Self{ .a = a, .i = std.ArrayList(T).empty, .raw = null, .rawSentinel = null, ._disposed = false };

            c.raw = a.alloc(T, s.i.items.len) catch unreachable;
            std.mem.copyForwards(T, c.raw.?, s.i.items[0..s.i.items.len]);

            c.rawSentinel = a.allocSentinel(T, s.i.items.len, sentinel) catch unreachable;
            if (s.rawSentinel) |rawSentinel| c.rawSentinel = a.dupeSentinel(T, rawSentinel, 0) catch unreachable;

            c.i = s.i.clone(a) catch unreachable;
            return c;
        }

        //capacity methods

        pub fn size(s: *Self) usize {
            return s.length();
        }

        pub fn length(s: *Self) usize {
            return s.i.items.len;
        }

        pub fn resize(s: *Self, new_capacity: usize, value: ?T) *Self {
            if (new_capacity > s.i.items.len and value != null) {
                const growth = new_capacity - s.i.items.len;
                const slice_ = s.i.addManyAsSlice(s.a, growth) catch unreachable;
                if (value) |c| @memset(slice_, c);
            } else if (new_capacity < s.i.items.len) {
                s.i.shrinkAndFree(s.a, new_capacity);
            }
            s.set_internal_buffers();
            return s;
        }

        pub fn capacity(s: *Self) usize {
            return s.i.capacity;
        }

        pub fn reserve(s: *Self, new_capacity: usize) *Self {
            s.i.ensureTotalCapacity(s.a, new_capacity) catch unreachable;
            return s;
        }

        pub fn clear(s: *Self) *Self {
            defer s.set_internal_buffers();
            return s.set(empty_buffer);
        }

        pub fn empty(s: *const Self) bool {
            return s.i.items.len == 0;
        }

        pub fn shrink_to_fit(s: *Self) *Self {
            s.i.shrinkToLen(s.a) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        // element access

        pub fn at(s: *Self, pos: usize) !T {
            if (pos >= s.i.items.len) return StringErrors.InvalidArgument;
            return s.i.items[pos];
        }

        pub fn back(s: *Self) !?T {
            if (s.empty()) return StringErrors.EmptyString;
            return s.i.items[s.i.items.len - 1];
        }

        pub fn front(s: *Self) !?T {
            if (s.empty()) return StringErrors.EmptyString;
            return s.i.items[0];
        }

        // modifiers

        pub fn append(s: *Self, suffix: []const T) *Self {
            s.i.appendSlice(s.a, suffix) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn push_back(s: *Self, element: T) *Self {
            s.i.append(s.a, element) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn assign(s: *Self, buffer: []const T) *Self {
            return s.set(buffer);
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

        pub fn swap(s: *Self, other: *Self) !void {
            const temp = s.a.dupe(T, s.i.items) catch unreachable;
            defer s.a.free(temp);
            //store the other buffer into a temp buffer in the case of swapping to self.  using the arrayList.items will fail the copy
            const temp_other = s.a.dupe(T, other.i.items) catch unreachable;
            defer s.a.free(temp_other);
            _ = s.set(temp_other);
            _ = other.set(temp);
        }

        pub fn pop_back(s: *Self) ?T {
            const element = s.i.pop();
            s.set_internal_buffers();
            return element;
        }

        // string operations

        pub fn c_str(s: *Self, a: std.mem.Allocator, buffer: *[]T) !usize {
            return try s.stru(a, buffer);
        }

        pub fn data(s: *Self) []const T {
            return s.str();
        }

        pub fn str(s: *const Self) []T {
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

        //set contents of buffer and return buffer length, caller is responsible for freeing buffer
        pub fn strSentinelu(s: *Self, a: std.mem.Allocator, buffer: *[:sentinel]T) !usize {
            buffer.* = try a.dupeSentinel(T, s.i.items, sentinel);
            return buffer.len;
        }

        pub fn get_allocator(s: *Self) std.mem.Allocator {
            return s.a;
        }

        pub fn copy(a: std.mem.Allocator, source: string(T)) Self {
            var s = Self{ .a = a, .i = .empty, ._disposed = false };
            const copy_buffer = a.dupe(T, source.i.items) catch unreachable;
            defer a.free(copy_buffer);
            s.i.appendSlice(a, copy_buffer) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        pub fn find(s: *Self, needle: []const T, index: usize, len: i64) !i64 {
            if (index > s.i.items.len) return StringErrors.InvalidArgument;
            if (len > needle.len) return StringErrors.InvalidArgument;

            //if needle is empty, return index by cpp std standards
            if (needle.len == 0) return @intCast(index);

            const needle_len = if (len == npos) needle.len else @as(usize, @intCast(len));
            const needle_ = needle[0..needle_len];
            const haystack_ = s.i.items[index..];

            if (needle_.len > haystack_.len) return -1;

            const found = std.mem.find(T, haystack_, needle_);

            return if (found) |value| @intCast(value + index) else @as(i64, npos);
        }

        pub fn rfind(s: *Self, needle: []const T, index: usize) !i64 {
            const haystack_ = s.i.items[0..std.math.clamp(index + 1, 0, s.i.items.len)];
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
            const haystack_ = s.i.items[0..std.math.clamp(index + 1, 0, s.i.items.len)];
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

        pub fn substr(s: *Self, index: usize, count: i64) ![]T {
            if (index > s.i.items.len) return StringErrors.ArgumentOutOfRange;

            const char_count: usize = if (count == npos) s.i.items.len else @intCast(count);
            const start: usize = index;
            const end: usize = std.math.clamp(index + char_count, index, s.i.items.len);
            return try s.a.dupe(T, s.i.items[start..end]);
        }

        pub fn compare(s: *Self, b: []const T) !i8 {
            return try s.comparen(0, s.i.items.len, b, -1);
        }

        pub fn comparen(s: *Self, pos: usize, len: usize, b: []const T, n: i32) !i8 {
            if (pos > s.i.items.len) return StringErrors.ArgumentOutOfRange;

            const compared = s.i.items[pos..std.math.clamp(pos + len, pos, s.i.items.len)];
            const comparing = b[0..std.math.clamp(if (n == npos) b.len else @as(usize, @intCast(n)), 0, b.len)];
            const num_of_chars: usize = if (n == npos) @max(compared.len, comparing.len) else @as(usize, @intCast(n));

            if (compared.len == 0 and comparing.len == 0) return 0;

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

        // miscellaneous string methods

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

        // string mutating  methods

        pub fn trimRight(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            const last_not_of = try s.find_last_not_of(charactersToTrim, @intCast(s.length()), npos);

            //if every character is to be trimmed, special case returns an empty string
            if (last_not_of == npos) {
                return s.set(empty_buffer).str();
            }

            const last: usize = if (last_not_of >= 0) @intCast(last_not_of) else 0;

            const trimmed = try s.a.dupe(T, s.i.items[0..std.math.clamp(last + 1, 0, s.i.items.len)]);
            defer s.a.free(trimmed);

            return s.set(trimmed).str();
        }

        pub fn trimLeft(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            const first_not_of = try s.find_first_not_of(charactersToTrim, 0, charactersToTrim.len);

            const first: usize = if (first_not_of >= 0) @intCast(first_not_of) else s.i.items.len;

            const trimmed = try s.a.dupe(T, s.i.items[first..s.i.items.len]);
            defer s.a.free(trimmed);

            return s.set(trimmed).str();
        }

        pub fn trim(s: *Self, charactersToTrim: []const T) ![]T {
            if (charactersToTrim.len < 1) return StringErrors.InvalidArgument;
            if (s.i.items.len < 1) return StringErrors.EmptyString;

            const first_not_of = try s.find_first_not_of(charactersToTrim, 0, charactersToTrim.len);

            if (first_not_of == npos) {
                return s.set(empty_buffer).str();
            }

            const first: usize = if (first_not_of >= 0) @intCast(first_not_of) else s.i.items.len;

            const last_not_of = try s.find_last_not_of(charactersToTrim, @intCast(s.length()), @as(i64, @intCast(charactersToTrim.len)));

            if (last_not_of == npos) {
                return s.set(empty_buffer).str();
            }

            const last: usize = if (last_not_of >= 0) @intCast(last_not_of) else 0;

            const trimmed = try s.a.dupe(T, s.i.items[first..std.math.clamp(last + 1, 0, s.i.items.len)]);
            defer s.a.free(trimmed);

            //s.set sets internal buffers
            return s.set(trimmed).str();
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

        pub fn assign_format(s: *Self, comptime format: []const T, args: anytype) *Self {
            const formatted = std.fmt.allocPrint(
                s.a,
                format,
                args,
            ) catch unreachable;
            defer s.a.free(formatted);

            return s.set(formatted);
        }

        // string non-mutating methods
        pub fn span(s: *Self, index: usize, len: usize) ![]T {
            return s.slice(index, len);
        }

        pub fn slice(s: *Self, index: usize, len: usize) ![]T {
            if (index >= s.i.items.len) return StringErrors.ArgumentOutOfRange;
            return s.a.dupe(T, s.i.items[index..std.math.clamp(index + len, 0, s.i.items.len)]) catch unreachable;
        }

        pub fn parse_json(s: *const Self, comptime U: type, allocator: std.mem.Allocator, options: std.json.ParseOptions) !std.json.Parsed(U) {
            if (T != u8) @compileError("parse_json is only supported for string(u8).");
            return std.json.parseFromSlice(U, allocator, s.str(), options);
        }

        pub fn parse_json_leaky(s: *const Self, comptime U: type, allocator: std.mem.Allocator, options: std.json.ParseOptions) !U {
            if (T != u8) @compileError("parse_json_leaky is only supported for string(u8).");
            return std.json.parseFromSliceLeaky(U, allocator, s.str(), options);
        }

        pub fn jsonStringify(s: Self, jws: *std.json.Stringify) !void {
            if (T != u8) @compileError("jsonStringify is only supported for string(u8).");
            try jws.write(s.raw.?);
        }

        // Add this method so std.json knows how to parse your custom struct
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
            if (T != u8) @compileError("jsonParse is only supported for string(u8).");
            const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
            return switch (token) {
                .string => |buffer| Self.init(allocator, buffer),
                .allocated_string => |buffer| blk: {
                    defer allocator.free(buffer);
                    break :blk Self.init(allocator, buffer);
                },
                else => error.UnexpectedToken,
            };
        }

        // Overriding Value-Tree Parsing (Required for nested/dynamic JSON structures)
        pub fn jsonParseFromValue(
            allocator: std.mem.Allocator,
            source: std.json.Value,
            options: std.json.ParseOptions,
        ) !Self {
            _ = options;
            if (T != u8) @compileError("jsonParseFromValue is only supported for string(u8).");
            switch (source) {
                .string => |buffer| return Self.init(allocator, buffer),
                else => return error.UnexpectedToken,
            }
        }

        // private methods
        inline fn set(s: *Self, value: []const T) *Self {
            s.i.clearRetainingCapacity();
            s.i.appendSlice(s.a, value) catch unreachable;
            s.set_internal_buffers();
            return s;
        }

        inline fn set_internal_buffers(s: *Self) void {
            if (s.raw) |previous| {
                s.a.free(previous);
                s.raw = null;
            }
            s.raw = s.a.alloc(T, s.i.items.len) catch unreachable;
            std.mem.copyForwards(T, s.raw.?, s.i.items[0..s.i.items.len]);

            if (s.rawSentinel) |previous| {
                s.a.free(previous);
                s.rawSentinel = null;
            }
            s.rawSentinel = s.a.dupeSentinel(T, s.i.items[0..s.i.items.len], sentinel) catch unreachable;
        }
    };
}

//TODO: use string(T) as parameters instead of []const T
