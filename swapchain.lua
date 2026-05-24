local ffi = require("ffi")

local Swapchain = {}

function Swapchain.Init(vk, core_state, width, height, old_swapchain)
    print("[SWAPCHAIN] Building the display chain...")
    local surfaceCaps = ffi.new("VkSurfaceCapabilitiesKHR")
    vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(core_state.physicalDevice, core_state.surface, surfaceCaps)

    -- ========================================================
    -- THE FIX: Zero-Extent Guard
    -- If the OS minimizes or collapses the window during a resize,
    -- the max extent becomes 0x0. We must abort swapchain creation.
    -- ========================================================
    if surfaceCaps.maxImageExtent.width == 0 or surfaceCaps.maxImageExtent.height == 0 then
        print("[SWAPCHAIN WARNING] Surface extent is 0x0 (Minimized/Transitioning). Aborting rebuild.")
        return nil
    end

    local actualExtent = surfaceCaps.currentExtent
    if actualExtent.width ~= 4294967295 then
        width = math.max(1, tonumber(actualExtent.width))
        height = math.max(1, tonumber(actualExtent.height))
    else
        width = math.max(1, math.max(tonumber(surfaceCaps.minImageExtent.width), math.min(tonumber(surfaceCaps.maxImageExtent.width), width)))
        height = math.max(1, math.max(tonumber(surfaceCaps.minImageExtent.height), math.min(tonumber(surfaceCaps.maxImageExtent.height), height)))
    end

    local swapchainInfo = ffi.new("VkSwapchainCreateInfoKHR")
    ffi.fill(swapchainInfo, ffi.sizeof(swapchainInfo))
    swapchainInfo.sType = 1000001000
    swapchainInfo.surface = core_state.surface

    -- INJECT THE OLD SWAPCHAIN HERE
    swapchainInfo.oldSwapchain = old_swapchain or ffi.cast("VkSwapchainKHR", 0)

    swapchainInfo.minImageCount = surfaceCaps.minImageCount + 1
    swapchainInfo.imageFormat = 50
    swapchainInfo.imageColorSpace = 0
    swapchainInfo.imageExtent.width = width     -- Now strictly validated & clamped
    swapchainInfo.imageExtent.height = height   -- Now strictly validated & clamped

    swapchainInfo.imageArrayLayers = 1
    swapchainInfo.imageUsage = 16 -- VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
    swapchainInfo.preTransform = surfaceCaps.currentTransform
    swapchainInfo.compositeAlpha = 1 -- VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
    swapchainInfo.presentMode = 2 -- VK_PRESENT_MODE_FIFO_KHR (VSync on)
    swapchainInfo.clipped = 1 -- VK_TRUE

    local pSwapchain = ffi.new("VkSwapchainKHR[1]")
    local res = vk.vkCreateSwapchainKHR(core_state.device, swapchainInfo, nil, pSwapchain)
    -- Gracefully back out of volatile WM resizes instead of fatal asserts
    if res == -1000000001 then
        print("[SWAPCHAIN WARNING] Surface volatile. Retrying next frame...")
        return nil
    end
    assert(res == 0, "FATAL: Failed to create Swapchain! Error: " .. tonumber(res))
    local swapchain = pSwapchain[0]

    -- 3. Extract the Swapchain Images
    local pImageCount = ffi.new("uint32_t[1]")
    vk.vkGetSwapchainImagesKHR(core_state.device, swapchain, pImageCount, nil)
    local imageCount = pImageCount[0]

    local images = ffi.new("VkImage[?]", imageCount)
    vk.vkGetSwapchainImagesKHR(core_state.device, swapchain, pImageCount, images)

    -- 4. Create the Image Views
    local imageViews = ffi.new("VkImageView[?]", imageCount)

    for i = 0, imageCount - 1 do
        local viewInfo = ffi.new("VkImageViewCreateInfo")
        ffi.fill(viewInfo, ffi.sizeof(viewInfo))

        viewInfo.sType = 15 -- VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image = images[i]
        viewInfo.viewType = 1 -- VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format = 50 -- VK_FORMAT_B8G8R8A8_SRGB

        viewInfo.subresourceRange.aspectMask = 1 -- VK_IMAGE_ASPECT_COLOR_BIT
        viewInfo.subresourceRange.levelCount = 1
        viewInfo.subresourceRange.layerCount = 1

        -- Notice the pointer arithmetic (imageViews + i) to write directly to the array index!
        assert(vk.vkCreateImageView(core_state.device, viewInfo, nil, imageViews + i) == 0)
    end

    print("[SWAPCHAIN] Created successfully with " .. tonumber(imageCount) .. " images!")

    return {
        handle = swapchain,
        images = images,
        imageViews = imageViews,
        imageCount = imageCount,
        format = 50,
        extent = { width = width, height = height }
    }
end

function Swapchain.Destroy(vk, core_state, sc_state)
    print("[TEARDOWN] Destroying Swapchain & Image Views...")
    if not sc_state then return end

    for i = 0, sc_state.imageCount - 1 do
        if sc_state.imageViews[i] ~= nil then
            vk.vkDestroyImageView(core_state.device, sc_state.imageViews[i], nil)
        end
    end

    if sc_state.handle ~= nil then
        vk.vkDestroySwapchainKHR(core_state.device, sc_state.handle, nil)
    end
end

return Swapchain
