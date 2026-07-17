local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
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

Tap a card to select it, then tap a destination pile or foundation to move it there. Tap the stock pile to draw new cards (or recycle the waste once the stock is empty).
]])

local GAME_RULES_FR = [[
Solitaire Klondike — Règles

Déplacez les 52 cartes vers les 4 fondations, une par couleur, de l'As au Roi.

Colonnes : construisez en alternant les couleurs (ex. un 8 rouge sur un 9 noir). Une carte face cachée est révélée quand elle devient le sommet de sa colonne. Seul un Roi (ou une suite commençant par un Roi) peut être posé sur une colonne vide.

Fondations : construisez dans la même couleur, en partant de l'As.

Touchez une carte pour la sélectionner, puis touchez une colonne ou une fondation de destination. Touchez la pioche pour tirer de nouvelles cartes (ou recycler la défausse une fois la pioche vide).
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
    local sw = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Solitaire"), function()
        return {
            { text = _("New game"),          callback = function() self:onNewGame() end },
            { text = self:_drawCountLabel(), callback = function() self:openDrawCountMenu() end },
            { text = _("Auto-complete"),     callback = function() self:onAutoComplete() end },
            { text = _("Undo"),              callback = function() self:onUndo() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local board_w = is_landscape and math.floor(sw * 0.62) or math.floor(sw * 0.92)
    local board_h
    if is_landscape then
        -- Base height on available vertical space (screen minus title bar)
        -- rather than board width, so the tableau has room to fan out fully
        -- and the right-hand status column gets a tall layout to sit in.
        local tb_h    = title_bar:getSize().h
        local avail_h = sh - tb_h
        board_h = math.floor(avail_h * 0.94)
    else
        board_h = math.floor(board_w * 0.72)
    end

    self.board_widget = SolitaireBoardWidget:new{
        board        = self.board,
        width        = board_w,
        height       = board_h,
        onCellAction = function(zone, pile, idx) self:onCellAction(zone, pile, idx) end,
        onSendToFoundation = function(zone, pile) self:onSendToFoundation(zone, pile) end,
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    if is_landscape then
        local right = VerticalGroup:new{
            align = "center",
            self.status_text,
        }
        local content = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, content, nil)
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
    if ok then
        self:updateStatus(_("Last move undone."))
    else
        self:updateStatus(_("Nothing to undo."))
    end
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
    return T(_("Draw %1"), dc)
end

function SolitaireScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.status == "won" then
        status = T(_("Solved in %1 move(s)!"), self.board.moves)
    else
        status = T(_("Moves: %1  Foundations: %2/52"),
            self.board.moves,
            self.board.foundations.S + self.board.foundations.H
                + self.board.foundations.D + self.board.foundations.C)
    end
    ScreenBase.updateStatus(self, status)
end

return SolitaireScreen
