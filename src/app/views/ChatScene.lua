--[[
    ChatScene.lua - 类似微信的 AI 聊天界面

    功能：
    - 消息气泡显示（用户右侧、AI左侧）
    - 底部输入框 + 发送按钮
    - 流式输出实时显示
    - 持续对话（保持上下文）
    - 滚动消息列表

    使用方式：
        local ChatScene = require("app.views.ChatScene")
        display.replaceScene(ChatScene.new())
]]

local ChatScene = class("ChatScene", function()
    return display.newScene("ChatScene")
end)

-- 消息类型
local MSG_TYPE = {
    USER = 1,       -- 用户消息
    AI = 2,         -- AI 消息
    SYSTEM = 3      -- 系统消息
}

-- 颜色配置
local COLORS = {
    bg = cc.c3b(240, 240, 240),                    -- 背景色
    userBubble = cc.c3b(0, 150, 136),              -- 用户气泡（微信绿）
    aiBubble = cc.c3b(255, 255, 255),              -- AI 气泡（白色）
    userText = cc.c3b(255, 255, 255),              -- 用户文字
    aiText = cc.c3b(51, 51, 51),                   -- AI 文字
    systemText = cc.c3b(128, 128, 128),            -- 系统文字
    inputBg = cc.c3b(255, 255, 255),               -- 输入框背景
    sendBtn = cc.c3b(0, 150, 136),                 -- 发送按钮
    sendBtnDisabled = cc.c3b(180, 180, 180),       -- 发送按钮禁用
}

-- 尺寸配置
local SIZES = {
    bubblePaddingX = 15,
    bubblePaddingY = 10,
    bubbleMaxWidth = display.width * 0.65,
    bubbleRadius = 8,
    messageSpacing = 15,
    inputHeight = 50,
    inputPadding = 10,
    scrollMargin = 20,
}

function ChatScene:ctor()
    self.messages = {}          -- 消息列表
    self.messageNodes = {}      -- 消息节点列表
    self.isGenerating = false   -- AI 是否正在生成
    self.currentAIMsg = nil     -- 当前正在生成的 AI 消息

    self:initUI()
    self:initLLM()
end

function ChatScene:onEnter()
end

function ChatScene:onExit()
    -- 释放 LLM 资源
    local llm = require("app.modules.LLM")
    llm.release()
end

-- ==================== UI 初始化 ====================

function ChatScene:initUI()
    local winSize = display.size

    -- 背景
    local bg = cc.LayerColor:create(COLORS.bg)
    self:addChild(bg)

    -- 标题栏
    self.titleBar = self:createTitleBar()
    self:addChild(self.titleBar)

    -- 消息滚动区域
    self.scrollArea = self:createScrollArea()
    self:addChild(self.scrollArea)

    -- 底部输入区域
    self.inputArea = self:createInputArea()
    self:addChild(self.inputArea)
end

function ChatScene:createTitleBar()
    local winSize = display.size
    local titleHeight = 50

    local bar = cc.Node:create()
    bar:setContentSize(winSize.width, titleHeight)
    bar:setPosition(0, winSize.height - titleHeight)

    -- 背景色
    local bg = cc.LayerColor:create(cc.c4b(255, 255, 255, 255))
    bg:setContentSize(winSize.width, titleHeight)
    bar:addChild(bg)

    -- 标题
    local title = cc.Label:createWithSystemFont("AI 助手", "Arial", 18)
    title:setColor(cc.c3b(51, 51, 51))
    title:setPosition(winSize.width / 2, titleHeight / 2)
    bar:addChild(title)

    -- 底部分隔线
    local line = cc.LayerColor:create(cc.c4b(220, 220, 220, 255))
    line:setContentSize(winSize.width, 1)
    line:setPosition(0, 0)
    bar:addChild(line)

    return bar
end

function ChatScene:createScrollArea()
    local winSize = display.size
    local titleHeight = 50
    local inputHeight = SIZES.inputHeight + SIZES.inputPadding * 2

    local scrollHeight = winSize.height - titleHeight - inputHeight

    local scrollView = cc.ScrollView:create()
    scrollView:setViewSize(cc.size(winSize.width, scrollHeight))
    scrollView:setPosition(0, inputHeight)
    scrollView:setScale(1.0)
    scrollView:setDirection(1) -- cc.SCROLLVIEW_DIRECTION_VERTICAL = 1
    scrollView:setBounceable(true)
    scrollView:setContentOffset(cc.p(0, 0), false)

    -- 内容容器
    local container = cc.Node:create()
    container:setContentSize(winSize.width, scrollHeight)
    scrollView:setContainer(container)

    self.scrollContainer = container
    self.scrollHeight = scrollHeight

    return scrollView
end

function ChatScene:createInputArea()
    local winSize = display.size
    local areaHeight = SIZES.inputHeight + SIZES.inputPadding * 2

    local area = cc.Node:create()
    area:setContentSize(winSize.width, areaHeight)
    area:setPosition(0, 0)

    -- 背景
    local bg = cc.LayerColor:create(cc.c4b(255, 255, 255, 255))
    bg:setContentSize(winSize.width, areaHeight)
    area:addChild(bg)

    -- 顶部分隔线
    local line = cc.LayerColor:create(cc.c4b(220, 220, 220, 255))
    line:setContentSize(winSize.width, 1)
    line:setPosition(0, areaHeight - 1)
    area:addChild(line)

    -- 输入框背景
    local inputBg = cc.LayerColor:create(cc.c4b(245, 245, 245, 255))
    inputBg:setContentSize(winSize.width - 120, SIZES.inputHeight)
    inputBg:setPosition(SIZES.inputPadding, SIZES.inputPadding)
    area:addChild(inputBg)

    -- 输入框（使用 TextField 或自定义输入）
    self.inputField = self:createInputField()
    self.inputField:setPosition(SIZES.inputPadding + 10, SIZES.inputPadding + SIZES.inputHeight / 2)
    area:addChild(self.inputField)

    -- 发送按钮
    self.sendBtn = self:createSendButton()
    self.sendBtn:setPosition(winSize.width - 55, areaHeight / 2)
    area:addChild(self.sendBtn)

    return area
end

function ChatScene:createInputField()
    local winSize = display.size
    local fieldWidth = winSize.width - 140

    -- 创建 1x1 白色像素纹理作为 EditBox 背景
    local rt = cc.RenderTexture:create(2, 2)
    rt:begin()
    local dn = cc.DrawNode:create()
    dn:drawSolidRect(cc.p(0,0), cc.p(2,2), cc.c4f(0.96, 0.96, 0.96, 1.0))
    dn:visit()
    rt:endToLua()
    local spriteFrame = rt:getSprite():getSpriteFrame()

    -- 使用 Scale9Sprite 创建 EditBox
    local bgSprite = ccui.Scale9Sprite:createWithSpriteFrame(spriteFrame)
    local editBox = ccui.EditBox:create(cc.size(fieldWidth, SIZES.inputHeight), bgSprite)
    editBox:setPlaceHolder("输入消息...")
    editBox:setFontSize(16)
    editBox:setFontColor(cc.c3b(51, 51, 51))
    editBox:setAnchorPoint(0, 0.5)

    -- 回车发送
    editBox:registerScriptEditBoxHandler(function(event)
        if event == "return" then
            self:onSendClick()
        end
    end)

    self.textField = editBox
    return editBox
end

function ChatScene:createSendButton()
    local btnSize = cc.size(70, 36)

    -- 使用 ccui.Button
    local btn = ccui.Button:create()
    btn:setContentSize(btnSize)
    btn:setTitleText("发送")
    btn:setTitleFontSize(14)
    btn:setTitleColor(cc.c3b(255, 255, 255))
    btn:setScale9Enabled(true)

    -- 背景色
    btn:setColor(COLORS.sendBtn)

    btn:addTouchEventListener(function(sender, eventType)
        if eventType == ccui.TouchEventType.ended then
            self:onSendClick()
        end
    end)

    self.sendBtn = btn
    return btn
end

-- ==================== 消息显示 ====================

function ChatScene:addUserMessage(text)
    local msg = {
        type = MSG_TYPE.USER,
        text = text,
        time = os.time()
    }
    table.insert(self.messages, msg)

    local node = self:createMessageNode(msg)
    table.insert(self.messageNodes, node)
    self.scrollContainer:addChild(node)

    self:updateScrollLayout(true)
end

function ChatScene:addAIMessage(text)
    local msg = {
        type = MSG_TYPE.AI,
        text = text,
        time = os.time()
    }
    table.insert(self.messages, msg)

    local node = self:createMessageNode(msg)
    table.insert(self.messageNodes, node)
    self.scrollContainer:addChild(node)

    self.currentAIMsg = msg
    self.currentAINode = node

    self:updateScrollLayout(true)
end

function ChatScene:addSystemMessage(text)
    local msg = {
        type = MSG_TYPE.SYSTEM,
        text = text,
        time = os.time()
    }
    table.insert(self.messages, msg)

    local node = self:createMessageNode(msg)
    table.insert(self.messageNodes, node)
    self.scrollContainer:addChild(node)

    self:updateScrollLayout()
end

function ChatScene:appendAIText(text)
    if not self.currentAIMsg then return end
    self.currentAIMsg.text = self.currentAIMsg.text .. text

    local node = self.currentAINode
    local winSize = display.size
    local maxW = SIZES.bubbleMaxWidth

    -- 更新文字
    node.labelNode:setString(self.currentAIMsg.text)
    local labelSize = node.labelNode:getContentSize()

    -- 更新气泡大小
    local bw = math.min(labelSize.width + SIZES.bubblePaddingX * 2, maxW)
    local bh = labelSize.height + SIZES.bubblePaddingY * 2
    node.bubbleNode:setContentSize(cc.size(bw, bh))
    local isUser = node.msgData.type == MSG_TYPE.USER
    local posX = isUser and (winSize.width - bw - SIZES.scrollMargin) or SIZES.scrollMargin
    node.bubbleNode:setPosition(posX, 0)
    node.labelNode:setPosition(SIZES.bubblePaddingX, SIZES.bubblePaddingY)

    local oldNodeH = node:getContentSize().height
    local newNodeH = bh + SIZES.messageSpacing
    node:setContentSize(winSize.width, newNodeH)

    -- 增量调整：只改容器高度和当前节点之后的偏移
    local deltaH = newNodeH - oldNodeH
    if deltaH ~= 0 then
        local oldContainerH = self.scrollContainer:getContentSize().height
        local newContainerH = math.max(oldContainerH + deltaH, self.scrollHeight)
        self.scrollContainer:setContentSize(winSize.width, newContainerH)

        -- 容器变高了，把 AI 节点之前的节点整体上移 deltaH
        -- AI 节点本身不动（它在底部）
        local idx = nil
        for i, n in ipairs(self.messageNodes) do
            if n == node then idx = i; break end
        end
        if idx then
            for i = 1, idx - 1 do
                local n = self.messageNodes[i]
                n:setPosition(0, n:getPositionY() + deltaH)
            end
        end

        -- 滚动到底部
        local curOffset = self.scrollArea:getContentOffset()
        local targetY = self.scrollHeight - newContainerH
        if curOffset.y - targetY < 100 then
            self.scrollArea:setContentOffset(cc.p(0, targetY), false)
        end
    end
end

function ChatScene:createMessageNode(msg)
    local node = cc.Node:create()
    node.msgData = msg

    local winSize = display.size
    local maxWidth = SIZES.bubbleMaxWidth

    if msg.type == MSG_TYPE.SYSTEM then
        -- 系统消息：居中灰色文字
        local label = cc.Label:createWithSystemFont(msg.text, "Arial", 14)
        label:setColor(COLORS.systemText)
        label:setPosition(winSize.width / 2, 0)
        node:addChild(label)
        node:setContentSize(winSize.width, 30)
        node.labelNode = label
    else
        -- 用户/AI 消息：气泡样式
        local isUser = msg.type == MSG_TYPE.USER
        local bubbleColor = isUser and COLORS.userBubble or COLORS.aiBubble
        local textColor = isUser and COLORS.userText or COLORS.aiText

        -- 文字标签
        local label = cc.Label:createWithSystemFont(msg.text, "Arial", 16)
        label:setColor(textColor)
        label:setMaxLineWidth(maxWidth - SIZES.bubblePaddingX * 2)
        label:setDimensions(maxWidth - SIZES.bubblePaddingX * 2, 0)
        label:setHorizontalAlignment(cc.TEXT_ALIGNMENT_LEFT)
        local labelSize = label:getContentSize()

        -- 气泡大小
        local bubbleWidth = math.min(labelSize.width + SIZES.bubblePaddingX * 2, maxWidth)
        local bubbleHeight = labelSize.height + SIZES.bubblePaddingY * 2

        -- 气泡背景（直接用圆角矩形）
        local bubble = self:createRoundedRect(bubbleWidth, bubbleHeight, isUser and COLORS.userBubble or COLORS.aiBubble)
        bubble:setContentSize(bubbleWidth, bubbleHeight)
        node:addChild(bubble)
        node.bubbleNode = bubble

        -- 设置标签位置
        label:setAnchorPoint(0, 0)
        label:setPosition(SIZES.bubblePaddingX, SIZES.bubblePaddingY)
        bubble:addChild(label)
        node.labelNode = label

        -- 设置位置（用户右侧，AI左侧）
        local posX = isUser and (winSize.width - bubbleWidth - SIZES.scrollMargin) or SIZES.scrollMargin
        bubble:setPosition(posX, 0)

        node:setContentSize(winSize.width, bubbleHeight + SIZES.messageSpacing)
    end

    return node
end

function ChatScene:updateMessageNodeText(node, text)
    if node and node.labelNode then
        node.labelNode:setString(text)

        -- 更新气泡大小
        if node.bubbleNode then
            local labelSize = node.labelNode:getContentSize()
            local bubbleWidth = math.min(labelSize.width + SIZES.bubblePaddingX * 2, SIZES.bubbleMaxWidth)
            local bubbleHeight = labelSize.height + SIZES.bubblePaddingY * 2
            node.bubbleNode:setContentSize(cc.size(bubbleWidth, bubbleHeight))

            local winSize = display.size
            local isUser = node.msgData.type == MSG_TYPE.USER
            local posX = isUser and (winSize.width - bubbleWidth - SIZES.scrollMargin) or SIZES.scrollMargin
            node.bubbleNode:setPosition(posX, 0)

            -- 保持 label 在气泡内的位置
            node.labelNode:setPosition(SIZES.bubblePaddingX, SIZES.bubblePaddingY)

            node:setContentSize(winSize.width, bubbleHeight + SIZES.messageSpacing)
        end
    end
end

function ChatScene:createRoundedRect(width, height, color)
    local radius = SIZES.bubbleRadius
    local c = cc.c4f(color.r / 255, color.g / 255, color.b / 255, 1)

    -- 用 RenderTexture 渲染一个圆角矩形纹理，用于 Scale9Sprite
    local texSize = 64
    local rt = cc.RenderTexture:create(texSize, texSize)
    rt:begin()

    local dn = cc.DrawNode:create()
    local r = 8
    local s = texSize
    local fill = cc.c4f(1, 1, 1, 1)  -- 白色，后面用 setColor 着色

    -- 画 4 个角的扇形
    local segments = 8
    local function drawArc(cx, cy, startAngle)
        local pts = {cc.p(cx, cy)}
        for i = 0, segments do
            local angle = startAngle + math.pi / 2 * i / segments
            pts[#pts + 1] = cc.p(cx + r * math.cos(angle), cy + r * math.sin(angle))
        end
        dn:drawPolygon(pts, #pts, fill, 0, cc.c4f(0, 0, 0, 0))
    end

    drawArc(r, r, math.pi)                  -- 左下
    drawArc(s - r, r, math.pi * 1.5)        -- 右下
    drawArc(s - r, s - r, 0)                -- 右上
    drawArc(r, s - r, math.pi * 0.5)        -- 左上

    -- 画中间的矩形填充
    dn:drawSolidRect(cc.p(r, 0), cc.p(s - r, s), fill)
    dn:drawSolidRect(cc.p(0, r), cc.p(s, s - r), fill)
    dn:visit()
    rt:endToLua()

    local spriteFrame = rt:getSprite():getSpriteFrame()
    local sprite = ccui.Scale9Sprite:createWithSpriteFrame(spriteFrame)
    sprite:setContentSize(cc.size(width, height))
    sprite:setAnchorPoint(0, 0)
    sprite:setColor(color)

    return sprite
end

function ChatScene:updateScrollLayout(forceScrollToBottom)
    local winSize = display.size
    local totalHeight = 0

    -- 计算总高度
    for _, node in ipairs(self.messageNodes) do
        totalHeight = totalHeight + node:getContentSize().height
    end

    -- 设置容器大小
    local containerHeight = math.max(totalHeight, self.scrollHeight)
    self.scrollContainer:setContentSize(winSize.width, containerHeight)

    -- 布局消息节点（从上往下，y 从 containerHeight 递减）
    local y = containerHeight
    for _, node in ipairs(self.messageNodes) do
        local h = node:getContentSize().height
        y = y - h
        node:setPosition(0, y)
    end

    -- 计算目标偏移量（底部位置）
    local targetOffsetY = self.scrollHeight - containerHeight

    -- 判断是否需要自动滚动到底部
    local shouldScrollToBottom = forceScrollToBottom
    if not shouldScrollToBottom then
        local curOffset = self.scrollArea:getContentOffset()
        -- curOffset.y 接近 targetOffsetY（差值 < 100）说明在底部附近
        if curOffset.y - targetOffsetY < 100 then
            shouldScrollToBottom = true
        end
    end

    if shouldScrollToBottom then
        self.scrollArea:setContentOffset(cc.p(0, targetOffsetY), false)
    end
end

-- ==================== LLM 集成 ====================

function ChatScene:initLLM()
    local llm = require("app.modules.LLM")

    -- 检查是否已初始化
    if llm.isReady() then
        self:addSystemMessage("AI 助手已就绪")
        return
    end

    -- 使用自动下载 + 初始化流程
    self:addSystemMessage("正在准备 AI 模型...")

    llm.initWithDownload({
        backend = "GPU",
        onProgress = function(percent)
            -- 原地更新最后一条系统消息，显示下载进度
            self:updateLastSystemMessage(
                string.format("正在下载模型: %d%%", math.floor(percent))
            )
        end,
        onInit = function(success, error)
            if success then
                self:updateLastSystemMessage("AI 模型加载完成，开始对话吧！")
            else
                self:updateLastSystemMessage("AI 模型加载失败: " .. (error or "未知错误"))
            end
        end
    })
end

function ChatScene:updateLastSystemMessage(text)
    for i = #self.messages, 1, -1 do
        if self.messages[i].type == MSG_TYPE.SYSTEM then
            self.messages[i].text = text
            if self.messageNodes[i] and self.messageNodes[i].labelNode then
                self.messageNodes[i].labelNode:setString(text)
            end
            return
        end
    end
end

function ChatScene:onSendClick()
    -- 获取输入文本
    local text = self.textField:getText()
    if not text or text == "" then
        return
    end

    -- 检查是否正在生成
    if self.isGenerating then
        self:addSystemMessage("AI 正在思考中，请稍候...")
        return
    end

    -- 清空输入框
    self.textField:setText("")

    -- 添加用户消息
    self:addUserMessage(text)

    -- 发送到 AI
    self:sendToAI(text)
end

function ChatScene:sendToAI(text)
    local llm = require("app.modules.LLM")

    if not llm.isReady() then
        self:addSystemMessage("AI 模型未就绪，请稍后再试")
        return
    end

    self.isGenerating = true
    self:updateSendButtonState()

    -- 先添加一个空的 AI 消息占位
    self:addAIMessage("")

    -- 流式输出
    llm.chatStream(text,
        -- onToken: 实时更新
        function(token)
            self:appendAIText(token)
        end,
        -- onComplete: 完成
        function(response)
            self.isGenerating = false
            self.currentAIMsg = nil
            self.currentAINode = nil
            self:updateSendButtonState()
            self:updateScrollLayout(true)
        end,
        -- onError: 错误
        function(error)
            -- 先保存引用再清空
            local errNode = self.currentAINode
            self.isGenerating = false
            self.currentAIMsg = nil
            self.currentAINode = nil
            self:updateSendButtonState()

            -- 显示错误
            if errNode then
                self:updateMessageNodeText(errNode, "[错误: " .. error .. "]")
            else
                self:addSystemMessage("发生错误: " .. error)
            end
        end
    )
end

function ChatScene:updateSendButtonState()
    if self.isGenerating then
        self.sendBtn:setTitleText("...")
        self.sendBtn:setColor(COLORS.sendBtnDisabled)
        self.sendBtn:setEnabled(false)
    else
        self.sendBtn:setTitleText("发送")
        self.sendBtn:setColor(COLORS.sendBtn)
        self.sendBtn:setEnabled(true)
    end
end

-- ==================== 对话管理 ====================

function ChatScene:clearChat()
    -- 清空消息
    self.messages = {}

    -- 移除所有消息节点
    for _, node in ipairs(self.messageNodes) do
        node:removeFromParent()
    end
    self.messageNodes = {}

    -- 重置 LLM 对话历史
    local llm = require("app.modules.LLM")
    llm.resetConversation()

    -- 添加系统消息
    self:addSystemMessage("对话已清空")

    self:updateScrollLayout()
end

function ChatScene:newChat()
    self:clearChat()
    self:addSystemMessage("开始新对话")
end

return ChatScene
