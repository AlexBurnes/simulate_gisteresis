-- LÖVE2D Mobile Terminal Registration Simulation
-- https://love2d.org/wiki/Main_Page

love.window.setMode(1200, 900, {resizable=true})

local NUM_TERMINALS = 1000
local OPERATOR_THRESHOLDS = {0.5, 0.3, 0.2} -- 50%, 30%, 20%
local OPERATOR_COLORS = {
    {0.2, 0.8, 0.2}, -- green
    {0.2, 0.2, 0.8}, -- blue
    {0.8, 0.8, 0.2}, -- yellow
}
local BAR_WIDTH = 120
local BAR_GAP = 60
local BAR_HEIGHT = 400
local REREGISTER_PERIOD = 10 -- seconds
local REGISTRATION_ATTEMPTS = 3
local TERMINAL_START_INTERVAL = 0.01 -- seconds

local operators = {}
local terminals = {}
local time_since_last_terminal = 0
local next_terminal_index = 1
local simulation_time = 0

-- Add a table to track recent reregistration events for visualization
local rereg_flash = {0, 0, 0} -- one per operator
local FLASH_DURATION = 0.3 -- seconds

-- Metrics for failed registration attempts
local min_failed_attempts = math.huge
local max_failed_attempts = 0
local total_failed_attempts = 0
local total_registrations = 0

-- Per-operator metrics
local op_failed_min = {math.huge, math.huge, math.huge}
local op_failed_max = {0, 0, 0}
local op_failed_total = {0, 0, 0}
local op_registrations = {0, 0, 0}

-- Histogram of failed attempts (successful registrations)
local failed_histogram = {}

-- Time series log (avg failed attempts every 10s)
local time_series = {}
local last_time_series = 0
local TIME_SERIES_INTERVAL = 10

local simulation_paused = false

function love.load()
    for i = 1, 3 do
        operators[i] = {
            registered = 0,
            threshold = math.floor(OPERATOR_THRESHOLDS[i] * NUM_TERMINALS),
        }
    end
end

local function operator_register(terminal, op_index)
    local op = operators[op_index]
    if op.registered < op.threshold then
        if terminal.registered_operator then
            operators[terminal.registered_operator].registered = operators[terminal.registered_operator].registered - 1
        end
        op.registered = op.registered + 1
        terminal.registered_operator = op_index
        terminal.last_reregister = simulation_time
        return true
    end
    return false
end

local function can_register_in_operator(op_index)
    -- Calculate current distribution rate for the operator
    local total_registered = 0
    for i = 1, #operators do
        total_registered = total_registered + operators[i].registered
    end
    local current_percent = 0
    if total_registered > 0 then
        current_percent = (operators[op_index].registered / total_registered) * 100
    end
    local threshold_percent = OPERATOR_THRESHOLDS[op_index] * 100
    return current_percent <= threshold_percent
end

local function pick_random_operator(exclude)
    local choices = {}
    for i = 1, #operators do
        if not exclude or not exclude[i] then
            table.insert(choices, i)
        end
    end
    if #choices == 0 then return nil end
    return choices[love.math.random(1, #choices)]
end

function love.keypressed(key)
    if key == "space" then
        simulation_paused = not simulation_paused
    end
end

function love.update(dt)
    if simulation_paused then return end
    simulation_time = simulation_time + dt
    -- Time series logging
    if simulation_time - last_time_series >= TIME_SERIES_INTERVAL then
        local avg_failed = total_registrations > 0 and (total_failed_attempts / total_registrations) or 0
        table.insert(time_series, {time = simulation_time, avg = avg_failed})
        last_time_series = simulation_time
    end
    -- Start new terminals at 1 per second
    if next_terminal_index <= NUM_TERMINALS then
        time_since_last_terminal = time_since_last_terminal + dt
        if time_since_last_terminal >= TERMINAL_START_INTERVAL then
            local terminal = {
                id = next_terminal_index,
                registered_operator = nil,
                last_reregister = simulation_time,
                state = "unregistered",
                next_event_time = simulation_time + love.math.random(1, 10),
                current_operator = nil,
                current_attempts = 0,
                tried_operators = {},
                failed_attempts = 0,
            }
            terminals[next_terminal_index] = terminal
            next_terminal_index = next_terminal_index + 1
            time_since_last_terminal = time_since_last_terminal - TERMINAL_START_INTERVAL
        end
    end
    -- Handle terminal state transitions
    for _, terminal in ipairs(terminals) do
        if simulation_time >= (terminal.next_event_time or 0) then
            if terminal.state == "unregistered" then
                -- Registration logic
                if not terminal.current_operator then
                    terminal.current_operator = pick_random_operator()
                    terminal.current_attempts = 0
                    terminal.tried_operators = {}
                    terminal.tried_operators[terminal.current_operator] = true
                end
                terminal.current_attempts = terminal.current_attempts + 1
                -- Only try to register if operator is under threshold
                if can_register_in_operator(terminal.current_operator) then
                    if operator_register(terminal, terminal.current_operator) then
                        -- Registration succeeded
                        terminal.state = "registered"
                        terminal.next_event_time = simulation_time + love.math.random(1, 10)
                        -- Metrics (on every successful registration)
                        min_failed_attempts = math.min(min_failed_attempts, terminal.failed_attempts)
                        max_failed_attempts = math.max(max_failed_attempts, terminal.failed_attempts)
                        total_failed_attempts = total_failed_attempts + terminal.failed_attempts
                        total_registrations = total_registrations + 1
                        -- Per-operator metrics
                        local op = terminal.current_operator
                        op_failed_min[op] = math.min(op_failed_min[op], terminal.failed_attempts)
                        op_failed_max[op] = math.max(op_failed_max[op], terminal.failed_attempts)
                        op_failed_total[op] = op_failed_total[op] + terminal.failed_attempts
                        op_registrations[op] = op_registrations[op] + 1
                        -- Histogram
                        failed_histogram[terminal.failed_attempts] = (failed_histogram[terminal.failed_attempts] or 0) + 1
                        -- Reset for next cycle
                        terminal.current_operator = nil
                        terminal.current_attempts = 0
                        terminal.tried_operators = {}
                        terminal.failed_attempts = 0
                    else
                        -- Registration failed due to quota
                        terminal.failed_attempts = terminal.failed_attempts + 1
                        if terminal.current_attempts < REGISTRATION_ATTEMPTS then
                            -- Try again with the same operator after interval
                            terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                        else
                            -- Pick a new operator not tried yet
                            local new_op = pick_random_operator(terminal.tried_operators)
                            if new_op then
                                terminal.current_operator = new_op
                                terminal.current_attempts = 0
                                terminal.tried_operators[new_op] = true
                                terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                            else
                                -- All operators tried, reset and try again
                                terminal.current_operator = nil
                                terminal.current_attempts = 0
                                terminal.tried_operators = {}
                                terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                            end
                        end
                    end
                else
                    -- Registration failed due to threshold
                    terminal.failed_attempts = terminal.failed_attempts + 1
                    -- Operator is at/over threshold, pick a new one
                    local new_op = pick_random_operator(terminal.tried_operators)
                    if new_op then
                        terminal.current_operator = new_op
                        terminal.current_attempts = 0
                        terminal.tried_operators[new_op] = true
                        terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                    else
                        -- All operators tried, reset and try again
                        terminal.current_operator = nil
                        terminal.current_attempts = 0
                        terminal.tried_operators = {}
                        terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                    end
                end
            elseif terminal.state == "registered" then
                -- Unregister
                if terminal.registered_operator then
                    operators[terminal.registered_operator].registered = operators[terminal.registered_operator].registered - 1
                    terminal.registered_operator = nil
                end
                terminal.state = "unregistered"
                terminal.next_event_time = simulation_time + love.math.random(1, 10)
            end
        end
    end
end

function love.draw()
    local win_w = love.graphics.getWidth()
    local win_h = love.graphics.getHeight()
    -- Dynamically center operator bars
    local total_bar_width = (#operators) * BAR_WIDTH + (#operators-1) * BAR_GAP
    local START_X = math.floor((win_w - total_bar_width) / 2)
    local START_Y = math.floor(win_h * 0.7)
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Mobile Terminal Registration Simulation", START_X, 30)
    love.graphics.print(string.format("Time: %.1fs", simulation_time), START_X, 60)
    love.graphics.print(string.format("Terminals started: %d / %d", next_terminal_index-1, NUM_TERMINALS), START_X, 90)
    love.graphics.print("[Space] Pause/Resume", START_X, 110)
    -- Show registration metrics
    local avg_failed = total_registrations > 0 and (total_failed_attempts / total_registrations) or 0
    love.graphics.print(string.format("Failed registration attempts: min=%d, max=%d, avg=%.2f", min_failed_attempts < math.huge and min_failed_attempts or 0, max_failed_attempts, avg_failed), START_X, 130)
    -- 1. Ongoing failed attempts (only those actively trying to register)
    local ongoing_failed = 0
    local ongoing_unregistered = 0
    for _, t in ipairs(terminals) do
        if t.state == "unregistered" and (t.current_operator ~= nil) then
            ongoing_failed = ongoing_failed + t.failed_attempts
            ongoing_unregistered = ongoing_unregistered + 1
        end
    end
    love.graphics.print(string.format("Ongoing failed attempts (actively trying): %d", ongoing_failed), START_X, 150)
    love.graphics.print(string.format("Unregistered terminals (actively trying): %d", ongoing_unregistered), START_X, 170)
    -- 2. Per-operator metrics
    local y = 190
    for i = 1, #operators do
        local op_avg = op_registrations[i] > 0 and (op_failed_total[i] / op_registrations[i]) or 0
        love.graphics.print(string.format("Op%d: min=%d, max=%d, avg=%.2f, regs=%d", i, op_failed_min[i] < math.huge and op_failed_min[i] or 0, op_failed_max[i], op_avg, op_registrations[i]), START_X, y)
        y = y + 20
    end
    -- 3. Draw operator bars as before
    for i, op in ipairs(operators) do
        local x = START_X + (i-1)*(BAR_WIDTH+BAR_GAP)
        local ybar = START_Y
        local h = BAR_HEIGHT * OPERATOR_THRESHOLDS[i]
        local total_registered = 0
        for j = 1, #operators do
            total_registered = total_registered + operators[j].registered
        end
        local current_percent = 0
        if total_registered > 0 then
            current_percent = (op.registered / total_registered) * 100
        end
        local threshold_percent = OPERATOR_THRESHOLDS[i] * 100
        if current_percent <= threshold_percent then
            love.graphics.setColor(0.2, 0.8, 0.2)
        else
            love.graphics.setColor(0.9, 0.2, 0.2)
        end
        love.graphics.rectangle("fill", x, ybar-h, BAR_WIDTH, h)
        love.graphics.setColor(OPERATOR_COLORS[i])
        love.graphics.rectangle("line", x, ybar-h, BAR_WIDTH, h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Op%d", i), x+BAR_WIDTH/2-18, ybar+10)
        love.graphics.print(string.format("%d/%d", op.registered, op.threshold), x+BAR_WIDTH/2-30, ybar-h-30)
        love.graphics.print(
            string.format("%d (%.1f%%)", op.registered, current_percent),
            x + BAR_WIDTH/2 - 35, ybar - h - 50
        )
    end
    -- 4. Histogram of failed attempts (draw as bars under operator bars)
    local hist_x = START_X
    local hist_y = START_Y + 60
    local hist_bar_w = 20
    local hist_bar_h = 80
    local max_hist = 0
    for k, v in pairs(failed_histogram) do if v > max_hist then max_hist = v end end
    if max_hist > 0 then
        love.graphics.setColor(0.7, 0.7, 1)
        for i = 0, 20 do
            local count = failed_histogram[i] or 0
            local bar_height = (count / max_hist) * hist_bar_h
            love.graphics.rectangle("fill", hist_x + i * (hist_bar_w + 2), hist_y + hist_bar_h - bar_height, hist_bar_w, bar_height)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(tostring(i), hist_x + i * (hist_bar_w + 2), hist_y + hist_bar_h + 2)
            love.graphics.setColor(0.7, 0.7, 1)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Histogram: failed attempts (bar height = count)", hist_x, hist_y - 18)
    end
    -- 5. Time series log
    local yts = hist_y + hist_bar_h + 40
    love.graphics.print("Time series (t, avg_failed):", START_X, yts)
    yts = yts + 20
    for i = math.max(1, #time_series-10), #time_series do
        local entry = time_series[i]
        if entry then
            love.graphics.print(string.format("%.0f: %.2f", entry.time, entry.avg), START_X, yts)
            yts = yts + 15
        end
    end
end 