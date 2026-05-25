return {
    -- System IPC
    sys = { idle = 0, boot = 1, kill = 2 },

    -- Engine Settings & Limits
    cfg = {
        use_validation = 0,       -- 1 = On, 0 = Off (Zero Overhead)
        vk_api_version = 4206592, -- VK_MAKE_API_VERSION(0, 1, 3, 0)
        ring_slots   = 4,
        pcount       = 1000000,
        grid_cells   = 262144,
        swarm_states = 7,
        max_draw     = 1024,
        max_comp     = 16,
        swap_slots   = 10,
        frame_slots  = 10,
    },

    -- Windowing
    win = { w = 1280, h = 720, min_w = 640, min_h = 360 },

    -- Input & Bindings
    move  = { fwd = 1, back = 2, left = 4, right = 8, up = 16, down = 32 },
    mouse = { left = 0, right = 1 },
    key   = { space = 32, num1 = 49, num2 = 50, num3 = 51, esc = 256, f11 = 290, f5 = 294 },

    -- Pipeline Modes
    mode = {
        dual = 0,
        geom = 1,
        points = 2,
        point_cloud_pass = 88
    },

    -- Vulkan Primitives (Explicitly isolated)
    vk_state = {
        cull_none  = 0, front_ccw = 0,
        topo_point = 0, topo_tri  = 3,
        cmp_le     = 4,
        depth_off  = 0, depth_on  = 1,
    },

    vk_stage = {
        top        = 1,
        early_frag = 2,
        vert       = 4,
        frag       = 8,
        vert_frag  = 12,
        -- color_out  = 16,
        color_out  = 1024,
        comp       = 2048
    },

    vk_access = {
        vert_read        = 4,
        shader_read      = 32,
        vert_shader_read = 36,
        shader_write     = 64,
        shader_rw        = 96,
        color_write      = 256
    },

    -- Vulkan Memory Properties (VkMemoryPropertyFlagBits)
    vk_mem = {
        device_local  = 1,
        host_visible  = 2,
        host_coherent = 4,
        host_cached   = 8,
    },

    -- Vulkan Shader Stages (VkShaderStageFlagBits)
    vk_shader_stage = {
        vert = 1,
        frag = 16,
        comp = 32,
    },

    -- Vulkan Descriptor Types (VkDescriptorType)
    vk_desc = {
        ssbo = 7, -- VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
    },

    -- Vulkan Structure Types (VkStructureType)
    vk_struct = {
        app_info                     = 0,
        instance_create              = 1,
        device_queue_create          = 2,
        device_create                = 3,
        mem_alloc                    = 5,
        buffer_create                = 12,
        shader_module_create         = 16,
        pipeline_shader_stage_create = 18,
        compute_pipeline_create      = 29,
        pipeline_layout_create       = 30,
        desc_set_layout_create       = 32,
        desc_pool_create             = 33,
        desc_set_alloc               = 34,
        write_desc_set               = 35,
        dynamic_rendering_features       = 1000044003,
        extended_dynamic_state_features  = 1000267000,
        extended_dynamic_state2_features = 1000377000,
        swapchain_create                   = 1000001000,
        image_view_create                  = 15,
        image_create                       = 14,
        pipeline_vertex_input_state_create = 19,
        pipeline_input_assembly_state_create = 20,
        pipeline_viewport_state_create     = 22,
        pipeline_rasterization_state_create = 23,
        pipeline_multisample_state_create  = 24,
        pipeline_depth_stencil_state_create = 25,
        pipeline_color_blend_state_create  = 26,
        pipeline_dynamic_state_create      = 27,
        pipeline_rendering_create          = 1000044002,
        graphics_pipeline_create           = 28,
        semaphore_create                   = 9,
        fence_create                       = 8,
        command_buffer_begin               = 42,
        memory_barrier                     = 46,
        image_memory_barrier               = 45,
        rendering_attachment_info          = 1000044001,
        rendering_info                     = 1000044000,
        submit_info                        = 4,
        present_info                       = 1000001001,
    },

    -- Vulkan Queue Bitmasks (VkQueueFlagBits)
    vk_queue = {
        graphics = 1,
        compute  = 2,
        transfer = 4,
    },

    -- Vulkan Results (VkResult)
    vk_result = {
        success           = 0,
        error_out_of_date = -1000000001,
    },

    -- Vulkan Formats (VkFormat)
    vk_format = {
        b8g8r8a8_srgb = 50,
        d32_sfloat    = 126,
    },

    -- Vulkan Image & View Configuration
    vk_image = {
        view_type_2d             = 1,
        type_2d                  = 1,
        tiling_optimal           = 0,
        usage_color_attachment   = 16,
        usage_depth_attachment   = 32,
        aspect_color             = 1,
        aspect_depth             = 2,
        sample_count_1           = 1,
    },

    -- Vulkan Image Layouts (VkImageLayout)
    vk_layout = {
        undefined                = 0,
        color_attachment_optimal = 2,
        depth_attachment_optimal = 3,
        present_src              = 1000001002,
    },

    -- Swapchain specific
    vk_swapchain = {
        color_space_srgb_nonlinear = 0,
        composite_alpha_opaque     = 1,
        present_mode_fifo          = 2,
    },

    -- Render Pass Attachment Operations
    vk_attachment = {
        load_clear  = 1,
        store_store = 0,
        store_dont_care = 1,
    },

    -- Pipeline Rasterization & Blending
    vk_pipeline = {
        poly_mode_fill = 0,
        cull_back      = 1,
        face_ccw       = 0,
        blend_src_alpha = 6,
        blend_one       = 1,
        color_mask_rgba = 15,
    },

    -- Pipeline Dynamic States (VkDynamicState)
    vk_dynamic = {
        viewport             = 0,
        scissor              = 1,
        cull_mode_ext        = 1000267000,
        front_face_ext       = 1000267001,
        primitive_topo_ext   = 1000267002,
        depth_test_ext       = 1000267006,
        depth_write_ext      = 1000267007,
        depth_compare_op_ext = 1000267008,
    },

    c_math_structs = [[
    typedef struct { float m[16]; } mat4_t;

    typedef struct {
        mat4_t viewProj;
        uint32_t soa_upload_idx;
        uint32_t aos_current_idx;
        uint32_t aos_prev_idx;
        uint32_t particle_count;
        float dt;
        float total_time;
        float spread;
        float highlight_power;
        uint32_t algae_color;
        uint32_t water_color;
        uint32_t bg_color_a;
        uint32_t bg_color_b;
        uint32_t target_state;
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

        uint8_t _padding[32];
    } RenderPacket;
    ]],

    c_vk_structs = [[
    typedef struct {
        VkDevice device;
        VkQueue queue;
        VkSwapchainKHR swapchain;
        uint64_t swapchain_images[10];
        uint64_t swapchain_views[10];
        VkSemaphore image_available[10];
        VkSemaphore render_finished[10];
        VkFence in_flight[10];
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
    } RenderThreadInit;
    ]]
}
