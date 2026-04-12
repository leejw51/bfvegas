-- aiui.lua - "Ask Wiki" prompt panel, loading state, and node viewer modal
local Render = require("render")
local AI     = require("ai")
local Graph  = require("graph")
local Bot    = require("bot")
local Export = require("export")
local Settings = require("settings")

local AIUI = {}
AIUI.mode = nil          -- nil | "prompt" | "loading" | "view"
AIUI.text = ""
AIUI.cursor = 0
AIUI.cursorBlink = 0
AIUI.t = 0
AIUI.viewNode = nil
AIUI.pendingId = nil
AIUI.imageCache = {}
AIUI.scroll = 0
AIUI.maxScroll = 0
AIUI.copyTextBtn = nil
AIUI.copyImgBtn = nil
AIUI.copyFlash = 0
AIUI.copyFlashTarget = nil

function AIUI.isOpen() return AIUI.mode ~= nil end

function AIUI.openPrompt()
    AIUI.mode = "prompt"
    AIUI.text = ""
    AIUI.cursor = 0
    AIUI.cursorBlink = 0
    love.keyboard.setKeyRepeat(true)
end

AIUI.exportBtns = nil

function AIUI.openExport()
    AIUI.mode = "export"
end

AIUI.setupText = ""
AIUI.setupCursor = 0
AIUI.setupSaveBtn = nil
AIUI.setupCancelBtn = nil
AIUI.setupMask = true

function AIUI.openSetup()
    AIUI.mode = "setup"
    AIUI.setupText = Settings.getGrokKey() or ""
    AIUI.setupCursor = #AIUI.setupText
    AIUI.cursorBlink = 0
    love.keyboard.setKeyRepeat(true)
end

local function saveSetup()
    Settings.setGrokKey(AIUI.setupText)
    local ok, err = Settings.save()
    if ok then
        Bot.say("Settings saved to data/info.json", 4)
    else
        Bot.say("Save failed: " .. tostring(err), 6)
    end
    AIUI.close()
end

function AIUI.openView(node)
    if not node then return end
    AIUI.mode = "view"
    AIUI.viewNode = node
    AIUI.scroll = 0
    AIUI.maxScroll = 0
end

function AIUI.wheelmoved(dy)
    if AIUI.mode ~= "view" then return false end
    AIUI.scroll = math.max(0, math.min(AIUI.maxScroll, AIUI.scroll - dy * 30))
    return true
end

function AIUI.close()
    AIUI.mode = nil
    AIUI.viewNode = nil
    love.keyboard.setKeyRepeat(false)
end

function AIUI.update(dt)
    AIUI.t = AIUI.t + dt
    AIUI.cursorBlink = (AIUI.cursorBlink + dt) % 1
    if AIUI.copyFlash > 0 then
        AIUI.copyFlash = AIUI.copyFlash - dt
        if AIUI.copyFlash <= 0 then AIUI.copyFlashTarget = nil end
    end
end

local function pointIn(b, x, y)
    return b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
end

local function copyImageToClipboard(path)
    if not path or path == "" then return false end
    if love.system.getOS() == "OS X" then
        local q = path:gsub('"', '\\"')
        local cmd = string.format(
            'osascript -e \'set the clipboard to (read (POSIX file "%s") as «class PNGf»)\' >/dev/null 2>&1',
            q
        )
        return os.execute(cmd) == 0 or os.execute(cmd) == true
    end
    love.system.setClipboardText(path)
    return true
end

function AIUI.mousepressed(x, y)
    if AIUI.mode == "setup" then
        if pointIn(AIUI.setupSaveBtn, x, y) then
            saveSetup()
            return true
        end
        if pointIn(AIUI.setupCancelBtn, x, y) then
            AIUI.close()
            return true
        end
        return true
    end
    if AIUI.mode == "export" then
        if AIUI.exportBtns then
            for _, b in ipairs(AIUI.exportBtns) do
                if pointIn(b, x, y) then
                    local ok, pathOrErr, count = Export.run(b.format)
                    if ok then
                        Bot.say(string.format("Exported %d nodes → %s", count or 0, pathOrErr), 5)
                    else
                        Bot.say("Export failed: " .. tostring(pathOrErr), 6)
                    end
                    AIUI.close()
                    return true
                end
            end
        end
        return false
    end
    if AIUI.mode ~= "view" or not AIUI.viewNode then return false end
    if pointIn(AIUI.copyTextBtn, x, y) then
        love.system.setClipboardText(AIUI.viewNode.body or "")
        AIUI.copyFlash = 1.2
        AIUI.copyFlashTarget = "text"
        Bot.say("Copied text to clipboard.", 2)
        return true
    end
    if pointIn(AIUI.copyImgBtn, x, y) then
        if copyImageToClipboard(AIUI.viewNode.image) then
            AIUI.copyFlash = 1.2
            AIUI.copyFlashTarget = "image"
            Bot.say("Copied image to clipboard.", 2)
        else
            Bot.say("No image to copy.", 2)
        end
        return true
    end
    return false
end

local function utf8StepBack(s, i)
    while i > 1 and s:byte(i) and s:byte(i) >= 128 and s:byte(i) < 192 do
        i = i - 1
    end
    return i
end

function AIUI.submit(Mindmap)
    if AIUI.mode ~= "prompt" or #AIUI.text == 0 then return end
    local question = AIUI.text
    local w, h = love.graphics.getDimensions()
    local wx, wy = Mindmap.screenToWorld(w/2, h/2, w, h)
    local pid = Mindmap.selected and Mindmap.selected.id or nil
    local node = Graph.create("Thinking…", pid, wx, wy)
    node.body = "_Wiki is thinking about: " .. question .. "_"
    Graph.save(node)
    Mindmap.selected = node
    AIUI.pendingId = node.id
    AIUI.mode = "loading"
    Bot.say("Asking the AI…", 6)

    local ok = AI.ask(question, node.id, function(result)
        local id = AIUI.pendingId
        AIUI.pendingId = nil
        AIUI.mode = nil
        local n = Graph.nodes[id]
        if not n then return end
        if not result.ok then
            n.title = "AI error"
            n.body = "_" .. tostring(result.error or "unknown") .. "_"
            Graph.save(n)
            Bot.say("AI failed: " .. tostring(result.error), 6)
            return
        end
        if result.title and #result.title > 0 then n.title = result.title end
        if result.body  and #result.body  > 0 then n.body  = result.body  end
        if result.image and result.image ~= "" then
            n.image = result.image
            AIUI.imageCache[n.id] = nil
        end
        Graph.save(n)
        Bot.say("Done! Click 👁 View to read it.", 5)
    end)
    if not ok then
        AIUI.mode = nil
        Bot.say("AI is already working on something.", 4)
    end
end

function AIUI.textinput(t)
    if AIUI.mode == "prompt" then
        AIUI.text = AIUI.text:sub(1, AIUI.cursor) .. t .. AIUI.text:sub(AIUI.cursor + 1)
        AIUI.cursor = AIUI.cursor + #t
    elseif AIUI.mode == "setup" then
        AIUI.setupText = AIUI.setupText:sub(1, AIUI.setupCursor) .. t .. AIUI.setupText:sub(AIUI.setupCursor + 1)
        AIUI.setupCursor = AIUI.setupCursor + #t
    end
end

function AIUI.keypressed(key, Mindmap)
    if AIUI.mode == "prompt" then
        if key == "escape" then AIUI.close()
        elseif key == "return" then AIUI.submit(Mindmap)
        elseif key == "backspace" then
            if AIUI.cursor > 0 then
                local i = utf8StepBack(AIUI.text, AIUI.cursor)
                AIUI.text = AIUI.text:sub(1, i - 1) .. AIUI.text:sub(AIUI.cursor + 1)
                AIUI.cursor = i - 1
            end
        elseif key == "left"  then AIUI.cursor = math.max(0, AIUI.cursor - 1)
        elseif key == "right" then AIUI.cursor = math.min(#AIUI.text, AIUI.cursor + 1)
        end
    elseif AIUI.mode == "setup" then
        if key == "escape" then AIUI.close()
        elseif key == "return" or key == "kpenter" then saveSetup()
        elseif key == "backspace" then
            if AIUI.setupCursor > 0 then
                local i = utf8StepBack(AIUI.setupText, AIUI.setupCursor)
                AIUI.setupText = AIUI.setupText:sub(1, i - 1) .. AIUI.setupText:sub(AIUI.setupCursor + 1)
                AIUI.setupCursor = i - 1
            end
        elseif key == "left"  then AIUI.setupCursor = math.max(0, AIUI.setupCursor - 1)
        elseif key == "right" then AIUI.setupCursor = math.min(#AIUI.setupText, AIUI.setupCursor + 1)
        elseif key == "home"  then AIUI.setupCursor = 0
        elseif key == "end"   then AIUI.setupCursor = #AIUI.setupText
        elseif key == "tab"   then AIUI.setupMask = not AIUI.setupMask
        end
    elseif AIUI.mode == "export" then
        if key == "escape" then AIUI.close() end
    elseif AIUI.mode == "view" then
        if key == "escape" then AIUI.close()
        elseif key == "down"     then AIUI.scroll = math.min(AIUI.maxScroll, AIUI.scroll + 30)
        elseif key == "up"       then AIUI.scroll = math.max(0, AIUI.scroll - 30)
        elseif key == "pagedown" then AIUI.scroll = math.min(AIUI.maxScroll, AIUI.scroll + 240)
        elseif key == "pageup"   then AIUI.scroll = math.max(0, AIUI.scroll - 240)
        elseif key == "home"     then AIUI.scroll = 0
        elseif key == "end"      then AIUI.scroll = AIUI.maxScroll
        end
    end
end

local function loadImage(node)
    if not node or not node.image or node.image == "" then return nil end
    if AIUI.imageCache[node.id] then return AIUI.imageCache[node.id] end
    -- read raw bytes via io.open (file lives in source dir, written by AI)
    local f = io.open(node.image, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local ok, fd = pcall(love.filesystem.newFileData, data, node.image)
    if not ok then return nil end
    local ok2, imgData = pcall(love.image.newImageData, fd)
    if not ok2 then return nil end
    local ok3, img = pcall(love.graphics.newImage, imgData)
    if not ok3 then return nil end
    AIUI.imageCache[node.id] = img
    return img
end

function AIUI.draw(w, h)
    if not AIUI.mode then return end
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if AIUI.mode == "prompt" then
        local pw, ph = math.min(720, w - 80), 230
        local px, py = (w - pw)/2, (h - ph)/2
        Render.card(px, py, pw, ph, 18, Render.colors.panel, Render.colors.panelEdge, true)

        Render.setColor(Render.colors.accent)
        love.graphics.setFont(Render.font("large"))
        love.graphics.print("✨ Ask Wiki anything", px + 24, py + 18)

        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.printf("Enter to generate · Esc to cancel", px + 24, py + 26, pw - 48, "right")

        local ix, iy, iw, ih = px + 24, py + 78, pw - 48, 90
        love.graphics.setColor(0.05, 0.07, 0.14, 0.95)
        love.graphics.rectangle("fill", ix, iy, iw, ih, 12, 12)
        love.graphics.setColor(Render.colors.accent[1], Render.colors.accent[2], Render.colors.accent[3], 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", ix, iy, iw, ih, 12, 12)

        local font = Render.font("medium")
        love.graphics.setFont(font)
        if #AIUI.text == 0 then
            Render.setColor(Render.colors.textDim)
            love.graphics.print("e.g. How do neural networks learn?", ix + 16, iy + 18)
        else
            Render.setColor(Render.colors.text)
            love.graphics.printf(AIUI.text, ix + 16, iy + 18, iw - 32, "left")
        end
        if AIUI.cursorBlink < 0.55 then
            local before = AIUI.text:sub(1, AIUI.cursor)
            local cw = font:getWidth(before)
            Render.setColor(Render.colors.accent)
            love.graphics.setLineWidth(2)
            love.graphics.line(ix + 16 + cw, iy + 16, ix + 16 + cw, iy + 16 + font:getHeight())
        end

    elseif AIUI.mode == "setup" then
        local pw, ph = math.min(720, w - 80), 300
        local px, py = (w - pw)/2, (h - ph)/2
        Render.card(px, py, pw, ph, 18, Render.colors.panel, Render.colors.panelEdge, true)

        Render.setColor(Render.colors.accent)
        love.graphics.setFont(Render.font("large"))
        love.graphics.print("⚙ Settings", px + 24, py + 18)

        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.printf("Enter to save · Esc to cancel · Tab toggles mask", px + 24, py + 26, pw - 48, "right")

        Render.setColor(Render.colors.text)
        love.graphics.setFont(Render.font("small"))
        love.graphics.print("GROK_API_KEY", px + 24, py + 68)
        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.print("overrides environment variable when set · stored in data/info.json", px + 24, py + 88)

        local ix, iy, iw, ih = px + 24, py + 110, pw - 48, 54
        love.graphics.setColor(0.05, 0.07, 0.14, 0.95)
        love.graphics.rectangle("fill", ix, iy, iw, ih, 12, 12)
        love.graphics.setColor(Render.colors.accent[1], Render.colors.accent[2], Render.colors.accent[3], 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", ix, iy, iw, ih, 12, 12)

        local display = AIUI.setupText
        if AIUI.setupMask then display = string.rep("•", #AIUI.setupText) end
        local font = Render.font("medium")
        love.graphics.setFont(font)
        if #AIUI.setupText == 0 then
            Render.setColor(Render.colors.textDim)
            love.graphics.print("xai-…", ix + 16, iy + 16)
        else
            Render.setColor(Render.colors.text)
            love.graphics.print(display, ix + 16, iy + 16)
        end
        if AIUI.cursorBlink < 0.55 then
            local before = display:sub(1, AIUI.setupMask and AIUI.setupCursor or AIUI.setupCursor)
            if AIUI.setupMask then before = string.rep("•", AIUI.setupCursor) end
            local cw = font:getWidth(before)
            Render.setColor(Render.colors.accent)
            love.graphics.setLineWidth(2)
            love.graphics.line(ix + 16 + cw, iy + 14, ix + 16 + cw, iy + 14 + font:getHeight())
        end

        local btnW, btnH, gap = 120, 40, 12
        local by = py + ph - btnH - 24
        local saveX = px + pw - 24 - btnW
        local cancelX = saveX - gap - btnW
        AIUI.setupSaveBtn = { x = saveX, y = by, w = btnW, h = btnH }
        AIUI.setupCancelBtn = { x = cancelX, y = by, w = btnW, h = btnH }

        Render.card(saveX, by, btnW, btnH, 10, {0.20, 0.40, 0.30, 0.95}, Render.colors.panelEdge, false)
        Render.setColor(Render.colors.text)
        love.graphics.setFont(Render.font("medium"))
        love.graphics.printf("Save", saveX, by + 9, btnW, "center")

        Render.card(cancelX, by, btnW, btnH, 10, {0.13, 0.17, 0.26, 0.94}, Render.colors.panelEdge, false)
        Render.setColor(Render.colors.text)
        love.graphics.printf("Cancel", cancelX, by + 9, btnW, "center")

    elseif AIUI.mode == "export" then
        local pw, ph = math.min(560, w - 80), 240
        local px, py = (w - pw)/2, (h - ph)/2
        Render.card(px, py, pw, ph, 18, Render.colors.panel, Render.colors.panelEdge, true)
        Render.setColor(Render.colors.accent)
        love.graphics.setFont(Render.font("large"))
        love.graphics.printf("Export wiki", px, py + 22, pw, "center")
        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.printf("Choose a format · Esc to cancel", px, py + 56, pw, "center")

        local formats = { {"PDF","pdf"}, {"Markdown","md"}, {"CSV","csv"}, {"JSONL","jsonl"} }
        local btnW, btnH, gap = 110, 44, 12
        local total = #formats * btnW + (#formats - 1) * gap
        local startX = px + (pw - total) / 2
        local by = py + 110
        AIUI.exportBtns = {}
        for i, f in ipairs(formats) do
            local bx = startX + (i - 1) * (btnW + gap)
            local b = { x = bx, y = by, w = btnW, h = btnH, format = f[2], label = f[1] }
            AIUI.exportBtns[i] = b
            Render.card(bx, by, btnW, btnH, 10, {0.13, 0.17, 0.26, 0.94}, Render.colors.panelEdge, false)
            Render.setColor(Render.colors.text)
            love.graphics.setFont(Render.font("medium"))
            love.graphics.printf(f[1], bx, by + 10, btnW, "center")
        end
        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.printf("output → data/exports/wiki.<ext>", px, py + ph - 30, pw, "center")

    elseif AIUI.mode == "loading" then
        Render.setColor(Render.colors.accent)
        love.graphics.setFont(Render.font("large"))
        local dots = string.rep(".", math.floor(AIUI.t * 3) % 4)
        love.graphics.printf("Wiki is thinking" .. dots, 0, h/2 - 24, w, "center")
        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("small"))
        love.graphics.printf("generating title, body, and image…", 0, h/2 + 18, w, "center")

    elseif AIUI.mode == "view" and AIUI.viewNode then
        local node = AIUI.viewNode
        local pw, ph = math.min(860, w - 60), math.min(660, h - 60)
        local px, py = (w - pw)/2, (h - ph)/2
        Render.card(px, py, pw, ph, 18, Render.colors.panel, Render.colors.panelEdge, true)

        local hasImage = node.image and node.image ~= ""
        local btnW, btnH = 96, 26
        local gap = 8
        local rightEdge = px + pw - 24
        AIUI.copyTextBtn = nil
        AIUI.copyImgBtn = nil
        local bx = rightEdge
        if hasImage then
            bx = bx - btnW
            AIUI.copyImgBtn = { x = bx, y = py + 18, w = btnW, h = btnH }
            bx = bx - gap
        end
        bx = bx - btnW
        AIUI.copyTextBtn = { x = bx, y = py + 18, w = btnW, h = btnH }

        local titleRight = AIUI.copyTextBtn.x - 12
        Render.setColor(Render.colors.accent)
        love.graphics.setFont(Render.font("large"))
        love.graphics.printf(node.title or "Untitled", px + 24, py + 18, titleRight - (px + 24), "left")

        local function drawBtn(b, label, flashKey)
            local flashing = AIUI.copyFlash > 0 and AIUI.copyFlashTarget == flashKey
            local fill = flashing and {0.20, 0.50, 0.30, 0.95} or {0.13, 0.17, 0.26, 0.94}
            Render.card(b.x, b.y, b.w, b.h, 8, fill, Render.colors.panelEdge, false)
            Render.setColor(Render.colors.text)
            love.graphics.setFont(Render.font("small"))
            love.graphics.printf(flashing and "Copied!" or label, b.x, b.y + 6, b.w, "center")
        end
        drawBtn(AIUI.copyTextBtn, "Copy Text", "text")
        if AIUI.copyImgBtn then drawBtn(AIUI.copyImgBtn, "Copy Image", "image") end

        Render.setColor(Render.colors.textDim)
        love.graphics.setFont(Render.font("tiny"))
        love.graphics.printf("Esc to close", px + 24, py + 48, pw - 48, "right")
        love.graphics.setColor(Render.colors.panelEdge)
        love.graphics.setLineWidth(1)
        love.graphics.line(px + 24, py + 60, px + pw - 24, py + 60)

        local contentTop = py + 72
        local contentBottom = py + ph - 24
        local contentH = contentBottom - contentTop
        love.graphics.setScissor(px + 24, contentTop, pw - 48, contentH)

        local cursorY = contentTop - AIUI.scroll
        local startY = cursorY

        local img = loadImage(node)
        if img then
            local iw, ih = img:getDimensions()
            local maxW, maxH = pw - 48, 300
            local s = math.min(maxW / iw, maxH / ih)
            local dw, dh = iw * s, ih * s
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, px + (pw - dw)/2, cursorY, 0, s, s)
            cursorY = cursorY + dh + 14
        end

        local bodyFont = Render.font("body")
        Render.setColor(Render.colors.text)
        love.graphics.setFont(bodyFont)
        local bx = px + 28
        local bw = pw - 56
        local body = node.body or ""
        local _, lines = bodyFont:getWrap(body, bw)
        love.graphics.printf(body, bx, cursorY, bw, "left")
        cursorY = cursorY + #lines * bodyFont:getHeight()

        love.graphics.setScissor()

        local totalH = cursorY - startY
        AIUI.maxScroll = math.max(0, totalH - contentH)
        if AIUI.scroll > AIUI.maxScroll then AIUI.scroll = AIUI.maxScroll end

        if AIUI.maxScroll > 0 then
            local trackX = px + pw - 14
            local trackY = contentTop
            local trackH = contentH
            love.graphics.setColor(1, 1, 1, 0.08)
            love.graphics.rectangle("fill", trackX, trackY, 4, trackH, 2, 2)
            local thumbH = math.max(24, trackH * (contentH / totalH))
            local thumbY = trackY + (trackH - thumbH) * (AIUI.scroll / AIUI.maxScroll)
            Render.setColor(Render.colors.accent)
            love.graphics.rectangle("fill", trackX, thumbY, 4, thumbH, 2, 2)
        end
    end
end

return AIUI
