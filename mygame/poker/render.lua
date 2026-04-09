-- render.lua - All rendering for Texas Hold'em

local Cards = require("cards")

local Render = {}

-- Fonts (initialized in love.load via Render.init)
local fonts = {}
local cardImages = {}
local cardBackImage = nil

-- Colors
local C = {
    felt       = {0.1, 0.35, 0.1},
    feltLight  = {0.12, 0.40, 0.12},
    border     = {0.4, 0.25, 0.1},
    borderDark = {0.3, 0.18, 0.07},
    cardWhite  = {1, 1, 1},
    cardBorder = {0.3, 0.3, 0.3},
    btnNormal  = {0.2, 0.2, 0.2, 0.9},
    btnHover   = {0.35, 0.35, 0.35, 0.9},
    btnDisable = {0.15, 0.15, 0.15, 0.5},
    gold       = {0.85, 0.65, 0.13},
    red        = {0.85, 0.1, 0.1},
    white      = {1, 1, 1},
    black      = {0, 0, 0},
    dimWhite   = {0.7, 0.7, 0.7},
    shadow     = {0, 0, 0, 0.4},
    highlight  = {1, 0.9, 0.3, 0.3},
    green      = {0.2, 0.8, 0.2},
    darkBg     = {0.05, 0.12, 0.05},
}
Render.C = C

-- Player positions (center of player area)
local POSITIONS = {
    {x = 640, y = 510},  -- Player (bottom)
    {x = 140, y = 330},  -- AI 1 (left)
    {x = 640, y = 60},   -- AI 2 (top)
    {x = 1140, y = 330}, -- AI 3 (right)
}
Render.POSITIONS = POSITIONS

-- Card dimensions (display size)
local CARD_W = 80
local CARD_H = 112
local CARD_SPACING = 14
local cardImageScale = 1  -- computed in init based on image size

-- Whether we have loaded PNG card images
local useImageCards = false
local tableBgImage = nil
local titleBgImage = nil

-- Avatar images: avatarImages["alice"] = love.Image
local avatarImages = {}
local avatarSpriteSheets = {}  -- sprite sheets for animation
local AVATAR_SIZE = 128  -- size of each frame in sprite sheet
local AVATAR_DISPLAY = 50  -- display size on screen
local AVATAR_FRAMES = 4  -- number of animation frames

-- Avatar animation state per player index
-- Frame mapping: 0=neutral, 1=smile/call, 2=thinking/turn, 3=confident/raise
local avatarAnimState = {}

function Render.initAvatarAnim(playerIdx)
    avatarAnimState[playerIdx] = {
        fromFrame = 0,
        toFrame = 0,
        blend = 1.0,       -- 1.0 = fully showing toFrame
        scale = 1.0,        -- current display scale
        targetScale = 1.0,  -- target scale (zoom)
        alpha = 1.0,        -- current alpha
        targetAlpha = 1.0,  -- target alpha
    }
end

function Render.triggerAvatarAnim(playerIdx, targetFrame)
    local state = avatarAnimState[playerIdx]
    if not state then return end
    state.fromFrame = state.toFrame
    state.toFrame = targetFrame
    state.blend = 0.0  -- start blending

    -- Zoom/alpha based on action type
    if targetFrame == 2 then
        -- Thinking: subtle zoom in
        state.targetScale = 1.12
        state.targetAlpha = 1.0
    elseif targetFrame == 3 then
        -- Raise/confident: big zoom in + full alpha
        state.targetScale = 1.2
        state.targetAlpha = 1.0
    elseif targetFrame == 1 then
        -- Call/check: slight pop
        state.targetScale = 1.08
        state.targetAlpha = 1.0
    else
        -- Neutral/fold: back to normal
        state.targetScale = 1.0
        state.targetAlpha = 0.85
    end
end

function Render.updateAvatarAnims(dt)
    for _, state in pairs(avatarAnimState) do
        -- Blend between frames
        if state.blend < 1.0 then
            state.blend = math.min(1.0, state.blend + dt * 3.0)  -- ~0.33s blend
        end
        -- Smooth scale easing
        local scaleDiff = state.targetScale - state.scale
        state.scale = state.scale + scaleDiff * math.min(dt * 6.0, 1.0)
        -- Smooth alpha easing
        local alphaDiff = state.targetAlpha - state.alpha
        state.alpha = state.alpha + alphaDiff * math.min(dt * 5.0, 1.0)

        -- After action settles, ease back to neutral scale
        if state.blend >= 1.0 and state.targetScale ~= 1.0 then
            state.targetScale = state.targetScale + (1.0 - state.targetScale) * math.min(dt * 1.5, 1.0)
            if math.abs(state.targetScale - 1.0) < 0.005 then
                state.targetScale = 1.0
            end
        end
    end
end

function Render.init()
    fonts.small = love.graphics.newFont(13)
    fonts.normal = love.graphics.newFont(16)
    fonts.medium = love.graphics.newFont(20)
    fonts.large = love.graphics.newFont(28)
    fonts.xlarge = love.graphics.newFont(40)
    fonts.title = love.graphics.newFont(56)
    fonts.card = love.graphics.newFont(15)
    fonts.cardLarge = love.graphics.newFont(26)

    -- Load card images from assets/cards/
    local suits = {"c", "d", "h", "s"}
    local ranks = {"a", "2", "3", "4", "5", "6", "7", "8", "9", "t", "j", "q", "k"}
    local loaded = 0
    for _, s in ipairs(suits) do
        for _, r in ipairs(ranks) do
            local path = "assets/cards/" .. r .. s .. ".png"
            if love.filesystem.getInfo(path) then
                cardImages[r .. s] = love.graphics.newImage(path)
                cardImages[r .. s]:setFilter("linear", "linear")
                loaded = loaded + 1
            end
        end
    end
    -- Card back
    if love.filesystem.getInfo("assets/cards/back.png") then
        cardBackImage = love.graphics.newImage("assets/cards/back.png")
        cardBackImage:setFilter("linear", "linear")
        loaded = loaded + 1
    end

    if loaded >= 52 then
        useImageCards = true
        -- Compute scale: image is 200x280, display at CARD_W x CARD_H
        local imgW = cardImages["ah"]:getWidth()
        cardImageScale = CARD_W / imgW
        print("Loaded " .. loaded .. " card images (scale=" .. string.format("%.2f", cardImageScale) .. ")")
    else
        print("Card images not found (" .. loaded .. "/53), using programmatic rendering")
    end

    -- Load avatar images
    local avatarNames = {"alice", "bob", "charlie", "you"}
    for _, name in ipairs(avatarNames) do
        local path = "assets/avatars/" .. name .. ".png"
        if love.filesystem.getInfo(path) then
            avatarImages[name] = love.graphics.newImage(path)
            avatarImages[name]:setFilter("linear", "linear")
            print("Loaded avatar: " .. name)
        end
        -- Load sprite sheet for animation
        local spritePath = "assets/avatars/" .. name .. "_sprite.png"
        if love.filesystem.getInfo(spritePath) then
            avatarSpriteSheets[name] = love.graphics.newImage(spritePath)
            avatarSpriteSheets[name]:setFilter("linear", "linear")
            print("Loaded avatar sprite: " .. name)
        end
    end

    -- Load table background
    if love.filesystem.getInfo("assets/table_bg.png") then
        tableBgImage = love.graphics.newImage("assets/table_bg.png")
        tableBgImage:setFilter("linear", "linear")
    end
    -- Load title background
    if love.filesystem.getInfo("assets/title_bg.png") then
        titleBgImage = love.graphics.newImage("assets/title_bg.png")
        titleBgImage:setFilter("linear", "linear")
    end
end

function Render.getFont(name)
    return fonts[name] or fonts.normal
end

-- Utility: draw rounded rectangle
local function roundRect(mode, x, y, w, h, r)
    r = r or 6
    love.graphics.rectangle(mode, x, y, w, h, r, r)
end

function Render.drawTable()
    local W, H = 1280, 720  -- use design resolution (scaling handled by main.lua)

    if tableBgImage then
        -- Use Grok-generated table background
        love.graphics.setColor(1, 1, 1)
        local sx = W / tableBgImage:getWidth()
        local sy = H / tableBgImage:getHeight()
        love.graphics.draw(tableBgImage, 0, 0, 0, sx, sy)
    else
        -- Fallback: programmatic table
        -- Dark background
        love.graphics.setColor(C.darkBg)
        love.graphics.rectangle("fill", 0, 0, W, H)

        -- Outer table border (wood)
        love.graphics.setColor(C.borderDark)
        love.graphics.ellipse("fill", W/2, H/2, 520, 290)
        love.graphics.setColor(C.border)
        love.graphics.ellipse("fill", W/2, H/2, 505, 278)

        -- Green felt
        love.graphics.setColor(C.felt)
        love.graphics.ellipse("fill", W/2, H/2, 485, 262)

        -- Felt texture: subtle inner ellipse
        love.graphics.setColor(C.feltLight)
        love.graphics.ellipse("line", W/2, H/2, 400, 210)
        love.graphics.setColor(C.felt)
    end
end

function Render.drawCard(card, x, y, faceUp, scale)
    scale = scale or 1.0
    local w = CARD_W * scale
    local h = CARD_H * scale

    if not faceUp then
        Render.drawCardBack(x, y, scale)
        return
    end

    -- Try image-based rendering
    if useImageCards then
        local fname = Cards.cardFilename(card)
        local img = cardImages[fname]
        if img then
            -- Shadow
            love.graphics.setColor(0, 0, 0, 0.3)
            roundRect("fill", x + 2, y + 2, w, h, 5 * scale)
            -- Draw card image
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, x, y, 0, cardImageScale * scale, cardImageScale * scale)
            return
        end
    end

    -- Fallback: programmatic rendering
    -- Shadow
    love.graphics.setColor(C.shadow)
    roundRect("fill", x + 2, y + 2, w, h, 5 * scale)

    -- Card background
    love.graphics.setColor(C.cardWhite)
    roundRect("fill", x, y, w, h, 5 * scale)

    -- Card border
    love.graphics.setColor(C.cardBorder)
    love.graphics.setLineWidth(1)
    roundRect("line", x, y, w, h, 5 * scale)

    -- Rank and suit
    local col = Cards.suitColor(card.suit)
    love.graphics.setColor(col)

    local rankStr = Cards.rankDisplayString(card.rank)
    local suitStr = Cards.suitSymbol(card.suit)

    -- Top-left rank + suit
    love.graphics.setFont(fonts.card)
    love.graphics.print(rankStr, x + 4 * scale, y + 3 * scale)
    love.graphics.print(suitStr, x + 4 * scale, y + 16 * scale)

    -- Center suit (large)
    love.graphics.setFont(fonts.cardLarge)
    local sw = fonts.cardLarge:getWidth(suitStr)
    love.graphics.print(suitStr, x + w/2 - sw/2, y + h/2 - 16 * scale)

    -- Bottom-right (inverted)
    love.graphics.setFont(fonts.card)
    love.graphics.printf(rankStr, x, y + h - 20 * scale, w - 4 * scale, "right")
    love.graphics.printf(suitStr, x, y + h - 33 * scale, w - 4 * scale, "right")
end

function Render.drawCardBack(x, y, scale)
    scale = scale or 1.0
    local w = CARD_W * scale
    local h = CARD_H * scale

    -- Try image-based rendering
    if cardBackImage then
        love.graphics.setColor(0, 0, 0, 0.3)
        roundRect("fill", x + 2, y + 2, w, h, 5 * scale)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cardBackImage, x, y, 0, cardImageScale * scale, cardImageScale * scale)
        return
    end

    -- Fallback: programmatic
    -- Shadow
    love.graphics.setColor(C.shadow)
    roundRect("fill", x + 2, y + 2, w, h, 5 * scale)

    -- Card back - dark blue
    love.graphics.setColor(0.15, 0.15, 0.55)
    roundRect("fill", x, y, w, h, 5 * scale)

    -- Inner pattern
    love.graphics.setColor(0.2, 0.2, 0.65)
    roundRect("fill", x + 4*scale, y + 4*scale, w - 8*scale, h - 8*scale, 3*scale)

    -- Diamond pattern
    love.graphics.setColor(0.25, 0.25, 0.7)
    local cx, cy = x + w/2, y + h/2
    love.graphics.polygon("fill",
        cx, cy - 18*scale,
        cx + 12*scale, cy,
        cx, cy + 18*scale,
        cx - 12*scale, cy)

    -- Border
    love.graphics.setColor(0.3, 0.3, 0.75)
    love.graphics.setLineWidth(1)
    roundRect("line", x, y, w, h, 5 * scale)
end

function Render.drawPlayer(player, idx, showCards, isCurrentTurn, isDealer)
    local pos = POSITIONS[idx]
    if not pos then return end

    local px, py = pos.x, pos.y
    local isHuman = (idx == 1)
    local boxW, boxH = 150, 80

    -- Current turn highlight with animated glow
    if isCurrentTurn and not player.folded then
        local time = love.timer.getTime()
        local pulse = 0.2 + 0.15 * math.sin(time * 4)
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], pulse * 0.5)
        roundRect("fill", px - boxW/2 - 7, py - boxH/2 - 7, boxW + 14, boxH + 14, 14)
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], pulse)
        roundRect("fill", px - boxW/2, py - boxH/2, boxW, boxH, 10)
    end

    -- Player area background
    local bgAlpha = player.folded and 0.3 or 0.6
    love.graphics.setColor(0, 0, 0, bgAlpha)
    roundRect("fill", px - boxW/2, py - boxH/2, boxW, boxH, 8)

    -- Avatar
    local avatarKey = string.lower(player.name)
    local avatarImg = avatarImages[avatarKey]
    local avatarSprite = avatarSpriteSheets[avatarKey]
    local avSize = AVATAR_DISPLAY
    local avX = px - boxW/2 + 5
    local avY = py - avSize/2

    if avatarSprite then
        -- Event-driven animated avatar with crossfade, zoom, and alpha blending
        local state = avatarAnimState[idx]
        local baseScale = avSize / AVATAR_SIZE
        local foldedAlpha = player.folded and 0.4 or 1
        local animScale = state and state.scale or 1.0
        local animAlpha = state and state.alpha or 1.0
        local finalScale = baseScale * animScale
        local finalAlpha = foldedAlpha * animAlpha

        -- Apply zoom: scale around avatar center
        local centerX = avX + avSize / 2
        local centerY = avY + avSize / 2
        local drawX = centerX - (AVATAR_SIZE * finalScale) / 2
        local drawY = centerY - (AVATAR_SIZE * finalScale) / 2

        if state and state.blend < 1.0 then
            -- Crossfade: draw fromFrame fading out, toFrame fading in
            local t = state.blend
            local eased = t * t * (3 - 2 * t)  -- smoothstep

            -- Draw fromFrame (fading out)
            local fromQuad = love.graphics.newQuad(
                state.fromFrame * AVATAR_SIZE, 0, AVATAR_SIZE, AVATAR_SIZE,
                avatarSprite:getWidth(), avatarSprite:getHeight()
            )
            love.graphics.setColor(1, 1, 1, finalAlpha * (1 - eased))
            love.graphics.draw(avatarSprite, fromQuad, drawX, drawY, 0, finalScale, finalScale)

            -- Draw toFrame (fading in)
            local toQuad = love.graphics.newQuad(
                state.toFrame * AVATAR_SIZE, 0, AVATAR_SIZE, AVATAR_SIZE,
                avatarSprite:getWidth(), avatarSprite:getHeight()
            )
            love.graphics.setColor(1, 1, 1, finalAlpha * eased)
            love.graphics.draw(avatarSprite, toQuad, drawX, drawY, 0, finalScale, finalScale)
        else
            -- Static: show current frame
            local frameIdx = state and state.toFrame or 0
            local quad = love.graphics.newQuad(
                frameIdx * AVATAR_SIZE, 0, AVATAR_SIZE, AVATAR_SIZE,
                avatarSprite:getWidth(), avatarSprite:getHeight()
            )
            love.graphics.setColor(1, 1, 1, finalAlpha)
            love.graphics.draw(avatarSprite, quad, drawX, drawY, 0, finalScale, finalScale)
        end
    elseif avatarImg then
        -- Static avatar
        local avScale = avSize / avatarImg:getWidth()
        love.graphics.setColor(1, 1, 1, player.folded and 0.4 or 1)
        love.graphics.draw(avatarImg, avX, avY, 0, avScale, avScale)
    else
        -- Fallback: colored circle
        love.graphics.setColor(0.3, 0.3, 0.5, player.folded and 0.3 or 0.7)
        love.graphics.circle("fill", avX + avSize/2, py, avSize/2 - 2)
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.5)
        love.graphics.circle("line", avX + avSize/2, py, avSize/2 - 2)
        -- Initial letter
        love.graphics.setFont(fonts.medium)
        love.graphics.setColor(C.white)
        local initial = string.sub(player.name, 1, 1)
        local tw = fonts.medium:getWidth(initial)
        love.graphics.print(initial, avX + avSize/2 - tw/2, py - 10)
    end

    -- Text area (to the right of avatar)
    local textX = avX + avSize + 5
    local textW = boxW - avSize - 15

    -- Name
    love.graphics.setFont(fonts.normal)
    local nameColor = player.folded and C.dimWhite or C.white
    love.graphics.setColor(nameColor)
    love.graphics.printf(player.name, textX, py - 30, textW, "center")

    -- Chips
    love.graphics.setColor(C.gold)
    love.graphics.setFont(fonts.small)
    love.graphics.printf("$" .. player.chips, textX, py - 12, textW, "center")

    -- Last action with pop animation
    if player.lastAction and not player.folded then
        local actionColor = {0.6, 0.9, 0.6}
        if string.find(player.lastAction, "Raise") or player.lastAction == "ALL IN" then
            actionColor = {1, 0.7, 0.2}
        elseif string.find(player.lastAction, "Fold") then
            actionColor = {0.7, 0.3, 0.3}
        end
        love.graphics.setColor(actionColor)
        love.graphics.setFont(fonts.small)
        love.graphics.printf(player.lastAction, textX, py + 4, textW, "center")
    end

    -- Folded indicator with fade
    if player.folded then
        local time = love.timer.getTime()
        local fadeAlpha = 0.5 + 0.2 * math.sin(time * 2)
        love.graphics.setColor(0.6, 0.2, 0.2, fadeAlpha)
        love.graphics.setFont(fonts.small)
        love.graphics.printf("FOLDED", textX, py + 4, textW, "center")
    end

    -- Dealer button
    if isDealer then
        local dx, dy
        if idx == 1 then dx, dy = px + boxW/2 + 10, py - 20
        elseif idx == 2 then dx, dy = px + boxW/2 + 10, py
        elseif idx == 3 then dx, dy = px + boxW/2 + 10, py
        else dx, dy = px - boxW/2 - 15, py end
        love.graphics.setColor(C.gold)
        love.graphics.circle("fill", dx, dy, 12)
        love.graphics.setColor(C.black)
        love.graphics.setFont(fonts.small)
        local tw = fonts.small:getWidth("D")
        love.graphics.print("D", dx - tw/2, dy - 7)
    end

    -- Cards
    if #player.hand > 0 and not player.folded then
        local cardScale = 0.7  -- smaller cards for AI players
        local cw = CARD_W * cardScale
        local ch = CARD_H * cardScale
        local cardY, startX

        if idx == 1 then
            -- Human: below player info, full size
            cardScale = 1.0
            cw = CARD_W
            ch = CARD_H
            cardY = py + 45
            local totalW = #player.hand * (cw + CARD_SPACING) - CARD_SPACING
            startX = px - totalW / 2
        elseif idx == 2 then
            -- Left: cards to the right of info box
            cardY = py - ch / 2
            startX = px + 75
        elseif idx == 3 then
            -- Top: cards below info box
            cardY = py + 45
            local totalW = #player.hand * (cw + CARD_SPACING * cardScale) - CARD_SPACING * cardScale
            startX = px - totalW / 2
        else
            -- Right: cards to the left of info box
            cardY = py - ch / 2
            local totalW = #player.hand * (cw + CARD_SPACING * cardScale) - CARD_SPACING * cardScale
            startX = px - 75 - totalW
        end

        for i, card in ipairs(player.hand) do
            local spacing = (idx == 1) and CARD_SPACING or (CARD_SPACING * cardScale)
            local cx = startX + (i - 1) * (cw + spacing)
            local faceUp = showCards or isHuman
            Render.drawCard(card, cx, cardY, faceUp, cardScale)
        end
    end
end

function Render.drawCommunityCards(cards, x, y, revealCount)
    revealCount = revealCount or #cards
    local totalW = 5 * (CARD_W + CARD_SPACING) - CARD_SPACING
    local startX = x - totalW / 2

    for i = 1, 5 do
        local cx = startX + (i - 1) * (CARD_W + CARD_SPACING)
        if i <= #cards then
            local faceUp = (i <= revealCount)
            Render.drawCard(cards[i], cx, y, faceUp, 1.0)
        else
            love.graphics.setColor(1, 1, 1, 0.08)
            roundRect("line", cx, y, CARD_W, CARD_H, 5)
        end
    end
end

function Render.drawCommunityCardsAnimated(cards, x, y, Easing)
    local totalW = 5 * (CARD_W + CARD_SPACING) - CARD_SPACING
    local startX = x - totalW / 2

    for i = 1, 5 do
        local cx = startX + (i - 1) * (CARD_W + CARD_SPACING)
        if i <= #cards then
            -- Get animation progress for this card
            local animVal = Easing.getValue("comm_" .. i)
            local scale = animVal
            local cardAlpha = animVal

            -- Animate: scale up from 0 + slide down
            love.graphics.push()
            local cardCenterX = cx + CARD_W / 2
            local cardCenterY = y + CARD_H / 2
            love.graphics.translate(cardCenterX, cardCenterY)
            love.graphics.scale(scale, scale)
            love.graphics.translate(-cardCenterX, -cardCenterY - (1 - animVal) * 30)

            Render.drawCard(cards[i], cx, y, true, 1.0)
            love.graphics.pop()
        else
            love.graphics.setColor(1, 1, 1, 0.08)
            roundRect("line", cx, y, CARD_W, CARD_H, 5)
        end
    end
end

function Render.drawPot(amount, x, y, scale)
    if amount <= 0 then return end
    scale = scale or 1.0

    love.graphics.push()
    love.graphics.translate(x, y + 10)
    love.graphics.scale(scale, scale)
    love.graphics.translate(-x, -(y + 10))

    -- Chip stack visual
    local stackCount = math.min(math.ceil(amount / 50), 10)
    for i = 1, stackCount do
        local ox = (i - stackCount/2 - 0.5) * 12
        local oy = -i * 2
        -- Chip shadow
        love.graphics.setColor(0, 0, 0, 0.2)
        love.graphics.circle("fill", x + ox + 1, y + oy + 1, 9)
        -- Chip body
        love.graphics.setColor(0.85, 0.65, 0.13)
        love.graphics.circle("fill", x + ox, y + oy, 9)
        -- Chip edge
        love.graphics.setColor(0.6, 0.4, 0.05)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", x + ox, y + oy, 9)
        -- Chip center
        love.graphics.setColor(1, 0.85, 0.3, 0.5)
        love.graphics.circle("fill", x + ox, y + oy, 4)
    end

    -- Amount text
    love.graphics.setFont(fonts.medium)
    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("$" .. amount, x - 99, y + 14, 200, "center")
    -- Gold text
    love.graphics.setColor(C.gold)
    love.graphics.printf("$" .. amount, x - 100, y + 13, 200, "center")

    love.graphics.pop()
end

function Render.drawButtons(buttons)
    local time = love.timer.getTime()

    for i, btn in ipairs(buttons) do
        if btn.visible == false then goto continue end

        -- Hover scale effect
        local hoverScale = 1.0
        if btn.hovered and btn.enabled then
            hoverScale = 1.06
        end

        local bx, by = btn.x, btn.y
        local bw, bh = btn.w * hoverScale, btn.h * hoverScale
        bx = btn.x + (btn.w - bw) / 2
        by = btn.y + (btn.h - bh) / 2

        -- Glow behind enabled buttons
        if btn.enabled and btn.hovered then
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.2)
            roundRect("fill", bx - 3, by - 3, bw + 6, bh + 6, 9)
        end

        local col
        if not btn.enabled then
            col = C.btnDisable
        elseif btn.hovered then
            col = C.btnHover
        else
            col = C.btnNormal
        end

        love.graphics.setColor(col)
        roundRect("fill", bx, by, bw, bh, 6)

        -- Border
        if btn.enabled then
            local pulse = 0.5 + 0.2 * math.sin(time * 3 + i)
            love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], pulse)
        else
            love.graphics.setColor(0.3, 0.3, 0.3, 0.3)
        end
        love.graphics.setLineWidth(1)
        roundRect("line", bx, by, bw, bh, 6)

        -- Text
        love.graphics.setFont(fonts.normal)
        if btn.enabled then
            love.graphics.setColor(C.white)
        else
            love.graphics.setColor(0.4, 0.4, 0.4)
        end
        love.graphics.printf(btn.text, bx, by + bh/2 - 8, bw, "center")

        ::continue::
    end
end

function Render.drawBackButton(hovered)
    local bx, by, bw, bh = 10, 680, 120, 30
    local col = hovered and C.btnHover or C.btnNormal
    love.graphics.setColor(col)
    roundRect("fill", bx, by, bw, bh, 6)
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.6)
    love.graphics.setLineWidth(1)
    roundRect("line", bx, by, bw, bh, 6)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(C.white)
    love.graphics.printf("Back to Main", bx, by + bh/2 - 7, bw, "center")
end

Render.BACK_BTN = {x = 10, y = 680, w = 120, h = 30}

function Render.drawRaiseControls(raiseAmount, minRaise, maxRaise, buttons)
    -- Raise amount display
    love.graphics.setFont(fonts.medium)
    love.graphics.setColor(C.gold)
    love.graphics.printf("$" .. raiseAmount, 790, 675, 80, "center")
end

function Render.drawMessage(text, subtext, alpha, popScale)
    alpha = alpha or 1.0
    popScale = popScale or 1.0
    local W, H = 1280, 720

    -- Dim overlay
    love.graphics.setColor(0, 0, 0, 0.5 * alpha)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Apply pop scale from center
    love.graphics.push()
    love.graphics.translate(W/2, H/2)
    love.graphics.scale(popScale, popScale)
    love.graphics.translate(-W/2, -H/2)

    -- Message box with glow
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], 0.15 * alpha)
    roundRect("fill", W/2 - 260, H/2 - 80, 520, 160, 18)
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9 * alpha)
    roundRect("fill", W/2 - 250, H/2 - 70, 500, 140, 15)
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], alpha)
    love.graphics.setLineWidth(2)
    roundRect("line", W/2 - 250, H/2 - 70, 500, 140, 15)

    -- Main text
    love.graphics.setFont(fonts.large)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(text, W/2 - 240, H/2 - 45, 480, "center")

    -- Subtext
    if subtext then
        love.graphics.setFont(fonts.normal)
        love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], alpha)
        love.graphics.printf(subtext, W/2 - 240, H/2 + 5, 480, "center")
    end

    love.graphics.pop()
end

function Render.drawHUD(dealerIdx, blinds, roundNum, phase)
    love.graphics.setFont(fonts.large)
    love.graphics.setColor(C.dimWhite)
    love.graphics.print("Round " .. roundNum, 10, 10)
    love.graphics.print("Blinds: $" .. blinds.small .. " / $" .. blinds.big, 10, 42)

    -- Phase indicator
    if phase then
        love.graphics.setColor(C.gold)
        love.graphics.printf(phase, 0, 10, 1270, "right")
    end
end

function Render.drawMenu()
    local W, H = 1280, 720
    local time = love.timer.getTime()

    -- Background
    if titleBgImage then
        love.graphics.setColor(1, 1, 1)
        local sx = W / titleBgImage:getWidth()
        local sy = H / titleBgImage:getHeight()
        love.graphics.draw(titleBgImage, 0, 0, 0, sx, sy)
        -- Dark overlay for readability
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.rectangle("fill", 0, 0, W, H)
    else
        love.graphics.setColor(C.darkBg)
        love.graphics.rectangle("fill", 0, 0, W, H)
        love.graphics.setColor(C.felt)
        love.graphics.ellipse("fill", W/2, H/2 + 40, 350, 180)
        love.graphics.setColor(C.border)
        love.graphics.setLineWidth(4)
        love.graphics.ellipse("line", W/2, H/2 + 40, 355, 183)
    end

    -- Title with subtle float animation
    local titleY = H/2 - 110 + math.sin(time * 1.2) * 5
    love.graphics.setFont(fonts.title)
    -- Title shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("TEXAS HOLD'EM", 3, titleY + 3, W, "center")
    -- Title glow
    local glowPulse = 0.7 + 0.3 * math.sin(time * 2)
    love.graphics.setColor(C.gold[1], C.gold[2], C.gold[3], glowPulse)
    love.graphics.printf("TEXAS HOLD'EM", 0, titleY, W, "center")

    -- Subtitle
    love.graphics.setFont(fonts.medium)
    love.graphics.setColor(0.9, 0.9, 0.9, 0.9)
    love.graphics.printf("No Limit Poker", 0, titleY + 70, W, "center")

    -- Decorative cards with slight sway
    local cx = W/2
    local sway1 = math.sin(time * 0.8) * 3
    local sway2 = math.sin(time * 0.8 + 1) * 3
    Render.drawCardBack(cx - 110, H/2 + 30 + sway1, 0.9)
    Render.drawCardBack(cx - 75, H/2 + 20 + sway2, 0.9)
    Render.drawCard({rank=1, suit=4}, cx + 15, H/2 + 20 + sway1, true, 0.9)
    Render.drawCard({rank=13, suit=3}, cx + 50, H/2 + 30 + sway2, true, 0.9)

    -- Menu buttons
    local menuBtns = {
        {text = "Play Poker",  key = "ENTER", y = H/2 + 110},
        {text = "Learn Hands", key = "L",     y = H/2 + 160},
        {text = "Cheatsheet",  key = "C",     y = H/2 + 210},
    }
    for _, mb in ipairs(menuBtns) do
        local btnW, btnH = 260, 42
        local bx = W/2 - btnW/2
        local by = mb.y

        -- Check hover
        local mx, my = love.mouse.getPosition()
        -- Approximate: menu buttons hover (coordinates may need scaling but works for 1:1)
        local hovered = (mx >= bx and mx <= bx + btnW and my >= by and my <= by + btnH)

        local btnScale = hovered and 1.05 or 1.0
        love.graphics.push()
        love.graphics.translate(bx + btnW/2, by + btnH/2)
        love.graphics.scale(btnScale, btnScale)
        love.graphics.translate(-(bx + btnW/2), -(by + btnH/2))

        -- Button bg
        if hovered then
            love.graphics.setColor(0.85, 0.65, 0.13, 0.3)
            love.graphics.rectangle("fill", bx - 2, by - 2, btnW + 4, btnH + 4, 10, 10)
        end
        love.graphics.setColor(0.1, 0.1, 0.12, 0.85)
        love.graphics.rectangle("fill", bx, by, btnW, btnH, 8, 8)

        -- Border
        local pulse = 0.4 + 0.3 * math.sin(time * 3)
        love.graphics.setColor(0.85, 0.65, 0.13, pulse)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", bx, by, btnW, btnH, 8, 8)

        -- Text
        love.graphics.setFont(fonts.medium)
        love.graphics.setColor(1, 1, 1, hovered and 1 or 0.85)
        love.graphics.printf(mb.text, bx, by + btnH/2 - 10, btnW, "center")

        -- Key hint
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf("[" .. mb.key .. "]", bx + btnW + 8, by + btnH/2 - 6, 60, "left")

        love.graphics.pop()
    end

    -- Credits
    love.graphics.setColor(C.dimWhite)
    love.graphics.setFont(fonts.small)
    love.graphics.printf("1 vs 3 AI Opponents  |  Starting Chips: $1000", 0, H - 40, W, "center")

    -- Store menu button rects for click detection
    Render._menuButtons = menuBtns
end

function Render.drawGameOver(winner, isHuman)
    local W, H = 1280, 720
    local time = love.timer.getTime()

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Floating title
    local titleY = H/2 - 85 + math.sin(time * 1.5) * 4
    love.graphics.setFont(fonts.title)
    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(isHuman and "YOU WIN!" or "GAME OVER", 3, titleY + 3, W, "center")
    -- Text
    if isHuman then
        local glow = 0.8 + 0.2 * math.sin(time * 3)
        love.graphics.setColor(C.gold[1] * glow, C.gold[2] * glow, C.gold[3])
    else
        love.graphics.setColor(0.8, 0.2, 0.2)
    end
    love.graphics.printf(isHuman and "YOU WIN!" or "GAME OVER", 0, titleY, W, "center")

    love.graphics.setFont(fonts.large)
    love.graphics.setColor(C.white)
    love.graphics.printf(winner.name .. " wins the game!", 0, H/2 - 10, W, "center")

    -- Animated chip count
    love.graphics.setFont(fonts.medium)
    local chipScale = 1.0 + 0.03 * math.sin(time * 4)
    love.graphics.push()
    love.graphics.translate(W/2, H/2 + 45)
    love.graphics.scale(chipScale, chipScale)
    love.graphics.translate(-W/2, -(H/2 + 45))
    love.graphics.setColor(C.gold)
    love.graphics.printf("Final chips: $" .. winner.chips, 0, H/2 + 35, W, "center")
    love.graphics.pop()

    local pulse = 0.5 + 0.5 * math.sin(time * 3)
    love.graphics.setColor(1, 1, 1, pulse)
    love.graphics.setFont(fonts.normal)
    love.graphics.printf("Press ENTER to play again", 0, H/2 + 90, W, "center")
end

function Render.drawThinking(idx)
    local pos = POSITIONS[idx]
    if not pos then return end

    local time = love.timer.getTime()
    local dots = string.rep(".", math.floor(time * 3) % 4)

    -- Animated thinking bubble
    local bubbleY = pos.y - 62 + math.sin(time * 4) * 2
    local bubbleAlpha = 0.7 + 0.2 * math.sin(time * 5)

    -- Small bubbles leading to thought
    for i = 1, 3 do
        local bx = pos.x - 25 + i * 8
        local by = pos.y - 42 - i * 5 + math.sin(time * 3 + i) * 2
        local br = 2 + i
        love.graphics.setColor(1, 1, 0.7, bubbleAlpha * 0.5)
        love.graphics.circle("fill", bx, by, br)
    end

    -- Main bubble
    love.graphics.setColor(0, 0, 0, 0.5)
    roundRect("fill", pos.x - 48, bubbleY - 2, 96, 22, 10)
    love.graphics.setColor(0.15, 0.15, 0.1, bubbleAlpha)
    roundRect("fill", pos.x - 50, bubbleY - 3, 96, 22, 10)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 0.5, bubbleAlpha)
    love.graphics.printf("Thinking" .. dots, pos.x - 50, bubbleY, 96, "center")
end

function Render.drawPlayerBet(player, idx)
    if player.bet <= 0 or player.folded then return end
    local pos = POSITIONS[idx]
    if not pos then return end

    -- Position bet chips between player and pot center
    local cx, cy = 640, 300
    local bx, by
    if idx == 1 then
        -- Bottom player: chips above
        bx = pos.x
        by = pos.y - 60
    elseif idx == 3 then
        -- Top player: chips well below (past the cards area)
        bx = pos.x
        by = pos.y + 130
    else
        -- Side players: chips towards center
        bx = pos.x + (cx - pos.x) * 0.45
        by = pos.y + (cy - pos.y) * 0.3
    end

    -- Draw stacked chips based on bet amount
    local chipDefs = {
        {threshold = 500, color = {0.15, 0.15, 0.15}, edge = {0.3, 0.3, 0.3}},
        {threshold = 100, color = {0.2, 0.2, 0.8},    edge = {0.3, 0.3, 0.9}},
        {threshold = 50,  color = {0.8, 0.15, 0.15},   edge = {0.9, 0.25, 0.25}},
        {threshold = 10,  color = {0.85, 0.65, 0.13},  edge = {0.65, 0.45, 0.05}},
    }
    local remaining = player.bet
    local stackX = bx
    local chipIdx = 0
    for _, def in ipairs(chipDefs) do
        local count = math.floor(remaining / def.threshold)
        count = math.min(count, 5)
        for j = 1, count do
            chipIdx = chipIdx + 1
            local cy2 = by - (chipIdx - 1) * 4
            -- Shadow
            love.graphics.setColor(0, 0, 0, 0.2)
            love.graphics.circle("fill", stackX + 1, cy2 + 1, 10)
            -- Chip
            love.graphics.setColor(def.color)
            love.graphics.circle("fill", stackX, cy2, 10)
            love.graphics.setColor(def.edge)
            love.graphics.setLineWidth(1.5)
            love.graphics.circle("line", stackX, cy2, 10)
            -- Dashes
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.circle("line", stackX, cy2, 6)
            remaining = remaining - def.threshold
        end
    end

    -- Amount text
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.printf("$" .. player.bet, bx - 29, by + 14, 60, "center")
    love.graphics.setColor(C.white)
    love.graphics.printf("$" .. player.bet, bx - 30, by + 13, 60, "center")
end

function Render.drawShowdownInfo(player, idx, evalResult)
    if not evalResult or player.folded then return end
    local pos = POSITIONS[idx]
    if not pos then return end

    local isBottom = (idx == 1)
    local infoY = isBottom and (pos.y + 108) or (pos.y + 42)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(C.gold)
    love.graphics.printf(evalResult.name, pos.x - 80, infoY, 160, "center")
end

return Render
