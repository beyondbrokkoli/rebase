#ifndef VIBE_MEMORY_H
#define VIBE_MEMORY_H

#include <stdint.h>
#include <stddef.h>

#if defined(_MSC_VER)
    #define VIBE_ALIGN64 __declspec(align(64))
#else
    #define VIBE_ALIGN64 __attribute__((aligned(64)))
#endif

#define VIBE_GRID_CELL_COUNT 2097152 // 128 * 128 * 128

// Vulkan Draw Command Struct
typedef struct {
    uint32_t vertexCount;
    uint32_t instanceCount;
    uint32_t firstVertex;
    uint32_t firstInstance;
} VkDrawIndirectCommand;

// 1. The Physics Stream (AVX2 / Compute SoA)
typedef struct {
    float* px; float* py; float* pz;
    float* vx; float* vy; float* vz;
    float* seed;
    float* material_id;
} PhysicsStreamSoA;

// 2. The Render Stream (Rasterizer AoS)
typedef struct {
    float x, y, z, w;
} VertexAoS;

// The AAA 14-Buffer Temporal Ping-Pong Setup
typedef struct {
    PhysicsStreamSoA physics_A;
    PhysicsStreamSoA physics_B;

    VertexAoS* render_A;
    VertexAoS* render_B;

    uint32_t* grid_A;
    uint32_t* grid_B;

    VkDrawIndirectCommand* draw_cmd_A;
    VkDrawIndirectCommand* draw_cmd_B;

    uint32_t max_particles;
    uint32_t total_allocated_bytes;
    int is_initialized;
} VibeMemoryMap;

// --- VRAM INJECTION PAYLOAD ---
// Lua fills this struct with the mapped pointers from vkMapMemory
typedef struct {
    uint32_t max_particles;

    // Physics Streams
    float *px_A, *py_A, *pz_A, *vx_A, *vy_A, *vz_A, *seed_A, *mat_A;
    float *px_B, *py_B, *pz_B, *vx_B, *vy_B, *vz_B, *seed_B, *mat_B;

    // Render Streams
    VertexAoS *render_A, *render_B;

    // Topo & Cmds
    uint32_t *grid_A, *grid_B;
    VkDrawIndirectCommand *draw_cmd_A, *draw_cmd_B;
} VramInjectionBoard;

#ifdef __cplusplus
extern "C" {
#endif

// Replaces the old vibe_mem_init. C accepts VRAM instead of allocating RAM.
void vibe_mem_inject_vram(VramInjectionBoard* payload);

void vibe_mem_destroy(void);
VibeMemoryMap* vibe_mem_get_map(void);
void vibe_mem_ptr2str(void* ptr, char* out_buffer, size_t buffer_size);

// Telemetry & Time Machine Hooks
void vibe_get_boards(void** out_telemetry, void** out_control);
void vibe_audit_memory_state(void);

#ifdef __cplusplus
}
#endif

#endif // VIBE_MEMORY_H
