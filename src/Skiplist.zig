const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Alloc = std.mem.Allocator;
const Writer = std.Io.Writer;

const Max: [256]u8 = [_]u8{std.math.maxInt(u8)} ** 256;

/// The empty slice is guaranteed to be "less than" all other keys.
/// Callers are prohibited from using the empty slice as a key in the skiplist.
const MinKey: []const u8 = Max[0..0];

/// This slice is effectively "larger than" all other keys.
/// Callers are prohibited from using this key or any other key with the same prefix in the skiplist.
const MaxKey: []const u8 = Max[0..];

const Level = u8;
const MaxLevel = 48; // ¯\_(ツ)_/¯ 32 seems restrictive, 64 seems impossible.

fn compare(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

const Skiplist = @This();
const K = []const u8;
const V = []const u8;

alloc: Alloc,
prng: std.Random.Xoshiro256,
nil: *Node,
header: *Node,

pub fn init(alloc: Alloc) Alloc.Error!@This() {
    const nil = try Node.init(alloc, MaxKey, MinKey, 0);
    const header = try Node.init(alloc, MinKey, MinKey, MaxLevel);
    @memset(header.forwards(), nil);
    header.level = 1; // Must be done after @memset

    return .{
        .alloc = alloc,
        .nil = nil,
        .header = header,
        .prng = std.Random.DefaultPrng.init(7),
    };
}

pub fn deinit(this: *@This()) void {
    this.clear(true);
    this.nil.deinit(this.alloc);
    this.header.level = MaxLevel;
    this.header.deinit(this.alloc);
}

/// Empties the list by destroying all internal nodes between the header and end of the list.
/// `destroy_pointers`: When true, free will be called on all keys and values in the internal nodes. When false, free will be skipped.
pub fn clear(this: *@This(), comptime destroy_pointers: bool) void {
    var last = this.header;
    var ptr = last.getForward(0);
    while (ptr != this.nil) {
        last = ptr;
        ptr = ptr.getForward(0);
        if (destroy_pointers) {
            last.destroy(this.alloc);
        } else {
            last.deinit(this.alloc);
        }
    }
    assert(ptr == this.nil);
    this.header.level = MaxLevel; // Must be done for @memset
    @memset(this.header.forwards(), this.nil);
    this.header.level = 1;
}

pub fn find(this: *@This(), key: K) ?V {
    if (key.len == 0) return null;

    var ptr = this.header;
    for (0..this.header.level) |level| {
        const i = this.header.level - level - 1;
        assert(i < ptr.level);
        while (compare(ptr.getForward(i).getKey(), key) == .lt) {
            ptr = ptr.getForward(i);
        }
    }
    ptr = ptr.getForward(0);
    if (ptr == this.nil) {
        return null;
    } else if (compare(ptr.getKey(), key) == .eq) {
        return ptr.getValue();
    } else {
        return null;
    }
}

pub const DeleteResult = struct { ?[]const u8, ?[]const u8 };
pub fn delete(this: *@This(), key: K) DeleteResult {
    if (key.len == 0) return .{ null, null };

    var ptr = this.header;
    var update: [MaxLevel]*Node = undefined;
    assert(blk: {
        @memset(update[0..MaxLevel], undefined);
        break :blk true;
    });
    for (0..this.header.level) |level| {
        const i = this.header.level - level - 1;
        assert(i < ptr.level);
        while (compare(ptr.getForward(i).getKey(), key) == .lt) {
            ptr = ptr.getForward(i);
        }
        update[i] = ptr;
    }
    ptr = ptr.getForward(0);
    if (ptr == this.nil) {
        return .{ null, null };
    } else if (compare(ptr.getKey(), key) == .eq) {
        const k = ptr.getKey();
        const v = ptr.getValue();
        for (0..ptr.level) |i| {
            update[i].setForward(i, ptr.getForward(i));
        }
        assert(this.header.level >= ptr.level);
        ptr.deinit(this.alloc);
        while (this.header.level > 1 and this.header.getForward(this.header.level - 1) == this.nil) {
            this.header.level -= 1;
        }
        return .{ k, v };
    } else {
        return .{ null, null };
    }
}

pub const UpsertError = Alloc.Error || error{InvalidKey};
pub fn upsert(this: *@This(), key: K, value: V) UpsertError!?V {
    if (key.len == 0) return error.InvalidKey;

    var ptr = this.header;
    var update: [MaxLevel]*Node = [_]*Node{undefined} ** MaxLevel;
    for (0..this.header.level) |level| {
        const i = this.header.level - level - 1;
        assert(i < ptr.level);
        while (compare(ptr.getForward(i).getKey(), key) == .lt) {
            ptr = ptr.getForward(i);
        }
        update[i] = ptr;
    }
    ptr = ptr.getForward(0);
    if (compare(ptr.getKey(), key) == .eq) {
        if (ptr == this.nil) {
            return error.InvalidKey; // Must be checked after `compare()` keys, since ptr may be nil when inserting.
        }
        const old = ptr.getValue();
        ptr.setValue(value);
        return old;
    } else {
        const level = this.randomLevel();
        if (level > this.header.level) {
            for (this.header.level..level) |i| {
                update[i] = this.header;
            }
            this.header.level = level;
        }
        ptr = try Node.init(this.alloc, key, value, level);
        for (0..level) |i| {
            ptr.setForward(i, update[i].getForward(i));
            update[i].setForward(i, ptr);
        }
        return null;
    }
}

fn randomLevel(this: *@This()) Level {
    var level: Level = 1;
    var random = this.prng.random();
    while (random.float(f32) < 0.5 and level < MaxLevel) {
        level += 1;
    }
    return level;
}

pub fn writeGraphVizDot(this: *@This(), writer: *Writer) !void {
    try writer.print(
        \\digraph g {{
        \\  rankdir=LR;
        \\  rank=same;
        \\
        \\
    , .{});

    try this.header.writeGraphVizDot(writer, .header, null);
    try this.nil.writeGraphVizDot(writer, .nil, this.header.level);
    var ptr = this.header.getForward(0);
    while (ptr != this.nil) : (ptr = ptr.getForward(0)) {
        try writer.print("\n", .{});
        try ptr.writeGraphVizDot(writer, .internal, null);
    }

    try writer.print(
        \\}}
        \\
    , .{});
    try writer.flush();
}

/// A `Node` contains a key value pair within the skip list.
/// Keys are limited to 2^32
const Node = extern struct {
    key: [*]const u8,
    value: [*]const u8,
    value_len: u32,
    key_len: u16,
    level: u8,
    forward: [1]*Node = undefined,

    fn init(alloc: Alloc, key: K, value: V, level: Level) Alloc.Error!*Node {
        assert(key.len < std.math.maxInt(@FieldType(Node, "key_len"))); // Skiplist key too long.
        assert(value.len < std.math.maxInt(@FieldType(Node, "value_len"))); // Skiplist value too long.
        assert(level <= MaxLevel);

        const size = nodeSize(level);
        const original = try alloc.alignedAlloc(u8, std.mem.Alignment.of(Node), size);
        const node: *Node = @ptrCast(original);
        node.* = .{
            .key = key.ptr,
            .key_len = @intCast(key.len),
            .value = value.ptr,
            .value_len = @intCast(value.len),
            .level = level,
        };
        assert(node.zeroForward());
        return node;
    }

    fn zeroForward(this: *Node) bool {
        const f: [*]*Node = @ptrCast(&this.forward[0]);
        @memset(f[0..this.level], undefined);
        return true;
    }

    fn deinit(this: *Node, alloc: Alloc) void {
        const original: [*]align(@alignOf(Node)) u8 = @ptrCast(this);
        alloc.free(original[0..nodeSize(this.level)]);
    }

    fn destroy(this: *Node, alloc: Alloc) void {
        assert(this.key != MinKey.ptr); // `destroy()`: Skiplist.header cannot be destroyed!
        assert(this.key != MaxKey.ptr); // `destroy()`: Skiplist.nil cannot be destroyed!
        const original: [*]align(@alignOf(Node)) u8 = @ptrCast(this);
        alloc.free(this.getKey());
        alloc.free(this.getValue());
        alloc.free(original[0..nodeSize(this.level)]);
    }

    fn nodeSize(level: Level) usize {
        assert(level <= MaxLevel);

        const extra_slots = @as(i16, @intCast(level)) - 1;
        const clamp: usize = @max(0, extra_slots);
        return @sizeOf(Node) + (@sizeOf(*Node) * clamp);
    }

    inline fn getKey(this: *Node) []const u8 {
        return this.key[0..this.key_len];
    }

    inline fn getValue(this: *Node) []const u8 {
        return this.value[0..this.value_len];
    }

    inline fn setValue(this: *Node, value: V) void {
        assert(value.len < std.math.maxInt(@FieldType(Node, "value_len"))); // Skiplist value too long.
        this.value = value.ptr;
        this.value_len = @intCast(value.len);
    }

    inline fn setForward(this: *Node, i: usize, node: *Node) void {
        assert(i < this.level);
        const f: [*]*Node = @ptrCast(&this.forward[0]);
        f[i] = node;
    }

    inline fn getForward(this: *Node, i: usize) *Node {
        assert(i < this.level);
        const f: [*]*Node = @ptrCast(&this.forward[0]);
        return f[i];
    }

    inline fn forwards(this: *Node) []*Node {
        assert(this.level > 0);
        assert(this.level <= MaxLevel);
        const f: [*]*Node = @ptrCast(&this.forward[0]);
        return f[0..this.level];
    }

    const Style = enum {
        header,
        internal,
        nil,
    };
    fn writeGraphVizDot(this: *@This(), writer: *Writer, style: Style, level_override: ?Level) !void {
        try writer.print(
            \\  "{*}" [shape=none label=<
            \\    <TABLE>
            \\
        , .{this});

        switch (style) {
            .header => {
                try writer.print(
                    \\      <TR><TD>HEADER</TD></TR>
                    \\
                , .{});
            },
            .internal => {
                try writer.print(
                    \\      <TR><TD>"{s}"</TD></TR>
                    \\      <TR><TD>"{s}"</TD></TR>
                    \\
                , .{ this.getKey(), this.getValue() });
            },
            .nil => {
                try writer.print(
                    \\      <TR><TD>NIL</TD></TR>
                    \\
                , .{});
            },
        }

        var level = this.level;
        if (level_override) |lo| {
            assert(style == .nil); // only time this should be used.
            level = lo;
        }
        for (0..level) |i| {
            const index = level - i - 1;
            try writer.print(
                \\      <TR><TD PORT="{d}">[{d}]</TD></TR>
                \\
            , .{ index, index });
        }

        try writer.print(
            \\    </TABLE>
            \\  >];
            \\
        , .{});

        for (0..this.level) |i| {
            try writer.print(
                \\  "{*}":{d} -> "{*}":{d} [rank="{d}"];
                \\
            , .{ this, i, this.getForward(i), i, i });
        }
    }
};

fn string(alloc: Alloc, i: usize) ![]const u8 {
    const len = i + 1; // Zero length allocation returns a shared 0xfffffffffff pointer.
    const s = try alloc.alloc(u8, len);
    for (0..len) |j| {
        s[j] = 'a' + @as(u8, @intCast(j));
    }
    return s;
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    for (0..20) |i| {
        const k = try string(alloc, i);
        const v = try string(alloc, i);
        var inserted = try list.upsert(k, v);
        assert(inserted == null);
        inserted = try list.upsert(k, v);
        assert(inserted != null);
        assert(std.mem.eql(u8, inserted.?, v));
    }

    for (0..20) |i| {
        const k = try string(alloc, i);
        defer alloc.free(k);

        var found = list.find(k);
        assert(found != null);
        assert(std.mem.eql(u8, k, found.?));

        var key, var value = list.delete(k);
        assert(key != null);
        assert(value != null);
        assert(key.?.ptr != value.?.ptr);
        assert(std.mem.eql(u8, k, key.?));
        assert(std.mem.eql(u8, k, value.?));
        alloc.free(key.?);
        alloc.free(value.?);

        key, value = list.delete(k);
        assert(key == null);
        assert(value == null);

        found = list.find(k);
        assert(found == null);
    }
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    const result = list.upsert(MinKey, MaxKey);
    assert(result == error.InvalidKey);
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    const result = list.upsert(MaxKey, MaxKey);
    assert(result == error.InvalidKey);
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    const key, const value = list.delete(MinKey);
    assert(key == null);
    assert(value == null);
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    const key, const value = list.delete(MaxKey);
    assert(key == null);
    assert(value == null);
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    const value = list.find(MinKey);
    assert(value == null);
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    const value = list.find(MaxKey);
    assert(value == null);
}

test {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer list.deinit();

    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();

    var random_data: [2048]u8 = undefined;
    random.bytes(random_data[0..]);

    for (0..65536) |_| {
        const start = random.intRangeLessThan(usize, 0, 2000);
        const key = random_data[start .. start + 32];
        const val = key[0..12];

        _ = try list.upsert(key, std.mem.asBytes(val));
    }

    list.clear(false);
}

// TODO: The address of pointers are not stable between runs. We should either assign stable identifiers
// to the nodes in the list (which seems to require some performance overhead) or find another way to
// match the output against some expected value. For now, it will remain untested since the graphviz dot
// functionality is not critical.
// pub fn main() !void {
//     var da = std.heap.DebugAllocator(.{}).init;
//     defer {
//         const check = da.deinit();
//         assert(check == .ok);
//     }
//     const alloc = da.allocator();
//
//     var list = try Skiplist.init(alloc);
//     defer {
//         list.clear(false); // Called before deinit since the keys and values are not on the heap.
//         list.deinit();
//     }
//
//     var prng = std.Random.DefaultPrng.init(42);
//     var random = prng.random();
//
//     const random_data_len = 2048;
//     var random_data: [random_data_len]u8 = undefined;
//     for (0..random_data_len) |i| {
//         random_data[i] = random.intRangeAtMost(u8, 63, 126);
//     }
//
//     for (0..3) |_| {
//         const start = random.intRangeLessThan(usize, 0, 2000);
//         const width = random.intRangeLessThan(usize, 6, 32);
//         const key = random_data[start .. start + width];
//         const val = key[0..6];
//
//         _ = try list.upsert(key, std.mem.asBytes(val));
//     }
//
//     var data: [1 << 16]u8 = undefined;
//     var fbs = std.io.fixedBufferStream(data[0..]);
//
//     var write_buffer: [4096]u8 = undefined;
//     var out = fbs.writer().adaptToNewApi(&write_buffer);
//     const writer = &out.new_interface;
//     try list.writeGraphVizDot(writer);
//
//     // TODO: Need a more deterministic node identity than the pointers.
//     const expected_template =
//         \\digraph g {
//         \\  rankdir=LR;
//         \\  rank=same;
//         \\
//         \\  "Skiplist.Node@7fc5cfd40000" [shape=none label=<
//         \\    <TABLE>
//         \\      <TR><TD>HEADER</TD></TR>
//         \\      <TR><TD PORT="2">[2]</TD></TR>
//         \\      <TR><TD PORT="1">[1]</TD></TR>
//         \\      <TR><TD PORT="0">[0]</TD></TR>
//         \\    </TABLE>
//         \\  >];
//         \\  "Skiplist.Node@7fc5cfd40000":0 -> "Skiplist.Node@7fc5cfd20040":0 [rank="0"];
//         \\  "Skiplist.Node@7fc5cfd40000":1 -> "Skiplist.Node@7fc5cfd20040":1 [rank="1"];
//         \\  "Skiplist.Node@7fc5cfd40000":2 -> "Skiplist.Node@7fc5cfd20000":2 [rank="2"];
//         \\  "Skiplist.Node@7fc5cfd60000" [shape=none label=<
//         \\    <TABLE>
//         \\      <TR><TD>NIL</TD></TR>
//         \\      <TR><TD PORT="2">[2]</TD></TR>
//         \\      <TR><TD PORT="1">[1]</TD></TR>
//         \\      <TR><TD PORT="0">[0]</TD></TR>
//         \\    </TABLE>
//         \\  >];
//         \\
//         \\  "Skiplist.Node@7fc5cfd20040" [shape=none label=<
//         \\    <TABLE>
//         \\      <TR><TD>"I`jBXiM\tkvKrqG_Lv"</TD></TR>
//         \\      <TR><TD>"I`jBXi"</TD></TR>
//         \\      <TR><TD PORT="1">[1]</TD></TR>
//         \\      <TR><TD PORT="0">[0]</TD></TR>
//         \\    </TABLE>
//         \\  >];
//         \\  "Skiplist.Node@7fc5cfd20040":0 -> "Skiplist.Node@7fc5cfd20000":0 [rank="0"];
//         \\  "Skiplist.Node@7fc5cfd20040":1 -> "Skiplist.Node@7fc5cfd20000":1 [rank="1"];
//         \\
//         \\  "Skiplist.Node@7fc5cfd20000" [shape=none label=<
//         \\    <TABLE>
//         \\      <TR><TD>"eWYF}LKr{jlB"</TD></TR>
//         \\      <TR><TD>"eWYF}L"</TD></TR>
//         \\      <TR><TD PORT="2">[2]</TD></TR>
//         \\      <TR><TD PORT="1">[1]</TD></TR>
//         \\      <TR><TD PORT="0">[0]</TD></TR>
//         \\    </TABLE>
//         \\  >];
//         \\  "Skiplist.Node@7fc5cfd20000":0 -> "Skiplist.Node@7fc5cfd20080":0 [rank="0"];
//         \\  "Skiplist.Node@7fc5cfd20000":1 -> "Skiplist.Node@7fc5cfd20080":1 [rank="1"];
//         \\  "Skiplist.Node@7fc5cfd20000":2 -> "Skiplist.Node@7fc5cfd60000":2 [rank="2"];
//         \\
//         \\  "Skiplist.Node@7fc5cfd20080" [shape=none label=<
//         \\    <TABLE>
//         \\      <TR><TD>"gYdBcCV[~a|e^h"</TD></TR>
//         \\      <TR><TD>"gYdBcC"</TD></TR>
//         \\      <TR><TD PORT="1">[1]</TD></TR>
//         \\      <TR><TD PORT="0">[0]</TD></TR>
//         \\    </TABLE>
//         \\  >];
//         \\  "Skiplist.Node@7fc5cfd20080":0 -> "Skiplist.Node@7fc5cfd60000":0 [rank="0"];
//         \\  "Skiplist.Node@7fc5cfd20080":1 -> "Skiplist.Node@7fc5cfd60000":1 [rank="1"];
//         \\}
//         \\
//     ;
//     var expected: [expected_template.len]u8 = undefined;
//     std.mem.copyForwards(u8, expected[0..], expected_template[0..]);
//     var temp: [64]u8 = undefined;
//     var temp_fbs = std.io.fixedBufferStream(&temp);
//     try std.fmt.format(
//         &temp_fbs.writer(),
//         "{*}",
//         .{list.header},
//     );
//     const replaced = std.mem.replace(u8, expected[0..], "Skiplist.Node@7fc5cfd60000", "Skiplist.Node@NIL-00000000", expected[0..]);
//     assert(replaced == 26);
//     std.debug.print("{s}\n", .{expected[0..]});
//
//     try std.testing.expectEqualStrings(expected[0..], fbs.getWritten());
// }
