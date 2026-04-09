-- main.lua - Entry point for Texas Hold'em Poker
-- A single-player game vs 3 AI opponents built with LOVE2D

local Game = require("game")
local Render = require("render")
local Quiz = require("quiz")
local Cheatsheet = require("cheatsheet")

-- Design resolution (all layout is based on this)
local DESIGN_W = 1280
local DESIGN_H = 720

-- App mode: "game", "quiz", or "cheatsheet"
local appMode = "game"

-- Computed scale/offset for letterboxing
local scaleX, scaleY, scale = 1, 1, 1
local offsetX, offsetY = 0, 0

local function updateScale()
    local winW, winH = love.graphics.getDimensions()
    scaleX = winW / DESIGN_W
    scaleY = winH / DESIGN_H
    scale = math.min(scaleX, scaleY)
    offsetX = (winW - DESIGN_W * scale) / 2
    offsetY = (winH - DESIGN_H * scale) / 2
end

-- Convert screen coords to game coords
local function screenToGame(sx, sy)
    return (sx - offsetX) / scale, (sy - offsetY) / scale
end

function love.load()
    math.randomseed(os.time())
    for _ = 1, 10 do math.random() end

    Render.init()
    Game.init()
    love.graphics.setBackgroundColor(0.02, 0.02, 0.02)
    updateScale()
end

function love.resize(w, h)
    updateScale()
end

function love.update(dt)
    dt = math.min(dt, 1/30)
    if appMode == "quiz" then
        Quiz.update(dt)
        if Quiz.shouldGoBack and Quiz.shouldGoBack() then
            appMode = "game"
            Game.init()
        end
    elseif appMode == "cheatsheet" then
        Cheatsheet.update(dt)
        if Cheatsheet.shouldGoBack() then
            appMode = "game"
            Game.init()
        end
    else
        Game.update(dt)
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scale)

    if appMode == "quiz" then
        Quiz.draw()
    elseif appMode == "cheatsheet" then
        Cheatsheet.draw()
    else
        Game.draw()
    end

    -- FPS counter
    love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    love.graphics.setFont(Render.getFont("small"))
    love.graphics.print("FPS: " .. love.timer.getFPS(), DESIGN_W - 70, DESIGN_H - 20)

    love.graphics.pop()

    -- Draw letterbox bars
    if offsetX > 0 then
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle("fill", 0, 0, offsetX, love.graphics.getHeight())
        love.graphics.rectangle("fill", love.graphics.getWidth() - offsetX, 0, offsetX, love.graphics.getHeight())
    end
    if offsetY > 0 then
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), offsetY)
        love.graphics.rectangle("fill", 0, love.graphics.getHeight() - offsetY, love.graphics.getWidth(), offsetY)
    end
end

function love.keypressed(key)
    if key == "f" or key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen())
        updateScale()
        return
    end

    if appMode == "quiz" then
        local result = Quiz.keypressed(key)
        if result == "menu" then
            appMode = "game"
            Game.init()
        end
        return
    end

    if appMode == "cheatsheet" then
        local result = Cheatsheet.keypressed(key)
        if result == "menu" then
            appMode = "game"
            Game.init()
        end
        return
    end

    -- Game mode
    if key == "escape" then
        love.event.quit()
        return
    end

    -- Menu shortcuts
    if Game.getState() == "menu" then
        if key == "l" then
            appMode = "quiz"
            Quiz.init()
            return
        end
        if key == "c" then
            appMode = "cheatsheet"
            Cheatsheet.init()
            return
        end
        if key == "1" or key == "return" or key == "space" then
            Game.keypressed("return")
            return
        end
        if key == "2" then
            appMode = "quiz"
            Quiz.init()
            return
        end
        if key == "3" then
            appMode = "cheatsheet"
            Cheatsheet.init()
            return
        end
    end

    Game.keypressed(key)
end

function love.mousepressed(x, y, button)
    local gx, gy = screenToGame(x, y)

    if appMode == "quiz" then
        Quiz.mousepressed(gx, gy, button)
        return
    end

    if appMode == "cheatsheet" then
        Cheatsheet.mousepressed(gx, gy, button)
        return
    end

    -- Check menu button clicks
    if Game.getState() == "menu" and button == 1 then
        local btnW, btnH = 260, 42
        local bx = 640 - btnW/2
        -- "Play Poker" button at y = 360 + 110 = 470
        if gx >= bx and gx <= bx + btnW and gy >= 470 and gy <= 470 + btnH then
            Game.keypressed("return")
            return
        end
        -- "Learn Hands" button at y = 360 + 160 = 520
        if gx >= bx and gx <= bx + btnW and gy >= 520 and gy <= 520 + btnH then
            appMode = "quiz"
            Quiz.init()
            return
        end
        -- "Cheatsheet" button at y = 360 + 210 = 570
        if gx >= bx and gx <= bx + btnW and gy >= 570 and gy <= 570 + btnH then
            appMode = "cheatsheet"
            Cheatsheet.init()
            return
        end
    end

    Game.mousepressed(gx, gy, button)
end

function love.mousemoved(x, y)
    local gx, gy = screenToGame(x, y)
    if appMode == "quiz" then
        Quiz.mousemoved(gx, gy)
        return
    end
    if appMode == "cheatsheet" then
        Cheatsheet.mousemoved(gx, gy)
        return
    end
    Game.mousemoved(gx, gy)
end
