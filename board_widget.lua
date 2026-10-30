local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local CardWidget = lrequire("card_widget")

-- ---------------------------------------------------------------------------
-- SolitaireBoardWidget (Klondike)
--
-- Layout: a top row of 6 slots (stock, waste, gap, foundation x4) followed
-- by 7 fanned tableau columns below. All input is tap-based; hit-testing is
-- done directly against this geometry rather than via a uniform grid (see
-- GridWidgetBase), since tableau piles have variable, overlapping heights.
-- Card drawing and gestures live in card_widget.lua, shared with the other
-- variants.
-- ---------------------------------------------------------------------------

local SolitaireBoardWidget = CardWidget:extend{}

-- A tableau column is sized for a full King-to-Ace run; a longer one (face-
-- down cards under a 13-card run) gets its face-down cards squeezed.
local MAX_COLUMN_CARDS = 13
local GAP_RATIO = 0.08   -- top row to tableau gap / card height

function SolitaireBoardWidget:layout()
    -- The board is 7 cards wide and, at worst, the top row plus a 13-card
    -- tableau column tall. Size the card to fit both budgets, so the tallest
    -- column never runs past our bottom edge into the controls below.
    local tall_units = self.CARD_RATIO * (2 + GAP_RATIO + (MAX_COLUMN_CARDS - 1) * self.FAN_RATIO)
    self:setCardSize(math.min(self.max_width / 7, self.max_height / tall_units))
    self.tableau_gap = math.max(4, math.floor(self.slot_h * GAP_RATIO))

    self.width  = self.slot_w * 7
    self.tableau_h = (MAX_COLUMN_CARDS - 1) * self.fan_offset + self.slot_h
    self.height = self.slot_h + self.tableau_gap + self.tableau_h
    self:makeFaces()
end

function SolitaireBoardWidget:_columnPositions(col)
    local f = self.fan_offset
    return CardWidget.fanPositions(col, self.slot_h, self.tableau_h, f, f,
        math.floor(f / 3), math.floor(f / 2))
end

-- Returns zone, pile, idx for a tap at local coordinates (lx, ly), or nil.
function SolitaireBoardWidget:_hitTest(lx, ly)
    if lx < 0 or ly < 0 or lx >= self.width then return nil end

    if ly < self.slot_h then
        local col = math.floor(lx / self.slot_w)
        if col == 0 then return "stock" end
        if col == 1 then return "waste" end
        if col >= 3 and col <= 6 then
            return "foundation", self.SUIT_ORDER[col - 2]
        end
        return nil
    end

    local ty = ly - self.slot_h - self.tableau_gap
    if ty < 0 then return nil end
    local pile = math.floor(lx / self.slot_w) + 1
    if pile < 1 or pile > 7 then return nil end
    local col = self.board.tableau[pile]
    if not col or #col == 0 then return "tableau", pile end
    return "tableau", pile, CardWidget.hitColumn(self:_columnPositions(col), ty)
end

function SolitaireBoardWidget:paintBoard(bb, x, y)
    local board = self.board
    local sw, sh = self.slot_w, self.slot_h
    local sel = board.selected

    -- Stock
    if #board.stock > 0 then
        self:drawFaceDown(bb, x, y)
    else
        self:drawEmpty(bb, x, y, "↺")
    end

    -- Waste (shows the top card only)
    local wtop = board.waste[#board.waste]
    if wtop then
        self:drawFaceUp(bb, x + sw, y, wtop, sel and sel.zone == "waste")
    else
        self:drawEmpty(bb, x + sw, y)
    end

    -- Foundations (columns 3..6)
    for i, suit in ipairs(self.SUIT_ORDER) do
        local fx = x + sw * (i + 2)
        local n = board.foundations[suit]
        if n > 0 then
            self:drawFaceUp(bb, fx, y, { rank = n, suit = suit })
        else
            self:drawEmpty(bb, fx, y, self.SUIT_GLYPHS[suit])
        end
    end

    -- Tableau
    local ty0 = y + sh + self.tableau_gap
    for pile = 1, 7 do
        local col = board.tableau[pile]
        local sel_from = sel and sel.zone == "tableau" and sel.pile == pile and sel.idx or nil
        self:drawColumn(bb, x + sw * (pile - 1), ty0, col, self:_columnPositions(col), sel_from)
    end
end

return SolitaireBoardWidget
