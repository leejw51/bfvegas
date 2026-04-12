-- ai.lua - bridge to libmywiki_ai (Rust cdylib) via LuaJIT FFI.
-- The blocking HTTPS calls happen on a love.thread worker so the main loop
-- never stalls. Results are pushed back through a channel and consumed in
-- AI.update() once per frame.
local AI = {}
AI.busy = false
AI.callback = nil
AI.thread = nil
AI.outChannel = love.thread.getChannel("ai_out")
AI.lastError = nil

-- Probe FFI + library availability up front so the AI button can give a
-- clear error instead of silently spinning.
local function probeLibrary()
    local ok_ffi, ffi = pcall(require, "ffi")
    if not ok_ffi then return false, "LuaJIT ffi not available" end
    ffi.cdef[[
        char* mywiki_ai_node(const char* question, const char* node_id);
        void  mywiki_ai_string_free(char* ptr);
        const char* mywiki_ai_version();
    ]]
    local lib = require("nativelib").load(ffi)
    if lib then
        local ver = ffi.string(lib.mywiki_ai_version())
        return true, lib, ver
    end
    return false, "libmywiki_ai not found (run `make` in rust/)"
end

AI.available, AI.lib_or_err, AI.version = probeLibrary()
if AI.available then
    print("[ai] libmywiki_ai loaded, version " .. tostring(AI.version))
else
    print("[ai] " .. tostring(AI.lib_or_err))
end

local THREAD_CODE = [=[
local question, nodeId = ...
local ffi = require("ffi")
ffi.cdef[[
    char* mywiki_ai_node(const char* question, const char* node_id);
    void  mywiki_ai_string_free(char* ptr);
]]
local lib = require("nativelib").load(ffi)
if not lib then
    love.thread.getChannel("ai_out"):push('{"ok":false,"error":"ffi load failed"}')
    return
end

local cstr = lib.mywiki_ai_node(question, nodeId)
if cstr == nil then
    love.thread.getChannel("ai_out"):push('{"ok":false,"error":"null result"}')
    return
end
local s = ffi.string(cstr)
lib.mywiki_ai_string_free(cstr)
love.thread.getChannel("ai_out"):push(s)
]=]

local json = require("json")

function AI.ask(question, nodeId, callback)
    if AI.busy then return false, "busy" end
    if not AI.available then return false, AI.lib_or_err end
    AI.busy = true
    AI.callback = callback
    AI.thread = love.thread.newThread(THREAD_CODE)
    AI.thread:start(question, nodeId)
    return true
end

function AI.update()
    if not AI.busy then return end
    local raw = AI.outChannel:pop()
    if not raw then
        if AI.thread and AI.thread:getError() then
            AI.busy = false
            local err = AI.thread:getError()
            print("[ai] thread error: " .. err)
            local cb = AI.callback; AI.callback = nil
            if cb then cb({ok=false, error="thread: " .. err}) end
        end
        return
    end
    AI.busy = false
    local ok, result = pcall(json.decode, raw)
    if not ok or type(result) ~= "table" then
        result = {ok=false, error="bad json from rust"}
    end
    local cb = AI.callback
    AI.callback = nil
    if cb then cb(result) end
end

return AI
