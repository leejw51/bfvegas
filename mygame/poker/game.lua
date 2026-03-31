-- game.lua - Game state machine for Texas Hold'em

local Cards = require("cards")
local HandEval = require("hand_eval")
local AI = require("ai")
local Render = require("render")
local Easing = require("easing")

local Game = {}

local game = {}

-- Forward declarations
local startNewRound, startBettingRound, advanceToNextPlayer, processBet
local checkBettingRoundOver, advancePhase, doShowdown, awardPot
local createButtons, updateButtons, getActivePlayers, getActiveNonFolded

local SMALL_BLIND = 10
local BIG_BLIND = 20

local phaseNames = {
    menu = "Menu",
    dealing = "Dealing",
    preflop = "Pre-Flop",
    flop_deal = "Dealing Flop",
    flop_bet = "Flop",
    turn_deal = "Dealing Turn",
    turn_bet = "Turn",
    river_deal = "Dealing River",
    river_bet = "River",
    showdown = "Showdown",
    round_end = "Round End",
    game_over = "Game Over",
}

function Game.init()
    game = {
        state = "menu",
        players = {},
        deck = {},
        communityCards = {},
        pot = 0,
        currentBet = 0,
        dealerIdx = 1,
        currentPlayerIdx = 1,
        roundNum = 0,
        timer = 0,
        buttons = {},
        raiseAmount = BIG_BLIND,
        minRaise = BIG_BLIND,
        message = nil, -- {text, subtext, timer}
        showdownResults = {},
        showdownRevealed = 0,
        dealingCards = {},  -- animation queue
        dealingTimer = 0,
        aiTimer = 0,
        cardAnims = {},
        communityAnims = {},
        chipAnims = {},     -- flying chip animations
        potDisplay = 0,     -- animated pot display value
        foldAnims = {},     -- {[playerIdx] = timer}
        phaseAnim = 0,      -- phase transition timer
        bettingStarted = false,
        actedThisRound = {},
        lastRaiser = nil,
        winnersThisRound = {},
        humanActionNeeded = false,
    }

    -- Create players
    game.players[1] = {
        name = "You",
        style = "human",
        chips = 1000,
        hand = {},
        folded = false,
        bet = 0,
        seat = 1,
        isAI = false,
        allIn = false,
        lastAction = nil,
    }
    game.players[2] = AI.createPlayer("Alice", "aggressive", 2)
    game.players[3] = AI.createPlayer("Bob", "conservative", 3)
    game.players[4] = AI.createPlayer("Charlie", "balanced", 4)

    game.buttons = createButtons()
end

function Game.getState()
    return game
end

createButtons = function()
    return {
        {text = "Fold",  x = 380, y = 668, w = 120, h = 42, action = "fold",  enabled = false, hovered = false, visible = true},
        {text = "Check", x = 520, y = 668, w = 120, h = 42, action = "check", enabled = false, hovered = false, visible = true},
        {text = "Raise", x = 660, y = 668, w = 120, h = 42, action = "raise", enabled = false, hovered = false, visible = true},
        {text = "-",     x = 795, y = 672, w = 35,  h = 35, action = "raise_down", enabled = false, hovered = false, visible = true},
        {text = "+",     x = 870, y = 672, w = 35,  h = 35, action = "raise_up",   enabled = false, hovered = false, visible = true},
    }
end

getActiveNonFolded = function()
    local active = {}
    for i, p in ipairs(game.players) do
        if not p.folded and p.chips > 0 then
            active[#active + 1] = i
        elseif not p.folded and p.allIn then
            active[#active + 1] = i
        end
    end
    return active
end

local function countNonFolded()
    local count = 0
    for _, p in ipairs(game.players) do
        if not p.folded then count = count + 1 end
    end
    return count
end

local function countPlayersWithChips()
    local count = 0
    for _, p in ipairs(game.players) do
        if p.chips > 0 then count = count + 1 end
    end
    return count
end

-- Spawn flying chip animation from player to pot (or pot to player)
local function spawnChipAnim(fromIdx, toCenter, amount)
    local fromPos = Render.POSITIONS[fromIdx]
    if not fromPos then return end
    local toX, toY = 640, 260  -- pot position
    local fX, fY = fromPos.x, fromPos.y
    if not toCenter then
        -- Reverse: pot to player
        fX, fY, toX, toY = toX, toY, fX, fY
    end
    -- Spawn multiple chips with slight offsets
    local chipCount = math.min(math.ceil(amount / 20), 8)
    for i = 1, chipCount do
        local delay = (i - 1) * 0.06
        local id = "chip_" .. love.timer.getTime() .. "_" .. i .. "_" .. math.random(1000)
        game.chipAnims[#game.chipAnims + 1] = {
            fromX = fX + (math.random() - 0.5) * 20,
            fromY = fY,
            toX = toX + (math.random() - 0.5) * 30,
            toY = toY + (math.random() - 0.5) * 10,
            delay = delay,
            elapsed = 0,
            duration = 0.4 + math.random() * 0.15,
            amount = amount,
            active = true,
        }
    end
end

local function nextPlayerIdx(idx)
    local n = #game.players
    local next = idx % n + 1
    return next
end

local function nextActivePlayer(startIdx)
    local idx = startIdx
    for _ = 1, #game.players do
        idx = nextPlayerIdx(idx)
        local p = game.players[idx]
        if not p.folded and not p.allIn and p.chips > 0 then
            return idx
        end
    end
    return nil
end

startNewRound = function()
    game.roundNum = game.roundNum + 1
    game.communityCards = {}
    game.pot = 0
    game.potDisplay = 0
    game.currentBet = 0
    game.showdownResults = {}
    game.showdownRevealed = 0
    game.message = nil
    game.winnersThisRound = {}
    game.chipAnims = {}
    game.foldAnims = {}
    Easing.clearParticles()

    -- Reset players
    for _, p in ipairs(game.players) do
        p.hand = {}
        p.folded = (p.chips <= 0)
        p.bet = 0
        p.allIn = false
        p.lastAction = nil
    end

    -- New round flash
    Easing.tween("new_round", 0.8, Easing.easeOutExpo)

    -- Move dealer
    local startDealer = game.dealerIdx
    for _ = 1, #game.players do
        game.dealerIdx = nextPlayerIdx(game.dealerIdx)
        if game.players[game.dealerIdx].chips > 0 then break end
    end

    -- Create and shuffle deck
    game.deck = Cards.newDeck()

    -- Post blinds
    local sbIdx = game.dealerIdx
    for _ = 1, #game.players do
        sbIdx = nextPlayerIdx(sbIdx)
        if not game.players[sbIdx].folded then break end
    end
    local bbIdx = sbIdx
    for _ = 1, #game.players do
        bbIdx = nextPlayerIdx(bbIdx)
        if not game.players[bbIdx].folded then break end
    end

    -- Small blind
    local sbAmount = math.min(SMALL_BLIND, game.players[sbIdx].chips)
    game.players[sbIdx].chips = game.players[sbIdx].chips - sbAmount
    game.players[sbIdx].bet = sbAmount
    game.pot = game.pot + sbAmount
    game.players[sbIdx].lastAction = "SB $" .. sbAmount
    if game.players[sbIdx].chips == 0 then game.players[sbIdx].allIn = true end
    spawnChipAnim(sbIdx, true, sbAmount)

    -- Big blind
    local bbAmount = math.min(BIG_BLIND, game.players[bbIdx].chips)
    game.players[bbIdx].chips = game.players[bbIdx].chips - bbAmount
    game.players[bbIdx].bet = bbAmount
    game.pot = game.pot + bbAmount
    game.players[bbIdx].lastAction = "BB $" .. bbAmount
    if game.players[bbIdx].chips == 0 then game.players[bbIdx].allIn = true end
    spawnChipAnim(bbIdx, true, bbAmount)

    game.currentBet = BIG_BLIND
    game.bbIdx = bbIdx
    game.sbIdx = sbIdx

    -- Deal cards (animation)
    game.state = "dealing"
    game.dealingTimer = 0
    game.dealingCards = {}
    local dealOrder = {}
    local idx = nextPlayerIdx(game.dealerIdx)
    for _ = 1, #game.players do
        if not game.players[idx].folded then
            dealOrder[#dealOrder + 1] = idx
        end
        idx = nextPlayerIdx(idx)
    end

    local cardIdx = 0
    for round = 1, 2 do
        for _, pIdx in ipairs(dealOrder) do
            cardIdx = cardIdx + 1
            game.dealingCards[#game.dealingCards + 1] = {
                playerIdx = pIdx,
                cardNum = round,
                delay = cardIdx * 0.12,
                dealt = false,
            }
        end
    end
end

startBettingRound = function(startFromIdx)
    game.actedThisRound = {}
    game.lastRaiser = nil
    game.humanActionNeeded = false

    -- Reset per-round bets
    for _, p in ipairs(game.players) do
        p.bet = 0
        if not p.folded then
            p.lastAction = nil
        end
    end
    game.currentBet = 0

    -- Find first active player
    local idx = startFromIdx
    for _ = 1, #game.players do
        local p = game.players[idx]
        if not p.folded and not p.allIn and p.chips > 0 then
            game.currentPlayerIdx = idx
            break
        end
        idx = nextPlayerIdx(idx)
    end

    game.aiTimer = 0
    game.bettingStarted = true

    -- Check if only one non-folded player or no one can act
    if countNonFolded() <= 1 then
        advancePhase()
        return
    end

    local canAct = 0
    for _, p in ipairs(game.players) do
        if not p.folded and not p.allIn and p.chips > 0 then canAct = canAct + 1 end
    end
    if canAct == 0 then
        advancePhase()
        return
    end
end

updateButtons = function()
    local p = game.players[1]
    local isMyTurn = (game.currentPlayerIdx == 1 and game.humanActionNeeded)
    local toCall = game.currentBet - p.bet

    for _, btn in ipairs(game.buttons) do
        btn.enabled = false
    end

    if not isMyTurn or p.folded then return end

    -- Fold
    game.buttons[1].enabled = true

    -- Check/Call
    if toCall <= 0 then
        game.buttons[2].text = "Check"
        game.buttons[2].enabled = true
    else
        game.buttons[2].text = "Call $" .. math.min(toCall, p.chips)
        game.buttons[2].enabled = true
    end

    -- Raise
    if p.chips > toCall then
        game.buttons[3].enabled = true
        game.minRaise = math.max(BIG_BLIND, game.currentBet * 2 - p.bet)
        if game.raiseAmount < toCall + BIG_BLIND then
            game.raiseAmount = toCall + BIG_BLIND
        end
        game.raiseAmount = math.min(game.raiseAmount, p.chips)
        game.buttons[3].text = "Raise"
        game.buttons[4].enabled = true
        game.buttons[5].enabled = true
    end
end

processBet = function(playerIdx, action, amount)
    local p = game.players[playerIdx]

    if action == "fold" then
        p.folded = true
        p.lastAction = "Fold"
        -- Fold animation
        game.foldAnims[playerIdx] = 0
        Easing.tween("fold_" .. playerIdx, 0.5, Easing.easeInExpo)
        -- Action label pop
        Easing.tween("action_" .. playerIdx, 0.4, Easing.easeOutBack)
    elseif action == "check" then
        p.lastAction = "Check"
        Easing.tween("action_" .. playerIdx, 0.4, Easing.easeOutBack)
    elseif action == "call" then
        local toCall = math.min(game.currentBet - p.bet, p.chips)
        p.chips = p.chips - toCall
        p.bet = p.bet + toCall
        game.pot = game.pot + toCall
        p.lastAction = "Call $" .. toCall
        if p.chips == 0 then p.allIn = true; p.lastAction = "ALL IN" end
        -- Chip fly animation
        spawnChipAnim(playerIdx, true, toCall)
        Easing.tween("action_" .. playerIdx, 0.4, Easing.easeOutBack)
        Easing.tween("pot_bump", 0.3, Easing.easeOutElastic)
    elseif action == "raise" then
        local totalBet = amount
        local additional = totalBet - p.bet
        additional = math.min(additional, p.chips)
        p.chips = p.chips - additional
        p.bet = p.bet + additional
        game.pot = game.pot + additional
        game.currentBet = p.bet
        game.lastRaiser = playerIdx
        p.lastAction = "Raise $" .. p.bet
        if p.chips == 0 then p.allIn = true; p.lastAction = "ALL IN" end
        -- Chip fly + screen shake for raise
        spawnChipAnim(playerIdx, true, additional)
        Easing.tween("action_" .. playerIdx, 0.4, Easing.easeOutBack)
        Easing.tween("pot_bump", 0.3, Easing.easeOutElastic)
        if additional >= 100 then
            Easing.startShake(2, 0.15)
        end
        -- Reset acted flags for others
        for i, _ in ipairs(game.players) do
            if i ~= playerIdx then
                game.actedThisRound[i] = false
            end
        end
    end

    game.actedThisRound[playerIdx] = true
end

checkBettingRoundOver = function()
    -- Check if only one player left
    if countNonFolded() <= 1 then return true end

    -- Everyone who can act must have acted and matched the bet
    for i, p in ipairs(game.players) do
        if not p.folded and not p.allIn and p.chips > 0 then
            if not game.actedThisRound[i] then return false end
            if p.bet < game.currentBet then return false end
        end
    end
    return true
end

advancePhase = function()
    -- Check if only one player remains
    if countNonFolded() <= 1 then
        for i, p in ipairs(game.players) do
            if not p.folded then
                local wonAmount = game.pot
                p.chips = p.chips + wonAmount
                game.winnersThisRound = {i}
                game.message = {
                    text = p.name .. " wins $" .. wonAmount .. "!",
                    subtext = "Everyone else folded",
                    timer = 2.5,
                }
                -- Chips fly from pot to winner
                spawnChipAnim(i, false, wonAmount)
                Easing.tween("msg_pop", 0.5, Easing.easeOutElastic)
                -- Celebration particles
                local pos = Render.POSITIONS[i]
                if pos then
                    Easing.spawnParticles(pos.x, pos.y, 20, {color = {1, 0.85, 0.2}, speed = 120, life = 1.5})
                end
                game.pot = 0
                break
            end
        end
        game.state = "round_end"
        game.timer = 2.5
        return
    end

    local s = game.state
    if s == "preflop" then
        game.state = "flop_deal"
        game.timer = 0
        game.dealingTimer = 0
        Easing.tween("phase_flash", 0.6, Easing.easeOutExpo)
    elseif s == "flop_bet" then
        game.state = "turn_deal"
        game.timer = 0
        Easing.tween("phase_flash", 0.6, Easing.easeOutExpo)
    elseif s == "turn_bet" then
        game.state = "river_deal"
        game.timer = 0
        Easing.tween("phase_flash", 0.6, Easing.easeOutExpo)
    elseif s == "river_bet" then
        game.state = "showdown"
        game.timer = 0
        game.showdownRevealed = 0
        Easing.tween("phase_flash", 0.8, Easing.easeOutExpo)
    end
end

advanceToNextPlayer = function()
    if checkBettingRoundOver() then
        advancePhase()
        return
    end

    local idx = game.currentPlayerIdx
    local found = nextActivePlayer(idx)

    if found then
        game.currentPlayerIdx = found
        game.aiTimer = 0
    else
        advancePhase()
    end
end

doShowdown = function()
    game.showdownResults = {}
    for i, p in ipairs(game.players) do
        if not p.folded then
            local allCards = {}
            for _, c in ipairs(p.hand) do allCards[#allCards + 1] = c end
            for _, c in ipairs(game.communityCards) do allCards[#allCards + 1] = c end
            local eval = HandEval.evaluate(allCards)
            game.showdownResults[i] = eval
        end
    end

    -- Find winner(s)
    local bestScore = -1
    local winners = {}
    for i, eval in pairs(game.showdownResults) do
        if eval.score > bestScore then
            bestScore = eval.score
            winners = {i}
        elseif eval.score == bestScore then
            winners[#winners + 1] = i
        end
    end

    game.winnersThisRound = winners
    awardPot(winners)
end

awardPot = function(winners)
    if #winners == 0 then return end
    local share = math.floor(game.pot / #winners)
    local remainder = game.pot - share * #winners

    for idx, wIdx in ipairs(winners) do
        local bonus = (idx == 1) and remainder or 0
        game.players[wIdx].chips = game.players[wIdx].chips + share + bonus
    end

    -- Build message
    local winnerNames = {}
    for _, wIdx in ipairs(winners) do
        winnerNames[#winnerNames + 1] = game.players[wIdx].name
    end
    local evalName = game.showdownResults[winners[1]] and game.showdownResults[winners[1]].name or ""

    local msgText
    if #winners == 1 then
        msgText = winnerNames[1] .. " wins $" .. game.pot .. "!"
    else
        msgText = table.concat(winnerNames, " & ") .. " split $" .. game.pot .. "!"
    end

    local subtext = evalName
    if #winners == 1 and winners[1] == 1 then
        local funMessages = {"Nice hand!", "Well played!", "Impressive!", "You got this!"}
        subtext = evalName .. " - " .. funMessages[math.random(#funMessages)]
    elseif #winners == 1 and game.showdownResults[winners[1]] then
        local aiMsgs = {"A worthy opponent!", "Good cards!", "Well earned!"}
        subtext = evalName .. " - " .. aiMsgs[math.random(#aiMsgs)]
    end

    game.message = {text = msgText, subtext = subtext, timer = 3.0}

    -- Chips fly from pot to each winner
    for _, wIdx in ipairs(winners) do
        spawnChipAnim(wIdx, false, share)
    end

    -- Spawn celebration particles at winner positions
    for _, wIdx in ipairs(winners) do
        local pos = Render.POSITIONS[wIdx]
        if pos then
            local goldColor = {1, 0.85, 0.2}
            Easing.spawnParticles(pos.x, pos.y, 30, {color = goldColor, speed = 150, life = 2.0, size = 5})
            if wIdx == 1 then
                -- Extra particles for human player win
                Easing.spawnParticles(pos.x, pos.y, 20, {color = {1, 0.4, 0.1}, speed = 200, life = 1.8, size = 6})
            end
        end
    end
    -- Screen shake on big wins
    if share >= 200 then
        Easing.startShake(4, 0.3)
    end
    -- Message pop-in animation
    Easing.tween("msg_pop", 0.5, Easing.easeOutElastic)

    game.pot = 0
end

function Game.update(dt)
    -- Update all animations/particles
    Easing.update(dt)
    Easing.updateParticles(dt)
    Easing.updateShake(dt)

    -- Animate pot display smoothly towards actual pot
    if game.potDisplay then
        local diff = game.pot - game.potDisplay
        if math.abs(diff) < 1 then
            game.potDisplay = game.pot
        else
            game.potDisplay = game.potDisplay + diff * math.min(dt * 8, 1)
        end
    end

    -- Update chip flight animations
    local i = 1
    while i <= #game.chipAnims do
        local ca = game.chipAnims[i]
        ca.elapsed = ca.elapsed + dt
        if ca.elapsed - ca.delay >= ca.duration then
            table.remove(game.chipAnims, i)
        else
            i = i + 1
        end
    end

    local s = game.state

    if s == "menu" then
        return

    elseif s == "dealing" then
        game.dealingTimer = game.dealingTimer + dt
        local allDealt = true
        for _, d in ipairs(game.dealingCards) do
            if not d.dealt and game.dealingTimer >= d.delay then
                d.dealt = true
                local card = Cards.deal(game.deck, 1)[1]
                local p = game.players[d.playerIdx]
                p.hand[#p.hand + 1] = card
                -- Trigger card slide-in animation
                local animId = "deal_" .. d.playerIdx .. "_" .. d.cardNum
                Easing.tween(animId, 0.35, Easing.easeOutBack)
            end
            if not d.dealt then allDealt = false end
        end
        if allDealt then
            -- Start preflop betting
            game.state = "preflop"
            -- Start from player after big blind
            local startIdx = game.bbIdx
            startIdx = nextPlayerIdx(startIdx)
            -- Find first active player from there
            for _ = 1, #game.players do
                if not game.players[startIdx].folded and not game.players[startIdx].allIn and game.players[startIdx].chips > 0 then
                    break
                end
                startIdx = nextPlayerIdx(startIdx)
            end

            game.actedThisRound = {}
            game.lastRaiser = nil
            game.humanActionNeeded = false
            game.currentPlayerIdx = startIdx
            game.currentBet = BIG_BLIND
            game.bettingStarted = true
            game.aiTimer = 0
        end

    elseif s == "preflop" or s == "flop_bet" or s == "turn_bet" or s == "river_bet" then
        -- Betting round logic
        if checkBettingRoundOver() then
            advancePhase()
            return
        end

        local cp = game.players[game.currentPlayerIdx]
        if cp.folded or cp.allIn or cp.chips <= 0 then
            game.actedThisRound[game.currentPlayerIdx] = true
            advanceToNextPlayer()
            return
        end

        if cp.isAI then
            game.aiTimer = game.aiTimer + dt
            if game.aiTimer >= 0.7 then
                -- AI decides
                local gameState = {
                    communityCards = game.communityCards,
                    pot = game.pot,
                    currentBet = game.currentBet,
                    playerBet = cp.bet,
                    phase = game.state,
                    bigBlind = BIG_BLIND,
                }
                local decision = AI.decide(cp, gameState)
                processBet(game.currentPlayerIdx, decision.action, decision.amount)
                advanceToNextPlayer()
            end
        else
            -- Human player turn
            game.humanActionNeeded = true
            updateButtons()
        end

    elseif s == "flop_deal" then
        game.timer = game.timer + dt
        if game.timer >= 0.3 and #game.communityCards < 3 then
            local card = Cards.deal(game.deck, 1)[1]
            game.communityCards[#game.communityCards + 1] = card
            -- Flip-in animation for each community card
            local idx = #game.communityCards
            Easing.tween("comm_" .. idx, 0.4, Easing.easeOutBack)
            game.timer = 0.1
        end
        if #game.communityCards >= 3 then
            game.state = "flop_bet"
            local startIdx = nextPlayerIdx(game.dealerIdx)
            for _ = 1, #game.players do
                if not game.players[startIdx].folded and not game.players[startIdx].allIn and game.players[startIdx].chips > 0 then
                    break
                end
                startIdx = nextPlayerIdx(startIdx)
            end
            startBettingRound(startIdx)
        end

    elseif s == "turn_deal" then
        game.timer = game.timer + dt
        if game.timer >= 0.4 then
            local card = Cards.deal(game.deck, 1)[1]
            game.communityCards[#game.communityCards + 1] = card
            Easing.tween("comm_" .. #game.communityCards, 0.4, Easing.easeOutBack)
            game.state = "turn_bet"
            local startIdx = nextPlayerIdx(game.dealerIdx)
            for _ = 1, #game.players do
                if not game.players[startIdx].folded and not game.players[startIdx].allIn and game.players[startIdx].chips > 0 then
                    break
                end
                startIdx = nextPlayerIdx(startIdx)
            end
            startBettingRound(startIdx)
        end

    elseif s == "river_deal" then
        game.timer = game.timer + dt
        if game.timer >= 0.4 then
            local card = Cards.deal(game.deck, 1)[1]
            game.communityCards[#game.communityCards + 1] = card
            Easing.tween("comm_" .. #game.communityCards, 0.4, Easing.easeOutBack)
            game.state = "river_bet"
            local startIdx = nextPlayerIdx(game.dealerIdx)
            for _ = 1, #game.players do
                if not game.players[startIdx].folded and not game.players[startIdx].allIn and game.players[startIdx].chips > 0 then
                    break
                end
                startIdx = nextPlayerIdx(startIdx)
            end
            startBettingRound(startIdx)
        end

    elseif s == "showdown" then
        game.timer = game.timer + dt
        if game.showdownRevealed == 0 then
            doShowdown()
            game.showdownRevealed = 1
            game.timer = 0
        end
        if game.timer >= 3.5 then
            game.state = "round_end"
            game.timer = 0
        end

    elseif s == "round_end" then
        game.timer = game.timer + dt
        if game.message then
            game.message.timer = game.message.timer - dt
        end
        if game.timer >= 3.0 then
            -- Check for game over
            local alive = countPlayersWithChips()
            if alive <= 1 then
                game.state = "game_over"
                return
            end
            -- Eliminate broke players
            for _, p in ipairs(game.players) do
                if p.chips <= 0 then p.folded = true end
            end
            startNewRound()
        end

    elseif s == "game_over" then
        -- Wait for restart
    end
end

function Game.keypressed(key)
    if game.state == "menu" then
        if key == "return" or key == "space" then
            startNewRound()
        end
    elseif game.state == "game_over" then
        if key == "return" or key == "space" then
            Game.init()
            startNewRound()
        end
    end
end

function Game.mousepressed(mx, my, button)
    if button ~= 1 then return end

    -- Menu clicks
    if game.state == "menu" then
        local btnW, btnH = 260, 42
        local bx = 640 - btnW/2
        -- "Play Poker" button at y = 360 + 120 = 480
        local by1 = 480
        if mx >= bx and mx <= bx + btnW and my >= by1 and my <= by1 + btnH then
            startNewRound()
            return
        end
        return
    end

    for _, btn in ipairs(game.buttons) do
        if btn.enabled and btn.visible ~= false then
            if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
                Game.handleButton(btn.action)
                return
            end
        end
    end
end

function Game.mousemoved(mx, my)
    for _, btn in ipairs(game.buttons) do
        btn.hovered = (btn.enabled and mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h)
    end
end

function Game.handleButton(action)
    if not game.humanActionNeeded then return end
    local p = game.players[1]

    if action == "fold" then
        processBet(1, "fold", 0)
        game.humanActionNeeded = false
        advanceToNextPlayer()
    elseif action == "check" then
        local toCall = game.currentBet - p.bet
        if toCall <= 0 then
            processBet(1, "check", 0)
        else
            processBet(1, "call", 0)
        end
        game.humanActionNeeded = false
        advanceToNextPlayer()
    elseif action == "raise" then
        processBet(1, "raise", game.raiseAmount)
        game.humanActionNeeded = false
        advanceToNextPlayer()
    elseif action == "raise_up" then
        game.raiseAmount = math.min(p.chips, game.raiseAmount + BIG_BLIND)
    elseif action == "raise_down" then
        local minR = game.currentBet - p.bet + BIG_BLIND
        game.raiseAmount = math.max(minR, game.raiseAmount - BIG_BLIND)
    end
end

function Game.draw()
    if game.state == "menu" then
        Render.drawMenu()
        return
    end

    -- Apply screen shake
    local shakeX, shakeY = Easing.getShakeOffset()
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Draw table
    Render.drawTable()

    -- Draw HUD
    local phaseName = phaseNames[game.state] or game.state
    Render.drawHUD(game.dealerIdx, {small = SMALL_BLIND, big = BIG_BLIND}, game.roundNum, phaseName)

    -- Draw community cards with pop-in animation
    if #game.communityCards > 0 then
        Render.drawCommunityCardsAnimated(game.communityCards, 640, 290, Easing)
    end

    -- Draw pot (animated value) with bump effect
    local potBump = Easing.getValue("pot_bump")
    local potScale = 1.0 + (1.0 - potBump) * 0.2  -- slight scale on new chips
    Render.drawPot(math.floor(game.potDisplay or game.pot), 640, 250, potScale)

    -- Draw players
    local showAll = (game.state == "showdown" or game.state == "round_end") and game.showdownRevealed > 0
    for i, p in ipairs(game.players) do
        local isCurrent = (i == game.currentPlayerIdx and
            (game.state == "preflop" or game.state == "flop_bet" or game.state == "turn_bet" or game.state == "river_bet"))
        local isDealer = (i == game.dealerIdx)
        Render.drawPlayer(p, i, showAll, isCurrent, isDealer)

        -- Draw bets
        Render.drawPlayerBet(p, i)

        -- Draw showdown info
        if showAll and game.showdownResults[i] then
            Render.drawShowdownInfo(p, i, game.showdownResults[i])
        end

        -- Draw thinking indicator for AI
        if isCurrent and p.isAI and not p.folded then
            Render.drawThinking(i)
        end
    end

    -- Highlight winners
    if (game.state == "showdown" or game.state == "round_end") and #game.winnersThisRound > 0 then
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
        for _, wIdx in ipairs(game.winnersThisRound) do
            local pos = Render.POSITIONS[wIdx]
            if pos then
                love.graphics.setColor(Render.C.gold[1], Render.C.gold[2], Render.C.gold[3], 0.3 * pulse)
                love.graphics.rectangle("fill", pos.x - 80, pos.y - 50, 160, 100, 10, 10)
            end
        end
    end

    -- Draw buttons (during betting rounds for human)
    if game.humanActionNeeded then
        updateButtons()
        Render.drawButtons(game.buttons)
        if game.buttons[3].enabled then
            Render.drawRaiseControls(game.raiseAmount, game.minRaise, game.players[1].chips)
        end
    end

    -- Draw flying chip animations
    for _, ca in ipairs(game.chipAnims) do
        local t = (ca.elapsed - ca.delay) / ca.duration
        if t >= 0 and t <= 1 then
            local eased = Easing.easeOutCubic(t)
            local cx = ca.fromX + (ca.toX - ca.fromX) * eased
            local cy = ca.fromY + (ca.toY - ca.fromY) * eased
            -- Arc: chips fly in a slight parabola
            cy = cy - math.sin(eased * math.pi) * 40
            -- Scale: start big, shrink slightly
            local s = 1.0 - eased * 0.3
            local alpha = 1.0 - eased * 0.3

            -- Draw chip
            love.graphics.setColor(0.85, 0.65, 0.13, alpha)
            love.graphics.circle("fill", cx, cy, 10 * s)
            love.graphics.setColor(0.6, 0.4, 0.05, alpha)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", cx, cy, 10 * s)
            -- Inner detail
            love.graphics.setColor(1, 0.85, 0.3, alpha * 0.6)
            love.graphics.circle("fill", cx, cy, 5 * s)
        end
    end

    -- Phase transition flash
    local phaseFlash = 1.0 - Easing.getValue("phase_flash")
    if phaseFlash > 0.01 then
        love.graphics.setColor(1, 1, 1, phaseFlash * 0.15)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
    end

    -- Draw particles
    Easing.drawParticles()

    -- Draw message overlay with pop animation
    if game.message and game.message.timer and game.message.timer > 0 then
        local alpha = math.min(1, game.message.timer / 0.5)
        local popScale = Easing.getValue("msg_pop")
        Render.drawMessage(game.message.text, game.message.subtext, alpha, popScale)
    end

    -- Game over
    if game.state == "game_over" then
        local winner = game.players[1]
        for _, p in ipairs(game.players) do
            if p.chips > winner.chips then winner = p end
        end
        Render.drawGameOver(winner, winner == game.players[1])
    end

    love.graphics.pop() -- end shake transform
end

function Game.getState()
    return game.state
end

return Game
