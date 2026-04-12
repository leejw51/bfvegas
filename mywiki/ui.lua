-- ui.lua - top toolbar (logo + buttons) and bottom hint bar
local Render = require("render")
local E      = require("easing")

local UI = {}

UI.buttons = {}
UI.hover = nil
UI.t = 0

local function btn(label, x, y, w, h, action)
    return {
        label = label, x = x, y = y, w = w, h = h, action = action,
        scale = E.tween(1, 1, 0.18, E.outCubic),
    }
end

function UI.init() end

UI.titleRight = 150

function UI.layout(w)
    local oldHover = {}
    for _, b in ipairs(UI.buttons) do oldHover[b.action] = b.scale.value end
    local specs = {
        {"+ Node",     92, "addNode"},
        {"Edit",       92, "edit"},
        {"Delete",    100, "delete"},
        {"Center",    100, "center"},
        {"Save",       92, "save"},
        {"AI",         72, "ai"},
        {"View",       86, "view"},
        {"Export",     92, "export"},
        {"Setup",      86, "setup"},
        {"Clear All", 110, "clearAll"},
    }
    UI.buttons = {}
    local gap, x = 8, UI.titleRight
    for _, s in ipairs(specs) do
        table.insert(UI.buttons, btn(s[1], x, 16, s[2], 34, s[3]))
        x = x + s[2] + gap
    end
    table.insert(UI.buttons, btn("? Tip", w - 96, 16, 80, 34, "tip"))
    for _, b in ipairs(UI.buttons) do
        if oldHover[b.action] then b.scale.value = oldHover[b.action] end
    end
end

function UI.update(dt, mx, my)
    UI.t = UI.t + dt
    UI.hover = nil
    for _, b in ipairs(UI.buttons) do
        local h = mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h
        if h then UI.hover = b.action end
        local target = h and 1.08 or 1.0
        if math.abs(b.scale.value - target) > 0.001 then
            b.scale:reset(b.scale.value, target)
        end
        b.scale:update(dt)
    end
end

function UI.draw(w, h, status)
    -- top bar
    Render.card(8, 6, w - 16, 56, 14, Render.colors.panel, Render.colors.panelEdge, true)

    -- logo + title
    local logo = Render.image("logo")
    if logo then
        local lw, lh = logo:getDimensions()
        local s = 44 / math.max(lw, lh)
        local rot = math.sin(UI.t * 1.2) * 0.04
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(logo, 42, 34, rot, s, s, lw/2, lh/2)
    else
        Render.setColor(Render.colors.accent)
        love.graphics.circle("fill", 42, 34, 14)
    end
    Render.setColor(Render.colors.text)
    love.graphics.setFont(Render.font("medium"))
    love.graphics.print("MyWiki", 70, 22)

    -- buttons (animated scale)
    for _, b in ipairs(UI.buttons) do
        local s = b.scale.value
        local cx, cy = b.x + b.w/2, b.y + b.h/2
        local dw, dh = b.w * s, b.h * s
        local x, y = cx - dw/2, cy - dh/2
        local hovered = (UI.hover == b.action)
        local fill = hovered and {0.20, 0.30, 0.50, 0.96} or {0.13, 0.17, 0.26, 0.94}
        Render.card(x, y, dw, dh, 9, fill, Render.colors.panelEdge, false)
        if hovered then
            love.graphics.setColor(Render.colors.accent[1], Render.colors.accent[2], Render.colors.accent[3], 0.25)
            love.graphics.rectangle("fill", x, y, dw, dh, 9, 9)
        end
        Render.setColor(Render.colors.text)
        love.graphics.setFont(Render.font("small"))
        love.graphics.printf(b.label, x, y + 9, dw, "center")
    end

    -- bottom status
    Render.card(8, h - 32, w - 16, 26, 8, Render.colors.panel, Render.colors.panelEdge, false)
    Render.setColor(Render.colors.textDim)
    love.graphics.setFont(Render.font("tiny"))
    love.graphics.printf(status or "", 16, h - 26, w - 32, "left")
    love.graphics.printf("E edit · Tab rename · Del remove · S save · Space tip · F fullscreen", 16, h - 26, w - 32, "right")
end

function UI.click(sx, sy)
    for _, b in ipairs(UI.buttons) do
        if sx >= b.x and sx <= b.x + b.w and sy >= b.y and sy <= b.y + b.h then
            return b.action
        end
    end
end

return UI
