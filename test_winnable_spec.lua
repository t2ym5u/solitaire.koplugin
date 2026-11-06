-- Winnable deals: every Golf and Pyramid deal, with every option, can be won,
-- checked by replaying a winning game through the boards' own tap() rules;
-- a seed always gives the same deal; dealing stays fast; a random FreeCell
-- deal is never #11982.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local function key(cards)
    local t = {}
    for _, c in ipairs(cards) do t[#t + 1] = c.rank .. c.suit end
    return table.concat(t, ",")
end

describe("winnable deals", function()
    local Golf, Pyramid, FreeCell, Variants

    setup(function()
        Golf     = require("golf_board")
        Pyramid  = require("pyramid_board")
        FreeCell = require("freecell_board")
        Variants = dofile(DIR .. "variants.lua")
    end)

    -- Golf: find a winning game with random plays written here (not the
    -- board's own search), then play it through tap().
    local function golfWinningLine(b)
        local wrap = b.wrap
        for _ = 1, 20000 do
            local h, line = {}, {}
            for p = 1, 7 do h[p] = #b.tableau[p] end
            local top, sp, left = b.waste[#b.waste].rank, #b.stock, 35
            while left > 0 do
                local fit = {}
                for p = 1, 7 do
                    if h[p] > 0 then
                        local d = math.abs(b.tableau[p][h[p]].rank - top)
                        if d == 1 or (wrap and d == 12) then fit[#fit + 1] = p end
                    end
                end
                if #fit > 0 then
                    local p = fit[math.random(#fit)]
                    top = b.tableau[p][h[p]].rank
                    h[p] = h[p] - 1
                    left = left - 1
                    line[#line + 1] = p
                elseif sp > 0 then
                    top = b.stock[sp].rank
                    sp = sp - 1
                    line[#line + 1] = "stock"
                else
                    break
                end
            end
            if left == 0 then return line end
        end
        return nil
    end

    for _, wrap in ipairs({ false, true }) do
        it("Golf (wrap " .. tostring(wrap) .. "): 200 deals, each won by replaying a game", function()
            local worst = 0
            for seed = 1, 200 do
                math.randomseed(seed)
                local t0 = os.clock()
                local b = Golf:new{ wrap = wrap }
                worst = math.max(worst, os.clock() - t0)
                local line = golfWinningLine(b)
                assert.is_not_nil(line, "no win found for seed " .. seed)
                local res
                for _, m in ipairs(line) do
                    res = m == "stock" and b:tap("stock") or b:tap("tableau", m)
                    assert.are_not.equal("invalid", res)
                end
                assert.are.equal("won", b.status)
            end
            -- ~5 ms worst on LuaJIT; busted's Lua is slower, keep it generous
            assert.is_true(worst < 0.25, "worst deal " .. worst .. " s")
        end)
    end

    local function replayPyramid(b, line)
        for _, m in ipairs(line) do
            local kind = m[1]
            if kind == "stock" then
                b:tap("stock")
            elseif kind == "king" then
                assert.are.equal(13, b.pyramid[m[2]][m[3]].rank)
                b:tap("pyramid", m[2], m[3])
            elseif kind == "king_waste" then
                b:tap("waste")
            elseif kind == "pair" then
                assert.are.equal("selected", b:tap("pyramid", m[2], m[3]))
                b:tap("pyramid", m[4], m[5])
            elseif kind == "pair_waste" then
                assert.are.equal("selected", b:tap("waste"))
                b:tap("pyramid", m[2], m[3])
            end
        end
        return b.status
    end

    for _, passes in ipairs({ 3, 2, 1, 0 }) do
        it("Pyramid (" .. passes .. " passes): 200 deals, each won by replaying a game", function()
            local worst = 0
            for seed = 1, 200 do
                math.randomseed(seed)
                local t0 = os.clock()
                local b = Pyramid:new{ passes = passes }
                worst = math.max(worst, os.clock() - t0)
                local line = {}
                local ok = Pyramid.solve(b.pyramid, b.stock, b.waste, b.pass, passes, 2000000, line)
                assert.is_true(ok, "no win found for seed " .. seed)
                assert.are.equal("won", replayPyramid(b, line))
            end
            assert.is_true(worst < 0.25, "worst deal " .. worst .. " s")
        end)
    end

    it("the Pyramid solver proves a deal lost when it is", function()
        -- A lone 5 needs an 8: none in the stock => lost; one => won.
        local function card(r, s) return { rank = r, suit = s, up = true } end
        local b = Pyramid:new{ passes = 1 }
        for r = 1, 7 do
            for i = 1, r do b.pyramid[r][i] = false end
        end
        b.pyramid[7][1] = card(5, "S")
        b.stock = { card(9, "S"), card(7, "H") }
        b.waste = {}
        assert.is_false(Pyramid.solve(b.pyramid, b.stock, b.waste, 1, 1, 1000))
        b.stock = { card(9, "S"), card(8, "H") }
        assert.is_true(Pyramid.solve(b.pyramid, b.stock, b.waste, 1, 1, 1000))
    end)

    it("a seed always gives the same deal", function()
        for seed = 1, 10 do
            math.randomseed(seed)
            local a = Golf:new{ wrap = false }
            math.randomseed(seed)
            local b = Golf:new{ wrap = false }
            for p = 1, 7 do assert.are.equal(key(a.tableau[p]), key(b.tableau[p])) end
            assert.are.equal(key(a.stock), key(b.stock))
            for _, passes in ipairs({ 3, 1 }) do
                math.randomseed(seed)
                local c = Pyramid:new{ passes = passes }
                math.randomseed(seed)
                local d = Pyramid:new{ passes = passes }
                for r = 1, 7 do assert.are.equal(key(c.pyramid[r]), key(d.pyramid[r])) end
                assert.are.equal(key(c.stock), key(d.stock))
            end
        end
    end)

    it("a built Pyramid deal (1 pass) holds the 52 cards once each", function()
        for seed = 1, 50 do
            math.randomseed(seed)
            local b = Pyramid:new{ passes = 1 }
            local seen, n = {}, 0
            local function add(c)
                local k = c.rank .. c.suit
                assert.is_nil(seen[k])
                seen[k] = true
                n = n + 1
            end
            for r = 1, 7 do for i = 1, r do add(b.pyramid[r][i]) end end
            for _, c in ipairs(b.stock) do
                assert.is_false(c.up)
                add(c)
            end
            assert.are.equal(52, n)
            assert.are.equal(24, #b.stock)
        end
    end)

    it("resuming a save does not deal (and still loads old saves)", function()
        math.randomseed(4)
        local g = Golf:new{ wrap = true }
        local p = Pyramid:new{ passes = 2 }
        local gs, ps = Variants.serialize("golf", g), Variants.serialize("pyramid", p)
        local get = function(k) return Variants.SETTING_DEFAULTS[k] end
        -- variants.lua loads its own copies of the board modules
        local VG, VP = Variants.DEFS.golf.Board, Variants.DEFS.pyramid.Board
        local golfReset, pyrReset = VG.reset, VP.reset
        VG.reset = function() error("dealt a Golf game only to load a save") end
        VP.reset = function() error("dealt a Pyramid game only to load a save") end
        local okG, g2, ok = pcall(Variants.restore, "golf", gs, get)
        local okP, p2, ok2 = pcall(Variants.restore, "pyramid", ps, get)
        VG.reset, VP.reset = golfReset, pyrReset
        assert.is_true(okG, tostring(g2))
        assert.is_true(okP, tostring(p2))
        assert.is_true(ok)
        assert.is_true(g2.wrap)
        for c = 1, 7 do assert.are.equal(key(g.tableau[c]), key(g2.tableau[c])) end
        assert.is_true(ok2)
        assert.are.equal(2, p2.passes)
        assert.are.equal(key(p.stock), key(p2.stock))
        -- no save: a fresh, complete deal
        local g3, ok3 = Variants.restore("golf", nil, get)
        assert.is_false(ok3)
        assert.are.equal(35, g3:cardsLeft())
    end)

    it("a random FreeCell deal is never #11982, which can still be chosen", function()
        local real = math.random
        local calls = 0
        -- the first draw lands on 11982, the next one on 5
        math.random = function(n)
            calls = calls + 1
            if n == FreeCell.MAX_DEAL then return calls == 1 and 11982 or 5 end
            return real(n)
        end
        local ok, b = pcall(FreeCell.new, FreeCell)
        math.random = real
        assert.is_true(ok)
        assert.are.equal(5, b.deal)
        local chosen = FreeCell:new{ deal = 11982 }
        assert.are.equal(11982, chosen.deal)
    end)
end)
