-- easing.lua - tiny easing library (Penner-style, normalized t in [0,1])
local E = {}

function E.linear(t) return t end
function E.inQuad(t) return t * t end
function E.outQuad(t) return 1 - (1 - t) * (1 - t) end
function E.inOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return 1 - (-2 * t + 2)^2 / 2
end
function E.inCubic(t) return t * t * t end
function E.outCubic(t) return 1 - (1 - t)^3 end
function E.inOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    return 1 - (-2 * t + 2)^3 / 2
end
function E.outQuart(t) return 1 - (1 - t)^4 end
function E.outQuint(t) return 1 - (1 - t)^5 end
function E.outExpo(t)
    if t >= 1 then return 1 end
    return 1 - 2^(-10 * t)
end
function E.outBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
end
function E.outElastic(t)
    local c4 = (2 * math.pi) / 3
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return 2^(-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end
function E.outBounce(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then return n1 * t * t
    elseif t < 2 / d1 then t = t - 1.5 / d1; return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then t = t - 2.25 / d1; return n1 * t * t + 0.9375
    else t = t - 2.625 / d1; return n1 * t * t + 0.984375 end
end

-- helper: tween value from a→b over duration d, using easing fn
-- usage: local tw = E.tween(0,1,0.4,E.outBack); tw:update(dt); tw.value
function E.tween(from, to, duration, fn)
    return setmetatable({
        from = from, to = to, duration = duration,
        fn = fn or E.outCubic, t = 0, value = from, done = false,
    }, {__index = {
        update = function(self, dt)
            if self.done then return end
            self.t = self.t + dt
            local k = math.min(1, self.t / self.duration)
            self.value = self.from + (self.to - self.from) * self.fn(k)
            if k >= 1 then self.done = true end
        end,
        reset = function(self, from, to)
            self.from = from or self.from
            self.to = to or self.to
            self.t = 0
            self.value = self.from
            self.done = false
        end,
    }})
end

return E
