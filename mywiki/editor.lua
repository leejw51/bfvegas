-- editor.lua - markdown text editor panel for the selected node
local Render = require("render")
local Graph = require("graph")
local E = require("easing")

local Editor = {}

Editor.open = false
Editor.node = nil
Editor.mode = "body"
Editor.text = ""
Editor.cursor = 0
Editor.scroll = 0
Editor.cursorBlink = 0
Editor.anim = E.tween(0, 0, 0.35, E.outBack)
Editor.wrapWidth = 0
Editor.desiredCol = nil

local function isContByte(b) return b and b >= 128 and b < 192 end

local function nextCharPos(text, p)
    p = p + 1
    while p < #text and isContByte(text:byte(p + 1)) do p = p + 1 end
    return p
end

local function rowColAt(text, cursor, font, tw)
    local before = text:sub(1, cursor)
    if before == "" then return 0, 0 end
    local endsNl = before:sub(-1) == "\n"
    local _, wrapped = font:getWrap(before, tw)
    if endsNl then return #wrapped, 0 end
    local last = wrapped[#wrapped] or ""
    return #wrapped - 1, font:getWidth(last)
end

local function findCursorAt(text, targetRow, targetX, font, tw)
    local best, bestDiff = nil, math.huge
    local p = 0
    while p <= #text do
        local r, x = rowColAt(text, p, font, tw)
        if r == targetRow then
            local d = math.abs(x - targetX)
            if d < bestDiff then bestDiff = d; best = p end
        elseif r > targetRow then
            break
        end
        if p == #text then break end
        p = nextCharPos(text, p)
    end
    return best
end

function Editor.openFor(node, mode)
    Editor.open = true
    Editor.node = node
    Editor.mode = mode or "body"
    Editor.text = (mode == "title") and node.title or node.body
    Editor.cursor = #Editor.text
    Editor.cursorBlink = 0
    Editor.anim:reset(0, 1)
    love.keyboard.setKeyRepeat(true)
end

function Editor.close(save)
    if save and Editor.node then
        if Editor.mode == "title" then
            local t = Editor.text:gsub("\n", " ")
            if #t == 0 then t = "Untitled" end
            Editor.node.title = t
        else
            Editor.node.body = Editor.text
        end
        Graph.save(Editor.node)
    end
    Editor.open = false
    Editor.node = nil
    love.keyboard.setKeyRepeat(false)
end

function Editor.update(dt)
    Editor.cursorBlink = (Editor.cursorBlink + dt) % 1.0
    Editor.anim:update(dt)
end

function Editor.textinput(t)
    if not Editor.open then return end
    Editor.text = Editor.text:sub(1, Editor.cursor) .. t .. Editor.text:sub(Editor.cursor + 1)
    Editor.cursor = Editor.cursor + #t
    Editor.desiredCol = nil
end

function Editor.keypressed(key)
    if not Editor.open then return end
    if key == "escape" then
        Editor.close(true)
        return true
    elseif key == "backspace" then
        if Editor.cursor > 0 then
            -- handle utf-8 byte step
            local i = Editor.cursor
            while i > 1 and (Editor.text:byte(i) and Editor.text:byte(i) >= 128 and Editor.text:byte(i) < 192) do
                i = i - 1
            end
            Editor.text = Editor.text:sub(1, i - 1) .. Editor.text:sub(Editor.cursor + 1)
            Editor.cursor = i - 1
        end
    elseif key == "return" then
        if Editor.mode == "title" then
            Editor.close(true)
        else
            Editor.text = Editor.text:sub(1, Editor.cursor) .. "\n" .. Editor.text:sub(Editor.cursor + 1)
            Editor.cursor = Editor.cursor + 1
        end
    elseif key == "left" then
        if Editor.cursor > 0 then
            local i = Editor.cursor
            while i > 1 and isContByte(Editor.text:byte(i)) do i = i - 1 end
            Editor.cursor = i - 1
        end
        Editor.desiredCol = nil
    elseif key == "right" then
        if Editor.cursor < #Editor.text then
            Editor.cursor = nextCharPos(Editor.text, Editor.cursor)
        end
        Editor.desiredCol = nil
    elseif key == "home" then
        Editor.cursor = 0
        Editor.desiredCol = nil
    elseif key == "end" then
        Editor.cursor = #Editor.text
        Editor.desiredCol = nil
    elseif key == "up" or key == "down" then
        local font = Render.font("body")
        local tw = Editor.wrapWidth
        if tw > 0 then
            local row, col = rowColAt(Editor.text, Editor.cursor, font, tw)
            if not Editor.desiredCol then Editor.desiredCol = col end
            local target = row + (key == "up" and -1 or 1)
            if target < 0 then
                Editor.cursor = 0
            else
                local p = findCursorAt(Editor.text, target, Editor.desiredCol, font, tw)
                if p then Editor.cursor = p
                elseif key == "down" then Editor.cursor = #Editor.text end
            end
        end
    end
    return true
end

function Editor.draw(w, h)
    if not Editor.open then return end
    local a = Editor.anim.value
    -- dim background
    love.graphics.setColor(0, 0, 0, 0.55 * math.min(1, a))
    love.graphics.rectangle("fill", 0, 0, w, h)

    local pw, ph = math.min(720, w - 80), math.min(520, h - 100)
    local cx, cy = w/2, h/2
    local px, py = cx - pw/2 * a, cy - ph/2 * a
    local dw, dh = pw * a, ph * a
    Render.card(px, py, dw, dh, 16, Render.colors.panel, Render.colors.panelEdge, true)
    if a < 0.85 then return end
    px, py = cx - pw/2, cy - ph/2

    -- header
    Render.setColor(Render.colors.accent)
    love.graphics.setFont(Render.font("medium"))
    local label = (Editor.mode == "title") and "Rename node" or ("Edit: " .. (Editor.node and Editor.node.title or ""))
    love.graphics.printf(label, px + 20, py + 16, pw - 40, "left")

    Render.setColor(Render.colors.textDim)
    love.graphics.setFont(Render.font("tiny"))
    love.graphics.printf("Esc to save & close   ·   Enter for newline", px + 20, py + 18, pw - 40, "right")

    -- divider
    love.graphics.setColor(Render.colors.panelEdge)
    love.graphics.setLineWidth(1)
    love.graphics.line(px + 20, py + 46, px + pw - 20, py + 46)

    -- text area
    local tx, ty = px + 24, py + 60
    local tw, th = pw - 48, ph - 80
    Editor.wrapWidth = tw
    love.graphics.setScissor(tx, ty, tw, th)

    local font = Render.font("body")
    love.graphics.setFont(font)
    local lineH = font:getHeight()

    local row, colX = rowColAt(Editor.text, Editor.cursor, font, tw)

    -- auto-scroll so cursor stays in view
    local cursorY = row * lineH
    if cursorY - Editor.scroll < 0 then
        Editor.scroll = cursorY
    elseif cursorY - Editor.scroll > th - lineH then
        Editor.scroll = cursorY - (th - lineH)
    end

    Render.setColor(Render.colors.text)
    love.graphics.printf(Editor.text, tx, ty - Editor.scroll, tw, "left")

    if Editor.cursorBlink < 0.55 then
        local cxp = tx + colX
        local cyp = ty + cursorY - Editor.scroll
        Render.setColor(Render.colors.accent)
        love.graphics.setLineWidth(2)
        love.graphics.line(cxp, cyp, cxp, cyp + lineH)
    end

    love.graphics.setScissor()
end

return Editor
