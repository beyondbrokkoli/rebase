#ifndef VIBE_CONTROL_BOARD_H
#define VIBE_CONTROL_BOARD_H

#include <stdint.h>
#include <stdatomic.h>
#include <stddef.h>

#define VIBE_MAX_USER_PARAMS 16

// ========================================================================
// 1. ASYNCHRONOUS DATA STRUCTURES
// ========================================================================

// Sequence Lock for safe 16-float asynchronous transfers
typedef struct {
    _Atomic uint32_t sequence;
    float matrix[16];          // Column-major viewProj
} AsyncCameraMatrix;

// ========================================================================
// 2. SUB-SYSTEM BOARDS
// ========================================================================

// The Engine Core (Lifecycle & Debugging)
typedef struct {
    _Atomic int is_running;
    _Atomic int force_draw_buffer;
    _Atomic int debug_frame_step;  // 0 = Free Run, 1 = Paused, 2 = Step
} CoreStateBoard;

// The Entity Atlas (Memory Segmentation Boundaries)
typedef struct {
    _Atomic uint32_t total_active_count;
    _Atomic uint32_t cpu_core_offset;    _Atomic uint32_t cpu_core_count;
    _Atomic uint32_t gpu_hunters_offset; _Atomic uint32_t gpu_hunters_count;
    _Atomic uint32_t gpu_boids_offset;   _Atomic uint32_t gpu_boids_count;
    _Atomic uint32_t gpu_meteors_offset; _Atomic uint32_t gpu_meteors_count;
} AtlasBoard;

// The Physics & Shader Payload (The Frictionless Sandbox)
typedef struct {
    _Atomic int swarm_state;       // 0-7 State Machine

    // Generic Push Constants / AVX2 Variables
    // Lua defines the mapping (e.g., [0]=gravity, [1]=metal, [2]=bass)
    // C blindly copies this array to vkCmdPushConstants every frame.
    _Atomic float params[VIBE_MAX_USER_PARAMS];
} SimulationBoard;

// Asynchronous Input State (For Lua to read OS events from C, or vice versa)
typedef struct {
    _Atomic uint32_t mouse_buttons;
    _Atomic float mouse_x;
    _Atomic float mouse_y;
    _Atomic uint32_t key_states;
} InputBoard;

// ========================================================================
// 3. THE MASTER CONTROL BOARD
// ========================================================================

// The Lock-Free Shared State (Lua Writes -> C Reads)
typedef struct {
    CoreStateBoard  core;
    AtlasBoard      atlas;
    SimulationBoard sim;
    InputBoard      input;
    AsyncCameraMatrix camera;
} EngineControlBoard;

// --- MEGALOMANIACAL TELEMETRY LAYER ---

typedef struct {
    uint64_t ptr_address;
    size_t size_bytes;
    int alignment;
    char name[32];
} BufferTelemetry;

typedef struct {
    _Atomic uint64_t bridge_crossings;
    _Atomic int current_c_phase;
    BufferTelemetry buffers[14];
} EngineTelemetryBoard;

// Global Instances
extern EngineControlBoard g_ControlBoard;
extern EngineTelemetryBoard g_TelemetryBoard;

#endif // VIBE_CONTROL_BOARD_H
