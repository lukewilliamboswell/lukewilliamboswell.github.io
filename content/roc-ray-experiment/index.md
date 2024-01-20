[Return to Home](/)

# Building a GUI platform - Action-State using [raylib](https://www.raylib.com) and [zig](https://ziglang.org)

<time class="post-date" datetime="2024-01-21">21 Jan 2024</time>

*Source code at [https://github.com/lukewilliamboswell/roc-ray](https://github.com/lukewilliamboswell/roc-ray)*

Richard Feldman has a draft [Design Idea: Action-State](https://docs.google.com/document/d/16qY4NGVOHu8mvInVD-ddTajZYSsFvFBvQON_hmyHGfo/edit?usp=sharing) which outlines an idea to build User-Interfaces (UI) using Roc. The idea is similar to, but different from how UI are built in Elm with the [The Elm Architecture (TEA)](https://guide.elm-lang.org/architecture/). The design idea is tailored for plugin's. It has an `Init` and `Render` function, instead of the `Model`, `View`, `Update` found in TEA.

I have been wanting to explore this design, and after working on the [roc-wasm4](https://github.com/lukewilliamboswell/roc-wasm4) zig platform with Brendan Hansknecht recently, I thought I might be able to get something working. 

This is my attempt to document that experience and share some of the things I have learnt about platform development along the way. The code isn't polished. There is still a lot more to learn about roc, zig, and platform development. However, I want to share what I have, flaws and all, so that others can benefit from this exploration.

I'm still tinkering with different ideas, and maybe some day this platform can become really useful for building cross-platform GUIs with roc. 

P.S. if you're reading this and have any interest in writing a layout algorithm for GUI's in pure roc, then please let me know. That would make this platform really awesome! 

## Goals

1. Learn more about Roc, platform dev, and have some fun

With this exper

2. Implement a [zig](https://ziglang.org) platform that uses [raylib](https://www.raylib.com) for graphics

asdf

3. Implement the Action-State design idea

The platform is minimal, with only the features needed for the demo implemented.

## Demo

The code for this demo is located at [github.com/lukewilliamboswell/roc-ray](https://github.com/lukewilliamboswell/roc-ray/blob/main/examples/gui-counter.roc). It includes a working implementation for the Counter example used in the Action-State design idea. The demo shows three counters in a window which can be independently modified and retain thier own state in the `Model`. User actions from cliking the buttons update the state of the `Model` using an `Action`.

To run this locally you need [roc](https://www.roc-lang.org), [zig](https://ziglang.org) version 0.11.0, and [raylib](https://www.raylib.com).

<img class="demo-img" src="/roc-ray-experiment/demo.gif" alt="screen capture of the counter demo application being used"/>

## Step 1 Minimal platform

To get started, I copied across another implementation and modified parts as needed. There wasn't a platform with the exact form I needed, but by combining different parts of [roc-wasm4](https://github.com/lukewilliamboswell/roc-wasm4), [roc-zig-package-experiment](https://github.com/lukewilliamboswell/roc-zig-package-experiment), and [roc-lang/platform-switching](https://github.com/roc-lang/roc/tree/main/examples/platform-switching) I was able to get something minimal working. I wanted the API from roc-wasm and the implementation of e.g. `roc_alloc` and `roc_panic` from the platform-switching example.

My aim here was to have a platform that uses `build.zig` to generate the pre-built files e.g. `macos-arm64.a`, so that I can package the platform into a URL. This would mean that the experience for end users when building applications using this platform would be as simple as `roc run`. 

Cross-compiling for different architectures using zig is easy, so my hope is that including raylib and necessary dependencies in this platform will also be easy to build a static library. Then when running an application that targets the platform from a URL roc will automatically use the prebuilt-binary for that platform, and there is no need for application authors to have the host (zig) toolchain, and raylib installed.

To run an app locally, such as while developing the platform or one of the examples, I use a relative path like `packages { ray: "../platform/main.roc" }`, and then use `roc dev --prebuilt-platform example.roc`. This instructs the roc cli to use the prebuilt-platform binary in the platform. This is needed, as the platform is built separately from the roc application.

For the first step when developing the platform, I chose not to include raylib, or call into roc from zig so as to keep things simple. The zig `pub fn main() void` function at this stage just printed "hello,world" to stdio, which was enough to verify the program was running as expected. 

I wanted to confirm the platform built correctly, and that roc was able to link against it.

## Step 2 raylib library

I followed the instructions in [https://github.com/ryupold/raylib.zig](https://github.com/ryupold/raylib.zig) to add raylib to the platform and implement the example from the README.

I updated `build.zig` and made minor changes so the libraries would build and link with roc. The zig `pub fn main() void` was updated to the raylib example. It didn't call into roc at this stage. 

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

## Step 3 Roc <-> Host interface

I did't need to change `platform/main.roc` and the implementation for `mainForHost` in particular. By leaving the roc-host interface as it was, I could also re-purpose the implementation for calling into roc in the `platform/host.zig`.

When the zig calls the `roc__mainForHost_1_exposed_generic` generated by roc, it returns a struct containing two functions `init` and `update`. This is defined in `platform/main.roc` and represents the interface between roc and the host. 

Note that the design for platforms is currently evolving, so how this is done in future may change significantly.

```roc
ProgramForHost : {
    init : Task (Box Model) [],
    update : Box Model -> Task (Box Model) [],
}

mainForHost : ProgramForHost
mainForHost = { init, update }
```

Both of the functions in the `ProgramForHost` provide a boxed representation of the app's `Model` to the host. Boxing the model stores the `Model` on the heap which enables roc to provide the host with an opaque pointer to the the `Model`. 

The platform is unable to know what the size or shape of the `Model` will be, as this is defined in the roc application and provided to the platform. The host receives a pointer to a `Model` by calling `init`, which it can then pass back to roc in a future call to `update`. This is how a roc application is able to retain state between calls.  

## Aside Glue & LLVM IR

In future platform authors will use `roc glue` to generate all of the relevant types and glue code for thier platform roc API and the roc builtins (standard library). However this feature is still in development and there isn't a glue-spec written for zig yet.

It is useful to know that roc can generate the LLVM IR representation for a platform by running e.g. `roc build --emit-llvm-ir --no-link examples/gui-counter.roc`. This produces a `gui-counter.ll` file which contains the IR for the appplication and platform without the host `--no-link`. 

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

## Step 4 Calling Roc
 
The implementation in to call roc from `host.zig` was implemented as follows:

```c
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

I have a surface level appreciation for how this works, so I am not going to try and explain it any further here. However I have always found people to be friendly and helpful when I ask questions in the begineer channel on roc zulip. Thank you again to Brendan Hansknecht for helping with this. 

## Step 5 Adding a single Effect

To confirm roc was being called correctly, and that it could effect raylib I needed an effect. I chose to enable roc to set the window size, as this looked relatively simple to implement. So, first I added the effect in the platform.

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

And finally, in the `host.zig`.

```c
export fn roc_fx_setWindowSize(width: i32, height: i32) callconv(.C) void {
    raylib.SetWindowSize(width, height);
}
```

## Step 6 Roc <-> Roc interface

```roc
platform "roc-ray"
    # due to a bug we cannot export `Program` here but use `_` instead
    requires { Model } { main : _ } 
    exposes [Core, GUI, Action, Task]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

ProgramForHost : {
    init : Task (Box Model) [],
    update : Box Model -> Task (Box Model) [],
}

mainForHost : ProgramForHost
mainForHost = { init, update }

init : Task (Box Model) []
init = main.init |> Task.map Box.box

update : Box Model -> Task (Box Model) []
update = \boxedModel ->
    boxedModel
    |> Box.unbox
    |> main.render
    |> Task.map Box.box
```

The app provides two functions `init` and `render` to the platform. These both return a `Task Model []` that provides the `Model` to be passed to the next frame. The raylib platform 

```c
pub fn main() void {

    // SETUP WINDOW 
    // ...

    // CALL ROC INIT 
    // ...

    // RUN WINDOW FRAME LOOP
    while (!raylib.WindowShouldClose() and !should_exit) {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();

        raylib.ClearBackground(raylib.BLACK);

        // CALL ROC UPDATE
        roc__mainForHost_1_caller(&model, undefined, update_captures);
        roc__mainForHost_2_caller(undefined, update_captures, &model);

        // ...
    }

    // CLEANUP
    // ...
}
```

 so that the application can execute effects like 
reading a file* before returning the modal to use for rendering the screen

```roc
Program : {
    init : Task Model [],
    render : Model -> Task Model [],
}
```

## Application Code

Below is a copy of the source at the time of writing.

```roc
# gui-counter.roc
app "counter"
    packages { ray: "../platform/main.roc" }
    imports [
        ray.Task.{ Task },
        ray.Action.{ Action },
        ray.Core.{ Color, Rectangle },
        ray.GUI.{ Elem },
        Counter.{ Counter },
    ]
    provides [main, Model] to ray

Model : {
    left : Counter,
    middle : Counter,
    right : Counter,
}

Program : {
    init : Task Model [],
    render : Model -> Task Model [],
}

main : Program
main = { init, render }

init : Task Model []
init =

    {} <- Core.setWindowSize { width, height } |> Task.await
    {} <- Core.setWindowTitle "GUI Counter Demo" |> Task.await

    Task.ok {
        left: Counter.init 10,
        middle: Counter.init 20,
        right: Counter.init 30,
    }

render : Model -> Task Model []
render = \model ->

    # this is temporary workaround for a bug `Error in alias analysis: error in module...`
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