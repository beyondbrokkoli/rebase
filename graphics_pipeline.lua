local ffi = require("ffi")
local bit = require("bit")
local reg = require("registry")
local vk_struct, vk_shader = reg.vk_struct, reg.vk_shader_stage
local vk_state, vk_pipeline, vk_dynamic = reg.vk_state, reg.vk_pipeline, reg.vk_dynamic
local vk_format, vk_image, vk_layout = reg.vk_format, reg.vk_image, reg.vk_layout

local GraphicsPipeline = {}

local DELETION_QUEUE_SIZE = 16
local deletion_queue = {}
for i = 0, DELETION_QUEUE_SIZE - 1 do
    deletion_queue[i] = {
        active = false, frame_target = 0,
        geom = nil, points = nil,
        vert = nil, frag = nil
    }
end
local d_head = 0
local d_tail = 0

function GraphicsPipeline.PumpDeletionQueue(vk, core_state, current_frame)
    local device = type(core_state) == "table" and core_state.device or core_state

    while d_tail ~= d_head do
        local item = deletion_queue[d_tail]
        if current_frame < item.frame_target then break end

        vk.vkDestroyPipeline(device, item.geom, nil)
        vk.vkDestroyPipeline(device, item.points, nil)
        if item.vert ~= nil then vk.vkDestroyShaderModule(device, item.vert, nil) end
        if item.frag ~= nil then vk.vkDestroyShaderModule(device, item.frag, nil) end

        item.active = false
        d_tail = (d_tail + 1) % DELETION_QUEUE_SIZE
    end
end

local function ReadShaderFile(filename)
    local file = io.open(filename, "rb")
    assert(file, "FATAL: Failed to open shader file: " .. filename)
    local content = file:read("*a")
    file:close()
    return content
end

local function createShaderModule(vk, device, code)
    local info = ffi.new("VkShaderModuleCreateInfo", {
        sType = vk_struct.shader_module_create, codeSize = string.len(code), pCode = ffi.cast("const uint32_t*", code)
    })
    local pMod = ffi.new("VkShaderModule[1]")
    assert(vk.vkCreateShaderModule(device, info, nil, pMod) == 0)
    return pMod[0]
end

local function BuildPipelines(vk, device, layout, colorFormat, vertModule, fragModule)
    local shaderStages = ffi.new("VkPipelineShaderStageCreateInfo[2]")
    shaderStages[0].sType = vk_struct.pipeline_shader_stage_create; shaderStages[0].stage = vk_shader.vert; shaderStages[0].module = vertModule; shaderStages[0].pName = "main"
    shaderStages[1].sType = vk_struct.pipeline_shader_stage_create; shaderStages[1].stage = vk_shader.frag; shaderStages[1].module = fragModule; shaderStages[1].pName = "main"

    local vertexInputInfo = ffi.new("VkPipelineVertexInputStateCreateInfo", { sType = vk_struct.pipeline_vertex_input_state_create })
    local inputAssembly = ffi.new("VkPipelineInputAssemblyStateCreateInfo", { sType = vk_struct.pipeline_input_assembly_state_create })
    local viewportState = ffi.new("VkPipelineViewportStateCreateInfo", { sType = vk_struct.pipeline_viewport_state_create, viewportCount = 1, scissorCount = 1 })

    local rasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo", {
        sType = vk_struct.pipeline_rasterization_state_create, polygonMode = vk_pipeline.poly_mode_fill, lineWidth = 1.0, cullMode = vk_pipeline.cull_back, frontFace = vk_pipeline.face_ccw
    })
    local multisampling = ffi.new("VkPipelineMultisampleStateCreateInfo", { sType = vk_struct.pipeline_multisample_state_create, rasterizationSamples = vk_image.sample_count_1 })
    local depthStencil = ffi.new("VkPipelineDepthStencilStateCreateInfo", {
        sType = vk_struct.pipeline_depth_stencil_state_create, depthTestEnable = vk_state.depth_on, depthWriteEnable = vk_state.depth_on, depthCompareOp = vk_state.cmp_le
    })

    local colorBlendAttachment = ffi.new("VkPipelineColorBlendAttachmentState[1]")
    colorBlendAttachment[0].colorWriteMask = vk_pipeline.color_mask_rgba
    colorBlendAttachment[0].srcColorBlendFactor = vk_pipeline.blend_src_alpha
    colorBlendAttachment[0].dstColorBlendFactor = vk_pipeline.blend_one
    colorBlendAttachment[0].srcAlphaBlendFactor = vk_pipeline.blend_one

    local colorBlending = ffi.new("VkPipelineColorBlendStateCreateInfo", {
        sType = vk_struct.pipeline_color_blend_state_create, attachmentCount = 1, pAttachments = colorBlendAttachment
    })

    local dynamicStates = ffi.new("VkDynamicState[8]", {
        vk_dynamic.viewport, vk_dynamic.scissor, vk_dynamic.cull_mode_ext,
        vk_dynamic.front_face_ext, vk_dynamic.primitive_topo_ext, vk_dynamic.depth_test_ext,
        vk_dynamic.depth_write_ext, vk_dynamic.depth_compare_op_ext
    })

    local dynamicStateInfo = ffi.new("VkPipelineDynamicStateCreateInfo", {
        sType = vk_struct.pipeline_dynamic_state_create, dynamicStateCount = 8, pDynamicStates = dynamicStates
    })

    local colorFormats = ffi.new("int32_t[1]", {colorFormat})
    local pipelineRenderingInfo = ffi.new("VkPipelineRenderingCreateInfo", {
        sType = vk_struct.pipeline_rendering_create, colorAttachmentCount = 1, pColorAttachmentFormats = colorFormats, depthAttachmentFormat = vk_format.d32_sfloat
    })

    local pipelineInfo = ffi.new("VkGraphicsPipelineCreateInfo[1]")
    pipelineInfo[0].sType = vk_struct.graphics_pipeline_create; pipelineInfo[0].pNext = pipelineRenderingInfo
    pipelineInfo[0].stageCount = 2; pipelineInfo[0].pVertexInputState = vertexInputInfo
    pipelineInfo[0].pInputAssemblyState = inputAssembly; pipelineInfo[0].pViewportState = viewportState
    pipelineInfo[0].pRasterizationState = rasterizer; pipelineInfo[0].pMultisampleState = multisampling
    pipelineInfo[0].pDepthStencilState = depthStencil; pipelineInfo[0].pColorBlendState = colorBlending
    pipelineInfo[0].pDynamicState = dynamicStateInfo; pipelineInfo[0].layout = layout
    pipelineInfo[0].pStages = shaderStages

    inputAssembly.topology = vk_state.topo_tri
    local pGeomPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pGeomPipeline) == 0)

    inputAssembly.topology = vk_state.topo_point
    local pointRasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo")
    ffi.copy(pointRasterizer, rasterizer, ffi.sizeof(rasterizer))
    pointRasterizer.cullMode = vk_state.cull_none
    pipelineInfo[0].pRasterizationState = pointRasterizer
    colorBlendAttachment[0].blendEnable = 1

    local pPointsPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pPointsPipeline) == 0)

    return pGeomPipeline[0], pPointsPipeline[0]
end

function GraphicsPipeline.Init(vk, core_state, width, height, pipelineLayout, colorFormat)
    print("[GRAPHICS] Building Reverse-Z Depth Buffer and Shader Modules...")
    local device = core_state.device

    local dImgInfo = ffi.new("VkImageCreateInfo")
    ffi.fill(dImgInfo, ffi.sizeof(dImgInfo))
    dImgInfo.sType = vk_struct.image_create
    dImgInfo.imageType = vk_image.type_2d
    dImgInfo.extent.width = width
    dImgInfo.extent.height = height
    dImgInfo.extent.depth = 1
    dImgInfo.mipLevels = 1
    dImgInfo.arrayLayers = 1
    dImgInfo.format = vk_format.d32_sfloat
    dImgInfo.tiling = vk_image.tiling_optimal
    dImgInfo.initialLayout = vk_layout.undefined
    dImgInfo.usage = vk_image.usage_depth_attachment
    dImgInfo.samples = vk_image.sample_count_1

    local pDepthImage = ffi.new("VkImage[1]")
    assert(vk.vkCreateImage(device, dImgInfo, nil, pDepthImage) == 0)

    local memReqs = ffi.new("VkMemoryRequirements")
    vk.vkGetImageMemoryRequirements(device, pDepthImage[0], memReqs)
    local memProperties = ffi.new("VkPhysicalDeviceMemoryProperties")
    vk.vkGetPhysicalDeviceMemoryProperties(core_state.physicalDevice, memProperties)
    local memoryTypeIndex = -1
    for i = 0, memProperties.memoryTypeCount - 1 do
        if bit.band(memReqs.memoryTypeBits, bit.lshift(1, i)) ~= 0 and bit.band(memProperties.memoryTypes[i].propertyFlags, 1) ~= 0 then
            memoryTypeIndex = i; break
        end
    end

    local dAllocInfo = ffi.new("VkMemoryAllocateInfo", { sType = vk_struct.mem_alloc, allocationSize = memReqs.size, memoryTypeIndex = memoryTypeIndex })
    local pDepthMemory = ffi.new("VkDeviceMemory[1]"); assert(vk.vkAllocateMemory(device, dAllocInfo, nil, pDepthMemory) == 0)
    assert(vk.vkBindImageMemory(device, pDepthImage[0], pDepthMemory[0], 0) == 0)

    local dViewInfo = ffi.new("VkImageViewCreateInfo", {
        sType = vk_struct.image_view_create, image = pDepthImage[0], viewType = vk_image.view_type_2d, format = vk_format.d32_sfloat,
        subresourceRange = { aspectMask = vk_image.aspect_depth, levelCount = 1, layerCount = 1 }
    })
    local pDepthView = ffi.new("VkImageView[1]"); assert(vk.vkCreateImageView(device, dViewInfo, nil, pDepthView) == 0)

    local unifiedVert = createShaderModule(vk, device, ReadShaderFile("render_vert.spv"))
    local unifiedFrag = createShaderModule(vk, device, ReadShaderFile("render_frag.spv"))
    local pipeGeom, pipePoints = BuildPipelines(vk, device, pipelineLayout, colorFormat, unifiedVert, unifiedFrag)

    return {
        depthImage = pDepthImage[0], depthMemory = pDepthMemory[0], depthImageView = pDepthView[0],
        vert = unifiedVert, frag = unifiedFrag, pipelineLayout = pipelineLayout,
        colorFormat = colorFormat, pipeline_geom = pipeGeom, pipeline_points = pipePoints
    }
end

function GraphicsPipeline.HotReloadShaders(vk, core_state, gfx_state, current_frame)
    local device = core_state.device
    local item = deletion_queue[d_head]
    item.active = true
    item.frame_target = current_frame + 4
    item.geom = gfx_state.pipeline_geom
    item.points = gfx_state.pipeline_points
    item.vert = gfx_state.vert
    item.frag = gfx_state.frag
    d_head = (d_head + 1) % DELETION_QUEUE_SIZE

    local new_vert = createShaderModule(vk, device, ReadShaderFile("render_vert.spv"))
    local new_frag = createShaderModule(vk, device, ReadShaderFile("render_frag.spv"))
    local new_geom, new_points = BuildPipelines(vk, device, gfx_state.pipelineLayout, gfx_state.colorFormat, new_vert, new_frag)

    gfx_state.pipeline_geom = new_geom
    gfx_state.pipeline_points = new_points
    gfx_state.vert = new_vert
    gfx_state.frag = new_frag
end

function GraphicsPipeline.Destroy(vk, core_state, gfx_state)
    print("[TEARDOWN] Destroying Dual Graphics Pipelines & Depth Buffer...")
    if not gfx_state then return end
    local device = type(core_state) == "table" and core_state.device or core_state

    while d_tail ~= d_head do
        local item = deletion_queue[d_tail]
        vk.vkDestroyPipeline(device, item.geom, nil)
        vk.vkDestroyPipeline(device, item.points, nil)
        if item.vert ~= nil then vk.vkDestroyShaderModule(device, item.vert, nil) end
        if item.frag ~= nil then vk.vkDestroyShaderModule(device, item.frag, nil) end
        d_tail = (d_tail + 1) % DELETION_QUEUE_SIZE
    end

    if gfx_state.pipeline_geom then vk.vkDestroyPipeline(device, gfx_state.pipeline_geom, nil) end
    if gfx_state.pipeline_points then vk.vkDestroyPipeline(device, gfx_state.pipeline_points, nil) end
    if gfx_state.vert then vk.vkDestroyShaderModule(device, gfx_state.vert, nil) end
    if gfx_state.frag then vk.vkDestroyShaderModule(device, gfx_state.frag, nil) end
    if gfx_state.depthImageView then vk.vkDestroyImageView(device, gfx_state.depthImageView, nil) end
    if gfx_state.depthImage then vk.vkDestroyImage(device, gfx_state.depthImage, nil) end
    if gfx_state.depthMemory then vk.vkFreeMemory(device, gfx_state.depthMemory, nil) end
end

return GraphicsPipeline
