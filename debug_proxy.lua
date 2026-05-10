local ffi = require("ffi")

-- ========================================================
-- 1. THE FFI SCHEMA (Stripped of _Atomic for LuaJIT)
-- ========================================================
ffi.cdef[[
    // --- Asynchronous Data Structures ---
    typedef struct {
        uint32_t sequence;
        float matrix[16];
    } AsyncCameraMatrix;

    // --- Sub-System Boards ---
    typedef struct {
        int is_running;
        int force_draw_buffer;
        int debug_frame_step;
    } CoreStateBoard;

    typedef struct {
        uint32_t total_active_count;
        uint32_t cpu_core_offset;    uint32_t cpu_core_count;
        uint32_t gpu_hunters_offset; uint32_t gpu_hunters_count;
        uint32_t gpu_boids_offset;   uint32_t gpu_boids_count;
        uint32_t gpu_meteors_offset; uint32_t gpu_meteors_count;
    } AtlasBoard;

    typedef struct {
        int swarm_state;
        float params[16];
    } SimulationBoard;

    typedef struct {
        uint32_t mouse_buttons;
        float mouse_x;
        float mouse_y;
        uint32_t key_states;
    } InputBoard;

    // --- The Master Control Board ---
    typedef struct {
        CoreStateBoard  core;
        AtlasBoard      atlas;
        SimulationBoard sim;
        InputBoard      input;
        AsyncCameraMatrix camera;
    } EngineControlBoard;

    // --- Megalomaniacal Telemetry Layer ---
    typedef struct {
        uint64_t ptr_address;
        size_t size_bytes;
        int alignment;
        char name[32];
    } BufferTelemetry;

    typedef struct {
        uint64_t bridge_crossings;
        int current_c_phase;
        BufferTelemetry buffers[14];
    } EngineTelemetryBoard;
]]

-- ========================================================
-- 2. THE PROXY STATE
-- ========================================================
local DebugProxy = {
    IS_ACTIVE = true,
    show_ui = true,
    telemetry_ptr = nil,
    control_ptr = nil
}

-- ========================================================
-- 3. THE INFECTOR
-- ========================================================
function DebugProxy.Infect(module_name, target_module)
    if not DebugProxy.IS_ACTIVE then return target_module end

    local proxy = {}
    for key, value in pairs(target_module) do
        if type(value) == "function" then
            proxy[key] = function(...)
                if DebugProxy.telemetry_ptr then
                    DebugProxy.telemetry_ptr.bridge_crossings = DebugProxy.telemetry_ptr.bridge_crossings + 1
                end

                local start_time = os.clock()
                local results = { value(...) }
                local elapsed_ms = (os.clock() - start_time) * 1000

                if elapsed_ms > 1.0 then
                    print(string.format("[SPIKE] %s.%s took %.3f ms", module_name, key, elapsed_ms))
                end

                return unpack(results)
            end
        else
            proxy[key] = value
        end
    end
    return proxy
end

-- ========================================================
-- 4. HARDWARE BINDING
-- ========================================================
function DebugProxy.BindHardware(telemetry_cdata, control_cdata)
    DebugProxy.telemetry_ptr = ffi.cast("EngineTelemetryBoard*", telemetry_cdata)
    DebugProxy.control_ptr = ffi.cast("EngineControlBoard*", control_cdata)
    print("[TELEMETRY] Omniscient Proxy successfully bound to AVX2 Engine Core.")
end

-- ========================================================
-- 5. TIME MACHINE INPUT HOOKS (Now using .core routing)
-- ========================================================
function DebugProxy.KeyPressed(key)
    if not DebugProxy.IS_ACTIVE or not DebugProxy.control_ptr then return end

    if key == "f1" then
        DebugProxy.show_ui = not DebugProxy.show_ui
    elseif key == "p" then
        -- Updated to route through .core namespace
        local current = DebugProxy.control_ptr.core.debug_frame_step
        DebugProxy.control_ptr.core.debug_frame_step = (current == 0) and 1 or 0
        print("[TIME MACHINE] State: " .. (DebugProxy.control_ptr.core.debug_frame_step == 0 and "FREE RUN" or "PAUSED"))
    elseif key == "]" then
        -- Updated to route through .core namespace
        if DebugProxy.control_ptr.core.debug_frame_step == 1 then
            DebugProxy.control_ptr.core.debug_frame_step = 2
            print("[TIME MACHINE] Stepping One Frame...")
        end
    end
end

-- ========================================================
-- 6. TERMINAL VISUALIZER
-- ========================================================
function DebugProxy.PrintConsole()
    if not DebugProxy.IS_ACTIVE or not DebugProxy.show_ui or not DebugProxy.telemetry_ptr then return end

    local tb = DebugProxy.telemetry_ptr
    local cb = DebugProxy.control_ptr

    local phase_char = (tb.current_c_phase == 0) and "A" or "B"

    -- Updated to route through .core namespace
    local run_state = (cb.core.debug_frame_step == 0) and "FREE RUN" 
                   or (cb.core.debug_frame_step == 1 and "PAUSED" or "STEPPING")

    -- Clear screen (ANSI escape code)
    io.write("\27[2J\27[H")

    print("=== VIBE ENGINE MEGALOMANIACAL TELEMETRY ===")
    print(string.format("C-Core Phase Target: [%s]", phase_char))
    print(string.format("Time Machine State:  [%s]", run_state))
    print(string.format("FFI Bridge Crossings: %d", tonumber(tb.bridge_crossings)))

    tb.bridge_crossings = 0

    print("--------------------------------------------------")
    print(string.format("%-4s %-15s %-20s %s", "", "BUFFER", "ADDRESS", "SIZE (MB)"))
    print("--------------------------------------------------")

    for i = 0, 13 do
        local b = tb.buffers[i]
        local name = ffi.string(b.name)

        local active_marker = "    "
        if (tb.current_c_phase == 0 and name:sub(-2) == "_A") or
           (tb.current_c_phase == 1 and name:sub(-2) == "_B") then
            active_marker = ">>> " -- Danger: AVX2 is touching this!
        end

        local size_mb = tonumber(b.size_bytes) / (1024 * 1024)
        -- local addr_hex = string.format("0x%016llX", tonumber(b.ptr_address))
        -- REPLACE WITH THIS:
        local addr_hex = tostring(ffi.cast("void*", b.ptr_address))
        print(string.format("%s %-15s %-20s %.2f", active_marker, name, addr_hex, size_mb))
    end
    print("--------------------------------------------------")
    print("[F1] Hide  [P] Pause  []] Step Frame")
end

return DebugProxy
