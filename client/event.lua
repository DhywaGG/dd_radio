local radioInitializing = false
local jammersSynced = false
local initializationGeneration = 0

local function InitializeRadio()
    if radioInitializing then return end
    radioInitializing = true
    local generation = initializationGeneration

    CreateThread(function()
        while generation == initializationGeneration and not Radio:EnsureInitialized(1000) do
            Wait(500)
        end

        if generation ~= initializationGeneration then
            radioInitializing = false
            return
        end

        Radio.playerLoaded = true
        TriggerServerEvent('mm_radio:server:createdefaultjammer')

        if not jammersSynced then
            local jammers = lib.callback.await('mm_radio:server:getjammer', false) or {}
            for i = 1, #jammers do
                jammers[i].entity = NetworkGetNetworkIdFromEntity(jammers[i].entity)
                TriggerEvent('mm_radio:client:syncobject', jammers[i])
            end
            jammersSynced = true
        end

        radioInitializing = false
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if GetCurrentResourceName() ~= resource then return end
    InitializeRadio()
end)

AddEventHandler('onClientResourceStop', function(resource)
    if GetCurrentResourceName() == resource then
        Radio:toggleRadioAnimation(false)
        Radio:RemoveJammerZone()
        if Radio.onRadio then
            Radio:leaveradio()
        end
    end
end)

RegisterNetEvent('mm_radio:client:use', function(slot)
    if Radio.PlayerDead or IsPedFatallyInjured(cache.ped) then return end
    if not Radio:EnsureInitialized(10000) then
        return lib.notify({
            title = 'Radio',
            description = 'Data karakter belum siap. Silakan coba lagi.',
            type = 'error'
        })
    end
    Radio.usingRadio = true
    SetNuiFocus(true, true)
    Radio:toggleRadioAnimation(true)
    local battery, radioId = lib.callback.await('mm_radio:server:getradiodata', false, slot)
    local userdata = Radio.userData[Radio.identifier]
    Radio:SendSvelteMessage("setRadioVisible", {
        radioId = radioId,
        onRadio = Radio.onRadio,
        channel = Radio.RadioChannel,
        volume = Radio.Volume,
        favourite = Radio.favourite,
        recomended = Radio.recomended,
        userData = userdata,
        time = Radio:CalculateTimeToDisplay(),
        street = Radio:getCrossroads(),
        maxChannel = Shared.MaxFrequency,
        locale = Radio.locale,
        channelName = Shared.RadioNames,
        insideJammerZone = Radio.signalJammed,
        battery = battery,
        overlay = Shared.Overlay
    })
    UpdateTime()
    if userdata.allowMovement then
        SetNuiFocusKeepInput(true)
        DisableControls()
    end
end)

RegisterNetEvent('mm_radio:client:usejammer', function()
    if not Shared.Jammer.permission or not (lib.table.contains(Shared.Jammer.permission, Radio.PlayerJob) or lib.table.contains(Shared.Jammer.permission, Radio.PlayerGang)) then
        lib.notify({
            title = 'You dont have permission to use this item',
            type = 'error'
        })
    end
    local plyCoords = GetEntityCoords(cache.ped)
    local forward = GetEntityForwardVector(cache.ped)
    local x, y, z = table.unpack(plyCoords + forward * 1.0)
    local id = math.random(1000, 9999)
    TriggerServerEvent('mm_radio:server:spawnobject', {
        coords = vec4(x, y, z - 1.0, GetEntityHeading(cache.ped)),
        id = id,
        range = Shared.Jammer.range.default,
        allowedChannels = {},
        canRemove = true,
        canDamage = true
    })
end)

RegisterNetEvent('mm_radio:client:syncobject', function(data)
    local entity = NetworkGetEntityFromNetworkId(data.object)
    SetEntityCanBeDamaged(entity, data.canDamage)
    Radio.jammer[#Radio.jammer+1] = {
        id = data.id,
        entity = entity,
        coords = data.coords,
        allowedChannels = data.allowedChannels,
        range = data.range,
        enable = data.enable,
        canRemove = data.canRemove,
        zone = lib.zones.sphere({
            coords = data.coords,
            radius = data.range,
            debug = Shared.Debug,
            jammerid = data.id,
            entity = entity,
            onEnter = OnEnterJammerZone,
            onExit = OnExitJammerZone
        }),
        zoneJammer = lib.zones.sphere({
            coords = data.coords,
            radius = 2.5,
            debug = Shared.Debug,
            jammerid = data.id,
            entity = entity,
            onEnter = OnEnterJammer,
            onExit = OnExitJammer
        })
    }
end)

RegisterNetEvent('mm_radio:client:changeJammerRange', function(id, range)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.zone:remove()
            Wait(1000)
            entity.range = range
            entity.zone = lib.zones.sphere({
                coords = entity.coords,
                radius = range,
                debug = Shared.Debug,
                jammerid = id,
                entity = entity.entity,
                onEnter = OnEnterJammerZone,
                onExit = OnExitJammerZone
            })
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:removeallowedchannel', function(id, allowedChannels)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.allowedChannels = allowedChannels
            Radio:UpdateJammerZone(id, allowedChannels)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:addallowedchannel', function(id, allowedChannels)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.allowedChannels = allowedChannels
            Radio:UpdateJammerZone(id, allowedChannels)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:togglejammer', function(id, state)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.enable = state
            if state then
                entity.zone = lib.zones.sphere({
                    coords = entity.coords,
                    radius = entity.range,
                    debug = Shared.Debug,
                    jammerid = id,
                    entity = entity.entity,
                    onEnter = OnEnterJammerZone,
                    onExit = OnExitJammerZone
                })

            else
                entity.zone:remove()
                Radio:UpdateJammerRemove(id)
            end
            break
        end
    end
end)

RegisterNetEvent('mm_radio:client:removejammer', function(id)
    for i=1, #Radio.jammer do
        local entity = Radio.jammer[i]
        if entity.id == id then
            entity.zone:remove()
            entity.zoneJammer:remove()
            Radio:UpdateJammerRemove(id)
            table.remove(Radio.jammer, i)
        end
    end
end)

RegisterNetEvent('mm_radio:client:remove', function()
    SetNuiFocus(false, false)
    local userdata = Radio.identifier and Radio.userData[Radio.identifier]
    if userdata and userdata.allowMovement then
        SetNuiFocusKeepInput(false)
    end
    Radio:toggleRadioAnimation(false)
    Radio:SendSvelteMessage("setRadioHide", nil)
    SetTimeout(100, function()
        Radio.usingRadio = false
    end)
end)

RegisterNetEvent('mm_radio:client:radioListUpdate', function(players, channel)
    if Radio.RadioChannel == channel then
        Radio:SendSvelteMessage("updateRadioList", players)
    end
end)

RegisterNetEvent('mm_radio:client:nocharge', function()
    Radio:leaveradio()
end)

RegisterNetEvent("mm_radio:client:recharge", function()
    TriggerServerEvent('mm_radio:server:rechargeBattery')
end)

local function passwordNotify(success, message)
    lib.notify({ title = 'Radio Password', description = message, type = success and 'success' or 'error' })
end

RegisterNetEvent('mm_radio:client:openPasswordManager', function()
    lib.registerContext({
        id = 'mm_radio_password_manager',
        title = 'Pengaturan Password Radio',
        options = {
            {
                title = 'Pasang / Ganti Password',
                description = 'Perubahan langsung aktif tanpa restart server.',
                icon = 'lock',
                onSelect = function()
                    local input = lib.inputDialog('Pasang Password Channel', {
                        { type = 'number', label = 'Channel', required = true, min = 1, max = Shared.MaxFrequency, precision = 2, icon = 'tower-broadcast' },
                        { type = 'input', label = 'Password Baru', required = true, min = 3, max = 32, password = true, icon = 'key' }
                    })
                    if not input then return end
                    local success, message = lib.callback.await('mm_radio:server:setChannelPassword', false, input[1], input[2])
                    passwordNotify(success, message)
                end
            },
            {
                title = 'Hapus Password',
                description = 'Jadikan channel terbuka kembali.',
                icon = 'lock-open',
                onSelect = function()
                    local channels = lib.callback.await('mm_radio:server:getProtectedChannels', false)
                    if not channels then return passwordNotify(false, 'Kamu tidak memiliki izin admin.') end
                    if #channels == 0 then return passwordNotify(false, 'Belum ada channel yang memakai password.') end
                    local options = {}
                    for i = 1, #channels do
                        options[#options + 1] = { value = channels[i], label = ('Channel %s'):format(channels[i]) }
                    end
                    local input = lib.inputDialog('Hapus Password Channel', {
                        { type = 'select', label = 'Channel Terkunci', required = true, options = options, icon = 'tower-broadcast' }
                    })
                    if not input then return end
                    local success, message = lib.callback.await('mm_radio:server:removeChannelPassword', false, input[1])
                    passwordNotify(success, message)
                end
            },
            {
                title = 'Lihat Channel Terkunci',
                icon = 'list',
                onSelect = function()
                    local channels = lib.callback.await('mm_radio:server:getProtectedChannels', false)
                    if not channels then return passwordNotify(false, 'Kamu tidak memiliki izin admin.') end
                    local content = #channels > 0 and table.concat(channels, ', ') or 'Tidak ada'
                    lib.alertDialog({ header = 'Channel yang Memakai Password', content = content, centered = true })
                end
            }
        }
    })
    lib.showContext('mm_radio_password_manager')
end)

RegisterNetEvent("pma-voice:radioActive", function(talkingState)
    Radio:SendSvelteMessage("updateRadioTalking", {
        radioId = tostring(Radio.playerServerID),
        radioTalking = talkingState
    })
end)

RegisterNetEvent("pma-voice:setTalkingOnRadio", function(source, talkingState)
    Radio:SendSvelteMessage("updateRadioTalking", {
        radioId = tostring(source),
        radioTalking = talkingState
    })
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    InitializeRadio()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    Radio.hasRadio = false
    Radio:leaveradio()
    Radio.playerLoaded = false
    Radio.identifier = nil
    initializationGeneration = initializationGeneration + 1
    radioInitializing = false
    jammersSynced = false
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    local player = QBX.PlayerData
    player.job = job
    Radio:Init(player)
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    if Radio.playerLoaded then
        Wait(1000)
        Radio:doRadioCheck(val.items)
        Radio.PlayerDead = val.metadata.isdead or val.metadata.inlaststand
    end
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    local player = QBX.PlayerData
    player.gang = gang
    Radio:Init(player)
end)

RegisterNetEvent("QBCore:Client:SetDuty", function(newDuty)
    Radio.PlayerDuty = newDuty
end)

RegisterNetEvent("ND:updateCharacter", function(character)
    Radio.PlayerDead = character.metadata.dead
end)

AddEventHandler('ox_inventory:updateInventory', function()
    Radio:doRadioCheck()
end)

AddEventHandler('gameEventTriggered', function(event, data)
    if event == "CEventNetworkEntityDamage" then
        if not IsEntityAPed(data[1]) then return end
        if data[4] and NetworkGetPlayerIndexFromPed(data[1]) == cache.playerId and IsEntityDead(cache.ped) then
            if Radio.usingRadio then
                TriggerEvent('mm_radio:client:remove')
            end
            if Radio.playerLoaded and Radio.onRadio and Radio.hasRadio and Radio.RadioChannel ~= 0 then
                Radio:leaveradio()
            end
        end
    end
end)

AddStateBagChangeHandler('dead', ('player:%s'):format(cache.serverId), function(_, _, value)
    Radio.PlayerDead = value
end)
