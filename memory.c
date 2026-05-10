#include "memory.h"
#include "control_board.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Global Control & Telemetry Instances
EngineControlBoard g_ControlBoard = {0};
EngineTelemetryBoard g_TelemetryBoard = {0};
static VibeMemoryMap g_MemMap = {0};

// Internal Helper for Telemetry
static void _register_telemetry(int index, void* ptr, size_t size, int alignment, const char* name) {
    if (index < 0 || index >= 14) return;
    g_TelemetryBoard.buffers[index].ptr_address = (uint64_t)(uintptr_t)ptr;
    g_TelemetryBoard.buffers[index].size_bytes = size;
    g_TelemetryBoard.buffers[index].alignment = alignment;
    snprintf(g_TelemetryBoard.buffers[index].name, 32, "%s", name);
}

void vibe_mem_inject_vram(VramInjectionBoard* payload) {
    if (g_MemMap.is_initialized || !payload) return;

    g_MemMap.max_particles = payload->max_particles;

    // Map Phase A Physics
    g_MemMap.physics_A.px = payload->px_A;
    g_MemMap.physics_A.py = payload->py_A;
    g_MemMap.physics_A.pz = payload->pz_A;
    g_MemMap.physics_A.vx = payload->vx_A;
    g_MemMap.physics_A.vy = payload->vy_A;
    g_MemMap.physics_A.vz = payload->vz_A;
    g_MemMap.physics_A.seed = payload->seed_A;
    g_MemMap.physics_A.material_id = payload->mat_A;

    // Map Phase B Physics
    g_MemMap.physics_B.px = payload->px_B;
    g_MemMap.physics_B.py = payload->py_B;
    g_MemMap.physics_B.pz = payload->pz_B;
    g_MemMap.physics_B.vx = payload->vx_B;
    g_MemMap.physics_B.vy = payload->vy_B;
    g_MemMap.physics_B.vz = payload->vz_B;
    g_MemMap.physics_B.seed = payload->seed_B;
    g_MemMap.physics_B.material_id = payload->mat_B;

    // Map Render & Topo
    g_MemMap.render_A = payload->render_A;
    g_MemMap.render_B = payload->render_B;
    g_MemMap.grid_A = payload->grid_A;
    g_MemMap.grid_B = payload->grid_B;
    g_MemMap.draw_cmd_A = payload->draw_cmd_A;
    g_MemMap.draw_cmd_B = payload->draw_cmd_B;

    size_t float_array_size = g_MemMap.max_particles * sizeof(float);
    size_t render_size = g_MemMap.max_particles * sizeof(VertexAoS);
    size_t grid_size = VIBE_GRID_CELL_COUNT * sizeof(uint32_t);
    size_t draw_alloc_size = sizeof(VkDrawIndirectCommand) > 64 ? sizeof(VkDrawIndirectCommand) : 64;

    // Register with Telemetry Board so Lua can still spy on it
    _register_telemetry(0,  g_MemMap.render_A,      render_size,      64, "RenderAoS_A");
    _register_telemetry(1,  g_MemMap.render_B,      render_size,      64, "RenderAoS_B");
    _register_telemetry(2,  g_MemMap.physics_A.px,  float_array_size, 64, "PhysicsPX_A");
    _register_telemetry(3,  g_MemMap.physics_B.px,  float_array_size, 64, "PhysicsPX_B");
    _register_telemetry(4,  g_MemMap.physics_A.py,  float_array_size, 64, "PhysicsPY_A");
    _register_telemetry(5,  g_MemMap.physics_B.py,  float_array_size, 64, "PhysicsPY_B");
    _register_telemetry(6,  g_MemMap.physics_A.pz,  float_array_size, 64, "PhysicsPZ_A");
    _register_telemetry(7,  g_MemMap.physics_B.pz,  float_array_size, 64, "PhysicsPZ_B");
    _register_telemetry(8,  g_MemMap.physics_A.vx,  float_array_size, 64, "PhysicsVX_A");
    _register_telemetry(9,  g_MemMap.physics_B.vx,  float_array_size, 64, "PhysicsVX_B");
    _register_telemetry(10, g_MemMap.grid_A,        grid_size,        64, "TopoGrid_A");
    _register_telemetry(11, g_MemMap.grid_B,        grid_size,        64, "TopoGrid_B");
    _register_telemetry(12, g_MemMap.draw_cmd_A,    draw_alloc_size,  64, "DrawCmd_A");
    _register_telemetry(13, g_MemMap.draw_cmd_B,    draw_alloc_size,  64, "DrawCmd_B");

    g_TelemetryBoard.current_c_phase = 0;
    g_MemMap.is_initialized = 1;

    printf("[C-CORE] VRAM Injection Successful. AVX2 mapped to ReBAR.\n");
}

void vibe_mem_destroy(void) {
    if (!g_MemMap.is_initialized) return;

    // CRITICAL FIX: Vulkan (Lua) allocated these buffers. C must NOT free them.
    // We only clear the C-side references.
    memset(&g_MemMap, 0, sizeof(VibeMemoryMap));
}

VibeMemoryMap* vibe_mem_get_map(void) {
    return &g_MemMap;
}

void vibe_mem_ptr2str(void* ptr, char* out_buffer, size_t buffer_size) {
    if (out_buffer && buffer_size > 0) {
        snprintf(out_buffer, buffer_size, "%p", ptr);
    }
}

void vibe_get_boards(void** out_telemetry, void** out_control) {
    if (out_telemetry) *out_telemetry = (void*)&g_TelemetryBoard;
    if (out_control)   *out_control   = (void*)&g_ControlBoard;
}

void vibe_audit_memory_state(void) {
    if (!g_MemMap.is_initialized) {
        printf("\n[C-AUDIT] Engine Memory is NOT injected yet.\n");
        return;
    }

    int phase = g_TelemetryBoard.current_c_phase;

    printf("\n=== VIBE ENGINE MEGALOMANIACAL TELEMETRY (C-AUDIT) ===\n");
    printf("C-Core Phase Target: [%c]\n", phase == 0 ? 'A' : 'B');
    printf("--------------------------------------------------\n");
    printf("%-4s %-15s %-20s %s\n", "", "BUFFER", "ADDRESS", "SIZE (MB)");
    printf("--------------------------------------------------\n");

    for (int i = 0; i < 14; i++) {
        BufferTelemetry* b = &g_TelemetryBoard.buffers[i];
        double size_mb = (double)b->size_bytes / (1024.0 * 1024.0);

        const char* active_marker = "    ";
        size_t len = strlen(b->name);
        if (len >= 2) {
            if (phase == 0 && b->name[len-1] == 'A' && b->name[len-2] == '_') active_marker = ">>> ";
            if (phase == 1 && b->name[len-1] == 'B' && b->name[len-2] == '_') active_marker = ">>> ";
        }

        printf("%s %-15s 0x%016llX %.2f\n",
               active_marker, b->name, (unsigned long long)b->ptr_address, size_mb);
    }
    printf("--------------------------------------------------\n\n");
}
