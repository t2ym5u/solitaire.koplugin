local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG       = Blitbuffer.COLOR_WHITE
local C_BORDER   = Blitbuffer.COLOR_BLACK
local C_BACK     = Blitbuffer.COLOR_GRAY_5
local C_EMPTY    = Blitbuffer.COLOR_GRAY_E
local C_RED      = Blitbuffer.COLOR_GRAY_3   -- e-ink: no real red; a darker gray backs up the hollow-glyph shape cue below
local C_BLACK    = Blitbuffer.COLOR_BLACK
-- A selected card gets a thick black outline: a light-grey one read as
-- thinner than the plain 1px black edge of every other card.
local C_SELECTED = Blitbuffer.COLOR_BLACK

local RANK_LABELS = { [1]="A", [11]="J", [12]="Q", [13]="K" }
-- Red suits use hollow glyphs (♡♢) vs black suits' filled ones (♠♣): a
-- shape-based cue that works even where the gray-shade difference doesn't
-- read well on e-ink.
local SUIT_GLYPHS = { S = "♠", H = "♡", D = "♢", C = "♣" }
local RED_SUITS   = { H = true, D = true }

local function rankLabel(rank)
    return RANK_LABELS[rank] or tostring(rank)
end

-- ---------------------------------------------------------------------------
-- SolitaireBoardWidget
--
-- Layout: a top row of 6 slots (stock, waste, gap, foundation x4) followed
-- by 7 fanned tableau columns below. All input is tap-based; hit-testing is
-- done directly against this geometry rather than via a uniform grid (see
-- GridWidgetBase), since tableau piles have variable, overlapping heights.
-- ---------------------------------------------------------------------------

local SolitaireBoardWidget = InputContainer:extend{
    board        = nil,
    onCellAction = nil,
    max_width    = 300,
    max_height   = 400,
}

-- A tableau column can hold at most a full King-to-Ace run.
local MAX_COLUMN_CARDS = 13

-- Card geometry as multiples of the slot (card) width.
local CARD_RATIO = 1.35   -- card height / width
local GAP_RATIO  = 0.08   -- top row to tableau gap / card height
local FAN_RATIO  = 0.28   -- fanned card offset / card height

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (with a width limit sizeUtf8Text truncates, so a width test against it can
-- never fail); ink height is y_top + y_bottom. Measuring keeps the cards'
-- labels the same size on every DPI, where a size scaled off the slot width
-- was scaled a second time by Font:getFace().
local function fitFace(sample, max_w, max_h, screen_w)
    local lo, hi, best = 6, math.max(6, math.floor(max_h)), 6
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m   = RenderText:sizeUtf8Text(0, screen_w, Font:getFace("cfont", mid), sample, true, false)
        if m.x <= max_w and (m.y_top + m.y_bottom) <= max_h then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    return Font:getFace("cfont", best)
end

function SolitaireBoardWidget:init()
    -- The board is 7 cards wide and, at worst, the top row plus a 13-card
    -- tableau column tall. Size the card to fit both budgets, so the tallest
    -- column never runs past our bottom edge into the controls below.
    local tall_units = CARD_RATIO * (2 + GAP_RATIO + (MAX_COLUMN_CARDS - 1) * FAN_RATIO)
    self.slot_w = math.max(10, math.floor(math.min(self.max_width / 7, self.max_height / tall_units)))
    self.slot_h = math.floor(self.slot_w * CARD_RATIO)
    self.tableau_gap = math.max(4, math.floor(self.slot_h * GAP_RATIO))
    -- Vertical distance between fanned tableau cards' top edges.
    self.fan_offset = math.max(14, math.floor(self.slot_h * FAN_RATIO))

    self.width  = self.slot_w * 7
    self.height = self.slot_h + self.tableau_gap
        + (MAX_COLUMN_CARDS - 1) * self.fan_offset + self.slot_h

    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    local screen_w = Device.screen:getWidth()
    -- Corner label (rank + suit) sits in the strip left visible by the
    -- fanned card below, so it has to fit the fan offset; right-aligned suit
    -- so it doesn't crowd two-digit ranks (e.g. "10").
    self.rank_face = fitFace("10", self.slot_w * 0.45, self.fan_offset * 0.7, screen_w)
    -- Centered suit glyph: the largest size used on a card, kept consistent
    -- across the stock/waste/foundation row and the tableau.
    self.suit_face = fitFace("\xE2\x99\xA3", self.slot_w * 0.5, self.slot_h * 0.36, screen_w)

    -- Ranges follow the painted board: an unbounded range swallowed taps
    -- meant for the buttons under the board.
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            },
        },
        DoubleTap = {
            GestureRange:new{
                ges   = "double_tap",
                range = function() return self.paint_rect end,
            },
        },
    }
end

-- Returns zone, pile, idx for a tap at local coordinates (lx, ly), or nil.
function SolitaireBoardWidget:_hitTest(lx, ly)
    if lx < 0 or ly < 0 or lx >= self.width then return nil end

    if ly < self.slot_h then
        local col = math.floor(lx / self.slot_w)
        if col == 0 then return "stock" end
        if col == 1 then return "waste" end
        if col >= 3 and col <= 6 then
            return "foundation", SolitaireBoardWidget.SUIT_ORDER[col - 2]
        end
        return nil
    end

    local ty = ly - self.slot_h - self.tableau_gap
    if ty < 0 then return nil end
    local pile = math.floor(lx / self.slot_w) + 1
    if pile < 1 or pile > 7 then return nil end
    local col = self.board.tableau[pile]
    if not col or #col == 0 then return "tableau", pile end
    local idx = math.floor(ty / self.fan_offset) + 1
    idx = math.min(idx, #col)
    return "tableau", pile, idx
end

SolitaireBoardWidget.SUIT_ORDER = { "S", "H", "D", "C" }

function SolitaireBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local rect = self.paint_rect
    local lx = ges.pos.x - rect.x
    local ly = ges.pos.y - rect.y
    local zone, pile, idx = self:_hitTest(lx, ly)
    if zone and self.onCellAction then
        self.onCellAction(zone, pile, idx)
    end
    return true
end

-- Double-tapping a waste or tableau card sends it straight to its
-- foundation (top-right slots) if the move is legal, skipping the usual
-- select-then-tap-destination flow.
function SolitaireBoardWidget:onDoubleTap(_, ges)
    if not (ges and ges.pos) then return false end
    local rect = self.paint_rect
    local lx = ges.pos.x - rect.x
    local ly = ges.pos.y - rect.y
    local zone, pile = self:_hitTest(lx, ly)
    if (zone == "waste" or zone == "tableau") and self.onSendToFoundation then
        self.onSendToFoundation(zone, pile)
    end
    return true
end

function SolitaireBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function drawSlotFrame(bb, x, y, w, h, selected)
    local border = selected and C_SELECTED or C_BORDER
    local bw = selected and math.max(3, math.floor(w * 0.04)) or 1
    bb:paintRect(x, y, w, bw, border)
    bb:paintRect(x, y + h - bw, w, bw, border)
    bb:paintRect(x, y, bw, h, border)
    bb:paintRect(x + w - bw, y, bw, h, border)
end

local function drawFaceUpCard(bb, x, y, w, h, card, face_rank, face_suit, selected)
    bb:paintRect(x, y, w, h, C_BG)
    drawSlotFrame(bb, x, y, w, h, selected)
    local color = RED_SUITS[card.suit] and C_RED or C_BLACK
    local suit_text = SUIT_GLYPHS[card.suit] or "?"

    -- Corner labels sit in the strip that stays visible even when this card
    -- is mostly covered by the one fanned below it in the tableau -- the big
    -- centered suit glyph below would be hidden then. Rank sits left, suit
    -- sits right, so neither crowds the other for two-digit ranks ("10").
    local rank_text = rankLabel(card.rank)
    local pad = math.floor(w * 0.08)
    local corner_y = y + math.floor(h * 0.05)

    local m1r = RenderText:sizeUtf8Text(0, w, face_rank, rank_text, true, false)
    RenderText:renderUtf8Text(bb, x + pad, corner_y + math.abs(m1r.y_top),
        face_rank, rank_text, true, false, color)

    local m1s = RenderText:sizeUtf8Text(0, w, face_rank, suit_text, true, false)
    RenderText:renderUtf8Text(bb, x + w - m1s.x - pad, corner_y + math.abs(m1s.y_top),
        face_rank, suit_text, true, false, color)

    -- Large centered suit glyph, seen on fully visible cards (top of pile,
    -- waste, foundation).
    local m2 = RenderText:sizeUtf8Text(0, w, face_suit, suit_text, true, false)
    local sx = x + math.floor((w - m2.x) / 2)
    local sy = y + math.floor(h / 2) - math.floor((m2.y_top + m2.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, sx, sy + m2.y_top, face_suit, suit_text, true, false, color)
end

local function drawFaceDownCard(bb, x, y, w, h)
    bb:paintRect(x, y, w, h, C_BACK)
    drawSlotFrame(bb, x, y, w, h, false)
end

local function drawEmptySlot(bb, x, y, w, h, label, face, selected)
    bb:paintRect(x, y, w, h, C_EMPTY)
    drawSlotFrame(bb, x, y, w, h, selected)
    if label then
        local m = RenderText:sizeUtf8Text(0, w, face, label, true, false)
        local tx = x + math.floor((w - m.x) / 2)
        local ty = y + math.floor((h - (m.y_top + m.y_bottom)) / 2)
        RenderText:renderUtf8Text(bb, tx, ty + m.y_top, face, label, true, false, C_BORDER)
    end
end

function SolitaireBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, C_BG)

    local board = self.board
    local sw, sh = self.slot_w, self.slot_h
    local sel = board.selected

    -- Stock
    if #board.stock > 0 then
        drawFaceDownCard(bb, x, y, sw, sh)
    else
        drawEmptySlot(bb, x, y, sw, sh, "↺", self.suit_face, false)
    end

    -- Waste (shows the top card only)
    local wtop = board.waste[#board.waste]
    if wtop then
        local is_sel = sel and sel.zone == "waste"
        drawFaceUpCard(bb, x + sw, y, sw, sh, wtop, self.rank_face, self.suit_face, is_sel)
    else
        drawEmptySlot(bb, x + sw, y, sw, sh, nil, self.suit_face, false)
    end

    -- Foundations (columns 3..6)
    for i, suit in ipairs(SolitaireBoardWidget.SUIT_ORDER) do
        local fx = x + sw * (i + 2)
        local n = board.foundations[suit]
        if n > 0 then
            drawFaceUpCard(bb, fx, y, sw, sh, { rank = n, suit = suit }, self.rank_face, self.suit_face, false)
        else
            drawEmptySlot(bb, fx, y, sw, sh, SUIT_GLYPHS[suit], self.suit_face, false)
        end
    end

    -- Tableau
    local ty0 = y + sh + self.tableau_gap
    for pile = 1, 7 do
        local col = board.tableau[pile]
        local px = x + sw * (pile - 1)
        if #col == 0 then
            drawEmptySlot(bb, px, ty0, sw, sh, nil, self.suit_face, false)
        else
            for i, card in ipairs(col) do
                local cy = ty0 + (i - 1) * self.fan_offset
                local is_sel = sel and sel.zone == "tableau" and sel.pile == pile and i >= sel.idx
                if card.up then
                    drawFaceUpCard(bb, px, cy, sw, sh, card, self.rank_face, self.suit_face, is_sel)
                else
                    drawFaceDownCard(bb, px, cy, sw, sh)
                end
            end
        end
    end
end

return SolitaireBoardWidget
