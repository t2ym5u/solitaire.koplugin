-- ---------------------------------------------------------------------------
-- Card helpers shared by the FreeCell, Spider, Golf and Pyramid boards.
--
-- A card is { rank = 1..13, suit = "S"|"H"|"D"|"C", up = bool }, the same
-- shape the Klondike board (board.lua) uses, so every board_widget draws
-- them the same way. board.lua keeps its own private copies of these helpers:
-- it predates this file and is left untouched so Klondike saves and tests
-- stay exactly as they were.
-- ---------------------------------------------------------------------------

local Cards = {}

Cards.SUITS     = { "S", "H", "D", "C" }
Cards.RED_SUITS = { H = true, D = true }

function Cards.isRed(suit) return Cards.RED_SUITS[suit] == true end

-- One 52-card deck per entry of `suits` (default: one full deck). Spider's
-- one- and two-suit games pass the same suit several times.
function Cards.deck(suits)
    suits = suits or Cards.SUITS
    local deck = {}
    for _, suit in ipairs(suits) do
        for rank = 1, 13 do
            deck[#deck + 1] = { rank = rank, suit = suit, up = false }
        end
    end
    return deck
end

-- Fisher-Yates with math.random, like board.lua.
function Cards.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function Cards.copyCard(c)
    if not c then return false end
    return { rank = c.rank, suit = c.suit, up = c.up and true or false }
end

function Cards.copyList(list)
    local out = {}
    for i, c in ipairs(list or {}) do out[i] = Cards.copyCard(c) end
    return out
end

-- Copies an array of `n` card lists (tableau columns).
function Cards.copyPiles(piles, n)
    local out = {}
    for i = 1, n do out[i] = Cards.copyList(piles and piles[i]) end
    return out
end

function Cards.copyFoundations(f)
    f = f or {}
    return { S = f.S or 0, H = f.H or 0, D = f.D or 0, C = f.C or 0 }
end

-- A card read back from a save: a table with a known suit and a 1..13 rank.
function Cards.isValidCard(c)
    if type(c) ~= "table" then return false end
    local s = c.suit
    return s == "S" or s == "H" or s == "D" or s == "C"
end

-- Card census used by every load(): counts[suit .. rank] = copies seen.
-- add() returns false on a malformed card so a corrupted save is rejected.
function Cards.newCensus()
    local census = { counts = {}, total = 0 }
    function census:add(c)
        if not Cards.isValidCard(c) then return false end
        local r = c.rank
        if type(r) ~= "number" or r < 1 or r > 13 or r ~= math.floor(r) then return false end
        local key = c.suit .. r
        self.counts[key] = (self.counts[key] or 0) + 1
        self.total = self.total + 1
        return true
    end
    function census:addList(list)
        if type(list) ~= "table" then return false end
        for _, c in ipairs(list) do
            if not self:add(c) then return false end
        end
        return true
    end
    -- True when the census holds exactly `copies[suit]` of every rank of
    -- every suit (and nothing else).
    function census:matches(copies)
        local expected = 0
        for suit, n in pairs(copies) do
            for rank = 1, 13 do
                if (self.counts[suit .. rank] or 0) ~= n then return false end
            end
            expected = expected + 13 * n
        end
        return self.total == expected
    end
    return census
end

return Cards
