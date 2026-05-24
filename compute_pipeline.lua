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
    print("[COMPUTE] Forging 6-Pass Spatial Grid Shaders...");

    local mod_clear       = CreateShaderModule(vk, device, "clear_comp.spv")
    local mod_hash        = CreateShaderModule(vk, device, "hash_comp.spv")
    local mod_scan_local  = CreateShaderModule(vk, device, "scan_local_comp.spv")
    local mod_scan_group  = CreateShaderModule(vk, device, "scan_group_comp.spv")
    local mod_scan_add    = CreateShaderModule(vk, device, "scan_add_comp.spv")
    local mod_reorder     = CreateShaderModule(vk, device, "reorder_comp.spv")

    local modules = {mod_clear, mod_hash, mod_scan_local, mod_scan_group, mod_scan_add, mod_reorder}
    local pipelineInfos = ffi.new("VkComputePipelineCreateInfo[6]")

    for i = 0, 5 do
        pipelineInfos[i].sType = 29
        pipelineInfos[i].layout = pipelineLayout
        pipelineInfos[i].stage.sType = 18
        pipelineInfos[i].stage.stage = 32
        pipelineInfos[i].stage.module = modules[i + 1]
        pipelineInfos[i].stage.pName = "main"
    end

    local pPipelines = ffi.new("VkPipeline[6]")
    assert(vk.vkCreateComputePipelines(device, nil, 6, pipelineInfos, nil, pPipelines) == 0)

return {
        pipe_clear       = pPipelines[0],
        pipe_hash        = pPipelines[1],
        pipe_scan_local  = pPipelines[2],
        pipe_scan_group  = pPipelines[3],
        pipe_scan_add    = pPipelines[4],
        pipe_reorder     = pPipelines[5],

        -- MUST export these so Destroy() can see them
        mod_clear        = mod_clear,
        mod_hash         = mod_hash,
        mod_scan_local   = mod_scan_local,
        mod_scan_group   = mod_scan_group,
        mod_scan_add     = mod_scan_add,
        mod_reorder      = mod_reorder,

        pipelineLayout   = pipelineLayout
    }
end

function ComputePipeline.Destroy(vk, core_state, comp_state)
    print("[TEARDOWN] Dismantling Compute Graph Pipelines...")
    if not comp_state or not core_state then return end

    local device = core_state.device

    if comp_state.pipe_clear      ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_clear, nil) end
    if comp_state.pipe_hash       ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_hash, nil) end
    if comp_state.pipe_scan_local ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_scan_local, nil) end
    if comp_state.pipe_scan_group ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_scan_group, nil) end
    if comp_state.pipe_scan_add   ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_scan_add, nil) end
    if comp_state.pipe_reorder    ~= nil then vk.vkDestroyPipeline(device, comp_state.pipe_reorder, nil) end

    if comp_state.mod_clear       ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_clear, nil) end
    if comp_state.mod_hash        ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_hash, nil) end
    if comp_state.mod_scan_local  ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_scan_local, nil) end
    if comp_state.mod_scan_group  ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_scan_group, nil) end
    if comp_state.mod_scan_add    ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_scan_add, nil) end
    if comp_state.mod_reorder     ~= nil then vk.vkDestroyShaderModule(device, comp_state.mod_reorder, nil) end
end

return ComputePipeline
