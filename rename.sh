# Define the pairs exactly as you want them
declare -A REPLACEMENTS=(
    ["vibe_ring_get_write_idx"]="vx_stream_acquire"
    ["vibe_ring_get_packet"]="vx_stream_packet"
    ["vibe_ring_submit"]="vx_stream_commit"
    ["vibe_ring_init_wsi"]="vx_stream_init"
    ["vibe_start_render_thread"]="vx_thread_start"
    ["vibe_kill_render_thread"]="vx_thread_kill"
    ["vibe_get_is_running"]="vx_core_is_running"
    ["vibe_trigger_shutdown"]="vx_core_shutdown"
    ["vibe_mark_lua_finished"]="vx_core_mark_finished"
    ["vibe_get_glfw_extensions"]="vx_sys_glfw_extensions"
    ["vibe_publish_vk_instance"]="vx_sys_publish_instance"
    ["vibe_get_vk_surface"]="vx_sys_get_surface"
    ["vibe_set_glfw_cmd"]="vx_sys_set_cmd"
    ["vibe_get_resize_flag"]="vx_sys_resize_flag"
    ["vibe_get_window_size"]="vx_sys_window_size"
    ["vibe_get_last_key"]="vx_input_last_key"
    ["vibe_get_wasd"]="vx_input_wasd"
    ["vibe_get_mouse_dx"]="vx_input_mouse_dx"
    ["vibe_get_mouse_dy"]="vx_input_mouse_dy"
    ["vibe_get_mouse_btn"]="vx_input_mouse_btn"
    ["vibe_get_spacebar"]="vx_input_spacebar"
    ["vibe_stream_positions"]="vx_math_stream_pos"
    ["vibe_inject_validation_layers"]="vx_sys_inject_validation"
    ["vibe_eject_validation_layers"]="vx_sys_eject_validation"
    ["vibe_record_commands"]="vx_record_commands"
    ["vibe_init_mailbox"]="vx_init_mailbox"
)

# Loop through all .c and .lua files and apply the exact word-boundary replacements
for file in *.c *.lua; do
    if [ -f "$file" ]; then
        for old in "${!REPLACEMENTS[@]}"; do
            new="${REPLACEMENTS[$old]}"
            sed -i "s/\b${old}\b/${new}/g" "$file"
        done
        echo "Processed $file"
    fi
done
