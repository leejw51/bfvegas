-- graph.lua - load/save wiki nodes as markdown files in data/
local Graph = {}

Graph.dataDir = "data"
Graph.nodes = {}     -- id -> node
Graph.order = {}     -- list of ids in load order

local function newId()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local s = ""
    for _ = 1, 8 do
        local i = love.math.random(1, #chars)
        s = s .. chars:sub(i, i)
    end
    return s
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- parse YAML-ish frontmatter (key: value, only flat strings/numbers)
local function parseFrontmatter(text)
    local meta, body = {}, text
    if text:sub(1, 3) == "---" then
        local close = text:find("\n---", 4, true)
        if close then
            local fm = text:sub(4, close - 1)
            body = text:sub(close + 5)
            for line in fm:gmatch("[^\n]+") do
                local k, v = line:match("^%s*([%w_]+)%s*:%s*(.*)$")
                if k then meta[k] = trim(v) end
            end
        end
    end
    return meta, trim(body)
end

local function serialize(node)
    local parent = node.parent or ""
    local image  = node.image or ""
    local body   = node.body or ""
    return string.format(
        "---\nid: %s\ntitle: %s\nparent: %s\nx: %.1f\ny: %.1f\ncolor: %d\nimage: %s\n---\n%s\n",
        node.id, node.title, parent, node.x, node.y, node.color, image, body
    )
end

function Graph.save(node)
    os.execute('mkdir -p "' .. Graph.dataDir .. '"')
    local path = Graph.dataDir .. "/" .. node.id .. ".md"
    local f, err = io.open(path, "w")
    if not f then print("save failed: " .. tostring(err)); return end
    f:write(serialize(node))
    f:close()
end

function Graph.saveAll()
    for _, n in pairs(Graph.nodes) do Graph.save(n) end
end

function Graph.delete(id)
    -- delete node + descendants
    local function collect(rootId, acc)
        acc[rootId] = true
        for cid, n in pairs(Graph.nodes) do
            if n.parent == rootId then collect(cid, acc) end
        end
    end
    local doomed = {}
    collect(id, doomed)
    for did in pairs(doomed) do
        os.remove(Graph.dataDir .. "/" .. did .. ".md")
        Graph.nodes[did] = nil
    end
    -- rebuild order
    local newOrder = {}
    for _, oid in ipairs(Graph.order) do
        if Graph.nodes[oid] then newOrder[#newOrder+1] = oid end
    end
    Graph.order = newOrder
end

function Graph.clearAll()
    for id in pairs(Graph.nodes) do
        os.remove(Graph.dataDir .. "/" .. id .. ".md")
    end
    Graph.nodes = {}
    Graph.order = {}
end

function Graph.create(title, parentId, x, y)
    local id = newId()
    while Graph.nodes[id] do id = newId() end
    local depth = 0
    local p = parentId
    while p and Graph.nodes[p] do depth = depth + 1; p = Graph.nodes[p].parent end
    local color = (depth % 7) + 1
    local node = {
        id = id,
        title = title or "New idea",
        parent = parentId,
        x = x or 0,
        y = y or 0,
        color = color,
        body = "# " .. (title or "New idea") .. "\n\nWrite your notes here...\n",
    }
    Graph.nodes[id] = node
    Graph.order[#Graph.order+1] = id
    Graph.save(node)
    return node
end

local function listMarkdown(dir)
    local out = {}
    -- prefer love.filesystem (reads from source dir); fall back to shell ls
    if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(dir) then
        for _, f in ipairs(love.filesystem.getDirectoryItems(dir)) do
            if f:sub(-3) == ".md" then out[#out+1] = f end
        end
        if #out > 0 then return out end
    end
    local p = io.popen('ls "' .. dir .. '" 2>/dev/null')
    if p then
        for line in p:lines() do
            if line:sub(-3) == ".md" then out[#out+1] = line end
        end
        p:close()
    end
    return out
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function Graph.load()
    Graph.nodes = {}
    Graph.order = {}
    os.execute('mkdir -p "' .. Graph.dataDir .. '"')
    local files = listMarkdown(Graph.dataDir)
    for _, f in ipairs(files) do
        if f:sub(-3) == ".md" then
            local text = readFile(Graph.dataDir .. "/" .. f)
            if text then
                local meta, body = parseFrontmatter(text)
                if meta.id then
                    local node = {
                        id = meta.id,
                        title = meta.title or "Untitled",
                        parent = (meta.parent ~= "" and meta.parent) or nil,
                        x = tonumber(meta.x) or 0,
                        y = tonumber(meta.y) or 0,
                        color = tonumber(meta.color) or 1,
                        image = (meta.image and meta.image ~= "" and meta.image) or nil,
                        body = body,
                    }
                    Graph.nodes[node.id] = node
                    Graph.order[#Graph.order+1] = node.id
                end
            end
        end
    end
    -- bootstrap if empty
    if #Graph.order == 0 then
        local root = Graph.create("AI Wiki", nil, 0, 0)
        Graph.create("Machine Learning", root.id, -260, -160)
        Graph.create("Neural Networks", root.id, 260, -160)
        Graph.create("LLMs", root.id, -260, 160)
        Graph.create("Agents", root.id, 260, 160)
    end
end

function Graph.children(id)
    local out = {}
    for _, n in pairs(Graph.nodes) do
        if n.parent == id then out[#out+1] = n end
    end
    return out
end

function Graph.root()
    for _, n in pairs(Graph.nodes) do
        if not n.parent then return n end
    end
    return Graph.nodes[Graph.order[1]]
end

return Graph
