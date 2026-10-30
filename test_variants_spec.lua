local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Variants", function()
    local Variants

    setup(function()
        Variants = require("variants")
    end)

    local function getter(over)
        return function(key)
            if over and over[key] ~= nil then return over[key] end
            return Variants.SETTING_DEFAULTS[key]
        end
    end

    describe("saves from before the variants existed", function()
        -- Exactly what solitaire 1.1.0 wrote under the "state" key: no
        -- `variant` field, Klondike fields only.
        local function oldKlondikeSave()
            local col = function(...) return { ... } end
            local card = function(rank, suit, up) return { rank = rank, suit = suit, up = up } end
            local tableau = {}
            local deck = {}
            for _, suit in ipairs({ "S", "H", "D", "C" }) do
                for rank = 1, 13 do deck[#deck + 1] = card(rank, suit, false) end
            end
            -- Aces and twos of spades already on the foundation.
            table.remove(deck, 2); table.remove(deck, 1)
            for p = 1, 7 do
                tableau[p] = {}
                for i = 1, p do
                    local c = table.remove(deck)
                    c.up = (i == p)
                    tableau[p][i] = c
                end
            end
            local waste = col(table.remove(deck), table.remove(deck))
            for _, c in ipairs(waste) do c.up = true end
            return {
                tableau     = tableau,
                foundations = { S = 2, H = 0, D = 0, C = 0 },
                stock       = deck,
                waste       = waste,
                draw_count  = 3,
                status      = "playing",
                moves       = 17,
            }
        end

        it("resumes as a Klondike game, with its own draw count", function()
            local old = oldKlondikeSave()
            assert.is_nil(old.variant)
            local board, resumed = Variants.restore("klondike", old, getter{ draw_count = 1 })
            assert.is_true(resumed)
            assert.are.equal(17, board.moves)
            assert.are.equal(3, board.draw_count)
            assert.are.equal(2, board.foundations.S)
            assert.are.equal(#old.stock, #board.stock)
            assert.are.same(old.tableau[7], board.tableau[7])
        end)

        it("is still found under the original state key", function()
            assert.are.equal("state", Variants.stateKey("klondike"))
            for _, id in ipairs(Variants.ORDER) do
                if id ~= "klondike" then assert.are_not.equal("state", Variants.stateKey(id)) end
            end
        end)

        it("is written back with a variant tag the old loader ignores", function()
            local board = Variants.restore("klondike", oldKlondikeSave(), getter())
            local data = Variants.serialize("klondike", board)
            assert.are.equal("klondike", data.variant)
            local again, resumed = Variants.restore("klondike", data, getter())
            assert.is_true(resumed)
            assert.are.equal(17, again.moves)
        end)

        it("an untagged save is never taken for another variant", function()
            for _, id in ipairs(Variants.ORDER) do
                if id ~= "klondike" then
                    local _, resumed = Variants.restore(id, oldKlondikeSave(), getter())
                    assert.is_false(resumed)
                end
            end
        end)
    end)

    describe("every variant", function()
        it("deals a fresh game when there is no save or a corrupt one", function()
            for _, id in ipairs(Variants.ORDER) do
                local board, resumed = Variants.restore(id, nil, getter())
                assert.is_false(resumed)
                assert.are.equal("playing", board.status)
                local _, resumed2 = Variants.restore(id, { variant = id, tableau = {} }, getter())
                assert.is_false(resumed2)
            end
        end)

        it("refuses a save tagged with another variant", function()
            local b = Variants.restore("golf", nil, getter())
            local data = Variants.serialize("golf", b)
            local _, resumed = Variants.restore("pyramid", data, getter())
            assert.is_false(resumed)
        end)

        it("takes its option from the settings", function()
            assert.are.equal(4, Variants.restore("spider", nil, getter{ spider_suits = 4 }).suits)
            assert.is_true(Variants.restore("golf", nil, getter{ golf_wrap = true }).wrap)
            assert.are.equal(0, Variants.restore("pyramid", nil, getter{ pyramid_passes = 0 }).passes)
            assert.are.equal(3, Variants.restore("klondike", nil, getter{ draw_count = 3 }).draw_count)
        end)

        it("keys Spider statistics by suit count", function()
            local b = Variants.restore("spider", nil, getter{ spider_suits = 2 })
            assert.are.equal("spider2", Variants.statsKey("spider", b))
            assert.are.equal("golf", Variants.statsKey("golf", {}))
        end)
    end)

    -- Random play through each board's tap() API: every reachable state must
    -- still hold the full card set (load() checks it) and undo must lead back
    -- to the deal.
    describe("random play", function()
        local function randomTap(id, b)
            local r = math.random
            if id == "klondike" then
                local z = r(4)
                if z == 1 then return b:tap("stock") end
                if z == 2 then return b:tap("waste") end
                if z == 3 then return b:tap("foundation", ({ "S", "H", "D", "C" })[r(4)]) end
                local p = r(7)
                return b:tap("tableau", p, r(math.max(1, #b.tableau[p])))
            elseif id == "freecell" then
                local z = r(3)
                if z == 1 then return b:tap("cell", r(4)) end
                if z == 2 then return b:tap("foundation", ({ "S", "H", "D", "C" })[r(4)]) end
                local p = r(8)
                return b:tap("tableau", p, r(math.max(1, #b.tableau[p])))
            elseif id == "spider" then
                if r(12) == 1 then return b:tap("stock") end
                local p = r(10)
                return b:tap("tableau", p, r(math.max(1, #b.tableau[p])))
            elseif id == "golf" then
                if r(4) == 1 then return b:tap("stock") end
                return b:tap("tableau", r(7))
            elseif id == "pyramid" then
                local z = r(4)
                if z == 1 then return b:tap("stock") end
                if z == 2 then return b:tap("waste") end
                local row = r(7)
                return b:tap("pyramid", row, r(row))
            end
        end

        for _, id in ipairs({ "klondike", "freecell", "spider", "golf", "pyramid" }) do
            it(id .. " conserves its cards and undoes back to the deal", function()
                for seed = 1, 8 do
                    math.randomseed(seed)
                    local b = Variants.restore(id, nil, getter{ spider_suits = ({ 1, 2, 4 })[seed % 3 + 1] })
                    local start = Variants.serialize(id, b)
                    local changes = 0
                    for _ = 1, 400 do
                        if b.status ~= "playing" then break end
                        local before = b._undo:size()
                        randomTap(id, b)
                        if b.autoComplete and math.random(20) == 1 then b:autoComplete() end
                        if b._undo:size() > before then changes = changes + (b._undo:size() - before) end
                        if changes > 150 then break end
                        local _, ok = Variants.restore(id, Variants.serialize(id, b), getter())
                        assert.is_true(ok)
                    end
                    while b:undo() do end
                    local back = Variants.serialize(id, b)
                    back.status, start.status = nil, nil
                    back.draw_count, start.draw_count = nil, nil
                    assert.are.same(start, back)
                end
            end)
        end
    end)
end)
