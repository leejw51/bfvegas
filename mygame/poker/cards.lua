-- cards.lua - Card and Deck module for Texas Hold'em

local Cards = {}

-- Suit constants: 1=clubs, 2=diamonds, 3=hearts, 4=spades
-- Rank constants: 1=ace, 2-10, 11=jack, 12=queen, 13=king

local suitSymbols = {"♣", "♦", "♥", "♠"}
local rankStrings = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K"}
local suitNames = {"c", "d", "h", "s"}
local suitColors = {
    {0.15, 0.15, 0.15},  -- clubs: dark
    {0.85, 0.1, 0.1},    -- diamonds: red
    {0.85, 0.1, 0.1},    -- hearts: red
    {0.15, 0.15, 0.15},  -- spades: dark
}

function Cards.newDeck()
    local deck = {}
    for suit = 1, 4 do
        for rank = 1, 13 do
            deck[#deck + 1] = {rank = rank, suit = suit}
        end
    end
    Cards.shuffle(deck)
    return deck
end

function Cards.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function Cards.deal(deck, n)
    local hand = {}
    for i = 1, n do
        if #deck == 0 then break end
        hand[#hand + 1] = table.remove(deck)
    end
    return hand
end

function Cards.rankString(rank)
    return rankStrings[rank] or "?"
end

function Cards.suitSymbol(suit)
    return suitSymbols[suit] or "?"
end

function Cards.suitColor(suit)
    return suitColors[suit] or {0, 0, 0}
end

function Cards.cardToString(card)
    return Cards.rankString(card.rank) .. Cards.suitSymbol(card.suit)
end

function Cards.cardFilename(card)
    local r = string.lower(Cards.rankString(card.rank))
    local s = suitNames[card.suit]
    return r .. s
end

function Cards.rankDisplayString(rank)
    if rank == 1 then return "A"
    elseif rank == 11 then return "J"
    elseif rank == 12 then return "Q"
    elseif rank == 13 then return "K"
    elseif rank == 10 then return "10"
    else return tostring(rank)
    end
end

return Cards
