local channels = {}
local jammer = {}
local batteryData = {}
local spawnedDefaultJammer = false
local channelPasswords = {}
local authorizedIdentifiers = {
    ['license:0220b485234c1c55c406fa23024a962052dda556'] = true,
    -- Tambahkan Steam identifier di sini jika sudah ada, contoh:
    -- ['steam:110000xxxxxxxxx'] = true,
}

local function normalizeChannel(channel)
    channel = tonumber(channel)
    if not channel or channel < 1 or channel > Shared.MaxFrequency then return nil end
    return ('%.2f'):format(channel):gsub('0+$', ''):gsub('%.$', '')
end

local function saveChannelPasswords()
    SaveResourceFile(GetCurrentResourceName(), 'channel_passwords.json', json.encode(channelPasswords), -1)
end

local function isRadioAdmin(src)
    if src == 0 then return true end
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if authorizedIdentifiers[identifier:lower()] then return true end
    end
    return false
end

lib.callback.register('mm_radio:server:checkChannelPassword', function(source, channel, password)
    local key = normalizeChannel(channel)
    if not key then return false, 'invalid' end
    local savedPassword = channelPasswords[key]
    if not savedPassword then return true, 'open' end
    if type(password) ~= 'string' or password ~= savedPassword then return false, 'wrong_password' end
    return true, 'accepted'
end)

lib.callback.register('mm_radio:server:getProtectedChannels', function(source)
    if not isRadioAdmin(source) then return nil end
    local result = {}
    for channel in pairs(channelPasswords) do result[#result + 1] = channel end
    table.sort(result, function(a, b) return tonumber(a) < tonumber(b) end)
    return result
end)

lib.callback.register('mm_radio:server:setChannelPassword', function(source, channel, password)
    if not isRadioAdmin(source) then return false, 'Kamu tidak memiliki izin admin.' end
    local key = normalizeChannel(channel)
    if not key then return false, ('Channel harus antara 1 dan %s.'):format(Shared.MaxFrequency) end
    if type(password) ~= 'string' then return false, 'Password tidak valid.' end
    password = password:match('^%s*(.-)%s*$')
    if #password < 3 or #password > 32 then return false, 'Password harus terdiri dari 3 sampai 32 karakter.' end
    channelPasswords[key] = password
    saveChannelPasswords()
    return true, ('Password channel %s berhasil dipasang/diganti dan langsung aktif.'):format(key)
end)

lib.callback.register('mm_radio:server:removeChannelPassword', function(source, channel)
    if not isRadioAdmin(source) then return false, 'Kamu tidak memiliki izin admin.' end
    local key = normalizeChannel(channel)
    if not key then return false, 'Channel tidak valid.' end
    if not channelPasswords[key] then return false, ('Channel %s tidak memakai password.'):format(key) end
    channelPasswords[key] = nil
    saveChannelPasswords()
    return true, ('Password channel %s berhasil dihapus dan langsung nonaktif.'):format(key)
end)

RegisterNetEvent('mm_radio:server:consumeBattery', function(data)
    for i=1, #data do
        local id = data[i]
        if not batteryData[id] then batteryData[id] = 100 end
        local battery = batteryData[id] - Shared.Battery.consume
        batteryData[id] = math.max(battery, 0)
        if batteryData[id] == 0 then
            TriggerClientEvent('mm_radio:client:nocharge', source)
        end
    end
end)

RegisterNetEvent('mm_radio:server:rechargeBattery', function()
    local src = source
    for i=1, #Shared.RadioItem do
        local item = exports.ox_inventory:GetSlotWithItem(src, Shared.RadioItem[i])
        if item then
            local id = item.metadata?.radioId or false
            if not id then return end
            batteryData[id] = 100
            exports.ox_inventory:RemoveItem(src, 'radiocell', 1)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:server:spawnobject', function(data)
    local src = source
	CreateThread(function()
		local entity = CreateObject(joaat(Shared.Jammer.model), data.coords.x, data.coords.y, data.coords.z, true, true, false)
		while not DoesEntityExist(entity) do Wait(50) end
		SetEntityHeading(entity, data.coords.w)
        local netobj = NetworkGetNetworkIdFromEntity(entity)
        if data.canRemove then
            exports.ox_inventory:RemoveItem(src, 'jammer', 1)
        end
        TriggerClientEvent('mm_radio:client:syncobject', -1, {
            enable = true,
            object = netobj,
            coords = data.coords,
            id = data.id,
            range = data.range or Shared.Jammer.range.default,
            allowedChannels = data.allowedChannels or {},
            canRemove = data.canRemove,
            canDamage = data.canDamage
        })
        jammer[#jammer+1] = {
            enable = true,
            entity = entity,
            id = data.id,
            coords = data.coords,
            range = data.range or Shared.Jammer.range.default,
            allowedChannels = data.allowedChannels or {},
            canRemove = data.canRemove,
            canDamage = data.canDamage
        }
	end)
end)

RegisterNetEvent('mm_radio:server:togglejammer', function(id)
    for i=1, #jammer do
        local entity = jammer[i]
        if entity.id == id then
            jammer[i].enable = not jammer[i].enable
            TriggerClientEvent('mm_radio:client:togglejammer', -1, id, jammer[i].enable)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:server:removejammer', function(id, isDamaged)
    local src = source
	CreateThread(function()
        for i=1, #jammer do
            local entity = jammer[i]
            if entity.id == id then
                DeleteEntity(entity.entity)
                TriggerClientEvent('mm_radio:client:removejammer', -1, id)
                table.remove(jammer, i)
                if not isDamaged then
                    exports.ox_inventory:AddItem(src, 'jammer', 1)
                end
                break
            end
        end
	end)
end)

RegisterNetEvent('mm_radio:server:changeJammerRange', function(id, range)
    for i=1, #jammer do
        local entity = jammer[i]
        if entity.id == id then
            jammer[i].range = range
            TriggerClientEvent('mm_radio:client:changeJammerRange', -1, id, range)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:server:removeallowedchannel', function(id, allowedChannels)
    for i=1, #jammer do
        local entity = jammer[i]
        if entity.id == id then
            jammer[i].allowedChannels = allowedChannels
            TriggerClientEvent('mm_radio:client:removeallowedchannel', -1, id, allowedChannels)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:server:addallowedchannel', function(id, allowedChannels)
    for i=1, #jammer do
        local entity = jammer[i]
        if entity.id == id then
            jammer[i].allowedChannels = allowedChannels
            TriggerClientEvent('mm_radio:client:addallowedchannel', -1, id, allowedChannels)
            break
        end
    end
end)

RegisterNetEvent('mm_radio:server:addToRadioChannel', function(channel, username)
    local src = source
    if not channels[channel] then
        channels[channel] = {}
    end
    channels[channel][tostring(src)] = {name = username, isTalking = false}
    TriggerClientEvent('mm_radio:client:radioListUpdate', -1, channels[channel], channel)
end)

RegisterNetEvent('mm_radio:server:removeFromRadioChannel', function(channel)
    local src = source

    if not channels[channel] then return end
    channels[channel][tostring(src)] = nil
    TriggerClientEvent('mm_radio:client:radioListUpdate', -1, channels[channel], channel)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    for i=1, #jammer do
        DeleteEntity(jammer[i].entity)
    end
    jammer = {}
    SaveResourceFile(GetCurrentResourceName(), 'battery.json', json.encode(batteryData), -1)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    batteryData = json.decode(LoadResourceFile(GetCurrentResourceName(), 'battery.json')) or {}
    channelPasswords = json.decode(LoadResourceFile(GetCurrentResourceName(), 'channel_passwords.json')) or {}
end)

AddEventHandler("playerDropped", function()
    local plyid = source
    for id, channel in pairs (channels) do
        if channel[tostring(plyid)] then
            channels[id][tostring(plyid)] = nil
            TriggerClientEvent('mm_radio:client:radioListUpdate', -1, channels[id], id)
            break
        end
    end
end)

RegisterNetEvent("mm_radio:server:createdefaultjammer", function()
    if spawnedDefaultJammer then return end
    for i=1, #Shared.Jammer.default do
        local data = Shared.Jammer.default[i]
        TriggerEvent('mm_radio:server:spawnobject', {
            coords = data.coords,
            id = data.id,
            range = data.range,
            allowedChannels = data.allowedChannels,
            canRemove = false,
            canDamage = data.canDamage
        })
    end
    spawnedDefaultJammer = true
end)

local function SetRadioData(src, slot)
    local player = exports.qbx_core:GetPlayer(src)
    local radioId = player.PlayerData.citizenid .. math.random(1000, 9999)
    local name = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
    exports.ox_inventory:SetMetadata(src, slot, { radioId = radioId, name = name })
    return radioId
end

local function GetSlotWithRadio(source)
    for i=1, #Shared.RadioItem do
        return exports.ox_inventory:GetSlotIdWithItem(source, Shared.RadioItem[i])
    end
end

lib.callback.register('mm_radio:server:getradiodata', function(source, slot)
    if not Shared.Battery.state then return 100, 'PERSONAL' end
    local battery = 100
    local slotid = false
    if not slot then
        slotid = GetSlotWithRadio(source)
    else
        slotid = slot.slot
    end
    local slotData = exports.ox_inventory:GetSlot(source, slotid)
    if slotData and lib.table.contains(Shared.RadioItem, slotData.name) then
        local id = false
        if not slotData.metadata?.radioId then
            id = SetRadioData(source, slotid)
        else
            id = slotData.metadata?.radioId
        end
        battery = id and batteryData[id] or 100
    end
    return battery, id
end)

lib.callback.register('mm_radio:server:getjammer', function()
    return jammer
end)

if Shared.UseCommand then
    if not Shared.Ready then return end
    lib.addCommand('radio', {
        help = 'Open Radio Menu',
        params = {},
    }, function(source)
        TriggerClientEvent('mm_radio:client:use', source, 100)
    end)
    lib.addCommand('jammer', {
        help = 'Setup Jammer',
        params = {},
    }, function(source)
        TriggerClientEvent('mm_radio:client:usejammer', source)
    end)
    lib.addCommand('rechargeradio', {
        help = 'Recharge Radio Battery',
        params = {},
    }, function(source)
        TriggerClientEvent('mm_radio:client:recharge', source)
    end)
end

lib.addCommand('remradiodata', {
    help = 'Remove Radio Data',
    params = {},
}, function(source)
    TriggerClientEvent('mm_radio:client:removedata', source)
end)

lib.addCommand('radiopassword', {
    help = 'Atur password channel radio langsung di dalam kota'
}, function(source)
    if not isRadioAdmin(source) then
        return TriggerClientEvent('ox_lib:notify', source, {
            title = 'Radio Password',
            description = 'License atau Steam identifier kamu tidak memiliki akses.',
            type = 'error'
        })
    end
    TriggerClientEvent('mm_radio:client:openPasswordManager', source)
end)

lib.versionCheck('Qbox-project/mm_radio')
