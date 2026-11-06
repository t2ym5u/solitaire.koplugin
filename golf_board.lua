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

local NUM_COLS   = 7
local COL_HEIGHT = 5

-- ---------------------------------------------------------------------------
-- GolfBoard
--
-- 7 face-up columns of 5 cards, a 16-card stock and a waste started with
-- one card from the stock. The top card of any column may go onto the waste
-- when its rank is one above or one below the waste card, whatever the suit.
-- Kings and Aces do not connect unless `wrap` is on. The stock deals one
-- card at a time to the waste and is never recycled.
--
-- Won when every column is cleared; lost when the stock is empty and no
-- column top fits the waste. There is only one destination, so a single tap
-- on a column plays its top card.
-- ---------------------------------------------------------------------------

local GolfBoard = {}
GolfBoard.__index = GolfBoard

GolfBoard.NUM_COLS   = NUM_COLS
GolfBoard.COL_HEIGHT = COL_HEIGHT

-- opts.empty: no deal yet (the caller loads a save, or calls reset).
function GolfBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({}, self)
    if opts.empty then
        obj.wrap = opts.wrap and true or false
        return obj
    end
    obj:reset(opts.wrap)
    return obj
end

-- Every deal can be won. A deal is kept once a random game on it clears the
-- tableau: up to PLAYOUTS games per deal, each playing a random fitting
-- column card whenever there is one, else the next stock card. That winning
-- game is the proof. Only about 4 deals in 10 can be won without the K-A
-- wrap (9 in 10 with it), so a few deals are usually tried; the work is
-- capped by counts and only uses math.random, so a seed always gives the
-- same deal. MAX_DEALS is never reached in practice (each deal passes with
-- a chance of 1 in 7 or better): the last deal is then kept as it is.
GolfBoard.PLAYOUTS  = 100
GolfBoard.MAX_DEALS = 200

local function randomWin(tableau, stock, top0, wrap, tries)
    local base, h = {}, {}
    for p = 1, NUM_COLS do
        base[p] = {}
        for i = 1, #tableau[p] do base[p][i] = tableau[p][i].rank end
    end
    local draws = {}
    for i = #stock, 1, -1 do draws[#draws + 1] = stock[i].rank end
    local ns, total = #draws, NUM_COLS * COL_HEIGHT
    local cand = {}
    for _ = 1, tries do
        for p = 1, NUM_COLS do h[p] = #base[p] end
        local top, sp, left = top0, 0, total
        while true do
            local n = 0
            for p = 1, NUM_COLS do
                local hp = h[p]
                if hp > 0 then
                    local d = base[p][hp] - top
                    if d == 1 or d == -1 or (wrap and (d == 12 or d == -12)) then
                        n = n + 1
                        cand[n] = p
                    end
                end
            end
            if n > 0 then
                local p = cand[math.random(n)]
                top = base[p][h[p]]
                h[p] = h[p] - 1
                left = left - 1
                if left == 0 then return true end
            elseif sp < ns then
                sp = sp + 1
                top = draws[sp]
            else
                break
            end
        end
    end
    return false
end
GolfBoard._randomWin = randomWin

local function dealOnce()
    local deck = Cards.deck()
    Cards.shuffle(deck)
    local tableau = {}
    for p = 1, NUM_COLS do
        local col = {}
        for i = 1, COL_HEIGHT do
            local card = table.remove(deck)
            card.up = true
            col[i] = card
        end
        tableau[p] = col
    end
    local first = table.remove(deck)
    first.up = true
    return tableau, deck, first
end

function GolfBoard:reset(wrap)
    if wrap ~= nil then self.wrap = wrap and true or false end
    if self.wrap == nil then self.wrap = false end
    local tableau, deck, first
    for _ = 1, GolfBoard.MAX_DEALS do
        tableau, deck, first = dealOnce()
        if randomWin(tableau, deck, first.rank, self.wrap, GolfBoard.PLAYOUTS) then break end
    end
    self.tableau  = tableau
    self.waste    = { first }
    self.stock    = deck
    self.selected = nil
    self.status   = "playing"
    self.moves    = 0
    self._undo    = UndoStack:new{ max_size = 200 }
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

function GolfBoard:_snapshot()
    return {
        tableau = Cards.copyPiles(self.tableau, NUM_COLS),
        stock   = Cards.copyList(self.stock),
        waste   = Cards.copyList(self.waste),
        moves   = self.moves,
    }
end

function GolfBoard:_apply(snap)
    self.tableau = Cards.copyPiles(snap.tableau, NUM_COLS)
    self.stock   = Cards.copyList(snap.stock)
    self.waste   = Cards.copyList(snap.waste)
    self.moves   = snap.moves or 0
end

function GolfBoard:undo()
    local snap = self._undo:pop()
    if not snap then return false end
    self:_apply(snap)
    self.status = "playing"
    return true
end

function GolfBoard:canUndo()
    return self._undo:canUndo()
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

function GolfBoard:fitsOnWaste(card)
    local top = self.waste[#self.waste]
    if not card or not top then return false end
    local d = math.abs(card.rank - top.rank)
    return d == 1 or (self.wrap and d == 12)
end

function GolfBoard:cardsLeft()
    local n = 0
    for p = 1, NUM_COLS do n = n + #self.tableau[p] end
    return n
end

function GolfBoard:isWon()
    return self:cardsLeft() == 0
end

function GolfBoard:hasMoves()
    if #self.stock > 0 then return true end
    for p = 1, NUM_COLS do
        local col = self.tableau[p]
        if self:fitsOnWaste(col[#col]) then return true end
    end
    return false
end

-- Golf score: cards left on the tableau, or minus the stock left after a win.
function GolfBoard:score()
    local left = self:cardsLeft()
    if left == 0 then return -#self.stock end
    return left
end

function GolfBoard:_settle(result)
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

-- zone: "stock" | "tableau" (pile 1-7) | "waste".
-- Returns "drew" | "empty" | "moved" | "won" | "lost" | "invalid" |
-- "not_playing".
function GolfBoard:tap(zone, pile)
    if self.status ~= "playing" then return "not_playing" end
    if zone == "stock" then
        if #self.stock == 0 then return "empty" end
        self._undo:push(self:_snapshot())
        local card = table.remove(self.stock)
        card.up = true
        self.waste[#self.waste + 1] = card
        self.moves = self.moves + 1
        return self:_settle("drew")
    elseif zone == "tableau" then
        local col = self.tableau[pile]
        local card = col and col[#col]
        if not self:fitsOnWaste(card) then return "invalid" end
        self._undo:push(self:_snapshot())
        self.waste[#self.waste + 1] = table.remove(col)
        self.moves = self.moves + 1
        return self:_settle("moved")
    end
    return "invalid"
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function GolfBoard:serialize()
    local data = self:_snapshot()
    data.variant = "golf"
    data.wrap    = self.wrap
    data.status  = self.status
    return data
end

function GolfBoard:load(data)
    if type(data) ~= "table" or data.variant ~= "golf"
        or type(data.tableau) ~= "table" or type(data.stock) ~= "table"
        or type(data.waste) ~= "table" or #data.waste == 0 then
        return false
    end
    if #data.tableau ~= NUM_COLS then return false end
    local census = Cards.newCensus()
    for p = 1, NUM_COLS do
        if not census:addList(data.tableau[p]) then return false end
    end
    if not census:addList(data.stock) or not census:addList(data.waste) then return false end
    if not census:matches({ S = 1, H = 1, D = 1, C = 1 }) then return false end

    self:_apply(data)
    for p = 1, NUM_COLS do
        for _, c in ipairs(self.tableau[p]) do c.up = true end
    end
    for _, c in ipairs(self.stock) do c.up = false end
    for _, c in ipairs(self.waste) do c.up = true end
    self.wrap     = data.wrap and true or false
    self.status   = (data.status == "won" or data.status == "lost") and data.status or "playing"
    self.selected = nil
    self._undo    = UndoStack:new{ max_size = 200 }
    return true
end

return GolfBoard
