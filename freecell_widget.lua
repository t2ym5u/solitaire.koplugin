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
-- FreeCellWidget
--
-- Top row: 4 free cells (left) and 4 foundations (right); below, 8 fanned
-- face-up columns. Columns are sized for 16 cards and squeeze their fan
-- beyond that, which covers every column a real game produces (7 dealt plus
-- a 12-card run built on top).
-- ---------------------------------------------------------------------------

local FreeCellWidget = CardWidget:extend{}

local COLS = 8
local NOMINAL_CARDS = 16
local GAP_RATIO = 0.08

function FreeCellWidget:layout()
    local tall_units = self.CARD_RATIO * (2 + GAP_RATIO + (NOMINAL_CARDS - 1) * self.FAN_RATIO)
    self:setCardSize(math.min(self.max_width / COLS, self.max_height / tall_units))
    self.tableau_gap = math.max(4, math.floor(self.slot_h * GAP_RATIO))
    self.width = self.slot_w * COLS
    self.tableau_h = (NOMINAL_CARDS - 1) * self.fan_offset + self.slot_h
    self.height = self.slot_h + self.tableau_gap + self.tableau_h
    self:makeFaces()
end

function FreeCellWidget:_columnPositions(col)
    local f = self.fan_offset
    return CardWidget.fanPositions(col, self.slot_h, self.tableau_h, f, f, f, math.floor(f * 0.6))
end

function FreeCellWidget:_hitTest(lx, ly)
    if lx < 0 or ly < 0 or lx >= self.width then return nil end
    local c = math.floor(lx / self.slot_w) + 1
    if ly < self.slot_h then
        if c <= 4 then return "cell", c end
        return "foundation", self.SUIT_ORDER[c - 4]
    end
    local ty = ly - self.slot_h - self.tableau_gap
    if ty < 0 then return nil end
    local col = self.board.tableau[c]
    if not col or #col == 0 then return "tableau", c end
    return "tableau", c, CardWidget.hitColumn(self:_columnPositions(col), ty)
end

function FreeCellWidget:paintBoard(bb, x, y)
    local board = self.board
    local sw, sh = self.slot_w, self.slot_h
    local sel = board.selected

    for i = 1, 4 do
        local card = board.cells[i]
        local cx = x + sw * (i - 1)
        if card then
            self:drawFaceUp(bb, cx, y, card, sel and sel.zone == "cell" and sel.pile == i)
        else
            self:drawEmpty(bb, cx, y)
        end
    end
    for i, suit in ipairs(self.SUIT_ORDER) do
        local fx = x + sw * (i + 3)
        local n = board.foundations[suit]
        if n > 0 then
            self:drawFaceUp(bb, fx, y, { rank = n, suit = suit })
        else
            self:drawEmpty(bb, fx, y, self.SUIT_GLYPHS[suit])
        end
    end

    local ty0 = y + sh + self.tableau_gap
    for pile = 1, COLS do
        local col = board.tableau[pile]
        local sel_from = sel and sel.zone == "tableau" and sel.pile == pile and sel.idx or nil
        self:drawColumn(bb, x + sw * (pile - 1), ty0, col, self:_columnPositions(col), sel_from)
    end
end

return FreeCellWidget
