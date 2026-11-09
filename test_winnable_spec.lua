-- Resuming a Golf or Pyramid save never deals a new game. (The winnable-deal
-- guarantees live in test_difficulty_spec.lua.)
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

describe("winnable deals: saves", function()
    local Golf, Pyramid, Variants

    setup(function()
        Golf     = require("golf_board")
        Pyramid  = require("pyramid_board")
        Variants = dofile(DIR .. "variants.lua")
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
end)
