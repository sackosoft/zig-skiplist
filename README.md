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

Next, in order for your code to import `zig-skiplist`, you'll need to update your `build.zig` to do the following:

1. get a reference the `zig-skiplist` dependency.
2. get a reference to the `skiplist` module.
3. add the module as an import to your executable or library.

```zig
// (1) Get a reference to the `zig fetch`'ed dependency
const skiplist_dependency = b.dependency("skiplist", .{
    .target = target,
    .optimize = optimize,
});

// (2) Get a reference to the language bindings module.
const skiplist = skiplist_dependency.module("skiplist");

// Set up your library or executable
const lib = // ...
const exe = // ...

// (3) Add the module as an import to your executable or library.
my_exe.root_module.addImport("skiplist", skiplist);
my_lib.root_module.addImport("skiplist", skiplist);
```

Now you can import and use the skiplist!

```zig
const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const Skiplist = @import("skiplist");

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer {
        const check = da.deinit();
        assert(check == .ok);
    }
    const alloc = da.allocator();

    var list = try Skiplist.init(alloc);
    defer { 
        list.clear(false);
        list.deinit();
    }

    const key = "key";
    var previous = try list.upsert(key, "world!"))
    assert(previous == null);

    var value = list.find(key);
    assert(value != null);
    print("Hello, {s}!\n", .{value});
}
```

## License

The `zig-skiplist` project is distributed under the terms of the open and permissive MIT License.
The terms of this license can be found in the [LICENSE](./LICENSE) file.
