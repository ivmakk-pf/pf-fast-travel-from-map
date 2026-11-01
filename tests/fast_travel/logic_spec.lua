local logic = require("ftm.fast_travel.logic")

describe("isMapTab", function()
    it("is true for the map tab", function()
        assert.are.equal(true, logic.isMapTab(4))
    end)

    it("is false when the ledger closes", function()
        assert.are.equal(false, logic.isMapTab(0))
    end)

    it("is false for each other tab", function()
        for _, tab in ipairs({ 1, 2, 3, 5, 6, 7 }) do
            assert.are.equal(false, logic.isMapTab(tab))
        end
    end)

    it("is false for a value that is not a number", function()
        assert.are.equal(false, logic.isMapTab(nil))
        assert.are.equal(false, logic.isMapTab("4"))
        assert.are.equal(false, logic.isMapTab({}))
    end)
end)
