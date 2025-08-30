[Return to Home](/)

# Roc Platforms: Supporting multi-entrypoint hosts

<time class="post-date" datetime="2025-08-30">30 Aug 2025</time> *~8 mins reading time*

This post summarises a problem we discovered while implementing the test platforms: how to “run” a Roc app with our pre-built interpreter-shim when the platform host expects multiple entrypoints. The solution involves a small layer of glue generated at runtime that maps multiple entrypoints to a single interpreter entrypoint.

The short version:
- Platform hosts expect to find multiple entrypoint symbols provided by the Roc app (e.g. `init!`, `update!`, `render!`).
- We compile and embed an interpreter shim into the Roc CLI which exposes a single generic entrypoint.
- At runtime, the Roc CLI generates a tiny LLVM bitcode file that defines the expected host symbols and delegates them to the single interpreter entrypoint.
- This enables fast dev loops using the interpreter for multi-entrypoint hosts.

## Background: Roc App + Platform Host = Executable

A Roc application is linked with a platform host to produce an executable.

- Platform authors provide a static library (e.g. `libhost.a`, `host.lib`) which we call the platform host.
- `roc build app.roc` compiles the Roc app to machine code and links it with the host to produce an executable.
- Hosts expect the app to define a set of entrypoints—for example, `init!`, `update!`, and `render!`.
- At runtime, the host calls those entrypoints, passing a struct of function pointers for Roc.

Here’s an illustration in Zig of a host invoking two entrypoints implemented by a Roc app:

```zig
fn platform_main() !void {
    // Create the RocOps struct; roc_alloc, roc_dealloc, roc_crash, roc_dbg, etc...
    var roc_ops = RocOps{ ... };

    // Generate random integers
    var rand = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const a = rand.random().intRangeAtMost(i64, 0, 100);
    const b = rand.random().intRangeAtMost(i64, 0, 100);

    // Arguments struct for passing two integers to Roc as a tuple
    const Args = extern struct { a: i64, b: i64 };
    var args = Args{ .a = a, .b = b };

    // Call `addInts`
    var add_result: i64 = undefined;
    roc__addInts(&roc_ops, @as(*anyopaque, @ptrCast(&add_result)), @as(*anyopaque, @ptrCast(&args)));

    // Call `multiplyInts`
    var multiply_result: i64 = undefined;
    roc__multiplyInts(&roc_ops, @as(*anyopaque, @ptrCast(&multiply_result)), @as(*anyopaque, @ptrCast(&args)));
}
```

This is the “normal” compiled workflow.

## The Interpreter Shim

For a fast dev loop (`roc app.roc` without a subcommand), we use an interpreter which is very fast to start executing as it avoids lowering the program to machine code and linking.

- We pre-compile an interpreter shim as a static library and embed it into the Roc CLI (`libroc_interpreter_shim.a`).
- When you “run” an app, the CLI links the host with this interpreter shim (instead of an app object file) and caches the resulting executable. This can be done once, so subsequent runs can use the cached executable instead.
- The CLI is responsible for file I/O and loads the app, parsing/canonicalization/typechecking it etc to produce a `ModuleEnv`, which is a cacheable intermediate representation of the application. Note if the source code has not changed the CLI can load this from cache instead.
- It then forks a child process to run the shim and passes the `ModuleEnv` via inter-process communication (IPC).

This gives fast iteration: your app logic runs under the interpreter while the host and ABI remain identical.

## The multi-entrypoint problem

Pre-building the interpreter shim means it cannot know the platform and the expected entrypoints ahead of time. To remain platform-agnostic, the shim is compiled to export only a single generic entrypoint:

```zig
export fn roc_entrypoint(entry_idx: u32, ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, arg_ptr: ?*anyopaque) callconv(.C) void
```

- `roc_entrypoint` is the shim’s single entry.
- The first argument is an `entry_idx` used to dispatch to the intended platform entry (i.e. “which function did the host want to call?”).
- That’s convenient for the interpreter, but the host still needs multiple concrete symbols to link against.

**So: how do we link a host that expects multiple symbols with an interpreter shim that only exports one?**

## The multi-entrypoint solution

We generate a thin, per-platform “adapter” at runtime using Zig’s standard library API `std.zig.llvm.Builder`.

- The Roc CLI looks at the platform’s API to determine which entrypoint symbols the host needs.
- It then generates a small LLVM bitcode module that defines each required symbol and forwards all calls to the single interpreter entry (`roc_entrypoint`), passing an `entry_idx` that identifies the target.
- The CLI compiles this bitcode into an object, then links: host + interpreter shim + this small adapter object.
- The result is an executable with all expected symbols provided, and an interpreter implementation in place of a fully compiled application.

A simplified LLVM bitcode file example for three entrypoints:

```llvm
; ModuleID = 'platform_host_shim'
source_filename = "platform_host_shim"

declare void @roc_entrypoint(i32 %0, ptr %1, ptr %2, ptr %3)

define void @roc__init(ptr %0, ptr %1, ptr %2) {
entry:
  call void @roc_entrypoint(i32 0, ptr %0, ptr %1, ptr %2)
  ret void
}

define void @roc__render(ptr %0, ptr %1, ptr %2) {
entry:
  call void @roc_entrypoint(i32 1, ptr %0, ptr %1, ptr %2)
  ret void
}

define void @roc__update(ptr %0, ptr %1, ptr %2) {
entry:
  call void @roc_entrypoint(i32 2, ptr %0, ptr %1, ptr %2)
  ret void
}
```

Each defined symbol (`roc__init`, `roc__render`, `roc__update`) and forwards to `roc_entrypoint` with a distinct index.

This keeps the interpreter shim simple and reusable, while meeting every platform host’s multi-entrypoint ABI.
