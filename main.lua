local ffi = require("ffi")
local DebugProxy = require("debug_proxy")

-- ========================================================
-- 1. CROSS-PLATFORM SLEEP
-- ========================================================
if ffi.os == "Windows" then
    ffi.cdef[[ void Sleep(uint32_t ms); ]]
else
    ffi.cdef[[ int usleep(uint32_t usec); ]]
end

local function os_sleep(ms)
    if ffi.os == "Windows" then
        ffi.C.Sleep(ms)
    else
        ffi.C.usleep(ms * 1000)
    end
end

-- ========================================================
-- 2. THE GENERALIZED FFI SCHEMA
-- ========================================================
ffi.cdef[[
    // --- Data Stream Primitives ---
    typedef struct { uint32_t vertexCount; uint32_t instanceCount; uint32_t firstVertex; uint32_t firstInstance; } VkDrawIndirectCommand;
    typedef struct { float x, y, z, w; } VertexAoS;

    // --- VRAM Injection Payload ---
    typedef struct {
        uint32_t max_particles;
        float *px_A, *py_A, *pz_A, *vx_A, *vy_A, *vz_A, *seed_A, *mat_A;
        float *px_B, *py_B, *pz_B, *vx_B, *vy_B, *vz_B, *seed_B, *mat_B;
        VertexAoS *render_A, *render_B;
        uint32_t *grid_A, *grid_B;
        VkDrawIndirectCommand *draw_cmd_A, *draw_cmd_B;
    } VramInjectionBoard;

    // --- Asynchronous Control Structures ---
    typedef struct { uint32_t sequence; float matrix[16]; } AsyncCameraMatrix;
    typedef struct { int is_running; int force_draw_buffer; int debug_frame_step; } CoreStateBoard;
    typedef struct { uint32_t total_active_count; uint32_t cpu_core_offset; uint32_t cpu_core_count; uint32_t gpu_hunters_offset; uint32_t gpu_hunters_count; uint32_t gpu_boids_offset; uint32_t gpu_boids_count; uint32_t gpu_meteors_offset; uint32_t gpu_meteors_count; } AtlasBoard;
    typedef struct { int swarm_state; float params[16]; } SimulationBoard;
    typedef struct { uint32_t mouse_buttons; float mouse_x; float mouse_y; uint32_t key_states; } InputBoard;

    typedef struct {
        CoreStateBoard  core;
        AtlasBoard      atlas;
        SimulationBoard sim;
        InputBoard      input;
        AsyncCameraMatrix camera;
    } EngineControlBoard;

    // --- Telemetry ---
    typedef struct { uint64_t ptr_address; size_t size_bytes; int alignment; char name[32]; } BufferTelemetry;
    typedef struct { uint64_t bridge_crossings; int current_c_phase; BufferTelemetry buffers[14]; } EngineTelemetryBoard;
]]

-- ========================================================
-- 3. PARAMETER MAPPING
-- ========================================================
local Params = {
    GRAVITY_BLEND = 0,
    METAL_BLEND   = 1,
    PARADOX_BLEND = 2,
    QUANTUM_JITTER = 6
}

-- ========================================================
-- 4. HARDWARE BINDING
-- ========================================================
print("\n[LUA VM] Thread 5 Awoken. Binding hardware...")

local t_str, c_str = C_Bridge.get_boards()
local telemetry_ptr = ffi.cast("EngineTelemetryBoard*", tonumber(t_str))
local control_ptr   = ffi.cast("EngineControlBoard*", tonumber(c_str))

pcall(function() DebugProxy.BindHardware(telemetry_ptr, control_ptr) end)

-- ========================================================
-- 4.5 THE INJECTION PATCH (The "Heist" Signal)
-- ========================================================
local function ptr2str(ptr)
    if ptr == nil then return "0" end
    local cdata_num = ffi.cast("uint64_t", ffi.cast("uintptr_t", ptr))
    return string.match(tostring(cdata_num), "%d+")
end

print("[LUA VM] Preparing VRAM Injection Payload...")

local Anchors = {}
local function sim_rebar_float(n) 
    local mem = ffi.new("float[?]", n)
    table.insert(Anchors, mem)
    return ffi.cast("float*", mem) 
end

-- FIX: Allocate as a 1-element array to get a pointer
local payload_ptr = ffi.new("VramInjectionBoard[1]")
local payload = payload_ptr[0] -- Reference to the struct data
payload.max_particles = 15000000
local count = payload.max_particles

-- [PHASE A]
payload.px_A, payload.py_A, payload.pz_A = sim_rebar_float(count), sim_rebar_float(count), sim_rebar_float(count)
payload.vx_A, payload.vy_A, payload.vz_A = sim_rebar_float(count), sim_rebar_float(count), sim_rebar_float(count)
payload.seed_A, payload.mat_A = sim_rebar_float(count), sim_rebar_float(count)

-- [PHASE B]
payload.px_B, payload.py_B, payload.pz_B = sim_rebar_float(count), sim_rebar_float(count), sim_rebar_float(count)
payload.vx_B, payload.vy_B, payload.vz_B = sim_rebar_float(count), sim_rebar_float(count), sim_rebar_float(count)
payload.seed_B, payload.mat_B = sim_rebar_float(count), sim_rebar_float(count)

-- [RENDER & TOPOLOGY]
payload.render_A = ffi.new("VertexAoS[?]", count); table.insert(Anchors, payload.render_A)
payload.render_B = ffi.new("VertexAoS[?]", count); table.insert(Anchors, payload.render_B)
payload.grid_A   = ffi.new("uint32_t[?]", 2097152); table.insert(Anchors, payload.grid_A)
payload.grid_B   = ffi.new("uint32_t[?]", 2097152); table.insert(Anchors, payload.grid_B)
payload.draw_cmd_A = ffi.new("VkDrawIndirectCommand"); table.insert(Anchors, payload.draw_cmd_A)
payload.draw_cmd_B = ffi.new("VkDrawIndirectCommand"); table.insert(Anchors, payload.draw_cmd_B)

-- THE HEIST: Pass the pointer-array (payload_ptr) to ptr2str
C_Bridge.inject_vram(ptr2str(payload_ptr))

print("[LUA VM] Injection successful. C-Core Awakened.")
-- ========================================================
-- 5. THE CO-OVERLORD LOOP
-- ========================================================
print("[LUA VM] Entering IPC Horizon.")
local ticks = 0

while control_ptr.core.is_running == 1 do
    -- Modulate the sandbox
    control_ptr.sim.params[Params.QUANTUM_JITTER] = math.sin(ticks * 0.01)

    -- Telemetry Heartbeat
    if ticks % 60 == 0 then
        DebugProxy.PrintConsole()
    end

    ticks = ticks + 1
    os_sleep(16)
end

print("\n[LUA VM] Engine shutdown detected. Exiting gracefully...")
