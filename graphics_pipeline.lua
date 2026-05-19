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
    print("[GRAPHICS] Building Reverse-Z Depth Buffer and Shader Modules (Dynamic State Enabled)...")
    local device = core_state.device
    local physDevice = core_state.physicalDevice

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

    -- 2. Allocate VRAM for the Depth Image
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

    -- 3. Create the Depth Image View
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

    -- 4. Load Shader Modules
    local vertCode = ReadShaderFile("render_vert.spv")
    local fragCode = ReadShaderFile("render_frag.spv")
    local vertInfo = ffi.new("VkShaderModuleCreateInfo", { sType = 16, codeSize = string.len(vertCode), pCode = ffi.cast("const uint32_t*", vertCode) })
    local fragInfo = ffi.new("VkShaderModuleCreateInfo", { sType = 16, codeSize = string.len(fragCode), pCode = ffi.cast("const uint32_t*", fragCode) })
    local pVertModule = ffi.new("VkShaderModule[1]")
    local pFragModule = ffi.new("VkShaderModule[1]")
    assert(vk.vkCreateShaderModule(device, vertInfo, nil, pVertModule) == 0)
    assert(vk.vkCreateShaderModule(device, fragInfo, nil, pFragModule) == 0)

    local shaderStages = ffi.new("VkPipelineShaderStageCreateInfo[2]")
    shaderStages[0].sType = 18; shaderStages[0].stage = 1; shaderStages[0].module = pVertModule[0]; shaderStages[0].pName = "main"
    shaderStages[1].sType = 18; shaderStages[1].stage = 16; shaderStages[1].module = pFragModule[0]; shaderStages[1].pName = "main"

    local vertexInputInfo = ffi.new("VkPipelineVertexInputStateCreateInfo")
    ffi.fill(vertexInputInfo, ffi.sizeof(vertexInputInfo)); vertexInputInfo.sType = 19

    local inputAssembly = ffi.new("VkPipelineInputAssemblyStateCreateInfo")
    ffi.fill(inputAssembly, ffi.sizeof(inputAssembly)); inputAssembly.sType = 20; inputAssembly.topology = 3

    local viewportState = ffi.new("VkPipelineViewportStateCreateInfo")
    ffi.fill(viewportState, ffi.sizeof(viewportState)); viewportState.sType = 22; viewportState.viewportCount = 1; viewportState.scissorCount = 1

    local rasterizer = ffi.new("VkPipelineRasterizationStateCreateInfo")
    ffi.fill(rasterizer, ffi.sizeof(rasterizer)); rasterizer.sType = 23; rasterizer.polygonMode = 0; rasterizer.lineWidth = 1.0

    local multisampling = ffi.new("VkPipelineMultisampleStateCreateInfo")
    ffi.fill(multisampling, ffi.sizeof(multisampling)); multisampling.sType = 24; multisampling.rasterizationSamples = 1

    local depthStencil = ffi.new("VkPipelineDepthStencilStateCreateInfo")
    ffi.fill(depthStencil, ffi.sizeof(depthStencil)); depthStencil.sType = 25

    local colorBlendAttachment = ffi.new("VkPipelineColorBlendAttachmentState[1]")
    ffi.fill(colorBlendAttachment, ffi.sizeof(colorBlendAttachment))
    colorBlendAttachment[0].colorWriteMask = 15; colorBlendAttachment[0].blendEnable = 0

    local colorBlending = ffi.new("VkPipelineColorBlendStateCreateInfo")
    ffi.fill(colorBlending, ffi.sizeof(colorBlending)); colorBlending.sType = 26; colorBlending.attachmentCount = 1; colorBlending.pAttachments = colorBlendAttachment

    -- === INJECT EXTENDED DYNAMIC STATES (BULLETPROOF) ===
    local dynamicStates = ffi.new("int32_t[6]", {
        0,
        1000267004,
        1000267000,
        1000267006,
        1000267007,
        1000267008,
    });

    local dynamicStateInfo = ffi.new("VkPipelineDynamicStateCreateInfo", {
        sType = 27,
        dynamicStateCount = 6,
        pDynamicStates = dynamicStates
    })

    local colorFormats = ffi.new("int32_t[1]", {colorFormat})
    local pipelineRenderingInfo = ffi.new("VkPipelineRenderingCreateInfo")
    ffi.fill(pipelineRenderingInfo, ffi.sizeof(pipelineRenderingInfo))
    pipelineRenderingInfo.sType = 1000044002; pipelineRenderingInfo.colorAttachmentCount = 1; pipelineRenderingInfo.pColorAttachmentFormats = colorFormats; pipelineRenderingInfo.depthAttachmentFormat = 126

    local pipelineInfo = ffi.new("VkGraphicsPipelineCreateInfo[1]")
    ffi.fill(pipelineInfo, ffi.sizeof(pipelineInfo))
    pipelineInfo[0].sType = 28; pipelineInfo[0].pNext = pipelineRenderingInfo
    pipelineInfo[0].stageCount = 2; pipelineInfo[0].pStages = shaderStages
    pipelineInfo[0].pVertexInputState = vertexInputInfo
    pipelineInfo[0].pInputAssemblyState = inputAssembly
    pipelineInfo[0].pViewportState = viewportState
    pipelineInfo[0].pRasterizationState = rasterizer
    pipelineInfo[0].pMultisampleState = multisampling
    pipelineInfo[0].pDepthStencilState = depthStencil
    pipelineInfo[0].pColorBlendState = colorBlending
    pipelineInfo[0].pDynamicState = dynamicStateInfo; -- Bind the dynamic override
    pipelineInfo[0].layout = pipelineLayout

    local pPipeline = ffi.new("VkPipeline[1]")
    assert(vk.vkCreateGraphicsPipelines(device, nil, 1, pipelineInfo, nil, pPipeline) == 0)
    print("[GRAPHICS] Swarm Pipeline Successfully Compiled with Dynamic States!")

    return { depthImage = depthImage, depthMemory = depthMemory, depthImageView = depthImageView, vertModule = pVertModule[0], fragModule = pFragModule[0], pipeline = pPipeline[0], pipelineLayout = pipelineLayout }
end
function GraphicsPipeline.Destroy(vk, core_state, gfx_state)
    print("[TEARDOWN] Destroying Graphics Pipeline & Depth Buffer...")
    if not gfx_state then return end

    local device = type(core_state) == "table" and core_state.device or core_state

    vk.vkDestroyPipeline(device, gfx_state.pipeline, nil)
    vk.vkDestroyShaderModule(device, gfx_state.vertModule, nil)
    vk.vkDestroyShaderModule(device, gfx_state.fragModule, nil)

    vk.vkDestroyImageView(device, gfx_state.depthImageView, nil)
    vk.vkDestroyImage(device, gfx_state.depthImage, nil)
    vk.vkFreeMemory(device, gfx_state.depthMemory, nil)
end

return GraphicsPipeline
