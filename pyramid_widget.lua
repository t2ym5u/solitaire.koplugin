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
-- PyramidWidget
--
-- Top row: stock and waste; below, the 7-row pyramid. Each row overlaps the
-- one above by half a card, which leaves the covered cards' corner labels
-- readable. Covered cards are greyed out so the playable ones stand out.
-- ---------------------------------------------------------------------------

local PyramidWidget = CardWidget:extend{}

local COLS = 7
local GAP_RATIO = 0.15
local ROW_RATIO = 0.5   -- vertical step between pyramid rows / card height

function PyramidWidget:layout()
    local rows = self.board.ROWS
    local tall_units = self.CARD_RATIO * (2 + GAP_RATIO + (rows - 1) * ROW_RATIO)
    self:setCardSize(math.min(self.max_width / COLS, self.max_height / tall_units))
    self.row_offset = math.floor(self.slot_h * ROW_RATIO)
    self.tableau_gap = math.max(6, math.floor(self.slot_h * GAP_RATIO))
    self.width = self.slot_w * COLS
    self.height = self.slot_h + self.tableau_gap + (rows - 1) * self.row_offset + self.slot_h
    self:makeFaces(self.row_offset)
    self.count_face = CardWidget.fitFace("24", self.slot_w * 0.6, self.slot_h * 0.3)
end

-- Local top-left corner of pyramid card (r, i).
function PyramidWidget:_cardPos(r, i)
    local px = math.floor((COLS - r) * self.slot_w / 2) + (i - 1) * self.slot_w
    local py = self.slot_h + self.tableau_gap + (r - 1) * self.row_offset
    return px, py
end

function PyramidWidget:_hitTest(lx, ly)
    if lx < 0 or ly < 0 or lx >= self.width then return nil end
    if ly < self.slot_h then
        local c = math.floor(lx / self.slot_w) + 1
        if c == 1 then return "stock" end
        if c == 2 then return "waste" end
        return nil
    end
    -- Lower rows are drawn over upper ones: test them first.
    local pyr = self.board.pyramid
    for r = self.board.ROWS, 1, -1 do
        for i = 1, r do
            if pyr[r][i] then
                local px, py = self:_cardPos(r, i)
                if lx >= px and lx < px + self.slot_w and ly >= py and ly < py + self.slot_h then
                    return "pyramid", r, i
                end
            end
        end
    end
    return nil
end

function PyramidWidget:paintBoard(bb, x, y)
    local board = self.board
    local sw, sh = self.slot_w, self.slot_h
    local sel = board.selected

    if #board.stock > 0 then
        self:drawFaceDown(bb, x, y)
        self:drawLabel(bb, x, y + math.floor((sh - sh * 0.3) / 2), sw,
            tostring(#board.stock), self.count_face)
    else
        self:drawEmpty(bb, x, y, board:canRecycle() and "↺" or nil)
    end
    local wtop = board.waste[#board.waste]
    if wtop then
        self:drawFaceUp(bb, x + sw, y, wtop, sel and sel.zone == "waste")
    else
        self:drawEmpty(bb, x + sw, y)
    end

    for r = 1, board.ROWS do
        for i = 1, r do
            local card = board.pyramid[r][i]
            if card then
                local px, py = self:_cardPos(r, i)
                local is_sel = sel and sel.zone == "pyramid" and sel.pile == r and sel.idx == i
                self:drawFaceUp(bb, x + px, y + py, card, is_sel, not board:isExposed(r, i))
            end
        end
    end
end

return PyramidWidget
