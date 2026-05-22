local ffi = require("ffi")

local ComputePipeline = {}

local function ReadShaderFile(filename)
    local file = io.open(filename, "rb")
    assert(file, "FATAL: Failed to open shader file: " .. filename)
    local content = file:read("*a")
    file:close()
    return content
end

local function CreateShaderModule(vk, device, filename)
    local compCode = ReadShaderFile(filename)
    local compInfo = ffi.new("VkShaderModuleCreateInfo", {
        sType = 16, -- VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
        codeSize = string.len(compCode),
        pCode = ffi.cast("const uint32_t*", compCode)
    })
    local pMod = ffi.new("VkShaderModule[1]")
    assert(vk.vkCreateShaderModule(device, compInfo, nil, pMod) == 0, "Failed to create shader module: " .. filename)
    return pMod[0]
end

function ComputePipeline.Init(vk, device, pipelineLayout)
    print("[COMPUTE] Forging 4-Pass Spatial Grid Shaders...")

    -- 1. Load the 4 Compute Modules
    local mod_clear   = CreateShaderModule(vk, device, "clear_comp.spv")
    local mod_hash    = CreateShaderModule(vk, device, "hash_comp.spv")
    local mod_scan    = CreateShaderModule(vk, device, "scan_comp.spv")
    local mod_reorder = CreateShaderModule(vk, device, "reorder_comp.spv")

    local modules = {mod_clear, mod_hash, mod_scan, mod_reorder}

    -- 2. Batch configure the 4 Pipeline creation infos
    local pipelineInfos = ffi.new("VkComputePipelineCreateInfo[4]")
    for i = 0, 3 do
        pipelineInfos[i].sType = 29 -- VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO
        pipelineInfos[i].layout = pipelineLayout

        -- Inline stage configuration
        pipelineInfos[i].stage.sType = 18 -- VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        pipelineInfos[i].stage.stage = 32 -- VK_SHADER_STAGE_COMPUTE_BIT
        pipelineInfos[i].stage.module = modules[i + 1]
        pipelineInfos[i].stage.pName = "main"
    end

    -- 3. Bake all 4 pipelines in one single driver call
    local pPipelines = ffi.new("VkPipeline[4]")
    assert(vk.vkCreateComputePipelines(device, nil, 4, pipelineInfos, nil, pPipelines) == 0)

    print("[COMPUTE] Spatial Grid Pipelines Locked and Loaded!")

    return {
        pipe_clear   = pPipelines[0],
        pipe_hash    = pPipelines[1],
        pipe_scan    = pPipelines[2],
        pipe_reorder = pPipelines[3],

        mod_clear    = mod_clear,
        mod_hash     = mod_hash,
        mod_scan     = mod_scan,
        mod_reorder  = mod_reorder,

        pipelineLayout = pipelineLayout
    }
end

function ComputePipeline.Destroy(vk, core_state, comp_state)
    print("[TEARDOWN] Dismantling Compute Graph Pipelines...")
    if not comp_state or not core_state then return end

    local device = core_state.device

    if comp_state.pipe_clear   ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_clear, nil) end
    if comp_state.pipe_hash    ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_hash, nil) end
    if comp_state.pipe_scan    ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_scan, nil) end
    if comp_state.pipe_reorder ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_reorder, nil) end

    if comp_state.mod_clear    ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_clear, nil) end
    if comp_state.mod_hash     ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_hash, nil) end
    if comp_state.mod_scan     ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_scan, nil) end
    if comp_state.mod_reorder  ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_reorder, nil) end
end

return ComputePipeline
