-- keyboard window move and resize
--
-- TODO:
--  * set and move cusror
--

local math = require "math"
local keygrabber = require("awful.keygrabber")

local capi = {
    mouse = mouse,
    screen = screen,
    client = client
}
local DELTA = 64

local function clamp(value, minValue, maxValue)
    return math.min(math.max(value, minValue), maxValue)
end

local movements = {}

local function update_geometry(client, geom)
    local workarea = capi.screen[client.screen].workarea
    geom.x = clamp(
        geom.x, workarea.x, workarea.x + workarea.width - geom.width)
    geom.y = clamp(
        geom.y, workarea.y, workarea.y + workarea.height - geom.height)
    client:geometry(geom)
end

function reversed_ipairs(t)
    local function ripairs_it(t, i)
        i = i - 1
        local v = t[i]
        if v ~= nil then
            return i,v
        else
            return nil
        end
    end
    return ripairs_it, t, #t + 1
end


local function find_closest_edge(edges, x0, x1)
    if x0 == x1 then return x0 end

    -- TODO: use bin search instead
    if x0 < x1 then
        for _, x in ipairs(edges) do
            if x > x0 and x < x1 then
                return x
            end
        end
    else
        for _, x in reversed_ipairs(edges) do
            if x < x0 and x > x1 then
                return x
            end
        end
    end
    return x1
end

local function get_edges(client)
    local left, right, top, bottom = {}, {}, {}, {}
    local screen = client.screen

    local function insert_edge(c)
        table.insert(left, c.x)
        table.insert(left, c.x + c.width + 1)
        table.insert(right, c.x + c.width)
        table.insert(right, c.x - 1)
        table.insert(top, c.y)
        table.insert(top, c.y + c.height + 1)
        table.insert(bottom, c.y + c.height)
        table.insert(bottom, c.y - 1)
    end

    for _, c in ipairs(screen.clients) do
        if c ~= client then
            insert_edge(c)
        end
    end
    insert_edge(capi.screen[screen].workarea)

    table.sort(left)
    table.sort(right)
    table.sort(top)
    table.sort(bottom)
    return left, right, top, bottom
end

local function min_or_max(sign, a, b)
    if sign > 0 then
        return math.min(a, b)
    else
        return math.max(a, b)
    end
end

local function move(client, dx, dy)
    local left, right, top, bottom = get_edges(client)

    local xedge0 = find_closest_edge(
        left, client.x, client.x + dx)
    local yedge0 = find_closest_edge(
        top, client.y, client.y + dy)

    local xedge1 = find_closest_edge(
        right, client.x + client.width,
        client.x + client.width + dx) - client.width
    local yedge1 = find_closest_edge(
        bottom, client.y + client.height,
        client.y + client.height + dy) - client.height

    local geom = {
        x = min_or_max(dx, xedge0, xedge1),
        y = min_or_max(dy, yedge0, yedge1),
        width = client.width,
        height = client.height
    }

    client:geometry(geom)
end

local function resize(client, dx, dy)
    local _, right, _, bottom = get_edges(client)

    local xedge = find_closest_edge(
        right, client.x + client.width, client.x + client.width + dx)
    local yedge = find_closest_edge(
        bottom, client.y + client.height, client.y + client.height + dy)

    local geom = {
        x = client.x,
        y = client.y,
        width = math.max(xedge - client.x, 1),
        height = math.max(yedge - client.y, 1)
    }
    update_geometry(client, geom)
end

local function start_action(client, func)
    local grabber
    grabber = function (mod, key, event)
        if event == "release" then
            return
        end

        local delta = 1
        for _, v in ipairs(mod) do
            if v == "Shift" then
                delta = DELTA
            end
        end

        if key == "Shift_L" or key == "Shift_R" then
            return
        elseif key == "Up" then
            func(client, 0, -delta)
        elseif key == "Down"  then
            func(client, 0, delta)
        elseif key == "Right" then
            func(client, delta, 0)
        elseif key == "Left"  then
            func(client, -delta, 0)
        elseif key == "Return" or key == "Escape" then
            keygrabber.stop(grabber)
        end
    end

    keygrabber.run(grabber)
end


function movements.start_move(client)
    start_action(client, move)
end

function movements.start_resize(client)
    start_action(client, resize)
end

return movements
