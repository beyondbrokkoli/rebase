local ffi = require("ffi")
local bit = require("bit")

local GraphicsPipeline = {}

-- DEFERRED DELETION QUEUE (Pre-allocated)
local DELETION_QUEUE_SIZE = 16
local deletion_queue = {}
for i = 0, DELETION_QUEUE_SIZE - 1 do
    deletion_queue[i] = {
        active = false, frame_target = 0,
        geom = nil, points = nil,
        vert = nil, frag = nil  -- REPLACED the 4 old shader pointers
    }
end
local d_head = 0
local d_tail = 0

function GraphicsPipeline.PumpDeletionQueue(vk, core_state, current_frame)
    local device = type(core_state) == "table" and core_state.device or core_state

    while d_tail ~= d_head do
        local item = deletion_queue[d_tail]
        if current_frame < item.frame_target then
            break
        end

        vk.vkDestroyPipeline(device, item.geom, nil)
        vk.vkDestroyPipeline(device, item.points, nil)
        -- Only two modules to destroy now!
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
        sType = 16, codeSize = string.len(code), pCode = ffi.cast("const uint32_t*", code)
    })
    local pMod = ffi.new("VkShaderModule[1]")
    assert(vk.vkCreateShaderModule(device, info, nil, pMod) == 0)
    return pMod[0]
end

-- PIPELINE BUILDER (Reusable for Hotswapping)
local function BuildPipelines(vk, device, layout, colorFormat, vertModule, fragModule)
    -- We only need ONE stage array now, shared by both pipelines!
    local shaderStages = ffi.new("VkPipelineShaderStageCreateInfo[2]")
    shaderStages[0].sType = 18; shaderStages[0].stage = 1;  shaderStages[0].module = vertModule; shaderStages[0].pName = "main"
    shaderStages[1].sType = 18; shaderStages[1].stage = 16; shaderStages[1].module = fragModule; shaderStages[1].pName = "main"

    local vertexInputInfo = ffi.new("VkPipelineVertexInputStateCreateInfo", { sType = 19 })
    local inputAssembly = ffi.new("VkPipelineInputAssemblyStateCreateInfo", { sType = 20 })
    local viewportState = ffi.new("VkPipelineViewportStateCreateInfo", { sType = 22, viewportCount = 1, scissorCount = 1 })

    local rasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo", {
        sType = 23, polygonMode = 0, lineWidth = 1.0, cullMode = 1, frontFace = 0
    })
    local multisampling = ffi.new("VkPipelineMultisampleStateCreateInfo", { sType = 24, rasterizationSamples = 1 })
    local depthStencil = ffi.new("VkPipelineDepthStencilStateCreateInfo", {
        sType = 25, depthTestEnable = 1, depthWriteEnable = 1, depthCompareOp = 4
    })

    local colorBlendAttachment = ffi.new("VkPipelineColorBlendAttachmentState[1]")
    colorBlendAttachment[0].colorWriteMask = 15; colorBlendAttachment[0].srcColorBlendFactor = 6
    colorBlendAttachment[0].dstColorBlendFactor = 1; colorBlendAttachment[0].srcAlphaBlendFactor = 1

    local colorBlending = ffi.new("VkPipelineColorBlendStateCreateInfo", {
        sType = 26, attachmentCount = 1, pAttachments = colorBlendAttachment
    })

    local dynamicStates = ffi.new("VkDynamicState[8]", { 0, 1, 1000267000, 1000267001, 1000267002, 1000267006, 1000267007, 1000267008 })
    local dynamicStateInfo = ffi.new("VkPipelineDynamicStateCreateInfo", {
        sType = 27, dynamicStateCount = 8, pDynamicStates = dynamicStates
    })

    local colorFormats = ffi.new("int32_t[1]", {colorFormat})
    local pipelineRenderingInfo = ffi.new("VkPipelineRenderingCreateInfo", {
        sType = 1000044002, colorAttachmentCount = 1, pColorAttachmentFormats = colorFormats, depthAttachmentFormat = 126
    })

    local pipelineInfo = ffi.new("VkGraphicsPipelineCreateInfo[1]")
    pipelineInfo[0].sType = 28; pipelineInfo[0].pNext = pipelineRenderingInfo
    pipelineInfo[0].stageCount = 2; pipelineInfo[0].pVertexInputState = vertexInputInfo
    pipelineInfo[0].pInputAssemblyState = inputAssembly; pipelineInfo[0].pViewportState = viewportState
    pipelineInfo[0].pRasterizationState = rasterizer; pipelineInfo[0].pMultisampleState = multisampling
    pipelineInfo[0].pDepthStencilState = depthStencil; pipelineInfo[0].pColorBlendState = colorBlending
    pipelineInfo[0].pDynamicState = dynamicStateInfo; pipelineInfo[0].layout = layout

    -- Bind our unified shader stages
    pipelineInfo[0].pStages = shaderStages

    -- Compile Geometry Pipeline (Topology: TRIANGLE_LIST)
    inputAssembly.topology = 3
    local pGeomPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pGeomPipeline) == 0)

    -- Compile Point Pipeline (Topology: POINT_LIST)
    inputAssembly.topology = 0
    local pointRasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo")
    ffi.copy(pointRasterizer, rasterizer, ffi.sizeof(rasterizer))
    pointRasterizer.cullMode = 0
    pipelineInfo[0].pRasterizationState = pointRasterizer

    local pPointsPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pPointsPipeline) == 0)

    return pGeomPipeline[0], pPointsPipeline[0]
end
function GraphicsPipeline.Init(vk, core_state, width, height, pipelineLayout, colorFormat)
    print("[GRAPHICS] Building Reverse-Z Depth Buffer and Shader Modules...")
    local device = core_state.device

    -- 1. Create Depth Image (The Z-Buffer)
    local dImgInfo = ffi.new("VkImageCreateInfo")
    ffi.fill(dImgInfo, ffi.sizeof(dImgInfo))
    dImgInfo.sType = 14 -- VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
    dImgInfo.imageType = 1 -- VK_IMAGE_TYPE_2D
    dImgInfo.extent.width = width
    dImgInfo.extent.height = height
    dImgInfo.extent.depth = 1
    dImgInfo.mipLevels = 1
    dImgInfo.arrayLayers = 1
    dImgInfo.format = 126 -- VK_FORMAT_D32_SFLOAT
    dImgInfo.tiling = 0 -- VK_IMAGE_TILING_OPTIMAL
    dImgInfo.initialLayout = 0 -- VK_IMAGE_LAYOUT_UNDEFINED
    dImgInfo.usage = 32 -- VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
    dImgInfo.samples = 1 -- VK_SAMPLE_COUNT_1_BIT

    local pDepthImage = ffi.new("VkImage[1]")
    assert(vk.vkCreateImage(device, dImgInfo, nil, pDepthImage) == 0)
    local depthImage = pDepthImage[0]

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
    local dAllocInfo = ffi.new("VkMemoryAllocateInfo", { sType = 5, allocationSize = memReqs.size, memoryTypeIndex = memoryTypeIndex })
    local pDepthMemory = ffi.new("VkDeviceMemory[1]"); assert(vk.vkAllocateMemory(device, dAllocInfo, nil, pDepthMemory) == 0)
    assert(vk.vkBindImageMemory(device, pDepthImage[0], pDepthMemory[0], 0) == 0)

    local dViewInfo = ffi.new("VkImageViewCreateInfo", {
        sType = 15, image = pDepthImage[0], viewType = 1, format = 126,
        subresourceRange = { aspectMask = 2, levelCount = 1, layerCount = 1 }
    })
    local pDepthView = ffi.new("VkImageView[1]"); assert(vk.vkCreateImageView(device, dViewInfo, nil, pDepthView) == 0)

    -- THE FIX: Unified Module Load
    local unifiedVert = createShaderModule(vk, device, ReadShaderFile("render_vert.spv"))
    local unifiedFrag = createShaderModule(vk, device, ReadShaderFile("render_frag.spv"))

    local pipeGeom, pipePoints = BuildPipelines(vk, device, pipelineLayout, colorFormat, unifiedVert, unifiedFrag)

    return {
        depthImage = pDepthImage[0], depthMemory = pDepthMemory[0], depthImageView = pDepthView[0],
        vert = unifiedVert, frag = unifiedFrag,  -- Unified modules
        pipelineLayout = pipelineLayout,
        colorFormat = colorFormat,
        pipeline_geom = pipeGeom,
        pipeline_points = pipePoints
    }
end

-- THE HOTSWAP ROUTINE
function GraphicsPipeline.HotReloadShaders(vk, core_state, gfx_state, current_frame)
    local device = core_state.device

    -- 1. Enqueue the current pipelines for safe deferred destruction
    local item = deletion_queue[d_head]
    item.active = true
    item.frame_target = current_frame + 4
    item.geom = gfx_state.pipeline_geom
    item.points = gfx_state.pipeline_points
    item.vert = gfx_state.vert
    item.frag = gfx_state.frag

    d_head = (d_head + 1) % DELETION_QUEUE_SIZE

    -- 2. Compile New Unified Modules
    local new_vert = createShaderModule(vk, device, ReadShaderFile("render_vert.spv"))
    local new_frag = createShaderModule(vk, device, ReadShaderFile("render_frag.spv"))

    -- 3. Forge New Pipelines
    local new_geom, new_points = BuildPipelines(vk, device, gfx_state.pipelineLayout, gfx_state.colorFormat, new_vert, new_frag)

    -- 4. Overwrite state
    gfx_state.pipeline_geom = new_geom
    gfx_state.pipeline_points = new_points
    gfx_state.vert = new_vert
    gfx_state.frag = new_frag
end

function GraphicsPipeline.Destroy(vk, core_state, gfx_state)
    print("[TEARDOWN] Destroying Dual Graphics Pipelines & Depth Buffer...")
    if not gfx_state then return end
    local device = type(core_state) == "table" and core_state.device or core_state

    -- Force clear the deletion queue without frame checks
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

