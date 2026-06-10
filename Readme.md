# Pretext

This project was written entirely by me, a human, and AI agents were only used for review.  All code is, for better or wose, written by me.

# Purpose

Create a string library in zig that is heavily inspired by C++'s std::string.  It will not be an exact copy but should implement the bulk of methods.

# Scope

## In Scope

Methods
- Mutating 
- Constructors (init in zig)
- Search
- Informational
- Memory Management
  
## Out of Scope
- Iterators
- Overloaded Operators

# References
- https://cppreference.com/cpp/header/string
- https://cplusplus.com/reference/string/string/
- https://www.w3schools.com/cpp/cpp_ref_string.asp

# Interface
- pub const StringErrors = error{ InvalidArgument, EmptyString, ArgumentOutOfRange, NullArguement };
- pub const empty_buffer = "";
- pub fn init(a: std.mem.Allocator, initial: ?[]const T) Self
- pub fn from_arrayList(a: std.mem.Allocator, list: std.ArrayList(T)) Self
- pub fn from_slice(a: std.mem.Allocator, buffer: []const T) Self
- pub fn deinit(s: *Self) void
- pub fn clone(s: Self) Self

## Capacity

- pub fn size(s: *Self) usize
- pub fn length(s: *Self) usize
- pub fn resize(s: *Self, new_capacity: usize, value: ?T) *Self
- pub fn capacity(s: *Self) usize
- pub fn reserve(s: *Self, new_capacity: usize) *Self
- pub fn clear(s: *Self) *Self
- pub fn empty(s: *Self) bool
- pub fn shrink_to_fit(s: *Self) *Self

## Element Access

- pub fn at(s: *Self, pos: usize) !T
- pub fn back(s: *Self) !?T
- pub fn front(s: *Self) !?T

## Modifiers

- pub fn append(s: *Self, suffix: []const T) *Self
- pub fn push_back(s: *Self, element: T) *Self
- pub fn assign(s: *Self, buffer: []const T) *Self
- pub fn insert(s: *Self, pos: usize, value: []const T) *Self
- pub fn erase(s: *Self, pos: usize, len: i64) *Self
- pub fn replace(s: *Self, pos: usize, len: i64, buffer: []const T) !*Self
- pub fn replacen(s: *Self, pos: usize, len: i64, buffer: []const T, subpos: usize, sublen: i64) !*Self
- pub fn swap(s: *Self, other: *Self) !void
- pub fn pop_back(s: *Self) ?T

## String Operations

- pub fn c_str(s: *Self, a: std.mem.Allocator, buffer: *[]T) !usize
- pub fn data(s: *Self) []const T
- pub fn str(s: *Self) []T
- pub fn strSentinel(s: *Self) [:sentinel]T
- pub fn stru(s: *Self, a: std.mem.Allocator, buffer: *[]T) !usize
- pub fn strSentinelu(s: *Self, a: std.mem.Allocator, buffer: *[:sentinel]T) !usize
- pub fn get_allocator(s: *Self) std.mem.Allocator
- pub fn copy(a: std.mem.Allocator, source: string(T)) Self
- pub fn find(s: *Self, needle: []const T, index: usize, len: i64) !i64
- pub fn rfind(s: *Self, needle: []const T, index: usize) !i64
- pub fn find_first_of(s: *Self, needle: []const T, index: usize, n: usize) !i64
- pub fn find_last_of(s: *Self, needle: []const T, index: usize, n: usize) !i64
- pub fn find_first_not_of(s: *Self, notlist: []const T, index: usize, n: usize) !i64
- pub fn find_last_not_of(s: *Self, needle: []const T, pos: i64, n: i64) !i64
- pub fn substr(s: *Self, index: usize, count: i64) ![]T
- pub fn compare(s: *Self, b: []const T) !i8
- pub fn comparen(s: *Self, pos: usize, len: usize, b: []const T, n: i32) !i8

## String Information 

- pub fn starts_with(s: *Self, buffer: []const T) !bool
- pub fn ends_with(s: *Self, buffer: []const T) !bool
- pub fn contains(s: *Self, buffer: []const T) !bool

## String Mutating Methods

- pub fn trimRight(s: *Self, charactersToTrim: []const T) ![]T
- pub fn trimLeft(s: *Self, charactersToTrim: []const T) ![]T
- pub fn trim(s: *Self, charactersToTrim: []const T) ![]T
- pub fn fill(s: *Self, value: T, count: usize) *Self

## Data Methods
- pub fn span(s: *Self, index: usize, len: usize) ![]T
- pub fn slice(s: *Self, index: usize, len: usize) ![]T