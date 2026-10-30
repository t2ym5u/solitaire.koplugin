local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputDialog     = require("ui/widget/inputdialog")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")

local SolitaireBoardWidget = lrequire("board_widget")
local FreeCellBoard        = lrequire("freecell_board")
local FreeCellWidget       = lrequire("freecell_widget")
local SpiderWidget         = lrequire("spider_widget")
local GolfWidget           = lrequire("golf_widget")
local PyramidWidget        = lrequire("pyramid_widget")
local Rules                = lrequire("rules")
local Variants             = lrequire("variants")

-- ---------------------------------------------------------------------------
-- Variants: boards, save keys and settings live in variants.lua; here is
-- only how the screen shows and drives each one.
-- ---------------------------------------------------------------------------

local VARIANT_ORDER = Variants.ORDER

local VARIANT_NAMES = {
    klondike = _("Klondike"),
    freecell = _("FreeCell"),
    spider   = _("Spider"),
    golf     = _("Golf"),
    pyramid  = _("Pyramid"),
}

local SPIDER_SUIT_LABELS = { [1] = _("1 suit"), [2] = _("2 suits"), [4] = _("4 suits") }

local VIEWS = {
    klondike = { Widget = SolitaireBoardWidget, double_tap = true, auto_complete = true },
    freecell = { Widget = FreeCellWidget,       double_tap = true, auto_complete = true },
    spider   = { Widget = SpiderWidget,         deal_button = true },
    golf     = { Widget = GolfWidget },
    pyramid  = { Widget = PyramidWidget },
}

-- Results that leave the board as it was but deserve a word in the status.
local RESULT_MESSAGES = {
    invalid  = _("Invalid move."),
    too_many = _("Not enough free cells or empty columns to move that many cards."),
    blocked  = _("Fill every empty column before dealing a new row."),
}

-- Results after which the game changed (and counts as played).
local CHANGED = { moved = true, won = true, lost = true, drew = true, recycled = true }

-- Double-tap is off by default screen-wide (KOReader delays every single
-- tap while it waits to see if a second one follows); Klondike and FreeCell
-- opt in for double-tap-to-foundation, the other variants keep taps snappy.
local SolitaireScreen = ScreenBase:extend{ disable_double_tap = false }

function SolitaireScreen:_setting(key)
    return self.plugin:getSetting(key, Variants.SETTING_DEFAULTS[key])
end

function SolitaireScreen:init()
    self._get = function(key) return self:_setting(key) end
    local variant = self:_setting("variant")
    if not Variants.isValid(variant) then variant = "klondike" end
    self:_loadVariant(variant)
    ScreenBase.init(self)
end

-- Makes `variant` current: resumes its saved game, or deals a new one.
function SolitaireScreen:_loadVariant(variant)
    self.variant = variant
    self.V = VIEWS[variant]
    self.disable_double_tap = not self.V.double_tap
    local state = self.plugin:loadState(Variants.stateKey(variant))
    local ok
    self.board, ok = Variants.restore(variant, state, self._get)
    if ok then
        self.counted_played = state.counted_played and true or false
        self.counted_won    = state.counted_won and true or false
    else
        self.counted_played, self.counted_won = false, false
    end
end

function SolitaireScreen:serializeState()
    local data = Variants.serialize(self.variant, self.board)
    data.counted_played = self.counted_played
    data.counted_won    = self.counted_won
    return data
end

function SolitaireScreen:_save()
    self.plugin:saveState(self:serializeState(), Variants.stateKey(self.variant))
end

-- ---------------------------------------------------------------------------
-- Statistics: games started and won, per variant (Spider per suit count).
-- ---------------------------------------------------------------------------

function SolitaireScreen:_bumpStat(field)
    local stats = self.plugin:getSetting("stats", {})
    local key = Variants.statsKey(self.variant, self.board)
    local row = stats[key] or { played = 0, won = 0 }
    row[field] = (row[field] or 0) + 1
    stats[key] = row
    self.plugin:saveSetting("stats", stats)
end

-- A deal counts as played on its first move, and as won once.
function SolitaireScreen:_recordResult(result)
    if not CHANGED[result] then return end
    if not self.counted_played then
        self.counted_played = true
        self:_bumpStat("played")
    end
    if self.board.status == "won" and not self.counted_won then
        self.counted_won = true
        self:_bumpStat("won")
    end
end

function SolitaireScreen:showStatistics()
    local stats = self.plugin:getSetting("stats", {})
    local rows = {}
    local function add(key, name)
        local row = stats[key]
        if row and (row.played or 0) > 0 then
            local pct = math.floor(100 * (row.won or 0) / row.played + 0.5)
            rows[#rows + 1] = T(_("%1: %2 won of %3 played (%4%)"), name, row.won or 0, row.played, pct)
        end
    end
    for _i, id in ipairs(VARIANT_ORDER) do
        if id == "spider" then
            for _j, n in ipairs({ 1, 2, 4 }) do
                add("spider" .. n, VARIANT_NAMES.spider .. " (" .. SPIDER_SUIT_LABELS[n] .. ")")
            end
        else
            add(id, VARIANT_NAMES[id])
        end
    end
    local text = #rows > 0 and table.concat(rows, "\n") or _("No games played yet.")
    self:showMessage(text, 10)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function SolitaireScreen:_menuItems()
    local items = {
        { text = _("New game"), callback = function() self:onNewGame() end },
        { text = T(_("Game: %1"), VARIANT_NAMES[self.variant]), callback = function() self:openVariantMenu() end },
    }
    local opt = self:_optionItem()
    if opt then items[#items + 1] = opt end
    items[#items + 1] = { text = _("Statistics"), callback = function() self:showStatistics() end }
    local rules = Rules[self.variant]
    items[#items + 1] = self:makeRulesButtonConfig(rules.en, rules.fr)
    return items
end

function SolitaireScreen:_actionButtons()
    local buttons = { { text = _("Undo"), callback = function() self:onUndo() end } }
    if self.V.auto_complete then
        buttons[2] = { text = _("Auto-complete"), callback = function() self:onAutoComplete() end }
    elseif self.V.deal_button then
        buttons[2] = { text = _("Deal a row"), callback = function() self:onCellAction("stock") end }
    end
    return buttons
end

function SolitaireScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(VARIANT_NAMES[self.variant], function()
        return self:_menuItems()
    end)

    -- Undo (and Auto-complete / Deal) are used during play, so they sit
    -- under the board rather than in the menu.
    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:_actionButtons()),
    }

    -- The widget fits its cards inside both budgets.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = self.V.Widget:new{
        board        = self.board,
        max_width    = budget_w - frame_extra,
        max_height   = budget_h - frame_extra,
        onCellAction = function(zone, pile, idx) self:onCellAction(zone, pile, idx) end,
        onSendToFoundation = self.V.double_tap
            and function(zone, pile) self:onSendToFoundation(zone, pile) end or nil,
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function SolitaireScreen:_rebuild()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Play
-- ---------------------------------------------------------------------------

-- Common tail of every board action: redraw, save, count, report.
function SolitaireScreen:_afterAction(result)
    local msg = RESULT_MESSAGES[result]
    if result == "empty" and self.variant ~= "klondike" then
        msg = _("The stock is empty.")
    end
    self.board_widget:refresh()
    if result == "invalid" or result == "too_many" or result == "blocked" then
        self:updateStatus(msg)
        return
    end
    self:_recordResult(result)
    self:_save()
    self:refreshActionBar()
    self:updateStatus(msg)
    if result == "won" then
        self:showMessage(T(_("You won in %1 moves!"), self.board.moves), 4)
    end
end

function SolitaireScreen:onCellAction(zone, pile, idx)
    if self.board.status ~= "playing" then return end
    self:_afterAction(self.board:tap(zone, pile, idx))
end

function SolitaireScreen:onSendToFoundation(zone, pile)
    if self.board.status ~= "playing" or not self.board.sendTopCardToFoundation then return end
    self:_afterAction(self.board:sendTopCardToFoundation(zone, pile))
end

function SolitaireScreen:onAutoComplete()
    local moved = self.board:autoComplete()
    self.board_widget:refresh()
    if moved > 0 then self:_recordResult("moved") end
    self:_save()
    self:refreshActionBar()
    if moved == 0 then
        self:updateStatus(_("No automatic moves available."))
        return
    end
    if self.board.status == "won" then
        self:updateStatus()
        self:showMessage(T(_("You won in %1 moves!"), self.board.moves), 4)
    else
        self:updateStatus(T(_("Auto-played %1 card(s)."), moved))
    end
end

function SolitaireScreen:onUndo()
    local ok = self.board:undo()
    self.board_widget:refresh()
    self:_save()
    self:refreshActionBar()
    if ok then
        self:updateStatus(_("Last move undone."))
    else
        self:updateStatus(_("Nothing to undo."))
    end
end

function SolitaireScreen:isRoundOver()
    return self.board.status == "won" or self.board.status == "lost"
end

-- A lost Golf/Pyramid game can still be taken back.
function SolitaireScreen:getRoundOverButtons()
    local buttons = { { text = _("New game"), callback = function() self:onNewGame() end } }
    if self.board.status == "lost" then
        table.insert(buttons, 1, { text = _("Undo"), callback = function() self:onUndo() end })
    end
    return buttons
end

function SolitaireScreen:onNewGame()
    Variants.reset(self.variant, self.board, self._get)
    self.counted_played, self.counted_won = false, false
    self:_save()
    self:_rebuild()
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function SolitaireScreen:openVariantMenu()
    local items = {}
    for _i, id in ipairs(VARIANT_ORDER) do
        items[#items + 1] = { id = id, text = VARIANT_NAMES[id] }
    end
    MenuHelper.openPickerMenu{
        title      = _("Game"),
        items      = items,
        current_id = self.variant,
        parent     = self,
        on_select  = function(id) self:switchVariant(id) end,
    }
end

-- The game left keeps its save; the one picked resumes where it was.
function SolitaireScreen:switchVariant(id)
    if not Variants.isValid(id) or id == self.variant then return end
    self:_save()
    self.plugin:saveSetting("variant", id)
    self:_loadVariant(id)
    Device.input.disable_double_tap = self.disable_double_tap
    self:_rebuild()
end

-- Picks a value for a variant option, then deals a new game with it.
function SolitaireScreen:_openOptionPicker(title, key, items)
    MenuHelper.openPickerMenu{
        title      = title,
        items      = items,
        current_id = self:_setting(key),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting(key, id)
            self:onNewGame()
        end,
    }
end

-- The variant's own option in the title-bar menu, or nil.
function SolitaireScreen:_optionItem()
    local v = self.variant
    if v == "klondike" then
        return { text = self:_drawCountLabel(), callback = function()
            self:_openOptionPicker(_("Draw mode"), "draw_count", {
                { id = 1, text = _("Draw 1") },
                { id = 3, text = _("Draw 3") },
            })
        end }
    elseif v == "freecell" then
        return { text = _("Choose deal"), callback = function() self:openDealDialog() end }
    elseif v == "spider" then
        return { text = T(_("Suits: %1"), self:_setting("spider_suits")), callback = function()
            self:_openOptionPicker(_("Number of suits"), "spider_suits", {
                { id = 1, text = SPIDER_SUIT_LABELS[1] },
                { id = 2, text = SPIDER_SUIT_LABELS[2] },
                { id = 4, text = SPIDER_SUIT_LABELS[4] },
            })
        end }
    elseif v == "golf" then
        local on = self:_setting("golf_wrap")
        return { text = T(_("Wrap K–A: %1"), on and _("On") or _("Off")), callback = function()
            self:_openOptionPicker(_("Wrap K–A"), "golf_wrap", {
                { id = false, text = _("Off") },
                { id = true,  text = _("On") },
            })
        end }
    elseif v == "pyramid" then
        return { text = T(_("Passes: %1"), self:_passesLabel(self:_setting("pyramid_passes"))), callback = function()
            self:_openOptionPicker(_("Passes through the stock"), "pyramid_passes", {
                { id = 1, text = self:_passesLabel(1) },
                { id = 2, text = self:_passesLabel(2) },
                { id = 3, text = self:_passesLabel(3) },
                { id = 0, text = self:_passesLabel(0) },
            })
        end }
    end
end

function SolitaireScreen:_passesLabel(n)
    if n == 0 then return _("Unlimited") end
    return tostring(n)
end

-- The game in progress's draw count (a resumed save keeps its own).
function SolitaireScreen:_drawCountLabel()
    return T(_("Draw: %1"), self.board.draw_count or self:_setting("draw_count"))
end

function SolitaireScreen:openDealDialog()
    local dialog
    dialog = InputDialog:new{
        title      = T(_("Deal number (1–%1)"), FreeCellBoard.MAX_DEAL),
        input      = tostring(self.board.deal or ""),
        input_type = "number",
        buttons = {{
            {
                text     = _("Cancel"),
                id       = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text             = _("OK"),
                is_enter_default = true,
                callback         = function()
                    local n = tonumber(dialog:getInputText())
                    if not n or n < 1 or n > FreeCellBoard.MAX_DEAL or n ~= math.floor(n) then
                        self:showMessage(T(_("Deal number (1–%1)"), FreeCellBoard.MAX_DEAL))
                        return
                    end
                    UIManager:close(dialog)
                    self.board:reset(n)
                    self.counted_played, self.counted_won = false, false
                    self:_save()
                    self:_rebuild()
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ---------------------------------------------------------------------------
-- Status line
-- ---------------------------------------------------------------------------

function SolitaireScreen:_statusParts()
    local b, v = self.board, self.variant
    local moves = T(_("Moves: %1"), b.moves)
    if v == "klondike" then
        local f = b.foundations
        return self:_drawCountLabel(), moves, T(_("Foundations: %1/52"), f.S + f.H + f.D + f.C)
    elseif v == "freecell" then
        return T(_("Deal #%1"), b.deal), moves, T(_("Foundations: %1/52"), b:foundationCount())
    elseif v == "spider" then
        return T(_("Suits: %1"), b.suits), moves, T(_("Runs: %1/8"), #b.completed),
            T(_("Deals left: %1"), b:dealsLeft())
    elseif v == "golf" then
        return moves, T(_("Cards left: %1"), b:cardsLeft()), T(_("Stock: %1"), #b.stock)
    elseif v == "pyramid" then
        local pass = b.passes == 0 and T(_("Pass %1"), b.pass) or T(_("Pass %1/%2"), b.pass, b.passes)
        return moves, T(_("Cards left: %1"), b:cardsLeft()), pass
    end
end

function SolitaireScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.status == "won" then
        status = T(_("Solved in %1 move(s)!"), self.board.moves)
    elseif self.board.status == "lost" then
        status = self:joinStatus(_("No more moves."), T(_("Cards left: %1"), self.board:cardsLeft()))
    else
        status = self:joinStatus(self:_statusParts())
    end
    ScreenBase.updateStatus(self, status)
end

return SolitaireScreen
