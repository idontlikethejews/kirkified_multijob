# kirkified_multijob

## Fully secured and optimized multijob system for FiveM

A modern multi-job management system for ESX-based FiveM servers. Built with military-grade security and peak performance optimization.

![multijob](https://i.ibb.co/93YrQ4rD/image.png)

## 🛠️ Technology Stack (teknologia)

- **Backend**: Lua (server-side & client-side)
- **Frontend**: React with Tailwind CSS
- **Icons**: Iconify
- **Framework**: ESX Legacy
- **UI Library**: ox_lib

## ✨ Features

## 🔒 Why This Is The Safest Multijob Script

### Exploit Prevention
- **No Direct Event Exposure**: Uses `lib.callback` instead of `RegisterNetEvent` - completely eliminates the classic exploit where cheaters trigger e.g. `TriggerServerEvent("multijob:setjob", "police", 14)` to give themselves any job
- **Server-Side Only Logic**: All job changes, validations, and database operations happen server-side - clients can't manipulate anything
- **Strict Input Validation**: Every parameter is type-checked, range-validated, and sanitized before processing
- **Integer Verification**: Prevents decimal/float slot exploits with `slot % 1 ~= 0` checks
- **Job Existence Validation**: Verifies jobs and grades exist in database before allowing any changes

### Anti-Spam Protection
- **Cooldown System**: Configurable rate limiting prevents database flooding and DDoS attempts
  - Job switching: 5 seconds (default)
  - Duty toggle: 3 seconds (default)
  - Add/Remove slots: 10 seconds (default)
- **Per-Player Tracking**: Each player has independent cooldown timers per action type
- **Real-Time Feedback**: Shows remaining cooldown time to users
- **Automatic Cleanup**: Cooldowns are cleared when players disconnect

### Database Security
- **Parameterized Queries**: 100% SQL injection proof with prepared statements
- **Save Locks**: Prevents race conditions and concurrent write conflicts
- **Single-Row Storage**: Optimized schema stores all player slots in one row (efficient & organized)
- **Query Caching**: Job existence checks are cached to reduce database load

### Authorization & Access Control
- **Whitelist System**: Restrict specific jobs to authorized identifiers only
- **Blacklist System**: Prevent certain jobs from being added to multijob slots
- **Active Job Protection**: Cannot remove or modify currently active job
- **Player Verification**: Every action validates player existence and permissions

## 🚀 Performance Optimizations

- **Async Operations**: Non-blocking database calls with `.await` syntax
- **Smart Caching**: Job existence queries cached to minimize database hits
- **Memory Management**: Automatic cleanup of disconnected player data
- **Efficient Storage**: JSON-based slot storage in single database row
- **State Bags**: Optional duty status broadcasting for cross-script compatibility
- **Minimal Overhead**: Lightweight code with no unnecessary computations

## ✨ Features

### Multi-Job Management
- Support for unlimited jobs per player (configurable)
- Switch between jobs instantly with cooldown protection
- Each job preserves its rank/grade independently
- Active job synchronization with ESX core

### Duty System
- Toggle on/off duty for supported jobs (police, ambulance, mechanic)
- Automatic job name transformation (e.g., `police` ↔ `offpolice`)
- State bag integration for cross-script duty detection
- Configurable duty-enabled jobs list

### User Interface
- Clean, intuitive job management menu
- Real-time job information (label, grade, salary)
- Visual indicators for active job and duty status
- Add/remove job slots dynamically
- Responsive design with ox_lib integration

### Database Features
- Automatic migration from old `multijob_slots` table to optimized `multijob_data` schema
- Auto-save system with configurable intervals (default: 5 minutes)
- Save on disconnect to prevent data loss
- Indexed queries for fast lookups

### Developer-Friendly Exports

```lua
-- Check if player is on duty
local isOnDuty = exports['kirkified_multijob']:isPlayerOnDuty(source)

-- Get all player's jobs
local jobs = exports['kirkified_multijob']:getPlayerJobs(source)
-- Returns: { [1] = {job = "police", grade = 2}, [2] = {job = "mechanic", grade = 1} }

-- Get player's active slot number
local activeSlot = exports['kirkified_multijob']:getActiveSlot(source)
-- Returns: 1, 2, or 3

-- Check if player has specific job (any slot)
local hasJob = exports['kirkified_multijob']:hasJob(source, "police")
-- Returns: true or false

-- Client-side: Check local player duty status
local myDuty = exports['kirkified_multijob']:isOnDuty()

-- Client-side: Open menu programmatically
exports['kirkified_multijob']:openMenu()

-- Client-side: Close menu programmatically
exports['kirkified_multijob']:closeMenu()
```

## 📦 Dependencies

- [es_extended](https://github.com/esx-framework/esx_legacy)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)

## 📥 Installation

1. Download and extract the script to your resources folder
2. Ensure dependencies are installed and started before this resource
3. Add `ensure kirkified_jobcenter` to your server.cfg
4. The database table will be created automatically on first start
5. Configure `config.lua` to your preferences
6. Restart your server

### Localization
- Multi-language support (English & Polish included)
- Easy to add custom languages via JSON files
- Locale files for all notifications

## 🔧 Usage Examples

### For Players
1. Use `/multijob` command to open the job management menu
2. View all your job slots with salary and grade information
3. Click "Switch" to change your active job (5s cooldown)
4. Click "Toggle Duty" for jobs that support duty system (3s cooldown)
5. Add new job slots (up to maximum configured)
6. Remove jobs from inactive slots

### For Developers

**Check if police officer is on duty before allowing actions:**
```lua
RegisterCommand('arrest', function(source)
    local isOnDuty = exports['kirkified_multijob']:isPlayerOnDuty(source)
    if not isOnDuty then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = 'You must be on duty to arrest'
        })
        return
    end
    -- Continue with arrest logic
end)
```

**Check if player has mechanic job in any slot:**
```lua
local hasMechanicJob = exports['kirkified_multijob']:hasJob(source, 'mechanic')
if hasMechanicJob then
    -- Allow vehicle repair
end
```

**Get all jobs for custom UI:**
```lua
local playerJobs = exports['kirkified_multijob']:getPlayerJobs(source)
for slot, jobData in pairs(playerJobs) do
    print(string.format("Slot %d: %s (Grade %d)", slot, jobData.job, jobData.grade))
end
```

## 📝 License

This script is provided as-is. Feel free to modify for your server needs.

## 🤝 Support

For issues, suggestions, or contributions, please open an issue on GitHub.

---

**Made with ❤️ for the FiveM community**
