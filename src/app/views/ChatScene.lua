--[[
    ChatScene.lua - 类似微信的 AI 聊天界面

    功能：
    - 消息气泡显示（用户右侧、AI左侧）
    - 语音输入（按住说话）
    - 图片输入（拍照/相册，多模态 AI 分析）
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
    SYSTEM = 3,     -- 系统消息
    USER_IMAGE = 4  -- 带图片的用户消息
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
    plusBtn = cc.c3b(240, 240, 240),               -- +号按钮
    plusBtnActive = cc.c3b(0, 150, 136),           -- +号按钮激活
    micBtn = cc.c3b(240, 240, 240),                -- 语音按钮
    micBtnActive = cc.c3b(0, 150, 136),            -- 语音按钮激活
    expandBg = cc.c3b(245, 245, 245),              -- 展开面板背景
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
    sideBtnSize = 40,               -- 两侧按钮大小
    expandPanelHeight = 100,        -- 展开面板高度
    previewHeight = 100,            -- 预览条高度
    imageMaxWidth = display.width * 0.45,
    imageMaxHeight = 200,
}

function ChatScene:ctor()
    self.messages = {}          -- 消息列表
    self.messageNodes = {}      -- 消息节点列表
    self.isGenerating = false   -- AI 是否正在生成
    self.currentAIMsg = nil     -- 当前正在生成的 AI 消息
    self.pendingImage = nil     -- 待发送的图片路径
    self.isListening = false    -- 是否正在语音识别
    self.plusExpanded = false   -- +号面板是否展开

    self:initUI()
    self:initLLM()
end

function ChatScene:onEnter()
    __ON_APP_RESUME__ = function(data)
        self:rebuildEditBox()
        self:refreshAllBubbles()
    end
end

function ChatScene:onExit()
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

    local bg = cc.LayerColor:create(cc.c4b(255, 255, 255, 255))
    bg:setContentSize(winSize.width, titleHeight)
    bar:addChild(bg)

    local title = cc.Label:createWithSystemFont("AI 助手", "Arial", 18)
    title:setColor(cc.c3b(51, 51, 51))
    title:setPosition(winSize.width / 2, titleHeight / 2)
    bar:addChild(title)

    local line = cc.LayerColor:create(cc.c4b(220, 220, 220, 255))
    line:setContentSize(winSize.width, 1)
    line:setPosition(0, 0)
    bar:addChild(line)

    return bar
end

function ChatScene:createScrollArea()
    local winSize = display.size
    local titleHeight = 50
    local estimatedInputHeight = SIZES.inputHeight + SIZES.inputPadding * 2

    local scrollHeight = winSize.height - titleHeight - estimatedInputHeight

    local scrollView = cc.ScrollView:create()
    scrollView:setViewSize(cc.size(winSize.width, scrollHeight))
    scrollView:setPosition(0, estimatedInputHeight)
    scrollView:setScale(1.0)
    scrollView:setDirection(1)
    scrollView:setBounceable(true)
    scrollView:setContentOffset(cc.p(0, 0), false)

    local container = cc.Node:create()
    container:setContentSize(winSize.width, scrollHeight)
    scrollView:setContainer(container)

    self.scrollContainer = container
    self.scrollHeight = scrollHeight

    return scrollView
end

function ChatScene:createInputArea()
    local winSize = display.size
    local inputRowH = SIZES.inputHeight + SIZES.inputPadding * 2

    local area = cc.Node:create()
    area:setContentSize(winSize.width, inputRowH)
    area:setPosition(0, 0)

    -- 背景
    local bg = cc.LayerColor:create(cc.c4b(255, 255, 255, 255))
    bg:setContentSize(winSize.width, inputRowH)
    area:addChild(bg)

    -- 顶部分隔线
    local line = cc.LayerColor:create(cc.c4b(220, 220, 220, 255))
    line:setContentSize(winSize.width, 1)
    line:setPosition(0, inputRowH - 1)
    area:addChild(line)

    -- 语音按钮（左侧）
    self.micBtn = self:createSideButton("语音", COLORS.micBtn, function()
        self:onMicClick()
    end)
    self.micBtn:setPosition(SIZES.inputPadding, inputRowH / 2)
    area:addChild(self.micBtn)

    -- +号/发送按钮（右侧）- 使用动态回调
    self.plusBtnCallback = function() self:onPlusClick() end
    local btnSize = SIZES.sideBtnSize
    self.plusBtn = ccui.Button:create()
    self.plusBtn:setContentSize(cc.size(btnSize, btnSize))
    self.plusBtn:setTitleText("+")
    self.plusBtn:setTitleFontSize(20)
    self.plusBtn:setTitleColor(cc.c3b(51, 51, 51))
    self.plusBtn:setScale9Enabled(true)
    self.plusBtn:setColor(COLORS.plusBtn)
    self.plusBtn:setAnchorPoint(0, 0.5)
    self.plusBtn:addTouchEventListener(function(sender, eventType)
        if eventType == ccui.TouchEventType.ended then
            if self.plusBtnCallback then
                self.plusBtnCallback()
            end
        end
    end)
    self.plusBtn:setPosition(winSize.width - SIZES.inputPadding - btnSize, inputRowH / 2)
    area:addChild(self.plusBtn)

    -- 输入框（中间）
    local inputX = SIZES.inputPadding + SIZES.sideBtnSize + 5
    local fieldWidth = winSize.width - (SIZES.inputPadding + SIZES.sideBtnSize + 5) * 2 - SIZES.sideBtnSize

    self.inputField = self:createInputField(fieldWidth)
    self.inputField:setPosition(inputX, SIZES.inputPadding + SIZES.inputHeight / 2)
    area:addChild(self.inputField)

    self.inputArea = area
    return area
end

function ChatScene:createSideButton(text, color, callback)
    local btn = ccui.Button:create()
    btn:setContentSize(cc.size(SIZES.sideBtnSize, SIZES.sideBtnSize))
    btn:setTitleText(text)
    btn:setTitleFontSize(16)
    btn:setTitleColor(cc.c3b(51, 51, 51))
    btn:setScale9Enabled(true)
    btn:setColor(color)
    btn:setAnchorPoint(0, 0.5)

    btn:addTouchEventListener(function(sender, eventType)
        if eventType == ccui.TouchEventType.ended then
            callback()
        end
    end)

    return btn
end

function ChatScene:createInputField(width)
    local bgSprite = ccui.Scale9Sprite:create()
    bgSprite:setContentSize(cc.size(width, SIZES.inputHeight))
    bgSprite:setColor(cc.c3b(245, 245, 245))

    local editBox = ccui.EditBox:create(cc.size(width, SIZES.inputHeight), bgSprite)
    editBox:setPlaceHolder("输入消息...")
    editBox:setFontSize(16)
    editBox:setFontColor(cc.c3b(51, 51, 51))
    editBox:setAnchorPoint(0, 0.5)

    editBox:registerScriptEditBoxHandler(function(event)
        if event == "return" then
            self:onSendClick()
        elseif event == "changed" then
            self:updatePlusSendButton()
        end
    end)

    self.textField = editBox
    return editBox
end

function ChatScene:updatePlusSendButton()
    local text = self.textField:getText()
    if text and text ~= "" then
        self.plusBtn:setTitleText("发送")
        self.plusBtn:setColor(COLORS.sendBtn)
        self.plusBtn:setTitleColor(cc.c3b(255, 255, 255))
        self.plusBtnCallback = function() self:onSendClick() end
    else
        self.plusBtn:setTitleText("+")
        self.plusBtn:setColor(COLORS.plusBtn)
        self.plusBtn:setTitleColor(cc.c3b(51, 51, 51))
        self.plusBtnCallback = function() self:onPlusClick() end
    end
end

function ChatScene:rebuildEditBox()
    if not self.inputArea then return end

    local oldText = ""
    if self.textField then
        oldText = self.textField:getText() or ""
        self.textField:closeKeyboard()
        self.textField:removeFromParent()
        self.textField = nil
        self.inputField = nil
    end

    local winSize = display.size
    local inputX = SIZES.inputPadding + SIZES.sideBtnSize + 5
    local fieldWidth = winSize.width - (SIZES.inputPadding + SIZES.sideBtnSize + 5) * 2 - SIZES.sideBtnSize

    self.inputField = self:createInputField(fieldWidth)
    self.inputField:setPosition(inputX, SIZES.inputPadding + SIZES.inputHeight / 2)
    self.inputArea:addChild(self.inputField)

    if oldText ~= "" then
        self.textField:setText(oldText)
    end
end

function ChatScene:refreshAllBubbles()
    for _, node in ipairs(self.messageNodes) do
        if node.bubbleNode and node.drawNode and node.bubbleColor then
            local size = node.bubbleNode:getContentSize()
            self:drawRoundedRect(node.bubbleNode, size.width, size.height)
        end
    end
end

-- ==================== 语音按钮交互 ====================

function ChatScene:onMicClick()
    local llm = require("app.modules.LLM")

    if self.isListening then
        -- 停止录音
        llm.stopSpeech()
        return
    end

    -- 检查权限
    if not llm.hasPermission("RECORD_AUDIO") then
        llm.requestPermission("RECORD_AUDIO", function(granted)
            if granted then
                self:startRecording()
            else
                self:addSystemMessage("需要麦克风权限才能录音")
            end
        end)
        return
    end

    self:startRecording()
end

function ChatScene:startRecording()
    local llm = require("app.modules.LLM")
    self.isListening = true

    -- 按钮视觉反馈
    self.micBtn:setColor(COLORS.micBtnActive)
    self.micBtn:setTitleColor(cc.c3b(255, 255, 255))
    self.micBtn:setTitleText("录音中")

    llm.startSpeech(
        function()
            -- onStart: 录音开始
        end,
        function(audioPath, err)
            -- onResult: 录音完成，audioPath 为音频文件路径
            self.isListening = false
            self.micBtn:setColor(COLORS.micBtn)
            self.micBtn:setTitleColor(cc.c3b(51, 51, 51))
            self.micBtn:setTitleText("语音")

            if err then
                self:addSystemMessage("录音失败: " .. err)
            elseif audioPath then
                -- 发送音频给 AI 分析
                local text = self.textField:getText() or ""
                if text == "" then
                    text = "请分析这段音频内容"
                end
                self.textField:setText("")
                self:updatePlusSendButton()
                self:clearPendingImage()

                -- 添加用户消息（显示录音提示）
                self:addUserMessage("[语音消息]" .. (text ~= "请分析这段音频内容" and text or ""), nil)

                -- 发送音频给 AI
                self:sendToAI(text, nil, audioPath)
            end
        end
    )
end

-- ==================== +号展开面板 ====================

function ChatScene:onPlusClick()
    self.plusExpanded = not self.plusExpanded

    if self.plusExpanded then
        self:showExpandPanel()
    else
        self:hideExpandPanel()
    end
end

function ChatScene:showExpandPanel()
    if self.expandPanel then
        self.expandPanel:removeFromParent()
        self.expandPanel = nil
    end

    -- 如果有预览条，先收起
    self:clearPendingImage()

    local winSize = display.size
    local inputRowH = SIZES.inputHeight + SIZES.inputPadding * 2
    local panelH = SIZES.expandPanelHeight

    local panel = cc.Node:create()
    panel:setContentSize(winSize.width, panelH)
    panel:setPosition(0, inputRowH)

    local bg = cc.LayerColor:create(cc.c4b(245, 245, 245, 255))
    bg:setContentSize(winSize.width, panelH)
    panel:addChild(bg)

    -- 顶部分隔线
    local line = cc.LayerColor:create(cc.c4b(220, 220, 220, 255))
    line:setContentSize(winSize.width, 1)
    line:setPosition(0, panelH - 1)
    panel:addChild(line)

    -- 拍照按钮
    local photoBtn = self:createExpandButton("拍照", 80, panelH / 2, function()
        self:onCameraClick()
    end)
    panel:addChild(photoBtn)

    -- 相册按钮
    local galleryBtn = self:createExpandButton("相册", 200, panelH / 2, function()
        self:onGalleryClick()
    end)
    panel:addChild(galleryBtn)

    self.expandPanel = panel
    self.inputArea:addChild(panel)

    -- 调整输入区域高度
    self.inputArea:setContentSize(winSize.width, inputRowH + panelH)
    self:updateScrollAreaBounds(inputRowH + panelH)
end

function ChatScene:hideExpandPanel()
    if self.expandPanel then
        self.expandPanel:removeFromParent()
        self.expandPanel = nil
    end
    self.plusExpanded = false

    local winSize = display.size
    local inputRowH = SIZES.inputHeight + SIZES.inputPadding * 2
    self.inputArea:setContentSize(winSize.width, inputRowH)
    self:updateScrollAreaBounds(inputRowH)
end

function ChatScene:createExpandButton(text, x, y, callback)
    local btnW, btnH = 80, 70
    local btn = cc.Node:create()
    btn:setContentSize(btnW, btnH)
    btn:setPosition(x - btnW / 2, y - btnH / 2)

    -- 图标背景
    local iconBg = cc.LayerColor:create(cc.c4b(255, 255, 255, 255))
    iconBg:setContentSize(50, 50)
    iconBg:setPosition((btnW - 50) / 2, btnH - 55)
    btn:addChild(iconBg)

    -- 图标文字
    local icon = cc.Label:createWithSystemFont(text == "拍照" and "📷" or "🖼️", "Arial", 24)
    icon:setPosition(btnW / 2, btnH - 30)
    btn:addChild(icon)

    -- 标签
    local label = cc.Label:createWithSystemFont(text, "Arial", 12)
    label:setColor(cc.c3b(102, 102, 102))
    label:setPosition(btnW / 2, 10)
    btn:addChild(label)

    -- 点击区域
    local touchBtn = ccui.Button:create()
    touchBtn:setContentSize(btnW, btnH)
    touchBtn:setPosition(btnW / 2, btnH / 2)
    touchBtn:setScale9Enabled(true)
    touchBtn:setOpacity(0)
    touchBtn:addTouchEventListener(function(sender, eventType)
        if eventType == ccui.TouchEventType.ended then
            callback()
        end
    end)
    btn:addChild(touchBtn)

    return btn
end

-- ==================== 拍照和相册 ====================

function ChatScene:onCameraClick()
    local llm = require("app.modules.LLM")

    if not llm.hasPermission("CAMERA") then
        llm.requestPermission("CAMERA", function(granted)
            if granted then
                llm.takePhoto(function(path, err)
                    self:onImageResult(path, err)
                end)
            else
                self:addSystemMessage("需要相机权限才能拍照")
            end
        end)
        return
    end

    llm.takePhoto(function(path, err)
        self:onImageResult(path, err)
    end)
end

function ChatScene:onGalleryClick()
    local llm = require("app.modules.LLM")

    if not llm.hasPermission("READ_EXTERNAL_STORAGE") then
        llm.requestPermission("READ_EXTERNAL_STORAGE", function(granted)
            if granted then
                llm.pickImage(function(path, err)
                    self:onImageResult(path, err)
                end)
            else
                self:addSystemMessage("需要存储权限才能选择图片")
            end
        end)
        return
    end

    llm.pickImage(function(path, err)
        self:onImageResult(path, err)
    end)
end

function ChatScene:onImageResult(path, err)
    if err then
        self:addSystemMessage("获取图片失败: " .. err)
        return
    end
    if path then
        self:setPendingImage(path)
    end
end

-- ==================== 图片预览 ====================

function ChatScene:setPendingImage(path)
    self.pendingImage = path

    -- 收起展开面板
    self:hideExpandPanel()

    local winSize = display.size
    local inputRowH = SIZES.inputHeight + SIZES.inputPadding * 2
    local previewH = SIZES.previewHeight

    -- 创建预览条
    if self.previewBar then
        self.previewBar:removeFromParent()
    end

    self.previewBar = cc.Node:create()
    self.previewBar:setContentSize(winSize.width, previewH)
    self.previewBar:setPosition(0, inputRowH)

    local bg = cc.LayerColor:create(cc.c4b(240, 240, 240, 255))
    bg:setContentSize(winSize.width, previewH)
    self.previewBar:addChild(bg)

    -- 分隔线
    local line = cc.LayerColor:create(cc.c4b(220, 220, 220, 255))
    line:setContentSize(winSize.width, 1)
    line:setPosition(0, previewH - 1)
    self.previewBar:addChild(line)

    -- 缩略图
    local sprite = cc.Sprite:create(path)
    if sprite then
        local size = sprite:getContentSize()
        local thumbSize = 80
        local scale = math.min(thumbSize / size.width, thumbSize / size.height)
        sprite:setScale(scale)
        sprite:setPosition(55, previewH / 2)
        sprite:setTag(100)
        self.previewBar:addChild(sprite)
    end

    -- 取消按钮
    local cancelBtn = ccui.Button:create()
    cancelBtn:setContentSize(cc.size(24, 24))
    cancelBtn:setTitleText("x")
    cancelBtn:setTitleFontSize(14)
    cancelBtn:setTitleColor(cc.c3b(255, 255, 255))
    cancelBtn:setColor(cc.c3b(200, 60, 60))
    cancelBtn:setScale9Enabled(true)
    cancelBtn:setPosition(95, previewH - 12)
    cancelBtn:addTouchEventListener(function(sender, eventType)
        if eventType == ccui.TouchEventType.ended then
            self:clearPendingImage()
        end
    end)
    self.previewBar:addChild(cancelBtn)

    -- 提示文字
    local hint = cc.Label:createWithSystemFont("图片已选择，输入问题后发送", "Arial", 12)
    hint:setColor(cc.c3b(128, 128, 128))
    hint:setPosition(winSize.width / 2, previewH / 2)
    self.previewBar:addChild(hint)

    self.inputArea:addChild(self.previewBar)

    -- 调整输入区域高度
    self.inputArea:setContentSize(winSize.width, inputRowH + previewH)
    self:updateScrollAreaBounds(inputRowH + previewH)
end

function ChatScene:clearPendingImage()
    self.pendingImage = nil
    if self.previewBar then
        self.previewBar:removeFromParent()
        self.previewBar = nil
    end

    local winSize = display.size
    local inputRowH = SIZES.inputHeight + SIZES.inputPadding * 2
    self.inputArea:setContentSize(winSize.width, inputRowH)
    self:updateScrollAreaBounds(inputRowH)
end

-- ==================== 滚动区域调整 ====================

function ChatScene:updateScrollAreaBounds(totalInputHeight)
    local winSize = display.size
    local titleHeight = 50
    local scrollHeight = winSize.height - titleHeight - totalInputHeight

    if self.scrollArea then
        self.scrollHeight = scrollHeight
        self.scrollArea:setViewSize(cc.size(winSize.width, scrollHeight))
        self.scrollArea:setPosition(0, totalInputHeight)
    end
end

-- ==================== 消息显示 ====================

function ChatScene:addUserMessage(text, imagePath)
    local msg = {
        type = imagePath and MSG_TYPE.USER_IMAGE or MSG_TYPE.USER,
        text = text,
        imagePath = imagePath,
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

    node.labelNode:setString(self.currentAIMsg.text)
    local labelSize = node.labelNode:getContentSize()

    local bw = math.min(labelSize.width + SIZES.bubblePaddingX * 2, maxW)
    local bh = labelSize.height + SIZES.bubblePaddingY * 2
    node.bubbleNode:setContentSize(cc.size(bw, bh))
    self:drawRoundedRect(node.bubbleNode, bw, bh)
    local isUser = node.msgData.type == MSG_TYPE.USER
    local posX = isUser and (winSize.width - bw - SIZES.scrollMargin) or SIZES.scrollMargin
    node.bubbleNode:setPosition(posX, 0)
    node.labelNode:setPosition(SIZES.bubblePaddingX, SIZES.bubblePaddingY)

    local oldNodeH = node:getContentSize().height
    local newNodeH = bh + SIZES.messageSpacing
    node:setContentSize(winSize.width, newNodeH)

    local deltaH = newNodeH - oldNodeH
    if deltaH ~= 0 then
        local oldContainerH = self.scrollContainer:getContentSize().height
        local newContainerH = math.max(oldContainerH + deltaH, self.scrollHeight)
        self.scrollContainer:setContentSize(winSize.width, newContainerH)

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
        local label = cc.Label:createWithSystemFont(msg.text, "Arial", 14)
        label:setColor(COLORS.systemText)
        label:setPosition(winSize.width / 2, 0)
        node:addChild(label)
        node:setContentSize(winSize.width, 30)
        node.labelNode = label
    elseif msg.type == MSG_TYPE.USER_IMAGE then
        -- 带图片的用户消息
        local bubbleColor = COLORS.userBubble
        local textColor = COLORS.userText
        local padding = SIZES.bubblePaddingX

        local bubbleHeight = 0
        local bubbleWidth = 0

        -- 文字部分
        local label = nil
        if msg.text and msg.text ~= "" then
            label = cc.Label:createWithSystemFont(msg.text, "Arial", 16)
            label:setColor(textColor)
            label:setMaxLineWidth(maxWidth - padding * 2)
            label:setDimensions(maxWidth - padding * 2, 0)
            label:setHorizontalAlignment(cc.TEXT_ALIGNMENT_LEFT)
            label:setAnchorPoint(0, 0)
        end

        -- 图片缩略图
        local imgSprite = nil
        if msg.imagePath then
            imgSprite = cc.Sprite:create(msg.imagePath)
            if imgSprite then
                local imgSize = imgSprite:getContentSize()
                local imgMaxW = SIZES.imageMaxWidth
                local imgMaxH = SIZES.imageMaxHeight
                local scale = math.min(imgMaxW / imgSize.width, imgMaxH / imgSize.height, 1.0)
                imgSprite:setScale(scale)
                local scaledW = imgSize.width * scale
                local scaledH = imgSize.height * scale
                imgSprite:setAnchorPoint(0, 0)

                bubbleWidth = math.max(bubbleWidth, scaledW + padding * 2)
                bubbleHeight = bubbleHeight + scaledH + 5
                node.imageSprite = imgSprite
                node.imageHeight = scaledH
                node.imageWidth = scaledW
            end
        end

        if label then
            local labelSize = label:getContentSize()
            bubbleWidth = math.max(bubbleWidth, labelSize.width + padding * 2)
            bubbleHeight = bubbleHeight + labelSize.height
            node.labelNode = label
        end

        bubbleWidth = math.min(bubbleWidth, maxWidth)
        bubbleHeight = bubbleHeight + SIZES.bubblePaddingY * 2

        local bubble = self:createRoundedRect(bubbleWidth, bubbleHeight, bubbleColor)
        bubble:setContentSize(bubbleWidth, bubbleHeight)
        node:addChild(bubble)
        node.bubbleNode = bubble

        -- 布局：图片在上，文字在下
        local yOffset = SIZES.bubblePaddingY

        if imgSprite then
            local imgX = (bubbleWidth - node.imageWidth) / 2
            imgSprite:setPosition(imgX, yOffset)
            yOffset = yOffset + node.imageHeight + 5
            bubble:addChild(imgSprite)
        end

        if label then
            label:setPosition(padding, yOffset)
            bubble:addChild(label)
        end

        local posX = winSize.width - bubbleWidth - SIZES.scrollMargin
        bubble:setPosition(posX, 0)
        node:setContentSize(winSize.width, bubbleHeight + SIZES.messageSpacing)
    else
        -- 用户/AI 纯文本消息
        local isUser = msg.type == MSG_TYPE.USER
        local bubbleColor = isUser and COLORS.userBubble or COLORS.aiBubble
        local textColor = isUser and COLORS.userText or COLORS.aiText

        local label = cc.Label:createWithSystemFont(msg.text, "Arial", 16)
        label:setColor(textColor)
        label:setMaxLineWidth(maxWidth - SIZES.bubblePaddingX * 2)
        label:setDimensions(maxWidth - SIZES.bubblePaddingX * 2, 0)
        label:setHorizontalAlignment(cc.TEXT_ALIGNMENT_LEFT)
        local labelSize = label:getContentSize()

        local bubbleWidth = math.min(labelSize.width + SIZES.bubblePaddingX * 2, maxWidth)
        local bubbleHeight = labelSize.height + SIZES.bubblePaddingY * 2

        local bubble = self:createRoundedRect(bubbleWidth, bubbleHeight, bubbleColor)
        bubble:setContentSize(bubbleWidth, bubbleHeight)
        node:addChild(bubble)
        node.bubbleNode = bubble

        label:setAnchorPoint(0, 0)
        label:setPosition(SIZES.bubblePaddingX, SIZES.bubblePaddingY)
        bubble:addChild(label)
        node.labelNode = label

        local posX = isUser and (winSize.width - bubbleWidth - SIZES.scrollMargin) or SIZES.scrollMargin
        bubble:setPosition(posX, 0)

        node:setContentSize(winSize.width, bubbleHeight + SIZES.messageSpacing)
    end

    return node
end

function ChatScene:updateMessageNodeText(node, text)
    if node and node.labelNode then
        node.labelNode:setString(text)

        if node.bubbleNode then
            local labelSize = node.labelNode:getContentSize()
            local bubbleWidth = math.min(labelSize.width + SIZES.bubblePaddingX * 2, SIZES.bubbleMaxWidth)
            local bubbleHeight = labelSize.height + SIZES.bubblePaddingY * 2
            node.bubbleNode:setContentSize(cc.size(bubbleWidth, bubbleHeight))

            self:drawRoundedRect(node.bubbleNode, bubbleWidth, bubbleHeight)

            local winSize = display.size
            local isUser = node.msgData.type == MSG_TYPE.USER or node.msgData.type == MSG_TYPE.USER_IMAGE
            local posX = isUser and (winSize.width - bubbleWidth - SIZES.scrollMargin) or SIZES.scrollMargin
            node.bubbleNode:setPosition(posX, 0)

            node.labelNode:setPosition(SIZES.bubblePaddingX, SIZES.bubblePaddingY)

            node:setContentSize(winSize.width, bubbleHeight + SIZES.messageSpacing)
        end
    end
end

function ChatScene:createRoundedRect(width, height, color)
    local node = cc.Node:create()
    node:setContentSize(cc.size(width, height))
    node:setAnchorPoint(0, 0)

    local dn = cc.DrawNode:create()
    node:addChild(dn)
    node.drawNode = dn
    node.bubbleColor = color

    self:drawRoundedRect(node, width, height)
    return node
end

function ChatScene:drawRoundedRect(bubbleNode, width, height)
    local dn = bubbleNode.drawNode
    local color = bubbleNode.bubbleColor
    local r = SIZES.bubbleRadius
    local c = cc.c4f(color.r / 255, color.g / 255, color.b / 255, 1)
    local segments = 8

    dn:clear()

    local function drawArc(cx, cy, startAngle)
        local pts = {cc.p(cx, cy)}
        for i = 0, segments do
            local angle = startAngle + math.pi / 2 * i / segments
            pts[#pts + 1] = cc.p(cx + r * math.cos(angle), cy + r * math.sin(angle))
        end
        dn:drawPolygon(pts, #pts, c, 0, cc.c4f(0, 0, 0, 0))
    end

    drawArc(r, r, math.pi)
    drawArc(width - r, r, math.pi * 1.5)
    drawArc(width - r, height - r, 0)
    drawArc(r, height - r, math.pi * 0.5)

    dn:drawSolidRect(cc.p(r, 0), cc.p(width - r, height), c)
    dn:drawSolidRect(cc.p(0, r), cc.p(width, height - r), c)
end

function ChatScene:updateScrollLayout(forceScrollToBottom)
    local winSize = display.size
    local totalHeight = 0

    for _, node in ipairs(self.messageNodes) do
        totalHeight = totalHeight + node:getContentSize().height
    end

    local containerHeight = math.max(totalHeight, self.scrollHeight)
    self.scrollContainer:setContentSize(winSize.width, containerHeight)

    local y = containerHeight
    for _, node in ipairs(self.messageNodes) do
        local h = node:getContentSize().height
        y = y - h
        node:setPosition(0, y)
    end

    local targetOffsetY = self.scrollHeight - containerHeight

    local shouldScrollToBottom = forceScrollToBottom
    if not shouldScrollToBottom then
        local curOffset = self.scrollArea:getContentOffset()
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

    if llm.isReady() then
        self:addSystemMessage("AI 助手已就绪")
        return
    end

    self:addSystemMessage("正在准备 AI 模型...")

    llm.initWithDownload({
        backend = "GPU",
        onProgress = function(percent)
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
    local text = self.textField:getText() or ""
    local imagePath = self.pendingImage

    if text == "" and not imagePath then
        return
    end

    if self.isGenerating then
        self:addSystemMessage("AI 正在思考中，请稍候...")
        return
    end

    -- 清空输入
    self.textField:setText("")
    self:updatePlusSendButton()
    self:clearPendingImage()

    -- 添加用户消息
    self:addUserMessage(text, imagePath)

    -- 发送到 AI
    self:sendToAI(text, imagePath)
end

function ChatScene:sendToAI(text, imagePath, audioPath)
    local llm = require("app.modules.LLM")

    if not llm.isReady() then
        self:addSystemMessage("AI 模型未就绪，请稍后再试")
        return
    end

    self.isGenerating = true
    self:updateSendButtonState()

    self:addAIMessage("")

    local onToken = function(token)
        self:appendAIText(token)
    end
    local onComplete = function(response)
        self.isGenerating = false
        self.currentAIMsg = nil
        self.currentAINode = nil
        self:updateSendButtonState()
        self:updateScrollLayout(true)
    end
    local onError = function(error)
        local errNode = self.currentAINode
        self.isGenerating = false
        self.currentAIMsg = nil
        self.currentAINode = nil
        self:updateSendButtonState()

        if errNode then
            self:updateMessageNodeText(errNode, "[错误: " .. error .. "]")
        else
            self:addSystemMessage("发生错误: " .. error)
        end
    end

    if imagePath or audioPath then
        llm.chatWithImage(text, imagePath, audioPath, onToken, onComplete, onError)
    else
        llm.chatStream(text, onToken, onComplete, onError)
    end
end

function ChatScene:updateSendButtonState()
    if self.isGenerating then
        self.plusBtn:setTitleText("...")
        self.plusBtn:setColor(COLORS.sendBtnDisabled)
        self.plusBtn:setTitleColor(cc.c3b(255, 255, 255))
        self.plusBtn:setEnabled(false)
    else
        self.plusBtn:setEnabled(true)
        self:updatePlusSendButton()
    end
end

-- ==================== 对话管理 ====================

function ChatScene:clearChat()
    self.messages = {}

    for _, node in ipairs(self.messageNodes) do
        node:removeFromParent()
    end
    self.messageNodes = {}

    local llm = require("app.modules.LLM")
    llm.resetConversation()

    self:addSystemMessage("对话已清空")

    self:updateScrollLayout()
end

function ChatScene:newChat()
    self:clearChat()
    self:addSystemMessage("开始新对话")
end

return ChatScene
