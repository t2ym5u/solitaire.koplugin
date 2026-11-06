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

-- opts.empty: no deal yet (the caller loads a save, or calls reset).
function PyramidBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({}, self)
    if opts.empty then
        obj.passes = validPasses(opts.passes)
        return obj
    end
    obj:reset(opts.passes)
    return obj
end

-- ---------------------------------------------------------------------------
-- Winnable deals
--
-- Every deal can be won. A random deal is kept once a depth-first search,
-- capped at SOLVE_NODES positions, finds a way to clear the pyramid; that
-- is the proof. About 6 random deals in 10 can be won with 3 passes or
-- unlimited passes, 4 in 10 with 2, so a few deals are usually tried. With
-- a single pass only about 1 deal in 25 can be won, too few to find by
-- trying: those deals are built around a winning game instead (see
-- buildDeal), as is any deal after MAX_DEALS failed tries, which never
-- happens in practice. All the work is capped by counts and only uses
-- math.random, so a seed always gives the same deal.
-- ---------------------------------------------------------------------------

PyramidBoard.SOLVE_NODES = 300
PyramidBoard.MAX_DEALS   = 120

local SLOTS = ROWS * (ROWS + 1) / 2
local SLOT_ROW, SLOT_IDX, KID1, KID2 = {}, {}, {}, {}
do
    local idx, k = {}, 0
    for r = 1, ROWS do
        idx[r] = {}
        for i = 1, r do
            k = k + 1
            idx[r][i] = k
            SLOT_ROW[k], SLOT_IDX[k] = r, i
        end
    end
    for r = 1, ROWS - 1 do
        for i = 1, r do
            KID1[idx[r][i]] = idx[r + 1][i]
            KID2[idx[r][i]] = idx[r + 1][i + 1]
        end
    end
end

-- Search for a win from a position: pyramid[r][i] cards (false = removed),
-- stock (top last), waste (top last), the current pass and the pass limit.
-- Returns true (a win was found), false (proved lost) or nil (cap reached).
-- With a `trace` table, a win also fills it with the winning moves, in
-- order: { "king", r, i }, { "king_waste" }, { "pair", r1, i1, r2, i2 },
-- { "pair_waste", r, i } or { "stock" } (draw or turn the waste over).
function PyramidBoard.solve(pyramid, stock, waste, pass0, passes, cap, trace)
    local rank, gone, bitv = {}, {}, {}
    local pmask, left, b = 0, 0, 1
    for k = 1, SLOTS do
        bitv[k] = b
        b = b * 2
        local c = pyramid[SLOT_ROW[k]][SLOT_IDX[k]]
        if c then
            rank[k], gone[k], left = c.rank, false, left + 1
        else
            rank[k], gone[k], pmask = 0, true, pmask + bitv[k]
        end
    end
    if left == 0 then return true end
    -- Waste bottom to top, then the stock in drawing order: one sequence.
    local seq = {}
    for i = 1, #waste do seq[#seq + 1] = waste[i].rank end
    local pos0 = #seq
    for i = #stock, 1, -1 do seq[#seq + 1] = stock[i].rank end
    local ns = #seq
    local sg, sbit, smask = {}, {}, 0
    b = 1
    for j = 1, ns do sg[j], sbit[j], b = false, b, b * 2 end
    local seen, nodes = {}, 0
    local function note(m)
        if trace then table.insert(trace, 1, m) end
        return true
    end

    local function wasteTop(pos)
        for j = pos, 1, -1 do if not sg[j] then return j end end
        return nil
    end
    local function takeP(k, v)
        gone[k] = v
        if v then pmask, left = pmask + bitv[k], left - 1
        else pmask, left = pmask - bitv[k], left + 1 end
    end
    local function takeS(j, v)
        sg[j] = v
        smask = v and smask + sbit[j] or smask - sbit[j]
    end

    local dfs
    dfs = function(pos, pass)
        if left == 0 then return true end
        nodes = nodes + 1
        if nodes > cap then error("cap", 0) end
        local t = seen[pmask]
        if not t then t = {}; seen[pmask] = t end
        local key = (smask * 32 + pos) * 4 + (passes == 0 and 0 or pass)
        if t[key] then return false end
        t[key] = true
        local av = {}
        for k = 1, SLOTS do
            if not gone[k] then
                local k1 = KID1[k]
                if not k1 or (gone[k1] and gone[KID2[k]]) then av[#av + 1] = k end
            end
        end
        local w = wasteTop(pos)
        -- A King goes on its own and blocks nothing: removing it is never wrong.
        for _, k in ipairs(av) do
            if rank[k] == 13 then
                takeP(k, true)
                local r = dfs(pos, pass)
                takeP(k, false)
                return r and note{ "king", SLOT_ROW[k], SLOT_IDX[k] }
            end
        end
        if w and seq[w] == 13 then
            takeS(w, true)
            local r = dfs(pos, pass)
            takeS(w, false)
            return r and note{ "king_waste" }
        end
        for x = 1, #av do
            local a = av[x]
            for y = x + 1, #av do
                local c = av[y]
                if rank[a] + rank[c] == 13 then
                    takeP(a, true); takeP(c, true)
                    local r = dfs(pos, pass)
                    takeP(a, false); takeP(c, false)
                    if r then
                        return note{ "pair", SLOT_ROW[a], SLOT_IDX[a], SLOT_ROW[c], SLOT_IDX[c] }
                    end
                end
            end
        end
        if w then
            for _, a in ipairs(av) do
                if rank[a] + seq[w] == 13 then
                    takeP(a, true); takeS(w, true)
                    local r = dfs(pos, pass)
                    takeP(a, false); takeS(w, false)
                    if r then return note{ "pair_waste", SLOT_ROW[a], SLOT_IDX[a] } end
                end
            end
        end
        for j = pos + 1, ns do
            if not sg[j] then return dfs(j, pass) and note{ "stock" } end
        end
        if (passes == 0 or pass < passes) and wasteTop(ns) then
            return dfs(0, pass + 1) and note{ "stock" }
        end
        return false
    end

    local ok, res = pcall(dfs, pos0, pass0)
    if not ok then
        if res == "cap" then return nil end
        error(res, 0)
    end
    return res
end

local function dealOnce()
    local deck = Cards.deck()
    Cards.shuffle(deck)
    local pyramid = {}
    for r = 1, ROWS do
        local row = {}
        for i = 1, r do
            local card = table.remove(deck)
            card.up = true
            row[i] = card
        end
        pyramid[r] = row
    end
    return pyramid, deck
end

-- Builds a deal around a winning game: plays a random game on blank slots
-- and gives each slot its rank as it is removed (a King alone, or two ranks
-- adding up to 13), then the ranks left to the cards never removed, and
-- suits at random. Returns nil if the game it played got stuck.
local function buildOnce(passes)
    local left_of = {}
    for r = 1, 13 do left_of[r] = 4 end
    local prank, srank, gone, sg = {}, {}, {}, {}
    local ns = 52 - SLOTS
    for k = 1, SLOTS do gone[k] = false end
    for j = 1, ns do sg[j] = false end
    local pos, pass, left = 0, 1, SLOTS
    local function pairRank()
        local opts = {}
        for a = 1, 6 do
            if left_of[a] > 0 then opts[#opts + 1] = a end -- left_of[a] == left_of[13 - a]
        end
        if #opts == 0 then return nil end
        local a = opts[math.random(#opts)]
        if math.random(2) == 1 then a = 13 - a end
        return a
    end
    local function use(r) left_of[r] = left_of[r] - 1 end
    for _ = 1, 400 do
        if left == 0 then break end
        local av = {}
        for k = 1, SLOTS do
            if not gone[k] then
                local k1 = KID1[k]
                if not k1 or (gone[k1] and gone[KID2[k]]) then av[#av + 1] = k end
            end
        end
        local w
        for j = pos, 1, -1 do if not sg[j] then w = j; break end end
        local kinds = {}
        local pr = pairRank()
        if #av >= 2 and pr then kinds[#kinds + 1] = "pp" end
        if w and pr then kinds[#kinds + 1] = "pw" end
        if left_of[13] > 0 and (#av > 0 or w) then kinds[#kinds + 1] = "k" end
        local nextj
        for j = pos + 1, ns do if not sg[j] then nextj = j; break end end
        local canRecycle = not nextj and (passes == 0 or pass < passes) and w
        if nextj or canRecycle then kinds[#kinds + 1] = "draw" end
        if #kinds == 0 then return nil end
        local kind = kinds[math.random(#kinds)]
        if kind == "pp" then
            local x = math.random(#av)
            local y = math.random(#av - 1)
            if y >= x then y = y + 1 end
            prank[av[x]], prank[av[y]] = pr, 13 - pr
            gone[av[x]], gone[av[y]] = true, true
            use(pr); use(13 - pr)
            left = left - 2
        elseif kind == "pw" then
            local x = av[math.random(#av)]
            prank[x], srank[w] = pr, 13 - pr
            gone[x], sg[w] = true, true
            use(pr); use(13 - pr)
            left = left - 1
        elseif kind == "k" then
            use(13)
            if w and (#av == 0 or math.random(#av + 1) == 1) then
                srank[w], sg[w] = 13, true
            else
                local x = av[math.random(#av)]
                prank[x], gone[x] = 13, true
                left = left - 1
            end
        elseif nextj then
            pos = nextj
        else
            pos, pass = 0, pass + 1
        end
    end
    if left > 0 then return nil end
    -- The ranks left go to the stock cards never removed.
    local rest = {}
    for r = 1, 13 do
        for _ = 1, left_of[r] do rest[#rest + 1] = r end
    end
    Cards.shuffle(rest)
    for j = 1, ns do
        if not srank[j] then srank[j] = table.remove(rest) end
    end
    -- Suits at random.
    local suits = {}
    for r = 1, 13 do
        suits[r] = { "S", "H", "D", "C" }
        Cards.shuffle(suits[r])
    end
    local function card(r, up)
        return { rank = r, suit = table.remove(suits[r]), up = up }
    end
    local pyramid = {}
    for r = 1, ROWS do pyramid[r] = {} end
    for k = 1, SLOTS do pyramid[SLOT_ROW[k]][SLOT_IDX[k]] = card(prank[k], true) end
    local stock = {}
    for j = ns, 1, -1 do stock[#stock + 1] = card(srank[j], false) end -- draw order: top last
    return pyramid, stock
end

PyramidBoard.MAX_BUILDS = 200

-- Returns pyramid, stock; nil if every try got stuck (never seen in practice).
local function buildDeal(passes)
    for _ = 1, PyramidBoard.MAX_BUILDS do
        local pyramid, stock = buildOnce(passes)
        if pyramid then return pyramid, stock end
    end
    return nil
end
PyramidBoard._buildDeal = buildDeal

function PyramidBoard:reset(passes)
    self.passes = validPasses(passes or self.passes)
    local pyramid, deck
    if self.passes ~= 1 then
        for _ = 1, PyramidBoard.MAX_DEALS do
            local p, d = dealOnce()
            if PyramidBoard.solve(p, d, {}, 1, self.passes, PyramidBoard.SOLVE_NODES) then
                pyramid, deck = p, d
                break
            end
        end
    end
    if not pyramid then pyramid, deck = buildDeal(self.passes) end
    if not pyramid then pyramid, deck = dealOnce() end
    self.pyramid  = pyramid
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
