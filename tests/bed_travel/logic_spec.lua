local logic = require("ftm.bed_travel.logic")

describe("press", function()
    it("opens the window for a left press on the bed icon", function()
        assert.are.equal(true, logic.press(true, true))
    end)

    it("does not open it for a right press on the bed icon", function()
        assert.are.equal(false, logic.press(true, false))
    end)

    it("does not open it for a left press next to the bed icon", function()
        assert.are.equal(false, logic.press(false, true))
    end)
end)

describe("onConfirm", function()
    it("travels to the bed for an open bed window and no fast-travel selection", function()
        assert.are.equal("bed", logic.onConfirm(true, false))
    end)

    it("leaves a fast-travel selection to the game, also with a bed window", function()
        assert.are.equal("vanilla", logic.onConfirm(true, true))
        assert.are.equal("vanilla", logic.onConfirm(false, true))
    end)

    it("does nothing with neither", function()
        assert.are.equal("none", logic.onConfirm(false, false))
    end)
end)

describe("target", function()
    local function V(x, y, z)
        return { X = x, Y = y, Z = z }
    end
    local bed, point, zero = V(1, 2, 3), V(4, 5, 6), V(0, 0, 0)

    it("is the bed location when it is not zero", function()
        assert.are.equal(bed, logic.target(bed, point))
    end)

    it("is the respawn point location when the bed location is zero or missing", function()
        assert.are.equal(point, logic.target(zero, point))
        assert.are.equal(point, logic.target(nil, point))
    end)

    it("is nil when both are zero or missing", function()
        assert.are.equal(nil, logic.target(zero, zero))
        assert.are.equal(nil, logic.target(nil, nil))
    end)
end)

describe("hoverColor", function()
    it("is white on hover", function()
        local c = logic.hoverColor(true)
        assert.are.equal(1, c.R)
        assert.are.equal(1, c.G)
        assert.are.equal(1, c.B)
        assert.are.equal(1, c.A)
    end)

    it("is a dim gray at full opacity off hover", function()
        local c = logic.hoverColor(false)
        assert.are.equal(0.75, c.R)
        assert.are.equal(0.75, c.G)
        assert.are.equal(0.75, c.B)
        assert.are.equal(1, c.A)
    end)
end)

describe("iconColor", function()
    it("is the vanilla gold of a selected fast-travel icon while selected, with and without hover", function()
        for _, hovered in ipairs({ true, false }) do
            local c = logic.iconColor(hovered, true)
            assert.are.same({ R = 0.64, G = 0.31, B = 0, A = 1 }, c)
        end
    end)

    it("is the hover color when not selected", function()
        assert.are.equal(logic.hoverColor(true), logic.iconColor(true, false))
        assert.are.equal(logic.hoverColor(false), logic.iconColor(false, false))
    end)
end)

describe("refreshTint", function()
    it("is true each 10 turns (0.5 s)", function()
        assert.is_true(logic.refreshTint(10))
        assert.is_true(logic.refreshTint(20))
    end)

    it("is false at the other turns", function()
        assert.is_false(logic.refreshTint(1))
        assert.is_false(logic.refreshTint(9))
        assert.is_false(logic.refreshTint(11))
    end)
end)

describe("isBedSelection", function()
    it("is true only for a selection with the bed name", function()
        assert.is_true(logic.isBedSelection(true, "Bed", "Bed"))
    end)

    it("is false for another destination, for no selection, and for an unread name", function()
        assert.is_false(logic.isBedSelection(true, "Church", "Bed"))
        assert.is_false(logic.isBedSelection(false, "Bed", "Bed"))
        assert.is_false(logic.isBedSelection(true, nil, "Bed"))
    end)
end)

describe("iconChanged", function()
    it("is true when an icon comes, changes, or goes", function()
        assert.is_true(logic.iconChanged(nil, 100))
        assert.is_true(logic.iconChanged(100, 200))
        assert.is_true(logic.iconChanged(100, nil))
    end)

    it("is false for the same icon, and with no icon before and after", function()
        assert.is_false(logic.iconChanged(100, 100))
        assert.is_false(logic.iconChanged(nil, nil))
    end)
end)

describe("sameSpot", function()
    it("matches a marker at the bed location, within the rounding", function()
        assert.is_true(logic.sameSpot({ X = 100, Y = 200, Z = 300 }, { X = 100, Y = 205, Z = 300 }))
    end)

    it("does not match a marker away from the bed", function()
        assert.is_false(logic.sameSpot({ X = 100, Y = 211, Z = 300 }, { X = 100, Y = 200, Z = 300 }))
    end)

    it("does not match with no location", function()
        assert.is_false(logic.sameSpot(nil, { X = 1, Y = 2, Z = 3 }))
        assert.is_false(logic.sameSpot({ X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 }))
    end)
end)

describe("isBedMarkerKey", function()
    it("matches the key of a respawn point marker", function()
        assert.is_true(logic.isBedMarkerKey("BP_RespawnPointTemplate_C_2147481234"))
    end)

    it("does not match another marker", function()
        assert.is_false(logic.isBedMarkerKey("LocalPlayer"))
    end)
end)

describe("onLedgerTab", function()
    it("arms the map hook and starts the hover on the map tab", function()
        assert.are.equal("map", logic.onLedgerTab(true, false))
        assert.are.equal("map", logic.onLedgerTab(true, true))
    end)

    it("resets the hover and closes the bed window on another tab when the window is open", function()
        assert.are.equal("clear", logic.onLedgerTab(false, true))
    end)

    it("only resets the hover on another tab with no bed window", function()
        assert.are.equal("reset", logic.onLedgerTab(false, false))
    end)
end)
