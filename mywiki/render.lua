-- render.lua - shared colors, fonts, drawing helpers
local Render = {}

Render.colors = {
    bg        = {0.04, 0.05, 0.10},
    bgGrid    = {0.10, 0.14, 0.22},
    panel     = {0.09, 0.11, 0.18, 0.92},
    panelEdge = {0.40, 0.55, 0.95, 0.90},
    text      = {0.95, 0.97, 1.00},
    textDim   = {0.62, 0.70, 0.88},
    accent    = {0.40, 0.82, 1.00},
    accent2   = {0.95, 0.55, 0.92},
    success   = {0.45, 0.92, 0.65},
    warn      = {0.99, 0.78, 0.35},
    danger    = {1.00, 0.42, 0.45},
    edge      = {0.50, 0.70, 1.00, 0.85},
    shadow    = {0, 0, 0, 0.55},
}

Render.nodePalette = {
    {0.36, 0.78, 1.00},
    {0.96, 0.56, 0.90},
    {0.55, 0.94, 0.68},
    {1.00, 0.78, 0.40},
    {0.78, 0.58, 1.00},
    {1.00, 0.55, 0.55},
    {0.50, 0.96, 0.96},
}

local fonts = {}
local images = {}

function Render.init()
    local symbolaPath = "assets/fonts/Symbola.ttf"
    local hasSymbola = love.filesystem.getInfo(symbolaPath) ~= nil
    local function mkFont(size)
        local f = love.graphics.newFont(size)
        if hasSymbola then
            f:setFallbacks(love.graphics.newFont(symbolaPath, size))
        end
        return f
    end
    fonts.tiny    = mkFont(11)
    fonts.small   = mkFont(13)
    fonts.body    = mkFont(15)
    fonts.medium  = mkFont(18)
    fonts.large   = mkFont(26)
    fonts.huge    = mkFont(40)
    for _, f in pairs(fonts) do f:setFilter("linear", "linear") end

    -- preload optional generated assets
    local function tryLoad(name, path)
        if love.filesystem.getInfo(path) then
            local img = love.graphics.newImage(path)
            img:setFilter("linear", "linear")
            images[name] = img
        end
    end
    tryLoad("bot",      "assets/bot.png")
    tryLoad("bg",       "assets/bg.png")
    tryLoad("logo",     "assets/logo.png")
    tryLoad("card",     "assets/node_card.png")
    tryLoad("particle", "assets/particle.png")
end

function Render.font(name) return fonts[name] or fonts.body end
function Render.image(name) return images[name] end

function Render.setColor(c, a)
    love.graphics.setColor(c[1], c[2], c[3], (a or c[4] or 1))
end

function Render.card(x, y, w, h, r, fill, border, shadow)
    if shadow then
        Render.setColor(Render.colors.shadow)
        love.graphics.rectangle("fill", x + 4, y + 6, w, h, r, r)
    end
    if fill then
        Render.setColor(fill)
        love.graphics.rectangle("fill", x, y, w, h, r, r)
    end
    if border then
        Render.setColor(border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h, r, r)
    end
end

function Render.glow(cx, cy, radius, color, layers)
    layers = layers or 6
    if images.particle then
        local img = images.particle
        local iw, ih = img:getDimensions()
        local s = (radius * 2.6) / iw
        love.graphics.setColor(color[1], color[2], color[3], 0.55)
        love.graphics.draw(img, cx, cy, 0, s, s, iw/2, ih/2)
        return
    end
    for i = layers, 1, -1 do
        local a = 0.10 * (i / layers)
        love.graphics.setColor(color[1], color[2], color[3], a)
        love.graphics.circle("fill", cx, cy, radius * (1 + i * 0.18))
    end
end

function Render.connector(x1, y1, x2, y2, color, width, progress, flow)
    width = width or 3
    progress = progress or 1
    local mx = (x1 + x2) / 2
    local my = (y1 + y2) / 2 + 18
    local steps = 28
    local pts = {}
    local last = math.floor(steps * progress)
    for i = 0, last do
        local t = i / steps
        local u = 1 - t
        local px = u*u*x1 + 2*u*t*mx + t*t*x2
        local py = u*u*y1 + 2*u*t*my + t*t*y2
        pts[#pts+1] = px
        pts[#pts+1] = py
    end
    if #pts < 4 then return end
    Render.setColor(color, 0.20)
    love.graphics.setLineWidth(width + 5)
    love.graphics.line(pts)
    Render.setColor(color)
    love.graphics.setLineWidth(width)
    love.graphics.line(pts)
    -- flow dot
    if flow and progress >= 1 then
        local t = (flow % 1)
        local u = 1 - t
        local px = u*u*x1 + 2*u*t*mx + t*t*x2
        local py = u*u*y1 + 2*u*t*my + t*t*y2
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.circle("fill", px, py, width + 1.5)
        love.graphics.setColor(color[1], color[2], color[3], 0.55)
        love.graphics.circle("fill", px, py, width + 4)
    end
end

function Render.wrap(text, font, maxWidth)
    local _, lines = font:getWrap(text, maxWidth)
    return lines
end

-- 9-slice draw of an image into a target rect
function Render.nineSlice(img, x, y, w, h, edge)
    local iw, ih = img:getDimensions()
    edge = edge or 24
    local q = function(qx, qy, qw, qh) return love.graphics.newQuad(qx, qy, qw, qh, iw, ih) end
    local quads = {
        tl = q(0, 0, edge, edge),
        tr = q(iw - edge, 0, edge, edge),
        bl = q(0, ih - edge, edge, edge),
        br = q(iw - edge, ih - edge, edge, edge),
        t  = q(edge, 0, iw - edge*2, edge),
        b  = q(edge, ih - edge, iw - edge*2, edge),
        l  = q(0, edge, edge, ih - edge*2),
        r  = q(iw - edge, edge, edge, ih - edge*2),
        c  = q(edge, edge, iw - edge*2, ih - edge*2),
    }
    local cw, ch = w - edge*2, h - edge*2
    love.graphics.draw(img, quads.tl, x, y)
    love.graphics.draw(img, quads.tr, x + w - edge, y)
    love.graphics.draw(img, quads.bl, x, y + h - edge)
    love.graphics.draw(img, quads.br, x + w - edge, y + h - edge)
    love.graphics.draw(img, quads.t, x + edge, y, 0, cw / (iw - edge*2), 1)
    love.graphics.draw(img, quads.b, x + edge, y + h - edge, 0, cw / (iw - edge*2), 1)
    love.graphics.draw(img, quads.l, x, y + edge, 0, 1, ch / (ih - edge*2))
    love.graphics.draw(img, quads.r, x + w - edge, y + edge, 0, 1, ch / (ih - edge*2))
    love.graphics.draw(img, quads.c, x + edge, y + edge, 0, cw / (iw - edge*2), ch / (ih - edge*2))
end

return Render
