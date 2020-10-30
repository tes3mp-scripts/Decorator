local templates = require('custom.MWS-Templates.main')
local sine = templates.mimics.sine
local cosine = templates.mimics.cosine

local decoratorConfig = {
    showMessages = false,
    localization = {
        EnableMessage = color.Green .. "Decorator enabled, activate again for options.",
        DisableMessage = color.Green .. "Decorator disabled.",
        Label = "Decorator Menu",
        PositionButton = "Position 3d",
        RotateXButton = "Yaw",
        RotateYButton = "Pitch",
        RotateZButton = "Roll",
        PauseButton = "Pause",
        ManualButton = "Manual",
        PlaceButton = "Place",
        DisableButton = "Disable"
    },
    defaultMode = "position",
    position = {
        height = 125,
        distance = 75,
        feedback = true
    },
    rotation = {
        sensitivity = 10,
        feedback = true
    },
    defaultMarker = {
        baseId = "misc_dwrv_artifact60"
    }
}


local modes = {
    {
        name = "pause",
        value = -1
    },
    {
        name = "position",
        value = 0
    },
    {
        name = "rotatex",
        value = 1,
        axis = "x",
        inverse = "u"
    },
    {
        name = "rotatey",
        value = 2,
        axis = "y",
        inverse = "v"
    },
    {
        name = "rotatez",
        value = 3,
        axis = "z",
        inverse = "w"
    }
}

local scripts = {
script_decorator_position = templates.process([[
begin script_decorator_position
    float px
    float py
    float pz
    float sx
    float sz
    float cz
    float r
    float r0
    short mode
    ``SINE``
    ``COSINE``

    if (script_decorator_globals.mode != mode)
        set r0 to 0
    endif

    if (script_decorator_globals.mode == 0)
        set px to ( player->GetAngle X )
        set pz to ( player->GetAngle Z )
        set SINE_in to px
        `SINE`
        set sx to SINE_out

        set SINE_in to pz
        `SINE`
        set sz to SINE_out

        set COSINE_in to pz
        `COSINE`
        set cz to COSINE_out

        set px to ( {{position.distance}} * sz + player->GetPos X )
        set py to ( {{position.distance}} * cz + player->GetPos Y )
        set pz to ( {{position.height}} * (1 - sx) + player->GetPos Z )

        {{#position.feedback}}
        MessageBox "%.3f %.3f %.3f", px, py, pz
        {{/position.feedback}}

        SetPos X px
        SetPos Y py
        SetPos Z pz
    endif
    {{#modes}}
    {{#axis}}
    if (script_decorator_globals.mode == {{value}})
        ;set px to GetAngle x
        ;set py to GetAngle y
        ;set pz to GetAngle z

        set r to ( player->GetAngle Z )
        set r to ( r * {{rotation.sensitivity}} )

        ;set p{{axis}} to (r - r0) / GetSecondsPassed
        ;set r0 to r
        ;RotateWorld {{axis}} p{{axis}}

        SetAngle {{axis}} r

        ;set p{{axis}} to r
        ;SetAngle x px
        ;SetAngle y py
        ;SetAngle z pz

        {{#rotation.feedback}}
        set r to (r * `PI` / 180)
        MessageBox "%.3f", r
        {{/rotation.feedback}}
    endif
    {{/axis}}
    {{/modes}}

    set mode to script_decorator_globals.mode
`
    set px to GetAngle x
    set py to GetAngle y
    set pz to GetAngle z
    set px to px * `PI` / 180
    set py to py * `PI` / 180
    set pz to pz * `PI` / 180
    MessageBox "%.3f %.3f %.3f", px, py, pz

    `noPickUp`
end script_decorator_position
]], {
    position = decoratorConfig.position,
    rotation = decoratorConfig.rotation,
    modes = modes
}),

script_decorator_globals = [[
begin script_decorator_globals
    short mode
end script_decorator_globals
]],

script_decorator_menu = templates.process([[
begin script_decorator_menu
    `noPickUp`
end script_decorator_menu
]])
}

for _, mode in pairs(modes) do
    scripts["script_decorator_switch_" .. mode.name] = templates.process(
    [[
    begin script_decorator_switch_{{name}}
        set script_decorator_globals.mode to {{value}}
        stopscript script_decorator_switch_{{name}}
    end script_decorator_switch_{{name}}
    ]],
    mode)
end

--[[for _, script in pairs(scripts) do
    print(script)
end]]

local MENU_REF_ID = "decorator_menu"
local MARKER_REF_ID = "decorator_marker"

local GHOST_RECORD_STORE = nil

local enabled = {}
local placingItems = {}
local originals = {}
local activeMode = {}

local function CalculatePosition(pid, objectLoc)
    Players[pid]:SaveCell()
    local playerLoc = Players[pid].data.location
    objectLoc.posX = playerLoc.posX + decoratorConfig.position.distance * sine(playerLoc.rotZ)
    objectLoc.posY = playerLoc.posY + decoratorConfig.position.distance * cosine(playerLoc.rotZ)
    objectLoc.posZ = playerLoc.posZ + decoratorConfig.position.height * (1 - sine(playerLoc.rotX))
    return objectLoc
end


local function CalculateRotation(pid, objectLoc, axis)
    Players[pid]:SaveCell()
    local playerLoc = Players[pid].data.location
    local rotate = (playerLoc.rotZ) * decoratorConfig.rotation.sensitivity-- % (math.pi * 2)
    --[[if rotate > math.pi then
        rotate = math.pi - rotate
    end]]
    objectLoc[axis] = rotate
    tes3mp.SendMessage(pid, "ROTATE " .. rotate .. "\n")
    return objectLoc
end

local function PlaceAtLocationForPlayer(pid, cellDescription, location, refId)
    local uniqueIndex = WorldInstance:GenerateUniqueIndex()
    local item = {
        uniqueIndex = uniqueIndex,
        refId = refId,
        location = location
    }
    LoadedCells[cellDescription]:LoadObjectsPlaced(
        pid,
        { [item.uniqueIndex] = { location = item.location, refId = item.refId, packetType = "place" } },
        { item.uniqueIndex },
        false
    )
    return item
end

local function DeleteForPlayer(pid, cellDescription, uniqueIndex, refId)
    LoadedCells[cellDescription]:LoadObjectsDeleted(
        pid,
        { [uniqueIndex] = { refId = refId } },
        { uniqueIndex },
        false
    )
end

local function UpdatePlacingLocationForPlayer(pid)
    local cellDescription = tes3mp.GetCell(pid)
    local item = placingItems[pid]
    tableHelper.print(item)
    placingItems[pid] = PlaceAtLocationForPlayer(pid, cellDescription, item.location, item.refId)
    DeleteForPlayer(pid, cellDescription, item.uniqueIndex, item.refId)
end

local function RotateForPlayer(pid, index, delta)
    local location = placingItems[pid].location
    location[index] = location[index] + delta
    UpdatePlacingLocationForPlayer(pid)
end

local function AddDecoratorMenu(pid, limit)
    local inventory = Players[pid].data.inventory
    limit = limit or 1
    local load = false
    local index
    if not inventoryHelper.containsItem(inventory, MENU_REF_ID) then
        inventoryHelper.addItem(inventory, MENU_REF_ID, 1, -1, -1, "")
        load = true
        index = #inventory
        tableHelper.print(inventory[index])
    else
        index = inventoryHelper.getItemIndex(inventory, MENU_REF_ID, -1, -1, "")
        if inventory[index].count < limit then
            load = true
        end
    end

    if load then
        tes3mp.ClearInventoryChanges(pid)
        tes3mp.SetInventoryChangesAction(pid, enumerations.inventory.ADD)
        packetBuilder.AddPlayerInventoryItemChange(pid, inventory[index])
        tes3mp.SendInventoryChanges(pid)
    end
end

local function ReturnOriginal(pid, cellDescription)
    local uniqueIndex = next(originals[pid])
    local original = originals[pid][uniqueIndex]
    inventoryHelper.addItem(
        Players[pid].data.inventory,
        original.refId,
        original.count or 1,
        original.charge or -1,
        original.enchantmentCharge or -1,
        original.soul or ''
    )
    local item = placingItems[pid]
    DeleteForPlayer(pid, cellDescription, item.uniqueIndex, item.refId)

    tes3mp.ClearInventoryChanges(pid)
    tes3mp.SetInventoryChangesAction(pid, enumerations.inventory.ADD)
    packetBuilder.AddPlayerInventoryItemChange(pid, original)
    tes3mp.SendInventoryChanges(pid)

    placingItems[pid] = nil
    originals[pid] = nil
end

local function CalculatePlacingLocation(pid)
    local aMode = activeMode[pid]
    local item = placingItems[pid]
    if aMode == "position" then
        CalculatePosition(pid, item.location)
    elseif aMode == "rotatex" then
        CalculateRotation(pid, item.location, "rotX")
    elseif aMode == "rotatey" then
        CalculateRotation(pid, item.location, "rotY")
    elseif aMode == "rotatez" then
        CalculateRotation(pid, item.location, "rotZ")
    else
        return false
    end
    return true
end

local function SwitchMode(pid, mode)
    logicHandler.RunConsoleCommandOnPlayer(pid,
        "StartScript script_decorator_switch_" .. mode)
    if placingItems[pid] then
        CalculatePlacingLocation(pid)
        --UpdatePlacingLocationForPlayer(pid)
    end
    activeMode[pid] = mode
end

local function PlaceOriginal(pid)
    if placingItems[pid] then
        CalculatePlacingLocation(pid)
        local item = placingItems[pid]
        local originalObjects = originals[pid]
        local originalObject = originalObjects[next(originalObjects)]
        originalObject.location = item.location
        local cellDescription = tes3mp.GetCell(pid)

        local eventStatus = customEventHooks.triggerValidators("OnObjectPlace",
            { pid, cellDescription, originalObjects, {} })
        if eventStatus.validDefaultHandler then
            LoadedCells[cellDescription]:SaveObjectsPlaced(originalObjects)
            LoadedCells[cellDescription]:LoadObjectsPlaced(pid, originalObjects, tableHelper.getArrayFromIndexes(originalObjects), true)
        end
        customEventHooks.triggerHandlers("OnObjectPlace", eventStatus,
            {pid, cellDescription, originalObjects, {}})

        DeleteForPlayer(pid, cellDescription, item.uniqueIndex, item.refId)
        originals[pid] = nil
        placingItems[pid] = nil
        return customEventHooks.makeEventStatus(false, false)
    end
end

local ShowDecoratorMenu = nil
local function ShowManualMenu(pid)
    async.Wrap(function()
        local buttons = {}
        local buttonsMap = {}

        table.insert(buttons, "RX+")
        table.insert(buttonsMap, 'RX+')
        table.insert(buttons, "RX-")
        table.insert(buttonsMap, 'RX-')

        table.insert(buttons, "RY+")
        table.insert(buttonsMap, 'RY+')
        table.insert(buttons, "RY-")
        table.insert(buttonsMap, 'RY-')

        table.insert(buttons, "RZ+")
        table.insert(buttonsMap, 'RZ+')
        table.insert(buttons, "RZ-")
        table.insert(buttonsMap, 'RZ-')

        table.insert(buttons, "Back")
        table.insert(buttonsMap, 'back')

        local buttonNumber = guiHelper.CustomMessageBoxAsync(pid, buttons, decoratorConfig.localization.Label)
        if buttonNumber == nil then
            return
        end
        local result = buttonsMap[buttonNumber]
        if result == 'back' then
            ShowDecoratorMenu(pid)
        else
            local command = string.sub(result, 1, 1)
            local axis = string.sub(result, 2, 2)
            local direction = string.sub(result, 3, 3) == '+' and 1 or -1
            if command == "R" then
                RotateForPlayer(pid, "rot" .. string.upper(axis), direction * 5 * 2 * math.pi / 360)
            end
            ShowManualMenu(pid)
        end
    end)
end

local function ShowAxisMenu(pid, axis)
    async.Wrap(function()

    end)
end

local function ShowDecoratorMenu(pid)
    if not enabled[pid] then
        enabled[pid] = true
        if decoratorConfig.showMessages then
            tes3mp.SendMessage(pid, decoratorConfig.localization.EnableMessage .. "\n")
        end
    end
    async.Wrap(function()
        local buttons = {}
        local buttonsMap = {}

        table.insert(buttons, decoratorConfig.localization.PositionButton)
        table.insert(buttonsMap, 'position')

        table.insert(buttons, decoratorConfig.localization.RotateXButton)
        table.insert(buttonsMap, 'rotatex')
        table.insert(buttons, decoratorConfig.localization.RotateYButton)
        table.insert(buttonsMap, 'rotatey')
        table.insert(buttons, decoratorConfig.localization.RotateZButton)
        table.insert(buttonsMap, 'rotatez')

        table.insert(buttons, decoratorConfig.localization.PauseButton)
        table.insert(buttonsMap, 'pause')

        if not placingItems[pid] then
            table.insert(buttons, decoratorConfig.localization.DisableButton)
            table.insert(buttonsMap, 'disable')
        else
            table.insert(buttons, decoratorConfig.localization.ManualButton)
            table.insert(buttonsMap, 'manual')
            table.insert(buttons, decoratorConfig.localization.PlaceButton)
            table.insert(buttonsMap, 'place')
        end

        local buttonNumber = guiHelper.CustomMessageBoxAsync(pid, buttons, decoratorConfig.localization.Label)
        if buttonNumber == nil then
            return
        end
        local result = buttonsMap[buttonNumber]
        if result == 'disable' then
            enabled[pid] = false
            PlaceOriginal(pid)
            if decoratorConfig.showMessages then
                tes3mp.SendMessage(pid, decoratorConfig.localization.DisableMessage .. "\n")
            end
        elseif result == 'place' then
            PlaceOriginal(pid)
        elseif result == 'manual' then
            SwitchMode(pid, 'pause')
            async.Wrap(function() ShowManualMenu(pid) end)
        else
            SwitchMode(pid, result)
        end
    end)
end

customEventHooks.registerHandler('OnServerPostInit', function(eventStatus)
    if eventStatus.validCustomHandlers then
        GHOST_RECORD_STORE = RecordStores.miscellaneous
        for refId, text in pairs(scripts) do
            RecordStores.script.data.permanentRecords[refId] = {
                scriptText = text
            }
        end

        RecordStores.miscellaneous.data.permanentRecords[MARKER_REF_ID] = decoratorConfig.defaultMarker

        RecordStores.miscellaneous.data.permanentRecords[MENU_REF_ID] = {
            name = "Decorator Menu",
            model = "m/misc_dwrv_gear00.nif",
            icon = "m/misc_dwrv_gear00.dds",
            weight = 0,
            value = 0,
            script = "script_decorator_menu"
        }
    end
end)

customEventHooks.registerHandler('OnPlayerAuthentified', function(eventStatus, pid)
    if eventStatus.validCustomHandlers then
        AddDecoratorMenu(pid)
        SwitchMode(pid, decoratorConfig.defaultMode)
    end
end)

customEventHooks.registerHandler('OnPlayerItemUse', function(eventStatus, pid, refId)
    if eventStatus.validCustomHandlers then
        if refId == MENU_REF_ID then
            ShowDecoratorMenu(pid)
        end
    end
end)

customEventHooks.registerValidator('OnCellUnload', function(eventStatus, pid, cellDescription)
    if eventStatus.validCustomHandlers then
        if placingItems[pid] then
            ReturnOriginal(pid, cellDescription)
        end
    end
end)

--[[customEventHooks.registerValidator('OnPlayerCellChange', function(eventStatus, pid, cellDescription)
    if eventStatus.validCustomHandlers then
        if placingItems[pid] then
            if LoadedCells[cellDescription] and not LoadedCells[cellDescription].isExterior then
                ReturnOriginal(pid, cellDescription)
            end
        end
    end
end)]]

customEventHooks.registerValidator('OnPlayerDisconnect', function(eventStatus, pid)
    if eventStatus.validCustomHandlers then
        if placingItems[pid] then
            ReturnOriginal(pid, tes3mp.GetCell(pid))
        end
        enabled[pid] = nil
        activeMode[pid] = nil
    end
end)

customEventHooks.registerValidator('OnObjectPlace', function(eventStatus, pid, cellDescription, objects)
    if not eventStatus.validCustomHandlers or #objects > 1 then
        return
    end
    for uniqueIndex, object in pairs(objects) do
        if object.refId == MENU_REF_ID then
            AddDecoratorMenu(pid, 2)
            DeleteForPlayer(pid, cellDescription, uniqueIndex, MENU_REF_ID)
            return customEventHooks.makeEventStatus(false, false)
        elseif enabled[pid] and not placingItems[pid] then
            local decoratorEventStatus = customEventHooks.triggerValidators("Decorator_OnActivate",
                { pid, cellDescription, object })
            if not decoratorEventStatus.validDefaultHandler then return end

            local refId = GHOST_RECORD_STORE:GenerateRecordId()
            local records = {
                [refId] = {
                    baseId = object.refId,
                    script = "script_decorator_position"
                }
            }
            GHOST_RECORD_STORE:LoadRecords(pid, records, {refId}, false)
            placingItems[pid] = PlaceAtLocationForPlayer(pid, cellDescription, object.location, refId)
            DeleteForPlayer(pid, cellDescription, uniqueIndex, object.refId)
            originals[pid] = objects

            customEventHooks.triggerHandlers("Decorator_OnActivate", decoratorEventStatus,
                { pid, cellDescription, object })
            return customEventHooks.makeEventStatus(false, false)
        end
    end
end)
