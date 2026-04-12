-- export.lua - bridge to libmywiki_ai's mywiki_export function.
local Graph = require("graph")
local json  = require("json")

local Export = {}
Export.lib = nil
Export.available = false
Export.lastError = nil

local function probe()
    local ok_ffi, ffi = pcall(require, "ffi")
    if not ok_ffi then return false, "no ffi" end
    pcall(ffi.cdef, [[
        char* mywiki_export(const char* format, const char* nodes_json, const char* out_path);
        void  mywiki_ai_string_free(char* ptr);
    ]])
    local lib = require("nativelib").load(ffi)
    if lib then return true, lib, ffi end
    return false, "libmywiki_ai not found"
end

Export.available, Export.lib, Export.ffi = probe()
if not Export.available then
    print("[export] " .. tostring(Export.lib))
    Export.lib = nil
end

local function nodesAsJson()
    local list = {}
    for _, id in ipairs(Graph.order) do
        local n = Graph.nodes[id]
        if n then
            list[#list+1] = {
                id = n.id,
                title = n.title or "",
                parent = n.parent or "",
                body = n.body or "",
                image = n.image or "",
            }
        end
    end
    return json.encode(list)
end

local EXTS = { md = "md", csv = "csv", jsonl = "jsonl", pdf = "pdf" }

function Export.run(format)
    if not Export.available or not Export.lib then
        return false, "library not loaded"
    end
    local ext = EXTS[format]
    if not ext then return false, "unknown format: " .. tostring(format) end
    os.execute('mkdir -p data/exports')
    local path = "data/exports/wiki." .. ext
    local nodes_json = nodesAsJson()
    local cstr = Export.lib.mywiki_export(format, nodes_json, path)
    if cstr == nil then return false, "null result" end
    local s = Export.ffi.string(cstr)
    Export.lib.mywiki_ai_string_free(cstr)
    local ok, result = pcall(json.decode, s)
    if not ok or type(result) ~= "table" then
        return false, "bad json: " .. s
    end
    if result.ok then
        return true, path, result.count
    end
    return false, result.error or "unknown"
end

return Export
