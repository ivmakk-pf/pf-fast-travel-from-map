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

describe("hoverChange", function()
    it("sets the color at the first turn", function()
        assert.are.equal(0.75, logic.hoverChange(nil, false).R)
        assert.are.equal(1, logic.hoverChange(nil, true).R)
    end)

    it("sets the color when the hover changes", function()
        assert.are.equal(1, logic.hoverChange(false, true).R)
        assert.are.equal(0.75, logic.hoverChange(true, false).R)
    end)

    it("sets nothing when the hover stays", function()
        assert.are.equal(nil, logic.hoverChange(true, true))
        assert.are.equal(nil, logic.hoverChange(false, false))
    end)
end)

describe("hoverTurn", function()
    it("looks the icon up at each turn without an icon", function()
        for _, turn in ipairs({ 1, 2, 3, 61, 200 }) do
            assert.are.equal("find", logic.hoverTurn(turn, false))
        end
    end)

    it("looks the icon up again each 10 turns for the first 60 turns", function()
        for _, turn in ipairs({ 10, 20, 30, 40, 50, 60 }) do
            assert.are.equal("find", logic.hoverTurn(turn, true))
        end
    end)

    it("keeps the icon at the other turns, and after turn 60", function()
        for _, turn in ipairs({ 1, 9, 11, 59, 61, 70, 120 }) do
            assert.are.equal("keep", logic.hoverTurn(turn, true))
        end
    end)
end)

describe("hoverGiveUp", function()
    it("keeps looking for an icon for the first 20 turns (1 s)", function()
        assert.is_false(logic.hoverGiveUp(1))
        assert.is_false(logic.hoverGiveUp(20))
    end)

    it("gives up after turn 20", function()
        assert.is_true(logic.hoverGiveUp(21))
    end)
end)

describe("onLedgerTab", function()
    it("arms the map hook and starts the hover on the map tab", function()
        assert.are.equal("map", logic.onLedgerTab(true, false))
        assert.are.equal("map", logic.onLedgerTab(true, true))
    end)

    it("stops the hover and closes the bed window on another tab when the window is open", function()
        assert.are.equal("clear", logic.onLedgerTab(false, true))
    end)

    it("only stops the hover on another tab with no bed window", function()
        assert.are.equal("stop", logic.onLedgerTab(false, false))
    end)
end)
