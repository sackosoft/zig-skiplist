<div align="center">

# zig-skiplist

**An implementation of a Skiplist in Zig based on [Skip Lists: A Probabilistic Alternative to Balanced Trees -- William Pugh][1]**

[1]: https://15721.courses.cs.cmu.edu/spring2018/papers/08-oltpindexes1/pugh-skiplists-cacm1990.pdf

![Ubuntu Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-skiplist/tests-ubuntu.yml?label=Tests%20Ubuntu)
![Windows Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-skiplist/tests-windows.yml?label=Tests%20Windows)

<!--
TODO: Capture attention with a visualization, diagram, demo or other visual placeholder here.
![Placeholder]()
-->

</div>

## About

Skiplists are a probabilistic data structure which exhibit similar performance characteristics to a balanced binary tree.
Instead of performing re-balancing operations during insertion and deletion; the skiplist is designed to maintain balance
by consulting a random number generator. Unlike binary trees, which may exhibit worst-case runtime performance based on
the order of operations applied to the tree; skiplists are not sensitive to the ordering of inputs and the worst-case
runtime performance is based only on (very unlikely) random chance.

## API


| Contract | Description |
|---|---|
| `const K = []const u8;` | Keys in the skiplist are slices of bytes |
| `const V = []const u8;` | Values in the skiplist are slices of bytes |
| `fn init(alloc: Alloc) Alloc.Error!Skiplist {...}` | Initializes a new instance. |
| `fn deinit(this: *Skiplist) void {...}` | Destroys the instance and calls `alloc.destroy()` on each key and value within the instance. If this behavior is not desired, use `clear(false)` before calling `deinit()`. |
| `fn upsert(this: *Skiplist, key: K, value: V) UpsertError!?V {...}` | Adds the given key value pair to the skiplist. Returns the previous value if the key was already part of the skiplist. |
| `fn find(this: *Skiplist, key: K) ?V {...}` | Searches the list for the value that corresponds to the given key. |
| `pub const DeleteResult = struct { ?[]const u8, ?[]const u8 };`<br> `fn delete(this: *Skiplist, key: K) DeleteResult {...}` | Attempts to remove the given key from the skip list. Returns the removed key and value when a match is found. |
| `fn clear(this: *Skiplist, comptime destroy_pointers: bool) void {...}` | Destroys all nodes within the skiplist, returning it to an empty state. Optionally calling `alloc.destroy()` on each key and value within the skiplist. |
| `fn writeGraphVizDot(this: *Skiplist, writer: *Writer) !void {...}` | Serializes the contents of the skip list to the GraphViz Dot graph notation language, useful to visualize the contents of a skiplist. |


## Zig Version

The `main` branch targets the latest stable Zig version. Currently `0.15.2`.

For other Zig versions look for branches with the named version.

## Installation & Usage

It is recommended that you install `zig-skiplist` using `zig fetch`. This will add a `skiplist` dependency to your `build.zig.zon` file.

```bash
zig fetch --save=skiplist git+https://github.com/sackosoft/zig-skiplist
```

Then, update your `build.zig` to add the module as an import to the module you're developing.

1. Reference the `zig-skiplist` dependency.
2. Import the skiplist module into your module. This makes it available as an import via `@import("skiplist")`.

```zig
// (1) Reference the dependency introduced by `zig fetch`.
const skiplist_dep = b.dependency("skiplist", .{ .target = target, .optimize = optimize });

// (2) Add the module as an import to your executable or library.
your_module.addImport("skiplist", skiplist_dep.module("skiplist"));
```

Now you can import and use the skiplist! Refer to the [examples](./examples/) for more.

```zig
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
```

## Implementation Notes

This `zig-skiplist` implementation uses dynamically-sized skiplist nodes, kind of like [Flexible Array Members][10] in C.
In [a benchmark][11] against the naive implementation, with a secondary allocation for forward pointers, `zig-skiplist`
is about 50% faster and uses about 15% less memory.

[10]: https://en.wikipedia.org/wiki/Flexible_array_member
[11]: https://github.com/sackosoft/zig-skiplist/compare/main...benchmark/ratakor-vs-thsackos

## License

The `zig-skiplist` project is distributed under the terms of the open and permissive MIT License.
The terms of this license can be found in the [LICENSE](./LICENSE) file.
