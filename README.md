## CPU-Raytracing-Demo

A real-time, interactive software raytracer built to demonstrate high-performance cross-language integration. The mathematical heavy lifting (ray generation, intersection, and shading) is written entirely in x86-64 Assembly using SSE instructions, while the windowing, user input, and pixel display are managed by modern C++ and Qt6.

## Features

- **ASM Rendering Core:** Ray-sphere and ray-plane intersections calculated using raw x86-64 NASM and SSE vectorization.
- **Real-Time Freecam:** Fly around the scene in real-time using a delta-time smoothed camera.
- **Reflective Materials:** Recursive ray bouncing to simulate perfect metallic reflections.
- **Uncapped Framerate:** Directly hooked into the Qt event loop to render as fast as your CPU allows, with a real-time FPS counter in the window title.
- **Interactive Controls:** "Click and Drag" mouse look and WASD keyboard movement.

## Prerequisites

To build and run this project, you will need a Linux environment with the following dependencies installed:

- `g++` (Compiler with C++17 support)
- `nasm` (Netwide Assembler)
- `pkg-config`
- `qt6-base` / `Qt6Widgets` (Qt 6 development libraries and `moc`)

## Building

A `Makefile` is provided to easily compile the C++ code, assemble the NASM code, generate Qt meta-object code, and link everything together.

1. Open a terminal in the project directory.
2. Run the build command:
   ```bash
   make
   ```

This will generate an executable named `raytracer`.

## Running and Controls

Start the application by running:
```bash
./raytracer
```

### Controls

- **W / A / S / D:** Move the camera forward, left, backward, and right.
- **Mouse Left/Right Click (Hold & Drag):** Look around the scene.

## Architecture

The project bridges the gap between low-level assembly and high-level C++ using the **System V AMD64 ABI**. 

- `main.cpp`: Manages the Qt6 `QMainWindow`, handles keyboard/mouse events, maintains the camera state (position, yaw, pitch), and allocates a 32-bit ARGB pixel buffer.
- `raytracer.asm`: Exposes a `render_frame` function callable from C++. It takes the pixel buffer pointer, screen dimensions, and a pointer to the `SceneData` struct. It loops over every pixel, casts rays into the mathematical scene, computes bounces, and writes the final 8-bit color values back to the C++ buffer.
- `raytracer.h`: Defines the 16-byte aligned `SceneData`, `Vector3`, and `Sphere` structures shared between C++ and Assembly to ensure perfect memory layout matching.
