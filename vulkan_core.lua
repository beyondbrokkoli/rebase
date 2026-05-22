local ffi = require("ffi")
local bit = require("bit")
require("vulkan_headers")

ffi.cdef[[
    const char** vibe_get_glfw_extensions(uint32_t* count);
    void vibe_inject_validation_layers(void* instance);
    void vibe_eject_validation_layers(void* instance);
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

    -- 1. Ask C for GLFW Extensions natively!
    local pCount = ffi.new("uint32_t[1]")
    local glfwExtensions = ffi.C.vibe_get_glfw_extensions(pCount)
    local exts_count = pCount[0]

    -- 1.5. Splice the arrays: GLFW Extensions + Debug Utils + Physical Device Props
    local total_exts = exts_count + 2
    local instanceExtensions = ffi.new("const char*[?]", total_exts)

    for i = 0, exts_count - 1 do
        instanceExtensions[i] = glfwExtensions[i]
    end

    -- Append the TWO Instance extensions
    instanceExtensions[exts_count] = "VK_EXT_debug_utils"
    instanceExtensions[exts_count + 1] = "VK_KHR_get_physical_device_properties2"

    local appInfo = ffi.new("VkApplicationInfo", {
        sType = 0, -- VK_STRUCTURE_TYPE_APPLICATION_INFO
        pApplicationName = "VibeEngine Cooking Dish",
        apiVersion = 4206592 -- VK_MAKE_API_VERSION(0, 1, 3, 0)
    })
    -- 2.5 Define the Validation Layers
    local validationLayers = ffi.new("const char*[1]", {"VK_LAYER_KHRONOS_validation"})

    -- 3. Build the Instance Info
    local createInfo = ffi.new("VkInstanceCreateInfo", {
        sType = 1, -- VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
        pApplicationInfo = appInfo,
        enabledExtensionCount = total_exts,
        ppEnabledExtensionNames = instanceExtensions,
        enabledLayerCount = 1,
        ppEnabledLayerNames = validationLayers
    })

    -- 4. Create the Instance
    local pInstance = ffi.new("VkInstance[1]")
    local res = vk.vkCreateInstance(createInfo, nil, pInstance)
    assert(res == 0, "FATAL: vkCreateInstance failed!")
    local instance = pInstance[0]
    print("[LUA] Vulkan Instance Created!")

    -- Optional Validation Layer injection (Requires it to exist in main.c)
    ffi.C.vibe_inject_validation_layers(instance)

    -- Return the base state so main.lua can pass the instance to C and yield
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

    -- 5. Cast the raw pointer from C back into a VkSurfaceKHR
    local surface = ffi.cast("VkSurfaceKHR", surface_ptr)
    vk_state.surface = surface
    print("[LUA] Window Surface Linked from Main Thread!")

    -- 6. Find the GPU
    local pDeviceCount = ffi.new("uint32_t[1]")
    vk.vkEnumeratePhysicalDevices(instance, pDeviceCount, nil)
    local pDevices = ffi.new("VkPhysicalDevice[?]", pDeviceCount[0])
    vk.vkEnumeratePhysicalDevices(instance, pDeviceCount, pDevices)

    local physicalDevice = pDevices[0] -- Just grab the first GPU for now
    vk_state.physicalDevice = physicalDevice
    print("[LUA] Hardware GPU Selected!")

    -- 7. Find the Graphics/Compute Queue Family
    local pQueueFamilyCount = ffi.new("uint32_t[1]")
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyCount, nil)
    local queueFamilies = ffi.new("VkQueueFamilyProperties[?]", pQueueFamilyCount[0])
    vk.vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, pQueueFamilyCount, queueFamilies)

    local qIndex = -1
    for i = 0, pQueueFamilyCount[0] - 1 do
        -- VK_QUEUE_GRAPHICS_BIT is 1. (It guarantees Compute support too!)
        if bit.band(queueFamilies[i].queueFlags, 1) ~= 0 then
            qIndex = i
            break
        end
    end
    assert(qIndex ~= -1, "FATAL: Could not find a Graphics/Compute queue!")
    vk_state.qIndex = qIndex

    -- 8. Create the Logical Device
    local queuePriority = ffi.new("float[1]", 1.0)
    local queueCreateInfo = ffi.new("VkDeviceQueueCreateInfo", {
        sType = 2, -- VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
        queueFamilyIndex = qIndex,
        queueCount = 1,
        pQueuePriorities = queuePriority
    })

    local deviceExtensions = ffi.new("const char*[9]", { -- Increased to 9
        "VK_KHR_swapchain",
        "VK_KHR_dynamic_rendering",
        "VK_KHR_depth_stencil_resolve",
        "VK_KHR_create_renderpass2",
        "VK_KHR_multiview",
        "VK_KHR_maintenance2",
        "VK_EXT_extended_dynamic_state",
        "VK_EXT_extended_dynamic_state2",
        "VK_EXT_extended_dynamic_state3" -- ADD THIS LINE
    })

    -- 1. Dynamic Rendering Feature
    local dynamicRendering = ffi.new("VkPhysicalDeviceDynamicRenderingFeatures")
    ffi.fill(dynamicRendering, ffi.sizeof(dynamicRendering))
    dynamicRendering.sType = 1000044003
    dynamicRendering.dynamicRendering = 1

    -- 2. Extended Dynamic State 1 Feature
    local extDynamicState = ffi.new("VkPhysicalDeviceExtendedDynamicStateFeaturesEXT")
    ffi.fill(extDynamicState, ffi.sizeof(extDynamicState))
    extDynamicState.sType = 1000267000
    extDynamicState.pNext = dynamicRendering
    extDynamicState.extendedDynamicState = 1

    -- 3. Extended Dynamic State 2 Feature (THE FIX)
    local extDynamicState2 = ffi.new("VkPhysicalDeviceExtendedDynamicState2FeaturesEXT")
    ffi.fill(extDynamicState2, ffi.sizeof(extDynamicState2))
    extDynamicState2.sType = 1000377000 -- VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT
    extDynamicState2.pNext = extDynamicState
    extDynamicState2.extendedDynamicState2 = 1

    local extDynamicState3 = ffi.new("VkPhysicalDeviceExtendedDynamicState3FeaturesEXT")
    ffi.fill(extDynamicState3, ffi.sizeof(extDynamicState3))
    extDynamicState3.sType = 1000455000
    extDynamicState3.pNext = extDynamicState2 -- Chain it to EXT2!
    -- This is the magic flag that silences the Validation Layer error
    extDynamicState3.extendedDynamicState3PolygonMode = 0
    extDynamicState3.dynamicPrimitiveTopologyUnrestricted = 1

    local deviceFeatures = ffi.new("VkPhysicalDeviceFeatures")
    ffi.fill(deviceFeatures, ffi.sizeof(deviceFeatures))
    deviceFeatures.largePoints = 1

    local deviceCreateInfo = ffi.new("VkDeviceCreateInfo")
    ffi.fill(deviceCreateInfo, ffi.sizeof(deviceCreateInfo))
    deviceCreateInfo.sType = 3
    -- IMPORTANT: Update the pNext to point to the END of the chain (EXT3)
    deviceCreateInfo.pNext = extDynamicState3
    deviceCreateInfo.queueCreateInfoCount = 1
    deviceCreateInfo.pQueueCreateInfos = queueCreateInfo
    deviceCreateInfo.enabledExtensionCount = 9 -- Update to 9!
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

    print("[DEBUG] Device Pointer in core: " .. tostring(device))

    -- We pass the fully loaded state back to main.lua
    return vk_state
end

-- TEARDOWN
function core.Destroy(vk_state)
    print("[TEARDOWN] Shutting down Vulkan Core...")
    local vk = vk_state.vk

    -- 1. Destroy Logical Device First
    if vk_state.device ~= nil then
        vk.vkDestroyDevice(vk_state.device, nil)
    end

    -- 2. Destroy the Window Surface
    if vk_state.surface ~= nil then
        vk.vkDestroySurfaceKHR(vk_state.instance, vk_state.surface, nil)
    end

    -- 3. Destroy the Instance Last
    if vk_state.instance ~= nil then
        ffi.C.vibe_eject_validation_layers(vk_state.instance)
        vk.vkDestroyInstance(vk_state.instance, nil)
    end
end

return core
