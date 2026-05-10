local ffi = require("ffi")
local bit = require("bit")

local function init_allocator(vk)

    local function find_smart_buffer_memory(physicalDevice, typeFilter)
        local memProperties = ffi.new("VkPhysicalDeviceMemoryProperties")
        vk.vkGetPhysicalDeviceMemoryProperties(physicalDevice, memProperties)

        -- Hunt for ReBAR (VRAM that the CPU can crunch directly)
        local rebarFlags = bit.bor(1, 2, 4) -- DEVICE_LOCAL | HOST_VISIBLE | HOST_COHERENT
        for i = 0, memProperties.memoryTypeCount - 1 do
            local isTypeSupported = bit.band(typeFilter, bit.lshift(1, i)) ~= 0
            local hasProperties = bit.band(memProperties.memoryTypes[i].propertyFlags, rebarFlags) == rebarFlags
            if isTypeSupported and hasProperties then
                print("[MEMORY] ReBAR Supported! Streaming directly to VRAM.")
                return i
            end
        end

        -- Fallback to standard Host-Visible System RAM
        local stdFlags = bit.bor(2, 4) -- HOST_VISIBLE | HOST_COHERENT
        for i = 0, memProperties.memoryTypeCount - 1 do
            local isTypeSupported = bit.band(typeFilter, bit.lshift(1, i)) ~= 0
            local hasProperties = bit.band(memProperties.memoryTypes[i].propertyFlags, stdFlags) == stdFlags
            if isTypeSupported and hasProperties then
                print("[MEMORY] ReBAR NOT found. Falling back to System RAM.")
                return i
            end
        end
        error("FATAL: Failed to find suitable buffer memory!")
    end

    -- Returns: VkBuffer, VkDeviceMemory, mapped_ptr (cdata)
    local function create_host_visible_buffer(core_state, cdef_type, element_count, usage_flags)
        local byte_size = ffi.sizeof(cdef_type) * element_count

        local bufInfo = ffi.new("VkBufferCreateInfo")
        ffi.fill(bufInfo, ffi.sizeof(bufInfo))
        bufInfo.sType = 12 -- VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufInfo.size = byte_size
        bufInfo.usage = usage_flags
        bufInfo.sharingMode = 0

        local pBuffer = ffi.new("VkBuffer[1]")
        local res = vk.vkCreateBuffer(core_state.device, bufInfo, nil, pBuffer)
        assert(res == 0, "FATAL: vkCreateBuffer failed")

        local memReqs = ffi.new("VkMemoryRequirements")
        vk.vkGetBufferMemoryRequirements(core_state.device, pBuffer[0], memReqs)

        local allocInfo = ffi.new("VkMemoryAllocateInfo", {
            sType = 5, -- VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
            allocationSize = memReqs.size,
            memoryTypeIndex = find_smart_buffer_memory(core_state.physicalDevice, memReqs.memoryTypeBits)
        })

        local pMemory = ffi.new("VkDeviceMemory[1]")
        assert(vk.vkAllocateMemory(core_state.device, allocInfo, nil, pMemory) == 0)
        assert(vk.vkBindBufferMemory(core_state.device, pBuffer[0], pMemory[0], 0) == 0)

        local ppData = ffi.new("void*[1]")
        assert(vk.vkMapMemory(core_state.device, pMemory[0], 0, byte_size, 0, ppData) == 0)

        -- Return the holy trinity: The Buffer, The Memory, and the AVX2-ready Pointer
        return pBuffer[0], pMemory[0], ffi.cast(cdef_type .. "*", ppData[0])
    end

    return {
        create_host_visible_buffer = create_host_visible_buffer
    }
end

return init_allocator
