-- mindmap.lua - viewport, drawing, animated interaction for the node graph
local Render = require("render")
local Graph  = require("graph")
local Bot    = require("bot")
local E      = require("easing")
local AI     = require("ai")
local AIUI   = require("aiui")

local Mindmap = {}

Mindmap.cam = { x = 0, y = 0, scale = 1 }
Mindmap.camTween = nil   -- {tx, ty, ts, t, dur}
Mindmap.selected = nil
Mindmap.dragging = nil
Mindmap.dragOffX = 0
Mindmap.dragOffY = 0
Mindmap.panning = false
Mindmap.lastClickTime = 0
Mindmap.lastClickId = nil
Mindmap.t = 0
Mindmap.particles = {}
Mindmap.anims = {}       -- nodeId -> {scale=tween, edge=tween}

local NODE_W = 190
local NODE_H = 70

-- ---- particle field ----
local function spawnParticle(w, h)
    return {
        x = love.math.random() * w,
        y = love.math.random() * h,
        r = 0.6 + love.math.random() * 1.6,
        vx = (love.math.random() - 0.5) * 6,
        vy = (love.math.random() - 0.5) * 4 - 4,
        a = 0.15 + love.math.random() * 0.45,
        hue = love.math.random() < 0.5 and Render.colors.accent or Render.colors.accent2,
    }
end

function Mindmap.init()
    local w, h = love.graphics.getDimensions()
    for _ = 1, 70 do
        Mindmap.particles[#Mindmap.particles+1] = spawnParticle(w, h)
    end
    -- seed anims for existing nodes
    for id, _ in pairs(Graph.nodes) do
        Mindmap.anims[id] = {
            scale = E.tween(0, 1, 0.55, E.outBack),
            edge  = E.tween(0, 1, 0.6, E.outCubic),
            pulse = 0,
        }
    end
end

function Mindmap.screenToWorld(sx, sy, w, h)
    return (sx - w/2) / Mindmap.cam.scale + Mindmap.cam.x,
           (sy - h/2) / Mindmap.cam.scale + Mindmap.cam.y
end

local function nodeAt(wx, wy)
    for i = #Graph.order, 1, -1 do
        local n = Graph.nodes[Graph.order[i]]
        if n then
            if wx >= n.x - NODE_W/2 and wx <= n.x + NODE_W/2
               and wy >= n.y - NODE_H/2 and wy <= n.y + NODE_H/2 then
                return n
            end
        end
    end
end

local function ensureAnim(id)
    if not Mindmap.anims[id] then
        Mindmap.anims[id] = {
            scale = E.tween(0, 1, 0.55, E.outBack),
            edge  = E.tween(0, 1, 0.6, E.outCubic),
            pulse = 0,
        }
    end
    return Mindmap.anims[id]
end

function Mindmap.update(dt)
    Mindmap.t = Mindmap.t + dt

    -- camera tween
    if Mindmap.camTween then
        local tw = Mindmap.camTween
        tw.t = tw.t + dt
        local k = math.min(1, tw.t / tw.dur)
        local e = E.inOutCubic(k)
        Mindmap.cam.x = tw.fx + (tw.tx - tw.fx) * e
        Mindmap.cam.y = tw.fy + (tw.ty - tw.fy) * e
        Mindmap.cam.scale = tw.fs + (tw.ts - tw.fs) * e
        if k >= 1 then Mindmap.camTween = nil end
    end

    -- node anims
    for _, a in pairs(Mindmap.anims) do
        a.scale:update(dt)
        a.edge:update(dt)
        a.pulse = (a.pulse or 0) + dt
    end

    -- particle field
    local w, h = love.graphics.getDimensions()
    for _, p in ipairs(Mindmap.particles) do
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        if p.y < -10 or p.x < -10 or p.x > w + 10 then
            p.x = love.math.random() * w
            p.y = h + 10
            p.vy = -3 - love.math.random() * 4
        end
    end
end

local function drawBackground(w, h)
    -- base
    Render.setColor(Render.colors.bg)
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- generated cosmic bg
    local bg = Render.image("bg")
    if bg then
        love.graphics.setColor(1, 1, 1, 0.85)
        local iw, ih = bg:getDimensions()
        local sx = w / iw
        local sy = h / ih
        local s = math.max(sx, sy)
        local dx = (w - iw * s) / 2
        local dy = (h - ih * s) / 2
        -- subtle parallax drift
        dx = dx + math.sin(Mindmap.t * 0.05) * 8
        dy = dy + math.cos(Mindmap.t * 0.07) * 6
        love.graphics.draw(bg, dx, dy, 0, s, s)
    end

    -- moving grid
    Render.setColor(Render.colors.bgGrid, 0.55)
    love.graphics.setLineWidth(1)
    local step = 60 * Mindmap.cam.scale
    local ox = (-Mindmap.cam.x * Mindmap.cam.scale + w/2) % step
    local oy = (-Mindmap.cam.y * Mindmap.cam.scale + h/2) % step
    for x = ox, w, step do love.graphics.line(x, 0, x, h) end
    for y = oy, h, step do love.graphics.line(0, y, w, y) end

    -- particles
    local particle = Render.image("particle")
    for _, p in ipairs(Mindmap.particles) do
        if particle then
            local pw = particle:getWidth()
            local s = (p.r * 12) / pw
            love.graphics.setColor(p.hue[1], p.hue[2], p.hue[3], p.a)
            love.graphics.draw(particle, p.x, p.y, 0, s, s, pw/2, particle:getHeight()/2)
        else
            love.graphics.setColor(p.hue[1], p.hue[2], p.hue[3], p.a)
            love.graphics.circle("fill", p.x, p.y, p.r)
        end
    end

    -- vignette
    for i = 1, 6 do
        love.graphics.setColor(0, 0, 0, 0.06)
        love.graphics.rectangle("line", i*4, i*4, w - i*8, h - i*8, 18, 18)
    end
end

local function drawNode(n, isSelected)
    local color = Render.nodePalette[n.color] or Render.nodePalette[1]
    local anim = ensureAnim(n.id)
    local s = anim.scale.value
    if s <= 0.001 then return end

    local nw, nh = NODE_W, NODE_H
    local pulse = isSelected and (1 + 0.04 * math.sin(Mindmap.t * 4)) or 1
    local drawW = nw * s * pulse
    local drawH = nh * s * pulse
    local x, y = n.x - drawW/2, n.y - drawH/2

    -- glow
    Render.glow(n.x, n.y, drawW * 0.46 * (isSelected and 1.2 or 1.0), color, isSelected and 7 or 4)

    -- card image (9-slice) or fallback
    local cardImg = Render.image("card")
    if cardImg then
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", x + 4, y + 8, drawW, drawH, 16, 16)
        love.graphics.setColor(1, 1, 1, 0.96)
        Render.nineSlice(cardImg, x, y, drawW, drawH, 28)
        -- color tint overlay
        love.graphics.setColor(color[1], color[2], color[3], 0.20)
        love.graphics.rectangle("fill", x, y, drawW, drawH, 14, 14)
    else
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", x + 4, y + 8, drawW, drawH, 14, 14)
        love.graphics.setColor(0.10 + color[1]*0.10, 0.12 + color[2]*0.10, 0.20 + color[3]*0.10, 0.96)
        love.graphics.rectangle("fill", x, y, drawW, drawH, 14, 14)
    end

    -- top accent bar
    love.graphics.setColor(color[1], color[2], color[3], 0.95)
    love.graphics.rectangle("fill", x + 8, y + 6, drawW - 16, 4, 2, 2)

    -- border
    if isSelected then
        love.graphics.setColor(color[1], color[2], color[3], 1)
        love.graphics.setLineWidth(3)
    else
        love.graphics.setColor(color[1], color[2], color[3], 0.55)
        love.graphics.setLineWidth(1.5)
    end
    love.graphics.rectangle("line", x, y, drawW, drawH, 14, 14)

    -- title
    local font = Render.font("medium")
    love.graphics.setFont(font)
    Render.setColor(Render.colors.text)
    local title = n.title
    local ok, w = pcall(font.getWidth, font, title)
    if not ok then
        title = title:gsub("[\128-\255]", "?")
        w = font:getWidth(title)
    end
    if w > drawW - 24 then
        local function trimOne(s)
            local i = #s
            while i > 1 and s:byte(i) and s:byte(i) >= 128 and s:byte(i) < 192 do
                i = i - 1
            end
            return s:sub(1, i - 1)
        end
        while #title > 4 and font:getWidth(title .. "…") > drawW - 24 do
            title = trimOne(title)
        end
        title = title .. "…"
    end
    love.graphics.printf(title, x + 12, y + drawH/2 - font:getHeight()/2 - 4, drawW - 24, "center")

    -- child count
    local kids = #Graph.children(n.id)
    if kids > 0 then
        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.printf(kids .. " ◦ branches", x + 12, y + drawH - 16, drawW - 24, "center")
    end
end

function Mindmap.draw(w, h)
    drawBackground(w, h)

    love.graphics.push()
    love.graphics.translate(w/2, h/2)
    love.graphics.scale(Mindmap.cam.scale)
    love.graphics.translate(-Mindmap.cam.x, -Mindmap.cam.y)

    -- edges first (animated draw-in + flowing dot)
    for _, n in pairs(Graph.nodes) do
        if n.parent and Graph.nodes[n.parent] then
            local p = Graph.nodes[n.parent]
            local color = Render.nodePalette[n.color] or Render.colors.edge
            local anim = ensureAnim(n.id)
            Render.connector(p.x, p.y, n.x, n.y, color, 3, anim.edge.value, Mindmap.t * 0.6)
        end
    end

    -- nodes
    for _, id in ipairs(Graph.order) do
        local n = Graph.nodes[id]
        if n then drawNode(n, Mindmap.selected == n) end
    end

    love.graphics.pop()
end

function Mindmap.mousepressed(sx, sy, button, w, h)
    local wx, wy = Mindmap.screenToWorld(sx, sy, w, h)
    if button == 3 then
        Mindmap.panning = true
        return
    end
    local hit = nodeAt(wx, wy)
    if button == 1 then
        if hit then
            local now = love.timer.getTime()
            if Mindmap.lastClickId == hit.id and (now - Mindmap.lastClickTime) < 0.35 then
                Mindmap.selected = hit
                Mindmap.lastClickId = nil
                if AI.available then
                    AIUI.openPrompt()
                    Bot.say("Ask the AI to grow this branch…", 4)
                else
                    Bot.say("AI lib missing: " .. tostring(AI.lib_or_err), 6)
                end
                return
            end
            Mindmap.lastClickTime = now
            Mindmap.lastClickId = hit.id
            Mindmap.selected = hit
            Mindmap.dragging = hit
            Mindmap.dragOffX = wx - hit.x
            Mindmap.dragOffY = wy - hit.y
        end
    elseif button == 2 then
        Mindmap.panning = true
        Mindmap.rmbHit = hit
        Mindmap.rmbDragged = false
    end
end

function Mindmap.mousereleased(sx, sy, button)
    if button == 1 and Mindmap.dragging then
        Graph.save(Mindmap.dragging)
        Mindmap.dragging = nil
    elseif button == 3 then
        Mindmap.panning = false
    elseif button == 2 then
        Mindmap.panning = false
        if not Mindmap.rmbDragged and Mindmap.rmbHit then
            local hit = Mindmap.rmbHit
            Mindmap.selected = hit
            Mindmap.camTween = {
                fx = Mindmap.cam.x, fy = Mindmap.cam.y, fs = Mindmap.cam.scale,
                tx = hit.x, ty = hit.y, ts = 1.1, t = 0, dur = 0.6,
            }
        end
        Mindmap.rmbHit = nil
        Mindmap.rmbDragged = false
    end
end

function Mindmap.mousemoved(sx, sy, dx, dy, w, h)
    if Mindmap.panning then
        if dx*dx + dy*dy > 4 then Mindmap.rmbDragged = true end
        Mindmap.cam.x = Mindmap.cam.x - dx / Mindmap.cam.scale
        Mindmap.cam.y = Mindmap.cam.y - dy / Mindmap.cam.scale
        return
    end
    if Mindmap.dragging then
        local wx, wy = Mindmap.screenToWorld(sx, sy, w, h)
        Mindmap.dragging.x = wx - Mindmap.dragOffX
        Mindmap.dragging.y = wy - Mindmap.dragOffY
    end
end

function Mindmap.wheelmoved(_, dy)
    Mindmap.zoomBy(1 + dy * 0.12)
end

function Mindmap.zoomBy(factor)
    local s = Mindmap.cam.scale * factor
    Mindmap.cam.scale = math.max(0.3, math.min(2.5, s))
end

function Mindmap.zoomIn()  Mindmap.zoomBy(1.15) end
function Mindmap.zoomOut() Mindmap.zoomBy(1/1.15) end

function Mindmap.deleteSelected()
    if Mindmap.selected then
        local id = Mindmap.selected.id
        Graph.delete(id)
        Mindmap.anims[id] = nil
        Mindmap.selected = nil
        Bot.say("Branch removed.", 3)
    end
end

function Mindmap.centerOnSelected()
    local tx, ty, ts = 0, 0, 1
    if Mindmap.selected then
        tx, ty = Mindmap.selected.x, Mindmap.selected.y
        ts = 1.1
    end
    Mindmap.camTween = {
        fx = Mindmap.cam.x, fy = Mindmap.cam.y, fs = Mindmap.cam.scale,
        tx = tx, ty = ty, ts = ts, t = 0, dur = 0.6,
    }
end

return Mindmap
