-- main.lua - MyWiki: visual AI knowledge mindmap built with LOVE2D
local Render  = require("render")
local Graph   = require("graph")
local Mindmap = require("mindmap")
local Editor  = require("editor")
local Bot     = require("bot")
local UI      = require("ui")
local Settings = require("settings")
local AI      = require("ai")
local AIUI    = require("aiui")

local clearConfirmTimer = 0

function love.load()
    love.math.setRandomSeed(os.time())
    Settings.load()
    Render.init()
    Graph.load()
    Mindmap.init()
    Bot.init()
    UI.init()
    UI.layout(love.graphics.getWidth())
    love.graphics.setBackgroundColor(Render.colors.bg)
end

function love.resize(w, h)
    UI.layout(w)
end

function love.update(dt)
    dt = math.min(dt, 1/30)
    local mx, my = love.mouse.getPosition()
    if clearConfirmTimer > 0 then clearConfirmTimer = clearConfirmTimer - dt end
    Mindmap.update(dt)
    Bot.update(dt)
    Editor.update(dt)
    AI.update()
    AIUI.update(dt)
    UI.update(dt, mx, my)
    Bot.x = love.graphics.getWidth() - 100
    Bot.y = love.graphics.getHeight() - 110
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    Mindmap.draw(w, h)

    local status
    if Mindmap.selected then
        status = "Selected: " .. Mindmap.selected.title .. "  ·  " .. #Graph.children(Mindmap.selected.id) .. " children  ·  total nodes: " .. #Graph.order
    else
        status = "No selection  ·  total nodes: " .. #Graph.order
    end
    UI.draw(w, h, status)

    Bot.draw()
    Editor.draw(w, h)
    AIUI.draw(w, h)
end

local function addNodeAtCenter()
    local w, h = love.graphics.getDimensions()
    local wx, wy = Mindmap.screenToWorld(w/2, h/2, w, h)
    local pid = Mindmap.selected and Mindmap.selected.id or nil
    Mindmap.selected = Graph.create("New idea", pid, wx, wy)
    Bot.say("Idea added! Press Tab to rename.", 4)
end

local function doAction(action)
    if action == "addNode" then addNodeAtCenter()
    elseif action == "edit" then
        if Mindmap.selected then Editor.openFor(Mindmap.selected, "body")
        else Bot.say("Select a node first.", 3) end
    elseif action == "delete" then Mindmap.deleteSelected()
    elseif action == "center" then Mindmap.centerOnSelected()
    elseif action == "save" then Graph.saveAll(); Bot.say("Saved everything to data/", 3)
    elseif action == "clearAll" then
        if clearConfirmTimer > 0 then
            Graph.clearAll()
            Mindmap.selected = nil
            Mindmap.anims = {}
            Graph.load()
            Mindmap.init()
            Bot.say("All cleared. Fresh start!", 4)
            clearConfirmTimer = 0
        else
            clearConfirmTimer = 3
            Bot.say("Click Clear All again to confirm wiping everything.", 3)
        end
    elseif action == "ai" then
        if not AI.available then
            Bot.say("AI lib missing: " .. tostring(AI.lib_or_err), 6)
        else
            AIUI.openPrompt()
        end
    elseif action == "view" then
        if Mindmap.selected then AIUI.openView(Mindmap.selected)
        else Bot.say("Select a node to view.", 3) end
    elseif action == "export" then AIUI.openExport()
    elseif action == "setup" then AIUI.openSetup()
    elseif action == "tip" then Bot.nextTip()
    end
end

function love.mousepressed(x, y, button)
    if Editor.open then return end
    if AIUI.isOpen() then
        if AIUI.mode == "view" then
            if AIUI.mousepressed(x, y) then return end
            AIUI.close()
        elseif AIUI.mode == "export" then
            AIUI.mousepressed(x, y)
        elseif AIUI.mode == "setup" then
            AIUI.mousepressed(x, y)
        elseif AIUI.mode == "loading" then
            AIUI.close()
        end
        return
    end
    local action = UI.click(x, y)
    if action then doAction(action); return end
    local w, h = love.graphics.getDimensions()
    local result = Mindmap.mousepressed(x, y, button, w, h)
    if result == "edit" and Mindmap.selected then
        Editor.openFor(Mindmap.selected, "body")
    end
end

function love.mousereleased(x, y, button)
    if Editor.open then return end
    Mindmap.mousereleased(x, y, button)
end

function love.mousemoved(x, y, dx, dy)
    if Editor.open then return end
    local w, h = love.graphics.getDimensions()
    Mindmap.mousemoved(x, y, dx, dy, w, h)
end

function love.wheelmoved(dx, dy)
    if Editor.open then return end
    if AIUI.wheelmoved(dy) then return end
    Mindmap.wheelmoved(dx, dy)
end

function love.textinput(t)
    if Editor.open then Editor.textinput(t); return end
    if AIUI.isOpen() then AIUI.textinput(t) end
end

function love.keypressed(key)
    if AIUI.isOpen() then
        AIUI.keypressed(key, Mindmap)
        return
    end
    if Editor.open then
        Editor.keypressed(key)
        if not Editor.open and Editor.node == nil then
            Bot.say("Saved!", 2)
        end
        return
    end
    if key == "escape" then love.event.quit(); return end
    if key == "f" or key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen())
        UI.layout(love.graphics.getWidth())
        return
    end
    if key == "e" then doAction("edit"); return end
    if key == "delete" or key == "backspace" then doAction("delete"); return end
    if key == "s" then doAction("save"); return end
    if key == "space" then doAction("tip"); return end
    if key == "c" then doAction("center"); return end
    if key == "n" then doAction("addNode"); return end
    if key == "=" or key == "kp+" then Mindmap.zoomIn(); return end
    if key == "-" or key == "kp-" then Mindmap.zoomOut(); return end
    if key == "tab" then
        if Mindmap.selected then Editor.openFor(Mindmap.selected, "title") end
        return
    end
    -- arrow nav: pick nearest neighbor in direction
    if key == "left" or key == "right" or key == "up" or key == "down" then
        if Mindmap.selected then
            local cur = Mindmap.selected
            local best, bestD = nil, math.huge
            for _, n in pairs(Graph.nodes) do
                if n ~= cur then
                    local dx, dy = n.x - cur.x, n.y - cur.y
                    local ok = (key == "left" and dx < -10 and math.abs(dy) < math.abs(dx))
                            or (key == "right" and dx > 10 and math.abs(dy) < math.abs(dx))
                            or (key == "up" and dy < -10 and math.abs(dx) < math.abs(dy))
                            or (key == "down" and dy > 10 and math.abs(dx) < math.abs(dy))
                    if ok then
                        local d = dx*dx + dy*dy
                        if d < bestD then bestD = d; best = n end
                    end
                end
            end
            if best then Mindmap.selected = best end
        end
    end
end
