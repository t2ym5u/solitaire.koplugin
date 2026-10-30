local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local function c(rank, suit, up)
    return { rank = rank, suit = suit, up = up ~= false }
end

describe("SpiderBoard", function()
    local Board

    setup(function()
        Board = require("spider_board")
    end)

    local function emptyBoard(suits)
        math.randomseed(1)
        local b = Board:new{ suits = suits or 4 }
        for i = 1, 10 do b.tableau[i] = { c(1, "D") } end
        b.stock = {}
        b.completed = {}
        return b
    end

    -- K..A of one suit, face up, optionally above extra cards.
    local function fullRun(suit, below)
        local col = below or {}
        for r = 13, 1, -1 do col[#col + 1] = c(r, suit) end
        return col
    end

    describe("deal", function()
        it("deals 54 cards (6,6,6,6,5,...) with only the tops face up, 50 to the stock", function()
            math.randomseed(7)
            local b = Board:new{ suits = 2 }
            local total = 0
            for i = 1, 10 do
                local col = b.tableau[i]
                assert.are.equal(i <= 4 and 6 or 5, #col)
                for j, card in ipairs(col) do
                    assert.are.equal(j == #col, card.up)
                end
                total = total + #col
            end
            assert.are.equal(54, total)
            assert.are.equal(50, #b.stock)
            assert.are.equal(5, b:dealsLeft())
        end)

        it("uses 8 copies of each rank per suit set", function()
            for _, suits in ipairs({ 1, 2, 4 }) do
                local b = Board:new{ suits = suits }
                local per_suit = {}
                local function add(card) per_suit[card.suit] = (per_suit[card.suit] or 0) + 1 end
                for i = 1, 10 do for _, card in ipairs(b.tableau[i]) do add(card) end end
                for _, card in ipairs(b.stock) do add(card) end
                local n = 0
                for _, count in pairs(per_suit) do
                    n = n + 1
                    assert.are.equal(104 / suits, count)
                end
                assert.are.equal(suits, n)
            end
        end)

        it("an unknown suit count falls back to one suit", function()
            assert.are.equal(1, Board:new{ suits = 3 }.suits)
        end)
    end)

    describe("moves", function()
        it("any card goes on one rank higher, whatever the suit", function()
            local b = emptyBoard()
            b.tableau[1] = { c(7, "H") }
            b.tableau[2] = { c(8, "S") }
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("tableau", 2))
            b.tableau[3] = { c(5, "C") }
            b:tap("tableau", 3)
            assert.are.equal("invalid", b:tap("tableau", 2))
        end)

        it("only a same-suit run moves as a unit", function()
            local b = emptyBoard()
            b.tableau[1] = { c(9, "S"), c(8, "H"), c(7, "H") }
            b.tableau[2] = { c(10, "D") }
            -- 9S-8H is not a run: tapping the 9 selects 8H-7H instead
            b:tap("tableau", 1, 1)
            assert.are.equal(2, b.selected.idx)
            assert.are.equal("invalid", b:tap("tableau", 2))
            b.tableau[3] = { c(9, "C") }
            b:tap("tableau", 1, 1)
            assert.are.equal("moved", b:tap("tableau", 3))
            assert.are.equal(3, #b.tableau[3])
            assert.are.equal(1, #b.tableau[1])
        end)

        it("any card or run goes on an empty column, with no length limit", function()
            local b = emptyBoard()
            b.tableau[1] = { c(2, "D", false) }
            for r = 12, 1, -1 do b.tableau[1][#b.tableau[1] + 1] = c(r, "S") end
            b.tableau[2] = {}
            b:tap("tableau", 1, 2)
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.are.equal(12, #b.tableau[2])
            -- the face-down card left behind turns face up
            assert.is_true(b.tableau[1][1].up)
        end)

        it("flips the card uncovered by a move", function()
            local b = emptyBoard()
            b.tableau[1] = { c(3, "C", false), c(6, "H") }
            b.tableau[2] = { c(7, "H") }
            b:tap("tableau", 1)
            b:tap("tableau", 2)
            assert.is_true(b.tableau[1][1].up)
        end)
    end)

    describe("dealing a row", function()
        it("puts one face-up card on every column", function()
            local b = emptyBoard()
            for _ = 1, 10 do b.stock[#b.stock + 1] = c(4, "S", false) end
            assert.are.equal("drew", b:tap("stock"))
            for i = 1, 10 do
                assert.are.equal(2, #b.tableau[i])
                assert.is_true(b.tableau[i][2].up)
            end
            assert.are.equal(0, #b.stock)
            assert.are.equal("empty", b:dealRow())
        end)

        it("is refused while a column is empty", function()
            local b = emptyBoard()
            for _ = 1, 10 do b.stock[#b.stock + 1] = c(4, "S", false) end
            b.tableau[5] = {}
            assert.are.equal("blocked", b:tap("stock"))
            assert.are.equal(10, #b.stock)
            assert.is_false(b:canUndo())
        end)
    end)

    describe("completed runs", function()
        it("a finished K..A run of one suit leaves for the foundation", function()
            local b = emptyBoard()
            b.tableau[1] = { c(5, "C", false) }
            for r = 13, 2, -1 do b.tableau[1][#b.tableau[1] + 1] = c(r, "H") end
            b.tableau[2] = { c(1, "H") }
            b:tap("tableau", 2)
            assert.are.equal("moved", b:tap("tableau", 1))
            assert.are.same({ "H" }, b.completed)
            assert.are.equal(1, #b.tableau[1])
            assert.is_true(b.tableau[1][1].up)
        end)

        it("a mixed-suit K..A stays on the table", function()
            local b = emptyBoard()
            b.tableau[1] = {}
            for r = 13, 2, -1 do b.tableau[1][#b.tableau[1] + 1] = c(r, "H") end
            b.tableau[2] = { c(1, "S") }
            b:tap("tableau", 2)
            b:tap("tableau", 1)
            assert.are.equal(0, #b.completed)
            assert.are.equal(13, #b.tableau[1])
        end)

        it("the eighth run wins", function()
            local b = emptyBoard()
            b.completed = { "S", "S", "S", "S", "S", "S", "S" }
            b.tableau[1] = {}
            for r = 13, 2, -1 do b.tableau[1][#b.tableau[1] + 1] = c(r, "S") end
            b.tableau[2] = { c(1, "S") }
            b:tap("tableau", 2)
            assert.are.equal("won", b:tap("tableau", 1))
            assert.are.equal("won", b.status)
        end)
    end)

    describe("undo", function()
        it("restores a deal and a collected run", function()
            local b = emptyBoard()
            b.tableau[1] = fullRun("D")
            table.remove(b.tableau[1])
            b.tableau[2] = { c(1, "D") }
            b:tap("tableau", 2)
            b:tap("tableau", 1)
            assert.are.equal(1, #b.completed)
            assert.is_true(b:undo())
            assert.are.equal(0, #b.completed)
            assert.are.equal(12, #b.tableau[1])
            assert.are.equal(1, #b.tableau[2])
        end)
    end)

    describe("serialize / load", function()
        it("round-trips a game in progress", function()
            math.randomseed(3)
            local b = Board:new{ suits = 2 }
            b:dealRow()
            local data = b:serialize()
            local b2 = Board:new{ suits = 1 }
            assert.is_true(b2:load(data))
            assert.are.equal(2, b2.suits)
            assert.are.same(b.tableau, b2.tableau)
            assert.are.same(b.stock, b2.stock)
            assert.are.equal(b.moves, b2.moves)
        end)

        it("counts completed runs as their 13 cards", function()
            local b = Board:new{ suits = 1 }
            -- lift one full run of spades off the table into completed
            local all = {}
            for i = 1, 10 do for _, card in ipairs(b.tableau[i]) do all[#all + 1] = card end end
            for _, card in ipairs(b.stock) do all[#all + 1] = card end
            local removed, kept = {}, {}
            for _, card in ipairs(all) do
                if not removed[card.rank] then removed[card.rank] = true else kept[#kept + 1] = card end
            end
            local data = b:serialize()
            data.tableau = {}
            for i = 1, 10 do data.tableau[i] = {} end
            for i, card in ipairs(kept) do
                local col = data.tableau[(i % 10) + 1]
                col[#col + 1] = card
            end
            data.stock = {}
            data.completed = { "S" }
            assert.is_true(Board:new():load(data))
        end)

        it("rejects a save whose cards do not match its suit count", function()
            local b = Board:new{ suits = 2 }
            local data = b:serialize()
            data.suits = 4
            assert.is_false(Board:new():load(data))
            data = b:serialize()
            table.remove(data.stock)
            assert.is_false(Board:new():load(data))
            assert.is_false(Board:new():load({ variant = "golf" }))
        end)
    end)
end)
