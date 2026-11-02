local fakes = require("fakes")
local logic = require("ftm.bed_travel.logic")

local WHITE, DIM = logic.hoverColor(true), logic.hoverColor(false)
local GOLD = logic.iconColor(false, true)

describe("bed_hover", function()
    local env, ctx, hover, map, current, findIcon, now

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

    -- One map Tick, `ms` after the one before.
    local function tick(ms)
        now = now + (ms or 50) / 1000
        hover.onTick({
            get = function()
                return map
            end,
        }, findIcon, now)
    end

    local function ticks(n, ms)
        for _ = 1, n do
            tick(ms)
        end
    end

    before_each(function()
        env = fakes.install()
        package.loaded["ftm.bed_travel.hover"] = nil
        hover = require("ftm.bed_travel.hover")
        ctx = require("ftm.core.context").new("T")
        ctx.config = { verbose = true }
        hover.install(ctx)
        map = fakes.object({})
        now = 100
        current = icon()
        findIcon = spy.new(function()
            return current, 1
        end)
    end)
    after_each(function()
        fakes.restore()
    end)

    it("sets the dim color at the first check, then the full color while the mouse is on the icon", function()
        tick()
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
        current.hovered = true
        tick()
        assert.spy(current.SetIconColor).was.called_with(current, WHITE)
        current.hovered = false
        tick()
        assert.spy(current.SetIconColor).was.called(3)
        assert.are.equal(1, lines("bed hover on"))
        assert.are.equal(1, lines("bed hover off"))
    end)

    it("checks at most each 50 ms, whatever the frame rate", function()
        ticks(30, 7) -- 210 ms at about 144 frames a second
        assert.spy(findIcon).was.called(4)
        assert.spy(findIcon).was.called_with(map)
    end)

    it("sets no color while the hover stays", function()
        ticks(5)
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("sets the tint again each 10 checks, for a new icon at the address of the old one", function()
        ticks(10)
        assert.spy(current.SetIconColor).was.called(2)
    end)

    it("does nothing while the map has no bed icon, and goes on within 1 s when it comes", function()
        current = nil
        ticks(30)
        current = icon()
        ticks(20)
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
    end)

    it("checks only each 1 s while the map has no bed icon, so the walk of the markers stays rare", function()
        current = nil
        ticks(60) -- 3 s at 50 ms
        assert.spy(findIcon).was.called(3)
    end)

    it("goes back to a check each 50 ms after the icon is found", function()
        current = nil
        tick()
        current = icon()
        ticks(20)
        local calls = #findIcon.calls
        ticks(4)
        assert.are.equal(calls + 4, #findIcon.calls)
    end)

    it("starts again at a new map: the first check sets the color", function()
        tick()
        map = fakes.object({})
        tick()
        assert.spy(current.SetIconColor).was.called(2)
    end)

    it("traces a new bed icon in place of an earlier one, not the first icon", function()
        tick()
        assert.are.equal(0, lines("bed icon changed"))
        current = icon()
        tick()
        assert.are.equal(1, lines("bed icon changed"))
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
    end)

    it("logs one warning and checks no more after an error, until the next reset", function()
        current.IsHovered = function()
            error("stale")
        end
        ticks(3)
        assert.are.equal(1, lines("WARN bed hover: .*stale"))
        assert.spy(findIcon).was.called(1)
        hover.reset()
        current = icon()
        tick()
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("reset calls no game object and logs the ticks, the checks, and the check time", function()
        ticks(3, 10)
        ticks(2)
        hover.reset()
        assert.spy(current.SetIconColor).was.called(1)
        assert.are.equal(
            1,
            lines("bed hover end: 5 ticks, 3 checks, %d+ ms total, %d+ checks of 1 ms or more, 1 markers")
        )
    end)

    it("reset with no tick since the last reset logs nothing", function()
        hover.reset()
        tick()
        hover.reset()
        hover.reset()
        assert.are.equal(1, lines("bed hover end"))
    end)

    it("logs no end line without verbose", function()
        ctx.config.verbose = false
        ticks(3)
        hover.reset()
        assert.are.equal(0, lines("bed hover end"))
    end)

    it("after a reset, the first check sets the color again", function()
        current.hovered = true
        tick()
        hover.reset()
        current.hovered = false
        tick()
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
    end)

    describe("select", function()
        it("sets the gold at the next check, and the hover changes nothing while selected", function()
            tick()
            hover.select(true)
            tick()
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
            current.hovered = true
            ticks(2)
            current.hovered = false
            tick()
            assert.spy(current.SetIconColor).was.called(2)
        end)

        it("sets the hover look again at the next check after select(false)", function()
            hover.select(true)
            tick()
            current.hovered = true
            hover.select(false)
            tick()
            assert.spy(current.SetIconColor).was.called_with(current, WHITE)
        end)

        it("is cleared by reset", function()
            hover.select(true)
            tick()
            hover.reset()
            tick()
            assert.spy(current.SetIconColor).was.called_with(current, DIM)
        end)

        it("sets the gold on a new icon that comes while selected", function()
            hover.select(true)
            tick()
            current = icon()
            tick()
            assert.spy(current.SetIconColor).was.called_with(current, GOLD)
        end)
    end)
end)
