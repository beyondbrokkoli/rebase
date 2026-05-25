return {
    -- System IPC
    sys = { idle = 0, boot = 1, kill = 2 },

    -- Engine Settings & Limits
    cfg = {
        use_validation = 1,       -- 1 = On, 0 = Off (Zero Overhead)
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
}
