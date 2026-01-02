-- ╔═══════════════════════════════════════════════════════════╗
-- ║  SMOOTH AUTO WALK V6.2 - TAB SYSTEM + LOOP             ║
-- ║  Real smooth walking with proper foot grounding          ║
-- ╚═══════════════════════════════════════════════════════════╝

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer

-- ════════════════════════════════════════════════════════════
-- CONFIG & STATE
-- ════════════════════════════════════════════════════════════
local State = {
    recording = false,
    replaying = false,
    paused = false,
    guiVisible = true,
    waitingForMovement = false
}

local Config = {
    recordRate = 0.05,
    rewindStep = 25,
    playbackSpeed = 1.0,
    autoLoop = false  -- Auto replay when finished
}

local Recording = {
    frames = {},
    currentIndex = 0
}

local SaveFolder = "AutoWalkRecordings"

-- Auto-detect executor workspace path
local function getWorkspacePath()
    local paths = {
        "AutoWalkRecordings",
        "/storage/emulated/0/Delta/Workspace/AutoWalkRecordings",
        "workspace/AutoWalkRecordings",
    }
    
    for _, path in ipairs(paths) do
        local success = pcall(function()
            if not isfolder(path) then
                makefolder(path)
            end
        end)
        if success then
            SaveFolder = path
            return path
        end
    end
    
    return "AutoWalkRecordings"
end

-- ════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ════════════════════════════════════════════════════════════
local function getChar()
    return LP.Character or LP.CharacterAdded:Wait()
end

local function getHRP()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local char = getChar()
    return char and char:FindFirstChild("Humanoid")
end

local function notify(title, text)
    game.StarterGui:SetCore("SendNotification", {
        Title = "🎬 " .. title;
        Text = text;
        Duration = 2;
    })
end

local function formatTime(frames)
    local seconds = frames * Config.recordRate
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d", mins, secs)
end

-- ════════════════════════════════════════════════════════════
-- RECORDING MODULE
-- ════════════════════════════════════════════════════════════
local RecordModule = {}

function RecordModule.Start()
    if State.recording then return end
    
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then
        notify("Error", "Character not found!")
        return
    end
    
    State.recording = true
    State.paused = false
    
    if Recording.currentIndex == 0 or Recording.currentIndex >= #Recording.frames then
        Recording.currentIndex = #Recording.frames
    end
    
    notify("Recording", "Started!")
    updateStatus("🔴 RECORDING")
    
    task.spawn(function()
        while State.recording do
            while State.paused and State.recording do
                task.wait(0.1)
            end
            
            if not State.recording then break end
            
            hrp = getHRP()
            hum = getHum()
            if not hrp or not hum then break end
            
            if State.waitingForMovement then
                local isMoving = hrp.AssemblyLinearVelocity.Magnitude > 1 or 
                                hum.MoveDirection.Magnitude > 0.1
                
                if isMoving then
                    State.waitingForMovement = false
                    updateStatus("🔴 RECORDING")
                    notify("Recording!", "Movement detected!")
                else
                    task.wait(Config.recordRate)
                    continue
                end
            end
            
            local frame = {
                cf = hrp.CFrame,
                vel = hrp.AssemblyLinearVelocity,
                state = hum:GetState(),
                moveDir = hum.MoveDirection,
                speed = hum.WalkSpeed,
                jump = hum:GetState() == Enum.HumanoidStateType.Jumping or
                       hum:GetState() == Enum.HumanoidStateType.Freefall
            }
            
            table.insert(Recording.frames, frame)
            Recording.currentIndex = #Recording.frames
            
            updateUI()
            
            task.wait(Config.recordRate)
        end
    end)
end

function RecordModule.Stop()
    if not State.recording then return end
    State.recording = false
    State.paused = false
    
    notify("Stopped", #Recording.frames .. " frames recorded")
    updateStatus("⏹ Ready")
end

function RecordModule.TogglePause()
    if not State.recording then return end
    
    State.paused = not State.paused
    
    if State.paused then
        updateStatus("⏸ PAUSED")
        notify("Paused", "Press Backspace to rewind")
    else
        if Recording.currentIndex > 0 and Recording.currentIndex < #Recording.frames then
            local deletedCount = #Recording.frames - Recording.currentIndex
            
            for i = #Recording.frames, Recording.currentIndex + 1, -1 do
                table.remove(Recording.frames, i)
            end
            
            notify("Overwrite!", string.format("Deleted %d frames", deletedCount))
            
            State.waitingForMovement = true
            updateStatus("⏳ WAITING...")
            notify("Get Ready!", "Start moving to continue recording")
            updateUI()
        else
            updateStatus("🔴 RECORDING")
            notify("Resumed", "Recording continues")
        end
    end
end

function RecordModule.Clear()
    Recording.frames = {}
    Recording.currentIndex = 0
    notify("Cleared", "All data deleted")
    updateStatus("⏹ Ready")
    updateUI()
end

-- ════════════════════════════════════════════════════════════
-- REPLAY MODULE
-- ════════════════════════════════════════════════════════════
local ReplayModule = {}
local replayConnection = nil

function ReplayModule.FindClosestFrame()
    if #Recording.frames == 0 then return 1 end
    
    local hrp = getHRP()
    if not hrp then return 1 end
    
    local currentPos = hrp.Position
    local closestFrame = 1
    local closestDistance = math.huge
    
    for i, frame in ipairs(Recording.frames) do
        local framePos = frame.cf.Position
        local distance = (currentPos - framePos).Magnitude
        
        if distance < closestDistance then
            closestDistance = distance
            closestFrame = i
        end
    end
    
    return closestFrame, closestDistance
end

function ReplayModule.Play()
    if #Recording.frames == 0 then
        notify("Error", "No recording!")
        return
    end
    
    if State.replaying then
        notify("Warning", "Already playing!")
        return
    end
    
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then return end
    
    State.replaying = true
    State.paused = false
    
    local startFrame, distance = ReplayModule.FindClosestFrame()
    
    if distance < 50 then
        Recording.currentIndex = startFrame
        notify("Smart Start", string.format("Frame %d/%d (%.1fm away)", startFrame, #Recording.frames, distance))
        print(string.format("[SMART START] Starting from frame %d (distance: %.1f studs)", startFrame, distance))
    else
        Recording.currentIndex = 1
        notify("Playing", "Starting from beginning")
        print("[NORMAL START] Starting from frame 1 (too far from recording path)")
    end
    
    updateStatus("▶ PLAYING")
    
    local startTick = tick()
    local frameTime = Config.recordRate / Config.playbackSpeed
    startTick = startTick - ((Recording.currentIndex - 1) * frameTime)
    
    if replayConnection then
        replayConnection:Disconnect()
    end
    
    replayConnection = RunService.Heartbeat:Connect(function(dt)
        if not State.replaying then
            if replayConnection then
                replayConnection:Disconnect()
                replayConnection = nil
            end
            return
        end
        
        if State.paused then return end
        
        hrp = getHRP()
        hum = getHum()
        if not hrp or not hum then
            State.replaying = false
            return
        end
        
        local elapsed = tick() - startTick
        local targetFrame = math.floor(elapsed / frameTime) + 1
        
        if targetFrame > #Recording.frames then
            -- Check if auto loop is enabled
            if Config.autoLoop then
                Recording.currentIndex = 1
                startTick = tick()
                notify("Loop", "Restarting replay!")
                print("[LOOP] Auto-restarting from frame 1")
            else
                State.replaying = false
                notify("Complete", "Replay finished!")
                updateStatus("✅ Complete")
                updateUI()
            end
            return
        end
        
        targetFrame = math.clamp(targetFrame, 1, #Recording.frames)
        Recording.currentIndex = targetFrame
        
        local frame = Recording.frames[targetFrame]
        local nextFrame = Recording.frames[math.min(targetFrame + 1, #Recording.frames)]
        
        if frame then
            if frame.state and frame.state ~= Enum.HumanoidStateType.        if frame then
            -- 1. Set humanoid state untuk animasi yang benar
            if frame.state and frame.state ~= Enum.HumanoidStateType.None then
                local currentState = hum:GetState()
                if currentState ~= frame.state then
                    pcall(function()
                        hum:ChangeState(frame.state)
                    end)
                end
            end
            
            if frame.moveDir and frame.moveDir.Magnitude > 0.05 then
                hum:Move(frame.moveDir, true)
            else
                hum:Move(Vector3.zero, true)
            end
            
            if nextFrame and targetFrame < #Recording.frames then
                local progress = (elapsed % frameTime) / frameTime
                
                local lerpedCF = frame.cf:Lerp(nextFrame.cf, progress)
                
                local isGrounded = frame.state == Enum.HumanoidStateType.Running or 
                                  frame.state == Enum.HumanoidStateType.RunningNoPhysics or
                                  frame.state == Enum.HumanoidStateType.Climbing or
                                  frame.state == Enum.HumanoidStateType.Landed
                
                if isGrounded then
                    local exactY = frame.cf.Position.Y
                    local lerpedPos = lerpedCF.Position
                    lerpedCF = CFrame.new(lerpedPos.X, exactY, lerpedPos.Z) * 
                              (lerpedCF - lerpedCF.Position)
                end
                
                hrp.CFrame = lerpedCF
                hrp.AssemblyLinearVelocity = frame.vel:Lerp(nextFrame.vel, progress)
            else
                hrp.CFrame = frame.cf
                hrp.AssemblyLinearVelocity = frame.vel
            end
            
            if frame.speed then
                hum.WalkSpeed = frame.speed * Config.playbackSpeed
            end
            
            if frame.jump then
                local currentState = hum:GetState()
                if currentState ~= Enum.HumanoidStateType.Jumping and 
                   currentState ~= Enum.HumanoidStateType.Freefall then
                    pcall(function()
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end)
                end
            end
        end
        
        updateUI()
    end)
end

function ReplayModule.Stop()
    State.replaying = false
    State.paused = false
    
    if replayConnection then
        replayConnection:Disconnect()
        replayConnection = nil
    end
    
    local hum = getHum()
    if hum then
        hum.WalkSpeed = 16
        hum:Move(Vector3.zero)
    end
    
    notify("Stopped", "Replay stopped")
    updateStatus("⏹ Stopped")
end

-- ════════════════════════════════════════════════════════════
-- SPEED CONTROL MODULE
-- ════════════════════════════════════════════════════════════
local SpeedModule = {}

function SpeedModule.SetSpeed(multiplier)
    Config.playbackSpeed = math.clamp(multiplier, 0.25, 3.0)
    notify("Speed", string.format("%.1fx", Config.playbackSpeed))
    print(string.format("[SPEED] Playback speed set to %.1fx", Config.playbackSpeed))
    GUI.UpdateSpeedButtons()
    updateUI()
end

-- ════════════════════════════════════════════════════════════
-- REWIND MODULE
-- ════════════════════════════════════════════════════════════
local RewindModule = {}

function RewindModule.StepBack()
    if #Recording.frames == 0 then
        notify("Error", "No recording!")
        return
    end
    
    if not State.recording or not State.paused then
        notify("Warning", "Pause recording first!")
        return
    end
    
    local oldIndex = Recording.currentIndex
    Recording.currentIndex = math.max(1, Recording.currentIndex - Config.rewindStep)
    
    local frame = Recording.frames[Recording.currentIndex]
    if frame then
        local hrp = getHRP()
        local hum = getHum()
        if hrp and hum then
            hrp.CFrame = frame.cf
            hrp.AssemblyLinearVelocity = Vector3.zero
            
            if frame.state then
                hum:ChangeState(frame.state)
            end
        end
    end
    
    local seconds = Config.rewindStep * Config.recordRate
    local frameDiff = oldIndex - Recording.currentIndex
    
    notify("⏪ Rewind", string.format("-%0.1fs (%d frames)", seconds, frameDiff))
    notify("Next", "Press SPACE to overwrite!")
    
    updateUI()
end

-- ════════════════════════════════════════════════════════════
-- SAVE/LOAD MODULE
-- ════════════════════════════════════════════════════════════
local SaveModule = {}

function SaveModule.Save()
    if #Recording.frames == 0 then
        notify("Error", "Nothing to save!")
        return
    end
    
    if not isfolder or not makefolder or not writefile then
        notify("Error", "Executor doesn't support file functions!")
        print("[ERROR] Missing functions: isfolder, makefolder, or writefile")
        print("[TIP] Try using a different executor (Solara, Wave, etc)")
        return
    end
    
    local filename = "Recording_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    
    local data = {
        version = "6.2",
        frameCount = #Recording.frames,
        recordRate = Config.recordRate,
        frames = {}
    }
    
    for _, frame in ipairs(Recording.frames) do
        local pos = frame.cf.Position
        local rx, ry, rz = frame.cf:ToOrientation()
        local vel = frame.vel
        local moveDir = frame.moveDir
        
        local stateValue = 8
        if frame.state then
            if type(frame.state) == "number" then
                stateValue = frame.state
            elseif type(frame.state) == "userdata" and frame.state.Value then
                stateValue = frame.state.Value
            end
        end
        
        table.insert(data.frames, {
            string.format("%.2f,%.2f,%.2f", pos.X, pos.Y, pos.Z),
            string.format("%.3f,%.3f,%.3f", rx, ry, rz),
            string.format("%.1f,%.1f,%.1f", vel.X, vel.Y, vel.Z),
            string.format("%.2f,%.2f,%.2f", moveDir.X, moveDir.Y, moveDir.Z),
            frame.jump and 1 or 0,
            frame.speed,
            stateValue
        })
    end
    
    local json = HttpService:JSONEncode(data)
    
    local success, err = pcall(function()
        if not isfolder(SaveFolder) then
            makefolder(SaveFolder)
            print("[CREATED] Folder: " .. SaveFolder)
        end
        writefile(SaveFolder .. "/" .. filename, json)
    end)
    
    if success then
        notify("Saved!", filename)
        print("╔═══════════════════════════════════════════════════╗")
        print("║  FILE SAVED SUCCESSFULLY!")
        print("║  Location: " .. SaveFolder .. "/" .. filename)
        print("║  Frames: " .. #Recording.frames)
        print("║  Size: " .. string.format("%.2f KB", #json / 1024))
        print("╚═══════════════════════════════════════════════════╝")
    else
        notify("Error", "Could not save file!")
        print("[ERROR] " .. tostring(err))
        print("[TIP] Try using a different executor")
    end
end

function SaveModule.Load(jsonData)
    local success, data = pcall(function()
        return HttpService:JSONDecode(jsonData)
    end)
    
    if not success then
        notify("Error", "Invalid JSON!")
        print("[ERROR] JSON decode failed: " .. tostring(data))
        return
    end
    
    if not data.frames then
        notify("Error", "No frames in file!")
        print("[ERROR] Missing 'frames' field in JSON")
        return
    end
    
    RecordModule.Clear()
    
    local loadedCount = 0
    for i, compressed in ipairs(data.frames) do
        local success, result = pcall(function()
            local pos = compressed[1]:split(",")
            local rot = compressed[2]:split(",")
            local vel = compressed[3]:split(",")
            local moveDir = compressed[4]:split(",")
            
            local cf = CFrame.new(
                tonumber(pos[1]), tonumber(pos[2]), tonumber(pos[3])
            ) * CFrame.Angles(
                tonumber(rot[1]), tonumber(rot[2]), tonumber(rot[3])
            )
            
            local stateValue = compressed[7] or 8
            local humanoidState = Enum.HumanoidStateType.Running
            
            if stateValue == 0 then humanoidState = Enum.HumanoidStateType.FallingDown
            elseif stateValue == 1 then humanoidState = Enum.HumanoidStateType.Running
            elseif stateValue == 2 then humanoidState = Enum.HumanoidStateType.RunningNoPhysics
            elseif stateValue == 3 then humanoidState = Enum.HumanoidStateType.Climbing
            elseif stateValue == 4 then humanoidState = Enum.HumanoidStateType.StrafingNoPhysics
            elseif stateValue == 5 then humanoidState = Enum.HumanoidStateType.Ragdoll
            elseif stateValue == 6 then humanoidState = Enum.HumanoidStateType.GettingUp
            elseif stateValue == 7 then humanoidState = Enum.HumanoidStateType.Jumping
            elseif stateValue == 8 then humanoidState = Enum.HumanoidStateType.Running
            elseif stateValue == 10 then humanoidState = Enum.HumanoidStateType.Freefall
            elseif stateValue == 11 then humanoidState = Enum.HumanoidStateType.Flying
            elseif stateValue == 12 then humanoidState = Enum.HumanoidStateType.Landed
            elseif stateValue == 13 then humanoidState = Enum.HumanoidStateType.Swimming
            elseif stateValue == 15 then humanoidState = Enum.HumanoidStateType.Dead
            else humanoidState = Enum.HumanoidStateType.Running
            end
            
            table.insert(Recording.frames, {
                cf = cf,
                vel = Vector3.new(tonumber(vel[1]), tonumber(vel[2]), tonumber(vel[3])),
                moveDir = Vector3.new(tonumber(moveDir[1]), tonumber(moveDir[2]), tonumber(moveDir[3])),
                jump = compressed[5] == 1,
                speed = compressed[6],
                state = humanoidState
            })
            
            loadedCount = loadedCount + 1
        end)
        
        if not success then
            print("[WARNING] Failed to load frame " .. i .. ": " .. tostring(result))
        end
    end
    
    if loadedCount > 0 then
        notify("Loaded!", loadedCount .. " frames")
        print("╔═══════════════════════════════════════════════════╗")
        print("║  FILE LOADED SUCCESSFULLY!")
        print("║  Frames loaded: " .. loadedCount .. " / " .. #data.frames)
        print("║  Version: " .. (data.version or "unknown"))
        print("╚═══════════════════════════════════════════════════╝")
        updateUI()
    else
        notify("Error", "No frames loaded!")
        print("[ERROR] All frames failed to load")
    end
end

function SaveModule.LoadFromFile()
    if not isfolder or not listfiles or not readfile then
        notify("Error", "Executor doesn't support file functions!")
        print("[ERROR] Missing functions: isfolder, listfiles, or readfile")
        print("[TIP] Your executor doesn't support file operations")
        return
    end
    
    if not isfolder(SaveFolder) then
        notify("Error", "No recordings folder!")
        print("[ERROR] Folder not found: " .. SaveFolder)
        print("[TIP] Try saving a recording first to create the folder")
        return
    end
    
    local success, result = pcall(function()
        local allFiles = listfiles(SaveFolder)
        local files = {}
        
        print("[DEBUG] Total files in folder: " .. #allFiles)
        
        for _, file in ipairs(allFiles) do
            if file:match("%.json$") then
                table.insert(files, file)
            end
        end
        
        if #files == 0 then
            notify("Error", "No .json recordings found!")
            print("[ERROR] Folder: " .. SaveFolder)
            print("[ERROR] .json files found: 0")
            print("[ERROR] Total files: " .. #allFiles)
            
            if #allFiles > 0 then
                print("[DEBUG] Files in folder:")
                for i, file in ipairs(allFiles) do
                    local filename = file:match("([^/\\]+)$") or file
                    print("  " .. i .. ". " .. filename)
                end
                print("[TIP] Make sure files have .json extension")
            else
                print("[TIP] Folder is empty. Save a recording first!")
            end
            return false
        end
        
        table.sort(files, function(a, b) return a > b end)
        
        print("╔═══════════════════════════════════════════════════╗")
        print("║  FOUND " .. #files .. " RECORDING FILE(S):")
        for i, file in ipairs(files) do
            local filename = file:match("([^/\\]+)$") or file
            print("║  " .. i .. ". " .. filename)
        end
        print("╚═══════════════════════════════════════════════════╝")
        
        SaveModule.ShowFilePicker(files)
        return true
    end)
    
    if not success then
        notify("Error", "Load failed!")
        print("[ERROR] " .. tostring(result))
        print("[TIP] Check console for details")
    end
end

function SaveModule.ShowFilePicker(files)
    local existing = LP.PlayerGui:FindFirstChild("FilePickerGUI")
    if existing then existing:Destroy() end
    
    local sg = Instance.new("ScreenGui")
    sg.Name = "FilePickerGUI"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = LP.PlayerGui
    
    local bg = Instance.new("Frame", sg)
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.5
    bg.BorderSizePixel = 0
    
    local picker = Instance.new("Frame", bg)
    picker.Size = UDim2.new(0, 400, 0, 450)
    picker.Position = UDim2.new(0.5, -200, 0.5, -225)
    picker.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    picker.BorderSizePixel = 0
    Instance.new("UICorner", picker).CornerRadius = UDim.new(0, 12)
    
    local stroke = Instance.new("UIStroke", picker)
    stroke.Color = Color3.fromRGB(0, 255, 120)
    stroke.Thickness = 2
    
    local header = Instance.new("Frame", picker)
    header.Size = UDim2.new(1, 0, 0, 45)
    header.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    header.BorderSizePixel = 0
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
    
    local headerFix = Instance.new("Frame", header)
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    headerFix.BorderSizePixel = 0
    
    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "📁 Select Recording (" .. #files .. " files)"
    title.TextColor3 = Color3.new(0, 0, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    
    local closeBtn = Instance.new("TextButton", header)
    closeBtn.Size = UDim2.new(0, 35, 0, 35)
    closeBtn.Position = UDim2.new(1, -40, 0, 5)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(0, 0, 0)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    closeBtn.BackgroundTransparency = 1
    closeBtn.MouseButton1Click:Connect(function()
        sg:Destroy()
    end)
    
    local scroll = Instance.new("ScrollingFrame", picker)
    scroll.Size = UDim2.new(1, -20, 1, -95)
    scroll.Position = UDim2.new(0, 10, 0, 55)
    scroll.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Color3.fromRGB(0, 255, 120)
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    
    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    
    for i, filePath in ipairs(files) do
        local filename = filePath:match("([^/\\]+)$") or filePath
        
        local dateStr = filename:match("Recording_(%d+_%d+)")
        local displayName = filename
        if dateStr then
            local year = dateStr:sub(1, 4)
            local month = dateStr:sub(5, 6)
            local day = dateStr:sub(7, 8)
            local hour = dateStr:sub(10, 11)
            local min = dateStr:sub(12, 13)
            local sec = dateStr:sub(14, 15)
            displayName = string.format("%s/%s/%s %s:%s:%s", day, month, year, hour, min, sec)
        end
        
        local btn = Instance.new("TextButton", scroll)
        btn.Size = UDim2.new(1, -10, 0, 50)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        
        local nameLabel = Instance.new("TextLabel", btn)
        nameLabel.Size = UDim2.new(1, -15, 0, 22)
        nameLabel.Position = UDim2.new(0, 10, 0, 5)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = "📄 " .. displayName
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        
        local fileLabel = Instance.new("TextLabel", btn)
        fileLabel.Size = UDim2.new(1, -15, 0, 18)
        fileLabel.Position = UDim2.new(0, 10, 0, 27)
        fileLabel.BackgroundTransparency = 1
        fileLabel.Text = filename
        fileLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        fileLabel.Font = Enum.Font.Gotham
        fileLabel.TextSize = 9
        fileLabel.TextXAlignment = Enum.TextXAlignment.Left
        
        btn.MouseEnter:Connect(function()
            btn.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
            nameLabel.TextColor3 = Color3.new(0, 0, 0)
            fileLabel.TextColor3 = Color3.fromRGB(30, 30, 30)
        end)
        
        btn.MouseLeave:Connect(function()
            btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            fileLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        end)
        
        btn.MouseButton1Click:Connect(function()
            sg:Destroy()
            
            print("[LOADING] " .. filename)
            notify("Loading...", displayName)
            
            local success, data = pcall(function()
                return readfile(filePath)
            end)
            
            if success and data and data ~= "" then
                print("[DEBUG] File size: " .. #data .. " bytes")
                SaveModule.Load(data)
            else
                notify("Error", "Could not read file!")
                print("[ERROR] Failed to read: " .. filePath)
            end
        end)
    end
    
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end)
    scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    
    local cancelBtn = Instance.new("TextButton", picker)
    cancelBtn.Size = UDim2.new(1, -20, 0, 35)
    cancelBtn.Position = UDim2.new(0, 10, 1, -45)
    cancelBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    cancelBtn.BorderSizePixel = 0
    cancelBtn.Font = Enum.Font.GothamBold
    cancelBtn.TextSize = 13
    cancelBtn.TextColor3 = Color3.new(1, 1, 1)
    cancelBtn.Text = "❌ Cancel"
    Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 8)
    
    cancelBtn.MouseButton1Click:Connect(function()
        sg:Destroy()
    end)
end

-- ════════════════════════════════════════════════════════════
-- UI SYSTEM (TAB-BASED WITH RECORD/REPLAY PAGES)
-- ════════════════════════════════════════════════════════════
local GUI = {}

function GUI.Create()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AutoWalkGUI"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = LP:WaitForChild("PlayerGui")
    
    -- MINIMIZED ICON
    local miniIcon = Instance.new("Frame", sg)
    miniIcon.Name = "MiniIcon"
    miniIcon.Size = UDim2.new(0, 55, 0, 55)
    miniIcon.Position = UDim2.new(0.02, 0, 0.5, -27)
    miniIcon.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    miniIcon.BorderSizePixel = 0
    miniIcon.Visible = false
    miniIcon.Active = true
    miniIcon.ZIndex = 999
    Instance.new("UICorner", miniIcon).CornerRadius = UDim.new(1, 0)
    
    local miniStroke = Instance.new("UIStroke", miniIcon)
    miniStroke.Color = Color3.fromRGB(255, 255, 255)
    miniStroke.Thickness = 3
    
    local miniLabel = Instance.new("TextLabel", miniIcon)
    miniLabel.Size = UDim2.new(1, 0, 1, 0)
    miniLabel.BackgroundTransparency = 1
    miniLabel.Text = "🎬"
    miniLabel.TextColor3 = Color3.new(0, 0, 0)
    miniLabel.Font = Enum.Font.GothamBold
    miniLabel.TextSize = 28
    miniLabel.ZIndex = 1000
    
    -- Main Frame
    local main = Instance.new("Frame", sg)
    main.Name = "Main"
    main.Size = UDim2.new(0, 220, 0, 280)
    main.Position = UDim2.new(0.98, -220, 0.02, 0)
    main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    main.BorderSizePixel = 0
    main.Active = true
    main.ClipsDescendants = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(0, 255, 120)
    stroke.Thickness = 2
    
    -- Header
    local header = Instance.new("Frame", main)
    header.Size = UDim2.new(1, 0, 0, 28)
    header.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    header.BorderSizePixel = 0
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
    
    local headerFix = Instance.new("Frame", header)
    headerFix.Size = UDim2.new(1, 0, 0, 10)
    headerFix.Position = UDim2.new(0, 0, 1, -10)
    headerFix.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    headerFix.BorderSizePixel = 0
    
    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 8, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🎬 Auto Walk"
    title.TextColor3 = Color3.new(0, 0, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Hide button
    local hideBtn = Instance.new("TextButton", header)
    hideBtn.Name = "HideBtn"
    hideBtn.Size = UDim2.new(0, 20, 0, 20)
    hideBtn.Position = UDim2.new(1, -46, 0, 4)
    hideBtn.Text = "—"
    hideBtn.TextColor3 = Color3.new(0, 0, 0)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 13
    hideBtn.BackgroundTransparency = 1
    
    -- Close button
    local closeBtn = Instance.new("TextButton", header)
    closeBtn.Size = UDim2.new(0, 20, 0, 20)
    closeBtn.Position = UDim2.new(1, -24, 0, 4)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(0, 0, 0)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 11
    closeBtn.BackgroundTransparency = 1
    closeBtn.MouseButton1Click:Connect(function()
        State.guiVisible = false
        main.Visible = false
        miniIcon.Visible = true
        miniIcon.Position = UDim2.new(0, main.AbsolutePosition.X, 0, main.AbsolutePosition.Y)
        notify("Hidden", "Press H to show")
    end)
    
    -- TAB CONTAINER
    local tabContainer = Instance.new("Frame", main)
    tabContainer.Name = "TabContainer"
    tabContainer.Size = UDim2.new(1, -10, 0, 28)
    tabContainer.Position = UDim2.new(0, 5, 0, 33)
    tabContainer.BackgroundTransparency = 1
    
    -- RECORD TAB
    local recordTab = Instance.new("TextButton", tabContainer)
    recordTab.Name = "RecordTab"
    recordTab.Size = UDim2.new(0.5, -2, 1, 0)
    recordTab.Position = UDim2.new(0, 0, 0, 0)
    recordTab.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    recordTab.BorderSizePixel = 0
    recordTab.Font = Enum.Font.GothamBold
    recordTab.TextSize = 10
    recordTab.TextColor3 = Color3.new(0, 0, 0)
    recordTab.Text = "🎬 RECORD"
    recordTab.AutoButtonColor = false
    Instance.new("UICorner", recordTab).CornerRadius = UDim.new(0, 6)
    
    -- REPLAY TAB
    local replayTab = Instance.new("TextButton", tabContainer)
    replayTab.Name = "ReplayTab"
    replayTab.Size = UDim2.new(0.5, -2, 1, 0)
    replayTab.Position = UDim2.new(0.5, 2, 0, 0)
    replayTab.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    replayTab.BorderSizePixel = 0
    replayTab.Font = Enum.Font.GothamBold
    replayTab.TextSize = 10
    replayTab.TextColor3 = Color3.fromRGB(150, 150, 150)
    replayTab.Text = "📺 REPLAY"
    replayTab.AutoButtonColor = false
    Instance.new("UICorner", replayTab).CornerRadius = UDim.new(0, 6)
    
    -- Content container
    local content = Instance.new("Frame", main)
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -66)
    content.Position = UDim2.new(0, 0, 0, 66)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    
    -- Status Label
    local statusLabel = Instance.new("TextLabel", content)
    statusLabel.Name = "Status"
    statusLabel.Size = UDim2.new(1, -10, 0, 16)
    statusLabel.Position = UDim2.new(0, 5, 0, 5)
    statusLabel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    statusLabel.Text = "⏹ Ready"
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 9
    statusLabel.TextWrapped = true
    statusLabel.TextScaled = false
    Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 4)
    
    -- Info Label
    local infoLabel = Instance.new("TextLabel", content)
    infoLabel.Name = "Info"
    infoLabel.Size = UDim2.new(1, -10, 0, 12)
    infoLabel.Position = UDim2.new(0, 5, 0, 24)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "Frames: 0 | Time: 00:00"
    infoLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 7
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextWrapped = true
    infoLabel.TextScaled = false
    
    -- Progress Bar
    local progressBG = Instance.new("Frame", content)
    progressBG.Size = UDim2.new(1, -10, 0, 2)
    progressBG.Position = UDim2.new(0, 5, 0, 39)
    progressBG.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    progressBG.BorderSizePixel = 0
    Instance.new("UICorner", progressBG).CornerRadius = UDim.new(1, 0)
    
    local progressBar = Instance.new("Frame", progressBG)
    progressBar.Name = "Bar"
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    progressBar.BorderSizePixel = 0
    Instance.new("UICorner", progressBar).CornerRadius = UDim.new(1, 0)
    
    -- RECORD PAGE CONTAINER
    local recordPage = Instance.new("Frame", content)
    recordPage.Name = "RecordPage"
    recordPage.Size = UDim2.new(1, -10, 1, -46)
    recordPage.Position = UDim2.new(0, 5, 0, 44)
    recordPage.BackgroundTransparency = 1
    recordPage.Visible = true
    recordPage.ClipsDescendants = true
    
    local recordLayout = Instance.new("UIListLayout", recordPage)
    recordLayout.Padding = UDim.new(0, 3)
    recordLayout.SortOrder = Enum.SortOrder.LayoutOrder
    
    -- REPLAY PAGE CONTAINER
    local replayPage = Instance.new("Frame", content)
    replayPage.Name = "ReplayPage"
    replayPage.Size = UDim2.new(1, -10, 1, -46)
    replayPage.Position = UDim2.new(0, 5, 0, 44)
    replayPage.BackgroundTransparency = 1
    replayPage.Visible = false
    replayPage.ClipsDescendants = true
    
    local replayLayout = Instance.new("UIListLayout", replayPage)
    replayLayout.Padding = UDim.new(0, 3)
    replayLayout.SortOrder = Enum.SortOrder.LayoutOrder
    
    -- Click mini icon to expand
    local miniBtn = Instance.new("TextButton", miniIcon)
    miniBtn.Size = UDim2.new(1, 0, 1, 0)
    miniBtn.BackgroundTransparency = 1
    miniBtn.Text = ""
    miniBtn.ZIndex = 1001
    miniBtn.MouseButton1Click:Connect(function()
        State.guiVisible = true
        miniIcon.Visible = false
        main.Visible = true
    end)
    
    -- Hide/Show functionality
    hideBtn.MouseButton1Click:Connect(function()
        State.guiVisible = false
        main.Visible = false
        miniIcon.Visible = true
        miniIcon.Position = UDim2.new(0, main.AbsolutePosition.X, 0, main.AbsolutePosition.Y)
    end)
    
    GUI.Main = main
    GUI.Content = content
    GUI.StatusLabel = statusLabel
    GUI.InfoLabel = infoLabel
    GUI.ProgressBar = progressBar
    GUI.RecordPage = recordPage
    GUI.ReplayPage = replayPage
    GUI.RecordTab = recordTab
    GUI.ReplayTab = replayTab
    GUI.MiniIcon = miniIcon
    
    return sg
end

-- TAB SWITCHING
function GUI.SwitchToRecord()
    GUI.RecordTab.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    GUI.RecordTab.TextColor3 = Color3.new(0, 0, 0)
    
    GUI.ReplayTab.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    GUI.ReplayTab.TextColor3 = Color3.fromRGB(150, 150, 150)
    
    GUI.RecordPage.Visible = true
    GUI.ReplayPage.Visible = false
    
    print("[GUI] Switched to RECORD mode")
end

function GUI.SwitchToReplay()
    GUI.ReplayTab.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    GUI.ReplayTab.TextColor3 = Color3.new(0, 0, 0)
    
    GUI.RecordTab.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    GUI.RecordTab.TextColor3 = Color3.fromRGB(150, 150, 150)
    
    GUI.RecordPage.Visible = false
    GUI.ReplayPage.Visible = true
    
    print("[GUI] Switched to REPLAY mode")
end

-- Create button for specific page
function GUI.CreateButton(text, color, callback, page)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 24)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text = text
    btn.TextWrapped = true
    btn.TextScaled = false
    btn.Parent = page
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    
    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- Create speed button
function GUI.CreateSpeedButton(speed, parent)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.23, 0, 0, 22)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = Color3.fromRGB(200, 200, 200)
    btn.Text = speed .. "x"
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    
    btn.MouseButton1Click:Connect(function()
        SpeedModule.SetSpeed(speed)
    end)
    
    return btn
end

-- Update speed button visuals
function GUI.UpdateSpeedButtons()
    if not GUI.SpeedButtons then return end
    
    for speed, btn in pairs(GUI.SpeedButtons) do
        if speed == Config.playbackSpeed then
            btn.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
            btn.TextColor3 = Color3.new(0, 0, 0)
            btn.Text = "●" .. speed .. "x"
        else
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            btn.TextColor3 = Color3.fromRGB(200, 200, 200)
            btn.Text = speed .. "x"
        end
    end
end

function GUI.MakeDraggable(frame)
    local dragging, dragStart, startPos
    
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or 
           input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ════════════════════════════════════════════════════════════
-- UI UPDATE FUNCTIONS
-- ════════════════════════════════════════════════════════════
function updateStatus(text)
    if GUI.StatusLabel then
        GUI.StatusLabel.Text = text
    end
end

function updateUI()
    if GUI.InfoLabel then
        GUI.InfoLabel.Text = string.format("Frames: %d / %d | Time: %s | Speed: %.1fx", 
            Recording.currentIndex, 
            #Recording.frames,
            formatTime(#Recording.frames),
            Config.playbackSpeed)
    end
    
    if GUI.ProgressBar and #Recording.frames > 0 then
        local progress = Recording.currentIndex / #Recording.frames
        GUI.ProgressBar:TweenSize(
            UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0),
            Enum.EasingDirection.Out,
            Enum.EasingStyle.Linear,
            0.1,
            true
        )
    end
end

-- ════════════════════════════════════════════════════════════
-- INITIALIZE UI
-- ════════════════════════════════════════════════════════════
local mainGUI = GUI.Create()
GUI.MakeDraggable(GUI.Main)
GUI.MakeDraggable(GUI.MiniIcon)

-- TAB CLICK HANDLERS
GUI.RecordTab.MouseButton1Click:Connect(function()
    GUI.SwitchToRecord()
end)

GUI.ReplayTab.MouseButton1Click:Connect(function()
    GUI.SwitchToReplay()
end)

-- ════════════════════════════════════════════════════════════
-- RECORD PAGE BUTTONS
-- ════════════════════════════════════════════════════════════
GUI.CreateButton("⏺ Record / Stop (R)", Color3.fromRGB(220, 50, 50), function()
    if State.recording then
        RecordModule.Stop()
    else
        RecordModule.Start()
    end
end, GUI.RecordPage)

GUI.CreateButton("⏸ Pause / Resume (Space)", Color3.fromRGB(200, 150, 50), function()
    RecordModule.TogglePause()
end, GUI.RecordPage)

GUI.CreateButton("⏪ Rewind 2s (Backspace)", Color3.fromRGB(255, 150, 0), function()
    RewindModule.StepBack()
end, GUI.RecordPage)

GUI.CreateButton("💾 Save Recording", Color3.fromRGB(0, 150, 200), function()
    SaveModule.Save()
end, GUI.RecordPage)

GUI.CreateButton("🗑️ Clear Recording", Color3.fromRGB(200, 50, 50), function()
    RecordModule.Clear()
end, GUI.RecordPage)

-- ════════════════════════════════════════════════════════════
-- REPLAY PAGE BUTTONS
-- ════════════════════════════════════════════════════════════
GUI.CreateButton("📥 Load Recording", Color3.fromRGB(0, 200, 150), function()
    SaveModule.LoadFromFile()
end, GUI.ReplayPage)

GUI.CreateButton("▶ Play / Stop (P)", Color3.fromRGB(50, 200, 50), function()
    if State.replaying then
        ReplayModule.Stop()
    else
        ReplayModule.Play()
    end
end, GUI.ReplayPage)

-- SPEED CONTROL LABEL
local speedLabel = Instance.new("TextLabel", GUI.ReplayPage)
speedLabel.Size = UDim2.new(1, 0, 0, 16)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "⚡ Playback Speed:"
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 8
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.LayoutOrder = 100

-- SPEED BUTTONS CONTAINER
local speedContainer = Instance.new("Frame", GUI.ReplayPage)
speedContainer.Size = UDim2.new(1, 0, 0, 22)
speedContainer.BackgroundTransparency = 1
speedContainer.LayoutOrder = 101

local speedLayout = Instance.new("UIListLayout", speedContainer)
speedLayout.FillDirection = Enum.FillDirection.Horizontal
speedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
speedLayout.Padding = UDim.new(0, 3)

-- CREATE SPEED BUTTONS
GUI.SpeedButtons = {}
local speeds = {0.5, 0.9, 1.0, 1.5}

for _, speed in ipairs(speeds) do
    local btn = GUI.CreateSpeedButton(speed, speedContainer)
    GUI.SpeedButtons[speed] = btn
end

GUI.UpdateSpeedButtons()

-- ════════════════════════════════════════════════════════════
-- KEYBINDS
-- ════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.R then
        if State.recording then
            RecordModule.Stop()
        else
            RecordModule.Start()
        end
    end
    
    if input.KeyCode == Enum.KeyCode.Space then
        if State.recording then
            RecordModule.TogglePause()
        end
    end
    
    if input.KeyCode == Enum.KeyCode.P then
        if State.replaying then
            ReplayModule.Stop()
        else
            ReplayModule.Play()
        end
    end
    
    if input.KeyCode == Enum.KeyCode.Backspace then
        RewindModule.StepBack()
    end
    
    -- Tab shortcuts
    if input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.KeypadOne then
        GUI.SwitchToRecord()
    end
    
    if input.KeyCode == Enum.KeyCode.Two or input.KeyCode == Enum.KeyCode.KeypadTwo then
        GUI.SwitchToReplay()
    end
    
    if input.KeyCode == Enum.KeyCode.S and input:IsModifierKeyDown(Enum.ModifierKey.Ctrl) then
        SaveModule.Save()
    end
    
    -- H = Hide/Show GUI
    if input.KeyCode == Enum.KeyCode.H then
        State.guiVisible = not State.guiVisible
        
        if State.guiVisible then
            GUI.MiniIcon.Visible = false
            GUI.Main.Visible = true
            print("[GUI] Showing main window (H key)")
        else
            GUI.Main.Visible = false
            GUI.MiniIcon.Visible = true
            GUI.MiniIcon.Position = UDim2.new(0, GUI.Main.AbsolutePosition.X, 0, GUI.Main.AbsolutePosition.Y)
            print("[GUI] Minimized to icon (H key)")
        end
    end
end)

-- ════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ════════════════════════════════════════════════════════════
LP.CharacterAdded:Connect(function()
    task.wait(1)
    if State.recording then RecordModule.Stop() end
    if State.replaying then ReplayModule.Stop() end
end)

-- ════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════
if isfolder and makefolder then
    getWorkspacePath()
    print("[INFO] Using save folder: " .. SaveFolder)
end

notify("Loaded", "Auto Walk v6.2 Ready!")
updateStatus("⏹ Ready")
updateUI()

print("╔═══════════════════════════════════════════════════╗")
print("║  SMOOTH AUTO WALK V6.2 - TAB + LOOP             ║")
print("╠═══════════════════════════════════════════════════╣")
print("║  KEYBINDS:                                        ║")
print("║  R         = Record/Stop                          ║")
print("║  Space     = Pause/Resume (Record only)           ║")
print("║  P         = Play/Stop                            ║")
print("║  Backspace = Rewind 2s (paused only)              ║")
print("║  1         = Switch to RECORD tab                 ║")
print("║  2         = Switch to REPLAY tab                 ║")
print("║  H         = Hide/Show GUI                        ║")
print("║  Ctrl+S    = Quick Save                           ║")
print("╠═══════════════════════════════════════════════════╣")
print("║  NEW FEATURES:                                    ║")
print("║  ✅ Tab-based UI (Record / Replay)                ║")
print("║  ✅ Speed selector: 0.5x, 0.9x, 1x, 1.5x          ║")
print("║  ✅ Auto-loop toggle button                       ║")
print("║  ✅ Smoother interpolation (smoothstep)           ║")
print("║  ✅ Smart start position detection                ║")
print("╠═══════════════════════════════════════════════════╣")
print("║  EXECUTOR COMPATIBILITY:                          ║")
print("║  ✅ Supports file functions: " .. tostring(writefile ~= nil))
print("║  ✅ Folder management: " .. tostring(isfolder ~= nil))
print("║  ✅ File listing: " .. tostring(listfiles ~= nil))
print("╚═══════════════════════════════════════════════════╝")

if not writefile or not isfolder or not listfiles then
    notify("Warning", "File functions not supported!")
    print("[WARNING] Your executor doesn't support file save/load")
    print("[TIP] You can still use the script, but can't save recordings")
else
    print("[SUCCESS] All file functions are available!")
    print("[TIP] Use the tab system: 1=Record, 2=Replay")
    print("[TIP] Speed buttons available in Replay tab")
end
