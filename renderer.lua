local ffi = require("ffi")
local bit = require("bit")
local reg = require("registry")
local vk_struct, vk_access, vk_stage = reg.vk_struct, reg.vk_access, reg.vk_stage
local vk_layout, vk_image, vk_attachment = reg.vk_layout, reg.vk_image, reg.vk_attachment

ffi.cdef[[
    typedef VkRenderingAttachmentInfo VkRenderingAttachmentInfoKHR;
    typedef VkRenderingInfo VkRenderingInfoKHR;
    typedef PFN_vkCmdBeginRendering PFN_vkCmdBeginRenderingKHR;
    typedef PFN_vkCmdEndRendering PFN_vkCmdEndRenderingKHR;
]]
local Renderer = {}

function Renderer.InitSync(vk, device, frames_in_flight)
    print("[RENDERER] Forging Synchronization Primitives...");

    local imageAvailable = ffi.new("VkSemaphore[?]", frames_in_flight);
    local renderFinished = ffi.new("VkSemaphore[?]", frames_in_flight);
    local inFlight = ffi.new("VkFence[?]", frames_in_flight);

    local semInfo = ffi.new("VkSemaphoreCreateInfo", { sType = vk_struct.semaphore_create })
    local fenceInfo = ffi.new("VkFenceCreateInfo", {
        sType = vk_struct.fence_create,
        flags = 1 -- VK_FENCE_CREATE_SIGNALED_BIT
    })

    for i = 0, frames_in_flight - 1 do
        assert(vk.vkCreateSemaphore(device, semInfo, nil, imageAvailable + i) == 0)
        assert(vk.vkCreateSemaphore(device, semInfo, nil, renderFinished + i) == 0)
        assert(vk.vkCreateFence(device, fenceInfo, nil, inFlight + i) == 0)
    end

    return {
        imageAvailable = imageAvailable,
        renderFinished = renderFinished,
        inFlight = inFlight
    }
end

function Renderer.AllocateFrameState(vk, device, width, height)
    local state = {}

    state.pImageIndex = ffi.new("uint32_t[1]")
    state.cmdBeginInfo = ffi.new("VkCommandBufferBeginInfo", { sType = vk_struct.command_buffer_begin })

    state.computeBarrier = ffi.new("VkMemoryBarrier", {
        sType = vk_struct.memory_barrier,
        srcAccessMask = vk_access.shader_write,
        dstAccessMask = vk_access.shader_read
    })

    state.colorBarrierIn = ffi.new("VkImageMemoryBarrier", {
        sType = vk_struct.image_memory_barrier,
        oldLayout = vk_layout.undefined,
        newLayout = vk_layout.color_attachment_optimal,
        srcQueueFamilyIndex = 4294967295,
        dstQueueFamilyIndex = 4294967295,
        subresourceRange = { aspectMask = vk_image.aspect_color, levelCount = 1, layerCount = 1 },
        srcAccessMask = 0,
        dstAccessMask = vk_access.color_write
    })

    state.depthBarrierIn = ffi.new("VkImageMemoryBarrier", {
        sType = vk_struct.image_memory_barrier,
        oldLayout = vk_layout.undefined,
        newLayout = vk_layout.depth_attachment_optimal,
        srcQueueFamilyIndex = 4294967295,
        dstQueueFamilyIndex = 4294967295,
        subresourceRange = { aspectMask = vk_image.aspect_depth, levelCount = 1, layerCount = 1 },
        srcAccessMask = 0,
        dstAccessMask = vk_access.depth_write
    })

    state.preBarriers = ffi.new("VkImageMemoryBarrier[2]")
    state.preBarriers[0] = state.colorBarrierIn
    state.preBarriers[1] = state.depthBarrierIn

    state.colorBarrierOut = ffi.new("VkImageMemoryBarrier", {
        sType = vk_struct.image_memory_barrier,
        oldLayout = vk_layout.color_attachment_optimal,
        newLayout = vk_layout.present_src,
        srcQueueFamilyIndex = 4294967295,
        dstQueueFamilyIndex = 4294967295,
        subresourceRange = { aspectMask = vk_image.aspect_color, levelCount = 1, layerCount = 1 },
        srcAccessMask = vk_access.color_write,
        dstAccessMask = 0
    })

    state.colorAttachment = ffi.new("VkRenderingAttachmentInfoKHR[1]")
    state.colorAttachment[0].sType = vk_struct.rendering_attachment_info
    state.colorAttachment[0].imageLayout = vk_layout.color_attachment_optimal
    state.colorAttachment[0].loadOp = vk_attachment.load_clear
    state.colorAttachment[0].storeOp = vk_attachment.store_store
    state.colorAttachment[0].clearValue.color.float32[0] = 0.01
    state.colorAttachment[0].clearValue.color.float32[1] = 0.01
    state.colorAttachment[0].clearValue.color.float32[2] = 0.02
    state.colorAttachment[0].clearValue.color.float32[3] = 1.0

    state.depthAttachment = ffi.new("VkRenderingAttachmentInfoKHR[1]")
    state.depthAttachment[0].sType = vk_struct.rendering_attachment_info
    state.depthAttachment[0].imageLayout = vk_layout.depth_attachment_optimal
    state.depthAttachment[0].loadOp = vk_attachment.load_clear
    state.depthAttachment[0].storeOp = vk_attachment.store_dont_care
    state.depthAttachment[0].clearValue.depthStencil.depth = 0.0

    state.renderInfo = ffi.new("VkRenderingInfoKHR[1]")
    state.renderInfo[0].sType = vk_struct.rendering_info
    state.renderInfo[0].renderArea.extent.width = width
    state.renderInfo[0].renderArea.extent.height = height
    state.renderInfo[0].layerCount = 1
    state.renderInfo[0].colorAttachmentCount = 1
    state.renderInfo[0].pColorAttachments = state.colorAttachment
    state.renderInfo[0].pDepthAttachment = state.depthAttachment

    state.viewport = ffi.new("VkViewport[1]", {{ 0.0, 0.0, width, height, 0.0, 1.0 }})
    state.scissor = ffi.new("VkRect2D[1]", {{ {0, 0}, {width, height} }})
    state.offsets = ffi.new("VkDeviceSize[1]", {0})

    state.submitInfo = ffi.new("VkSubmitInfo", {
        sType = vk_struct.submit_info,
        waitSemaphoreCount = 1,
        commandBufferCount = 1,
        signalSemaphoreCount = 1
    })

    state.waitStages = ffi.new("int32_t[1]", { vk_stage.color_out })
    state.submitInfo.pWaitDstStageMask = state.waitStages
    state.cmdPtr = ffi.new("VkCommandBuffer[1]")

    state.presentInfo = ffi.new("VkPresentInfoKHR", {
        sType = vk_struct.present_info,
        waitSemaphoreCount = 1,
        swapchainCount = 1
    })

    state.vkCmdBeginRendering = ffi.cast("PFN_vkCmdBeginRenderingKHR", vk.vkGetDeviceProcAddr(device, "vkCmdBeginRenderingKHR"))
    state.vkCmdEndRendering = ffi.cast("PFN_vkCmdEndRenderingKHR", vk.vkGetDeviceProcAddr(device, "vkCmdEndRenderingKHR"))
    assert(state.vkCmdBeginRendering ~= ffi.NULL and state.vkCmdEndRendering ~= ffi.NULL, "FATAL: KHR Dynamic Rendering Pointers Missing!")

    state.pFence = ffi.new("VkFence[1]")
    state.pDescriptorSets = ffi.new("VkDescriptorSet[1]")
    state.pComputeBarrierArr = ffi.new("VkMemoryBarrier[1]")
    state.pVertexBuffers = ffi.new("VkBuffer[1]")
    state.pColorBarrierOutArr = ffi.new("VkImageMemoryBarrier[1]")
    state.pWaitSemaphoreSubmit = ffi.new("VkSemaphore[1]")
    state.pSignalSemaphoreSubmit = ffi.new("VkSemaphore[1]")
    state.pWaitSemaphorePresent = ffi.new("VkSemaphore[1]")
    state.pSwapchains = ffi.new("VkSwapchainKHR[1]")
    state.pSubmitInfos = ffi.new("VkSubmitInfo[1]")

    state.pComputeBarrierArr[0] = state.computeBarrier
    state.pColorBarrierOutArr[0] = state.colorBarrierOut

    state.vkCmdBindPipeline = vk.vkCmdBindPipeline
    state.vkCmdBindDescriptorSets = vk.vkCmdBindDescriptorSets
    state.vkCmdPushConstants = vk.vkCmdPushConstants
    state.vkCmdDispatch = vk.vkCmdDispatch
    state.vkCmdPipelineBarrier = vk.vkCmdPipelineBarrier
    state.vkCmdSetViewport = vk.vkCmdSetViewport
    state.vkCmdSetScissor = vk.vkCmdSetScissor
    state.vkCmdBindVertexBuffers = vk.vkCmdBindVertexBuffers
    state.vkCmdDraw = vk.vkCmdDraw

    return state
end

function Renderer.Destroy(vk, device, sync, frames_in_flight)
    print("[TEARDOWN] Dismantling Renderer Sync Objects...")
    vk.vkDeviceWaitIdle(device)
    if not sync then return end

    for i = 0, frames_in_flight - 1 do
        vk.vkDestroySemaphore(device, sync.imageAvailable[i], nil);
        vk.vkDestroySemaphore(device, sync.renderFinished[i], nil);
        vk.vkDestroyFence(device, sync.inFlight[i], nil);
    end
end

return Renderer
