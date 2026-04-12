-- json.lua - tiny JSON encoder/decoder (objects, arrays, strings, numbers,
-- booleans, null). Sufficient for the Grok API request/response shapes.
local json = {}

local escape_map = {
    ['"'] = '\\"', ['\\'] = '\\\\',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    ['\b'] = '\\b', ['\f'] = '\\f',
}

local function encode_string(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        return escape_map[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

local encode
encode = function(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then return tostring(v)
    elseif t == "string" then return encode_string(v)
    elseif t == "table" then
        local n, count = 0, 0
        for _ in pairs(v) do count = count + 1 end
        for _ in ipairs(v) do n = n + 1 end
        if n == count and n > 0 then
            local parts = {}
            for i = 1, n do parts[i] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        elseif count == 0 then
            return "[]"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts+1] = encode_string(tostring(k)) .. ":" .. encode(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    error("cannot encode " .. t)
end
json.encode = encode

-- decoder
local pos, str

local function skip_ws()
    while pos <= #str do
        local c = str:byte(pos)
        if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1
        else break end
    end
end

local parse_value

local function parse_string()
    pos = pos + 1
    local out = {}
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c == '"' then pos = pos + 1; return table.concat(out)
        elseif c == "\\" then
            local nc = str:sub(pos+1, pos+1)
            if nc == "n" then out[#out+1] = "\n"; pos = pos + 2
            elseif nc == "t" then out[#out+1] = "\t"; pos = pos + 2
            elseif nc == "r" then out[#out+1] = "\r"; pos = pos + 2
            elseif nc == "b" then out[#out+1] = "\b"; pos = pos + 2
            elseif nc == "f" then out[#out+1] = "\f"; pos = pos + 2
            elseif nc == '"' then out[#out+1] = '"'; pos = pos + 2
            elseif nc == "\\" then out[#out+1] = "\\"; pos = pos + 2
            elseif nc == "/" then out[#out+1] = "/"; pos = pos + 2
            elseif nc == "u" then
                local hex = str:sub(pos+2, pos+5)
                local code = tonumber(hex, 16) or 0
                if code < 0x80 then
                    out[#out+1] = string.char(code)
                elseif code < 0x800 then
                    out[#out+1] = string.char(0xC0 + math.floor(code/0x40), 0x80 + (code % 0x40))
                else
                    out[#out+1] = string.char(
                        0xE0 + math.floor(code/0x1000),
                        0x80 + math.floor(code/0x40) % 0x40,
                        0x80 + (code % 0x40))
                end
                pos = pos + 6
            else
                pos = pos + 2
            end
        else
            out[#out+1] = c
            pos = pos + 1
        end
    end
    error("unterminated string")
end

local function parse_number()
    local s = pos
    while pos <= #str do
        local c = str:sub(pos, pos)
        if c:match("[%-%+%d%.eE]") then pos = pos + 1 else break end
    end
    return tonumber(str:sub(s, pos - 1))
end

local function parse_object()
    pos = pos + 1
    local obj = {}
    skip_ws()
    if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
    while true do
        skip_ws()
        local k = parse_string()
        skip_ws()
        if str:sub(pos, pos) ~= ":" then error("expected :") end
        pos = pos + 1
        obj[k] = parse_value()
        skip_ws()
        local c = str:sub(pos, pos)
        if c == "," then pos = pos + 1
        elseif c == "}" then pos = pos + 1; return obj
        else error("expected , or }") end
    end
end

local function parse_array()
    pos = pos + 1
    local arr = {}
    skip_ws()
    if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
    while true do
        arr[#arr+1] = parse_value()
        skip_ws()
        local c = str:sub(pos, pos)
        if c == "," then pos = pos + 1
        elseif c == "]" then pos = pos + 1; return arr
        else error("expected , or ]") end
    end
end

parse_value = function()
    skip_ws()
    local c = str:sub(pos, pos)
    if c == '"' then return parse_string()
    elseif c == "{" then return parse_object()
    elseif c == "[" then return parse_array()
    elseif c == "t" then pos = pos + 4; return true
    elseif c == "f" then pos = pos + 5; return false
    elseif c == "n" then pos = pos + 4; return nil
    else return parse_number() end
end

function json.decode(s)
    str = s
    pos = 1
    return parse_value()
end

return json
