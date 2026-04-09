-- allcards.lua - Display all 52 poker cards with sortable layouts.
-- Sub buttons: Symbol (group by suit), Color (red/black), Text (by rank).
-- Each sort triggers a fun animated transition where every card flies
-- to its new slot with a staggered ease + slight rotation overshoot.

local Render = require("render")
local Easing = require("easing")

local AllCards = {}

local W, H = 1280, 720

-- Layout: 13 columns x 4 rows = 52 cards
local COLS = 13
local ROWS = 4
local CARD_SCALE = 0.7
local CARD_W = 80 * CARD_SCALE   -- 56
local CARD_H = 112 * CARD_SCALE  -- 78.4
local GAP_X = 12
local GAP_Y = 14
local GRID_W = COLS * CARD_W + (COLS - 1) * GAP_X
local GRID_H = ROWS * CARD_H + (ROWS - 1) * GAP_Y
local GRID_X = (W - GRID_W) / 2
local GRID_Y = 175

-- Sort buttons (top bar, beneath title)
local BTN_Y = 110
local BTN_W = 150
local BTN_H = 38
local BTN_GAP = 18
local SORT_BUTTONS = {
    {id = "symbol", label = "Symbol"},
    {id = "color",  label = "Color"},
    {id = "text",   label = "Text"},
}

local TWEEN_DUR = 0.7

-- Card-zoom (focused single card) constants
local ZOOM_CARD_W = 260
local ZOOM_CARD_H = ZOOM_CARD_W * (112 / 80)  -- 364
local ZOOM_DUR = 0.45

local state = {
    shouldBack = false,
    backHovered = false,
    loaded = false,
    bgImage = nil,
    cards = {},          -- 52 cards, each {rank, suit, slot, fromX, fromY, t}
    sortMode = "symbol",
    btnHover = nil,
    title_t = 0,
    -- Single-card zoom
    zoomedCardIdx = nil, -- index into state.cards
    zoomT = 0,
    zoomDir = 1,
    zoomFromX = 0,
    zoomFromY = 0,
    zoomFromW = 0,
    zoomFromH = 0,
}

local function slotXY(slot)
    -- slot is 0..51
    local row = math.floor(slot / COLS)
    local col = slot % COLS
    local x = GRID_X + col * (CARD_W + GAP_X)
    local y = GRID_Y + row * (CARD_H + GAP_Y)
    return x, y
end

-- Suit ordering helpers (suit ids: 1=clubs, 2=diamonds, 3=hearts, 4=spades)
local function colorGroup(suit)
    -- Red first (diamonds, hearts), then black (clubs, spades)
    if suit == 2 then return 1
    elseif suit == 3 then return 2
    elseif suit == 1 then return 3
    else return 4 end
end

local SORTERS = {
    symbol = function(a, b)
        if a.suit ~= b.suit then return a.suit < b.suit end
        return a.rank < b.rank
    end,
    color = function(a, b)
        local ga, gb = colorGroup(a.suit), colorGroup(b.suit)
        if ga ~= gb then return ga < gb end
        return a.rank < b.rank
    end,
    text = function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.suit < b.suit
    end,
}

local function buildAllCards()
    local out = {}
    for suit = 1, 4 do
        for rank = 1, 13 do
            out[#out + 1] = {
                rank = rank,
                suit = suit,
                slot = 0,
                fromX = 0, fromY = 0,
                t = 1,
                rotFrom = 0,
            }
        end
    end
    return out
end

-- Compute current displayed (x, y) for a card given its tween state.
local function currentDisplayXY(c)
    local tx, ty = slotXY(c.slot)
    if c.t >= 1 then return tx, ty end
    local e = Easing.easeOutBack(c.t)
    return c.fromX + (tx - c.fromX) * e, c.fromY + (ty - c.fromY) * e
end

local function applySort(mode, fanIn)
    state.sortMode = mode
    -- Snapshot every card's current displayed position before reassigning slots.
    local snapshots = {}
    for i, c in ipairs(state.cards) do
        local x, y = currentDisplayXY(c)
        snapshots[i] = {x = x, y = y}
    end

    -- Sort a copy to determine new slot index for each original card.
    local indexed = {}
    for i, c in ipairs(state.cards) do
        indexed[i] = {orig = i, rank = c.rank, suit = c.suit}
    end
    table.sort(indexed, SORTERS[mode] or SORTERS.symbol)

    for newSlot, entry in ipairs(indexed) do
        local card = state.cards[entry.orig]
        if fanIn then
            -- Fly in from a starburst at the screen center, with rotation
            local cx = W / 2
            local cy = H / 2 + 40
            local angle = (entry.orig / 52) * math.pi * 2
            local dist = 700
            card.fromX = cx + math.cos(angle) * dist
            card.fromY = cy + math.sin(angle) * dist
            card.rotFrom = (math.random() - 0.5) * math.pi * 2
        else
            local snap = snapshots[entry.orig]
            card.fromX = snap.x
            card.fromY = snap.y
            card.rotFrom = (math.random() - 0.5) * 0.6
        end
        card.slot = newSlot - 1
        -- Stagger by new slot so the cards cascade across the grid
        card.t = -((newSlot - 1) * 0.012)
    end
end

function AllCards.init()
    state.shouldBack = false
    state.backHovered = false
    state.btnHover = nil
    state.title_t = 0
    state.zoomedCardIdx = nil
    state.zoomT = 0
    state.zoomDir = 1
    state.cards = buildAllCards()
    applySort("symbol", true)
    if not state.loaded then
        state.loaded = true
        if love.filesystem.getInfo("assets/allcards_bg.png") then
            state.bgImage = love.graphics.newImage("assets/allcards_bg.png")
            state.bgImage:setFilter("linear", "linear")
        end
    end
end

function AllCards.shouldGoBack()
    return state.shouldBack
end

function AllCards.update(dt)
    state.title_t = state.title_t + dt
    for _, c in ipairs(state.cards) do
        if c.t < 1 then
            c.t = math.min(1, c.t + dt / TWEEN_DUR)
        end
    end
    if state.zoomedCardIdx then
        state.zoomT = state.zoomT + state.zoomDir * (dt / ZOOM_DUR)
        if state.zoomT >= 1 then
            state.zoomT = 1
        elseif state.zoomT <= 0 then
            state.zoomT = 0
            if state.zoomDir < 0 then
                state.zoomedCardIdx = nil
            end
        end
    end
end

local function btnRect(i)
    local total = #SORT_BUTTONS * BTN_W + (#SORT_BUTTONS - 1) * BTN_GAP
    local startX = (W - total) / 2
    local x = startX + (i - 1) * (BTN_W + BTN_GAP)
    return x, BTN_Y, BTN_W, BTN_H
end

local function pointInRect(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function startCardZoomOut()
    if state.zoomedCardIdx and state.zoomDir > 0 then
        state.zoomDir = -1
    end
end

-- Find which card the cursor is over (by hit-testing the *target* slot
-- rect, so the click target stays stable even mid-animation).
local function cardAt(mx, my)
    for i, c in ipairs(state.cards) do
        local x, y = slotXY(c.slot)
        if mx >= x and mx <= x + CARD_W and my >= y and my <= y + CARD_H then
            return i, x, y
        end
    end
    return nil
end

function AllCards.mousepressed(mx, my, button)
    if button ~= 1 then return end

    -- If a card is currently zoomed, any click dismisses it
    if state.zoomedCardIdx then
        startCardZoomOut()
        return
    end

    local bb = Render.BACK_BTN
    if bb and pointInRect(mx, my, bb.x, bb.y, bb.w, bb.h) then
        state.shouldBack = true
        return
    end

    for i, btn in ipairs(SORT_BUTTONS) do
        local x, y, w, h = btnRect(i)
        if pointInRect(mx, my, x, y, w, h) then
            applySort(btn.id, false)
            return
        end
    end

    -- Card click → zoom in on that single card
    local idx, sx, sy = cardAt(mx, my)
    if idx then
        state.zoomedCardIdx = idx
        state.zoomT = 0
        state.zoomDir = 1
        state.zoomFromX = sx + CARD_W / 2
        state.zoomFromY = sy + CARD_H / 2
        state.zoomFromW = CARD_W
        state.zoomFromH = CARD_H
    end
end

function AllCards.mousemoved(mx, my)
    local bb = Render.BACK_BTN
    state.backHovered = bb and pointInRect(mx, my, bb.x, bb.y, bb.w, bb.h) or false
    state.btnHover = nil
    for i, btn in ipairs(SORT_BUTTONS) do
        local x, y, w, h = btnRect(i)
        if pointInRect(mx, my, x, y, w, h) then
            state.btnHover = btn.id
            break
        end
    end
end

function AllCards.keypressed(key)
    if state.zoomedCardIdx then
        if key == "escape" or key == "backspace" or key == "b"
           or key == "return" or key == "space" then
            startCardZoomOut()
            return
        end
        return
    end
    if key == "escape" or key == "backspace" or key == "b" or key == "return" then
        state.shouldBack = true
        return "menu"
    elseif key == "1" or key == "s" then
        applySort("symbol", false)
    elseif key == "2" or key == "c" then
        applySort("color", false)
    elseif key == "3" or key == "t" then
        applySort("text", false)
    elseif key == "r" then
        applySort(state.sortMode, true)
    end
end

function AllCards.draw()
    local C = Render.C

    -- Background
    if state.bgImage then
        love.graphics.setColor(1, 1, 1)
        local sx = W / state.bgImage:getWidth()
        local sy = H / state.bgImage:getHeight()
        love.graphics.draw(state.bgImage, 0, 0, 0, sx, sy)
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, W, H)
    else
        love.graphics.setColor(C.darkBg)
        love.graphics.rectangle("fill", 0, 0, W, H)
        love.graphics.setColor(C.felt)
        love.graphics.ellipse("fill", W/2, H/2 + 60, 560, 280)
    end

    -- Title
    local time = state.title_t
    love.graphics.setFont(Render.getFont("xlarge"))
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("ALL POKER CARDS", 3, 23, W, "center")
    local glow = 0.8 + 0.2 * math.sin(time * 2)
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], glow)
    love.graphics.printf("ALL POKER CARDS", 0, 20, W, "center")

    love.graphics.setFont(Render.getFont("small"))
    love.graphics.setColor(C.dimWhite)
    love.graphics.printf("All 52 cards — choose a sort mode to rearrange them",
        0, 70, W, "center")

    -- Sort buttons
    for i, btn in ipairs(SORT_BUTTONS) do
        local x, y, w, h = btnRect(i)
        local active = (state.sortMode == btn.id)
        local hovered = (state.btnHover == btn.id)
        if hovered or active then
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], active and 0.45 or 0.28)
            love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 8, 8)
        end
        love.graphics.setColor(0.1, 0.1, 0.12, 0.9)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
        love.graphics.setColor(C.gold)
        love.graphics.setLineWidth(active and 2.4 or 1.5)
        love.graphics.rectangle("line", x, y, w, h, 6, 6)
        love.graphics.setFont(Render.getFont("medium"))
        love.graphics.setColor(C.white)
        love.graphics.printf(btn.label, x, y + h/2 - 12, w, "center")
    end

    -- Soft felt panel behind cards
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", GRID_X - 16, GRID_Y - 12, GRID_W + 32, GRID_H + 24, 12, 12)
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.35)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", GRID_X - 16, GRID_Y - 12, GRID_W + 32, GRID_H + 24, 12, 12)

    -- Cards
    for _, c in ipairs(state.cards) do
        local tt = math.max(0, math.min(1, c.t))
        local eased = Easing.easeOutBack(tt)
        local tx, ty = slotXY(c.slot)
        local cx = c.fromX + (tx - c.fromX) * eased
        local cy = c.fromY + (ty - c.fromY) * eased
        local rot = c.rotFrom * (1 - eased)

        -- Pop-in scale
        local scaleMul = 0.4 + 0.6 * eased
        local drawScale = CARD_SCALE * scaleMul

        -- Draw rotated around the card center.
        love.graphics.push()
        love.graphics.translate(cx + CARD_W/2, cy + CARD_H/2)
        love.graphics.rotate(rot)
        local dw = 80 * drawScale
        local dh = 112 * drawScale
        love.graphics.setColor(1, 1, 1, math.min(1, eased + 0.15))
        Render.drawCard({rank = c.rank, suit = c.suit}, -dw/2, -dh/2, true, drawScale)
        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1, 1)

    -- Footer hint
    love.graphics.setFont(Render.getFont("small"))
    love.graphics.setColor(C.dimWhite)
    love.graphics.printf("Click a card to zoom  •  [1/S] Symbol  •  [2/C] Color  •  [3/T] Text  •  [R] Re-fan  •  [B] Back",
        0, H - 28, W, "center")

    -- Single-card zoom overlay
    if state.zoomedCardIdx then
        local c = state.cards[state.zoomedCardIdx]
        if c then
            local eased = Easing.easeOutBack(state.zoomT)
            local easedFade = Easing.easeOutExpo(state.zoomT)

            -- Dim backdrop
            love.graphics.setColor(0, 0, 0, 0.85 * easedFade)
            love.graphics.rectangle("fill", 0, 0, W, H)

            -- Animate from the small grid card position to the centered big card.
            local fromCx = state.zoomFromX
            local fromCy = state.zoomFromY
            local toCx = W / 2
            local toCy = H / 2
            local cx = fromCx + (toCx - fromCx) * eased
            local cy = fromCy + (toCy - fromCy) * eased

            local fromW = state.zoomFromW
            local toW = ZOOM_CARD_W
            local curW = fromW + (toW - fromW) * eased
            local drawScale = curW / 80
            local dw = 80 * drawScale
            local dh = 112 * drawScale

            -- Subtle floating sway once settled
            local time = state.title_t
            local sway = math.sin(time * 1.6) * 4 * easedFade

            love.graphics.push()
            love.graphics.translate(cx, cy + sway)
            love.graphics.rotate(math.sin(time * 1.3) * 0.04 * easedFade)
            love.graphics.setColor(1, 1, 1, easedFade)
            Render.drawCard({rank = c.rank, suit = c.suit}, -dw/2, -dh/2, true, drawScale)
            love.graphics.pop()

            -- Card label below
            love.graphics.setFont(Render.getFont("medium"))
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], easedFade)
            local rankNames = {"Ace", "Two", "Three", "Four", "Five", "Six",
                "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King"}
            local suitNames = {"Clubs", "Diamonds", "Hearts", "Spades"}
            local label = (rankNames[c.rank] or "?") .. " of " .. (suitNames[c.suit] or "?")
            love.graphics.printf(label, 0, H/2 + ZOOM_CARD_H/2 + 20, W, "center")

            love.graphics.setFont(Render.getFont("small"))
            love.graphics.setColor(C.dimWhite[1], C.dimWhite[2], C.dimWhite[3], easedFade)
            love.graphics.printf("Click anywhere or press [ESC] to return",
                0, H/2 + ZOOM_CARD_H/2 + 56, W, "center")
        end
    end

    -- Back button
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

return AllCards
