local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

-- ---------------------------------------------------------------------------
-- CardWidget -- shared base of every variant's board widget.
--
-- Holds the card drawing (face up, face down, empty slot), the font fitting,
-- the tap/double-tap plumbing and the column fanning maths. A subclass
-- implements:
--   :layout()            set self.width / self.height and card geometry
--                        (call self:setCardSize() and self:makeFaces())
--   :_hitTest(lx, ly)    local coordinates -> zone, pile, idx (or nil)
--   :paintBoard(bb, x, y)
-- ---------------------------------------------------------------------------

local C_BG       = Blitbuffer.COLOR_WHITE
local C_BORDER   = Blitbuffer.COLOR_BLACK
local C_BACK     = Blitbuffer.COLOR_GRAY_5
local C_EMPTY    = Blitbuffer.COLOR_GRAY_E
local C_RED      = Blitbuffer.COLOR_GRAY_3   -- e-ink: no real red; a darker gray backs up the hollow-glyph shape cue below
local C_BLACK    = Blitbuffer.COLOR_BLACK
-- A selected card gets a thick black outline: a light-grey one read as
-- thinner than the plain 1px black edge of every other card.
local C_SELECTED = Blitbuffer.COLOR_BLACK
-- Cards that cannot be played right now (Pyramid's covered cards) are
-- greyed out so the playable ones stand out.
local C_DIMMED   = Blitbuffer.COLOR_GRAY_9

local RANK_LABELS = { [1]="A", [11]="J", [12]="Q", [13]="K" }
-- Red suits use hollow glyphs (♡♢) vs black suits' filled ones (♠♣): a
-- shape-based cue that works even where the gray-shade difference doesn't
-- read well on e-ink.
local SUIT_GLYPHS = { S = "♠", H = "♡", D = "♢", C = "♣" }
local RED_SUITS   = { H = true, D = true }

local function rankLabel(rank)
    return RANK_LABELS[rank] or tostring(rank)
end

local CardWidget = InputContainer:extend{
    board              = nil,
    onCellAction       = nil,
    onSendToFoundation = nil,   -- nil: double-tap does nothing
    max_width          = 300,
    max_height         = 400,
}

CardWidget.SUIT_GLYPHS = SUIT_GLYPHS
CardWidget.SUIT_ORDER  = { "S", "H", "D", "C" }
CardWidget.CARD_RATIO  = 1.35   -- card height / width
CardWidget.FAN_RATIO   = 0.28   -- fanned face-up card offset / card height

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (with a width limit sizeUtf8Text truncates, so a width test against it can
-- never fail); ink height is y_top + y_bottom. Measuring keeps the cards'
-- labels the same size on every DPI, where a size scaled off the slot width
-- was scaled a second time by Font:getFace().
function CardWidget.fitFace(sample, max_w, max_h)
    local screen_w = Device.screen:getWidth()
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

function CardWidget:init()
    self:layout()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    -- Ranges follow the painted board: an unbounded range swallowed taps
    -- meant for the buttons under the board.
    self.ges_events = {
        Tap = {
            GestureRange:new{ ges = "tap", range = function() return self.paint_rect end },
        },
    }
    if self.onSendToFoundation then
        self.ges_events.DoubleTap = {
            GestureRange:new{ ges = "double_tap", range = function() return self.paint_rect end },
        }
    end
end

-- Card size from a width: height follows CARD_RATIO, the fan offset
-- FAN_RATIO (never under 14 px, below which a corner label is unreadable).
function CardWidget:setCardSize(slot_w)
    self.slot_w = math.max(10, math.floor(slot_w))
    self.slot_h = math.floor(self.slot_w * self.CARD_RATIO)
    self.fan_offset = math.max(14, math.floor(self.slot_h * self.FAN_RATIO))
end

-- Corner label (rank + suit) sits in the strip left visible by the fanned
-- card below, so it has to fit `strip_h`; the centred suit glyph is the
-- largest size used on a card. The label never grows past what Klondike's
-- fan allows, so it reads the same in every variant and "10" keeps clear
-- of the suit glyph beside it.
function CardWidget:makeFaces(strip_h)
    strip_h = math.min(strip_h or self.fan_offset, math.max(14, self.slot_h * 0.28))
    self.rank_face = CardWidget.fitFace("10", self.slot_w * 0.45, strip_h * 0.7)
    self.suit_face = CardWidget.fitFace("\xE2\x99\xA3", self.slot_w * 0.5, self.slot_h * 0.36)
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

function CardWidget:_local(ges)
    local rect = self.paint_rect
    return ges.pos.x - rect.x, ges.pos.y - rect.y
end

function CardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local zone, pile, idx = self:_hitTest(self:_local(ges))
    if zone and self.onCellAction then
        self.onCellAction(zone, pile, idx)
    end
    return true
end

-- Double-tapping a card sends it straight to its foundation if legal,
-- skipping the usual select-then-tap-destination flow.
function CardWidget:onDoubleTap(_, ges)
    if not (ges and ges.pos) then return false end
    local zone, pile = self:_hitTest(self:_local(ges))
    if zone and zone ~= "stock" and zone ~= "foundation" and self.onSendToFoundation then
        self.onSendToFoundation(zone, pile)
    end
    return true
end

function CardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

function CardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, C_BG)
    self:paintBoard(bb, x, y)
end

-- ---------------------------------------------------------------------------
-- Column fanning
--
-- Returns the top-edge offsets of every card of `col`, relative to the
-- column's top. Face-down cards step by `down_off`, face-up ones by
-- `up_off`. When the column would run past `avail_h`, face-down steps
-- shrink first (down to `min_down`), then face-up steps (down to
-- `min_up`), so a long Spider column stays on the board.
-- ---------------------------------------------------------------------------

function CardWidget.fanPositions(col, slot_h, avail_h, down_off, up_off, min_down, min_up)
    local n_down, n_up = 0, 0
    for i = 1, #col - 1 do
        if col[i].up then n_up = n_up + 1 else n_down = n_down + 1 end
    end
    local room = avail_h - slot_h
    if n_down * down_off + n_up * up_off > room then
        if n_down > 0 then
            local d = math.floor((room - n_up * up_off) / n_down)
            down_off = math.max(min_down, math.min(down_off, d))
        end
        if n_down * down_off + n_up * up_off > room and n_up > 0 then
            local u = math.floor((room - n_down * down_off) / n_up)
            up_off = math.max(min_up, math.min(up_off, u))
        end
    end
    local pos, y = {}, 0
    for i = 1, #col do
        pos[i] = y
        y = y + (col[i].up and up_off or down_off)
    end
    return pos
end

-- Card index under a tap at `ty` (relative to the column top), given the
-- positions from fanPositions(); taps below the last card pick the top card.
function CardWidget.hitColumn(pos, ty)
    local idx = 1
    for i = 1, #pos do
        if pos[i] <= ty then idx = i else break end
    end
    return idx
end

-- ---------------------------------------------------------------------------
-- Card drawing
-- ---------------------------------------------------------------------------

local function drawSlotFrame(bb, x, y, w, h, selected)
    local border = selected and C_SELECTED or C_BORDER
    local bw = selected and math.max(3, math.floor(w * 0.04)) or 1
    bb:paintRect(x, y, w, bw, border)
    bb:paintRect(x, y + h - bw, w, bw, border)
    bb:paintRect(x, y, bw, h, border)
    bb:paintRect(x + w - bw, y, bw, h, border)
end

-- selected: thick outline. dimmed: grey ink for a card that cannot be
-- played (it is then also partly covered, so its centre glyph is skipped:
-- only a sliver of it would show).
function CardWidget:drawFaceUp(bb, x, y, card, selected, dimmed)
    local w, h = self.slot_w, self.slot_h
    local face_rank, face_suit = self.rank_face, self.suit_face
    bb:paintRect(x, y, w, h, C_BG)
    drawSlotFrame(bb, x, y, w, h, selected)
    local color = RED_SUITS[card.suit] and C_RED or C_BLACK
    if dimmed then color = C_DIMMED end
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
    if dimmed then return end
    local m2 = RenderText:sizeUtf8Text(0, w, face_suit, suit_text, true, false)
    local sx = x + math.floor((w - m2.x) / 2)
    local sy = y + math.floor(h / 2) - math.floor((m2.y_top + m2.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, sx, sy + m2.y_top, face_suit, suit_text, true, false, color)
end

function CardWidget:drawFaceDown(bb, x, y)
    bb:paintRect(x, y, self.slot_w, self.slot_h, C_BACK)
    drawSlotFrame(bb, x, y, self.slot_w, self.slot_h, false)
end

-- An empty slot with an optional centred label (suit glyph, "↺"...).
function CardWidget:drawEmpty(bb, x, y, label, selected, face)
    local w, h = self.slot_w, self.slot_h
    face = face or self.suit_face
    bb:paintRect(x, y, w, h, C_EMPTY)
    drawSlotFrame(bb, x, y, w, h, selected)
    if label then
        local m = RenderText:sizeUtf8Text(0, w, face, label, true, false)
        local tx = x + math.floor((w - m.x) / 2)
        local ty = y + math.floor((h - (m.y_top + m.y_bottom)) / 2)
        RenderText:renderUtf8Text(bb, tx, ty + m.y_top, face, label, true, false, C_BORDER)
    end
end

-- Small centred text under/over a slot (stock counts...).
function CardWidget:drawLabel(bb, x, y, w, text, face)
    local m = RenderText:sizeUtf8Text(0, w, face, text, true, false)
    RenderText:renderUtf8Text(bb, x + math.floor((w - m.x) / 2), y + m.y_top,
        face, text, true, false, C_BLACK)
end

-- Draws a fanned column at (x, y) using fanPositions() output; cards from
-- index `sel_from` up get the selection outline.
function CardWidget:drawColumn(bb, x, y, col, pos, sel_from)
    if #col == 0 then
        self:drawEmpty(bb, x, y, nil, false)
        return
    end
    for i, card in ipairs(col) do
        local cy = y + pos[i]
        if card.up then
            self:drawFaceUp(bb, x, cy, card, sel_from ~= nil and i >= sel_from)
        else
            self:drawFaceDown(bb, x, cy)
        end
    end
end

return CardWidget
