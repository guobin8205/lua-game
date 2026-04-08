
local MyApp = class("MyApp", cc.load("mvc").AppBase)

function MyApp:onCreate()
    math.randomseed(os.time())
end

function MyApp:run()
    -- 启动 AI 聊天界面
    local ok, err = pcall(function()
        local ChatScene = require("app.views.ChatScene")
        cc.Director:getInstance():replaceScene(ChatScene.new())
    end)
    if not ok then
        print("[MyApp] ERROR: " .. tostring(err))
    end
end

return MyApp
