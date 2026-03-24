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
    float padding[5];        // 508 - 527 (to align camera_pos to 16 bytes)
    Vector3 camera_pos;      // 528 - 543
    Vector3 camera_forward;  // 544 - 559
    Vector3 camera_right;    // 560 - 575
    Vector3 camera_up;       // 576 - 591
    Vector3 light_pos;       // 592 - 607
};

// Main ASM rendering function for a specific row range (inclusive start, exclusive end)
void render_frame_part(uint32_t* pixels, int width, int height, int y_start, int y_end, const SceneData* scene);
// Full ASM rendering function (calls render_frame_part internally or maintains legacy signature)
void render_frame(uint32_t* pixels, int width, int height, const SceneData* scene);

#ifdef __cplusplus
}
#endif

#endif // RAYTRACER_H
