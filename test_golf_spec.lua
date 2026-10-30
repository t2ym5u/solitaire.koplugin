local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local function c(rank, suit, up)
    return { rank = rank, suit = suit, up = up ~= false }
end

describe("GolfBoard", function()
    local Board

    setup(function()
        Board = require("golf_board")
    end)

    local function emptyBoard(wrap)
        local b = Board:new{ wrap = wrap }
        for i = 1, 7 do b.tableau[i] = {} end
        b.stock = { c(9, "C", false) }
        b.waste = { c(7, "S") }
        return b
    end

    it("deals 7 face-up columns of 5, one waste card and a 16-card stock", function()
        math.randomseed(5)
        local b = Board:new()
        for i = 1, 7 do
            assert.are.equal(5, #b.tableau[i])
            for _, card in ipairs(b.tableau[i]) do assert.is_true(card.up) end
        end
        assert.are.equal(1, #b.waste)
        assert.are.equal(16, #b.stock)
        assert.are.equal(35, b:cardsLeft())
        assert.is_false(b.wrap)
    end)

    it("plays a column top one rank above or below the waste, any suit", function()
        local b = emptyBoard()
        b.tableau[1] = { c(6, "H") }
        b.tableau[2] = { c(8, "D") }
        b.tableau[3] = { c(9, "S") }
        assert.are.equal("moved", b:tap("tableau", 1))
        assert.are.equal(6, b.waste[#b.waste].rank)
        assert.are.equal("invalid", b:tap("tableau", 2))
        assert.are.equal("invalid", b:tap("tableau", 3))
    end)

    it("does not connect King and Ace unless wrap is on", function()
        local b = emptyBoard(false)
        b.waste = { c(13, "S") }
        b.tableau[1] = { c(1, "H") }
        b.tableau[2] = { c(12, "H") }
        assert.are.equal("invalid", b:tap("tableau", 1))
        assert.are.equal("moved", b:tap("tableau", 2))

        local w = emptyBoard(true)
        w.waste = { c(13, "S") }
        w.tableau[1] = { c(1, "H") }
        w.tableau[2] = { c(5, "H") }
        assert.are.equal("moved", w:tap("tableau", 1))
        assert.is_true(w.wrap)
    end)

    it("the stock deals one card at a time onto the waste and is not recycled", function()
        local b = emptyBoard()
        b.tableau[1] = { c(2, "H") }
        b.tableau[2] = { c(8, "S") }
        assert.are.equal("drew", b:tap("stock"))
        assert.are.equal(9, b.waste[#b.waste].rank)
        assert.are.equal(0, #b.stock)
        assert.are.equal("playing", b.status)
        b:tap("tableau", 2)
        assert.is_true(b.waste[#b.waste].up)
        -- stock empty, 2H fits neither 9 nor 8 -> lost
        assert.are.equal("lost", b.status)
    end)

    it("is lost only when the stock is empty and no top card fits", function()
        local b = emptyBoard()
        b.stock = {}
        b.tableau[1] = { c(2, "H"), c(6, "D") }
        b.tableau[2] = { c(5, "C") }
        assert.are.equal("moved", b:tap("tableau", 1))  -- 6 on 7, then 5 still fits
        assert.are.equal("playing", b.status)
        assert.are.equal("lost", b:tap("tableau", 2))  -- 5 on 6; 2 fits nothing
        assert.are.equal("not_playing", b:tap("tableau", 1))
        assert.are.equal(1, b:score())
    end)

    it("is won when every column is cleared", function()
        local b = emptyBoard()
        b.tableau[1] = { c(8, "H") }
        assert.are.equal("won", b:tap("tableau", 1))
        assert.is_true(b:isWon())
        assert.are.equal(-1, b:score())
    end)

    it("undo takes back a play and a draw, and reopens a lost game", function()
        local b = emptyBoard()
        b.tableau[1] = { c(2, "H") }
        b:tap("stock")
        assert.are.equal("lost", b.status)
        assert.is_true(b:undo())
        assert.are.equal("playing", b.status)
        assert.are.equal(1, #b.stock)
        assert.are.equal(1, #b.waste)
    end)

    it("round-trips through serialize / load and rejects a bad save", function()
        math.randomseed(11)
        local b = Board:new{ wrap = true }
        b:tap("stock")
        local data = b:serialize()
        local b2 = Board:new()
        assert.is_true(b2:load(data))
        assert.is_true(b2.wrap)
        assert.are.same(b.tableau, b2.tableau)
        assert.are.same(b.waste, b2.waste)
        assert.are.same(b.stock, b2.stock)
        data.waste[1] = { rank = data.tableau[1][1].rank, suit = data.tableau[1][1].suit }
        assert.is_false(Board:new():load(data))
        assert.is_false(Board:new():load({ variant = "golf" }))
    end)
end)
