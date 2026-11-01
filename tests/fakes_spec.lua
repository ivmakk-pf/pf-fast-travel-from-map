local fakes = require("fakes")

describe("fakes", function()
    local env
    before_each(function()
        env = fakes.install()
    end)
    after_each(function()
        fakes.restore()
    end)

    it("RegisterHook keeps the callback and returns new ids", function()
        local fn = function() end
        local pre, post = RegisterHook("/Script/X.Y:F", fn)
        local pre2 = RegisterHook("/Script/X.Y:G", fn)
        assert.are.equal(fn, env.hooks["/Script/X.Y:F"])
        assert.are_not.equal(pre, post)
        assert.are_not.equal(pre, pre2)
    end)

    it("RegisterHook fails for a path with the failing suffix", function()
        fakes.restore()
        env = fakes.install({ failHook = ":G" })
        assert.has_error(function()
            RegisterHook("/Script/X.Y:G", function() end)
        end)
        assert.has_no_error(function()
            RegisterHook("/Script/X.Y:F", function() end)
        end)
    end)

    it("NotifyOnNewObject keeps the watcher of a class", function()
        local fn = function() end
        NotifyOnNewObject("/Script/X.C", fn)
        assert.are.equal(fn, env.watchers["/Script/X.C"])
    end)

    it("ExecuteInGameThread runs the work at once", function()
        local ran = false
        ExecuteInGameThread(function()
            ran = true
        end)
        assert.is_true(ran)
    end)

    it("tick runs each loop once, and a loop that returns true ends", function()
        local a, b = 0, 0
        LoopAsync(50, function()
            a = a + 1
            return false
        end)
        LoopAsync(50, function()
            b = b + 1
            return true
        end)
        env.tick()
        env.tick()
        assert.are.equal(2, a)
        assert.are.equal(1, b)
    end)

    it("print keeps each line", function()
        print("hello\n")
        assert.are.same({ "hello\n" }, env.printed)
    end)

    it("object gives a valid object with an address, a class name, and an object name", function()
        local o = fakes.object({ class = "BP_X_C", name = "BP_X_1", Size = 3 })
        local other = fakes.object()
        assert.is_true(o:IsValid())
        assert.are_not.equal(o:GetAddress(), other:GetAddress())
        assert.are.equal("BP_X_C", o:GetClass():GetFName():ToString())
        assert.are.equal("BP_X_1", o:GetFName():ToString())
        assert.are.equal(3, o.Size)
        o.destroyed = true
        assert.is_false(o:IsValid())
    end)

    it("param wraps a value for get and set", function()
        local p = fakes.param(4)
        assert.are.equal(4, p:get())
        p:set(5)
        assert.are.equal(5, p:get())
    end)

    it("restore puts back the globals of before", function()
        fakes.restore()
        assert.is_nil(rawget(_G, "RegisterHook"))
        env = fakes.install()
    end)
end)
