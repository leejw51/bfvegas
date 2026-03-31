-- ai.lua - AI players module for Texas Hold'em

local HandEval = require("hand_eval")

local AI = {}

function AI.createPlayer(name, style, seat)
    return {
        name = name,
        style = style,
        chips = 1000,
        hand = {},
        folded = false,
        bet = 0,
        seat = seat,
        isAI = true,
        allIn = false,
        lastAction = nil,
    }
end

function AI.decide(player, gameState)
    local communityCards = gameState.communityCards or {}
    local pot = gameState.pot or 0
    local currentBet = gameState.currentBet or 0
    local playerBet = player.bet or 0
    local toCall = currentBet - playerBet
    local chips = player.chips

    -- Estimate hand strength
    local strength = 0
    if #communityCards >= 3 and #player.hand >= 2 then
        local allCards = {}
        for _, c in ipairs(player.hand) do allCards[#allCards + 1] = c end
        for _, c in ipairs(communityCards) do allCards[#allCards + 1] = c end
        local eval = HandEval.evaluate(allCards)
        -- Normalize: handRank 1-10 mapped to 0-1
        local handRank = math.floor(eval.score / 10000000)
        strength = handRank / 10
        -- Boost for higher kickers within same hand rank
        strength = strength + (eval.score % 10000000) / 100000000
    elseif #player.hand >= 2 then
        strength = HandEval.estimateHoleCards(player.hand[1], player.hand[2])
    end

    -- Add some randomness
    local noise = (math.random() - 0.5) * 0.15
    local perceivedStrength = math.max(0, math.min(1, strength + noise))

    -- Pot odds
    local potOdds = 0
    if pot + toCall > 0 then
        potOdds = toCall / (pot + toCall)
    end

    local style = player.style
    local action, amount

    -- Style-based thresholds
    local foldThreshold, raiseThreshold, bluffChance, raiseMultiplier
    if style == "aggressive" then
        foldThreshold = 0.2
        raiseThreshold = 0.35
        bluffChance = 0.20
        raiseMultiplier = 3.0
    elseif style == "conservative" then
        foldThreshold = 0.35
        raiseThreshold = 0.6
        bluffChance = 0.05
        raiseMultiplier = 2.0
    else -- balanced
        foldThreshold = 0.28
        raiseThreshold = 0.48
        bluffChance = 0.12
        raiseMultiplier = 2.5
    end

    -- Decision logic
    local isBluffing = math.random() < bluffChance

    if toCall == 0 then
        -- No bet to call: check or raise
        if perceivedStrength >= raiseThreshold or isBluffing then
            action = "raise"
            local raiseAmt = math.floor(gameState.bigBlind * raiseMultiplier * (1 + perceivedStrength))
            amount = math.min(chips, math.max(gameState.bigBlind, raiseAmt))
        else
            action = "check"
            amount = 0
        end
    else
        -- Must call or fold
        if perceivedStrength < foldThreshold and not isBluffing then
            -- Fold if call is expensive relative to stack
            if toCall > chips * 0.3 or perceivedStrength < foldThreshold * 0.6 then
                action = "fold"
                amount = 0
            else
                action = "call"
                amount = math.min(chips, toCall)
            end
        elseif perceivedStrength >= raiseThreshold or isBluffing then
            action = "raise"
            local raiseAmt = math.floor(toCall + gameState.bigBlind * raiseMultiplier * (1 + perceivedStrength))
            amount = math.min(chips, math.max(toCall + gameState.bigBlind, raiseAmt))
        else
            action = "call"
            amount = math.min(chips, toCall)
        end
    end

    -- All-in if raise/call exceeds chips
    if (action == "call" or action == "raise") and amount >= chips then
        amount = chips
        if action == "call" then
            action = "call"
        else
            action = "raise"
        end
    end

    return {action = action, amount = amount}
end

return AI
