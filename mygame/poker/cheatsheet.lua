-- cheatsheet.lua - Poker hand rank reference screen
-- Shows all 10 poker hand rankings from highest to lowest with
-- example cards and short descriptions.

local Render = require("render")
local Easing = require("easing")
local Quiz = require("quiz")

local Cheatsheet = {}

-- Shuffle button rect (in design coordinates)
local SHUFFLE_BTN = {x = 1280 - 170, y = 676, w = 140, h = 34}

-- Layout constants shared between click-hit-testing and drawing
local ROW_H = 58
local TOP_Y = 96
local ROW_PAD_X = 40

local state = {
    shouldBack = false,
    backHovered = false,
    shuffleHovered = false,
    loaded = false,
    bgImage = nil,
    hoveredRow = 0,
    -- Zoom state
    zoomedIdx = nil,   -- which hand is zoomed (nil = list view)
    zoomT = 0,         -- raw 0..1 progress
    zoomDir = 1,       -- +1 zooming in, -1 zooming out
    zoomDur = 0.55,    -- seconds
    -- Runtime-generated example cards per hand (parallel to HANDS)
    exampleCards = nil,
    -- Per-row shuffle animation [1..#HANDS] → 0..1 (1 = settled)
    shuffleAnim = {},
}

-- Hand rankings (highest to lowest). Example cards are generated at
-- runtime via Quiz.buildHand so ranks/suits can be reshuffled.
local HANDS = {
    {name = "Royal Flush",     desc = "A K Q J 10, all the same suit. Unbeatable."},
    {name = "Straight Flush",  desc = "Five cards in sequence, all the same suit."},
    {name = "Four of a Kind",  desc = "Four cards of the same rank, plus any card."},
    {name = "Full House",      desc = "Three of a kind combined with a pair."},
    {name = "Flush",           desc = "Any five cards of the same suit, not in sequence."},
    {name = "Straight",        desc = "Five cards in sequence, suits may differ."},
    {name = "Three of a Kind", desc = "Three cards of the same rank plus two kickers."},
    {name = "Two Pair",        desc = "Two different pairs plus a kicker."},
    {name = "One Pair",        desc = "Two cards of the same rank."},
    {name = "High Card",       desc = "No combination — the highest card plays."},
}

-- Generate a fresh random example for every hand category.
-- Returns an array parallel to HANDS; each entry is a list of {rank, suit}.
local function rollExamples()
    local out = {}
    for i, h in ipairs(HANDS) do
        local cards = Quiz.buildHand(h.name) or {}
        local pairs5 = {}
        for j, c in ipairs(cards) do
            pairs5[j] = {c.rank, c.suit}
        end
        out[i] = pairs5
    end
    return out
end

local function reshuffle()
    state.exampleCards = rollExamples()
    -- Kick off a per-row pop-in animation, staggered by row index.
    -- Negative values represent "still waiting to start" so the rows
    -- cascade top-to-bottom (increment ≈0.12 per row over a 0.35s tween).
    for i = 1, #HANDS do
        state.shuffleAnim[i] = -(i - 1) * 0.12
    end
end

function Cheatsheet.init()
    state.shouldBack = false
    state.backHovered = false
    state.shuffleHovered = false
    state.hoveredRow = 0
    state.zoomedIdx = nil
    state.zoomT = 0
    state.zoomDir = 1
    reshuffle()
    if not state.loaded then
        state.loaded = true
        -- Optional AI-generated background image (see generate_cheatsheet_assets.py)
        if love.filesystem.getInfo("assets/cheatsheet_bg.png") then
            state.bgImage = love.graphics.newImage("assets/cheatsheet_bg.png")
            state.bgImage:setFilter("linear", "linear")
        end
    end
end

function Cheatsheet.shouldGoBack()
    return state.shouldBack
end

function Cheatsheet.update(dt)
    if state.zoomedIdx then
        state.zoomT = state.zoomT + state.zoomDir * (dt / state.zoomDur)
        if state.zoomT >= 1 then
            state.zoomT = 1
        elseif state.zoomT <= 0 then
            state.zoomT = 0
            if state.zoomDir < 0 then
                state.zoomedIdx = nil  -- fully zoomed out, back to list
            end
        end
    end
    -- Advance row shuffle animations (staggered so rows pop in sequentially)
    for i = 1, #HANDS do
        local v = state.shuffleAnim[i] or 1
        if v < 1 then
            state.shuffleAnim[i] = math.min(1, v + dt / 0.35)
        end
    end
end

local function startZoomOut()
    if state.zoomedIdx and state.zoomDir > 0 then
        state.zoomDir = -1
    end
end

function Cheatsheet.keypressed(key)
    if state.zoomedIdx then
        if key == "escape" or key == "backspace" or key == "b"
           or key == "return" or key == "space" then
            startZoomOut()
            return
        end
        if key == "r" or key == "s" then
            reshuffle()
            return
        end
        return
    end
    if key == "r" or key == "s" then
        reshuffle()
        return
    end
    if key == "escape" or key == "backspace" or key == "b" or key == "return" then
        state.shouldBack = true
        return "menu"
    end
end

local function inShuffleBtn(mx, my)
    local b = SHUFFLE_BTN
    return mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h
end

local function rowAt(my)
    if my < TOP_Y then return 0 end
    local idx = math.floor((my - TOP_Y) / ROW_H) + 1
    if idx < 1 or idx > #HANDS then return 0 end
    local y = TOP_Y + (idx - 1) * ROW_H
    if my > y + ROW_H - 4 then return 0 end
    return idx
end

function Cheatsheet.mousepressed(mx, my, button)
    if button ~= 1 then return end

    -- Shuffle button works in both list and zoom views
    if inShuffleBtn(mx, my) then
        reshuffle()
        return
    end

    -- Clicking while zoomed: dismiss the zoom
    if state.zoomedIdx then
        startZoomOut()
        return
    end

    local bb = Render.BACK_BTN
    if bb and mx >= bb.x and mx <= bb.x + bb.w and my >= bb.y and my <= bb.y + bb.h then
        state.shouldBack = true
        return
    end

    -- Row click → zoom into that hand's cards
    if mx >= ROW_PAD_X and mx <= 1280 - ROW_PAD_X then
        local idx = rowAt(my)
        if idx > 0 then
            state.zoomedIdx = idx
            state.zoomT = 0
            state.zoomDir = 1
        end
    end
end

function Cheatsheet.mousemoved(mx, my)
    local bb = Render.BACK_BTN
    state.backHovered = bb and (mx >= bb.x and mx <= bb.x + bb.w and my >= bb.y and my <= bb.y + bb.h) or false
    state.shuffleHovered = inShuffleBtn(mx, my)
    if state.zoomedIdx then
        state.hoveredRow = 0
    else
        state.hoveredRow = rowAt(my)
    end
end

function Cheatsheet.draw()
    local W, H = 1280, 720
    local C = Render.C

    -- Background
    if state.bgImage then
        love.graphics.setColor(1, 1, 1)
        local sx = W / state.bgImage:getWidth()
        local sy = H / state.bgImage:getHeight()
        love.graphics.draw(state.bgImage, 0, 0, 0, sx, sy)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, W, H)
    else
        love.graphics.setColor(C.darkBg)
        love.graphics.rectangle("fill", 0, 0, W, H)
        love.graphics.setColor(C.felt)
        love.graphics.ellipse("fill", W/2, H/2 + 40, 500, 240)
    end

    -- Title
    local time = love.timer.getTime()
    love.graphics.setFont(Render.getFont("xlarge"))
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("POKER HAND RANKINGS", 3, 23, W, "center")
    local glow = 0.8 + 0.2 * math.sin(time * 2)
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], glow)
    love.graphics.printf("POKER HAND RANKINGS", 0, 20, W, "center")

    love.graphics.setFont(Render.getFont("small"))
    love.graphics.setColor(C.dimWhite)
    love.graphics.printf("Strongest to weakest — higher beats lower at showdown",
        0, 70, W, "center")

    -- Rows
    local rowH = ROW_H
    local topY = TOP_Y
    local cardScale = 0.62  -- bumped up from 0.5 for readability
    local cardW = 80 * cardScale  -- CARD_W from render.lua is 80
    local gap = 8
    local cardsAreaW = cardW * 5 + gap * 4
    local cardsStartX = W - 50 - cardsAreaW

    for i, hand in ipairs(HANDS) do
        local y = topY + (i - 1) * rowH
        local isHovered = (state.hoveredRow == i)

        -- Row background (alternating, brighter on hover)
        if isHovered then
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.18)
        elseif i % 2 == 0 then
            love.graphics.setColor(1, 1, 1, 0.05)
        else
            love.graphics.setColor(0, 0, 0, 0.35)
        end
        love.graphics.rectangle("fill", ROW_PAD_X, y, W - ROW_PAD_X * 2, rowH - 4, 6, 6)
        if isHovered then
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.8)
            love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line", ROW_PAD_X, y, W - ROW_PAD_X * 2, rowH - 4, 6, 6)
        end

        -- Left accent bar (gold, stronger for top hands)
        local accent = 1.0 - (i - 1) / #HANDS * 0.55
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], accent)
        love.graphics.rectangle("fill", ROW_PAD_X, y, 4, rowH - 4)

        -- Rank number
        love.graphics.setFont(Render.getFont("large"))
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.85)
        love.graphics.printf(tostring(i), 52, y + 12, 36, "right")

        -- Name
        love.graphics.setFont(Render.getFont("medium"))
        love.graphics.setColor(C.white)
        love.graphics.print(hand.name, 108, y + 6)

        -- Description
        love.graphics.setFont(Render.getFont("small"))
        love.graphics.setColor(C.dimWhite)
        love.graphics.print(hand.desc, 108, y + 32)

        -- Example cards (right side) — use runtime-generated examples
        local examples = state.exampleCards and state.exampleCards[i] or {}
        local popRaw = state.shuffleAnim[i] or 1
        local popT = math.max(0, math.min(1, popRaw))
        local popEase = Easing.easeOutExpo(popT)
        for j, c in ipairs(examples) do
            local cx = cardsStartX + (j - 1) * (cardW + gap)
            local drawScale = cardScale * popEase
            local dw = 80 * drawScale
            local dh = 112 * drawScale
            local cxC = cx + (80 * cardScale) / 2
            local cyC = y + 1 + (112 * cardScale) / 2
            love.graphics.setColor(1, 1, 1, popEase)
            Render.drawCard({rank = c[1], suit = c[2]},
                cxC - dw/2, cyC - dh/2, true, drawScale)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Footer hint
    love.graphics.setFont(Render.getFont("small"))
    love.graphics.setColor(C.dimWhite)
    love.graphics.printf("Click a row to zoom in   •   [R] shuffle   •   [B] back",
        0, H - 24, W, "center")

    -- Shuffle button (top-right of bottom bar)
    do
        local b = SHUFFLE_BTN
        if state.shuffleHovered then
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.35)
            love.graphics.rectangle("fill", b.x - 2, b.y - 2, b.w + 4, b.h + 4, 6, 6)
        end
        love.graphics.setColor(0.1, 0.1, 0.12, 0.9)
        love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6, 6)
        love.graphics.setColor(C.gold)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6, 6)
        love.graphics.setFont(Render.getFont("normal"))
        love.graphics.setColor(C.white)
        love.graphics.printf("Shuffle [R]", b.x, b.y + b.h/2 - 10, b.w, "center")
    end

    -- Zoom overlay (drawn on top of everything else)
    if state.zoomedIdx then
        local hand = HANDS[state.zoomedIdx]
        local eased = Easing.easeOutExpo(state.zoomT)

        -- Dim backdrop
        love.graphics.setColor(0, 0, 0, 0.82 * eased)
        love.graphics.rectangle("fill", 0, 0, W, H)

        -- Compute big-card layout
        -- Final size: fit 5 cards across ~1100px, big and readable.
        local bigCardW = 170
        local bigCardH = bigCardW * (112 / 80)  -- preserve CARD_W:CARD_H ratio
        local bigGap = 20
        local totalW = bigCardW * 5 + bigGap * 4
        local startX = (W - totalW) / 2
        local centerY = H / 2
        local scaleFromImage = bigCardW / 80  -- Render.drawCard scale arg

        -- Eased scale + slight fade-in
        local s = eased  -- 0..1
        love.graphics.setColor(1, 1, 1, eased)

        -- Big title
        love.graphics.setFont(Render.getFont("xlarge"))
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], eased)
        love.graphics.printf(hand.name, 0, centerY - bigCardH/2 - 80, W, "center")
        love.graphics.setFont(Render.getFont("medium"))
        love.graphics.setColor(1, 1, 1, eased * 0.9)
        love.graphics.printf(hand.desc, 0, centerY - bigCardH/2 - 34, W, "center")

        -- Cards: each scaled from its individual center for a nice pop-in
        local zoomCards = state.exampleCards and state.exampleCards[state.zoomedIdx] or {}
        for j, c in ipairs(zoomCards) do
            local cx = startX + (j - 1) * (bigCardW + bigGap)
            local cy = centerY - bigCardH / 2
            -- Stagger the ease per card for a cascading feel
            local stagger = math.max(0, math.min(1, (state.zoomT - (j - 1) * 0.06) / (1 - 0.3)))
            local cardEase = Easing.easeOutExpo(stagger)
            local drawScale = scaleFromImage * cardEase
            local drawW = 80 * drawScale
            local drawH = 112 * drawScale
            local dx = cx + bigCardW/2 - drawW/2
            local dy = cy + bigCardH/2 - drawH/2
            love.graphics.setColor(1, 1, 1, cardEase)
            Render.drawCard({rank = c[1], suit = c[2]}, dx, dy, true, drawScale)
        end
        love.graphics.setColor(1, 1, 1, 1)

        -- Dismiss hint
        love.graphics.setFont(Render.getFont("small"))
        love.graphics.setColor(C.dimWhite[1], C.dimWhite[2], C.dimWhite[3], eased)
        love.graphics.printf("Click anywhere or press [ESC] to return",
            0, centerY + bigCardH/2 + 30, W, "center")
    end

    -- Back button (reuse Render.BACK_BTN layout)
    local bb = Render.BACK_BTN
    if bb then
        if state.backHovered then
            love.graphics.setColor(0.85, 0.65, 0.13, 0.3)
            love.graphics.rectangle("fill", bb.x - 2, bb.y - 2, bb.w + 4, bb.h + 4, 6, 6)
        end
        love.graphics.setColor(0.1, 0.1, 0.12, 0.9)
        love.graphics.rectangle("fill", bb.x, bb.y, bb.w, bb.h, 6, 6)
        love.graphics.setColor(C.gold)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", bb.x, bb.y, bb.w, bb.h, 6, 6)
        love.graphics.setFont(Render.getFont("normal"))
        love.graphics.setColor(C.white)
        love.graphics.printf("< Back", bb.x, bb.y + bb.h/2 - 10, bb.w, "center")
    end
end

return Cheatsheet
