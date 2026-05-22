local ffi = require("ffi")
local bit = require("bit")

local GraphicsPipeline = {}

-- Helper function to read the raw binary SPIR-V files
local function ReadShaderFile(filename)
    local file = io.open(filename, "rb")
    assert(file, "FATAL: Failed to open shader file: " .. filename)
    local content = file:read("*a")
    file:close()
    return content
end

function GraphicsPipeline.Init(vk, core_state, width, height, pipelineLayout, colorFormat)
    print("[GRAPHICS] Building Reverse-Z Depth Buffer and Shader Modules...")

    local device = core_state.device
    local physDevice = core_state.physicalDevice

    -- ========================================================
    -- 1. Create Depth Image (The Z-Buffer)
    -- ========================================================
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

    -- ========================================================
    -- 2. Allocate VRAM for the Depth Image
    -- ========================================================
    local memReqs = ffi.new("VkMemoryRequirements")
    vk.vkGetImageMemoryRequirements(device, depthImage, memReqs)

    local memProperties = ffi.new("VkPhysicalDeviceMemoryProperties")
    vk.vkGetPhysicalDeviceMemoryProperties(physDevice, memProperties)

    -- Find VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT (1)
    local memoryTypeIndex = -1
    for i = 0, memProperties.memoryTypeCount - 1 do
        local isTypeSupported = bit.band(memReqs.memoryTypeBits, bit.lshift(1, i)) ~= 0
        local isVRAM = bit.band(memProperties.memoryTypes[i].propertyFlags, 1) ~= 0
        if isTypeSupported and isVRAM then
            memoryTypeIndex = i
            break
        end
    end
    assert(memoryTypeIndex ~= -1, "FATAL: Could not find VRAM for Depth Buffer!")

    local dAllocInfo = ffi.new("VkMemoryAllocateInfo")
    ffi.fill(dAllocInfo, ffi.sizeof(dAllocInfo))
    dAllocInfo.sType = 5 -- VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
    dAllocInfo.allocationSize = memReqs.size
    dAllocInfo.memoryTypeIndex = memoryTypeIndex

    local pDepthMemory = ffi.new("VkDeviceMemory[1]")
    assert(vk.vkAllocateMemory(device, dAllocInfo, nil, pDepthMemory) == 0)
    local depthMemory = pDepthMemory[0]

    assert(vk.vkBindImageMemory(device, depthImage, depthMemory, 0) == 0)

    -- ========================================================
    -- 3. Create the Depth Image View
    -- ========================================================
    local dViewInfo = ffi.new("VkImageViewCreateInfo")
    ffi.fill(dViewInfo, ffi.sizeof(dViewInfo))
    dViewInfo.sType = 15 -- VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
    dViewInfo.image = depthImage
    dViewInfo.viewType = 1 -- VK_IMAGE_VIEW_TYPE_2D
    dViewInfo.format = 126 -- VK_FORMAT_D32_SFLOAT
    dViewInfo.subresourceRange.aspectMask = 2 -- VK_IMAGE_ASPECT_DEPTH_BIT
    dViewInfo.subresourceRange.levelCount = 1
    dViewInfo.subresourceRange.layerCount = 1

    local pDepthView = ffi.new("VkImageView[1]")
    assert(vk.vkCreateImageView(device, dViewInfo, nil, pDepthView) == 0)
    local depthImageView = pDepthView[0]

    -- Load all 4 specialized shaders
    local geomVertCode = ReadShaderFile("geom_vert.spv")
    local geomFragCode = ReadShaderFile("geom_frag.spv")
    local pointVertCode = ReadShaderFile("points_vert.spv")
    local pointFragCode = ReadShaderFile("points_frag.spv")

    local function createShaderModule(code)
        local info = ffi.new("VkShaderModuleCreateInfo", { sType = 16, codeSize = string.len(code), pCode = ffi.cast("const uint32_t*", code) })
        local pMod = ffi.new("VkShaderModule[1]")
        assert(vk.vkCreateShaderModule(device, info, nil, pMod) == 0)
        return pMod[0]
    end

    local geomVertMod = createShaderModule(geomVertCode)
    local geomFragMod = createShaderModule(geomFragCode)
    local pointVertMod = createShaderModule(pointVertCode)
    local pointFragMod = createShaderModule(pointFragCode)

    local geomStages = ffi.new("VkPipelineShaderStageCreateInfo[2]")
    geomStages[0].sType = 18; geomStages[0].stage = 1; geomStages[0].module = geomVertMod; geomStages[0].pName = "main"
    geomStages[1].sType = 18; geomStages[1].stage = 16; geomStages[1].module = geomFragMod; geomStages[1].pName = "main"

    local pointStages = ffi.new("VkPipelineShaderStageCreateInfo[2]")
    pointStages[0].sType = 18; pointStages[0].stage = 1; pointStages[0].module = pointVertMod; pointStages[0].pName = "main"
    pointStages[1].sType = 18; pointStages[1].stage = 16; pointStages[1].module = pointFragMod; pointStages[1].pName = "main"

    -- 0 Attributes, 0 Bindings! The Shader handles the geometry now.
    local vertexInputInfo = ffi.new("VkPipelineVertexInputStateCreateInfo")
    ffi.fill(vertexInputInfo, ffi.sizeof(vertexInputInfo))
    vertexInputInfo.sType = 19
    vertexInputInfo.vertexBindingDescriptionCount = 0
    vertexInputInfo.pVertexBindingDescriptions = nil
    vertexInputInfo.vertexAttributeDescriptionCount = 0
    vertexInputInfo.pVertexAttributeDescriptions = nil

    local inputAssembly = ffi.new("VkPipelineInputAssemblyStateCreateInfo")
    ffi.fill(inputAssembly, ffi.sizeof(inputAssembly))
    inputAssembly.sType = 20
    -- Topology will be set per-pipeline below

    local viewportState = ffi.new("VkPipelineViewportStateCreateInfo")
    ffi.fill(viewportState, ffi.sizeof(viewportState))
    viewportState.sType = 22
    viewportState.viewportCount = 1
    viewportState.scissorCount = 1

    local rasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo")
    ffi.fill(rasterizer, ffi.sizeof(rasterizer))
    rasterizer.sType = 23
    rasterizer.polygonMode = 0
    rasterizer.lineWidth = 1.0
    rasterizer.cullMode = 1
    rasterizer.frontFace = 0

    local multisampling = ffi.new("VkPipelineMultisampleStateCreateInfo")
    ffi.fill(multisampling, ffi.sizeof(multisampling))
    multisampling.sType = 24
    multisampling.rasterizationSamples = 1

    local depthStencil = ffi.new("VkPipelineDepthStencilStateCreateInfo")
    ffi.fill(depthStencil, ffi.sizeof(depthStencil))
    depthStencil.sType = 25
    depthStencil.depthTestEnable = 1
    depthStencil.depthWriteEnable = 1
    depthStencil.depthCompareOp = 4

    local colorBlendAttachment = ffi.new("VkPipelineColorBlendAttachmentState[1]")
    ffi.fill(colorBlendAttachment, ffi.sizeof(colorBlendAttachment))
    colorBlendAttachment[0].colorWriteMask = 15
    colorBlendAttachment[0].blendEnable = 0
    colorBlendAttachment[0].srcColorBlendFactor = 6
    colorBlendAttachment[0].dstColorBlendFactor = 1
    colorBlendAttachment[0].colorBlendOp = 0
    colorBlendAttachment[0].srcAlphaBlendFactor = 1
    colorBlendAttachment[0].dstAlphaBlendFactor = 0
    colorBlendAttachment[0].alphaBlendOp = 0

    local colorBlending = ffi.new("VkPipelineColorBlendStateCreateInfo")
    ffi.fill(colorBlending, ffi.sizeof(colorBlending))
    colorBlending.sType = 26
    colorBlending.attachmentCount = 1
    colorBlending.pAttachments = colorBlendAttachment

    local colorFormats = ffi.new("int32_t[1]", {colorFormat})

    local dynamicStates = ffi.new("VkDynamicState[8]")
    dynamicStates[0] = 0
    dynamicStates[1] = 1
    dynamicStates[2] = 1000267000
    dynamicStates[3] = 1000267001
    dynamicStates[4] = 1000267002
    dynamicStates[5] = 1000267006
    dynamicStates[6] = 1000267007
    dynamicStates[7] = 1000267008

    local dynamicStateInfo = ffi.new("VkPipelineDynamicStateCreateInfo")
    ffi.fill(dynamicStateInfo, ffi.sizeof(dynamicStateInfo))
    dynamicStateInfo.sType = 27
    dynamicStateInfo.dynamicStateCount = 8
    dynamicStateInfo.pDynamicStates = dynamicStates

    local pipelineRenderingInfo = ffi.new("VkPipelineRenderingCreateInfo")
    ffi.fill(pipelineRenderingInfo, ffi.sizeof(pipelineRenderingInfo))
    pipelineRenderingInfo.sType = 1000044002
    pipelineRenderingInfo.colorAttachmentCount = 1
    pipelineRenderingInfo.pColorAttachmentFormats = colorFormats
    pipelineRenderingInfo.depthAttachmentFormat = 126

    -- Base Pipeline Info
    local pipelineInfo = ffi.new("VkGraphicsPipelineCreateInfo[1]")
    ffi.fill(pipelineInfo, ffi.sizeof(pipelineInfo))
    pipelineInfo[0].sType = 28
    pipelineInfo[0].pNext = pipelineRenderingInfo
    pipelineInfo[0].stageCount = 2
    pipelineInfo[0].pStages = shaderStages
    pipelineInfo[0].pVertexInputState = vertexInputInfo
    pipelineInfo[0].pInputAssemblyState = inputAssembly
    pipelineInfo[0].pViewportState = viewportState
    pipelineInfo[0].pRasterizationState = rasterizer
    pipelineInfo[0].pMultisampleState = multisampling
    pipelineInfo[0].pDepthStencilState = depthStencil
    pipelineInfo[0].pColorBlendState = colorBlending
    pipelineInfo[0].pDynamicState = dynamicStateInfo
    pipelineInfo[0].layout = pipelineLayout

    -- PIPELINE A: THE GEOMETRY SWARM
    pipelineInfo[0].pStages = geomStages
    inputAssembly.topology = 3 -- TRIANGLE_LIST
    local pGeomPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pGeomPipeline) == 0)

    -- PIPELINE B: THE VOLUMETRIC NEBULA
    pipelineInfo[0].pStages = pointStages
    inputAssembly.topology = 0 -- POINT_LIST

    local pointRasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo")
    ffi.copy(pointRasterizer, rasterizer, ffi.sizeof(rasterizer))
    pointRasterizer.cullMode = 0 -- No culling for points
    pipelineInfo[0].pRasterizationState = pointRasterizer

    local pPointsPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pPointsPipeline) == 0)

    return {
        depthImage = depthImage,
        depthMemory = depthMemory,
        depthImageView = depthImageView,
        -- Export all 4 modules so they can be destroyed properly
        gVert = geomVertMod, gFrag = geomFragMod,
        pVert = pointVertMod, pFrag = pointFragMod,
        pipelineLayout = pipelineLayout,
        pipeline_geom = pGeomPipeline[0],
        pipeline_points = pPointsPipeline[0]
    }
end

function GraphicsPipeline.Destroy(vk, core_state, gfx_state)
    print("[TEARDOWN] Destroying Dual Graphics Pipelines & Depth Buffer...")
    if not gfx_state then return end
    local device = type(core_state) == "table" and core_state.device or core_state

    vk.vkDestroyPipeline(device, gfx_state.pipeline_geom, nil)
    vk.vkDestroyPipeline(device, gfx_state.pipeline_points, nil)

    vk.vkDestroyShaderModule(device, gfx_state.geomVertMod, nil)
    vk.vkDestroyShaderModule(device, gfx_state.geomFragMod, nil)
    vk.vkDestroyShaderModule(device, gfx_state.pointVertMod, nil)
    vk.vkDestroyShaderModule(device, gfx_state.pointFragMod, nil)
    vk.vkDestroyImageView(device, gfx_state.depthImageView, nil)
    vk.vkDestroyImage(device, gfx_state.depthImage, nil)
    vk.vkFreeMemory(device, gfx_state.depthMemory, nil)
end

return GraphicsPipeline
