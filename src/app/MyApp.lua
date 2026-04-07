
local MyApp = class("MyApp", cc.load("mvc").AppBase)

function MyApp:onCreate()
    math.randomseed(os.time())
end

function MyApp:run()
    -- 启动 AI 聊天界面
    local ChatScene = require("app.views.ChatScene")
    display.replaceScene(ChatScene.new())
end

return MyApp
