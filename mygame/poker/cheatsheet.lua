-- cheatsheet.lua - Poker hand rank reference screen
-- Shows all 10 poker hand rankings from highest to lowest with
-- example cards and short descriptions.

local Render = require("render")
local Easing = require("easing")
local Quiz = require("quiz")

local Cheatsheet = {}

-- Shuffle button rect (in design coordinates)
local SHUFFLE_BTN = {x = 1280 - 170, y = 676, w = 140, h = 34}

-- Zoom-view buttons (Random Shuffle / Sort) - laid out beneath the big cards
local ZOOM_BTN_W = 200
local ZOOM_BTN_H = 44
local ZOOM_BTN_GAP = 30
-- y is computed in draw based on card layout, but click hit-tests need a
-- stable rect. Big cards are vertically centered, so this y is constant.
local ZOOM_BTN_Y = 360 + (170 * 112 / 80) / 2 + 28  -- centerY + bigCardH/2 + 28

-- Big card layout in zoom view (kept here so click-tests and draw agree)
local BIG_CARD_W = 170
local BIG_CARD_H = BIG_CARD_W * (112 / 80)
local BIG_GAP = 20

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
    -- In-zoom card view: per-card tween {rank, suit, slot, fromX, fromY, t, rotFrom}
    zoomCardsView = nil,
    zoomCardDur = 0.55,
    zoomShuffleHovered = false,
    zoomSortHovered = false,
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

-- Compute target X,Y for a slot index (0-based) in the zoom view
local function bigSlotXY(slot)
    local W = 1280
    local totalW = BIG_CARD_W * 5 + BIG_GAP * 4
    local startX = (W - totalW) / 2
    local centerY = 360
    local x = startX + slot * (BIG_CARD_W + BIG_GAP)
    local y = centerY - BIG_CARD_H / 2
    return x, y
end

-- Read current displayed (x, y) for an in-zoom card given its tween state.
local function zoomCardXY(c)
    local tx, ty = bigSlotXY(c.slot)
    if c.t >= 1 then return tx, ty end
    local e = Easing.easeOutBack(math.max(0, c.t))
    return c.fromX + (tx - c.fromX) * e, c.fromY + (ty - c.fromY) * e
end

-- Build a fresh zoom view from the current example for `idx`. If `flyIn`,
-- the cards burst in from below; otherwise they keep their current displayed
-- positions and animate to the new (possibly reordered) slots.
local function rebuildZoomView(idx, flyIn)
    local cards = state.exampleCards and state.exampleCards[idx] or {}
    -- Snapshot existing displayed positions keyed by "rank,suit"
    local snap = {}
    if state.zoomCardsView and not flyIn then
        for _, oc in ipairs(state.zoomCardsView) do
            local x, y = zoomCardXY(oc)
            snap[oc.rank .. "," .. oc.suit] = {x = x, y = y}
        end
    end

    local view = {}
    for j, c in ipairs(cards) do
        local rank, suit = c[1], c[2]
        local key = rank .. "," .. suit
        local fromX, fromY, rotFrom
        if flyIn or not snap[key] then
            -- Burst in from below center, with a gentle random rotation.
            local _, ty = bigSlotXY(j - 1)
            local cx = 1280 / 2 + (math.random() - 0.5) * 280
            fromX = cx - BIG_CARD_W / 2
            fromY = ty + 360
            rotFrom = (math.random() - 0.5) * math.pi
        else
            local s = snap[key]
            fromX = s.x
            fromY = s.y
            rotFrom = (math.random() - 0.5) * 0.4
        end
        view[j] = {
            rank = rank, suit = suit,
            slot = j - 1,
            fromX = fromX, fromY = fromY,
            t = -((j - 1) * 0.06),
            rotFrom = rotFrom,
        }
    end
    state.zoomCardsView = view
end

-- Re-roll only the cards for the currently zoomed hand.
local function shuffleZoomCards()
    if not state.zoomedIdx then return end
    local hand = HANDS[state.zoomedIdx]
    if not hand then return end
    local fresh = Quiz.buildHand(hand.name) or {}
    local pairs5 = {}
    for j, c in ipairs(fresh) do pairs5[j] = {c.rank, c.suit} end
    state.exampleCards[state.zoomedIdx] = pairs5
    rebuildZoomView(state.zoomedIdx, true)
end

-- Sort the zoomed cards by rank ascending (Aces low) so they're easy to read.
local function sortZoomCards()
    if not state.zoomedIdx then return end
    local cards = state.exampleCards and state.exampleCards[state.zoomedIdx]
    if not cards then return end
    table.sort(cards, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    rebuildZoomView(state.zoomedIdx, false)
end

local function zoomBtnRects()
    local W = 1280
    local totalW = ZOOM_BTN_W * 2 + ZOOM_BTN_GAP
    local startX = (W - totalW) / 2
    return
        {x = startX,                              y = ZOOM_BTN_Y, w = ZOOM_BTN_W, h = ZOOM_BTN_H},
        {x = startX + ZOOM_BTN_W + ZOOM_BTN_GAP, y = ZOOM_BTN_Y, w = ZOOM_BTN_W, h = ZOOM_BTN_H}
end

function Cheatsheet.init()
    state.shouldBack = false
    state.backHovered = false
    state.shuffleHovered = false
    state.hoveredRow = 0
    state.zoomedIdx = nil
    state.zoomT = 0
    state.zoomDir = 1
    state.zoomCardsView = nil
    state.zoomShuffleHovered = false
    state.zoomSortHovered = false
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
    -- Advance per-card zoom view tweens (staggered fly/sort animation)
    if state.zoomCardsView then
        for _, c in ipairs(state.zoomCardsView) do
            if c.t < 1 then
                c.t = math.min(1, c.t + dt / state.zoomCardDur)
            end
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
        if key == "r" then
            shuffleZoomCards()
            return
        end
        if key == "s" or key == "o" then
            sortZoomCards()
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

    -- Shuffle button (top-right) works only in list view
    if not state.zoomedIdx and inShuffleBtn(mx, my) then
        reshuffle()
        return
    end

    -- Zoom view: check Random Shuffle / Sort buttons before dismissing
    if state.zoomedIdx then
        local sb, ob = zoomBtnRects()
        local function inR(r) return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h end
        if inR(sb) then
            shuffleZoomCards()
            return
        end
        if inR(ob) then
            sortZoomCards()
            return
        end
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
            rebuildZoomView(idx, true)
        end
    end
end

function Cheatsheet.mousemoved(mx, my)
    local bb = Render.BACK_BTN
    state.backHovered = bb and (mx >= bb.x and mx <= bb.x + bb.w and my >= bb.y and my <= bb.y + bb.h) or false
    state.shuffleHovered = inShuffleBtn(mx, my)
    if state.zoomedIdx then
        state.hoveredRow = 0
        local sb, ob = zoomBtnRects()
        state.zoomShuffleHovered = mx >= sb.x and mx <= sb.x + sb.w and my >= sb.y and my <= sb.y + sb.h
        state.zoomSortHovered = mx >= ob.x and mx <= ob.x + ob.w and my >= ob.y and my <= ob.y + ob.h
    else
        state.hoveredRow = rowAt(my)
        state.zoomShuffleHovered = false
        state.zoomSortHovered = false
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

        local centerY = H / 2
        local scaleFromImage = BIG_CARD_W / 80

        love.graphics.setColor(1, 1, 1, eased)

        -- Big title
        love.graphics.setFont(Render.getFont("xlarge"))
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], eased)
        love.graphics.printf(hand.name, 0, centerY - BIG_CARD_H/2 - 80, W, "center")
        love.graphics.setFont(Render.getFont("medium"))
        love.graphics.setColor(1, 1, 1, eased * 0.9)
        love.graphics.printf(hand.desc, 0, centerY - BIG_CARD_H/2 - 34, W, "center")

        -- Per-card tweened layout (handles initial fly-in, shuffle and sort)
        local view = state.zoomCardsView or {}
        for _, c in ipairs(view) do
            local tt = math.max(0, math.min(1, c.t))
            local cardEase = Easing.easeOutBack(tt)
            local tx, ty = bigSlotXY(c.slot)
            local cx = c.fromX + (tx - c.fromX) * cardEase
            local cy = c.fromY + (ty - c.fromY) * cardEase
            local rot = c.rotFrom * (1 - cardEase)
            local scaleMul = 0.4 + 0.6 * cardEase
            local drawScale = scaleFromImage * scaleMul
            local drawW = 80 * drawScale
            local drawH = 112 * drawScale
            love.graphics.push()
            love.graphics.translate(cx + BIG_CARD_W/2, cy + BIG_CARD_H/2)
            love.graphics.rotate(rot)
            love.graphics.setColor(1, 1, 1, math.min(1, eased * (cardEase + 0.2)))
            Render.drawCard({rank = c.rank, suit = c.suit}, -drawW/2, -drawH/2, true, drawScale)
            love.graphics.pop()
        end
        love.graphics.setColor(1, 1, 1, 1)

        -- Random Shuffle / Sort buttons (only meaningful once zoom-in completes)
        local btnAlpha = eased
        local sb, ob = zoomBtnRects()
        local function drawZoomBtn(r, label, hovered)
            if hovered then
                love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.4 * btnAlpha)
                love.graphics.rectangle("fill", r.x - 3, r.y - 3, r.w + 6, r.h + 6, 8, 8)
            end
            love.graphics.setColor(0.1, 0.1, 0.12, 0.92 * btnAlpha)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], btnAlpha)
            love.graphics.setLineWidth(hovered and 2.4 or 1.6)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 8, 8)
            love.graphics.setFont(Render.getFont("medium"))
            love.graphics.setColor(1, 1, 1, btnAlpha)
            love.graphics.printf(label, r.x, r.y + r.h/2 - 12, r.w, "center")
        end
        drawZoomBtn(sb, "Random Shuffle [R]", state.zoomShuffleHovered)
        drawZoomBtn(ob, "Sort [S]",           state.zoomSortHovered)

        -- Dismiss hint
        love.graphics.setFont(Render.getFont("small"))
        love.graphics.setColor(C.dimWhite[1], C.dimWhite[2], C.dimWhite[3], eased)
        love.graphics.printf("Press [ESC] to return — click empty space dismisses too",
            0, ZOOM_BTN_Y + ZOOM_BTN_H + 14, W, "center")
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
