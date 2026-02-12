Config = {}

Config.Debug = false -- enable debug prints in server and player console

Config.Language = 'en' -- en, pl

-- Maximum job slots per player
Config.MaxJobs = 5

-- Default job for empty slots
Config.DefaultJob = {
    name = 'unemployed',
    grade = 0
}

Config.DutySystem = {
    enabled = true,
    -- Use state bags for duty status (recommended for cross-script compatibility)
    useStateBags = true,
    -- Prefix for off-duty jobs (e.g., 'police' becomes 'offpolice')
    offDutyPrefix = 'off',
    -- Jobs that support duty system
    dutyJobs = {
        'police',
        'ambulance',
        'mechanic'
    }
}

-- Job restrictions (optional whitelist per job)
Config.JobRestrictions = {
    -- e.g. only certain identifiers can have 'police' job
    -- ['police'] = {
    --     type = 'license', -- 'license' or 'identifier'
    --     whitelist = {
    --         'license:abc123',
    --         'license:def456'
    --     }
    -- }
}

-- Blacklisted jobs (cannot be added to multijob slots)
Config.BlacklistedJobs = {
    -- 'unemployed' -- e.g. prevent unemployed from being manually added
}

Config.MenuCommand = 'multijob'

-- Keymapping for opening menu (optional, set to false to disable)
Config.MenuKey = false -- e.g. 'F6'

Config.AutoSaveInterval = 300000 -- 5 minutes in ms

-- all in ms
Config.Cooldowns = {
    switchJob = 5000, 
    toggleDuty = 3000,
    addRemoveSlot = 10000
}

local function LoadLocale()
    local locale = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(Config.Language))
    
    if not locale then
        print(('^1[Multijob]^0 Locale file "locales/%s.json" not found. Using English as fallback.'):format(Config.Language))
        locale = LoadResourceFile(GetCurrentResourceName(), 'locales/en.json')
    end
    
    if locale then
        Config.Locale = json.decode(locale)
        if Config.Debug then
            print(('^2[Multijob]^0 Loaded locale: %s'):format(Config.Language))
        end
    else
        print('^1[Multijob]^0 Failed to load any locale file.')
        Config.Locale = {}
    end
end

LoadLocale()