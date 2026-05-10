#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

// Engine Headers
#include "memory.h"
#include "control_board.h"

// LuaJIT Headers
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

// ========================================================
// CROSS-PLATFORM THREADING & SLEEP BRIDGE
// ========================================================
#if defined(_WIN32) || defined(_WIN64)
    #include <windows.h>
    typedef HANDLE vibe_thread_t;
    typedef CRITICAL_SECTION vibe_mutex_t;
    typedef CONDITION_VARIABLE vibe_cond_t;
    #define THREAD_FUNC DWORD WINAPI
    #define THREAD_RETURN_VAL 0
    #define SLEEP_MS(ms) Sleep(ms)
    static vibe_thread_t vibe_thread_start(DWORD (WINAPI *func)(LPVOID), void* arg) { return CreateThread(NULL, 0, func, arg, 0, NULL); }
    static void vibe_thread_join(vibe_thread_t thread) { WaitForSingleObject(thread, INFINITE); CloseHandle(thread); }
    static void vibe_mutex_init(vibe_mutex_t* m) { InitializeCriticalSection(m); }
    static void vibe_mutex_lock(vibe_mutex_t* m) { EnterCriticalSection(m); }
    static void vibe_mutex_unlock(vibe_mutex_t* m) { LeaveCriticalSection(m); }
    static void vibe_mutex_destroy(vibe_mutex_t* m) { DeleteCriticalSection(m); }
    static void vibe_cond_init(vibe_cond_t* cv) { InitializeConditionVariable(cv); }
    static void vibe_cond_wait(vibe_cond_t* cv, vibe_mutex_t* m) { SleepConditionVariableCS(cv, m, INFINITE); }
    static void vibe_cond_broadcast(vibe_cond_t* cv) { WakeAllConditionVariable(cv); }
    static void vibe_cond_destroy(vibe_cond_t* cv) { }
#else
    #include <pthread.h>
    #include <unistd.h>
    typedef pthread_t vibe_thread_t;
    typedef pthread_mutex_t vibe_mutex_t;
    typedef pthread_cond_t vibe_cond_t;
    #define THREAD_FUNC void*
    #define THREAD_RETURN_VAL NULL
    #define SLEEP_MS(ms) usleep((ms) * 1000)
    static vibe_thread_t vibe_thread_start(void* (*func)(void*), void* arg) { pthread_t thread; pthread_create(&thread, NULL, func, arg); return thread; }
    static void vibe_thread_join(vibe_thread_t thread) { pthread_join(thread, NULL); }
    static void vibe_mutex_init(vibe_mutex_t* m) { pthread_mutex_init(m, NULL); }
    static void vibe_mutex_lock(vibe_mutex_t* m) { pthread_mutex_lock(m); }
    static void vibe_mutex_unlock(vibe_mutex_t* m) { pthread_mutex_unlock(m); }
    static void vibe_mutex_destroy(vibe_mutex_t* m) { pthread_mutex_destroy(m); }
    static void vibe_cond_init(vibe_cond_t* cv) { pthread_cond_init(cv, NULL); }
    static void vibe_cond_wait(vibe_cond_t* cv, vibe_mutex_t* m) { pthread_cond_wait(cv, m); }
    static void vibe_cond_broadcast(vibe_cond_t* cv) { pthread_cond_broadcast(cv); }
    static void vibe_cond_destroy(vibe_cond_t* cv) { pthread_cond_destroy(cv); }
#endif

#define NUM_WORKERS 4

vibe_mutex_t g_worker_mutex;
vibe_cond_t  g_worker_cv_start;
vibe_cond_t  g_worker_cv_done;

int g_workers_active = 0;
int g_worker_sig = 0;
vibe_thread_t g_worker_threads[NUM_WORKERS];
vibe_thread_t g_lua_thread;

// ========================================================
// THE AVX2 WORKER LOOP (Threads 1-4)
// ========================================================
THREAD_FUNC worker_loop(void* arg) {
    while (1) {
        vibe_mutex_lock(&g_worker_mutex);
        while (g_worker_sig == 0) {
            vibe_cond_wait(&g_worker_cv_start, &g_worker_mutex);
        }

        if (g_worker_sig == 2) {
            vibe_mutex_unlock(&g_worker_mutex);
            break;
        }
        vibe_mutex_unlock(&g_worker_mutex);

        // --- SIMULATED AVX2 CRUNCH ZONE ---
        // In the real engine, this is where vmath_step_swarm_chunk executes.
        // We simulate work so the threads don't instantly return.
        SLEEP_MS(2);

        // --- WORKER DONE ---
        vibe_mutex_lock(&g_worker_mutex);
        g_workers_active--;
        if (g_workers_active == 0) {
            vibe_cond_broadcast(&g_worker_cv_done);
        }
        vibe_mutex_unlock(&g_worker_mutex);
    }
    return THREAD_RETURN_VAL;
}

// ========================================================
// LUA INTEGRATION SANCTUARY
// ========================================================
static int l_vibe_get_boards(lua_State* L) {
    void *telemetry_ptr, *control_ptr;
    vibe_get_boards(&telemetry_ptr, &control_ptr);

    char t_str[64], c_str[64];
    vibe_mem_ptr2str(telemetry_ptr, t_str, sizeof(t_str));
    vibe_mem_ptr2str(control_ptr, c_str, sizeof(c_str));

    lua_pushstring(L, t_str);
    lua_pushstring(L, c_str);
    return 2;
}

static int l_vibe_inject_vram(lua_State* L) {
    // 1. Grab the decimal string from Lua
    const char* ptr_str = luaL_checkstring(L, 1);

    // 2. Reconstruct the raw pointer from the decimal heist
    VramInjectionBoard* payload = (VramInjectionBoard*)(uintptr_t)strtoull(ptr_str, NULL, 10);

    if (payload) {
        vibe_mem_inject_vram(payload);
    } else {
        printf("\n[C-BRIDGE ERROR] VRAM Injection Payload string was invalid: %s\n", ptr_str);
    }
    return 0;
}
static const luaL_Reg engine_funcs[] = {
    {"get_boards",  l_vibe_get_boards},
    {"inject_vram", l_vibe_inject_vram}, // The Injection Hook
    {NULL, NULL}
};

static void register_lua_bridge(lua_State* L) {
    lua_newtable(L);
    luaL_setfuncs(L, engine_funcs, 0);
    lua_setglobal(L, "C_Bridge");
}

// ========================================================
// THE LUA CO-OVERLORD LOOP (Thread 5)
// ========================================================
THREAD_FUNC lua_co_overlord_loop(void* arg) {
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    register_lua_bridge(L);

    if (luaL_dofile(L, "main.lua") != LUA_OK) {
        printf("\n[LUA ERROR] %s\n", lua_tostring(L, -1));
    }

    lua_close(L);
    return THREAD_RETURN_VAL;
}

// ========================================================
// THE C-OVERLORD BOOTLOADER (Thread 0)
// ========================================================
int main(int argc, char** argv) {
    printf("[C-OVERLORD] Booting Headless VibeEngine...\n");

    // FIX: C no longer initializes memory here.
    // It waits for Lua to call C_Bridge.inject_vram().
    g_ControlBoard.core.is_running = 1; // Namespace Fix

    // 2. BOOT THE AVX2 THREAD POOL
    vibe_mutex_init(&g_worker_mutex);
    vibe_cond_init(&g_worker_cv_start);
    vibe_cond_init(&g_worker_cv_done);

    for (int i = 0; i < NUM_WORKERS; i++) {
        g_worker_threads[i] = vibe_thread_start(worker_loop, (void*)(intptr_t)i);
    }

    // 3. BOOT LUA CO-OVERLORD (Thread 5)
    g_lua_thread = vibe_thread_start(lua_co_overlord_loop, NULL);

    // 4. THE DRY-RUN AUDITOR
    vibe_audit_memory_state();
    printf("Starting Headless Loop. Press Ctrl+C to exit.\n\n");

    // ========================================================
    // THE C-OVERLORD LOOP
    // ========================================================
    while (g_ControlBoard.core.is_running) { // Namespace Fix

        // SURGICAL GUARD: Do not dispatch workers if memory isn't ready
        VibeMemoryMap* map = vibe_mem_get_map();
        if (!map->is_initialized) {
            // Heartbeat while waiting for Lua to finish Vulkan init
            printf("\r[C-OVERLORD] Waiting for VRAM Injection... ");
            fflush(stdout);
            SLEEP_MS(100);
            continue;
        }

        // --- 2. WAIT FOR AVX2 WORKERS TO FINISH ---
        vibe_mutex_lock(&g_worker_mutex);
        while (g_workers_active > 0) {
            vibe_cond_wait(&g_worker_cv_done, &g_worker_mutex);
        }
        g_worker_sig = 0;
        vibe_mutex_unlock(&g_worker_mutex);

        // --- 3. FLIP THE PHASES ---
        g_TelemetryBoard.current_c_phase = (g_TelemetryBoard.current_c_phase == 0) ? 1 : 0;

        // --- 4. TERMINAL HEARTBEAT ---
        char current_phase = g_TelemetryBoard.current_c_phase == 0 ? 'A' : 'B';
        printf("\r[C-OVERLORD] Crunching Phase: %c | Active Workers: 4   ", current_phase);
        fflush(stdout);

        // --- 5. SIMULATE 60FPS TIMING ---
        SLEEP_MS(16);
    }

    // ========================================================
    // TEARDOWN
    // ========================================================
    printf("\n[C-OVERLORD] Shutting down...\n");

    vibe_mutex_lock(&g_worker_mutex);
    g_worker_sig = 2;
    vibe_cond_broadcast(&g_worker_cv_start);
    vibe_mutex_unlock(&g_worker_mutex);

    for (int i = 0; i < NUM_WORKERS; i++) {
        vibe_thread_join(g_worker_threads[i]);
    }

    vibe_thread_join(g_lua_thread);
    vibe_mutex_destroy(&g_worker_mutex);
    vibe_cond_destroy(&g_worker_cv_start);
    vibe_cond_destroy(&g_worker_cv_done);
    vibe_mem_destroy();

    return 0;
}
