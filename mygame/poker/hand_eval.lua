-- hand_eval.lua - Hand evaluation module for Texas Hold'em

local HandEval = {}

-- Generate all C(n,5) combinations from an array
local function combinations5(arr)
    local result = {}
    local n = #arr
    for i = 1, n - 4 do
        for j = i + 1, n - 3 do
            for k = j + 1, n - 2 do
                for l = k + 1, n - 1 do
                    for m = l + 1, n do
                        result[#result + 1] = {arr[i], arr[j], arr[k], arr[l], arr[m]}
                    end
                end
            end
        end
    end
    return result
end

-- Evaluate a 5-card hand, returns {score, name, best5}
local function evaluate5(cards)
    -- Count ranks and suits
    local rankCount = {}
    local suitCount = {}
    local ranks = {}
    for i = 1, 13 do rankCount[i] = 0 end
    for i = 1, 4 do suitCount[i] = 0 end

    for _, c in ipairs(cards) do
        rankCount[c.rank] = rankCount[c.rank] + 1
        suitCount[c.suit] = suitCount[c.suit] + 1
        ranks[#ranks + 1] = c.rank
    end

    -- Sort ranks high to low (ace = 14 for sorting)
    local sortedRanks = {}
    for _, r in ipairs(ranks) do
        sortedRanks[#sortedRanks + 1] = (r == 1) and 14 or r
    end
    table.sort(sortedRanks, function(a, b) return a > b end)

    -- Check flush
    local isFlush = false
    for i = 1, 4 do
        if suitCount[i] == 5 then isFlush = true; break end
    end

    -- Check straight
    local isStraight = false
    local straightHigh = 0

    -- Check normal straight (using high-ace values)
    local uniqueSorted = {}
    local seen = {}
    for _, r in ipairs(sortedRanks) do
        if not seen[r] then
            seen[r] = true
            uniqueSorted[#uniqueSorted + 1] = r
        end
    end

    if #uniqueSorted == 5 then
        if uniqueSorted[1] - uniqueSorted[5] == 4 then
            isStraight = true
            straightHigh = uniqueSorted[1]
        end
        -- Check ace-low straight: A,2,3,4,5 (14,5,4,3,2)
        if uniqueSorted[1] == 14 and uniqueSorted[2] == 5 and uniqueSorted[3] == 4 and uniqueSorted[4] == 3 and uniqueSorted[5] == 2 then
            isStraight = true
            straightHigh = 5 -- 5-high straight
        end
    end

    -- Categorize by rank counts
    local quads, trips, pairs, singles = {}, {}, {}, {}
    for rank = 1, 13 do
        local r = (rank == 1) and 14 or rank
        if rankCount[rank] == 4 then quads[#quads + 1] = r
        elseif rankCount[rank] == 3 then trips[#trips + 1] = r
        elseif rankCount[rank] == 2 then pairs[#pairs + 1] = r
        elseif rankCount[rank] == 1 then singles[#singles + 1] = r
        end
    end
    table.sort(quads, function(a,b) return a > b end)
    table.sort(trips, function(a,b) return a > b end)
    table.sort(pairs, function(a,b) return a > b end)
    table.sort(singles, function(a,b) return a > b end)

    local handRank, kickers, name

    if isStraight and isFlush then
        if straightHigh == 14 then
            handRank = 10
            name = "Royal Flush"
            kickers = {14}
        else
            handRank = 9
            name = "Straight Flush"
            kickers = {straightHigh}
        end
    elseif #quads == 1 then
        handRank = 8
        name = "Four of a Kind"
        kickers = {quads[1]}
        -- add kicker
        for _, r in ipairs(sortedRanks) do
            if r ~= quads[1] then kickers[#kickers + 1] = r; break end
        end
    elseif #trips == 1 and #pairs == 1 then
        handRank = 7
        name = "Full House"
        kickers = {trips[1], pairs[1]}
    elseif isFlush then
        handRank = 6
        name = "Flush"
        kickers = {sortedRanks[1], sortedRanks[2], sortedRanks[3], sortedRanks[4], sortedRanks[5]}
    elseif isStraight then
        handRank = 5
        name = "Straight"
        kickers = {straightHigh}
    elseif #trips == 1 then
        handRank = 4
        name = "Three of a Kind"
        kickers = {trips[1]}
        local count = 0
        for _, r in ipairs(sortedRanks) do
            if r ~= trips[1] then
                kickers[#kickers + 1] = r
                count = count + 1
                if count == 2 then break end
            end
        end
    elseif #pairs == 2 then
        handRank = 3
        name = "Two Pair"
        kickers = {pairs[1], pairs[2]}
        for _, r in ipairs(sortedRanks) do
            if r ~= pairs[1] and r ~= pairs[2] then
                kickers[#kickers + 1] = r; break
            end
        end
    elseif #pairs == 1 then
        handRank = 2
        name = "One Pair"
        kickers = {pairs[1]}
        local count = 0
        for _, r in ipairs(sortedRanks) do
            if r ~= pairs[1] then
                kickers[#kickers + 1] = r
                count = count + 1
                if count == 3 then break end
            end
        end
    else
        handRank = 1
        name = "High Card"
        kickers = {sortedRanks[1], sortedRanks[2], sortedRanks[3], sortedRanks[4], sortedRanks[5]}
    end

    -- Compute numerical score for comparison
    local score = handRank * 10000000
    for i, k in ipairs(kickers) do
        score = score + k * (15 ^ (5 - i))
    end

    return {score = score, name = name, best5 = cards}
end

function HandEval.evaluate(cards7)
    if #cards7 < 5 then
        return {score = 0, name = "Incomplete", best5 = {}}
    end

    local combos
    if #cards7 == 5 then
        combos = {cards7}
    else
        combos = combinations5(cards7)
    end

    local bestEval = nil
    for _, combo in ipairs(combos) do
        local eval = evaluate5(combo)
        if bestEval == nil or eval.score > bestEval.score then
            bestEval = eval
        end
    end
    return bestEval
end

function HandEval.compare(eval1, eval2)
    if eval1.score > eval2.score then return 1
    elseif eval1.score < eval2.score then return -1
    else return 0 end
end

function HandEval.handName(score)
    local rank = math.floor(score / 10000000)
    local names = {
        "High Card", "One Pair", "Two Pair", "Three of a Kind",
        "Straight", "Flush", "Full House", "Four of a Kind",
        "Straight Flush", "Royal Flush"
    }
    return names[rank] or "Unknown"
end

-- Estimate hand strength from just 2 hole cards (0.0 to 1.0)
function HandEval.estimateHoleCards(card1, card2)
    local r1 = (card1.rank == 1) and 14 or card1.rank
    local r2 = (card2.rank == 1) and 14 or card2.rank
    if r1 < r2 then r1, r2 = r2, r1 end

    local score = 0
    local suited = (card1.suit == card2.suit)

    -- High card value
    score = score + (r1 - 2) / 12 * 0.3
    score = score + (r2 - 2) / 12 * 0.15

    -- Pair bonus
    if r1 == r2 then
        score = score + 0.3 + (r1 - 2) / 12 * 0.15
    end

    -- Suited bonus
    if suited then score = score + 0.06 end

    -- Connected bonus (straight potential)
    local gap = r1 - r2
    if gap == 1 then score = score + 0.04
    elseif gap == 2 then score = score + 0.02
    elseif gap == 0 then -- pair, already handled
    end

    return math.min(1.0, math.max(0.0, score))
end

return HandEval
