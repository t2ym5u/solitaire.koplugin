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
-- GolfWidget
--
-- Top row: the stock (cards left on its back) and the waste; below, 7
-- columns of 5 face-up cards. Only the top card of a column is playable, so
-- the fan is wider than Klondike's and the card larger.
-- ---------------------------------------------------------------------------

local GolfWidget = CardWidget:extend{
    FAN_RATIO = 0.34,
}

local COLS = 7
local GAP_RATIO = 0.15

function GolfWidget:layout()
    local rows = self.board.COL_HEIGHT
    local tall_units = self.CARD_RATIO * (2 + GAP_RATIO + (rows - 1) * self.FAN_RATIO)
    self:setCardSize(math.min(self.max_width / COLS, self.max_height / tall_units))
    self.tableau_gap = math.max(6, math.floor(self.slot_h * GAP_RATIO))
    self.width = self.slot_w * COLS
    self.height = self.slot_h + self.tableau_gap + (rows - 1) * self.fan_offset + self.slot_h
    self:makeFaces()
    self.count_face = CardWidget.fitFace("16", self.slot_w * 0.6, self.slot_h * 0.3)
end

function GolfWidget:_hitTest(lx, ly)
    if lx < 0 or ly < 0 or lx >= self.width then return nil end
    local c = math.floor(lx / self.slot_w) + 1
    if ly < self.slot_h then
        if c == 1 then return "stock" end
        if c == 2 then return "waste" end
        return nil
    end
    if ly < self.slot_h + self.tableau_gap then return nil end
    -- Any tap on a column plays its top card.
    return "tableau", c
end

function GolfWidget:paintBoard(bb, x, y)
    local board = self.board
    local sw, sh = self.slot_w, self.slot_h

    if #board.stock > 0 then
        self:drawFaceDown(bb, x, y)
        self:drawLabel(bb, x, y + math.floor((sh - sh * 0.3) / 2), sw,
            tostring(#board.stock), self.count_face)
    else
        self:drawEmpty(bb, x, y)
    end
    local wtop = board.waste[#board.waste]
    if wtop then
        self:drawFaceUp(bb, x + sw, y, wtop)
    else
        self:drawEmpty(bb, x + sw, y)
    end

    local ty0 = y + sh + self.tableau_gap
    for pile = 1, COLS do
        local col = board.tableau[pile]
        local px = x + sw * (pile - 1)
        if #col == 0 then
            self:drawEmpty(bb, px, ty0)
        else
            for i, card in ipairs(col) do
                -- Buried cards are greyed: only the top one can be played.
                self:drawFaceUp(bb, px, ty0 + (i - 1) * self.fan_offset, card, false, i < #col)
            end
        end
    end
end

return GolfWidget
