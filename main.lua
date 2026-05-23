local ffi = require("ffi")
local bit = require("bit")
local math = require("math")
local vmath = require("vmath")
local vulkan_core = require("vulkan_core")
local memory = require("memory")
local swapchain_core = require("swapchain")
local descriptors = require("descriptors")
local compute = require("compute_pipeline")
local graphics = require("graphics_pipeline")
local renderer = require("renderer")
local os = require("os")
local PCOUNT = 1000000
-- HIGH-RESOLUTION KERNEL TIMER
local get_time_hires

if jit.os == "Windows" then
    ffi.cdef[[
        int QueryPerformanceCounter(int64_t *lpPerformanceCount);
        int QueryPerformanceFrequency(int64_t *lpFrequency);
    ]]
    local kernel32 = ffi.load("kernel32")
    local freq = ffi.new("int64_t[1]")
    kernel32.QueryPerformanceFrequency(freq)
    local inv_freq = 1.0 / tonumber(freq[0])

    get_time_hires = function()
        local count = ffi.new("int64_t[1]")
        kernel32.QueryPerformanceCounter(count)
        return tonumber(count[0]) * inv_freq
    end
else
    ffi.cdef[[
        typedef struct { long tv_sec; long tv_nsec; } timespec;
        int clock_gettime(int clk_id, timespec *tp);
    ]]
    local CLOCK_MONOTONIC = 1
    get_time_hires = function()
        local ts = ffi.new("timespec")
        ffi.C.clock_gettime(CLOCK_MONOTONIC, ts)
        return tonumber(ts.tv_sec) + (tonumber(ts.tv_nsec) * 1e-9)
    end
end

ffi.cdef[[
    // Core Engine Control
    int vx_core_is_running();
    void vx_core_shutdown();
    void vx_core_mark_finished();

    // GLFW Bridge
    const char** vx_sys_glfw_extensions(uint32_t* count);
    void vx_sys_publish_instance(void* instance);
    void* vx_sys_get_surface();
    void vx_sys_set_cmd(int cmd, int w, int h);
    int vx_input_last_key();
    uint32_t vx_input_wasd();
    float vx_input_mouse_dx();
    float vx_input_mouse_dy();
    int vx_sys_resize_flag();
    void vx_sys_window_size(int* w, int* h);

    // Math & Types
    typedef struct { float m[16]; } mat4_t;

    // Structs
    typedef struct {
        mat4_t viewProj;
        uint32_t pos_x_idx;
        uint32_t pos_y_idx;
        uint32_t pos_z_idx;
        uint32_t particle_count;
        float dt;
        uint32_t vel_x_idx;
        uint32_t vel_y_idx;
        uint32_t vel_z_idx;
        uint32_t target_state;
        uint32_t push_active;
        uint32_t pull_active;
        float mouse_x;
        float mouse_y;
        // THE FUSE: Padding replaced with Index Offsets (12 bytes)
        uint32_t sorted_idx;
        uint32_t cell_counters_idx;
        uint32_t cell_offsets_idx;
    } PushConstants;

    typedef struct {
        uint32_t target_state;
        uint32_t push_active;
        uint32_t pull_active;
        float mouse_x;
        float mouse_y;
        uint32_t _padding[3];
    } SwarmCommand;

    typedef struct {
        uint64_t pipeline_id;
        uint64_t descriptor_set;
        uint32_t index_count;
        uint32_t instance_count;
        uint32_t first_index;
        int32_t vertex_offset;
        uint32_t first_instance;
        uint16_t pc_offset;
        uint16_t pc_size;
        uint8_t push_constants[128];

        int16_t scissor_x;
        int16_t scissor_y;
        uint16_t scissor_w;
        uint16_t scissor_h;
        uint8_t cull_mode;
        uint8_t depth_test;
        uint8_t depth_write;
        uint8_t depth_compare_op;
        uint8_t front_face;
        uint8_t topology;
        uint8_t _reserved[10];
    } DrawCommand;

    typedef struct {
        uint64_t pipeline_id;
        uint64_t layout_id;
        uint64_t descriptor_set;
        uint32_t group_x;
        uint32_t group_y;
        uint32_t group_z;
        uint16_t pc_offset;
        uint16_t pc_size;
        uint32_t barrier_src_stage;
        uint32_t barrier_dst_stage;
        uint32_t barrier_src_access;
        uint32_t barrier_dst_access;
        uint8_t push_constants[128];
        uint8_t _padding[8];
    } ComputeCommand;

    typedef struct __attribute__((packed, aligned(64))) {
        ComputeCommand* comp_queue;
        uint32_t comp_count;
        uint32_t _pad_comp;
        DrawCommand* draw_queue;
        uint32_t draw_count;
        uint32_t _pad_draw;
        uint64_t gfx_layout;
        uint64_t vertex_buffer;
        uint64_t index_buffer;
        uint64_t swapchain_image;
        uint64_t swapchain_view;
        uint64_t depth_image;
        uint64_t depth_view;
        uint32_t width;
        uint32_t height;
        uint8_t _padding[32]; // Perfect 128-byte alignment
    } RenderPacket;

    typedef struct {
        void* device;
        void* queue;
        void* swapchain;
        uint64_t swapchain_images[10];
        uint64_t swapchain_views[10];
        void* image_available[3];
        void* render_finished[10];
        void* in_flight[3];
        void* vkWaitForFences;
        void* vkAcquireNextImageKHR;
        void* vkResetFences;
        void* vkQueueSubmit;
        void* vkQueuePresentKHR;
        void* pfnBegin;
        void* pfnEnd;
        void* pfnSetCullMode;
        void* pfnSetFrontFace;
        void* pfnSetPrimitiveTopology;
        void* pfnSetDepthTestEnable;
        void* pfnSetDepthWriteEnable;
        void* pfnSetDepthCompareOp;
        uint64_t _padding[4];
    } RenderThreadInit;

    // Subsystem Interfaces
    void vmath_init_workers(int num_threads);
    void vmath_destroy_workers();
    void vmath_dispatch_swarm(int count, float* px, float* py, float* pz, float* vx, float* vy, float* vz, float* seed, const SwarmCommand* cmd, float time, float dt, float gravity, float blend_metal, float blend_paradox);

    void vx_math_stream_pos(int count, float* c_px, float* c_py, float* c_pz, float* g_px, float* g_py, float* g_pz);
    int vx_stream_acquire();
    RenderPacket* vx_stream_packet(int idx);
    void vx_stream_commit(int idx);
    void vx_stream_init(RenderThreadInit* wsi);
    void vx_thread_start();
    void vx_thread_kill();
    int vx_input_mouse_btn(int btn);
    int vx_input_spacebar();

    void Sleep(uint32_t dwMilliseconds);
    int usleep(uint32_t usec);
]]

local function sys_sleep(ms)
    if jit.os == "Windows" then
        ffi.C.Sleep(ms)
    else
        ffi.C.usleep(ms * 1000)
    end
end

local vmath_lib = ffi.load(jit.os == "Windows" and "vx_math.dll" or "./libvx_math.so")

local function main()
    print("[LUA IO] Booting Headless...")
    local vk_state = vulkan_core.create_instance()
    ffi.C.vx_sys_publish_instance(vk_state.instance)

    print("[LUA IO] Ordering C-Core to Boot GLFW Window...")
    ffi.C.vx_sys_set_cmd(1, 1280, 720)

    while ffi.C.vx_sys_get_surface() == nil do
        -- Waiting for async C core window creation
        sys_sleep(10)
    end

    local surface_ptr = ffi.C.vx_sys_get_surface()
    vulkan_core.finalize_device_and_swapchain(vk_state, surface_ptr)

    local vk = vk_state.vk
    local device = vk_state.device

    local usage_flags = bit.bor(32, 128, 256)
    local INDEX_SIZE = 12000000 * 4
    local idx_usage = bit.bor(64, 256)
    memory.CreateHostVisibleBuffer("MASTER_INDEX_BLOCK", "uint32_t", INDEX_SIZE / 4, idx_usage, vk_state)

    local requested_count = PCOUNT
    local padded_capacity = math.ceil(requested_count / 8) * 8
    memory.AllocateSoA("float", padded_capacity, {"px", "py", "pz", "vx", "vy", "vz", "seed"})

    local cpu_soa = {
        px = memory.AVX_Arrays["px"],
        py = memory.AVX_Arrays["py"],
        pz = memory.AVX_Arrays["pz"],
        vx = memory.AVX_Arrays["vx"],
        vy = memory.AVX_Arrays["vy"],
        vz = memory.AVX_Arrays["vz"],
        seed = memory.AVX_Arrays["seed"]
    }

    -- PHASE V: VRAM MEGA-BUFFER EXPANSION (Spatial Grid)
    local NUM_CELLS = 262144 -- 64x64x64 Grid

    local FRAME_FLOAT_COUNT = padded_capacity * 3
    local FRAME_UINT_COUNT = padded_capacity        -- Sorted Indices
    local FRAME_CELL_COUNT = NUM_CELLS * 2          -- Counters + Offsets

    local FRAME_TOTAL_WORDS = FRAME_FLOAT_COUNT + FRAME_UINT_COUNT + FRAME_CELL_COUNT

    -- Pad to 64-byte cache lines (16 words per cache line)
    local ALIGN_WORDS = 16
    FRAME_TOTAL_WORDS = math.ceil(FRAME_TOTAL_WORDS / ALIGN_WORDS) * ALIGN_WORDS

    local TOTAL_WORDS = FRAME_TOTAL_WORDS * 4       -- 4 Ring Slots
    local UNIVERSE_SIZE_BYTES = TOTAL_WORDS * 4     -- 4 Bytes per word

    local gpu_usage_flags = bit.bor(32, 128, 256)   -- STORAGE_BUFFER
    memory.CreateHostVisibleBuffer("MASTER_GPU_BLOCK", "uint8_t", UNIVERSE_SIZE_BYTES, gpu_usage_flags, vk_state)
    local master_ptr = ffi.cast("float*", memory.Mapped["MASTER_GPU_BLOCK"])

    for p = 0, requested_count - 1 do
        cpu_soa.seed[p] = math.random()
        cpu_soa.px[p] = (math.random() - 0.5) * 20000.0
        cpu_soa.py[p] = (math.random() - 0.5) * 10000.0 + 5000.0
        cpu_soa.pz[p] = (math.random() - 0.5) * 20000.0
        cpu_soa.vx[p] = 0.0
        cpu_soa.vy[p] = 0.0
        cpu_soa.vz[p] = 0.0
    end

    vmath_lib.vmath_init_workers(8)

    local pWidth = ffi.new("int[1]")
    local pHeight = ffi.new("int[1]")
    ffi.C.vx_sys_window_size(pWidth, pHeight)

    local sc_state = swapchain_core.Init(vk, vk_state, pWidth[0], pHeight[0])
    local desc_state = descriptors.Init(vk, device, memory.Buffers["MASTER_GPU_BLOCK"])
    local comp_state = compute.Init(vk, device, desc_state.pipelineLayout)
    local gfx_state = graphics.Init(vk, vk_state, pWidth[0], pHeight[0], desc_state.pipelineLayout, sc_state.format)
    local sync_state = renderer.InitSync(vk, device, 3)
    local frame_state = renderer.AllocateFrameState(vk, device, sc_state.extent.width, sc_state.extent.height)

    local wsi = ffi.new("RenderThreadInit")
    wsi.device = device
    wsi.queue = vk_state.queue
    wsi.swapchain = sc_state.handle
    for i=0, sc_state.imageCount-1 do
        wsi.swapchain_images[i] = ffi.cast("uint64_t", sc_state.images[i])
        wsi.swapchain_views[i] = ffi.cast("uint64_t", sc_state.imageViews[i])
        wsi.render_finished[i] = sync_state.renderFinished[i]
    end
    for i=0, 2 do
        wsi.image_available[i] = sync_state.imageAvailable[i]
        wsi.in_flight[i] = sync_state.inFlight[i]
    end
    wsi.vkWaitForFences = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkWaitForFences"))
    wsi.vkAcquireNextImageKHR = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkAcquireNextImageKHR"))
    wsi.vkResetFences = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkResetFences"))
    wsi.vkQueueSubmit = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkQueueSubmit"))
    wsi.vkQueuePresentKHR = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkQueuePresentKHR"))
    wsi.pfnBegin = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkCmdBeginRenderingKHR"))
    wsi.pfnEnd = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkCmdEndRenderingKHR"))

    wsi.pfnSetCullMode = vk.vkGetDeviceProcAddr(device, "vkCmdSetCullModeEXT")
    wsi.pfnSetFrontFace = vk.vkGetDeviceProcAddr(device, "vkCmdSetFrontFaceEXT")
    wsi.pfnSetPrimitiveTopology = vk.vkGetDeviceProcAddr(device, "vkCmdSetPrimitiveTopologyEXT")
    wsi.pfnSetDepthTestEnable = vk.vkGetDeviceProcAddr(device, "vkCmdSetDepthTestEnableEXT")
    wsi.pfnSetDepthWriteEnable = vk.vkGetDeviceProcAddr(device, "vkCmdSetDepthWriteEnableEXT")
    wsi.pfnSetDepthCompareOp = vk.vkGetDeviceProcAddr(device, "vkCmdSetDepthCompareOpEXT")

    ffi.C.vx_stream_init(wsi)
    ffi.C.vx_thread_start()

    -- HOT PATH OPTIMIZATIONS (Caching Locality)
    local master_gpu_block = memory.Buffers["MASTER_GPU_BLOCK"]
    local master_index_block = memory.Buffers["MASTER_INDEX_BLOCK"]

    local c_px, c_py, c_pz = cpu_soa.px, cpu_soa.py, cpu_soa.pz
    local c_vx, c_vy, c_vz = cpu_soa.vx, cpu_soa.vy, cpu_soa.vz
    local c_seed = cpu_soa.seed

    -- Global Queue Allocation (Triple Buffered)
    local MAX_DRAW_COMMANDS = 1024
    local render_queues = ffi.new("DrawCommand[?]", MAX_DRAW_COMMANDS * 4)

    local MAX_COMPUTE_COMMANDS = 16
    local compute_queues = ffi.new("ComputeCommand[?]", MAX_COMPUTE_COMMANDS * 4)

    local frame_count = 0
    local pc = ffi.new("PushConstants")
    pc.pos_x_idx = 0
    pc.pos_y_idx = -16000000
    pc.pos_z_idx = 2000000
    pc.particle_count = PCOUNT
    pc.dt = 0.0

    local proj = ffi.new("mat4_t")
    local view = ffi.new("mat4_t")
    local aspect = sc_state.extent.width / sc_state.extent.height
    vmath.perspective_inf_revz(70.0, aspect, 0.1, proj)

    local cam_pos = {x = 0.0, y = 0.0, z = -600.0}
    local cam_yaw = 0.0
    local cam_pitch = 0.0
    local sensitivity = 0.002
    local move_speed = 320000.0
    local is_resizing = false

    local last_time = get_time_hires()
    local last_resize_time = last_time
    local RESIZE_COOLDOWN = 0.25
    local current_swarm_state = 1
    local MAX_SWARM_STATES = 7
    local swarm_cmd = ffi.new("SwarmCommand")
    local space_was_pressed = false

    -- GEOMETRY COMPILATION
    print("[LUA CO] Compiling Geometry...")
    local idx_ptr = ffi.cast("uint32_t*", memory.Mapped["MASTER_INDEX_BLOCK"])

    local indices = {
        -- SHAPE 0: ICE SHARD (24 indices. Uses vertices 0-5)
        0,2,3, 0,3,4, 0,4,5, 0,5,2, -- Top faces
        1,3,2, 1,4,3, 1,5,4, 1,2,5, -- Bottom faces

        -- SHAPE 1: CUBE (36 indices. Uses vertices 6-13)
        6,7,8, 6,8,9,       -- Front
        7,11,12, 7,12,8,    -- Right
        11,10,13, 11,13,12, -- Back
        10,6,9, 10,9,13,    -- Left
        9,8,12, 9,12,13,    -- Top
        10,11,7, 10,7,6     -- Bottom
    }

    for i, idx in ipairs(indices) do
        idx_ptr[i - 1] = idx
    end

    -- Render Mode States
    local MODE_DUAL   = 0
    local MODE_GEOM   = 1
    local MODE_POINTS = 2
    local active_render_mode = MODE_DUAL

    print("[LUA CO] Entering Flattened Render Loop...")
    local pc_ptr_type = ffi.typeof("PushConstants*")
    -- FLATTENED RENDER LOOP (No Yielding)
    while ffi.C.vx_core_is_running() == 1 do
        if ffi.C.vx_sys_resize_flag() == 1 then
            is_resizing = true
            last_resize_time = get_time_hires()
        end

        if is_resizing then
            if (get_time_hires() - last_resize_time) > RESIZE_COOLDOWN then
                print("[LUA CO] Window Stable. Initiating Vulkan Rebuild...")
                ffi.C.vx_thread_kill()
                vk.vkDeviceWaitIdle(device)

                local new_w = ffi.new("int[1]")
                local new_h = ffi.new("int[1]")
                ffi.C.vx_sys_window_size(new_w, new_h)

                if new_w[0] > 0 and new_h[0] > 0 then
                    local new_sc_state = swapchain_core.Init(vk, vk_state, new_w[0], new_h[0])

                    -- THE FIX: Only proceed if the swapchain actually built
                    if new_sc_state ~= nil then
                        graphics.Destroy(vk, vk_state, gfx_state)
                        swapchain_core.Destroy(vk, vk_state, sc_state)
                        renderer.Destroy(vk, device, sync_state, 3)

                        sc_state = new_sc_state
                        gfx_state = graphics.Init(vk, vk_state, new_w[0], new_h[0], desc_state.pipelineLayout, sc_state.format)

                        local fresh_sync = renderer.InitSync(vk, device, 3)
                        -- ... [Rest of the rebuild logic] ...
                        sync_state.imageAvailable = fresh_sync.imageAvailable
                        sync_state.renderFinished = fresh_sync.renderFinished
                        sync_state.inFlight = fresh_sync.inFlight

                        frame_state.viewport[0].width = new_w[0]
                        frame_state.viewport[0].height = new_h[0]
                        frame_state.scissor[0].extent.width = new_w[0]
                        frame_state.scissor[0].extent.height = new_h[0]
                        frame_state.renderInfo[0].renderArea.extent.width = new_w[0]
                        frame_state.renderInfo[0].renderArea.extent.height = new_h[0]

                        local safe_h = math.max(1, new_h[0])
                        aspect = new_w[0] / safe_h
                        vmath.perspective_inf_revz(70.0, aspect, 0.1, proj)

                        local new_wsi = ffi.new("RenderThreadInit")
                        new_wsi.device = device
                        new_wsi.queue = vk_state.queue
                        new_wsi.swapchain = sc_state.handle
                        for i=0, sc_state.imageCount-1 do
                            new_wsi.swapchain_images[i] = ffi.cast("uint64_t", sc_state.images[i])
                            new_wsi.swapchain_views[i] = ffi.cast("uint64_t", sc_state.imageViews[i])
                            new_wsi.render_finished[i] = sync_state.renderFinished[i]
                        end
                        for i=0, 2 do
                            new_wsi.image_available[i] = sync_state.imageAvailable[i]
                            new_wsi.in_flight[i] = sync_state.inFlight[i]
                        end
                        new_wsi.vkWaitForFences = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkWaitForFences"))
                        new_wsi.vkAcquireNextImageKHR = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkAcquireNextImageKHR"))
                        new_wsi.vkResetFences = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkResetFences"))
                        new_wsi.vkQueueSubmit = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkQueueSubmit"))
                        new_wsi.vkQueuePresentKHR = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkQueuePresentKHR"))
                        new_wsi.pfnBegin = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkCmdBeginRenderingKHR"))
                        new_wsi.pfnEnd = ffi.cast("void*", vk.vkGetDeviceProcAddr(device, "vkCmdEndRenderingKHR"))

                        new_wsi.pfnSetCullMode = vk.vkGetDeviceProcAddr(device, "vkCmdSetCullModeEXT")
                        new_wsi.pfnSetFrontFace = vk.vkGetDeviceProcAddr(device, "vkCmdSetFrontFaceEXT")
                        new_wsi.pfnSetPrimitiveTopology = vk.vkGetDeviceProcAddr(device, "vkCmdSetPrimitiveTopologyEXT")
                        new_wsi.pfnSetDepthTestEnable = vk.vkGetDeviceProcAddr(device, "vkCmdSetDepthTestEnableEXT")
                        new_wsi.pfnSetDepthWriteEnable = vk.vkGetDeviceProcAddr(device, "vkCmdSetDepthWriteEnableEXT")
                        new_wsi.pfnSetDepthCompareOp = vk.vkGetDeviceProcAddr(device, "vkCmdSetDepthCompareOpEXT")

                        ffi.C.vx_stream_init(new_wsi)
                        ffi.C.vx_thread_start()
                    end
                end
                print("[LUA CO] Rebuild Complete.")
                is_resizing = false
                last_time = get_time_hires()
            end
        else
            local current_time = get_time_hires()
            local dt = math.max(0.001, math.min(current_time - last_time, 0.033))
            last_time = current_time

            local dx = ffi.C.vx_input_mouse_dx()
            local dy = ffi.C.vx_input_mouse_dy()
            local wasd = ffi.C.vx_input_wasd()

            cam_yaw = cam_yaw + (dx * sensitivity)
            cam_pitch = math.max(-1.5, math.min(1.5, cam_pitch + (dy * sensitivity)))

            local fwd_x = math.sin(cam_yaw) * math.cos(cam_pitch)
            local fwd_y = -math.sin(cam_pitch)
            local fwd_z = math.cos(cam_yaw) * math.cos(cam_pitch)
            local right_x = math.cos(cam_yaw)
            local right_z = -math.sin(cam_yaw)
            local frame_speed = move_speed * dt

            if bit.band(wasd, 1) ~= 0 then cam_pos.x = cam_pos.x + fwd_x * frame_speed; cam_pos.y = cam_pos.y + fwd_y * frame_speed; cam_pos.z = cam_pos.z + fwd_z * frame_speed end
            if bit.band(wasd, 2) ~= 0 then cam_pos.x = cam_pos.x - fwd_x * frame_speed; cam_pos.y = cam_pos.y - fwd_y * frame_speed; cam_pos.z = cam_pos.z - fwd_z * frame_speed end
            if bit.band(wasd, 4) ~= 0 then cam_pos.x = cam_pos.x - right_x * frame_speed; cam_pos.z = cam_pos.z - right_z * frame_speed end
            if bit.band(wasd, 8) ~= 0 then cam_pos.x = cam_pos.x + right_x * frame_speed; cam_pos.z = cam_pos.z + right_z * frame_speed end
            if bit.band(wasd, 16) ~= 0 then cam_pos.y = cam_pos.y + frame_speed end
            if bit.band(wasd, 32) ~= 0 then cam_pos.y = cam_pos.y - frame_speed end

            vmath.lookAt(cam_pos.x, cam_pos.y, cam_pos.z,
                         cam_pos.x + fwd_x, cam_pos.y + fwd_y, cam_pos.z + fwd_z,
                         view)
            pc.dt = pc.dt + dt
            vmath.multiply_mat4(proj, view, pc.viewProj)

            local space_is_down = (ffi.C.vx_input_spacebar() == 1)
            if space_is_down then
                if not space_was_pressed then
                    current_swarm_state = (current_swarm_state % MAX_SWARM_STATES) + 1
                    space_was_pressed = true
                end
            else
                space_was_pressed = false
            end

            -- The Input Router
            local last_key = ffi.C.vx_input_last_key()
            if last_key == 256 then -- ESCAPE
                print("[LUA IO] ESCAPE PRESSED. Executing Teardown...")
                ffi.C.vx_core_shutdown()
            elseif last_key == 294 then -- GLFW_KEY_F5
                wants_hotswap = true    -- THE FIX: Flag it, don't execute immediately
            elseif last_key == 49 then -- '1' Key
                active_render_mode = MODE_DUAL
                print("[LUA] Switched to Dual Pipeline")
            elseif last_key == 50 then -- '2' Key
                active_render_mode = MODE_GEOM
                print("[LUA] Switched to 100% Geometry")
            elseif last_key == 51 then -- '3' Key
                active_render_mode = MODE_POINTS
                print("[LUA] Switched to 100% Point Cloud")
            end

            swarm_cmd.target_state = current_swarm_state - 1
            swarm_cmd.push_active = ffi.C.vx_input_mouse_btn(0)
            swarm_cmd.pull_active = ffi.C.vx_input_mouse_btn(1)
            swarm_cmd.mouse_x = 0.0
            swarm_cmd.mouse_y = 5000.0

            vmath_lib.vmath_dispatch_swarm(
                pc.particle_count,
                c_px, c_py, c_pz,
                c_vx, c_vy, c_vz,
                c_seed,
                swarm_cmd,
                pc.dt, dt, 9.81, 1.0, 1.0
            )

            -- 1. Get the actual ring buffer index for the WSI synchronization
            local write_idx = ffi.C.vx_stream_acquire()


            if write_idx ~= -1 then
                -- 1. Advance the unified frame offset pointer
                local frame_offset = write_idx * FRAME_TOTAL_WORDS

                local gpu_px = master_ptr + frame_offset
                local gpu_py = master_ptr + (frame_offset + padded_capacity)
                local gpu_pz = master_ptr + (frame_offset + (padded_capacity * 2))

                vmath_lib.vx_math_stream_pos(
                    padded_capacity,
                    c_px, c_py, c_pz,
                    gpu_px, gpu_py, gpu_pz
                )

                -- 2. Configure Push Constant Offsets
                pc.pos_x_idx = frame_offset
                pc.pos_y_idx = frame_offset + padded_capacity
                pc.pos_z_idx = frame_offset + (padded_capacity * 2)

                -- We don't stream velocity to the GPU, so zero these out
                pc.vel_x_idx = 0
                pc.vel_y_idx = 0
                pc.vel_z_idx = 0

                -- PHASE V: Bind the Grid Sorting Data (Directly after pos_z)
                pc.sorted_idx = frame_offset + (padded_capacity * 3)
                pc.cell_counters_idx = pc.sorted_idx + padded_capacity
                pc.cell_offsets_idx = pc.cell_counters_idx + NUM_CELLS

                local packet = ffi.C.vx_stream_packet(write_idx)
                local current_queue_ptr = render_queues + (write_idx * MAX_DRAW_COMMANDS)
                local current_comp_queue = compute_queues + (write_idx * MAX_COMPUTE_COMMANDS)

                -- THE 4-PASS COMPUTE GRAPH (Zero Allocation)
                packet.comp_queue = current_comp_queue
                packet.comp_count = 4

                -- Common state for all passes
                for c = 0, 3 do
                    current_comp_queue[c].layout_id = ffi.cast("uint64_t", comp_state.pipelineLayout)
                    current_comp_queue[c].descriptor_set = ffi.cast("uint64_t", desc_state.set0)
                    current_comp_queue[c].group_y = 1
                    current_comp_queue[c].group_z = 1
                    current_comp_queue[c].pc_offset = 0
                    current_comp_queue[c].pc_size = 128
                    ffi.copy(current_comp_queue[c].push_constants, pc, 128)
                end

                -- PASS 0: Clear Counters
                local c0 = current_comp_queue[0]
                c0.pipeline_id = ffi.cast("uint64_t", comp_state.pipe_clear)
                c0.group_x = math.ceil(NUM_CELLS / 256)
                c0.barrier_src_stage = 2048 -- COMPUTE
                c0.barrier_dst_stage = 2048 -- Wait before Hashing
                c0.barrier_src_access = 64  -- WRITE
                c0.barrier_dst_access = 96  -- READ/WRITE

                -- PASS 1: Hash & Count
                local c1 = current_comp_queue[1]
                c1.pipeline_id = ffi.cast("uint64_t", comp_state.pipe_hash)
                c1.group_x = math.ceil(pc.particle_count / 256)
                c1.barrier_src_stage = 2048
                c1.barrier_dst_stage = 2048 -- Wait before Scan
                c1.barrier_src_access = 64
                c1.barrier_dst_access = 96

                -- PASS 2: Prefix Scan (Single Threaded Block)
                local c2 = current_comp_queue[2]
                c2.pipeline_id = ffi.cast("uint64_t", comp_state.pipe_scan)
                c2.group_x = 1
                c2.barrier_src_stage = 2048
                c2.barrier_dst_stage = 2048 -- Wait before Reorder
                c2.barrier_src_access = 64
                c2.barrier_dst_access = 96

                -- PASS 3: Reorder & Scatter
                local c3 = current_comp_queue[3]
                c3.pipeline_id = ffi.cast("uint64_t", comp_state.pipe_reorder)
                c3.group_x = math.ceil(pc.particle_count / 256)
                c3.barrier_src_stage = 2048
                c3.barrier_dst_stage = 12   -- VERTEX_SHADER
                c3.barrier_src_access = 64  -- WRITE
                c3.barrier_dst_access = 36  -- VERTEX_ATTRIBUTE_READ

                -- ========================================================
                -- GLOBAL GRAPHICS CONTEXT
                -- ========================================================
                packet.gfx_layout = ffi.cast("uint64_t", gfx_state.pipelineLayout)
                packet.vertex_buffer = ffi.cast("uint64_t", master_gpu_block)
                packet.index_buffer = ffi.cast("uint64_t", master_index_block)
                packet.depth_image = ffi.cast("uint64_t", gfx_state.depthImage)
                packet.depth_view = ffi.cast("uint64_t", gfx_state.depthImageView)
                packet.width = sc_state.extent.width
                packet.height = sc_state.extent.height

                -- 3. Configure the Graphics Graph
                local half_count = math.floor(pc.particle_count / 2)

                -- COMMAND 0: The Geometric Swarm (FULL PUSH)
                local cmd0 = current_queue_ptr[0]
                cmd0.pipeline_id = ffi.cast("uint64_t", gfx_state.pipeline_geom)
                cmd0.descriptor_set = ffi.cast("uint64_t", desc_state.set0)
                cmd0.index_count = 24
                cmd0.first_index = 0
                cmd0.vertex_offset = 0
                -- cmd0.instance_count = half_count
                cmd0.instance_count = pc.particle_count
                cmd0.first_instance = 0

                -- [NEW] Define push constant range for CMD 0
                cmd0.pc_offset = 0
                cmd0.pc_size = 128
                ffi.copy(cmd0.push_constants, pc, 128)

                cmd0.scissor_x = 0
                cmd0.scissor_y = 0
                cmd0.scissor_w = sc_state.extent.width
                cmd0.scissor_h = sc_state.extent.height
                cmd0.cull_mode = 1
                cmd0.front_face = 0
                cmd0.topology = 3 -- Matches pipeline_geom (VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
                cmd0.depth_test = 1
                cmd0.depth_write = 1
                cmd0.depth_compare_op = 4

                -- ==========================================
                -- COMMAND 1: The Point Cloud Nebula (PARTIAL PUSH)
                -- ==========================================
                local cmd1 = current_queue_ptr[1]
                cmd1.pipeline_id = ffi.cast("uint64_t", gfx_state.pipeline_points)
                cmd1.descriptor_set = ffi.cast("uint64_t", desc_state.set0)
                cmd1.index_count = 1        -- 1 vertex per point particle
                cmd1.first_index = 0        -- Just read index 0 (value doesn't matter since gl_VertexIndex is ignored)
                cmd1.vertex_offset = 0
                cmd1.instance_count = half_count
                cmd1.first_instance = half_count

                -- [NEW] Zero-Allocation Partial Push Constants
                -- Replaces the ffi.new() GC spike. We only configure the 4 bytes that matter.
                cmd1.pc_offset = 96
                cmd1.pc_size = 4

                local pc_points_ptr = ffi.cast(pc_ptr_type, cmd1.push_constants)
                pc_points_ptr.target_state = 99

                cmd1.scissor_x = 0
                cmd1.scissor_y = 0
                cmd1.scissor_w = sc_state.extent.width
                cmd1.scissor_h = sc_state.extent.height
                cmd1.cull_mode = 0
                cmd1.front_face = 0
                cmd1.topology = 0 -- Matches pipeline_points (VK_PRIMITIVE_TOPOLOGY_POINT_LIST)
                cmd1.depth_test = 1
                cmd1.depth_write = 1
                cmd1.depth_compare_op = 4

                if active_render_mode == MODE_DUAL then
                    cmd0.instance_count = half_count
                    cmd1.first_instance = half_count
                    cmd1.instance_count = half_count
                    packet.draw_queue = current_queue_ptr
                    packet.draw_count = 2
                elseif active_render_mode == MODE_GEOM then
                    cmd0.instance_count = pc.particle_count
                    packet.draw_queue = current_queue_ptr
                    packet.draw_count = 1
                elseif active_render_mode == MODE_POINTS then
                    cmd1.first_instance = 0
                    cmd1.instance_count = pc.particle_count
                    packet.draw_queue = current_queue_ptr + 1
                    packet.draw_count = 1
                end

                -- Execute the debounced hotswap right before submission
                if wants_hotswap then
                    print("[LUA] Initiating Lock-Free Shader Hotswap...")
                    graphics.HotReloadShaders(vk, vk_state, gfx_state, frame_count)
                    wants_hotswap = false
                end

                ffi.C.vx_stream_commit(write_idx)

                -- Pump the queue only on valid GPU frames
                graphics.PumpDeletionQueue(vk, vk_state, frame_count)
                frame_count = frame_count + 1
            end

            sys_sleep(10)
        end
    end

    print("[LUA CO] Render Loop Terminated. Frames: " .. tostring(frame_count))

    -- TEARDOWN
    print("[TEARDOWN] Terminating Async Render Thread...")
    ffi.C.vx_thread_kill()
    vk.vkDeviceWaitIdle(vk_state.device)
    vmath_lib.vmath_destroy_workers()

    renderer.Destroy(vk, device, sync_state, 3)
    graphics.Destroy(vk, vk_state, gfx_state)
    compute.Destroy(vk, vk_state, comp_state)
    descriptors.Destroy(vk, device, desc_state)
    swapchain_core.Destroy(vk, vk_state, sc_state)

    print("[TEARDOWN] Freeing VRAM Arenas...")
    memory.DestroyBuffer("MASTER_GPU_BLOCK", vk_state)
    if memory.Buffers["MASTER_INDEX_BLOCK"] then
        memory.DestroyBuffer("MASTER_INDEX_BLOCK", vk_state)
    end

    vulkan_core.Destroy(vk_state)
end

main()
ffi.C.vx_core_mark_finished()
