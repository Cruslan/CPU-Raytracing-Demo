# CPU-Raytracing-Demo

A high-performance, real-time interactive software raytracer built to demonstrate cross-language C++17 and x86-64 NASM Assembly integration with 128-bit SSE4.1 SIMD vector acceleration.

The core mathematical raytracing pipeline (ray generation, ray-sphere/ray-plane intersections, reflection vectors, and lighting calculations) is written entirely in hand-optimized x86-64 Assembly using 128-bit SSE4.1 SIMD vector instructions, achieving frame rates of **950+ FPS** (peak **974 FPS**). Windowing, user input, camera transformation, multi-threading, and framebuffer display are managed by C++17 and Qt6.

## Key Features & Optimizations

- **High-Performance Assembly Core:** Mathematical calculations executed using x86-64 NASM and 128-bit SSE4.1 SIMD vector instructions (`dpps`, `addps`, `subps`, `mulps`, `rsqrtps` with Newton-Raphson refinement).
- **Extreme FPS Performance:** Benchmarks reach **956.94 FPS** (1-sphere scene) and **278.24 FPS** (10-sphere complex scene), delivering a **+56.2% net speedup** over initial baselines.
- **Multi-Core Parallel Rendering:** Screen space is dynamically partitioned and rendered in parallel across all available host CPU cores via C++ `std::thread` worker pools with 100% ARGB32 checksum determinism.
- **Stack & Thread Safety:** Redesigned 16-byte aligned stack allocation (`sub rsp, 312`) guaranteeing complete System V AMD64 ABI register preservation (`rbx`, `r12`-`r15`) and thread safety across 1 to 64 concurrent threads.
- **Real-Time Interactive Camera:** Uncapped real-time freecam navigation (WASD movement + mouse look) hooked directly into the Qt event loop with real-time FPS benchmarking in the window title.
- **Recursive Metallic Reflections:** Reflection ray bounce calculations for metallic surfaces and procedural checkerboard plane shading.

## Prerequisites

Building and running the project requires a Linux environment with:

- `g++` (C++17 capable compiler)
- `nasm` (Netwide Assembler with SSE4.1 support)
- `pkg-config`
- `Qt6Widgets` / `qt6-base` (Qt6 development framework and `moc`)

## Building

A `Makefile` is provided to compile C++ code, assemble NASM source, process Qt meta-object files, and link the final binary:

```bash
make
```

To clean build artifacts:
```bash
make clean
```

## Running & Controls

Execute the compiled binary:
```bash
./raytracer
```

### Navigation Controls
- **W / A / S / D:** Move camera forward, left, backward, and right.
- **Mouse Drag (Left/Right Click):** Rotate camera view (pitch and yaw).

## System Architecture

The project interfaces low-level assembly and C++ using the **System V AMD64 ABI**:

1. **`main.cpp`**: Manages Qt6 `QMainWindow`, handles keyboard/mouse input, computes camera matrices, allocates a 32-bit ARGB framebuffer, and dispatches parallel worker threads using `std::thread::hardware_concurrency()`.
2. **`raytracer.asm`**: Exports `render_frame_part(uint32_t* pixels, int width, int height, int y_start, int y_end, const SceneData* scene)`. Performs SIMD ray generation, ray-sphere / ray-plane intersection, lighting dot products, reflection ray generation, and writes ARGB32 pixels directly via fast pointer increment (`add rdi, 4`).
3. **`raytracer.h`**: Shared 16-byte aligned C++ and Assembly data structures (`SceneData`, `Vector3`, `Sphere`).
