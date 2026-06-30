require('common')

local ffi = require("ffi")
local d3d = require('d3d8')
local bit = require('bit')

local loaded = false

local loadedZoneId = 0
local currentZoneId = 0
local zoneData = {
    Names = {},
    Indices = {},
}

local icons = {
   detection = {},
   resistances = {},
   immunities = {},
}

-- The bitflags mobdb uses for statuses.
local immunityFlags = {
    Sleep = 0x01,
    Gravity = 0x02,
    Bind = 0x04,
    Stun = 0x08,
    Silence = 0x10,
    Paralyze = 0x20,
    Blind = 0x40,
    Slow = 0x80,
    Poison = 0x100,
    Elegy = 0x200,
    Requiem = 0x400,
    LightSleep = 0x800,
    DarkSleep = 0x1000,
    Petrify = 0x2000,
}

local function LoadMobInfoIcon(name)
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local device =  d3d.get_device();
    if device == nil then
        return nil;
    end

    local path = string.format('%s/submodules/mobdb/icons/%s.png', addon.path, name);
    local res = ffi.C.D3DXCreateTextureFromFileA(device, path, texture_ptr);

    if res ~= 0 then
        -- Texture failed to load - this is expected if file doesn't exist
        return nil;
    end

    return { image = texture_ptr[0] };
end

local function GetMobDataPath()
    local path = string.gsub(addon.path, '\\\\', '\\')
    return path .. 'submodules\\mobdb\\data\\'
end

local function HandleZone(zoneData)
    currentZoneId = zoneData.zone
end

local function LoadZone()
    -- zone 0 doesn't exist
    if currentZoneId == 0 then
        return
    end

    -- let's not read files constantly
    if currentZoneId == loadedZoneId then
        return
    end

    zoneData.Names = {}
    zoneData.Indices = {}
    
    local mobdbFile = GetMobDataPath() .. string.format('%d.lua', currentZoneId)

    local file = io.open(mobdbFile, 'r')
    if file == nil then
        -- No data in this zone, probably
        return
    end
    file:close()

    local func, err = loadfile(mobdbFile)
    if func == nil then
        print('Could not load data for zone ' .. tostring(currentZoneId) .. ': ' .. err)
    end

    local success, result = pcall(func)
    if not success then
        print('Could not load data for zone ' .. tostring(currentZoneId) .. ': ' .. result)
        return
    end

    loadedZoneId = currentZoneId
    if result and result.Names then
        zoneData.Names = result.Names
        zoneData.Indices = result.Indices
    end

end

---comment
---@param name string
---@param index integer
---@return MobData
local function GetMobData(name, index)
    if name == nil then
        return nil
    end

    -- we first check if the index exists,
    -- this gets us the most 'accurate' data
    -- since different spawns mean different jobs, etc.
    if index ~= nil and zoneData.Indices[index] then
        local data = zoneData.Indices[index]
        if data ~= nil then
            return data
        end
    end
    
    -- name is fallback
    if zoneData.Names == nil then
        return nil
    end
    return zoneData.Names[name]
end

---comment
---@param mobData MobData
local function HandleMobLevel(mobData)
    return 'Lv' .. tostring(mobData.MinLevel) .. '-' .. tostring(mobData.MaxLevel)
end

---@param mobData MobData
local function HandleMobDetections(mobData)
    local iconsToShow = {}
    local nm = mobData.Notorious

    local aggroIcon = nil
    local aggroName = ''
    if mobData.Aggro then
        aggroIcon = nm and icons.detection.aggroHQ or icons.detection.aggroNQ
        if nm then
            aggroName = 'Aggressive (NM)'
        else
            aggroName = 'Aggressive'
        end
    else
        aggroIcon = nm and icons.detection.passiveHQ or icons.detection.passiveNQ
        if nm then
            aggroName = 'Passive (NM)'
        else
            aggroName = 'Passive'
        end
    end
    table.insert(iconsToShow, {
        name = aggroName,
        icon = aggroIcon,
    })

    if mobData.Link then
        table.insert(iconsToShow, {
            name = 'Link',
            icon = icons.detection.link,
        })
    end

    if mobData.Sight then
        table.insert(iconsToShow, {
            name = 'Sight',
            icon = icons.detection.sight,
        })
    end

    if mobData.TrueSight then
        table.insert(iconsToShow, {
            name = 'True Sight',
            icon = icons.detection.truesight,
        })
    end

    if mobData.Sound then
        table.insert(iconsToShow, {
            name = 'Sound',
            icon = icons.detection.sound,
        })
    end

    if mobData.Scent then
        table.insert(iconsToShow, {
            name = 'Scent',
            icon = icons.detection.scent,
        })
    end

    if mobData.Magic then
        table.insert(iconsToShow, {
            name = 'Magic',
            icon = icons.detection.magic,
        })
    end

    if mobData.JA then
        table.insert(iconsToShow, {
            name = 'Job Ability',
            icon = icons.detection.ja,
        })
    end

    if mobData.Blood then
        table.insert(iconsToShow, {
            name = 'Blood',
            icon = icons.detection.blood,
        })
    end

    return iconsToShow
end

local function FormatModifierDisplay(modifier)
    local delta = (modifier - 1) * 100

    local prefix = delta > 0 and '+' or ''
    return prefix .. string.format('%.2f', delta):gsub('%.?0+$', '') .. '%'
end

local function ModifierSort(a, b)
    return a.modifier > b.modifier
end

---@param mobData MobData
local function HandleMobResistances(mobData)
    local iconsToShow = {}

    for element, modifier in pairs(mobData.Modifiers) do
        if modifier < 1 then
            table.insert(iconsToShow, {
                name = element,
                icon = icons.resistances[string.lower(element)],
                modifier = FormatModifierDisplay(modifier),
            })
        end
    end

    table.sort(iconsToShow, ModifierSort)

    return iconsToShow
end

---@param mobData MobData
local function HandleMobWeaknesses(mobData)
    local iconsToShow = {}
    for element, modifier in pairs(mobData.Modifiers) do
        if modifier > 1 then
            table.insert(iconsToShow, {
                name = element,
                icon = icons.resistances[string.lower(element)],
                modifier = FormatModifierDisplay(modifier),
            })
        end
    end

    table.sort(iconsToShow, ModifierSort)

    return iconsToShow
end

---@param mobData MobData
local function HandleMobImmunities(mobData)
    -- might as well bail if there's nothing there
    if mobData.Immunities == nil or mobData.Immunities == 0 then
        return {}
    end

    local iconsToShow = {}
    for name, flag in pairs(immunityFlags) do
        if bit.band(mobData.Immunities, flag) ~= 0 then
            table.insert(iconsToShow, {
                name = 'Immune to ' .. name,
                icon = icons.immunities[string.lower(name)],
            })
        end
    end
    return iconsToShow
end

-- Loads all icons into memory.
local function InitializeIcons()
    if loaded then
        return
    end
    loaded = true

    icons.detection.aggroNQ = LoadMobInfoIcon('AggroNQ')
    icons.detection.aggroHQ = LoadMobInfoIcon('AggroHQ')
    icons.detection.passiveNQ = LoadMobInfoIcon('PassiveNQ')
    icons.detection.passiveHQ = LoadMobInfoIcon('PassiveHQ')
    icons.detection.link = LoadMobInfoIcon('Link')
    icons.detection.sight = LoadMobInfoIcon('Sight')
    icons.detection.truesight = LoadMobInfoIcon('TrueSight')
    icons.detection.sound = LoadMobInfoIcon('Sound')
    icons.detection.scent = LoadMobInfoIcon('Scent')
    icons.detection.magic = LoadMobInfoIcon('Magic')
    icons.detection.ja = LoadMobInfoIcon('JA')
    icons.detection.blood = LoadMobInfoIcon('Blood')

    icons.resistances.fire = LoadMobInfoIcon('Fire')
    icons.resistances.ice = LoadMobInfoIcon('Ice')
    icons.resistances.wind = LoadMobInfoIcon('Wind')
    icons.resistances.earth = LoadMobInfoIcon('Earth')
    icons.resistances.lightning = LoadMobInfoIcon('Lightning')
    icons.resistances.water = LoadMobInfoIcon('Water')
    icons.resistances.light = LoadMobInfoIcon('Light')
    icons.resistances.dark = LoadMobInfoIcon('Dark')
    icons.resistances.slashing = LoadMobInfoIcon('Slashing')
    icons.resistances.piercing = LoadMobInfoIcon('Piercing')
    icons.resistances.h2h = LoadMobInfoIcon('H2H')
    icons.resistances.impact = LoadMobInfoIcon('Impact')

    icons.immunities.sleep = LoadMobInfoIcon('ImmuneSleep')
    icons.immunities.gravity = LoadMobInfoIcon('ImmuneGravity')
    icons.immunities.silence = LoadMobInfoIcon('ImmuneSilence')
    icons.immunities.bind = LoadMobInfoIcon('ImmuneBind')
    icons.immunities.stun = LoadMobInfoIcon('ImmuneStun')
    icons.immunities.silence = LoadMobInfoIcon('ImmuneSilence')
    icons.immunities.paralyze = LoadMobInfoIcon('ImmuneParalyze')
    icons.immunities.blind = LoadMobInfoIcon('ImmuneBlind')
    icons.immunities.slow = LoadMobInfoIcon('ImmuneSlow')
    icons.immunities.poison = LoadMobInfoIcon('ImmunePoison')
    icons.immunities.elegy = LoadMobInfoIcon('ImmuneElegy')
    icons.immunities.requiem = LoadMobInfoIcon('ImmuneRequiem')
    icons.immunities.petrify = LoadMobInfoIcon('ImmunePetrify')
    icons.immunities.darksleep = LoadMobInfoIcon('ImmuneDarkSleep')
    icons.immunities.lightsleep = LoadMobInfoIcon('ImmuneLightSleep')
end

return {
    InitializeIcons = InitializeIcons,
    HandleZone = HandleZone,
    LoadZone = LoadZone,
    GetMobData = GetMobData,
    HandleMobDetections = HandleMobDetections,
    HandleMobLevel = HandleMobLevel,
    HandleMobResistances = HandleMobResistances,
    HandleMobWeaknesses = HandleMobWeaknesses,
    HandleMobImmunities = HandleMobImmunities,
}