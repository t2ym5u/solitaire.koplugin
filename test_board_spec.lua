local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("SolitaireBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    local function newBoard()
        math.randomseed(42)
        return Board:new()
    end

    local function emptyBoard()
        local b = Board:new()
        for i = 1, 7 do b.tableau[i] = {} end
        b.stock = {}
        b.waste = {}
        b.foundations = { S = 0, H = 0, D = 0, C = 0 }
        b.selected = nil
        return b
    end

    describe("reset / deal", function()
        it("deals 28 cards to the tableau and 24 to the stock", function()
            local b = newBoard()
            local total = 0
            for i = 1, 7 do total = total + #b.tableau[i] end
            assert.are.equal(28, total)
            assert.are.equal(24, #b.stock)
        end)

        it("only the top card of each tableau pile is face-up", function()
            local b = newBoard()
            for i = 1, 7 do
                local col = b.tableau[i]
                assert.is_true(col[#col].up)
                for j = 1, #col - 1 do
                    assert.is_false(col[j].up)
                end
            end
        end)

        it("deals every one of the 52 distinct cards exactly once", function()
            local b = newBoard()
            local seen = {}
            local total = 0
            for i = 1, 7 do
                for _, c in ipairs(b.tableau[i]) do
                    local k = c.suit .. c.rank
                    assert.is_nil(seen[k])
                    seen[k] = true
                    total = total + 1
                end
            end
            for _, c in ipairs(b.stock) do
                local k = c.suit .. c.rank
                assert.is_nil(seen[k])
                seen[k] = true
                total = total + 1
            end
            assert.are.equal(52, total)
        end)
    end)

    describe("drawStock", function()
        it("moves draw_count cards from stock to waste, face-up", function()
            local b = newBoard()
            local result = b:drawStock()
            assert.are.equal("drew", result)
            assert.are.equal(1, #b.waste)
            assert.is_true(b.waste[1].up)
            assert.are.equal(23, #b.stock)
        end)

        it("recycles the waste back to the stock, face-down, once stock is empty", function()
            local b = emptyBoard()
            b.waste = { { rank = 5, suit = "S", up = true }, { rank = 6, suit = "H", up = true } }
            local result = b:drawStock()
            assert.are.equal("recycled", result)
            assert.are.equal(0, #b.waste)
            assert.are.equal(2, #b.stock)
            for _, c in ipairs(b.stock) do assert.is_false(c.up) end
        end)

        it("returns empty when both stock and waste are empty", function()
            local b = emptyBoard()
            assert.are.equal("empty", b:drawStock())
        end)
    end)

    describe("getMovableRun", function()
        it("returns nil for a non-face-up card", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 5, suit = "S", up = false } }
            assert.is_nil(b:getMovableRun(1, 1))
        end)

        it("returns a multi-card run when alternating colors descend correctly", function()
            local b = emptyBoard()
            b.tableau[1] = {
                { rank = 9, suit = "C", up = false },
                { rank = 8, suit = "H", up = true },
                { rank = 7, suit = "S", up = true },
            }
            local run = b:getMovableRun(1, 2)
            assert.are.equal(2, #run)
        end)

        it("returns nil when the run isn't a valid alternating descent", function()
            local b = emptyBoard()
            b.tableau[1] = {
                { rank = 8, suit = "H", up = true },
                { rank = 6, suit = "S", up = true },  -- not 7, breaks the descent
            }
            assert.is_nil(b:getMovableRun(1, 1))
        end)
    end)

    describe("isValidTableauMove / isValidFoundationMove", function()
        it("only a King may be placed on an empty tableau pile", function()
            local b = emptyBoard()
            assert.is_true(b:isValidTableauMove({ rank = 13, suit = "S" }, 1))
            assert.is_false(b:isValidTableauMove({ rank = 5, suit = "S" }, 1))
        end)

        it("requires alternating color and descending rank onto a non-empty pile", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 9, suit = "C", up = true } }
            assert.is_true(b:isValidTableauMove({ rank = 8, suit = "H" }, 1))
            assert.is_false(b:isValidTableauMove({ rank = 8, suit = "C" }, 1))  -- same color
            assert.is_false(b:isValidTableauMove({ rank = 7, suit = "H" }, 1))  -- wrong rank
        end)

        it("foundation only accepts the next rank of its own suit, starting at Ace", function()
            local b = emptyBoard()
            assert.is_true(b:isValidFoundationMove({ rank = 1, suit = "S" }, "S"))
            assert.is_false(b:isValidFoundationMove({ rank = 2, suit = "S" }, "S"))
            b.foundations.S = 1
            assert.is_true(b:isValidFoundationMove({ rank = 2, suit = "S" }, "S"))
            assert.is_false(b:isValidFoundationMove({ rank = 2, suit = "H" }, "S"))
        end)
    end)

    describe("tap", function()
        it("selects a face-up tableau card, then moves it onto a valid target", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 8, suit = "H", up = true } }
            b.tableau[2] = { { rank = 9, suit = "C", up = true } }
            assert.are.equal("selected", b:tap("tableau", 1))
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.are.equal(0, #b.tableau[1])
            assert.are.equal(2, #b.tableau[2])
        end)

        it("re-tapping the same pile deselects", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 8, suit = "H", up = true } }
            b:tap("tableau", 1)
            assert.are.equal("deselected", b:tap("tableau", 1))
            assert.is_nil(b.selected)
        end)

        it("an invalid target move clears the selection and reports invalid", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 5, suit = "S", up = true } }
            b.tableau[2] = { { rank = 5, suit = "H", up = true } }
            b:tap("tableau", 1)
            assert.are.equal("invalid", b:tap("tableau", 2))
            assert.is_nil(b.selected)
            assert.are.equal(1, #b.tableau[1])  -- nothing moved
        end)

        it("moving a run flips the newly exposed card face-up", function()
            local b = emptyBoard()
            b.tableau[1] = {
                { rank = 9, suit = "C", up = false },
                { rank = 8, suit = "H", up = true },
            }
            b.tableau[2] = { { rank = 9, suit = "S", up = true } }
            b:tap("tableau", 1)
            assert.are.equal("moved", b:tap("tableau", 2))
            assert.is_true(b.tableau[1][1].up)
        end)

        it("selects and plays the waste card onto a foundation", function()
            local b = emptyBoard()
            b.waste = { { rank = 1, suit = "D", up = true } }
            assert.are.equal("selected", b:tap("waste"))
            assert.are.equal("moved", b:tap("foundation", "D"))
            assert.are.equal(1, b.foundations.D)
            assert.are.equal(0, #b.waste)
        end)

        it("reaching all 4 foundations at King returns won and sets status", function()
            local b = emptyBoard()
            b.foundations = { S = 13, H = 13, D = 13, C = 12 }
            b.waste = { { rank = 13, suit = "C", up = true } }
            b:tap("waste")
            assert.are.equal("won", b:tap("foundation", "C"))
            assert.are.equal("won", b.status)
            assert.is_true(b:isWon())
        end)

        it("tapping stock delegates to drawStock and clears any selection", function()
            local b = newBoard()
            b.tableau[1][#b.tableau[1]].up = true
            b:tap("tableau", 1)
            assert.is_not_nil(b.selected)
            local result = b:tap("stock")
            assert.are.equal("drew", result)
            assert.is_nil(b.selected)
        end)
    end)

    describe("autoComplete", function()
        it("plays every waste/tableau-top card that has a legal foundation move", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 1, suit = "S", up = true } }
            b.waste = { { rank = 2, suit = "S", up = true } }
            local moved = b:autoComplete()
            assert.are.equal(2, moved)
            assert.are.equal(2, b.foundations.S)
        end)

        it("returns 0 when no card has a legal foundation move", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 5, suit = "S", up = true } }
            assert.are.equal(0, b:autoComplete())
        end)
    end)

    describe("undo", function()
        it("restores stock/waste after drawStock", function()
            local b = newBoard()
            local before_stock, before_waste = #b.stock, #b.waste
            b:drawStock()
            assert.is_true(b:canUndo())
            local ok = b:undo()
            assert.is_true(ok)
            assert.are.equal(before_stock, #b.stock)
            assert.are.equal(before_waste, #b.waste)
        end)

        it("restores a tableau move", function()
            local b = emptyBoard()
            b.tableau[1] = { { rank = 8, suit = "H", up = true } }
            b.tableau[2] = { { rank = 9, suit = "C", up = true } }
            b:tap("tableau", 1)
            b:tap("tableau", 2)
            local ok = b:undo()
            assert.is_true(ok)
            assert.are.equal(1, #b.tableau[1])
            assert.are.equal(1, #b.tableau[2])
        end)

        it("returns false when there's nothing to undo", function()
            local b = emptyBoard()
            assert.is_false(b:undo())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips a full game state", function()
            local b = newBoard()
            b:drawStock()
            local data = b:serialize()
            local b2 = Board:new()
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(#b.waste, #b2.waste)
            assert.are.equal(#b.stock, #b2.stock)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)

        it("load rejects data with a duplicated card (checksum guard)", function()
            local b = newBoard()
            local data = b:serialize()
            data.waste[#data.waste + 1] = { rank = data.stock[1].rank, suit = data.stock[1].suit, up = true }
            local b2 = Board:new()
            assert.is_false(b2:load(data))
        end)

        it("load rejects data missing cards (checksum guard)", function()
            local b = newBoard()
            local data = b:serialize()
            table.remove(data.stock)
            local b2 = Board:new()
            assert.is_false(b2:load(data))
        end)
    end)
end)
