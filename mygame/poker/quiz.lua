-- quiz.lua - Card Rank Learning Quiz mode
-- Shows random 5-card hands with 4 multiple-choice answers
-- Animated with easing effects

local Cards = require("cards")
local HandEval = require("hand_eval")
local Render = require("render")
local Easing = require("easing")

local Quiz = {}

-- Shared layout constants
local BTN_W = 400
local BTN_H = 60
local BTN_START_Y = 400
local BTN_SPACING = 72
local CARD_SCALE = 1.4  -- bigger cards for quiz

local HAND_NAMES = {
    "High Card", "One Pair", "Two Pair", "Three of a Kind",
    "Straight", "Flush", "Full House", "Four of a Kind",
    "Straight Flush", "Royal Flush",
}

local quiz = {}

-- Helper: random suit (1-4)
local function rSuit()
    return math.random(1, 4)
end

-- Helper: random suit different from given
local function rSuitNot(s)
    local r = math.random(1, 3)
    if r >= s then r = r + 1 end
    return r
end

-- Helper: pick n unique random ranks from 1-13
local function randomRanks(n, exclude)
    exclude = exclude or {}
    local excSet = {}
    for _, v in ipairs(exclude) do excSet[v] = true end
    local pool = {}
    for i = 1, 13 do
        if not excSet[i] then pool[#pool + 1] = i end
    end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local result = {}
    for i = 1, math.min(n, #pool) do
        result[i] = pool[i]
    end
    return result
end

-- Shuffle a table in place
local function shuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Build a specific hand type deterministically with random suits/ranks
local function buildHand(targetName)
    local hand = {}

    if targetName == "Royal Flush" then
        local s = rSuit()
        -- A K Q J 10 of same suit
        for _, r in ipairs({1, 13, 12, 11, 10}) do
            hand[#hand + 1] = {rank = r, suit = s}
        end

    elseif targetName == "Straight Flush" then
        local s = rSuit()
        -- Pick a starting rank 2-9 (so straight fits: start..start+4, avoiding royal)
        local start = math.random(2, 9)
        for i = 0, 4 do
            hand[#hand + 1] = {rank = start + i, suit = s}
        end

    elseif targetName == "Four of a Kind" then
        local r = math.random(1, 13)
        for s = 1, 4 do
            hand[#hand + 1] = {rank = r, suit = s}
        end
        -- One kicker with different rank
        local kr = randomRanks(1, {r})[1]
        hand[#hand + 1] = {rank = kr, suit = rSuit()}

    elseif targetName == "Full House" then
        local r3 = math.random(1, 13)
        local r2 = randomRanks(1, {r3})[1]
        -- Three of a kind
        local suits3 = {1, 2, 3, 4}
        shuffleTable(suits3)
        for i = 1, 3 do
            hand[#hand + 1] = {rank = r3, suit = suits3[i]}
        end
        -- Pair
        local suits2 = {1, 2, 3, 4}
        shuffleTable(suits2)
        for i = 1, 2 do
            hand[#hand + 1] = {rank = r2, suit = suits2[i]}
        end

    elseif targetName == "Flush" then
        local s = rSuit()
        -- 5 cards same suit, but NOT a straight
        local ranks
        for _ = 1, 100 do
            ranks = randomRanks(5, {})
            table.sort(ranks)
            -- Check it's not a straight
            local isStr = true
            for i = 2, 5 do
                if ranks[i] ~= ranks[i-1] + 1 then isStr = false; break end
            end
            -- Also check ace-high straight: 1,10,11,12,13
            local aceHigh = (ranks[1] == 1 and ranks[2] == 10 and ranks[3] == 11 and ranks[4] == 12 and ranks[5] == 13)
            if not isStr and not aceHigh then break end
        end
        for _, r in ipairs(ranks) do
            hand[#hand + 1] = {rank = r, suit = s}
        end

    elseif targetName == "Straight" then
        -- Pick start rank, NOT all same suit
        local start
        local useAceLow = (math.random(5) == 1)
        if useAceLow then
            -- A 2 3 4 5
            local ranks = {1, 2, 3, 4, 5}
            local suits = {}
            for i = 1, 5 do suits[i] = rSuit() end
            -- Ensure not all same suit
            if suits[1] == suits[2] and suits[2] == suits[3] and suits[3] == suits[4] and suits[4] == suits[5] then
                suits[5] = rSuitNot(suits[1])
            end
            for i = 1, 5 do
                hand[#hand + 1] = {rank = ranks[i], suit = suits[i]}
            end
        else
            start = math.random(2, 9)
            local suits = {}
            for i = 1, 5 do suits[i] = rSuit() end
            if suits[1] == suits[2] and suits[2] == suits[3] and suits[3] == suits[4] and suits[4] == suits[5] then
                suits[math.random(5)] = rSuitNot(suits[1])
            end
            for i = 0, 4 do
                hand[#hand + 1] = {rank = start + i, suit = suits[i + 1]}
            end
        end

    elseif targetName == "Three of a Kind" then
        local r3 = math.random(1, 13)
        local suits3 = {1, 2, 3, 4}
        shuffleTable(suits3)
        for i = 1, 3 do
            hand[#hand + 1] = {rank = r3, suit = suits3[i]}
        end
        -- 2 kickers, all different ranks (not pairing each other)
        local kickers = randomRanks(2, {r3})
        for _, kr in ipairs(kickers) do
            hand[#hand + 1] = {rank = kr, suit = rSuit()}
        end

    elseif targetName == "Two Pair" then
        local ranks2 = randomRanks(2, {})
        local r1, r2 = ranks2[1], ranks2[2]
        local suits1 = {1, 2, 3, 4}; shuffleTable(suits1)
        local suits2 = {1, 2, 3, 4}; shuffleTable(suits2)
        hand[#hand + 1] = {rank = r1, suit = suits1[1]}
        hand[#hand + 1] = {rank = r1, suit = suits1[2]}
        hand[#hand + 1] = {rank = r2, suit = suits2[1]}
        hand[#hand + 1] = {rank = r2, suit = suits2[2]}
        -- Kicker
        local kr = randomRanks(1, {r1, r2})[1]
        hand[#hand + 1] = {rank = kr, suit = rSuit()}

    elseif targetName == "One Pair" then
        local rp = math.random(1, 13)
        local suitsP = {1, 2, 3, 4}; shuffleTable(suitsP)
        hand[#hand + 1] = {rank = rp, suit = suitsP[1]}
        hand[#hand + 1] = {rank = rp, suit = suitsP[2]}
        -- 3 kickers, all unique, not forming flush or straight
        local kickers = randomRanks(3, {rp})
        for _, kr in ipairs(kickers) do
            hand[#hand + 1] = {rank = kr, suit = rSuit()}
        end

    else -- "High Card"
        -- 5 unique ranks, not all same suit, not a straight
        local ranks
        for _ = 1, 100 do
            ranks = randomRanks(5, {})
            table.sort(ranks)
            local isStr = true
            for i = 2, 5 do
                if ranks[i] ~= ranks[i-1] + 1 then isStr = false; break end
            end
            local aceHigh = (ranks[1] == 1 and ranks[2] == 10 and ranks[3] == 11 and ranks[4] == 12 and ranks[5] == 13)
            if not isStr and not aceHigh then break end
        end
        local suits = {}
        for i = 1, 5 do suits[i] = rSuit() end
        -- Ensure not all same suit (would be flush)
        if suits[1] == suits[2] and suits[2] == suits[3] and suits[3] == suits[4] and suits[4] == suits[5] then
            suits[math.random(5)] = rSuitNot(suits[1])
        end
        for i = 1, 5 do
            hand[#hand + 1] = {rank = ranks[i], suit = suits[i]}
        end
    end

    shuffleTable(hand)
    local eval = HandEval.evaluate(hand)
    return hand, eval
end

-- Pick 3 wrong answers that are different from the correct one
local function pickWrongAnswers(correctName)
    local wrong = {}
    local pool = {}
    for _, name in ipairs(HAND_NAMES) do
        if name ~= correctName then
            pool[#pool + 1] = name
        end
    end
    -- Shuffle pool
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    for i = 1, 3 do
        wrong[i] = pool[i]
    end
    return wrong
end

local function newQuestion()
    -- 1. Pick a random hand rank with weighted distribution
    local weightedHands = {
        {"Royal Flush",       3},
        {"Straight Flush",    5},
        {"Four of a Kind",    8},
        {"Full House",       12},
        {"Flush",            12},
        {"Straight",         12},
        {"Three of a Kind",  12},
        {"Two Pair",         15},
        {"One Pair",         15},
        {"High Card",         6},
    }
    local totalWeight = 0
    for _, entry in ipairs(weightedHands) do
        totalWeight = totalWeight + entry[2]
    end
    local roll = math.random(totalWeight)
    local target = "One Pair"
    local cumulative = 0
    for _, entry in ipairs(weightedHands) do
        cumulative = cumulative + entry[2]
        if roll <= cumulative then
            target = entry[1]
            break
        end
    end

    -- 2. Build the hand deterministically with random suits/ranks
    local hand, eval = buildHand(target)

    local correctName = eval.name
    local wrongAnswers = pickWrongAnswers(correctName)

    -- Build 4 choices, shuffle
    local choices = {
        {text = correctName, correct = true},
        {text = wrongAnswers[1], correct = false},
        {text = wrongAnswers[2], correct = false},
        {text = wrongAnswers[3], correct = false},
    }
    -- Shuffle choices
    for i = #choices, 2, -1 do
        local j = math.random(1, i)
        choices[i], choices[j] = choices[j], choices[i]
    end

    quiz.hand = hand
    quiz.eval = eval
    quiz.choices = choices
    quiz.answered = false
    quiz.selectedIdx = nil
    quiz.correctIdx = nil
    quiz.showResult = false
    quiz.resultTimer = 0
    quiz.questionNum = quiz.questionNum + 1
    quiz.wrongChoices = {}
    quiz.attempts = 0
    quiz.hintLevel = 0
    quiz.sortMode = 0

    -- Find correct index
    for i, c in ipairs(choices) do
        if c.correct then quiz.correctIdx = i end
    end

    -- Animations
    -- Cards deal in one by one
    for i = 1, 5 do
        Easing.tween("quiz_card_" .. i, 0.3 + i * 0.08, Easing.easeOutBack)
    end
    -- Choices slide in from right with stagger
    for i = 1, 4 do
        Easing.tween("quiz_choice_" .. i, 0.4 + i * 0.1, Easing.easeOutCubic)
    end
    -- Question pop
    Easing.tween("quiz_question", 0.5, Easing.easeOutElastic)
end

function Quiz.init()
    quiz = {
        hand = {},
        eval = nil,
        choices = {},
        answered = false,      -- true only when correct
        selectedIdx = nil,
        correctIdx = nil,
        showResult = false,    -- true when correct, auto-advance
        resultTimer = 0,
        score = 0,
        total = 0,
        streak = 0,
        bestStreak = 0,
        questionNum = 0,
        choiceHover = 0,
        wrongChoices = {},     -- track which choices were tried wrong
        attempts = 0,          -- attempts on current question
        hintLevel = 0,         -- 0=none, 1=eliminate one, 2=eliminate two, 3=show answer
        sortMode = 0,          -- 0=unsorted, 1=by rank, 2=by suit
        sortHover = false,
    }
    Easing.clearParticles()
    newQuestion()
end

function Quiz.update(dt)
    Easing.update(dt)
    Easing.updateParticles(dt)
    Easing.updateShake(dt)

    -- Only auto-advance on correct answer
    if quiz.showResult then
        quiz.resultTimer = quiz.resultTimer + dt
        if quiz.resultTimer >= 2.0 then
            quiz.showResult = false
            newQuestion()
        end
    end
end

local function sortHandByRank(hand)
    table.sort(hand, function(a, b)
        if a.rank == b.rank then return a.suit < b.suit end
        return a.rank < b.rank
    end)
end

local function sortHandBySuit(hand)
    table.sort(hand, function(a, b)
        if a.suit == b.suit then return a.rank < b.rank end
        return a.suit < b.suit
    end)
end

local function cycleSortMode()
    quiz.sortMode = (quiz.sortMode % 2) + 1
    if quiz.sortMode == 1 then
        sortHandByRank(quiz.hand)
    else
        sortHandBySuit(quiz.hand)
    end
    -- Re-animate cards
    for i = 1, 5 do
        Easing.tween("quiz_card_" .. i, 0.25 + i * 0.05, Easing.easeOutBack)
    end
end

function Quiz.keypressed(key)
    if key == "escape" then
        return "menu"
    end
    if key == "s" then
        cycleSortMode()
        return
    end
    if not quiz.answered then
        if key == "1" then Quiz.selectAnswer(1)
        elseif key == "2" then Quiz.selectAnswer(2)
        elseif key == "3" then Quiz.selectAnswer(3)
        elseif key == "4" then Quiz.selectAnswer(4)
        end
    elseif quiz.showResult and quiz.resultTimer >= 0.5 then
        -- Skip wait on correct
        quiz.showResult = false
        newQuestion()
    end
end

function Quiz.selectAnswer(idx)
    if quiz.answered or idx < 1 or idx > 4 then return end
    -- Don't allow re-clicking an already eliminated wrong answer
    if quiz.wrongChoices[idx] then return end

    local isCorrect = quiz.choices[idx].correct
    quiz.attempts = quiz.attempts + 1

    if isCorrect then
        -- Correct!
        quiz.answered = true
        quiz.selectedIdx = idx
        quiz.showResult = true
        quiz.resultTimer = 0
        quiz.total = quiz.total + 1
        -- Only count score if first attempt
        if quiz.attempts == 1 then
            quiz.score = quiz.score + 1
            quiz.streak = quiz.streak + 1
            if quiz.streak > quiz.bestStreak then
                quiz.bestStreak = quiz.streak
            end
        else
            quiz.streak = 0
        end
        -- Celebration
        Easing.tween("quiz_correct", 0.6, Easing.easeOutElastic)
        local particleCount = quiz.attempts == 1 and 30 or 15
        Easing.spawnParticles(640, 220, particleCount, {color = {0.2, 1, 0.3}, speed = 180, life = 1.5, size = 6})
        if quiz.attempts == 1 then
            Easing.spawnParticles(640, 220, 20, {color = {1, 0.85, 0.2}, speed = 120, life = 1.2, size = 5})
        end
    else
        -- Wrong! Mark this choice, give hint, stay on same question
        quiz.wrongChoices[idx] = true
        quiz.selectedIdx = idx
        quiz.hintLevel = quiz.hintLevel + 1
        quiz.streak = 0

        -- Shake + red flash
        Easing.startShake(5, 0.3)
        Easing.tween("quiz_wrong", 0.4, Easing.easeOutExpo)
        -- Bounce the wrong button
        Easing.tween("quiz_wrong_btn_" .. idx, 0.5, Easing.easeOutElastic)
        -- Pulse the correct answer hint after 2nd wrong
        if quiz.hintLevel >= 2 then
            Easing.tween("quiz_hint_glow", 0.8, Easing.easeOutCubic)
        end
    end
end

function Quiz.mousepressed(mx, my, button)
    if button ~= 1 then return end

    -- Back button
    local backW, backH = 160, 38
    local backX, backY = 20, 720 - 50
    if mx >= backX and mx <= backX + backW and my >= backY and my <= backY + backH then
        quiz.goBack = true
        return
    end

    -- Sort button
    local sortW, sortH = 120, 38
    local sortX, sortY = 1280 - sortW - 20, 720 - 50
    if mx >= sortX and mx <= sortX + sortW and my >= sortY and my <= sortY + sortH then
        cycleSortMode()
        return
    end

    if quiz.answered then
        if quiz.showResult and quiz.resultTimer >= 0.5 then
            quiz.showResult = false
            newQuestion()
        end
        return
    end

    -- Check choice buttons
    for i = 1, 4 do
        if not quiz.wrongChoices[i] then
            local bx = 640 - BTN_W / 2
            local by = BTN_START_Y + (i - 1) * BTN_SPACING
            if mx >= bx and mx <= bx + BTN_W and my >= by and my <= by + BTN_H then
                Quiz.selectAnswer(i)
                return
            end
        end
    end
end

function Quiz.mousemoved(mx, my)
    quiz.choiceHover = 0
    quiz.backHover = false
    quiz.sortHover = false

    -- Sort button hover
    local sortW, sortH = 120, 38
    local sortX, sortY = 1280 - sortW - 20, 720 - 50
    if mx >= sortX and mx <= sortX + sortW and my >= sortY and my <= sortY + sortH then
        quiz.sortHover = true
        return
    end

    -- Back button hover
    local backW, backH = 160, 38
    local backX, backY = 20, 720 - 50
    if mx >= backX and mx <= backX + backW and my >= backY and my <= backY + backH then
        quiz.backHover = true
        return
    end

    if quiz.answered then return end

    for i = 1, 4 do
        if not quiz.wrongChoices[i] then
            local bx = 640 - BTN_W / 2
            local by = BTN_START_Y + (i - 1) * BTN_SPACING
            if mx >= bx and mx <= bx + BTN_W and my >= by and my <= by + BTN_H then
                quiz.choiceHover = i
                return
            end
        end
    end
end

function Quiz.draw()
    local W, H = 1280, 720
    local time = love.timer.getTime()

    -- Apply shake
    local sx, sy = Easing.getShakeOffset()
    love.graphics.push()
    love.graphics.translate(sx, sy)

    -- Background
    Render.drawTable()

    -- Title bar
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, W, 50)
    love.graphics.setFont(Render.getFont("medium"))
    love.graphics.setColor(0.85, 0.65, 0.13)
    love.graphics.print("  Hand Rank Quiz", 10, 12)

    -- Score display
    love.graphics.setFont(Render.getFont("normal"))
    love.graphics.setColor(1, 1, 1)
    local scoreText = string.format("Score: %d/%d", quiz.score, quiz.total)
    love.graphics.printf(scoreText, W - 300, 14, 280, "right")

    -- Streak
    if quiz.streak > 0 then
        local streakPulse = 0.8 + 0.2 * math.sin(time * 4)
        love.graphics.setColor(1, 0.85, 0.2, streakPulse)
        love.graphics.printf("Streak: " .. quiz.streak, W - 500, 14, 180, "right")
    end

    -- Question text with pop animation
    local qScale = Easing.getValue("quiz_question")
    love.graphics.push()
    love.graphics.translate(W/2, 75)
    love.graphics.scale(qScale, qScale)
    love.graphics.translate(-W/2, -75)
    love.graphics.setFont(Render.getFont("xlarge"))
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.printf("What is this hand?", 2, 62, W, "center")
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("What is this hand?", 0, 60, W, "center")
    love.graphics.pop()

    -- Draw the 5 cards BIGGER with staggered deal animation
    local cardW = 80 * CARD_SCALE
    local cardH = 112 * CARD_SCALE
    local cardSpacing = 20
    local totalCardsW = 5 * cardW + 4 * cardSpacing
    local cardsStartX = W/2 - totalCardsW / 2
    local cardsY = 110

    for i = 1, 5 do
        local animVal = Easing.getValue("quiz_card_" .. i)
        local cx = cardsStartX + (i - 1) * (cardW + cardSpacing)
        local cy = cardsY

        -- Animate: slide up + scale from small
        love.graphics.push()
        local centerX = cx + cardW/2
        local centerY = cy + cardH/2
        love.graphics.translate(centerX, centerY)
        love.graphics.scale(animVal, animVal)
        love.graphics.translate(-centerX, -centerY)

        -- Slight float
        local floatY = math.sin(time * 1.5 + i * 0.5) * 3
        love.graphics.translate(0, -((1 - animVal) * 80) + floatY)

        if quiz.hand[i] then
            Render.drawCard(quiz.hand[i], cx, cy, true, CARD_SCALE)
        end
        love.graphics.pop()
    end

    -- Card label below cards
    love.graphics.setFont(Render.getFont("normal"))
    love.graphics.setColor(0.8, 0.8, 0.8, 0.7)
    local cardStrings = {}
    for _, c in ipairs(quiz.hand) do
        cardStrings[#cardStrings + 1] = Cards.cardToString(c)
    end
    love.graphics.printf(table.concat(cardStrings, "   "), 0, cardsY + cardH + 8, W, "center")

    -- Question number
    love.graphics.setFont(Render.getFont("small"))
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("Question #" .. quiz.questionNum, 0, cardsY + cardH + 30, W, "center")

    -- Draw 4 choice buttons (use shared constants)
    local btnW, btnH = BTN_W, BTN_H
    local startY = BTN_START_Y
    local spacing = BTN_SPACING

    -- Wrong flash overlay
    local wrongFlash = 1.0 - Easing.getValue("quiz_wrong")

    for i = 1, 4 do
        local choiceAnim = Easing.getValue("quiz_choice_" .. i)
        local bx = W/2 - btnW / 2
        local by = startY + (i - 1) * spacing

        -- Slide in from right
        local slideOffset = (1.0 - choiceAnim) * 400
        bx = bx + slideOffset

        local isEliminated = quiz.wrongChoices[i]       -- previously guessed wrong
        local isHovered = (quiz.choiceHover == i and not quiz.answered and not isEliminated)
        local isCorrect = quiz.choices[i] and quiz.choices[i].correct
        local isGotCorrect = (quiz.answered and isCorrect)

        -- Wrong button shake animation
        local wrongBtnShake = 1.0 - Easing.getValue("quiz_wrong_btn_" .. i)
        if isEliminated and wrongBtnShake > 0.01 then
            bx = bx + math.sin(wrongBtnShake * 30) * wrongBtnShake * 10
        end

        -- Hover scale
        local btnScale = 1.0
        if isHovered then btnScale = 1.04 end
        if isGotCorrect then
            local correctBounce = Easing.getValue("quiz_correct")
            btnScale = 1.0 + (1.0 - correctBounce) * 0.1
        end

        -- Hint glow: after 2 wrong, pulse the correct answer
        local hintGlow = 0
        if not quiz.answered and quiz.hintLevel >= 2 and isCorrect then
            hintGlow = 0.3 + 0.2 * math.sin(time * 5)
        end

        love.graphics.push()
        local btnCX = bx + btnW/2
        local btnCY = by + btnH/2
        love.graphics.translate(btnCX, btnCY)
        love.graphics.scale(btnScale, btnScale)
        love.graphics.translate(-btnCX, -btnCY)

        -- Button background
        if isGotCorrect then
            -- Correct answer - green glow
            local glow = 0.6 + 0.4 * math.sin(time * 6)
            love.graphics.setColor(0.1, 0.5, 0.15, 0.9)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, 10, 10)
            love.graphics.setColor(0.2, 1, 0.3, glow * 0.3)
            love.graphics.rectangle("fill", bx - 3, by - 3, btnW + 6, btnH + 6, 12, 12)
        elseif isEliminated then
            -- Eliminated wrong answer - dim red, crossed out
            love.graphics.setColor(0.25, 0.08, 0.08, 0.6)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, 10, 10)
            -- Strikethrough line
            love.graphics.setColor(0.6, 0.2, 0.2, 0.5)
            love.graphics.setLineWidth(2)
            love.graphics.line(bx + 50, by + btnH/2, bx + btnW - 20, by + btnH/2)
        elseif hintGlow > 0 then
            -- Hint: glow the correct answer
            love.graphics.setColor(0.18, 0.18, 0.22, 0.85)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, 10, 10)
            love.graphics.setColor(0.2, 0.9, 0.3, hintGlow)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", bx, by, btnW, btnH, 10, 10)
        elseif isHovered then
            love.graphics.setColor(0.3, 0.3, 0.35, 0.9)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, 10, 10)
            love.graphics.setColor(0.85, 0.65, 0.13, 0.6)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", bx, by, btnW, btnH, 10, 10)
        else
            love.graphics.setColor(0.18, 0.18, 0.22, 0.85)
            love.graphics.rectangle("fill", bx, by, btnW, btnH, 10, 10)
            love.graphics.setColor(0.4, 0.4, 0.4, 0.4)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", bx, by, btnW, btnH, 10, 10)
        end

        -- Number badge
        local badgeAlpha = isEliminated and 0.3 or 0.9
        love.graphics.setColor(0.85, 0.65, 0.13, badgeAlpha)
        love.graphics.circle("fill", bx + 30, by + btnH/2, 18)
        love.graphics.setFont(Render.getFont("medium"))
        love.graphics.setColor(0, 0, 0, badgeAlpha)
        local numW = Render.getFont("medium"):getWidth(tostring(i))
        love.graphics.print(tostring(i), bx + 30 - numW/2, by + btnH/2 - 10)

        -- Choice text
        love.graphics.setFont(Render.getFont("large"))
        if isGotCorrect then
            love.graphics.setColor(0.2, 1, 0.3)
        elseif isEliminated then
            love.graphics.setColor(0.5, 0.3, 0.3, 0.4)
        elseif isHovered then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.85, 0.85, 0.85)
        end
        if quiz.choices[i] then
            love.graphics.printf(quiz.choices[i].text, bx + 55, by + btnH/2 - 14, btnW - 100, "left")
        end

        -- Checkmark or X
        love.graphics.setFont(Render.getFont("xlarge"))
        if isGotCorrect then
            love.graphics.setColor(0.2, 1, 0.3)
            love.graphics.print("✓", bx + btnW - 45, by + btnH/2 - 20)
        elseif isEliminated then
            love.graphics.setColor(0.7, 0.2, 0.2, 0.6)
            love.graphics.print("✗", bx + btnW - 45, by + btnH/2 - 20)
        end

        love.graphics.pop()
    end

    -- Result overlay
    if quiz.answered and quiz.showResult then
        -- Correct! Show celebration overlay
        local resultY = 300
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", W/2 - 300, resultY - 20, 600, 80, 15, 15)

        local correctScale = Easing.getValue("quiz_correct")
        love.graphics.push()
        love.graphics.translate(W/2, resultY + 20)
        love.graphics.scale(correctScale, correctScale)
        love.graphics.translate(-W/2, -(resultY + 20))

        love.graphics.setFont(Render.getFont("title"))
        love.graphics.setColor(0, 0, 0, 0.5)
        local msg = quiz.attempts == 1 and "Correct!" or "Got it!"
        love.graphics.printf(msg, 3, resultY + 3, W, "center")
        local glow = 0.8 + 0.2 * math.sin(time * 6)
        love.graphics.setColor(0.2, 1, 0.3, glow)
        love.graphics.printf(msg, 0, resultY, W, "center")
        love.graphics.pop()
    end

    -- Wrong hint text (shown when not yet correct and has wrong attempts)
    if not quiz.answered and quiz.hintLevel > 0 then
        local hintY = 375
        love.graphics.setFont(Render.getFont("medium"))
        if quiz.hintLevel == 1 then
            love.graphics.setColor(1, 0.5, 0.3, 0.9)
            love.graphics.printf("Not quite! Try again.", 0, hintY, W, "center")
        elseif quiz.hintLevel >= 2 then
            love.graphics.setColor(1, 0.6, 0.2, 0.9)
            love.graphics.printf("Look for the glowing answer!", 0, hintY, W, "center")
        end
    end

    -- Wrong answer red flash
    if wrongFlash > 0.01 then
        love.graphics.setColor(0.8, 0, 0, wrongFlash * 0.2)
        love.graphics.rectangle("fill", 0, 0, W, H)
    end

    -- Particles
    Easing.drawParticles()

    -- "Back to Main" button
    local backW, backH = 160, 38
    local backX, backY = 20, H - 50
    local backHovered = (quiz.backHover == true)
    local backScale = backHovered and 1.05 or 1.0
    love.graphics.push()
    love.graphics.translate(backX + backW/2, backY + backH/2)
    love.graphics.scale(backScale, backScale)
    love.graphics.translate(-(backX + backW/2), -(backY + backH/2))
    if backHovered then
        love.graphics.setColor(0.85, 0.65, 0.13, 0.2)
        love.graphics.rectangle("fill", backX - 2, backY - 2, backW + 4, backH + 4, 8, 8)
    end
    love.graphics.setColor(0.15, 0.15, 0.18, 0.85)
    love.graphics.rectangle("fill", backX, backY, backW, backH, 8, 8)
    love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", backX, backY, backW, backH, 8, 8)
    love.graphics.setFont(Render.getFont("normal"))
    love.graphics.setColor(backHovered and 1 or 0.7, backHovered and 1 or 0.7, backHovered and 1 or 0.7)
    love.graphics.printf("← Main Menu", backX, backY + backH/2 - 8, backW, "center")
    love.graphics.pop()

    -- Sort button (bottom-right)
    local sortW, sortH = 120, 38
    local sortX, sortY = W - sortW - 20, H - 50
    local sortHovered = (quiz.sortHover == true)
    local sortScale = sortHovered and 1.05 or 1.0
    love.graphics.push()
    love.graphics.translate(sortX + sortW/2, sortY + sortH/2)
    love.graphics.scale(sortScale, sortScale)
    love.graphics.translate(-(sortX + sortW/2), -(sortY + sortH/2))
    if sortHovered then
        love.graphics.setColor(0.85, 0.65, 0.13, 0.2)
        love.graphics.rectangle("fill", sortX - 2, sortY - 2, sortW + 4, sortH + 4, 8, 8)
    end
    love.graphics.setColor(0.15, 0.15, 0.18, 0.85)
    love.graphics.rectangle("fill", sortX, sortY, sortW, sortH, 8, 8)
    love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", sortX, sortY, sortW, sortH, 8, 8)
    love.graphics.setFont(Render.getFont("normal"))
    local sortLabel
    if quiz.sortMode == 1 then
        sortLabel = "Sort: Rank"
    elseif quiz.sortMode == 2 then
        sortLabel = "Sort: Suit"
    else
        sortLabel = "Sort (S)"
    end
    love.graphics.setColor(sortHovered and 1 or 0.7, sortHovered and 1 or 0.7, sortHovered and 1 or 0.7)
    love.graphics.printf(sortLabel, sortX, sortY + sortH/2 - 8, sortW, "center")
    love.graphics.pop()

    -- Best streak
    if quiz.bestStreak > 0 then
        love.graphics.setFont(Render.getFont("small"))
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf("Best streak: " .. quiz.bestStreak, W - 200, H - 25, 190, "right")
    end

    love.graphics.pop()
end

-- Public: build a random 5-card example of a named hand type.
-- Accepts any HAND_NAMES string (e.g. "Royal Flush", "Two Pair").
function Quiz.buildHand(name)
    return buildHand(name)
end

function Quiz.shouldGoBack()
    if quiz.goBack then
        quiz.goBack = false
        return true
    end
    return false
end

return Quiz
