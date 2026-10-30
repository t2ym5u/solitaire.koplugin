local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local function c(rank, suit, up)
    return { rank = rank, suit = suit, up = up ~= false }
end

describe("PyramidBoard", function()
    local Board

    setup(function()
        Board = require("pyramid_board")
    end)

    -- An empty pyramid; tests place the cards they need.
    local function emptyBoard(passes)
        local b = Board:new{ passes = passes }
        for r = 1, 7 do
            for i = 1, r do b.pyramid[r][i] = false end
        end
        b.stock, b.waste, b.discard = {}, {}, {}
        return b
    end

    it("deals a 28-card pyramid and a 24-card stock", function()
        math.randomseed(2)
        local b = Board:new()
        assert.are.equal(28, b:cardsLeft())
        assert.are.equal(24, #b.stock)
        assert.are.equal(0, #b.waste)
        assert.are.equal(3, b.passes)
        for r = 1, 7 do assert.are.equal(r, #b.pyramid[r]) end
    end)

    it("exposes only the bottom row, then cards whose two covers are gone", function()
        math.randomseed(2)
        local b = Board:new()
        for i = 1, 7 do assert.is_true(b:isExposed(7, i)) end
        assert.is_false(b:isExposed(6, 1))
        b.pyramid[7][1] = false
        assert.is_false(b:isExposed(6, 1))
        b.pyramid[7][2] = false
        assert.is_true(b:isExposed(6, 1))
    end)

    it("removes a King on its own", function()
        local b = emptyBoard()
        b.pyramid[7][1] = c(13, "S")
        b.pyramid[7][2] = c(5, "S")
        b.stock = { c(4, "C", false) }
        assert.are.equal("moved", b:tap("pyramid", 7, 1))
        assert.is_false(b.pyramid[7][1])
        assert.are.equal(1, #b.discard)
    end)

    it("removes two exposed cards adding up to 13", function()
        local b = emptyBoard()
        b.pyramid[7][1] = c(6, "S")
        b.pyramid[7][2] = c(7, "H")
        b.pyramid[7][3] = c(3, "H")
        b.stock = { c(4, "C", false) }
        assert.are.equal("selected", b:tap("pyramid", 7, 1))
        assert.are.equal("invalid", b:tap("pyramid", 7, 3))
        assert.is_nil(b.selected)
        b:tap("pyramid", 7, 1)
        assert.are.equal("moved", b:tap("pyramid", 7, 2))
        assert.is_false(b.pyramid[7][1])
        assert.is_false(b.pyramid[7][2])
        assert.are.equal(2, #b.discard)
    end)

    it("pairs a pyramid card with the waste top, and Jack with 2, Queen with Ace", function()
        local b = emptyBoard()
        b.pyramid[7][1] = c(11, "S")
        b.pyramid[7][2] = c(1, "D")
        b.waste = { c(12, "C"), c(2, "H") }
        b.stock = { c(4, "C", false) }
        b:tap("waste")
        assert.are.equal("moved", b:tap("pyramid", 7, 1))
        assert.are.equal(12, b.waste[#b.waste].rank)
        b:tap("pyramid", 7, 2)
        assert.are.equal("won", b:tap("waste"))
    end)

    it("covered cards cannot be played", function()
        local b = emptyBoard()
        b.pyramid[6][1] = c(6, "S")
        b.pyramid[7][1] = c(7, "H")
        b.pyramid[7][2] = c(2, "H")
        b.stock = { c(4, "C", false) }
        assert.are.equal("invalid", b:tap("pyramid", 6, 1))
        b:tap("pyramid", 7, 1)
        assert.are.equal("invalid", b:tap("pyramid", 6, 1))
    end)

    it("tapping the same card twice deselects it", function()
        local b = emptyBoard()
        b.pyramid[7][1] = c(6, "S")
        b.stock = { c(4, "C", false) }
        b:tap("pyramid", 7, 1)
        assert.are.equal("deselected", b:tap("pyramid", 7, 1))
    end)

    describe("stock passes", function()
        local function stockBoard(passes)
            local b = emptyBoard(passes)
            b.pyramid[7][1] = c(5, "S")
            b.stock = { c(2, "C", false), c(3, "C", false) }
            return b
        end

        it("turns the waste back over until the passes are used up", function()
            local b = stockBoard(2)
            assert.are.equal("drew", b:tap("stock"))
            assert.are.equal("drew", b:tap("stock"))
            assert.is_true(b:canRecycle())
            assert.are.equal("recycled", b:tap("stock"))
            assert.are.equal(2, b.pass)
            assert.are.equal(2, #b.stock)
            -- last card of the last pass: nothing pairs, no recycle -> lost
            assert.are.equal("drew", b:tap("stock"))
            assert.are.equal("lost", b:tap("stock"))
            assert.is_false(b:canRecycle())
        end)

        it("one pass means no recycling", function()
            local b = stockBoard(1)
            b:tap("stock")
            assert.are.equal("lost", b:tap("stock"))
        end)

        it("0 passes means unlimited", function()
            local b = stockBoard(0)
            for _ = 1, 10 do
                b:tap("stock")
                b:tap("stock")
                assert.are.equal("recycled", b:tap("stock"))
            end
            assert.are.equal("playing", b.status)
            assert.is_nil(b:redealsLeft())
        end)

        it("an unknown pass count falls back to the default", function()
            assert.are.equal(3, Board:new{ passes = 7 }.passes)
        end)
    end)

    it("undo restores a removed pair and reopens a lost game", function()
        local b = emptyBoard(1)
        b.pyramid[7][1] = c(6, "S")
        b.pyramid[7][2] = c(7, "H")
        b.pyramid[7][3] = c(9, "H")
        b:tap("pyramid", 7, 1)
        assert.are.equal("lost", b:tap("pyramid", 7, 2))
        assert.is_true(b:undo())
        assert.are.equal("playing", b.status)
        assert.are.same(c(6, "S"), b.pyramid[7][1])
        assert.are.equal(0, #b.discard)
    end)

    it("round-trips through serialize / load and rejects a bad save", function()
        math.randomseed(4)
        local b = Board:new{ passes = 2 }
        b:tap("stock")
        b:tap("stock")
        local data = b:serialize()
        local b2 = Board:new()
        assert.is_true(b2:load(data))
        assert.are.equal(2, b2.passes)
        assert.are.same(b.pyramid, b2.pyramid)
        assert.are.same(b.waste, b2.waste)
        assert.are.same(b.stock, b2.stock)
        -- a card lost from the save
        data.pyramid[7][1] = false
        assert.is_false(Board:new():load(data))
        assert.is_false(Board:new():load({ variant = "pyramid" }))
    end)
end)
