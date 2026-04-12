-- bot.lua - friendly AI mascot with sprite + animated speech bubble
local Render = require("render")
local E      = require("easing")

local Bot = {}

Bot.x = 1180
Bot.y = 600
Bot.t = 0
Bot.message = ""
Bot.messageTimer = 0
Bot.bubbleAlpha = E.tween(0, 0, 0.3, E.outCubic)
Bot.entrance = E.tween(0, 1, 0.9, E.outBack)
Bot.tipIndex = 1
Bot.tips = {
    "Click empty space to drop a new idea!",
    "Drag a node to move it around.",
    "Double-click a node to spawn a child.",
    "Press E to edit the selected node.",
    "Press Delete to remove a node + its branch.",
    "Scroll to zoom, middle-drag to pan.",
    "Hit S to save everything to disk.",
    "Press Tab to rename the selected node.",
}

function Bot.init()
    Bot.say("Hi! I'm Wiki, your idea companion.")
end

function Bot.say(msg, duration)
    Bot.message = msg
    Bot.messageTimer = duration or 5
    Bot.bubbleAlpha:reset(0, 1)
end

function Bot.update(dt)
    Bot.t = Bot.t + dt
    Bot.entrance:update(dt)
    Bot.bubbleAlpha:update(dt)
    if Bot.messageTimer > 0 then
        Bot.messageTimer = Bot.messageTimer - dt
        if Bot.messageTimer <= 0.4 and Bot.bubbleAlpha.to ~= 0 then
            Bot.bubbleAlpha:reset(Bot.bubbleAlpha.value, 0)
        end
    elseif Bot.message ~= "" then
        if love.math.random() < dt * 0.12 then
            Bot.tipIndex = (Bot.tipIndex % #Bot.tips) + 1
            Bot.say(Bot.tips[Bot.tipIndex], 6)
        end
    end
end

function Bot.nextTip()
    Bot.tipIndex = (Bot.tipIndex % #Bot.tips) + 1
    Bot.say(Bot.tips[Bot.tipIndex], 6)
end

local function drawVectorBot(cx, cy, scale)
    local s = scale
    Render.glow(cx, cy, 38 * s, Render.colors.accent, 5)
    love.graphics.setColor(0.55, 0.70, 0.95)
    love.graphics.setLineWidth(3 * s)
    love.graphics.line(cx, cy - 38*s, cx, cy - 56*s)
    love.graphics.setColor(1.0, 0.78, 0.35)
    love.graphics.circle("fill", cx, cy - 60*s, 5*s)
    love.graphics.setColor(0.92, 0.95, 1.00)
    love.graphics.rectangle("fill", cx - 36*s, cy - 38*s, 72*s, 60*s, 18*s, 18*s)
    love.graphics.setColor(0.55, 0.70, 0.95)
    love.graphics.setLineWidth(3 * s)
    love.graphics.rectangle("line", cx - 36*s, cy - 38*s, 72*s, 60*s, 18*s, 18*s)
    love.graphics.setColor(0.06, 0.10, 0.18)
    love.graphics.rectangle("fill", cx - 26*s, cy - 28*s, 52*s, 38*s, 10*s, 10*s)
    local blink = (math.sin(Bot.t * 1.3) > 0.95) and 0.2 or 1.0
    love.graphics.setColor(0.40, 0.92, 1.00)
    love.graphics.ellipse("fill", cx - 12*s, cy - 12*s, 5*s, 6*s * blink)
    love.graphics.ellipse("fill", cx + 12*s, cy - 12*s, 5*s, 6*s * blink)
    love.graphics.setLineWidth(2 * s)
    love.graphics.setColor(0.40, 0.92, 1.00)
    love.graphics.arc("line", "open", cx, cy - 2*s, 9*s, 0.15, math.pi - 0.15)
    love.graphics.setColor(0.78, 0.85, 1.00)
    love.graphics.rectangle("fill", cx - 28*s, cy + 24*s, 56*s, 22*s, 8*s, 8*s)
end

function Bot.draw()
    local entry = Bot.entrance.value
    local bob = math.sin(Bot.t * 2) * 4
    local cx = Bot.x + (1 - entry) * 200
    local cy = Bot.y + bob - (1 - entry) * 20

    -- speech bubble
    local alpha = Bot.bubbleAlpha.value * entry
    if Bot.message ~= "" and alpha > 0.01 then
        local font = Render.font("small")
        love.graphics.setFont(font)
        local lines = Render.wrap(Bot.message, font, 230)
        local lineH = font:getHeight() + 2
        local h = #lines * lineH + 20
        local w = 260
        local liftIn = (1 - alpha) * 12
        local bx, by = cx - w - 10, cy - h - 30 + liftIn

        love.graphics.setColor(0, 0, 0, 0.55 * alpha)
        love.graphics.rectangle("fill", bx + 5, by + 7, w, h, 14, 14)

        love.graphics.setColor(Render.colors.panel[1], Render.colors.panel[2], Render.colors.panel[3], 0.94 * alpha)
        love.graphics.rectangle("fill", bx, by, w, h, 14, 14)

        love.graphics.setColor(Render.colors.panelEdge[1], Render.colors.panelEdge[2], Render.colors.panelEdge[3], 0.85 * alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", bx, by, w, h, 14, 14)

        love.graphics.setColor(Render.colors.text[1], Render.colors.text[2], Render.colors.text[3], alpha)
        for i, line in ipairs(lines) do
            love.graphics.print(line, bx + 14, by + 10 + (i-1)*lineH)
        end
        -- tail triangle
        love.graphics.setColor(Render.colors.panel[1], Render.colors.panel[2], Render.colors.panel[3], 0.94 * alpha)
        love.graphics.polygon("fill", bx + w - 30, by + h, bx + w - 8, by + h + 16, bx + w - 12, by + h)
    end

    -- bot sprite or vector fallback
    local img = Render.image("bot")
    if img then
        local iw, ih = img:getDimensions()
        local target = 150
        local s = target / math.max(iw, ih)
        s = s * (0.92 + 0.05 * math.sin(Bot.t * 2.2)) -- subtle breathe
        Render.glow(cx, cy, 60, Render.colors.accent, 5)
        love.graphics.setColor(1, 1, 1, entry)
        love.graphics.draw(img, cx, cy, math.sin(Bot.t * 1.5) * 0.03, s, s, iw/2, ih/2)
    else
        drawVectorBot(cx, cy, entry)
    end
end

return Bot
