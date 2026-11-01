local fakes = require("fakes")
local logic = require("ftm.bed_travel.logic")

local WHITE, DIM = logic.hoverColor(true), logic.hoverColor(false)

describe("bed_hover", function()
    local env, ctx, hover, current, findIcon

    local function icon()
        return fakes.object({
            hovered = false,
            IsHovered = function(self)
                return self.hovered
            end,
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

    before_each(function()
        env = fakes.install()
        package.loaded["ftm.bed_travel.hover"] = nil
        hover = require("ftm.bed_travel.hover")
        ctx = require("ftm.core.context").new("T")
        ctx.config = { verbose = true }
        current = icon()
        findIcon = spy.new(function()
            return current
        end)
    end)
    after_each(function()
        fakes.restore()
    end)

    it("sets the dim color at the first turn, then the full color while the mouse is on the icon", function()
        hover.start(ctx, findIcon)
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
        hover.start(ctx, findIcon)
        for _ = 1, 5 do
            env.tick()
        end
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("passes the turn number to the find, and looks up a kept icon only each 10 turns", function()
        hover.start(ctx, findIcon)
        for _ = 1, 12 do
            env.tick()
        end
        assert.spy(findIcon).was.called(2)
        assert.spy(findIcon).was.called_with(1)
        assert.spy(findIcon).was.called_with(10)
    end)

    it("takes a new icon after a travel and sets the old one back to white", function()
        hover.start(ctx, findIcon)
        env.tick()
        local old = current
        current = icon()
        for _ = 2, 10 do
            env.tick()
        end
        assert.spy(old.SetIconColor).was.called_with(old, WHITE)
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
    end)

    it("looks again at once when the icon is destroyed", function()
        hover.start(ctx, findIcon)
        env.tick()
        current.destroyed = true
        current = icon()
        env.tick()
        assert.spy(findIcon).was.called(2)
        assert.spy(current.SetIconColor).was.called_with(current, DIM)
    end)

    it("ends the poll when no icon is found for 20 turns", function()
        current = nil
        hover.start(ctx, findIcon)
        for _ = 1, 20 do
            env.tick()
        end
        assert.are.equal(1, #env.loops)
        env.tick()
        env.tick()
        assert.are.equal(0, #env.loops)
    end)

    it("stop sets the icon back to white and ends the poll", function()
        hover.start(ctx, findIcon)
        env.tick()
        hover.stop()
        assert.spy(current.SetIconColor).was.called_with(current, WHITE)
        env.tick()
        assert.are.equal(0, #env.loops)
    end)

    it("stop does not touch a destroyed icon", function()
        hover.start(ctx, findIcon)
        env.tick()
        current.destroyed = true
        hover.stop()
        assert.spy(current.SetIconColor).was.called(1)
    end)

    it("a new start ends the poll of the run before", function()
        hover.start(ctx, findIcon)
        hover.start(ctx, findIcon)
        env.tick()
        assert.are.equal(1, #env.loops)
    end)

    it("ends the poll with one warning when a turn throws", function()
        current.IsHovered = function()
            error("stale")
        end
        hover.start(ctx, findIcon)
        env.tick()
        env.tick()
        assert.are.equal(1, lines("WARN bed hover: .*stale"))
        assert.are.equal(0, #env.loops)
    end)
end)
