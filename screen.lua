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
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")

local SolitaireBoard       = lrequire("board")
local SolitaireBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Klondike Solitaire — Rules

Move all 52 cards to the 4 foundations, one suit each, built up from Ace to King.

Tableau piles: build down in alternating colors (e.g. red 8 on black 9). A face-down card is revealed when it becomes the top of its pile. Only a King (or a run starting with one) can be placed on an empty tableau pile.

Foundations: build up in the same suit, starting from the Ace.

Tap a card to select it, then tap a destination pile or foundation to move it there. Tap the stock pile to draw new cards (or recycle the waste once the stock is empty). Double-tap a card to send it straight to its foundation.

Undo takes back the last move; Auto-complete plays every card that can go to a foundation.
]])

local GAME_RULES_FR = [[
Solitaire Klondike — Règles

Déplacez les 52 cartes vers les 4 fondations, une par couleur, de l'As au Roi.

Colonnes : construisez en alternant les couleurs (ex. un 8 rouge sur un 9 noir). Une carte face cachée est révélée quand elle devient le sommet de sa colonne. Seul un Roi (ou une suite commençant par un Roi) peut être posé sur une colonne vide.

Fondations : construisez dans la même couleur, en partant de l'As.

Touchez une carte pour la sélectionner, puis touchez une colonne ou une fondation de destination. Touchez la pioche pour tirer de nouvelles cartes (ou recycler la défausse une fois la pioche vide). Touchez deux fois une carte pour l'envoyer directement sur sa fondation.

Annuler reprend le dernier coup ; Terminer automatiquement joue toutes les cartes qui peuvent aller sur une fondation.
]]

-- Double-tap is off by default screen-wide (KOReader delays every single
-- tap while it waits to see if a second one follows); opt in here since
-- double-tap-to-foundation is a deliberate feature of this game.
local SolitaireScreen = ScreenBase:extend{ disable_double_tap = false }

local RESULT_MESSAGES = {
    invalid = _("Invalid move."),
}

function SolitaireScreen:init()
    local state      = self.plugin:loadState()
    local draw_count = self.plugin:getSetting("draw_count", 1)
    self.board = SolitaireBoard:new{ draw_count = draw_count }
    if not self.board:load(state) then
        self.board:reset(draw_count)
    end
    ScreenBase.init(self)
end

function SolitaireScreen:serializeState()
    return self.board:serialize()
end

function SolitaireScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Solitaire"), function()
        return {
            { text = _("New game"),          callback = function() self:onNewGame() end },
            { text = self:_drawCountLabel(), callback = function() self:openDrawCountMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Undo and Auto-complete are used during play, so they sit under the
    -- board rather than in the menu.
    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Undo"),          callback = function() self:onUndo() end },
            { text = _("Auto-complete"), callback = function() self:onAutoComplete() end },
        }),
    }

    -- The board is taller than wide (room for a full 13-card column), so the
    -- widget fits its cards inside both budgets.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = SolitaireBoardWidget:new{
        board        = self.board,
        max_width    = budget_w - frame_extra,
        max_height   = budget_h - frame_extra,
        onCellAction = function(zone, pile, idx) self:onCellAction(zone, pile, idx) end,
        onSendToFoundation = function(zone, pile) self:onSendToFoundation(zone, pile) end,
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

function SolitaireScreen:onCellAction(zone, pile, idx)
    local board = self.board
    if board.status ~= "playing" then return end

    local result = board:tap(zone, pile, idx)

    if result == "invalid" then
        self.board_widget:refresh()
        self:updateStatus(RESULT_MESSAGES.invalid)
        return
    end

    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:refreshActionBar()

    if result == "won" then
        self:updateStatus()
        self:showMessage(T(_("You won in %1 moves!"), board.moves), 4)
    else
        self:updateStatus()
    end
end

function SolitaireScreen:onSendToFoundation(zone, pile)
    local board = self.board
    if board.status ~= "playing" then return end

    local result = board:sendTopCardToFoundation(zone, pile)

    if result == "invalid" then
        self.board_widget:refresh()
        self:updateStatus(RESULT_MESSAGES.invalid)
        return
    end

    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:refreshActionBar()

    if result == "won" then
        self:updateStatus()
        self:showMessage(T(_("You won in %1 moves!"), board.moves), 4)
    else
        self:updateStatus()
    end
end

function SolitaireScreen:onAutoComplete()
    local moved = self.board:autoComplete()
    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
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
    self.plugin:saveState(self:serializeState())
    self:refreshActionBar()
    if ok then
        self:updateStatus(_("Last move undone."))
    else
        self:updateStatus(_("Nothing to undo."))
    end
end

function SolitaireScreen:isRoundOver()
    return self.board.status == "won"
end

function SolitaireScreen:onNewGame()
    self.board:reset(self.plugin:getSetting("draw_count", 1))
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SolitaireScreen:openDrawCountMenu()
    MenuHelper.openPickerMenu{
        title      = _("Draw mode"),
        items      = {
            { id = 1, text = _("Draw 1") },
            { id = 3, text = _("Draw 3") },
        },
        current_id = self.plugin:getSetting("draw_count", 1),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("draw_count", id)
            self.board:reset(id)
            self.plugin:saveState(self.board:serialize())
            self:buildLayout()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
    }
end

function SolitaireScreen:_drawCountLabel()
    local dc = self.plugin:getSetting("draw_count", 1)
    return T(_("Draw: %1"), dc)
end

function SolitaireScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.status == "won" then
        status = T(_("Solved in %1 move(s)!"), self.board.moves)
    else
        local f = self.board.foundations
        status = self:joinStatus(self:_drawCountLabel(),
            T(_("Moves: %1"), self.board.moves),
            T(_("Foundations: %1/52"), f.S + f.H + f.D + f.C))
    end
    ScreenBase.updateStatus(self, status)
end

return SolitaireScreen
