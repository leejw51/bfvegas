-- settings.lua - persistent user settings stored in data/info.json
local json = require("json")

local Settings = {}
Settings.path = "data/info.json"
Settings.data = {}

local function setEnv(name, value)
    local ok, ffi = pcall(require, "ffi")
    if not ok then return end
    pcall(ffi.cdef, "int setenv(const char *name, const char *value, int overwrite);")
    pcall(ffi.cdef, "int _putenv_s(const char *name, const char *value);")
    local okCall = pcall(function() ffi.C.setenv(name, value, 1) end)
    if not okCall then
        pcall(function() ffi.C._putenv_s(name, value) end)
    end
end

function Settings.load()
    local f = io.open(Settings.path, "r")
    if not f then return end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" then
        Settings.data = data
    end
    Settings.apply()
end

function Settings.apply()
    local k = Settings.data.grok_api_key
    if type(k) == "string" and #k > 0 then
        setEnv("GROK_API_KEY", k)
    end
end

function Settings.save()
    os.execute("mkdir -p data")
    local f, err = io.open(Settings.path, "w")
    if not f then return false, err or "cannot open info.json" end
    f:write(json.encode(Settings.data))
    f:close()
    Settings.apply()
    return true
end

function Settings.getGrokKey()
    return Settings.data.grok_api_key or ""
end

function Settings.setGrokKey(k)
    Settings.data.grok_api_key = k or ""
end

return Settings
