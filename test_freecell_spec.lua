local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local function c(rank, suit) return { rank = rank, suit = suit, up = true } end

describe("FreeCellBoard", function()
    local Board

    setup(function()
        Board = require("freecell_board")
    end)

    -- A board with nothing on it; tests place the cards they need.
    local function emptyBoard()
        local b = Board:new{ deal = 1 }
        for i = 1, 8 do b.tableau[i] = {} end
        b.cells = { false, false, false, false }
        b.foundations = { S = 0, H = 0, D = 0, C = 0 }
        return b
    end

    local function label(card)
        local R = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K" }
        return R[card.rank] .. card.suit
    end

    describe("Microsoft deal numbering", function()
        it("reproduces Microsoft FreeCell deal #1", function()
            -- Rows of the well-known deal #1, left to right.
            local expected = {
                "JD 2D 9H JC 5D 7H 7C 5H",
                "KD KC 9S 5S AD QC KH 3H",
                "2S KS 9D QD JS AS AH 3C",
                "4C 5C TS QH 4H AC 4D 7S",
                "3S TD 4S TH 8H 2C JH 7D",
                "6D 8S 8D QS 6C 3D 8C TC",
                "6S 9C 2H 6H",
            }
            local cols = Board.msDeal(1)
            for row, line in ipairs(expected) do
                local got = {}
                for col = 1, 8 do
                    if cols[col][row] then got[#got + 1] = label(cols[col][row]) end
                end
                assert.are.equal(line, table.concat(got, " "))
            end
        end)

        it("deals 52 distinct face-up cards, 7 to the first four columns and 6 to the rest", function()
            for _, n in ipairs({ 1, 617, 11982, 32000 }) do
                local cols = Board.msDeal(n)
                local seen, total = {}, 0
                for i = 1, 8 do
                    assert.are.equal(i <= 4 and 7 or 6, #cols[i])
                    for _, card in ipairs(cols[i]) do
                        assert.is_true(card.up)
                        assert.is_nil(seen[label(card)])
                        seen[label(card)] = true
                        total = total + 1
                    end
                end
                assert.are.equal(52, total)
            end
        end)

        it("reset keeps the deal number, or picks one in 1..32000", function()
            assert.are.equal(617, Board:new{ deal = 617 }.deal)
            for _ = 1, 20 do
                local d = Board:new().deal
                assert.is_true(d >= 1 and d <= 32000)
            end
            local b = Board:new{ deal = 99999 }
            assert.is_true(b.deal >= 1 and b.deal <= 32000)
        end)
    end)

    describe("supermove limit", function()
        it("is (free cells + 1) * 2^(empty columns)", function()
            local b = emptyBoard()
            for i = 1, 8 do b.tableau[i] = { c(1, "S") } end
            assert.are.equal(5, b:maxRunLength(false))
            b.tableau[8] = {}
            assert.are.equal(10, b:maxRunLength(false))
            b.tableau[7] = {}
            assert.are.equal(20, b:maxRunLength(false))
            b.cells = { c(2, "S"), c(3, "S"), false, false }
            assert.are.equal(12, b:maxRunLength(false))
        end)

        it("does not count an empty destination column", function()
            local b = emptyBoard()
            for i = 1, 6 do b.tableau[i] = { c(1, "S") } end
            -- columns 7 and 8 empty, 4 free cells
            assert.are.equal(10, b:maxRunLength(true))
            assert.are.equal(20, b:maxRunLength(false))
        end)

        it("refuses a run longer than the limit with too_many", function()
            local b = emptyBoard()
            for i = 3, 8 do b.tableau[i] = { c(1, "D") } end
            -- 3-card run, free cells all full: limit is 1
            b.tableau[1] = { c(9, "S"), c(8, "H"), c(7, "C") }
            b.tableau[2] = { c(10, "H") }
            b.cells = { c(2, "D"), c(3, "D"), c(4, "D"), c(5, "D") }
            b:tap("tableau", 1, 1)
            assert.are.equal("too_many", b:tap("tableau", 2))
            assert.are.equal(3, #b.tableau[1])
            -- one free cell + 0 empty columns: 2 cards, still too few
            b.cells[1] = false
            b:tap("tableau", 1, 1)
            assert.are.equal("too_many", b:tap("tableau", 2))
            b.cells[2] = false
            b:tap("tableau", 1, 1)
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.are.equal(4, #b.tableau[2])
            assert.are.equal(0, #b.tableau[1])
        end)
    end)

    describe("moves", function()
        it("builds down in alternating colours only", function()
            local b = emptyBoard()
            b.tableau[1] = { c(8, "H") }
            b.tableau[2] = { c(9, "D") }
            b.tableau[3] = { c(9, "S") }
            b:tap("tableau", 1)
            assert.are.equal("invalid", b:tap("tableau", 2))
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("tableau", 3))
            assert.are.equal(2, #b.tableau[3])
        end)

        it("any card goes on an empty column", function()
            local b = emptyBoard()
            b.tableau[1] = { c(5, "H") }
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.are.equal(5, b.tableau[2][1].rank)
        end)

        it("moves a card to a free cell and back", function()
            local b = emptyBoard()
            b.tableau[1] = { c(9, "C"), c(5, "H") }
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("cell", 3))
            assert.are.equal(5, b.cells[3].rank)
            assert.are.equal(1, #b.tableau[1])
            -- occupied cell refuses another card
            b:tap("tableau", 1)
            assert.are.equal("invalid", b:tap("cell", 3))
            b.tableau[2] = { c(6, "S") }
            b:tap("cell", 3)
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.is_false(b.cells[3])
        end)

        it("a selected run sends only its top card to a free cell", function()
            local b = emptyBoard()
            b.tableau[1] = { c(9, "S"), c(8, "H") }
            b:tap("tableau", 1, 1)
            assert.are.equal("moved", b:tap("cell", 1))
            assert.are.equal(8, b.cells[1].rank)
            assert.are.equal(1, #b.tableau[1])
        end)

        it("picks the sub-run that fits the destination", function()
            local b = emptyBoard()
            b.tableau[1] = { c(10, "S"), c(9, "H"), c(8, "C"), c(7, "D") }
            b.tableau[2] = { c(9, "D") }
            -- the whole run is picked, but only 8-7 fits on the red 9
            assert.are.equal("selected", b:tap("tableau", 1, 1))
            assert.are.equal(1, b.selected.idx)
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.are.same({ 9, 8, 7 }, { b.tableau[2][1].rank, b.tableau[2][2].rank, b.tableau[2][3].rank })
            assert.are.equal(2, #b.tableau[1])
        end)

        it("tapping a buried card selects the movable run above it", function()
            local b = emptyBoard()
            b.tableau[1] = { c(2, "S"), c(10, "S"), c(9, "H") }
            b:tap("tableau", 1, 1)
            assert.are.equal(2, b.selected.idx)
        end)

        it("foundations build up by suit from the Ace", function()
            local b = emptyBoard()
            b.tableau[1] = { c(2, "H"), c(1, "H") }
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("foundation", "H"))
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("foundation", "H"))
            assert.are.equal(2, b.foundations.H)
            b.cells[1] = c(4, "H")
            b:tap("cell", 1)
            assert.are.equal("invalid", b:tap("foundation", "H"))
        end)

        it("double-tap sends a cell or column top to its foundation", function()
            local b = emptyBoard()
            b.cells[2] = c(1, "C")
            b.tableau[4] = { c(2, "C") }
            assert.are.equal("moved", b:sendTopCardToFoundation("cell", 2))
            assert.are.equal("moved", b:sendTopCardToFoundation("tableau", 4))
            assert.are.equal(2, b.foundations.C)
            assert.are.equal("invalid", b:sendTopCardToFoundation("tableau", 4))
        end)

        it("auto-complete plays every card it can, and wins", function()
            local b = emptyBoard()
            b.foundations = { S = 12, H = 12, D = 12, C = 11 }
            b.cells[1] = c(13, "S")
            b.tableau[1] = { c(13, "C"), c(12, "C") }
            b.tableau[2] = { c(13, "H") }
            b.tableau[3] = { c(13, "D") }
            assert.are.equal(5, b:autoComplete())
            assert.are.equal("won", b.status)
        end)
    end)

    describe("undo", function()
        it("restores a supermove", function()
            local b = emptyBoard()
            b.tableau[1] = { c(9, "S"), c(8, "H") }
            b.tableau[2] = { c(10, "H") }
            b:tap("tableau", 1, 1)
            b:tap("tableau", 2)
            assert.is_true(b:undo())
            assert.are.equal(2, #b.tableau[1])
            assert.are.equal(1, #b.tableau[2])
            assert.are.equal(0, b.moves)
            assert.is_false(b:undo())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips a game in progress", function()
            local b = Board:new{ deal = 1 }
            b:tap("tableau", 1)
            b:tap("cell", 1)
            local data = b:serialize()
            local b2 = Board:new{ deal = 5 }
            assert.is_true(b2:load(data))
            assert.are.equal(1, b2.deal)
            assert.are.same(b.tableau, b2.tableau)
            assert.are.same(b.cells, b2.cells)
            assert.are.equal(b.moves, b2.moves)
        end)

        it("rejects a save with a duplicated or missing card", function()
            local b = Board:new{ deal = 1 }
            local data = b:serialize()
            data.tableau[1][1] = { rank = data.tableau[2][1].rank, suit = data.tableau[2][1].suit, up = true }
            assert.is_false(Board:new():load(data))
            data = b:serialize()
            table.remove(data.tableau[1])
            assert.is_false(Board:new():load(data))
            assert.is_false(Board:new():load({ variant = "spider" }))
            assert.is_false(Board:new():load(nil))
        end)
    end)
end)
