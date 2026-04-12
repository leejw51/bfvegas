-- nativelib.lua - resolve and ffi.load libmywiki_ai across run modes:
-- bare `love .`, packaged `.love` next to the dylib, and fused .app/.exe
-- where the lib lives in Contents/Frameworks (macOS) or next to the binary.
local M = {}

local function candidates()
    local list = {
        "./libmywiki_ai.so", "libmywiki_ai.so",
        "./libmywiki_ai.dylib", "libmywiki_ai.dylib",
        "./mywiki_ai.dll", "mywiki_ai.dll",
    }
    if love and love.filesystem and love.filesystem.getSourceBaseDirectory then
        local base = love.filesystem.getSourceBaseDirectory()
        if base and #base > 0 then
            local names = {
                "libmywiki_ai.dylib", "libmywiki_ai.so", "mywiki_ai.dll",
            }
            for _, n in ipairs(names) do
                list[#list+1] = base .. "/" .. n
                list[#list+1] = base .. "/../Frameworks/" .. n
                list[#list+1] = base .. "/../Resources/" .. n
            end
        end
    end
    return list
end

function M.load(ffi)
    for _, p in ipairs(candidates()) do
        local ok, lib = pcall(ffi.load, p)
        if ok then return lib, p end
    end
    return nil, "libmywiki_ai not found"
end

-- Returned as a string so love.thread workers (which can't `require` upvalues
-- from the main state) can `loadstring` the same resolver inline.
M.LOADER_SRC = [=[
local ffi = require("ffi")
local function candidates()
    local list = {
        "./libmywiki_ai.so", "libmywiki_ai.so",
        "./libmywiki_ai.dylib", "libmywiki_ai.dylib",
        "./mywiki_ai.dll", "mywiki_ai.dll",
    }
    if love and love.filesystem and love.filesystem.getSourceBaseDirectory then
        local base = love.filesystem.getSourceBaseDirectory()
        if base and #base > 0 then
            local names = { "libmywiki_ai.dylib", "libmywiki_ai.so", "mywiki_ai.dll" }
            for _, n in ipairs(names) do
                list[#list+1] = base .. "/" .. n
                list[#list+1] = base .. "/../Frameworks/" .. n
                list[#list+1] = base .. "/../Resources/" .. n
            end
        end
    end
    return list
end
for _, p in ipairs(candidates()) do
    local ok, lib = pcall(ffi.load, p)
    if ok then return lib end
end
return nil
]=]

return M
