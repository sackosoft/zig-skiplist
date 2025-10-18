const std = @import("std");

const Skiplist = @import("skiplist");

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();

    var list = try Skiplist.init(da.allocator());
    defer {
        list.clear(false); // clear first: the values in this example are not allocated and cannot be destroyed.
        list.deinit();
    }

    const key = "key";
    const previous = try list.upsert(key, "world!");
    std.debug.assert(previous == null);

    const value = list.find(key);
    std.debug.assert(value != null);
    std.debug.print("Hello, {s}!\n", .{value.?});
}
