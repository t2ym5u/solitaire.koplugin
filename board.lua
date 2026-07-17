local UndoStack = require("undo_stack")

local SUITS      = { "S", "H", "D", "C" }
local RED_SUITS  = { H = true, D = true }
local DEFAULT_DRAW_COUNT = 1

local function isRed(suit) return RED_SUITS[suit] == true end

local function freshDeck()
    local deck = {}
    for _, suit in ipairs(SUITS) do
        for rank = 1, 13 do
            deck[#deck + 1] = { rank = rank, suit = suit }
        end
    end
    return deck
end

local function shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function copyCards(list)
    local out = {}
    for i, c in ipairs(list) do
        out[i] = { rank = c.rank, suit = c.suit, up = c.up and true or false }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- SolitaireBoard (Klondike)
-- ---------------------------------------------------------------------------

local SolitaireBoard = {}
SolitaireBoard.__index = SolitaireBoard

SolitaireBoard.SUITS = SUITS

function SolitaireBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        tableau     = {},
        foundations = { S = 0, H = 0, D = 0, C = 0 },
        stock       = {},
        waste       = {},
        draw_count  = opts.draw_count or DEFAULT_DRAW_COUNT,
        selected    = nil,
        status      = "playing",
        moves       = 0,
        _undo       = UndoStack:new{ max_size = 200 },
    }, self)
    obj:reset(obj.draw_count)
    return obj
end

function SolitaireBoard:reset(draw_count)
    self.draw_count = draw_count or self.draw_count or DEFAULT_DRAW_COUNT
    local deck = freshDeck()
    shuffle(deck)

    self.tableau = {}
    for pile = 1, 7 do
        self.tableau[pile] = {}
        for i = 1, pile do
            local card = table.remove(deck)
            card.up = (i == pile)
            self.tableau[pile][#self.tableau[pile] + 1] = card
        end
    end

    self.stock = deck
    self.waste = {}
    self.foundations = { S = 0, H = 0, D = 0, C = 0 }
    self.selected = nil
    self.status = "playing"
    self.moves = 0
    self._undo = UndoStack:new{ max_size = 200 }
end

-- ---------------------------------------------------------------------------
-- Undo (whole-board snapshots -- simplest robust approach given moves can
-- touch 2 zones + flip a newly-exposed tableau card in one step)
-- ---------------------------------------------------------------------------

function SolitaireBoard:_snapshot()
    local tableau_out = {}
    for i = 1, 7 do tableau_out[i] = copyCards(self.tableau[i]) end
    return {
        tableau     = tableau_out,
        foundations = { S = self.foundations.S, H = self.foundations.H,
                         D = self.foundations.D, C = self.foundations.C },
        stock       = copyCards(self.stock),
        waste       = copyCards(self.waste),
        moves       = self.moves,
    }
end

function SolitaireBoard:_restore(snap)
    self.tableau = {}
    for i = 1, 7 do self.tableau[i] = copyCards(snap.tableau[i]) end
    self.foundations = { S = snap.foundations.S, H = snap.foundations.H,
                          D = snap.foundations.D, C = snap.foundations.C }
    self.stock  = copyCards(snap.stock)
    self.waste  = copyCards(snap.waste)
    self.moves  = snap.moves
    self.status = "playing"
end

function SolitaireBoard:undo()
    local snap = self._undo:pop()
    if not snap then return false end
    self:_restore(snap)
    return true
end

function SolitaireBoard:canUndo()
    return self._undo:canUndo()
end

-- ---------------------------------------------------------------------------
-- Stock / waste
-- ---------------------------------------------------------------------------

-- Returns "drew" | "recycled" | "empty"
function SolitaireBoard:drawStock()
    if self.status ~= "playing" then return "empty" end
    self._undo:push(self:_snapshot())

    if #self.stock == 0 then
        if #self.waste == 0 then
            self._undo:pop()  -- nothing actually changed, don't leave a no-op undo entry
            return "empty"
        end
        for i = #self.waste, 1, -1 do
            local card = self.waste[i]
            card.up = false
            self.stock[#self.stock + 1] = card
        end
        self.waste = {}
        return "recycled"
    end

    local n = math.min(self.draw_count, #self.stock)
    for _ = 1, n do
        local card = table.remove(self.stock)
        card.up = true
        self.waste[#self.waste + 1] = card
    end
    return "drew"
end

-- ---------------------------------------------------------------------------
-- Move validation
-- ---------------------------------------------------------------------------

-- Returns the movable run (array of cards, bottom to top) starting at
-- tableau[pile][idx], or nil if that cell isn't the base of a valid
-- face-up, alternating-color, descending run.
function SolitaireBoard:getMovableRun(pile, idx)
    local col = self.tableau[pile]
    if not col or not col[idx] or not col[idx].up then return nil end
    for i = idx, #col - 1 do
        local a, b = col[i], col[i + 1]
        if not a.up or not b.up then return nil end
        if isRed(a.suit) == isRed(b.suit) then return nil end
        if a.rank ~= b.rank + 1 then return nil end
    end
    local run = {}
    for i = idx, #col do run[#run + 1] = col[i] end
    return run
end

function SolitaireBoard:isValidTableauMove(card, dest_pile)
    local col = self.tableau[dest_pile]
    if not col then return false end
    if #col == 0 then return card.rank == 13 end
    local top = col[#col]
    if not top.up then return false end
    return isRed(card.suit) ~= isRed(top.suit) and card.rank == top.rank - 1
end

function SolitaireBoard:isValidFoundationMove(card, suit)
    if card.suit ~= suit then return false end
    return self.foundations[suit] + 1 == card.rank
end

-- ---------------------------------------------------------------------------
-- Tap interaction (single entry point, mirrors memory.koplugin's tapCard
-- outcome-string idiom)
-- ---------------------------------------------------------------------------

local function sourceCard(self, sel)
    if sel.zone == "waste" then
        return self.waste[#self.waste]
    elseif sel.zone == "tableau" then
        local col = self.tableau[sel.pile]
        return col and col[sel.idx]
    end
    return nil
end

function SolitaireBoard:_removeSourceRun(sel, count)
    if sel.zone == "waste" then
        table.remove(self.waste)
    elseif sel.zone == "tableau" then
        local col = self.tableau[sel.pile]
        for _ = 1, count do table.remove(col) end
        local new_top = col[#col]
        if new_top and not new_top.up then new_top.up = true end
    end
end

function SolitaireBoard:_attemptMove(sel, dest)
    local run
    if sel.zone == "waste" then
        local card = self.waste[#self.waste]
        if not card then return false end
        run = { card }
    elseif sel.zone == "tableau" then
        run = self:getMovableRun(sel.pile, sel.idx)
        if not run then return false end
    else
        return false
    end

    if dest.zone == "foundation" then
        if #run ~= 1 then return false end
        local card = run[1]
        if not self:isValidFoundationMove(card, dest.suit) then return false end
        self._undo:push(self:_snapshot())
        self:_removeSourceRun(sel, 1)
        self.foundations[dest.suit] = card.rank
        return true
    elseif dest.zone == "tableau" then
        if sel.zone == "tableau" and sel.pile == dest.pile then return false end
        local card = run[1]
        if not self:isValidTableauMove(card, dest.pile) then return false end
        self._undo:push(self:_snapshot())
        self:_removeSourceRun(sel, #run)
        local dest_col = self.tableau[dest.pile]
        for _, c in ipairs(run) do
            dest_col[#dest_col + 1] = c
        end
        return true
    end
    return false
end

function SolitaireBoard:_afterMove()
    self.moves = self.moves + 1
    if self:isWon() then
        self.status = "won"
        return "won"
    end
    return "moved"
end

-- zone: "stock" | "waste" | "tableau" | "foundation"
-- pile: tableau pile index (1-7) for zone=="tableau", or suit key for zone=="foundation"
-- idx:  optional tableau card index; defaults to the pile's top card
--
-- Returns one of:
-- "drew" | "recycled" | "empty" (stock)
-- "selected" | "deselected" | "invalid" | "moved" | "won" | "not_playing"
function SolitaireBoard:tap(zone, pile, idx)
    if self.status ~= "playing" then return "not_playing" end

    if zone == "stock" then
        self.selected = nil
        return self:drawStock()
    end

    if self.selected then
        local sel = self.selected
        -- Tapping the exact same source again cancels the selection.
        if zone == "tableau" and sel.zone == "tableau" and sel.pile == pile then
            self.selected = nil
            return "deselected"
        end
        if zone == "waste" and sel.zone == "waste" then
            self.selected = nil
            return "deselected"
        end

        self.selected = nil
        local dest
        if zone == "tableau" then
            dest = { zone = "tableau", pile = pile }
        elseif zone == "foundation" then
            dest = { zone = "foundation", suit = pile }
        else
            return "invalid"
        end
        if self:_attemptMove(sel, dest) then
            return self:_afterMove()
        end
        return "invalid"
    end

    -- No active selection: try to select a source at this zone.
    if zone == "waste" then
        if #self.waste == 0 then return "invalid" end
        self.selected = { zone = "waste" }
        return "selected"
    elseif zone == "tableau" then
        local col = self.tableau[pile]
        if not col or #col == 0 then return "invalid" end
        idx = idx or #col
        local card = col[idx]
        if not card or not card.up then return "invalid" end
        self.selected = { zone = "tableau", pile = pile, idx = idx }
        return "selected"
    elseif zone == "foundation" then
        return "invalid"  -- moving a card back off a foundation isn't supported in v1
    end
    return "invalid"
end

-- Repeatedly auto-plays any waste-top/tableau-top card that has a legal
-- foundation move, until none remain. Returns the number of cards moved.
function SolitaireBoard:autoComplete()
    if self.status ~= "playing" then return 0 end
    local moved_count = 0
    local changed = true
    while changed do
        changed = false
        local w = self.waste[#self.waste]
        if w and self:isValidFoundationMove(w, w.suit) then
            self._undo:push(self:_snapshot())
            self:_removeSourceRun({ zone = "waste" }, 1)
            self.foundations[w.suit] = w.rank
            moved_count = moved_count + 1
            changed = true
        end
        for pile = 1, 7 do
            local col = self.tableau[pile]
            local c = col[#col]
            if c and c.up and self:isValidFoundationMove(c, c.suit) then
                self._undo:push(self:_snapshot())
                self:_removeSourceRun({ zone = "tableau", pile = pile }, 1)
                self.foundations[c.suit] = c.rank
                moved_count = moved_count + 1
                changed = true
            end
        end
    end
    if moved_count > 0 then self.moves = self.moves + moved_count end
    if self:isWon() then self.status = "won" end
    return moved_count
end

function SolitaireBoard:isWon()
    return self.foundations.S == 13 and self.foundations.H == 13
       and self.foundations.D == 13 and self.foundations.C == 13
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function SolitaireBoard:serialize()
    local tableau_out = {}
    for i = 1, 7 do tableau_out[i] = copyCards(self.tableau[i]) end
    return {
        tableau     = tableau_out,
        foundations = { S = self.foundations.S, H = self.foundations.H,
                         D = self.foundations.D, C = self.foundations.C },
        stock       = copyCards(self.stock),
        waste       = copyCards(self.waste),
        draw_count  = self.draw_count,
        status      = self.status,
        moves       = self.moves,
    }
end

-- Validates that every one of the 52 (suit,rank) pairs appears exactly once
-- across tableau+foundations+stock+waste before accepting -- KOReader can
-- suspend the app at any point, so a corrupted/partial save must never be
-- silently loaded as if it were a valid game.
function SolitaireBoard:load(data)
    if type(data) ~= "table" or not data.tableau or not data.stock
        or not data.waste or not data.foundations then
        return false
    end

    local seen = {}
    local total = 0
    local function mark(suit, rank)
        if type(rank) ~= "number" or rank < 1 or rank > 13 then return false end
        local key = suit .. rank
        if seen[key] then return false end
        seen[key] = true
        total = total + 1
        return true
    end

    if #data.tableau ~= 7 then return false end
    for _, col in ipairs(data.tableau) do
        for _, c in ipairs(col) do
            if not mark(c.suit, c.rank) then return false end
        end
    end
    for _, c in ipairs(data.stock) do
        if not mark(c.suit, c.rank) then return false end
    end
    for _, c in ipairs(data.waste) do
        if not mark(c.suit, c.rank) then return false end
    end
    for _, suit in ipairs(SUITS) do
        local n = data.foundations[suit] or 0
        for rank = 1, n do
            if not mark(suit, rank) then return false end
        end
    end
    if total ~= 52 then return false end

    self.tableau = {}
    for i = 1, 7 do self.tableau[i] = copyCards(data.tableau[i]) end
    self.foundations = { S = data.foundations.S or 0, H = data.foundations.H or 0,
                          D = data.foundations.D or 0, C = data.foundations.C or 0 }
    self.stock = copyCards(data.stock)
    for _, c in ipairs(self.stock) do c.up = false end
    self.waste = copyCards(data.waste)
    for _, c in ipairs(self.waste) do c.up = true end
    self.draw_count = data.draw_count or DEFAULT_DRAW_COUNT
    self.selected   = nil
    self.status     = data.status or "playing"
    self.moves      = data.moves or 0
    self._undo      = UndoStack:new{ max_size = 200 }
    return true
end

return SolitaireBoard
