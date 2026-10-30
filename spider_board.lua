local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local UndoStack = require("undo_stack")
local Cards     = lrequire("solitaire_cards")

local NUM_COLS   = 10
local NUM_RUNS   = 8   -- 104 cards = 8 King-to-Ace runs
local SUIT_SETS  = {
    [1] = { "S", "S", "S", "S", "S", "S", "S", "S" },
    [2] = { "S", "H", "S", "H", "S", "H", "S", "H" },
    [4] = { "S", "H", "D", "C", "S", "H", "D", "C" },
}

-- ---------------------------------------------------------------------------
-- SpiderBoard
--
-- Two decks (104 cards) in 1, 2 or 4 suits. 54 cards are dealt to 10
-- columns (6 to the first four, 5 to the rest, top card face up); the other
-- 50 stay in the stock and are dealt 10 at a time, one face-up card per
-- column, which is only allowed while no column is empty.
--
-- Any card may go on a card one rank higher, whatever its suit, but only a
-- same-suit descending run moves as a unit. A complete King-to-Ace run of
-- one suit leaves the tableau for the foundation by itself.
-- ---------------------------------------------------------------------------

local SpiderBoard = {}
SpiderBoard.__index = SpiderBoard

SpiderBoard.NUM_COLS = NUM_COLS
SpiderBoard.NUM_RUNS = NUM_RUNS

local function validSuits(n)
    n = tonumber(n)
    if SUIT_SETS[n] then return n end
    return 1
end

function SpiderBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({}, self)
    obj:reset(opts.suits)
    return obj
end

function SpiderBoard:reset(suits)
    self.suits = validSuits(suits or self.suits)
    local deck = Cards.deck(SUIT_SETS[self.suits])
    Cards.shuffle(deck)

    self.tableau = {}
    for p = 1, NUM_COLS do
        local col = {}
        local n = p <= 4 and 6 or 5
        for i = 1, n do
            local card = table.remove(deck)
            card.up = (i == n)
            col[i] = card
        end
        self.tableau[p] = col
    end
    self.stock     = deck
    self.completed = {}
    self.selected  = nil
    self.status    = "playing"
    self.moves     = 0
    self._undo     = UndoStack:new{ max_size = 200 }
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

function SpiderBoard:_snapshot()
    local completed = {}
    for i, s in ipairs(self.completed) do completed[i] = s end
    return {
        tableau   = Cards.copyPiles(self.tableau, NUM_COLS),
        stock     = Cards.copyList(self.stock),
        completed = completed,
        moves     = self.moves,
    }
end

function SpiderBoard:_apply(snap)
    self.tableau = Cards.copyPiles(snap.tableau, NUM_COLS)
    self.stock = Cards.copyList(snap.stock)
    self.completed = {}
    for i, s in ipairs(snap.completed or {}) do self.completed[i] = s end
    self.moves = snap.moves or 0
end

function SpiderBoard:undo()
    local snap = self._undo:pop()
    if not snap then return false end
    self:_apply(snap)
    self.selected = nil
    self.status = "playing"
    return true
end

function SpiderBoard:canUndo()
    return self._undo:canUndo()
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- True when col[idx..#col] is face up, one suit, descending by one.
function SpiderBoard:isRun(pile, idx)
    local col = self.tableau[pile]
    if not col or not col[idx] or not col[idx].up then return false end
    for i = idx, #col - 1 do
        local a, b = col[i], col[i + 1]
        if not b.up or a.suit ~= b.suit or a.rank ~= b.rank + 1 then return false end
    end
    return true
end

-- Index of the deepest card heading the movable run at the top of the pile.
function SpiderBoard:runBase(pile)
    local col = self.tableau[pile]
    local idx = #col
    while idx > 1 do
        local a, b = col[idx - 1], col[idx]
        if not a.up or a.suit ~= b.suit or a.rank ~= b.rank + 1 then break end
        idx = idx - 1
    end
    return idx
end

function SpiderBoard:fitsOn(card, pile)
    local col = self.tableau[pile]
    if #col == 0 then return true end
    local top = col[#col]
    return top.up and top.rank == card.rank + 1
end

function SpiderBoard:hasEmptyColumn()
    for p = 1, NUM_COLS do
        if #self.tableau[p] == 0 then return true end
    end
    return false
end

function SpiderBoard:dealsLeft()
    return math.floor(#self.stock / NUM_COLS)
end

function SpiderBoard:isWon()
    return #self.completed >= NUM_RUNS
end

-- Moves every finished K..A run off the tableau. Returns how many.
function SpiderBoard:_collectRuns()
    local n = 0
    for p = 1, NUM_COLS do
        local col = self.tableau[p]
        if #col >= 13 and col[#col].rank == 1 then
            local base = #col - 12
            if col[base].rank == 13 and self:isRun(p, base) then
                self.completed[#self.completed + 1] = col[base].suit
                for _ = 1, 13 do table.remove(col) end
                n = n + 1
            end
        end
        local top = col[#col]
        if top and not top.up then top.up = true end
    end
    return n
end

function SpiderBoard:_afterMove()
    self.moves = self.moves + 1
    self:_collectRuns()
    if self:isWon() then
        self.status = "won"
        return "won"
    end
    return "moved"
end

-- Deals one face-up card onto every column.
-- Returns "drew" | "won" | "empty" (no stock left) | "blocked" (a column is
-- empty) | "not_playing".
function SpiderBoard:dealRow()
    if self.status ~= "playing" then return "not_playing" end
    self.selected = nil
    if #self.stock < NUM_COLS then return "empty" end
    if self:hasEmptyColumn() then return "blocked" end
    self._undo:push(self:_snapshot())
    for p = 1, NUM_COLS do
        local card = table.remove(self.stock)
        card.up = true
        local col = self.tableau[p]
        col[#col + 1] = card
    end
    if self:_afterMove() == "won" then return "won" end
    return "drew"
end

-- Moves the selected run onto column `dest`. If the run picked does not
-- fit, the one card of it that does (rank one below the destination top)
-- and everything above it moves instead.
function SpiderBoard:_moveToTableau(sel, dest)
    if sel.pile == dest then return false end
    local col = self.tableau[sel.pile]
    local dest_col = self.tableau[dest]
    local start = sel.idx
    if not self:fitsOn(col[start], dest) then
        start = nil
        if #dest_col > 0 then
            for i = sel.idx + 1, #col do
                if self:fitsOn(col[i], dest) then start = i break end
            end
        end
        if not start then return false end
    end
    self._undo:push(self:_snapshot())
    local count = #col - start + 1
    for i = start, #col do dest_col[#dest_col + 1] = col[i] end
    for _ = 1, count do table.remove(col) end
    return true
end

-- zone: "stock" | "tableau" (pile 1-10, idx card) | "foundation".
-- Returns "drew" | "empty" | "blocked" | "selected" | "deselected" |
-- "invalid" | "moved" | "won" | "not_playing".
function SpiderBoard:tap(zone, pile, idx)
    if self.status ~= "playing" then return "not_playing" end
    if zone == "stock" then
        return self:dealRow()
    end

    local sel = self.selected
    if sel then
        self.selected = nil
        if zone ~= "tableau" then return "invalid" end
        if pile == sel.pile then return "deselected" end
        if self:_moveToTableau(sel, pile) then return self:_afterMove() end
        return "invalid"
    end

    if zone ~= "tableau" then return "invalid" end
    local col = self.tableau[pile]
    if not col or #col == 0 then return "invalid" end
    local base = self:runBase(pile)
    idx = math.max(base, math.min(idx or #col, #col))
    self.selected = { zone = "tableau", pile = pile, idx = idx }
    return "selected"
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function SpiderBoard:serialize()
    local data = self:_snapshot()
    data.variant = "spider"
    data.suits   = self.suits
    data.status  = self.status
    return data
end

-- Rejects any save whose cards are not exactly the two decks of its suit
-- count (completed runs count as 13 cards of their suit).
function SpiderBoard:load(data)
    if type(data) ~= "table" or data.variant ~= "spider"
        or type(data.tableau) ~= "table" or type(data.stock) ~= "table"
        or type(data.completed) ~= "table" then
        return false
    end
    local suits = tonumber(data.suits)
    if not SUIT_SETS[suits] or #data.tableau ~= NUM_COLS then return false end

    local census = Cards.newCensus()
    for p = 1, NUM_COLS do
        if not census:addList(data.tableau[p]) then return false end
    end
    if not census:addList(data.stock) then return false end
    for _, suit in ipairs(data.completed) do
        for rank = 1, 13 do
            if not census:add({ suit = suit, rank = rank }) then return false end
        end
    end
    local copies = {}
    for _, s in ipairs(SUIT_SETS[suits]) do copies[s] = (copies[s] or 0) + 1 end
    if not census:matches(copies) then return false end

    self:_apply(data)
    for _, c in ipairs(self.stock) do c.up = false end
    for p = 1, NUM_COLS do
        local col = self.tableau[p]
        if col[#col] then col[#col].up = true end
    end
    self.suits    = suits
    self.status   = data.status == "won" and "won" or "playing"
    self.selected = nil
    self._undo    = UndoStack:new{ max_size = 200 }
    return true
end

return SpiderBoard
