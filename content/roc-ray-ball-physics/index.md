[Return to Home](/)

# Ball physics simulation

This is a simple physics simulation of a number of balls that are attracted to the mouse, and experience gravity.

It was made using a WIP branch from [lukewilliamboswell/roc-ray](https://github.com/lukewilliamboswell/roc-ray) which is a graphics platform for the [roc programming language](https://www.roc-lang.org).

I wanted to find something simple to test the platform, and a new package [lukewilliamboswell/roc-pga2d](https://github.com/lukewilliamboswell/roc-pga2d) I made to learn more about Geometric Algebra and to help develop roc-ray with more interesting demos.

(Note: this uses the mouse... sorry mobile users I hadn't thought about you when making this 😅)

<style>
  #canvas {
      padding: 10px;
      margin: 0 auto;
      border-style: dashed;
      display: block;
      width: 800px;
      height: 600px;
    }
</style>

<canvas id="canvas" oncontextmenu="event.preventDefault()"></canvas>

<script>
    function _date_now() {
        return Date.now();
    }
    function on_load() {
        const dpr = window.devicePixelRatio;
        let canvas = document.getElementById("canvas");

        let on_resize = Module.cwrap("on_resize", null, [
            "number",
            "number",
        ]);

        canvas.addEventListener('click', function(e) {
          canvas.focus();
        });

        canvas.addEventListener('keydown', function(e) {
            if([" ", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].indexOf(e.key) > -1) {
                e.preventDefault();
            }
        });

        canvas.tabIndex = 1;

        let resize_handler = () => {
            on_resize(800, 600);
        };

        window.addEventListener("resize", resize_handler, true);

        resize_handler();
    }

    var Module = {
        postRun: [on_load],
        canvas: document.getElementById("canvas"),
    };
</script>
<script src="/roc-ray-ball-physics/rocray.js"></script>


```roc
app [Model, init!, render!] {
    rr: platform "../platform/main.roc",
    rand: "https://github.com/lukewilliamboswell/roc-random/releases/download/0.3.0/hPlOciYUhWMU7BefqNzL89g84-30fTE6l2_6Y3cxIcE.tar.br",
    pga: "https://github.com/lukewilliamboswell/roc-pga2d/releases/download/0.3.0/pdeyRVVsip_FFlHVK_ybcSzKxZLspU_KyMBicijEL-c.tar.br",
}

import rr.RocRay
import rr.Draw
import rr.Keys
import rand.Random
import pga.PGA2D

Ball : {
    position : PGA2D.Multivector,
    velocity: PGA2D.Multivector,
    mass: F32,
    color: RocRay.Color,
}

# CONSTANTS
numberOfBalls = 10
minBallMass = 1
maxBallMass = 20
minSpringK = 0.001  # Too small: barely any force
maxSpringK = 1.0    # Too large: unstable/explosive behavior
minDamping = 0.0    # No damping (perpetual motion)
maxDamping = 1.0    # Full damping (immediate stop)

Model : { balls : List Ball, springK: F32,  damping: F32, gravity: F32 }

init! : {} => Result Model []
init! = \{} ->

    RocRay.initWindow! { title: "Spring Physics" }
    RocRay.setTargetFPS! 60
    RocRay.displayFPS! { fps: Visible, pos: { x: 10, y: 10 }}

    balls = generateBalls

    Ok {
        balls,
        springK: 0.02,
        damping: 0.9,
        gravity: 0.5,
    }

render! : Model, RocRay.PlatformState => Result Model []
render! = \model, { mouse, keys } ->

    Draw.draw! White \{} ->

        # Display spring stiffness and damping
        Draw.text! {
            text: "Stiffnes: $(formatF32 model.springK) - press A/D to change",
            pos: { x: 10, y: 30 },
            size: 20,
            color: Black,
        }

        Draw.text! {
            text: "Damping: $(formatF32 model.damping) - press W/S to change",
            pos: { x: 10, y: 50 },
            size: 20,
            color: Black,
        }

        Draw.text! {
            text: "Gravity: $(formatF32 model.gravity) - press UP/DOWN to change",
            pos: { x: 10, y: 70 },
            size: 20,
            color: Black,
        }

        Draw.text! {
            text: "Press R to reset the balls",
            pos: { x: 10, y: 90 },
            size: 20,
            color: Black,
        }

        forEach! model.balls \ball ->

            # Get ball position
            w = if (Num.abs ball.position.e12) < 0.000001 then 0.000001 else ball.position.e12
            ballX = ball.position.e20 / w
            ballY = ball.position.e01 / w

            # Draw spring to mouse position
            Draw.line! {
                start: { x: ballX, y: ballY },
                end: mouse.position,
                color: Gray,
            }

            # Draw ball (vary radius based on mass)
            radius = 1 + (ball.mass - minBallMass)
            Draw.circle! {
                center: { x: ballX, y: ballY },
                radius,
                color: ball.color,
            }

            {}

    balls =
        updateBalls model mouse.position
        |> \b ->
            # reset balls if space is pressed
            if Keys.pressed keys KeyR then
                generateBalls
            else
                b

    springK =
        if Keys.pressed keys KeyA then
            model.springK - 0.01
            |> limit { min: minSpringK, max: maxSpringK }
        else if Keys.pressed keys KeyD then
            model.springK + 0.01
            |> limit { min: minSpringK, max: maxSpringK }
        else
            model.springK

    damping =
        if Keys.pressed keys KeyW then
            model.damping + 0.01
            |> limit { min: minDamping, max: maxDamping }
        else if Keys.pressed keys KeyS then
            model.damping - 0.01
            |> limit { min: minDamping, max: maxDamping }
        else
            model.damping

    gravity =
        if Keys.pressed keys KeyUp then
            model.gravity + 0.1
            |> limit { min: 0, max: 10 }
        else if Keys.pressed keys KeyDown then
            model.gravity - 0.1
            |> limit { min: 0, max: 10 }
        else
            model.gravity

    Ok {model & balls, springK, damping, gravity }

updateBalls : Model, RocRay.Vector2 -> List Ball
updateBalls = \model, mousePos ->

    List.map model.balls \ball ->

        # Get ball position
        w = if (Num.abs ball.position.e12) < 0.000001 then 0.000001 else ball.position.e12
        ballX = ball.position.e20 / w
        ballY = ball.position.e01 / w

        # Calculate spring force direction as an ideal point at infinity
        springForce = PGA2D.idealPoint {
            x: (mousePos.x - ballX) * model.springK / ball.mass,
            y: -1 * (mousePos.y - ballY) * model.springK / ball.mass,
        }

        # Calculate gravity force
        gravityForce = PGA2D.idealPoint {
            x: 0,
            y: -model.gravity,
        }

        combindedForce = PGA2D.add springForce gravityForce

        # Update velocity
        velocity = PGA2D.muls ((PGA2D.add ball.velocity combindedForce)) model.damping

        # Create translator from velocity
        translator = PGA2D.translator {
            dx: -velocity.e01,
            dy: -velocity.e20,
        }

        # Update ball position using translator
        position = PGA2D.mul translator ball.position

        { position, velocity, mass: ball.mass, color: ball.color }

generateBalls : List Ball
generateBalls =
    List.range { start: At 0, end: Before numberOfBalls }
    |> List.walk { seed: Random.seed 1234, balls: [] } \state, _ ->

        gen = Random.step state.seed ballGenerator

        { seed: gen.state, balls: List.append state.balls gen.value }

    |> .balls

ballGenerator : Random.Generator Ball
ballGenerator =
    { Random.chain <-
        position: { Random.chain <-
            x: Random.boundedU32 0 800 |> Random.map Num.toF32,
            y: Random.boundedU32 0 600 |> Random.map Num.toF32,
        }
        |> Random.map PGA2D.point,
        velocity: { Random.chain <-
            x: Random.boundedU32 0 10 |> Random.map Num.toF32,
            y: Random.boundedU32 0 10 |> Random.map Num.toF32,
        }
        |> Random.map PGA2D.idealPoint,
        mass: Random.boundedU32 minBallMass maxBallMass |> Random.map Num.toF32,
        color: { Random.chain <-
            r: Random.boundedU8 0 255,
            g: Random.boundedU8 0 255,
            b: Random.boundedU8 0 255,
        } |> Random.map \{ r, g, b } -> RGBA r g b 255,
    }

forEach! : List a, (a => {}) => {}
forEach! = \l, f! ->
    when l is
        [] -> {}
        [x, .. as xs] ->
            f! x
            forEach! xs f!

limit : F32, { min: F32, max: F32} -> F32
limit = \x, { min, max } ->
    if x < min then min else if x > max then max else x

# format a float to a string with 2 decimal places
formatF32 : F32 -> Str
formatF32 = \f32 ->
    rounded = Num.round (f32 * 100)
    whole = rounded // 100
    decimal = Num.abs (rounded % 100)
    decimalStr =
        if decimal < 10 then
            "0$(Num.toStr decimal)"
        else
            Num.toStr decimal

    "$(Num.toStr whole).$(decimalStr)"
```
