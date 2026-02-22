local ESX = exports['es_extended']:getSharedObject()

local playerjobs = {}
local timeout = {}
local jobcache = {}
local switchingslots = {}
local playercd = {}

local function IsOnCooldown(identifier, action)
    if not playercd[identifier] then
        playercd[identifier] = {}
    end
    local cdtime = Config.Cooldowns[action] or 0
    local lastaction = playercd[identifier][action] or 0
    local time = GetGameTimer()
    if time - lastaction < cdtime then
        return true, math.ceil((cdtime - (time - lastaction)) / 1000)
    end
    return false, 0
end

local function SetCooldown(identifier, action)
    if not playercd[identifier] then
        playercd[identifier] = {}
    end
    playercd[identifier][action] = GetGameTimer()
end

CreateThread(function()
    local oldtable = MySQL.single.await([[
        SELECT COUNT(*) as count 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE() 
        AND table_name = 'multijob_slots'
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS multijob_data (
            identifier VARCHAR(60) NOT NULL PRIMARY KEY,
            slots_data LONGTEXT NOT NULL,
            active_slot INT NOT NULL DEFAULT 1,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_identifier (identifier)
        )
    ]])

    if oldtable and oldtable.count > 0 then
        local olddata = MySQL.query.await('SELECT * FROM multijob_slots ORDER BY identifier, slot')
        if olddata and #olddata > 0 then
            local playerdata = {}
            for _, row in ipairs(olddata) do
                if not playerdata[row.identifier] then
                    playerdata[row.identifier] = {
                        slots = {},
                        activeSlot = 1
                    }
                end
                playerdata[row.identifier].slots[tostring(row.slot)] = {
                    job = row.job,
                    grade = row.grade
                }
                if row.is_active == 1 then
                    playerdata[row.identifier].activeSlot = row.slot
                end
            end
            for identifier, data in pairs(playerdata) do
                local slotsjson = json.encode(data.slots)
                MySQL.query.await([[
                    INSERT INTO multijob_data (identifier, slots_data, active_slot)
                    VALUES (?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                    slots_data = VALUES(slots_data),
                    active_slot = VALUES(active_slot)
                ]], {identifier, slotsjson, data.activeSlot})
            end
            print('^2[Multijob]^0 Migrated ' .. #olddata .. ' rows from old table')
        end
        MySQL.query.await('DROP TABLE IF EXISTS multijob_slots')
        print('^2[Multijob]^0 Old table dropped')
    end

    if Config.Debug then
        print('^2[Multijob]^0 Database initialized (single row per player)')
    end
end)

local function DoesJobExist(jobname, grade)
    local cache = jobname .. '_' .. grade
    if jobcache[cache] ~= nil then
        return jobcache[cache]
    end

    local result = MySQL.single.await('SELECT 1 FROM jobs WHERE name = ? LIMIT 1', {jobname})
    if not result then
        jobcache[cache] = false
        return false
    end

    local graderes = MySQL.single.await('SELECT 1 FROM job_grades WHERE job_name = ? AND grade = ? LIMIT 1', {jobname, grade})
    local exists = graderes ~= nil
    jobcache[cache] = exists
    return exists
end

local function IsPlayerWhitelisted(identifier, jobname)
    local restrictions = Config.JobRestrictions[jobname]
    if not restrictions then return true end

    for _, allowed in ipairs(restrictions.whitelist) do
        if identifier:find(allowed) then
            return true
        end
    end
    return false
end

local function IsJobBlacklisted(jobname)
    for _, blacklisted in ipairs(Config.BlacklistedJobs) do
        if blacklisted == jobname then
            return true
        end
    end
    return false
end

local function GetOffDutyJobName(jobname)
    if not Config.DutySystem.enabled then return jobname end
    for _, dutyjob in ipairs(Config.DutySystem.dutyJobs) do
        if dutyjob == jobname then
            return Config.DutySystem.offDutyPrefix .. jobname
        end
    end
    return jobname
end

local function GetOnDutyJobName(jobname)
    if not Config.DutySystem.enabled then return jobname end
    local prefix = Config.DutySystem.offDutyPrefix
    local prefixlen = #prefix
    if jobname:sub(1, prefixlen) == prefix then
        local basicjobname = jobname:sub(prefixlen + 1)
        for _, dutyjob in ipairs(Config.DutySystem.dutyJobs) do
            if dutyjob == basicjobname then
                return basicjobname
            end
        end
    end
    return jobname
end

local function IsJobDutyEnabled(jobname)
    if not Config.DutySystem.enabled then return false end
    for _, dutyjob in ipairs(Config.DutySystem.dutyJobs) do
        if dutyjob == jobname then
            return true
        end
    end
    return false
end

local function UpdateDutyStateBag(source, onDuty)
    if not Config.DutySystem.useStateBags then return end
    local playerState = Player(source).state
    playerState:set('onDuty', onDuty, true)
    if Config.Debug then
        print(('^3[Multijob]^0 Player %d duty state: %s'):format(
            source, 
            onDuty and 'ON' or 'OFF'
        ))
    end
end

local function LoadPlayerJobs(identifier)
    local result = MySQL.single.await([[
        SELECT slots_data, active_slot 
        FROM multijob_data 
        WHERE identifier = ?
    ]], {identifier})

    local jobs = {}
    local activeSlot = 1

    if result and result.slots_data then
        local success, decoded = pcall(json.decode, result.slots_data)
        if success and decoded then
            for key, value in pairs(decoded) do
                local slotNum = tonumber(key)
                if slotNum and slotNum >= 1 and slotNum <= Config.MaxJobs then
                    jobs[slotNum] = {
                        job = value.job or Config.DefaultJob.name,
                        grade = value.grade or Config.DefaultJob.grade
                    }
                end
            end
            activeSlot = result.active_slot or 1
        end
    end

    if not next(jobs) then
        local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
        if xPlayer then
            local currentJob = xPlayer.job.name
            local currentGrade = xPlayer.job.grade
            if currentJob == Config.DefaultJob.name then
                jobs[1] = { job = Config.DefaultJob.name, grade = Config.DefaultJob.grade }
            else
                jobs[1] = { job = currentJob, grade = currentGrade }
                activeSlot = 1
            end
        else
            jobs[1] = { job = Config.DefaultJob.name, grade = Config.DefaultJob.grade }
        end
    end

    if not jobs[1] then
        jobs[1] = {
            job = Config.DefaultJob.name,
            grade = Config.DefaultJob.grade
        }
        activeSlot = 1
    end

    if Config.Debug then
        print(string.format('^2[Multijob]^0 Loaded jobs for %s: active slot = %d',
            identifier, 
            activeSlot
        ))
        for slot, data in pairs(jobs) do
            print(string.format('  Slot %d: %s (grade %d)', 
                slot, 
                data.job, 
                data.grade
            ))
        end
    end

    return {
        slots = jobs,
        activeSlot = activeSlot
    }
end

local function SavePlayerJobs(identifier, jobdata)
    local maxwait = 100
    local waited = 0
    while timeout[identifier] and waited < maxwait do
        Wait(100)
        waited = waited + 1
    end

    if timeout[identifier] then
        if Config.Debug then
            print(('^1[Multijob]^0 Save timeout for %s, forcing save'):format(identifier))
        end
    end

    timeout[identifier] = true

    local savedslots = {}
    local slotcount = 0
    for slot, data in pairs(jobdata.slots) do
        if slot >= 1 and slot <= Config.MaxJobs then
            savedslots[tostring(slot)] = {
                job = data.job,
                grade = data.grade
            }
            slotcount = slotcount + 1
        end
    end

    local slotsjson = json.encode(savedslots)
    MySQL.query.await([[
        INSERT INTO multijob_data (identifier, slots_data, active_slot)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
        slots_data = VALUES(slots_data),
        active_slot = VALUES(active_slot)
    ]], {
        identifier,
        slotsjson,
        jobdata.activeSlot
    })

    timeout[identifier] = false

    if Config.Debug then
        print(('^2[Multijob]^0 Saved %d job slots for %s (single row)'):format(
            slotcount, 
            identifier
        ))
    end
end

local function GetPlayerMultijobData(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end

    local identifier = xPlayer.identifier
    if not playerjobs[identifier] then
        playerjobs[identifier] = LoadPlayerJobs(identifier)
    end
    return playerjobs[identifier]
end

local function SwitchToSlot(source, slot)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return false, Config.Locale.error or 'Error'
    end

    local identifier = xPlayer.identifier

    local oncd, remaining = IsOnCooldown(identifier, 'switchJob')
    if oncd then
        return false, (Config.Locale.cooldown or 'Please wait') .. ' ' .. remaining .. 's'
    end

    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then
        return false, Config.Locale.error or 'Error'
    end

    if not jobdata.slots[slot] then
        return false, Config.Locale.slotNotFound or 'Slot not found'
    end

    if jobdata.activeSlot == slot then
        return false, Config.Locale.alreadyActive or 'Already active'
    end

    local target = jobdata.slots[slot]
    if not DoesJobExist(target.job, target.grade) then
        if Config.Debug then
            print(('^1[Multijob]^0 Job %s grade %d no longer exists in database'):format(
                target.job, 
                target.grade
            ))
        end
        return false, Config.Locale.jobNotFound or 'Job no longer exists'
    end

    switchingslots[identifier] = true
    jobdata.activeSlot = slot
    playerjobs[identifier] = jobdata
    xPlayer.setJob(target.job, target.grade)

    local basicjob = GetOnDutyJobName(target.job)
    local isOnDuty = target.job == basicjob
    UpdateDutyStateBag(source, isOnDuty)

    SavePlayerJobs(identifier, jobdata)
    switchingslots[identifier] = false
    SetCooldown(identifier, 'switchJob')

    local joblabel = ESX.GetJobs()[target.job]?.label or target.job
    if Config.Debug then
        print(('^2[Multijob]^0 Player %s switched to slot %d: %s (grade %d)'):format(
            xPlayer.getName(),
            slot,
            target.job,
            target.grade
        ))
    end

    return true, (Config.Locale.switchedTo or 'Switched to') .. ' ' .. joblabel
end

local function ToggleDuty(source)
    if not Config.DutySystem.enabled then
        return false, Config.Locale.dutyNotAvailable or 'Duty system not available'
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return false, Config.Locale.error or 'Error'
    end

    local identifier = xPlayer.identifier

    local oncd, remaining = IsOnCooldown(identifier, 'toggleDuty')
    if oncd then
        return false, (Config.Locale.cooldown or 'Please wait') .. ' ' .. remaining .. 's'
    end

    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then
        return false, Config.Locale.error or 'Error'
    end

    local activeSlot = jobdata.activeSlot
    local currentjob = jobdata.slots[activeSlot]
    local basicjobname = GetOnDutyJobName(currentjob.job)

    if basicjobname == Config.DefaultJob.name then
        return false, Config.Locale.dutyNotSupported or 'This job does not support duty system'
    end

    if not IsJobDutyEnabled(basicjobname) then
        return false, Config.Locale.dutyNotSupported or 'This job does not support duty system'
    end

    local iscurrentlyOnDuty = currentjob.job == basicjobname
    local newjobname = iscurrentlyOnDuty and GetOffDutyJobName(basicjobname) or basicjobname

    if not DoesJobExist(newjobname, currentjob.grade) then
        if Config.Debug then
            print(('^1[Multijob]^0 Off-duty job "%s" does not exist in database'):format(
                newjobname
            ))
        end
        return false, Config.Locale.dutyJobNotFound or 'Duty job not configured'
    end

    switchingslots[identifier] = true
    jobdata.slots[activeSlot].job = newjobname
    playerjobs[identifier] = jobdata
    xPlayer.setJob(newjobname, currentjob.grade)
    UpdateDutyStateBag(source, not iscurrentlyOnDuty)
    SavePlayerJobs(identifier, jobdata)
    switchingslots[identifier] = false
    SetCooldown(identifier, 'toggleDuty')

    local message = iscurrentlyOnDuty and 
        (Config.Locale.wentOffDuty or 'You went off duty') or 
        (Config.Locale.wentOnDuty or 'You went on duty')

    if Config.Debug then
        print(('^2[Multijob]^0 Player %s toggled duty: %s'):format(
            xPlayer.getName(),
            newjobname
        ))
    end

    return true, message
end

local function RemoveJobFromSlot(source, slot)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return false, Config.Locale.error or 'Error'
    end

    local identifier = xPlayer.identifier

    local oncd, remaining = IsOnCooldown(identifier, 'addRemoveSlot')
    if oncd then
        return false, (Config.Locale.cooldown or 'Please wait') .. ' ' .. remaining .. 's'
    end

    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then
        return false, Config.Locale.error or 'Error'
    end

    if not jobdata.slots[slot] then
        return false, Config.Locale.slotNotFound or 'Slot not found'
    end

    if jobdata.activeSlot == slot then
        return false, Config.Locale.cannotRemoveActive or 'Cannot remove active job. Switch to another job first'
    end

    if jobdata.slots[slot].job == Config.DefaultJob.name then
        return false, Config.Locale.alreadyUnemployed or 'This slot is already unemployed'
    end

    jobdata.slots[slot] = {
        job = Config.DefaultJob.name,
        grade = Config.DefaultJob.grade
    }
    playerjobs[identifier] = jobdata
    SavePlayerJobs(identifier, jobdata)
    SetCooldown(identifier, 'addRemoveSlot')

    if Config.Debug then
        print(('^2[Multijob]^0 Player %s reset slot %d to unemployed'):format(
            xPlayer.getName(),
            slot
        ))
    end

    return true, Config.Locale.jobReset or 'Job reset to unemployed'
end

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = xPlayer.identifier
    playerjobs[identifier] = LoadPlayerJobs(identifier)
    local jobdata = playerjobs[identifier]
    local activeJob = jobdata.slots[jobdata.activeSlot]

    if activeJob then
        if xPlayer.job.name ~= activeJob.job or xPlayer.job.grade ~= activeJob.grade then
            xPlayer.setJob(activeJob.job, activeJob.grade)
        end
        local basicjob = GetOnDutyJobName(activeJob.job)
        local isOnDuty = activeJob.job == basicjob
        UpdateDutyStateBag(playerId, isOnDuty)
    end

    if Config.Debug then
        local count = 0
        for _ in pairs(jobdata.slots) do count = count + 1 end
        print(('^2[Multijob]^0 Loaded %d job slots for %s'):format(
            count, 
            xPlayer.getName()
        ))
    end
end)

AddEventHandler('esx:playerDropped', function(playerId, reason)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return end

    local identifier = xPlayer.identifier
    if playerjobs[identifier] then
        SavePlayerJobs(identifier, playerjobs[identifier])
        playerjobs[identifier] = nil
    end
    timeout[identifier] = nil
    switchingslots[identifier] = nil
    playercd[identifier] = nil

    if Config.Debug then
        print(('^3[Multijob]^0 Cleaned up data for %s'):format(
            xPlayer.getName()
        ))
    end
end)

AddEventHandler('esx:setJob', function(source, job, lastJob)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local identifier = xPlayer.identifier
    if switchingslots[identifier] then
        if Config.Debug then
            print(('^3[Multijob]^0 Ignoring esx:setJob during internal switch for %s'):format(
                xPlayer.getName()
            ))
        end
        return
    end

    if not playerjobs[identifier] then
        playerjobs[identifier] = LoadPlayerJobs(identifier)
    end

    local jobdata = playerjobs[identifier]
    local activeSlot = jobdata.activeSlot

    if Config.Debug then
        print(('^2[Multijob]^0 ESX setJob: Updating ACTIVE slot %d for %s to %s (grade %d)'):format(
            activeSlot,
            xPlayer.getName(),
            job.name,
            job.grade
        ))
    end

    jobdata.slots[activeSlot] = {
        job = job.name,
        grade = job.grade
    }
    playerjobs[identifier] = jobdata
    SavePlayerJobs(identifier, jobdata)

    local basicjob = GetOnDutyJobName(job.name)
    local isOnDuty = job.name == basicjob
    UpdateDutyStateBag(source, isOnDuty)
    TriggerClientEvent('multijob:jobUpdated', source)
end)

lib.callback.register('multijob:getData', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end

    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then return nil end

    local formattedSlots = {}
    local availablejobs = ESX.GetJobs()

    for slot = 1, Config.MaxJobs do
        if jobdata.slots[slot] then
            local data = jobdata.slots[slot]
            local basicjobname = GetOnDutyJobName(data.job)
            local jobinfo = availablejobs[data.job] or availablejobs[basicjobname]

            local grade_label = MySQL.scalar.await([[
                SELECT label 
                FROM job_grades 
                WHERE job_name = ? AND grade = ?
            ]], {basicjobname, data.grade}) 

            if not grade_label then
                local gradeinfo = jobinfo and jobinfo.grades and jobinfo.grades[tostring(data.grade)]
                grade_label = gradeinfo and (gradeinfo.label or gradeinfo.name or gradeinfo.grade_label) or ('Grade ' .. tostring(data.grade))
            end

            local grade_salary = MySQL.scalar.await([[
                SELECT salary 
                FROM job_grades 
                WHERE job_name = ? AND grade = ?
            ]], {basicjobname, data.grade}) or 0

            formattedSlots[#formattedSlots + 1] = {
                slot       = slot,
                job        = data.job,
                grade      = data.grade,
                label      = jobinfo and jobinfo.label or data.job,
                gradeLabel = grade_label,
                salary     = grade_salary,
                isactive   = slot == jobdata.activeSlot,
                isDutyJob  = IsJobDutyEnabled(basicjobname),
                isOnDuty   = data.job == basicjobname
            }
        end
    end

    if Config.Debug then
        print(string.format('^2[Multijob]^0 Sending %d slots to client (active: %d)', 
            #formattedSlots, 
            jobdata.activeSlot
        ))
    end

    return {
        slots       = formattedSlots,
        activeSlot  = jobdata.activeSlot,
        maxSlots    = Config.MaxJobs,
        locale      = Config.Locale,
        dutyEnabled = Config.DutySystem.enabled
    }
end)

lib.callback.register('multijob:switchSlot', function(source, slot)
    if type(slot) ~= 'number' or slot < 1 or slot > Config.MaxJobs or slot % 1 ~= 0 then
        if Config.Debug then
            print(('^1[Multijob]^0 Invalid slot from player %d: %s'):format(source, tostring(slot)))
        end
        return {
            success = false, 
            message = Config.Locale.invalidSlot or 'Invalid slot'
        }
    end

    local success, message = SwitchToSlot(source, slot)
    return {
        success = success, 
        message = message
    }
end)

lib.callback.register('multijob:toggleDuty', function(source)
    local success, message = ToggleDuty(source)
    return {
        success = success, 
        message = message
    }
end)

lib.callback.register('multijob:removeSlot', function(source, slot)
    if type(slot) ~= 'number' or slot < 1 or slot > Config.MaxJobs or slot % 1 ~= 0 then
        if Config.Debug then
            print(('^1[Multijob]^0 Invalid slot from player %d: %s'):format(source, tostring(slot)))
        end
        return {
            success = false, 
            message = Config.Locale.invalidSlot or 'Invalid slot'
        }
    end

    local success, message = RemoveJobFromSlot(source, slot)
    return {
        success = success, 
        message = message
    }
end)

lib.callback.register('multijob:addSlot', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return {
            success = false, 
            message = Config.Locale.error or 'Error'
        }
    end

    local identifier = xPlayer.identifier

    local oncd, remaining = IsOnCooldown(identifier, 'addRemoveSlot')
    if oncd then
        return {
            success = false, 
            message = (Config.Locale.cooldown or 'Please wait') .. ' ' .. remaining .. 's'
        }
    end

    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then
        return {
            success = false, 
            message = Config.Locale.error or 'Error'
        }
    end

    local slotcount = 0
    for _ in pairs(jobdata.slots) do
        slotcount = slotcount + 1
    end

    if slotcount >= Config.MaxJobs then
        return {
            success = false, 
            message = Config.Locale.maxSlotsReached or 'Maximum job slots reached'
        }
    end

    local newSlotNum = nil
    for i = 1, Config.MaxJobs do
        if not jobdata.slots[i] then
            newSlotNum = i
            break
        end
    end

    if not newSlotNum then
        return {
            success = false, 
            message = Config.Locale.noAvailableSlots or 'No available slots'
        }
    end

    jobdata.slots[newSlotNum] = {
        job = Config.DefaultJob.name,
        grade = Config.DefaultJob.grade
    }
    playerjobs[identifier] = jobdata
    SavePlayerJobs(identifier, jobdata)
    SetCooldown(identifier, 'addRemoveSlot')

    if Config.Debug then
        print(('^2[Multijob]^0 Player %s added new slot %d'):format(
            xPlayer.getName(),
            newSlotNum
        ))
    end

    return {
        success = true, 
        message = Config.Locale.slotAdded or 'New job slot added'
    }
end)

exports('isPlayerOnDuty', function(source)
    if Config.DutySystem.useStateBags then
        local playerState = Player(source).state
        return playerState.onDuty or false
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end

    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then return false end

    local activeJob = jobdata.slots[jobdata.activeSlot]
    if not activeJob then return false end

    local basicjob = GetOnDutyJobName(activeJob.job)
    return activeJob.job == basicjob
end)

exports('getPlayerJobs', function(source)
    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then return {} end
    return jobdata.slots
end)

exports('getActiveSlot', function(source)
    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then return nil end
    return jobdata.activeSlot
end)

exports('hasJob', function(source, jobname)
    local jobdata = GetPlayerMultijobData(source)
    if not jobdata then return false end

    for _, data in pairs(jobdata.slots) do
        local basicjob = GetOnDutyJobName(data.job)
        if basicjob == jobname then
            return true
        end
    end
    return false
end)

if Config.AutoSaveInterval > 0 then
    CreateThread(function()
        while true do
            Wait(Config.AutoSaveInterval)
            local saveCount = 0
            for identifier, jobdata in pairs(playerjobs) do
                if not timeout[identifier] then
                    SavePlayerJobs(identifier, jobdata)
                    saveCount = saveCount + 1
                end
            end
            if Config.Debug and saveCount > 0 then
                print(('^2[Multijob]^0 Auto-saved data for %d players'):format(saveCount))
            end
        end
    end)
end

if Config.Debug then
    print('^2[Multijob]^0 Server initialized successfully!')
end
