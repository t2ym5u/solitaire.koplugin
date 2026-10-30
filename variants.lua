local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local SolitaireBoard = lrequire("board")
local FreeCellBoard  = lrequire("freecell_board")
local SpiderBoard    = lrequire("spider_board")
local GolfBoard      = lrequire("golf_board")
local PyramidBoard   = lrequire("pyramid_board")

-- ---------------------------------------------------------------------------
-- Variants -- which board each game uses, where its save lives and which
-- setting drives its deal. No UI here, so the busted specs can exercise the
-- save/restore path the screen uses.
--
-- Klondike keeps the plugin's original "state" key: a save from before the
-- other variants existed has no `variant` field and still loads as the
-- Klondike game it is. Every other variant has its own key, so switching
-- games keeps each one's game in progress.
-- ---------------------------------------------------------------------------

local Variants = {}

Variants.ORDER = { "klondike", "freecell", "spider", "golf", "pyramid" }

Variants.SETTING_DEFAULTS = {
    variant        = "klondike",
    draw_count     = 1,
    spider_suits   = 1,
    golf_wrap      = false,
    pyramid_passes = PyramidBoard.DEFAULT_PASSES,
}

-- get(key) returns the setting's value (the screen passes its plugin
-- settings, defaults applied).
Variants.DEFS = {
    klondike = {
        Board = SolitaireBoard, state_key = "state",
        create = function(get) return SolitaireBoard:new{ draw_count = get("draw_count") } end,
        reset  = function(board, get) board:reset(get("draw_count")) end,
    },
    freecell = {
        Board = FreeCellBoard, state_key = "state_freecell",
        create = function() return FreeCellBoard:new() end,
        reset  = function(board) board:reset() end,
    },
    spider = {
        Board = SpiderBoard, state_key = "state_spider",
        create = function(get) return SpiderBoard:new{ suits = get("spider_suits") } end,
        reset  = function(board, get) board:reset(get("spider_suits")) end,
    },
    golf = {
        Board = GolfBoard, state_key = "state_golf",
        create = function(get) return GolfBoard:new{ wrap = get("golf_wrap") } end,
        reset  = function(board, get) board:reset(get("golf_wrap")) end,
    },
    pyramid = {
        Board = PyramidBoard, state_key = "state_pyramid",
        create = function(get) return PyramidBoard:new{ passes = get("pyramid_passes") } end,
        reset  = function(board, get) board:reset(get("pyramid_passes")) end,
    },
}

function Variants.isValid(id)
    return Variants.DEFS[id] ~= nil
end

function Variants.stateKey(id)
    return Variants.DEFS[id].state_key
end

-- Returns a board for `id`, resumed from `state` (the table saved under
-- the variant's state key) when it is a valid save of that variant, else
-- freshly dealt. Second result: true when the save was resumed.
function Variants.restore(id, state, get)
    local def = Variants.DEFS[id]
    local board = def.create(get)
    local ok = type(state) == "table"
        and (state.variant == id or (state.variant == nil and id == "klondike"))
        and board:load(state)
    if not ok then def.reset(board, get) end
    return board, ok and true or false
end

function Variants.reset(id, board, get)
    Variants.DEFS[id].reset(board, get)
end

-- What the screen saves: the board's own state, tagged with its variant.
function Variants.serialize(id, board)
    local data = board:serialize()
    data.variant = id
    return data
end

-- Per-variant statistics row key; Spider is split by suit count.
function Variants.statsKey(id, board)
    if id == "spider" then return "spider" .. tostring(board.suits) end
    return id
end

return Variants
