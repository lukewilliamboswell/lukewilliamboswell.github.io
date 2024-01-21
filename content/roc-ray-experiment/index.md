[Return to Home](/)

# Building a GUI platform - Action-State using [raylib](https://www.raylib.com) and [zig](https://ziglang.org)

<time class="post-date" datetime="2024-01-21">21 Jan 2024</time> *~10 mins reading time*

Richard Feldman has a draft [Design Idea: Action-State](https://docs.google.com/document/d/16qY4NGVOHu8mvInVD-ddTajZYSsFvFBvQON_hmyHGfo/edit?usp=sharing) which outlines an idea to build User-Interfaces (UI) using Roc. The idea is similar to, but different from how UI are built in Elm with [The Elm Architecture (TEA)](https://guide.elm-lang.org/architecture/). The design idea is tailored for plugins. It has an `Init` and `Render` function, instead of the `Model`, `View`, `Update` found in TEA.

I have been wanting to explore this design, and after working on the [roc-wasm4](https://github.com/lukewilliamboswell/roc-wasm4) zig platform with Brendan Hansknecht recently, I thought I might be able to get something working. 

This is my attempt to document that experience and share some of the things I have learned about platform development along the way. The code isn't polished. There is still a lot more to learn about roc, zig, and platform development. However, I want to share what I have, flaws and all, so that others can benefit from this exploration.

I'm still tinkering with different ideas, and maybe someday this platform can become useful for building cross-platform GUIs with roc. 

- [Goals](#goals)
- [Demo](#demo)
- [Step 1 minimal platform](#step1)
- [Step 2 raylib library](#step2)
- [Step 3 roc <-> host interface](#step3)
- [Glue & LLVM IR](#glue-llvm)
- [Step 4 calling roc](#step4)
- [Step 5 adding an effect](#step5)
- [Step 6 roc <-> roc interface](#step6)
- [Results](#results)
- [Source code](#source)

P.S. If you're reading this and have any interest in writing a layout algorithm for GUI's in pure roc, then please let me know. That would make this platform really awesome!

## [Goals](#goals) {#goals}

1. Learn more about Roc, platform dev, and have some fun
2. Implement a [zig](https://ziglang.org) platform that uses [raylib](https://www.raylib.com) for graphics
3. Implement the Action-State design idea

## [Demo](#demo) {#demo}

The code for this demo is located at [github.com/lukewilliamboswell/roc-ray](https://github.com/lukewilliamboswell/roc-ray/blob/main/examples/gui-counter.roc). It includes a working implementation for the Counter example used in the Action-State design idea. The demo shows three counters in a window that be independently modified and retain their own state in the `Model`. User actions from clicking the buttons update the state of the `Model` using an `Action`.

To run this locally you need [roc](https://www.roc-lang.org), [zig](https://ziglang.org) version 0.11.0, and [raylib](https://www.raylib.com).

<img class="demo-img" src="/roc-ray-experiment/demo.gif" alt="screen capture of the counter demo application being used"/>

## [Step 1 minimal platform](#step1) {#step1}

To get started, I copied and modified another platform to suit raylib. I combined different parts from [roc-wasm4](https://github.com/lukewilliamboswell/roc-wasm4), [roc-zig-package-experiment](https://github.com/lukewilliamboswell/roc-zig-package-experiment), and [roc-lang/platform-switching](https://github.com/roc-lang/roc/tree/main/examples/platform-switching). I wanted the API from roc-wasm and the implementation of e.g. `roc_alloc` and `roc_panic` from the platform-switching example.

I want the experience for application authors using this platform to be as simple as `roc run`. To do this I need the platform to generate the pre-built files e.g. `macos-arm64.a` using the `build.zig` script. I can then package the platform into a URL using `roc build --bundle .tar.br platform/main.roc`. This packages the platform roc API source code along with the pre-built binaries for each supported architecture.

Cross-compiling for different architectures using zig is easy, so my hope is that including raylib and necessary dependencies in this platform will also make it easy to build a static library. Then when running an application that targets the platform from a URL roc will automatically use the prebuilt-binary for that platform, and there is no need for application authors to have the zig toolchain installed.

However, while developing the platform or running an example locally, the platform is built separately from the roc application. I instruct the roc cli to use the prebuilt-platform binary by using a relative path e.g. `packages { ray: "../platform/main.roc" }`, and then `roc dev --prebuilt-platform example.roc`.

To keep things simple I chose not to include raylib or call into roc from zig. The main function in `platform/host.zig` just printed "hello,world" to stdio which was enough to test the platform built correctly, that roc was able to link against it, and that everything ran without any issues.

## [Step 2 raylib library](#step2) {#step2}

Next, I followed the instructions in [https://github.com/ryupold/raylib.zig](https://github.com/ryupold/raylib.zig) to add raylib to the platform and implement the example from the README.

I updated `build.zig` and made minor changes so the libraries would build and link with roc. The main function in `platform/host.zig` was updated with the raylib example. It still didn't call into roc at this stage. 

I wasn't able to get this working on my own, so I reached out to Brendan Hansknecht, who provided assistance with linking and missing symbols.

Below is the zig raylib example which I copied into my `platform/host.zig` alongside the other host functions like `roc_alloc` and `roc_panic`. Running the app with `roc dev` displayed the raylib example in a window with `"hello world!"` printed in yellow text.

```c
// other functions above like roc_alloc, roc_dealloc, roc_panic etc 
// copied from platform-switching example
// ... 

const raylib = @import("raylib");

pub fn main() void {
    raylib.SetConfigFlags(raylib.ConfigFlags{ .FLAG_WINDOW_RESIZABLE = true });
    raylib.InitWindow(800, 800, "hello world!");
    raylib.SetTargetFPS(60);

    defer raylib.CloseWindow();

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        
        raylib.ClearBackground(raylib.BLACK);
        raylib.DrawFPS(10, 10);

        raylib.DrawText("hello world!", 100, 100, 20, raylib.YELLOW);
    }
}
```

The roc app and platform API weren't doing anything useful at this stage. I had a script to build my platform into a static library. Roc could build the app and link it with the platform. The app displayed the raylib example in a window. However, the host wasn't actually calling into roc.

## [Step 3 roc <-> host interface](#step3) {#step3}

I didn't need to change `platform/main.roc` and the implementation for `mainForHost` in particular. By leaving the roc-host interface as it was, I re-purposed the implementation for calling into roc in `platform/host.zig`.

The host will call `roc__mainForHost_1_exposed_generic` which is generated by roc and returns a struct containing two functions `init` and `update`. This is defined in `platform/main.roc` and represents the interface between roc and the host.

*Note the design for platforms is currently evolving, so how this is done in future may change significantly.*

```roc
ProgramForHost : {
    init : Task (Box Model) [],
    update : Box Model -> Task (Box Model) [],
}

mainForHost : ProgramForHost
mainForHost = { init, update }
```

Both of the functions in `ProgramForHost` provide a boxed representation of the app's `Model` to the host. Boxing the model stores the `Model` on the heap which enables roc to provide the host with an opaque pointer to the the `Model`. 

The platform is unable to know the size or shape of `Model`, as this is defined in the application and provided to the platform. The host receives a pointer to a `Model` by calling `init`, which it can then pass back to roc in a future call to `update`. This is how a roc application is able to retain the state between calls.  

## [Glue & LLVM IR](#glue-llvm) {#glue-llvm}

In the future platform authors will use `roc glue` to generate all of the relevant types and glue code for their platform, including the roc builtins (or standard library). However, this feature is still in development and there isn't a glue-spec written for zig yet.

So, in the interim, it is useful to know that roc can generate the LLVM IR representation for a platform by running e.g. `roc build --emit-llvm-ir --no-link examples/gui-counter.roc`. This produces a `gui-counter.ll` file which contains the IR for the application and platform without the host.

For example, the generated LLVM IR for `roc__mainForHost_1_exposed_generic` is:

```c
define void @roc__mainForHost_1_exposed_generic(ptr %0) !dbg !667 {
entry:
  %call = call fastcc { { { { { i32, i32 }, {} }, {} }, {} }, {} } @_mainForHost_99c9f773566b1d5d689233ef7949cf16c8797c970a4668678361d8c89d24f20(), !dbg !668
  store { { { { { i32, i32 }, {} }, {} }, {} }, {} } %call, ptr %0, align 4, !dbg !668
  ret void, !dbg !668
}
```

Which is represented in `platform/host.zig` as:

```c
extern fn roc__mainForHost_1_exposed_generic(*anyopaque) callconv(.C) void;
```

By inspecting the LLVM IR I could sometimes find useful information to assist with platform implementation.

## [Step 4 calling roc](#step4) {#step4}
 
The implementation to call roc in `platform/host.zig` was implemented as follows:

```c
// MODEL
var model: *anyopaque = undefined;

// INIT ROC
const size = @as(usize, @intCast(roc__mainForHost_1_exposed_size()));
const captures = roc_alloc(size, @alignOf(u128));
defer roc_dealloc(captures, @alignOf(u128));

roc__mainForHost_1_exposed_generic(captures);
roc__mainForHost_0_caller(undefined, captures, &model);

const update_task_size = @as(usize, @intCast(roc__mainForHost_2_size()));
var update_captures = roc_alloc(update_task_size, @alignOf(u128));

// UPDATE ROC
roc__mainForHost_1_caller(&model, undefined, update_captures);
roc__mainForHost_2_caller(undefined, update_captures, &model);
```

I only have a surface-level appreciation for how this works, so I am not going to try and explain it any further here. However, I have always found people in the beginner channel on roc zulip to be friendly and helpful whenever I ask any questions. 

Thank you again to Brendan Hansknecht for helping me with this implementation. 

## [Step 5 adding an effect](#step5) {#step5}

To confirm roc was being called correctly, and that it could work with raylib I needed an `Effect`. 

I chose to give roc the ability to set the window size, as this looked relatively simple to implement. So, first I added the effect in the platform. 

From an application author's perspective, this looks like a function that returns a `Task` that cannot fail and returns the empty `{}` value. This is how it is used in the demo application.

```roc
init : Task Model []
init =

    {} <- Core.setWindowSize { width, height } |> Task.await

    # ... 
```

Within the platform, this is implemented using an `Effect`.

```roc 
# platform/Effect.roc
setWindowSize : I32, I32 -> Effect {}

# platform/Task.roc, since moved to platform/Core.roc
setWindowSize : { width : F32, height : F32 } -> Task {} []
setWindowSize = \{ width, height } ->
    Effect.setWindowSize (Num.round width) (Num.round height)
    |> Effect.map Ok
    |> InternalTask.fromEffect
```

*Note here that the host receives two `I32` values which is what raylib requires. However, for application authors, I have exposed an API that expects two `F32` in a record. My hypothesis is that a record will be more explicit for what these arguments do, and `F32`'s will simplify using these values across the app without having a lot of calls to `Num.toI32` or `Num.toF32`.*

Finally, this Effect is implemented in `platform/host.zig` so that roc will link against this and can call this function in the host.

```c
export fn roc_fx_setWindowSize(width: i32, height: i32) callconv(.C) void {
    raylib.SetWindowSize(width, height);
}
```

This is how roc will call into the host. Note that the host first calls into roc with `init` or `update`, and then these `Effect`s enable roc to call back into the host for impure operations like writing to a file, or requesting a change in window size.

## [Step 6 roc <-> roc interface](#step6) {#step6}

The app provides two functions `init` and `render` to the platform. These both return a `Task Model []` that provides the `Model` to be used in the next update.

In the demo application this is implemented as follows:

```roc
# examples/gui-counter.roc
app "counter"
    # ...
    provides [main, Model] to ray # from application to platform

# the application's state
Model : { left : Counter, middle : Counter, right : Counter }

# to the platform
main : Program Model
main = { init, render }

# returns a Model and does not fail 
init : Task Model []

# takes a Model and returns a new Model
render : Model -> Task Model []
```

Recall from earlier that the interface with the host, `ProgramForHost`, provides a boxed representation of the app's `Model`. This is achieved within the platform by transforming the `init` and `update` provided by the application as follows: 

```roc
# platform/main.roc
platform "roc-ray"
    requires { Model } { main : Program Model } # from application
    # ...
    provides [mainForHost] # to host

# interface with the host
ProgramForHost : {
    init : Task (Box Model) [],
    update : Box Model -> Task (Box Model) [],
}

mainForHost : ProgramForHost
mainForHost = { init, update }

# transform main.init provided by the application
init : Task (Box Model) []
init = main.init |> Task.map Box.box

# transform main.render provided by the application
update : Box Model -> Task (Box Model) []
update = \boxedModel ->
    boxedModel
    |> Box.unbox
    |> main.render
    |> Task.map Box.box
```

Note the model is unboxed and then boxed when calling the `render` provided by the application.

## [Results](#results) {#results}

1. Learn more about Roc, platform dev, and have some fun

TODO

2. Implement a [zig](https://ziglang.org) platform that uses [raylib](https://www.raylib.com) for graphics

TODO

3. Implement the Action-State design idea

TODO 

The platform is minimal, with only the features needed for the demo implemented.

## [Source code](#source) {#source}

*full source code at [https://github.com/lukewilliamboswell/roc-ray](https://github.com/lukewilliamboswell/roc-ray)*

Below is a copy of the demo application at the time of writing.

```roc
# gui-counter.roc
app "counter"
    packages { ray: "../platform/main.roc" }
    imports [
        ray.Task.{ Task },
        ray.Action.{ Action },
        ray.Core.{ Program, Color, Rectangle },
        ray.GUI.{ Elem },
        Counter.{ Counter },
    ]
    provides [main, Model] to ray

Model : {
    left : Counter,
    middle : Counter,
    right : Counter,
}

main : Program Model
main = { init, render }

init : Task Model []
init =

    {} <- Core.setWindowSize { width, height } |> Task.await
    {} <- Core.setWindowTitle "GUI Counter demo" |> Task.await

    Task.ok {
        left: Counter.init 10,
        middle: Counter.init 20,
        right: Counter.init 30,
    }

render : Model -> Task Model []
render = \model ->

    # this is a temporary workaround for a bug `Error in alias analysis: error in module...`
    # sometimes we need an extra Task in the chain to prevent this error
    _ <- Core.getMousePosition |> Task.await
    
    GUI.col [
        GUI.text { label: "Click below to change the counters, press ESC to exit", color: black },
        GUI.row [
            GUI.translate (Counter.render model.left red) .left \record, count -> { record & left: count },
            GUI.translate (Counter.render model.middle green) .middle \record, count -> { record & middle: count },
            GUI.translate (Counter.render model.right blue) .right \record, count -> { record & right: count },
        ],
    ]
    |> GUI.window { title: "Window", onClose: \_ -> Action.none }
    |> GUI.draw model {
        x: width / 8,
        y: height / 8,
        width: width * 6 / 8,
        height: height * 6 / 8,
    }

width = 800
height = 600
black = { r: 0, g: 0, b: 0, a: 255 }
blue = { r: 29, g: 66, b: 137, a: 255 }
red = { r: 211, g: 39, b: 62, a: 255 }
green = { r: 0, g: 59, b: 73, a: 255 }
```

```roc
# Counter.roc
interface Counter
    exposes [Counter, init, render]
    imports [ray.Action.{ Action }, ray.Core.{ Color }, ray.GUI.{ Elem }]

Counter := I64

init : I64 -> Counter
init = @Counter

render : Counter, Color -> Elem Counter
render = \@Counter state, color ->
    GUI.col [
        GUI.button {
            text: "+",
            onPress: \@Counter prev -> Action.update (@Counter (prev + 1)),
        },
        GUI.text {
            label: "Clicked $(Num.toStr state) times",
            color,
        },
        GUI.button {
            text: "-",
            onPress: \@Counter prev -> Action.update (@Counter (prev - 1)),
        },
    ]
```