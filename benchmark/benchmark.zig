const std = @import("std");

const SkiplistThsackos = @import("skiplist");

const SkiplistRatakorGeneric = @import("ratakor/skiplist.zig").EasySkipList;

fn runTest(skiplist: anytype) !void {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();

    const random_data_len = 2048;
    var random_data: [random_data_len]u8 = undefined;
    for (0..random_data_len) |i| {
        random_data[i] = random.intRangeAtMost(u8, 63, 126);
    }

    for (0..10_000) |_| {
        const start = random.intRangeLessThan(usize, 0, 2000);
        const width = random.intRangeLessThan(usize, 6, 32);
        const key = random_data[start .. start + width];

        const action = random.int(u2);
        if (action == 0) {
            // 25%
            _ = skiplist.delete(key);
        } else if (action == 1) {
            // 25%
            _ = skiplist.find(key);
        } else {
            // 50%
            const val = key[0..6];
            _ = try skiplist.upsert(key, std.mem.asBytes(val));
        }
    }
}

pub fn main() !void {
    if (std.os.argv.len != 2) {
        return error.InvalidArgsCount;
    }

    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const alloc = da.allocator();

    const seed = 37;

    const which = std.mem.sliceTo(std.os.argv[1], '\x00');
    if (std.mem.eql(u8, "-ratakor", which)) {
        const SkiplistRatakor = SkiplistRatakorGeneric(
            []const u8,
            []const u8,
            SkiplistThsackos.compare,
        );
        var list = try SkiplistRatakor.init(alloc, seed);
        defer list.deinit();

        try runTest(&list);
    } else if (std.mem.eql(u8, "-thsackos", which)) {
        var list = try SkiplistThsackos.init(da.allocator(), seed);
        defer {
            list.clear(false); // clear first: the values in this example are not allocated and cannot be destroyed.
            list.deinit();
        }

        try runTest(&list);
    } else {
        return error.InvalidArgsValue;
    }
}
