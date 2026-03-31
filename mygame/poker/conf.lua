function love.conf(t)
    t.title = "Texas Hold'em Poker"
    t.identity = "texasholdem"
    t.version = "11.4"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 960
    t.window.minheight = 540
    t.window.vsync = 1  -- enable vsync to prevent flickering
    t.modules.physics = false
    t.modules.video = false
end
