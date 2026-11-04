-- UI/Layout.lua
-- PURE: no WoW globals. Fits table columns into the available width.
-- Columns stretch to fill wide windows and shrink (down to MIN_SHARE of their
-- natural width) on narrow ones; if even that does not fit, the right-most
-- columns are dropped first (the first column, the name, is never dropped).

local _, ns = ...

local Layout = {}
ns.Layout = Layout

Layout.MIN_SHARE = 0.7
Layout.MAX_STRETCH = 1.6

-- columns: list of { width = natural width }; gap: pixels between columns.
-- Returns widths (index -> width, or nil when the column is hidden).
function Layout.FitColumns(columns, available, gap)
    gap = gap or 4
    local n = #columns
    local visible = n
    local function minTotal(k)
        local t = 0
        for i = 1, k do t = t + columns[i].width * Layout.MIN_SHARE end
        return t + gap * (k - 1)
    end
    while visible > 1 and minTotal(visible) > available do visible = visible - 1 end
    local natural = 0
    for i = 1, visible do natural = natural + columns[i].width end
    local room = available - gap * (visible - 1)
    local factor = room / natural
    if factor < Layout.MIN_SHARE then factor = Layout.MIN_SHARE end
    if factor > Layout.MAX_STRETCH then factor = Layout.MAX_STRETCH end
    local widths = {}
    for i = 1, visible do widths[i] = math.floor(columns[i].width * factor) end
    return widths, visible
end
