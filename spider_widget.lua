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
-- SpiderWidget
--
-- Top row: the stock (with the number of deals left on its back) and 8
-- slots for completed King-to-Ace runs; below, 10 columns. Spider columns
-- get long, so face-down cards only show a thin edge, and a column that
-- still runs past the bottom squeezes its face-down then face-up steps
-- (CardWidget.fanPositions) instead of growing the board.
-- ---------------------------------------------------------------------------

local SpiderWidget = CardWidget:extend{}

local COLS = 10
local GAP_RATIO  = 0.08
local DOWN_RATIO = 0.10   -- face-down step / card height
-- Nominal column: 5 face-down cards under a 13-card run plus 3 more.
local NOMINAL_DOWN = 5
local NOMINAL_UP   = 15

function SpiderWidget:layout()
    local tall_units = self.CARD_RATIO * (2 + GAP_RATIO + NOMINAL_DOWN * DOWN_RATIO
        + NOMINAL_UP * self.FAN_RATIO)
    self:setCardSize(math.min(self.max_width / COLS, self.max_height / tall_units))
    self.down_offset = math.max(5, math.floor(self.slot_h * DOWN_RATIO))
    self.tableau_gap = math.max(4, math.floor(self.slot_h * GAP_RATIO))
    self.width = self.slot_w * COLS
    self.tableau_h = NOMINAL_DOWN * self.down_offset + NOMINAL_UP * self.fan_offset + self.slot_h
    self.height = self.slot_h + self.tableau_gap + self.tableau_h
    self:makeFaces()
    self.count_face = CardWidget.fitFace("5", self.slot_w * 0.5, self.slot_h * 0.3)
end

function SpiderWidget:_columnPositions(col)
    return CardWidget.fanPositions(col, self.slot_h, self.tableau_h,
        self.down_offset, self.fan_offset, 3, math.floor(self.fan_offset * 0.5))
end

function SpiderWidget:_hitTest(lx, ly)
    if lx < 0 or ly < 0 or lx >= self.width then return nil end
    local c = math.floor(lx / self.slot_w) + 1
    if ly < self.slot_h then
        if c == 1 then return "stock" end
        return "foundation"
    end
    local ty = ly - self.slot_h - self.tableau_gap
    if ty < 0 then return nil end
    local col = self.board.tableau[c]
    if not col or #col == 0 then return "tableau", c end
    return "tableau", c, CardWidget.hitColumn(self:_columnPositions(col), ty)
end

function SpiderWidget:paintBoard(bb, x, y)
    local board = self.board
    local sw, sh = self.slot_w, self.slot_h
    local sel = board.selected

    local deals = board:dealsLeft()
    if deals > 0 then
        self:drawFaceDown(bb, x, y)
        self:drawLabel(bb, x, y + math.floor((sh - self.slot_h * 0.3) / 2), sw,
            tostring(deals), self.count_face)
    else
        self:drawEmpty(bb, x, y)
    end

    -- Completed runs, shown as their King.
    for i = 1, board.NUM_RUNS do
        local fx = x + sw * (i + 1)
        local suit = board.completed[i]
        if suit then
            self:drawFaceUp(bb, fx, y, { rank = 13, suit = suit })
        else
            self:drawEmpty(bb, fx, y)
        end
    end

    local ty0 = y + sh + self.tableau_gap
    for pile = 1, COLS do
        local col = board.tableau[pile]
        local sel_from = sel and sel.zone == "tableau" and sel.pile == pile and sel.idx or nil
        self:drawColumn(bb, x + sw * (pile - 1), ty0, col, self:_columnPositions(col), sel_from)
    end
end

return SpiderWidget
