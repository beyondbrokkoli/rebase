local ffi = require("ffi")
local bit = require("bit")
require("vulkan_headers")

local reg = require("registry")
local cfg = reg.cfg
local vk_struct = reg.vk_struct
local vk_queue = reg.vk_queue

ffi.cdef[[
    const char** vx_sys_glfw_extensions(uint32_t* count);
    void vx_sys_inject_validation(void* instance);
    void vx_sys_eject_validation(void* instance);
]]

local vk

-- 1. Try Windows/Wine standard (vulkan-1.dll)
local success, lib = pcall(ffi.load, "vulkan-1")

-- 2. Try Linux standard (libvulkan.so)
if not success then
    success, lib = pcall(ffi.load, "vulkan")
end

-- 3. Try Linux strict versioning (libvulkan.so.1)
if not success then
    success, lib = pcall(ffi.load, "libvulkan.so.1")
end

assert(success, "FATAL: Could not load the Vulkan dynamic library! Is the Vulkan runtime installed?\nError: " .. tostring(lib))
vk = lib

local core = {}

-- PART 1: Instance Creation (Before the Yield)
function core.create_instance()
    print("[LUA] Initializing Vulkan Core (Instance Generation)...")

    -- 1. Ask C for GLFW Extensions natively
    local pCount = ffi.new("uint32_t[1]")
    local glfwExtensions = ffi.C.vx_sys_glfw_extensions(pCount)
    local exts_count = pCount[0]

    -- 2. Dynamically build the extension list based on Validation state
    local total_exts = exts_count + 1 -- Base: GLFW + get_physical_device_properties2
    if cfg.use_validation == 1 then
        total_exts = total_exts + 1   -- Add space for debug_utils
    end

    local instanceExtensions = ffi.new("const char*[?]", total_exts)
    for i = 0, exts_count - 1 do
        instanceExtensions[i] = glfwExtensions[i]
    end

    local ext_idx = exts_count
    instanceExtensions[ext_idx] = "VK_KHR_get_physical_device_properties2"
    ext_idx = ext_idx + 1

    -- 3. Configure Validation Layers & Debug Extensions
    local validationLayers = nil
    local layerCount = 0

    if cfg.use_validation == 1 then
        instanceExtensions[ext_idx] = "VK_EXT_debug_utils"
        validationLayers = ffi.new("const char*[1]", {"VK_LAYER_KHRONOS_validation"})
        layerCount = 1
        print("[LUA] Validation Layers ENABLED.")
    else
        print("[LUA] Validation Layers DISABLED. Running raw.")
    end

    -- 4. Build the Instance Info
    local appInfo = ffi.new("VkApplicationInfo", {
        sType = vk_struct.app_info,
        pApplicationName = "VX Engine Runtime",
        apiVersion = cfg.vk_api_version
    })

    local createInfo = ffi.new("VkInstanceCreateInfo", {
        sType = vk_struct.instance_create,
        pApplicationInfo = appInfo,
        enabledExtensionCount = total_exts,
        ppEnabledExtensionNames = instanceExtensions,
        enabledLayerCount = layerCount,
        ppEnabledLayerNames = validationLayers
    })

    -- 5. Create the Instance
    local pInstance = ffi.new("VkInstance[1]")
    local res = vk.vkCreateInstance(createInfo, nil, pInstance)
    assert(res == 0, "FATAL: vkCreateInstance failed!")
    local instance = pInstance[0]
    print("[LUA] Vulkan Instance Created!")

    -- Inject C-side validation message routing if enabled
    if cfg.use_validation == 1 then
        ffi.C.vx_sys_inject_validation(instance)
    end

    return {
        vk = vk,
        instance = instance
    }
end

-- PART 2: Logical Device & Queue Generation (After the Yield)
function core.finalize_device_and_swapchain(vk_state, surface_ptr)
    print("[LUA] Resuming Vulkan Setup. Finalizing Logical Device...")

    local vk = vk_state.vk
    local instance = vk_state.instance

    local surface = ffi.cast("VkSurfaceKHR", surface_ptr)
    vk_state.surface = surface
    print("[LUA] Window Surface Linked from Main Thread!")

    -- 6. Find the GPU
    local pDeviceCount = ffi.new("uint32_t[1]")
    vk.vkEnumeratePhysicalDevices(instance, pDeviceCount, nil)
    local pDevices = ffi.new("VkPhysicalDevice[?]", pDeviceCount[0])
    vk.vkEnumeratePhysicalDevices(instance, pDeviceCount, pDevices)

    local physicalDevice = pDevices[0]
    vk_state.physicalDevice = physicalDevice
    print("[LUA] Hardware GPU Selected!")

    -- 7. Find the Graphics/Compute Queue Family
    local pQueueFamilyCount = ffi.new("uint32_t[1]")
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyCount, nil)
    local queueFamilies = ffi.new("VkQueueFamilyProperties[?]", pQueueFamilyCount[0])
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyCount, queueFamilies)

    local qIndex = -1
    for i = 0, pQueueFamilyCount[0] - 1 do
        if bit.band(queueFamilies[i].queueFlags, vk_queue.graphics) ~= 0 then
            qIndex = i
            break
        end
    end
    assert(qIndex ~= -1, "FATAL: Could not find a Graphics/Compute queue!")
    vk_state.qIndex = qIndex

    -- 8. Create the Logical Device
    local queuePriority = ffi.new("float[1]", 1.0)
    local queueCreateInfo = ffi.new("VkDeviceQueueCreateInfo", {
        sType = vk_struct.device_queue_create,
        queueFamilyIndex = qIndex,
        queueCount = 1,
        pQueuePriorities = queuePriority
    })

    local deviceExtensions = ffi.new("const char*[8]", {
        "VK_KHR_swapchain",
        "VK_KHR_dynamic_rendering",
        "VK_KHR_depth_stencil_resolve",
        "VK_KHR_create_renderpass2",
        "VK_KHR_multiview",
        "VK_KHR_maintenance2",
        "VK_EXT_extended_dynamic_state",
        "VK_EXT_extended_dynamic_state2"
    })

    -- 1. Dynamic Rendering Feature
    local dynamicRendering = ffi.new("VkPhysicalDeviceDynamicRenderingFeatures")
    ffi.fill(dynamicRendering, ffi.sizeof(dynamicRendering))
    dynamicRendering.sType = vk_struct.dynamic_rendering_features
    dynamicRendering.dynamicRendering = 1

    -- 2. Extended Dynamic State 1 Feature
    local extDynamicState = ffi.new("VkPhysicalDeviceExtendedDynamicStateFeaturesEXT")
    ffi.fill(extDynamicState, ffi.sizeof(extDynamicState))
    extDynamicState.sType = vk_struct.extended_dynamic_state_features
    extDynamicState.pNext = dynamicRendering
    extDynamicState.extendedDynamicState = 1

    -- 3. Extended Dynamic State 2 Feature
    local extDynamicState2 = ffi.new("VkPhysicalDeviceExtendedDynamicState2FeaturesEXT")
    ffi.fill(extDynamicState2, ffi.sizeof(extDynamicState2))
    extDynamicState2.sType = vk_struct.extended_dynamic_state2_features
    extDynamicState2.pNext = extDynamicState
    extDynamicState2.extendedDynamicState2 = 1

    local deviceFeatures = ffi.new("VkPhysicalDeviceFeatures")
    ffi.fill(deviceFeatures, ffi.sizeof(deviceFeatures))
    deviceFeatures.largePoints = 1

    -- 4. Device Creation
    local deviceCreateInfo = ffi.new("VkDeviceCreateInfo")
    ffi.fill(deviceCreateInfo, ffi.sizeof(deviceCreateInfo))
    deviceCreateInfo.sType = vk_struct.device_create
    deviceCreateInfo.pNext = extDynamicState2
    deviceCreateInfo.queueCreateInfoCount = 1
    deviceCreateInfo.pQueueCreateInfos = queueCreateInfo
    deviceCreateInfo.enabledExtensionCount = 8
    deviceCreateInfo.ppEnabledExtensionNames = deviceExtensions
    deviceCreateInfo.pEnabledFeatures = deviceFeatures

    local pDevice = ffi.new("VkDevice[1]")
    local res = vk.vkCreateDevice(physicalDevice, deviceCreateInfo, nil, pDevice)
    assert(res == 0, "FATAL: Failed to create Logical Device! Error: " .. tonumber(res))
    local device = pDevice[0]
    vk_state.device = device
    print("[LUA] Logical Device Created!")

    -- 9. Grab the Command Queue
    local pQueue = ffi.new("VkQueue[1]")
    vk.vkGetDeviceQueue(device, qIndex, 0, pQueue)
    vk_state.queue = pQueue[0]

    return vk_state
end

-- TEARDOWN
function core.Destroy(vk_state)
    print("[TEARDOWN] Shutting down Vulkan Core...")
    local vk = vk_state.vk

    if vk_state.device ~= nil then
        vk.vkDestroyDevice(vk_state.device, nil)
    end

    if vk_state.surface ~= nil then
        vk.vkDestroySurfaceKHR(vk_state.instance, vk_state.surface, nil)
    end

    if vk_state.instance ~= nil then
        if cfg.use_validation == 1 then
            ffi.C.vx_sys_eject_validation(vk_state.instance)
        end
        vk.vkDestroyInstance(vk_state.instance, nil)
    end
end

return core
