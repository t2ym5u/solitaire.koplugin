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

local ROWS = 7
local DEFAULT_PASSES = 3

-- ---------------------------------------------------------------------------
-- PyramidBoard
--
-- 28 face-up cards in a 7-row pyramid; row r holds r cards and card (r, i)
-- is covered by (r+1, i) and (r+1, i+1). The other 24 cards form a stock
-- turned one at a time onto a waste pile.
--
-- Remove an uncovered card (or the waste top) together with another one
-- when their ranks add up to 13 (J = 11, Q = 12), a King on its own. Once
-- the stock is empty the waste may be turned back over until `passes`
-- passes through the stock are used up (0 = unlimited). Won when the
-- pyramid is cleared; lost when no move is left.
-- ---------------------------------------------------------------------------

local PyramidBoard = {}
PyramidBoard.__index = PyramidBoard

PyramidBoard.ROWS = ROWS
PyramidBoard.DEFAULT_PASSES = DEFAULT_PASSES

local function validPasses(n)
    n = tonumber(n)
    if n == 0 or n == 1 or n == 2 or n == 3 then return n end
    return DEFAULT_PASSES
end

function PyramidBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({}, self)
    obj:reset(opts.passes)
    return obj
end

function PyramidBoard:reset(passes)
    self.passes = validPasses(passes or self.passes)
    local deck = Cards.deck()
    Cards.shuffle(deck)
    self.pyramid = {}
    for r = 1, ROWS do
        local row = {}
        for i = 1, r do
            local card = table.remove(deck)
            card.up = true
            row[i] = card
        end
        self.pyramid[r] = row
    end
    self.stock    = deck
    self.waste    = {}
    self.discard  = {}
    self.pass     = 1
    self.selected = nil
    self.status   = "playing"
    self.moves    = 0
    self._undo    = UndoStack:new{ max_size = 200 }
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

local function copyPyramid(src)
    local out = {}
    for r = 1, ROWS do
        local row = {}
        for i = 1, r do row[i] = Cards.copyCard(src[r] and src[r][i]) end
        out[r] = row
    end
    return out
end

function PyramidBoard:_snapshot()
    return {
        pyramid = copyPyramid(self.pyramid),
        stock   = Cards.copyList(self.stock),
        waste   = Cards.copyList(self.waste),
        discard = Cards.copyList(self.discard),
        pass    = self.pass,
        moves   = self.moves,
    }
end

function PyramidBoard:_apply(snap)
    self.pyramid = copyPyramid(snap.pyramid)
    self.stock   = Cards.copyList(snap.stock)
    self.waste   = Cards.copyList(snap.waste)
    self.discard = Cards.copyList(snap.discard)
    self.pass    = snap.pass or 1
    self.moves   = snap.moves or 0
end

function PyramidBoard:undo()
    local snap = self._undo:pop()
    if not snap then return false end
    self:_apply(snap)
    self.selected = nil
    self.status = "playing"
    return true
end

function PyramidBoard:canUndo()
    return self._undo:canUndo()
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

function PyramidBoard:isExposed(r, i)
    local row = self.pyramid[r]
    if not row or not row[i] then return false end
    if r == ROWS then return true end
    local below = self.pyramid[r + 1]
    return not below[i] and not below[i + 1]
end

function PyramidBoard:cardsLeft()
    local n = 0
    for r = 1, ROWS do
        for i = 1, r do
            if self.pyramid[r][i] then n = n + 1 end
        end
    end
    return n
end

function PyramidBoard:isWon()
    return self:cardsLeft() == 0
end

function PyramidBoard:canRecycle()
    return #self.stock == 0 and #self.waste > 0
        and (self.passes == 0 or self.pass < self.passes)
end

-- Passes left after the current one, or nil when unlimited.
function PyramidBoard:redealsLeft()
    if self.passes == 0 then return nil end
    return self.passes - self.pass
end

-- Every card that can be played right now, as { card = , sel = }.
function PyramidBoard:availableCards()
    local out = {}
    for r = 1, ROWS do
        for i = 1, r do
            if self:isExposed(r, i) then
                out[#out + 1] = { card = self.pyramid[r][i], sel = { zone = "pyramid", pile = r, idx = i } }
            end
        end
    end
    local w = self.waste[#self.waste]
    if w then out[#out + 1] = { card = w, sel = { zone = "waste" } } end
    return out
end

-- True when a King or a pair adding up to 13 can be removed now.
function PyramidBoard:hasPairMove()
    local avail = self:availableCards()
    local seen = {}
    for _, a in ipairs(avail) do
        local r = a.card.rank
        if r == 13 or seen[13 - r] then return true end
        seen[r] = true
    end
    return false
end

function PyramidBoard:hasMoves()
    return #self.stock > 0 or self:canRecycle() or self:hasPairMove()
end

function PyramidBoard:_cardAt(sel)
    if sel.zone == "waste" then return self.waste[#self.waste] end
    if sel.zone == "pyramid" and self:isExposed(sel.pile, sel.idx) then
        return self.pyramid[sel.pile][sel.idx]
    end
    return nil
end

function PyramidBoard:_remove(sel)
    local card
    if sel.zone == "waste" then
        card = table.remove(self.waste)
    else
        card = self.pyramid[sel.pile][sel.idx]
        self.pyramid[sel.pile][sel.idx] = false
    end
    self.discard[#self.discard + 1] = card
end

function PyramidBoard:_settle(result)
    if self:isWon() then
        self.status = "won"
        return "won"
    end
    if not self:hasMoves() then
        self.status = "lost"
        return "lost"
    end
    return result
end

function PyramidBoard:_drawStock()
    if #self.stock > 0 then
        self._undo:push(self:_snapshot())
        local card = table.remove(self.stock)
        card.up = true
        self.waste[#self.waste + 1] = card
        self.moves = self.moves + 1
        return self:_settle("drew")
    end
    if self:canRecycle() then
        self._undo:push(self:_snapshot())
        for i = #self.waste, 1, -1 do
            local card = self.waste[i]
            card.up = false
            self.stock[#self.stock + 1] = card
        end
        self.waste = {}
        self.pass = self.pass + 1
        self.moves = self.moves + 1
        return self:_settle("recycled")
    end
    return "empty"
end

-- zone: "stock" | "waste" | "pyramid" (pile = row, idx = position in row).
-- Returns "drew" | "recycled" | "empty" | "selected" | "deselected" |
-- "invalid" | "moved" | "won" | "lost" | "not_playing".
function PyramidBoard:tap(zone, pile, idx)
    if self.status ~= "playing" then return "not_playing" end
    if zone == "stock" then
        self.selected = nil
        return self:_drawStock()
    end
    if zone ~= "waste" and zone ~= "pyramid" then return "invalid" end

    local here = { zone = zone, pile = pile, idx = idx }
    local card = self:_cardAt(here)
    local sel = self.selected
    self.selected = nil
    if not card then return "invalid" end

    if sel and sel.zone == here.zone and sel.pile == here.pile and sel.idx == here.idx then
        return "deselected"
    end
    if card.rank == 13 then
        self._undo:push(self:_snapshot())
        self:_remove(here)
        self.moves = self.moves + 1
        return self:_settle("moved")
    end
    if not sel then
        self.selected = here
        return "selected"
    end
    local other = self:_cardAt(sel)
    if not other or other.rank + card.rank ~= 13 then return "invalid" end
    self._undo:push(self:_snapshot())
    self:_remove(sel)
    self:_remove(here)
    self.moves = self.moves + 1
    return self:_settle("moved")
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function PyramidBoard:serialize()
    local data = self:_snapshot()
    data.variant = "pyramid"
    data.passes  = self.passes
    data.status  = self.status
    return data
end

function PyramidBoard:load(data)
    if type(data) ~= "table" or data.variant ~= "pyramid"
        or type(data.pyramid) ~= "table" or type(data.stock) ~= "table"
        or type(data.waste) ~= "table" or type(data.discard) ~= "table" then
        return false
    end
    local census = Cards.newCensus()
    for r = 1, ROWS do
        local row = data.pyramid[r]
        if type(row) ~= "table" then return false end
        for i = 1, r do
            if row[i] and not census:add(row[i]) then return false end
        end
    end
    if not census:addList(data.stock) or not census:addList(data.waste)
        or not census:addList(data.discard) then
        return false
    end
    if not census:matches({ S = 1, H = 1, D = 1, C = 1 }) then return false end

    self:_apply(data)
    for _, c in ipairs(self.stock) do c.up = false end
    for _, c in ipairs(self.waste) do c.up = true end
    self.passes   = validPasses(data.passes)
    self.status   = (data.status == "won" or data.status == "lost") and data.status or "playing"
    self.selected = nil
    self._undo    = UndoStack:new{ max_size = 200 }
    return true
end

return PyramidBoard
