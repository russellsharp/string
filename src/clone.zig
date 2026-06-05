const std = @import("std");

pub fn cloneArrayList(a: std.mem.Allocator, T: type, source: std.ArrayList(T)) !std.ArrayList(T) {
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
