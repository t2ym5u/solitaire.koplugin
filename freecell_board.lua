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

local isRed = Cards.isRed

local NUM_CELLS = 4
local NUM_COLS  = 8
local MAX_DEAL  = 32000

-- ---------------------------------------------------------------------------
-- FreeCellBoard
--
-- 8 face-up tableau columns, 4 free cells (one card each), 4 foundations.
-- Deals are numbered 1..32000 and reproduce Microsoft FreeCell's deals, so a
-- player can replay a famous deal (#11982 is the one known unsolvable deal in
-- that range; every other one is winnable).
--
-- Only single cards really move. A run of N cards is a "supermove": it is
-- legal when it could be shuffled one card at a time through the free cells
-- and empty columns, i.e. N <= (free cells + 1) * 2^(empty columns), not
-- counting the destination column when it is empty itself.
-- ---------------------------------------------------------------------------

local FreeCellBoard = {}
FreeCellBoard.__index = FreeCellBoard

FreeCellBoard.NUM_CELLS = NUM_CELLS
FreeCellBoard.NUM_COLS  = NUM_COLS
FreeCellBoard.MAX_DEAL  = MAX_DEAL

-- Microsoft C runtime rand(): 31-bit LCG, 15-bit output. All products stay
-- below 2^53, so plain Lua numbers (doubles) compute it exactly, on LuaJIT
-- and on Lua 5.3+ alike.
local function msRand(state)
    state = (214013 * state + 2531011) % 2147483648
    return state, math.floor(state / 65536)
end

-- Returns the 8 columns of Microsoft FreeCell deal `n` (top card last).
-- Cards are numbered rank-major in Clubs, Diamonds, Hearts, Spades order;
-- each draw swaps the last undealt card into the hole it leaves.
function FreeCellBoard.msDeal(n)
    local ms_suits = { "C", "D", "H", "S" }
    local deck = {}
    for i = 0, 51 do deck[i + 1] = i end
    local cols = {}
    for c = 1, NUM_COLS do cols[c] = {} end
    local state, r = n, 0
    local left = 52
    for i = 0, 51 do
        state, r = msRand(state)
        local j = r % left
        local card = deck[j + 1]
        deck[j + 1] = deck[left]
        left = left - 1
        local col = cols[(i % NUM_COLS) + 1]
        col[#col + 1] = { rank = math.floor(card / 4) + 1, suit = ms_suits[(card % 4) + 1], up = true }
    end
    return cols
end

function FreeCellBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({}, self)
    obj:reset(opts.deal)
    return obj
end

-- deal: 1..32000, or nil for a random one.
function FreeCellBoard:reset(deal)
    deal = tonumber(deal)
    if not deal or deal < 1 or deal > MAX_DEAL then
        deal = math.random(MAX_DEAL)
    end
    self.deal        = math.floor(deal)
    self.tableau     = FreeCellBoard.msDeal(self.deal)
    self.cells       = { false, false, false, false }
    self.foundations = Cards.copyFoundations()
    self.selected    = nil
    self.status      = "playing"
    self.moves       = 0
    self._undo       = UndoStack:new{ max_size = 200 }
end

-- ---------------------------------------------------------------------------
-- Undo: whole-board snapshots (a supermove touches two columns at once).
-- ---------------------------------------------------------------------------

function FreeCellBoard:_snapshot()
    local cells = {}
    for i = 1, NUM_CELLS do cells[i] = Cards.copyCard(self.cells[i]) end
    return {
        tableau     = Cards.copyPiles(self.tableau, NUM_COLS),
        cells       = cells,
        foundations = Cards.copyFoundations(self.foundations),
        moves       = self.moves,
    }
end

function FreeCellBoard:_apply(snap)
    self.tableau = Cards.copyPiles(snap.tableau, NUM_COLS)
    self.cells = {}
    for i = 1, NUM_CELLS do self.cells[i] = Cards.copyCard(snap.cells[i]) end
    self.foundations = Cards.copyFoundations(snap.foundations)
    self.moves = snap.moves or 0
end

function FreeCellBoard:undo()
    local snap = self._undo:pop()
    if not snap then return false end
    self:_apply(snap)
    self.selected = nil
    self.status = "playing"
    return true
end

function FreeCellBoard:canUndo()
    return self._undo:canUndo()
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

function FreeCellBoard:freeCellCount()
    local n = 0
    for i = 1, NUM_CELLS do
        if not self.cells[i] then n = n + 1 end
    end
    return n
end

function FreeCellBoard:emptyColumnCount()
    local n = 0
    for i = 1, NUM_COLS do
        if #self.tableau[i] == 0 then n = n + 1 end
    end
    return n
end

-- Largest run that may move at once onto a column; an empty destination
-- column cannot also serve as a temporary spot.
function FreeCellBoard:maxRunLength(dest_is_empty)
    local empty = self:emptyColumnCount()
    if dest_is_empty then empty = empty - 1 end
    if empty < 0 then empty = 0 end
    return (self:freeCellCount() + 1) * (2 ^ empty)
end

-- True when col[idx..#col] is a descending, alternating-colour run.
function FreeCellBoard:isRun(pile, idx)
    local col = self.tableau[pile]
    if not col or not col[idx] then return false end
    for i = idx, #col - 1 do
        local a, b = col[i], col[i + 1]
        if isRed(a.suit) == isRed(b.suit) or a.rank ~= b.rank + 1 then return false end
    end
    return true
end

-- Index of the deepest card that heads a run ending at the top of the pile.
function FreeCellBoard:runBase(pile)
    local col = self.tableau[pile]
    local idx = #col
    while idx > 1 do
        local a, b = col[idx - 1], col[idx]
        if isRed(a.suit) == isRed(b.suit) or a.rank ~= b.rank + 1 then break end
        idx = idx - 1
    end
    return idx
end

function FreeCellBoard:fitsOnTableau(card, pile)
    local col = self.tableau[pile]
    if #col == 0 then return true end
    local top = col[#col]
    return isRed(card.suit) ~= isRed(top.suit) and card.rank == top.rank - 1
end

function FreeCellBoard:fitsOnFoundation(card)
    return self.foundations[card.suit] + 1 == card.rank
end

function FreeCellBoard:isWon()
    local f = self.foundations
    return f.S == 13 and f.H == 13 and f.D == 13 and f.C == 13
end

function FreeCellBoard:foundationCount()
    local f = self.foundations
    return f.S + f.H + f.D + f.C
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

-- The single card a selection stands for (cells and tableau tops), or nil.
function FreeCellBoard:_singleCard(sel)
    if sel.zone == "cell" then
        return self.cells[sel.pile] or nil
    end
    local col = self.tableau[sel.pile]
    if sel.idx ~= #col then return nil end
    return col[#col]
end

function FreeCellBoard:_takeSingle(sel)
    if sel.zone == "cell" then
        local c = self.cells[sel.pile]
        self.cells[sel.pile] = false
        return c
    end
    return table.remove(self.tableau[sel.pile])
end

-- Moves the selected run onto tableau column `dest`. When the run picked
-- does not fit, the matching shorter run inside it is used instead (tap a
-- column's top card, then a column whose top accepts any card of that run).
-- Returns "ok" | "invalid" | "too_many".
function FreeCellBoard:_moveToTableau(sel, dest)
    local dest_col = self.tableau[dest]
    if sel.zone == "cell" then
        local card = self.cells[sel.pile]
        if not card or not self:fitsOnTableau(card, dest) then return "invalid" end
        self._undo:push(self:_snapshot())
        self.cells[sel.pile] = false
        dest_col[#dest_col + 1] = card
        return "ok"
    end

    if sel.pile == dest then return "invalid" end
    local col = self.tableau[sel.pile]
    local start = sel.idx
    if not self:fitsOnTableau(col[start], dest) then
        start = nil
        if #dest_col > 0 then
            for i = sel.idx + 1, #col do
                if self:fitsOnTableau(col[i], dest) then start = i break end
            end
        end
        if not start then return "invalid" end
    end
    local count = #col - start + 1
    if count > self:maxRunLength(#dest_col == 0) then return "too_many" end

    self._undo:push(self:_snapshot())
    for i = start, #col do dest_col[#dest_col + 1] = col[i] end
    for _ = 1, count do table.remove(col) end
    return "ok"
end

function FreeCellBoard:_moveToCell(sel, cell)
    if self.cells[cell] then return "invalid" end
    local card = self:_singleCard(sel)
    if not card then
        -- A run was selected: park its top card, the only one that can go.
        if sel.zone ~= "tableau" then return "invalid" end
        sel = { zone = "tableau", pile = sel.pile, idx = #self.tableau[sel.pile] }
    end
    self._undo:push(self:_snapshot())
    self.cells[cell] = self:_takeSingle(sel)
    return "ok"
end

function FreeCellBoard:_moveToFoundation(sel)
    local card = self:_singleCard(sel)
    if not card and sel.zone == "tableau" then
        sel = { zone = "tableau", pile = sel.pile, idx = #self.tableau[sel.pile] }
        card = self:_singleCard(sel)
    end
    if not card or not self:fitsOnFoundation(card) then return "invalid" end
    self._undo:push(self:_snapshot())
    self:_takeSingle(sel)
    self.foundations[card.suit] = card.rank
    return "ok"
end

function FreeCellBoard:_afterMove()
    self.moves = self.moves + 1
    if self:isWon() then
        self.status = "won"
        return "won"
    end
    return "moved"
end

-- zone: "tableau" (pile 1-8, idx card) | "cell" (pile 1-4) | "foundation"
-- (pile = suit key). Returns "selected" | "deselected" | "invalid" |
-- "too_many" | "moved" | "won" | "not_playing".
function FreeCellBoard:tap(zone, pile, idx)
    if self.status ~= "playing" then return "not_playing" end

    local sel = self.selected
    if sel then
        self.selected = nil
        if zone == sel.zone and pile == sel.pile then return "deselected" end
        local r
        if zone == "tableau" then
            r = self:_moveToTableau(sel, pile)
        elseif zone == "cell" then
            r = self:_moveToCell(sel, pile)
        elseif zone == "foundation" then
            r = self:_moveToFoundation(sel)
        else
            r = "invalid"
        end
        if r == "ok" then return self:_afterMove() end
        return r
    end

    if zone == "cell" then
        if not self.cells[pile] then return "invalid" end
        self.selected = { zone = "cell", pile = pile }
        return "selected"
    elseif zone == "tableau" then
        local col = self.tableau[pile]
        if not col or #col == 0 then return "invalid" end
        -- A tap on a card buried under an out-of-sequence card selects the
        -- run that can actually move.
        local base = self:runBase(pile)
        idx = math.max(base, math.min(idx or #col, #col))
        self.selected = { zone = "tableau", pile = pile, idx = idx }
        return "selected"
    end
    return "invalid"
end

-- Double-tap shortcut: send a tableau or cell top card to its foundation.
function FreeCellBoard:sendTopCardToFoundation(zone, pile)
    if self.status ~= "playing" then return "not_playing" end
    self.selected = nil
    local sel
    if zone == "cell" then
        sel = { zone = "cell", pile = pile }
    elseif zone == "tableau" then
        local col = self.tableau[pile]
        if not col or #col == 0 then return "invalid" end
        sel = { zone = "tableau", pile = pile, idx = #col }
    else
        return "invalid"
    end
    if self:_moveToFoundation(sel) == "ok" then return self:_afterMove() end
    return "invalid"
end

-- Plays every cell/tableau top card that fits a foundation until none do.
-- Each card is its own undo step, like Klondike's auto-complete.
function FreeCellBoard:autoComplete()
    if self.status ~= "playing" then return 0 end
    self.selected = nil
    local moved = 0
    local changed = true
    while changed do
        changed = false
        for i = 1, NUM_CELLS do
            if self:_moveToFoundation({ zone = "cell", pile = i }) == "ok" then
                moved, changed = moved + 1, true
            end
        end
        for p = 1, NUM_COLS do
            local col = self.tableau[p]
            if #col > 0 and self:_moveToFoundation({ zone = "tableau", pile = p, idx = #col }) == "ok" then
                moved, changed = moved + 1, true
            end
        end
    end
    self.moves = self.moves + moved
    if self:isWon() then self.status = "won" end
    return moved
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function FreeCellBoard:serialize()
    local data = self:_snapshot()
    data.variant = "freecell"
    data.deal    = self.deal
    data.status  = self.status
    return data
end

-- Rejects any save that does not hold each of the 52 cards exactly once.
function FreeCellBoard:load(data)
    if type(data) ~= "table" or data.variant ~= "freecell"
        or type(data.tableau) ~= "table" or type(data.cells) ~= "table"
        or type(data.foundations) ~= "table" then
        return false
    end
    if #data.tableau ~= NUM_COLS then return false end
    local census = Cards.newCensus()
    for i = 1, NUM_COLS do
        if not census:addList(data.tableau[i]) then return false end
    end
    for i = 1, NUM_CELLS do
        local c = data.cells[i]
        if c and not census:add(c) then return false end
    end
    for _, suit in ipairs(Cards.SUITS) do
        local n = data.foundations[suit] or 0
        if type(n) ~= "number" or n < 0 or n > 13 then return false end
        for rank = 1, n do census:add({ suit = suit, rank = rank }) end
    end
    if not census:matches({ S = 1, H = 1, D = 1, C = 1 }) then return false end

    self:_apply(data)
    for i = 1, NUM_COLS do
        for _, c in ipairs(self.tableau[i]) do c.up = true end
    end
    for i = 1, NUM_CELLS do
        if self.cells[i] then self.cells[i].up = true end
    end
    self.deal     = tonumber(data.deal) or 0
    self.status   = data.status == "won" and "won" or "playing"
    self.selected = nil
    self._undo    = UndoStack:new{ max_size = 200 }
    return true
end

return FreeCellBoard
