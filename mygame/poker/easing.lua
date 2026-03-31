-- easing.lua - Easing functions and animation system

local Easing = {}

-- Easing functions (t = 0..1, returns 0..1)

function Easing.linear(t)
    return t
end

function Easing.easeInQuad(t)
    return t * t
end

function Easing.easeOutQuad(t)
    return t * (2 - t)
end

function Easing.easeInOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end

function Easing.easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

function Easing.easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    t = t - 1
    return 1 + 4 * t * t * t
end

function Easing.easeOutBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

function Easing.easeOutBounce(t)
    if t < 1 / 2.75 then
        return 7.5625 * t * t
    elseif t < 2 / 2.75 then
        t = t - 1.5 / 2.75
        return 7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75 then
        t = t - 2.25 / 2.75
        return 7.5625 * t * t + 0.9375
    else
        t = t - 2.625 / 2.75
        return 7.5625 * t * t + 0.984375
    end
end

function Easing.easeOutElastic(t)
    if t == 0 or t == 1 then return t end
    return math.pow(2, -10 * t) * math.sin((t - 0.075) * (2 * math.pi) / 0.3) + 1
end

function Easing.easeInExpo(t)
    if t == 0 then return 0 end
    return math.pow(2, 10 * (t - 1))
end

function Easing.easeOutExpo(t)
    if t == 1 then return 1 end
    return 1 - math.pow(2, -10 * t)
end

-- Spring-like overshoot
function Easing.spring(t)
    return 1 - math.cos(t * 4.5 * math.pi) * math.exp(-t * 6)
end

-----------------------------------------------------------
-- Animation manager
-----------------------------------------------------------
local animations = {}

--- Create a new tween animation.
-- @param id       unique string key (overwrites existing)
-- @param duration seconds
-- @param easeFn   easing function (default easeOutCubic)
-- @param onUpdate called each frame with (value 0..1, raw_t)
-- @param onDone   optional, called when finished
function Easing.tween(id, duration, easeFn, onUpdate, onDone)
    animations[id] = {
        elapsed  = 0,
        duration = duration,
        ease     = easeFn or Easing.easeOutCubic,
        update   = onUpdate,
        done     = onDone,
        finished = false,
    }
end

--- Cancel a running animation
function Easing.cancel(id)
    animations[id] = nil
end

--- Check if an animation is active
function Easing.isActive(id)
    return animations[id] ~= nil and not animations[id].finished
end

--- Get current eased value (0..1) for an animation, or 1 if done/absent
function Easing.getValue(id)
    local a = animations[id]
    if not a then return 1 end
    local t = math.min(a.elapsed / a.duration, 1)
    return a.ease(t)
end

--- Update all running animations. Call once per frame.
function Easing.update(dt)
    for id, a in pairs(animations) do
        if not a.finished then
            a.elapsed = a.elapsed + dt
            local t = math.min(a.elapsed / a.duration, 1)
            local v = a.ease(t)
            if a.update then a.update(v, t) end
            if t >= 1 then
                a.finished = true
                if a.done then a.done() end
            end
        end
    end
    -- Cleanup finished
    for id, a in pairs(animations) do
        if a.finished then animations[id] = nil end
    end
end

-----------------------------------------------------------
-- Particle system (lightweight)
-----------------------------------------------------------
local particles = {}

function Easing.spawnParticles(x, y, count, opts)
    opts = opts or {}
    local color = opts.color or {1, 0.85, 0.2}
    local life = opts.life or 1.5
    local speed = opts.speed or 120
    local size = opts.size or 4

    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local spd = speed * (0.3 + math.random() * 0.7)
        particles[#particles + 1] = {
            x = x, y = y,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd - speed * 0.3,
            life = life * (0.5 + math.random() * 0.5),
            maxLife = life,
            size = size * (0.5 + math.random() * 0.5),
            color = {color[1], color[2], color[3]},
            gravity = opts.gravity or 80,
            rotation = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 6,
        }
    end
end

function Easing.updateParticles(dt)
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles, i)
        else
            p.vy = p.vy + p.gravity * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.rotation = p.rotation + p.rotSpeed * dt
            i = i + 1
        end
    end
end

function Easing.drawParticles()
    for _, p in ipairs(particles) do
        local alpha = math.min(1, p.life / (p.maxLife * 0.3))
        local scale = p.life / p.maxLife
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha * 0.8)
        love.graphics.push()
        love.graphics.translate(p.x, p.y)
        love.graphics.rotate(p.rotation)
        local s = p.size * (0.5 + scale * 0.5)
        love.graphics.rectangle("fill", -s/2, -s/2, s, s)
        love.graphics.pop()
    end
end

function Easing.clearParticles()
    particles = {}
end

function Easing.particleCount()
    return #particles
end

-----------------------------------------------------------
-- Screen shake
-----------------------------------------------------------
local shake = {intensity = 0, duration = 0, elapsed = 0}

function Easing.startShake(intensity, duration)
    shake.intensity = intensity
    shake.duration = duration
    shake.elapsed = 0
end

function Easing.updateShake(dt)
    if shake.elapsed < shake.duration then
        shake.elapsed = shake.elapsed + dt
    end
end

function Easing.getShakeOffset()
    if shake.elapsed >= shake.duration then return 0, 0 end
    local t = 1 - shake.elapsed / shake.duration
    local i = shake.intensity * t
    return (math.random() - 0.5) * 2 * i, (math.random() - 0.5) * 2 * i
end

return Easing
