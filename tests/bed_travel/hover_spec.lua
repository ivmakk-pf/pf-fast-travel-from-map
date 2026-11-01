local fakes = require("fakes")
local logic = require("ftm.bed_travel.logic")

local WHITE, DIM = logic.hoverColor(true), logic.hoverColor(false)

describe("bed_hover", function()
    local env, ctx, hover, ui, current, findIcon

    local function icon()
        return fakes.object({
            hovered = false,
            IsHovered = spy.new(function(self)
                return self.hovered
            end),
            SetIconColor = spy.new(function() end),
        })
    end

    local function lines(pattern)
        local n = 0
        for _, line in ipairs(env.printed) do
            if line:find(pattern) then n = n + 1 end
        end
        return n
    end

    local function ticks(n)
        for _ = 1, n do
            env.tick()
        end
    end

    before_each(function()
        env = fakes.install()
        package.loaded["ftm.bed_travel.hover"] = nil
        hover = require("ftm.bed_travel.hover")
        ctx = require("ftm.core.context").new("T")
        ctx.config = { verbose = true }
        ui = fakes.object({})
        current = icon()
        findIcon = spy.new(function()
            return current, 3
        end)
    end)
    after_each(function()
        fakes.restore()
    end)

    it("sets the dim color at the first turn, then the full color while the mouse is on the icon", function()
        hover.start(ctx, ui, findIcon)
        env.tick()
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
        current.hovered = true
        env.tick()
        assert.spy(current.SetIconColor).was.called_with(current, WHITE)
        current.hovered = false
        env.tick()
        assert.spy(current.SetIconColor).was.called(3)
        assert.are.equal(1, lines("bed hover on"))
        assert.are.equal(1, lines("bed hover off"))
    end)

    it("sets no color while the hover stays", function()
        hover.start(ctx, ui, findIcon)
        ticks(5)
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("looks the icon up from the UI manager at each turn", function()
        hover.start(ctx, ui, findIcon)
        ticks(12)
        assert.spy(findIcon).was.called(12)
        assert.spy(findIcon).was.called_with(ui)
    end)

    it("never calls the icon of an earlier turn, also when that icon still reads as valid", function()
        hover.start(ctx, ui, findIcon)
        env.tick()
        local old = current
        current = icon()
        ticks(3)
        hover.stop(ui)
        assert.spy(old.IsHovered).was.called(1)
        assert.spy(old.SetIconColor).was.called(1)
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
        assert.spy(current.SetIconColor).was.called_with(current, WHITE)
    end)

    it("goes on after one turn with no icon late in the poll", function()
        hover.start(ctx, ui, findIcon)
        ticks(29)
        current = nil
        env.tick()
        current = icon()
        env.tick()
        assert.are.equal(1, #env.loops)
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
    end)

    it("ends the poll when no icon is found for 20 turns in a row", function()
        current = nil
        hover.start(ctx, ui, findIcon)
        ticks(20)
        assert.are.equal(1, #env.loops)
        ticks(2)
        assert.are.equal(0, #env.loops)
    end)

    it("stop sets the icon of the UI manager back to white and ends the poll", function()
        hover.start(ctx, ui, findIcon)
        env.tick()
        hover.stop(ui)
        assert.spy(current.SetIconColor).was.called_with(current, WHITE)
        env.tick()
        assert.are.equal(0, #env.loops)
    end)

    it("stop with an invalid UI manager calls nothing", function()
        hover.start(ctx, ui, findIcon)
        env.tick()
        ui.destroyed = true
        assert.has_no.errors(function()
            hover.stop(ui)
        end)
        assert.spy(findIcon).was.called(1)
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("stop does not touch a destroyed icon", function()
        hover.start(ctx, ui, findIcon)
        env.tick()
        current.destroyed = true
        hover.stop(ui)
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("stop with no poll since the last stop looks nothing up", function()
        hover.stop(ui)
        assert.spy(findIcon).was_not.called()
        hover.start(ctx, ui, findIcon)
        hover.stop(ui)
        hover.stop(ui)
        assert.spy(findIcon).was.called(1)
    end)

    it("a new start ends the poll of the run before", function()
        hover.start(ctx, ui, findIcon)
        hover.start(ctx, ui, findIcon)
        env.tick()
        assert.are.equal(1, #env.loops)
    end)

    it("ends the poll with one warning when a turn throws", function()
        current.IsHovered = function()
            error("stale")
        end
        hover.start(ctx, ui, findIcon)
        ticks(2)
        assert.are.equal(1, lines("WARN bed hover: .*stale"))
        assert.are.equal(0, #env.loops)
    end)

    it("logs the poll end with the turns, the time, the slow turns, and the markers", function()
        hover.start(ctx, ui, findIcon)
        ticks(3)
        hover.stop(ui)
        assert.are.equal(1, lines("bed hover end: 3 turns, %d+ ms total, %d+ turns of 1 ms or more, 3 markers"))
    end)

    it("logs the poll end when the poll gives up", function()
        current = nil
        hover.start(ctx, ui, findIcon)
        ticks(21)
        assert.are.equal(1, lines("bed hover end: 21 turns"))
        hover.stop(ui)
        assert.are.equal(1, lines("bed hover end"))
    end)

    it("logs no poll end line without verbose", function()
        ctx.config.verbose = false
        hover.start(ctx, ui, findIcon)
        ticks(3)
        hover.stop(ui)
        assert.are.equal(0, lines("bed hover end"))
    end)

    it("traces a new bed icon in place of an earlier one, not the first icon", function()
        hover.start(ctx, ui, findIcon)
        env.tick()
        assert.are.equal(0, lines("bed icon changed"))
        current = icon()
        ticks(2)
        assert.are.equal(1, lines("bed icon changed"))
    end)

    describe("select", function()
        local GOLD = logic.iconColor(false, true)

        it("sets the gold at the next turn, and the hover changes nothing while selected", function()
            hover.start(ctx, ui, findIcon)
            env.tick()
            hover.select(true)
            env.tick()
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
            current.hovered = true
            ticks(2)
            current.hovered = false
            env.tick()
            assert.spy(current.SetIconColor).was.called(2)
        end)

        it("sets the gold at the first turn when selected before it", function()
            hover.start(ctx, ui, findIcon)
            hover.select(true)
            env.tick()
            assert.spy(current.SetIconColor).was.called(1)
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
        end)

        it("sets the hover look again at the next turn after select(false)", function()
            hover.start(ctx, ui, findIcon)
            hover.select(true)
            env.tick()
            current.hovered = true
            hover.select(false)
            env.tick()
            assert.spy(current.SetIconColor).was.called_with(current, WHITE)
            assert.spy(current.SetIconColor).was.called(2)
        end)

        it("is cleared by stop, which sets white, and a new start is not selected", function()
            hover.start(ctx, ui, findIcon)
            hover.select(true)
            env.tick()
            hover.stop(ui)
            assert.spy(current.SetIconColor).was.called_with(current, WHITE)
            hover.start(ctx, ui, findIcon)
            env.tick()
            assert.spy(current.SetIconColor).was.called_with(current, DIM)
        end)

        it("keeps the gold at a new start with no stop before it", function()
            hover.start(ctx, ui, findIcon)
            hover.select(true)
            env.tick()
            hover.start(ctx, ui, findIcon)
            env.tick()
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
            local calls = current.SetIconColor.calls
            assert.are.same(GOLD, calls[#calls].vals[2])
        end)

        it("sets the gold again within 10 turns on a new icon at the address of the old one", function()
            hover.start(ctx, ui, findIcon)
            hover.select(true)
            env.tick()
            local address = current:GetAddress()
            current = icon()
            current.GetAddress = function()
                return address
            end
            ticks(9)
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
        end)

        it("sets the gold on a new icon that comes while selected", function()
            hover.start(ctx, ui, findIcon)
            hover.select(true)
            env.tick()
            current = icon()
            env.tick()
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
        end)
    end)

    it("after a failed turn, stop sets only the icon that it looks up again", function()
        local failed = current
        failed.IsHovered = function()
            error("stale")
        end
        hover.start(ctx, ui, findIcon)
        env.tick()
        current = icon()
        hover.stop(ui)
        assert.spy(failed.SetIconColor).was_not.called()
        assert.spy(current.SetIconColor).was.called_with(current, WHITE)
    end)
end)
