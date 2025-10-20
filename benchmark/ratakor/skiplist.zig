const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error;
const Order = std.math.Order;

pub const default_max_level = 32;

pub fn EasySkipList(
    comptime K: type,
    comptime V: type,
    comptime compareFn: fn (K, K) Order,
) type {
    return SkipList(K, V, std.Random.Xoshiro256, compareFn, default_max_level);
}

pub fn SkipList(
    comptime K: type,
    comptime V: type,
    comptime Prng: type,
    comptime compareFn: fn (K, K) Order,
    comptime maximum_level: usize,
) type {
    return struct {
        const Self = @This();

        header: *Node,
        count: usize = 0,
        level: usize = 1,

        allocator: Allocator,
        prng: Prng,

        pub const max_level = maximum_level;

        pub const Node = struct {
            key: K,
            value: V,
            forward: []?*Node,

            pub inline fn next(self: Node) ?*Node {
                return self.forward[0];
            }
        };

        pub fn init(allocator: Allocator, seed: u64) Error!Self {
            const node = try allocator.create(Node);
            node.forward = try allocator.alloc(?*Node, max_level);
            @memset(node.forward, null);
            return .{
                .header = node,
                .allocator = allocator,
                .prng = Prng.init(seed),
            };
        }

        pub fn deinit(self: Self) void {
            var node: ?*Node = self.header;
            while (node) |n| {
                node = n.next();
                self.allocator.free(n.forward);
                self.allocator.destroy(n);
            }
        }

        fn findNode(self: *Self, key: K, update: ?[]*Node) ?*Node {
            var node: *Node = self.header;
            var lvl = self.level - 1;

            while (true) : (lvl -= 1) {
                while (node.forward[lvl]) |next| {
                    if (compareFn(next.key, key).compare(.gte)) break;
                    node = next;
                }
                if (update) |u| u[lvl] = node;

                if (lvl == 0) break;
            }

            return node.next();
        }

        pub fn upsert(self: *Self, key: K, val: V) Error!*Node {
            var update: [max_level]*Node = undefined;
            const maybe_node = self.findNode(key, &update);

            if (maybe_node) |node| {
                if (compareFn(node.key, key).compare(.eq)) {
                    node.value = val;
                    return node;
                }
            }

            var lvl: usize = 1;
            while (self.prng.random().int(u2) == 0) lvl += 1;
            if (lvl > self.level) {
                if (lvl > max_level) lvl = max_level;
                for (self.level..lvl) |i| {
                    update[i] = self.header;
                }
                self.level = lvl;
            }

            var node = try self.allocator.create(Node);
            node.key = key;
            node.value = val;
            node.forward = try self.allocator.alloc(?*Node, lvl);

            for (0..lvl) |i| {
                node.forward[i] = update[i].forward[i];
                update[i].forward[i] = node;
            }

            self.count += 1;

            return node;
        }

        fn deleteNode(self: *Self, node: *Node, update: []*Node) void {
            for (0..self.level) |lvl| {
                if (update[lvl].forward[lvl] != node) break;
                update[lvl].forward[lvl] = node.forward[lvl];
            }

            while (self.level > 1) : (self.level -= 1) {
                if (self.header.forward[self.level - 1] != null) break;
            }

            self.count -= 1;
            self.allocator.free(node.forward);
            self.allocator.destroy(node);
        }

        pub fn delete(self: *Self, key: K) bool {
            var update: [max_level]*Node = undefined;
            const maybe_node = self.findNode(key, &update);

            if (maybe_node) |node| {
                if (compareFn(node.key, key).compare(.eq)) {
                    self.deleteNode(node, &update);
                    return true;
                }
            }
            return false;
        }

        pub fn deleteRange(self: *Self, from: K, to: K) usize {
            var update: [max_level]*Node = undefined;
            var maybe_node = self.findNode(from, &update);
            var total: usize = 0;

            while (maybe_node) |node| : (total += 1) {
                if (compareFn(node.key, to).compare(.gte)) break;
                maybe_node = node.next();
                self.deleteNode(node, &update);
            }

            return total;
        }

        pub fn find(self: *Self, key: K) ?*Node {
            const maybe_node = self.findNode(key, null);
            if (maybe_node) |node| {
                if (compareFn(node.key, key).compare(.eq)) {
                    return node;
                }
            }
            return null;
        }

        pub inline fn first(self: Self) ?*Node {
            return self.header.forward[0];
        }
    };
}
