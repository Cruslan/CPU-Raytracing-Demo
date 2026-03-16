#ifndef RAYTRACER_H
#define RAYTRACER_H

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

struct alignas(16) Vector3 {
    float x, y, z, w;
};

struct alignas(16) Sphere {
    Vector3 center;
    float radius;
    float padding[3];
    Vector3 color;
};

struct alignas(16) SceneData {
    Sphere spheres[10];      // 0 - 479
    Vector3 plane_normal;    // 480 - 495
    float plane_distance;    // 496 - 499
    int32_t has_plane;       // 500 - 503
    int32_t num_spheres;     // 504 - 507
    float padding[2];        // 508 - 515
    Vector3 camera_pos;      // 516 - 531
    Vector3 camera_forward;  // 532 - 547
    Vector3 camera_right;    // 548 - 563
    Vector3 camera_up;       // 564 - 579
    Vector3 light_pos;       // 580 - 595
};

// Main ASM rendering function
void render_frame(uint32_t* pixels, int width, int height, const SceneData* scene);

#ifdef __cplusplus
}
#endif

#endif // RAYTRACER_H
