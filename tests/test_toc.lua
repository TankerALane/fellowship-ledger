-- The two flavor TOCs must stay in step, and every file they list must exist.
local H = ...

local function parseToc(rel)
    local fields, files = {}, {}
    for line in (H.readFile(rel) .. "\n"):gmatch("(.-)\r?\n") do
        local k, v = line:match("^## ([%w%-_]+):%s*(.-)%s*$")
        if k then
            fields[k] = v
        elseif line ~= "" and not line:find("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return fields, files
end

local FOREVER = "FellowshipLedger/FellowshipLedger_Forever.toc"
local MAINLINE = "FellowshipLedger/FellowshipLedger_Mainline.toc"
local GENERIC = "FellowshipLedger/FellowshipLedger.toc"

H.test("interface numbers and flavor tags", function()
    local f = parseToc(FOREVER)
    local m = parseToc(MAINLINE)
    H.eq(f.Interface, "16001")
    H.eq(m.Interface, "120105")
    H.eq(f["X-Flavor"], "Forever")
    H.eq(m["X-Flavor"], "Retail")
end)

H.test("flavor TOCs share every other field and the file list", function()
    local f, ff = parseToc(FOREVER)
    local m, mf = parseToc(MAINLINE)
    for _, k in ipairs({ "Title", "Notes", "Author", "Version", "IconTexture", "SavedVariables", "OptionalDeps", "X-License" }) do
        H.eq(f[k], m[k], k)
    end
    H.eq(table.concat(ff, "|"), table.concat(mf, "|"), "file lists differ")
    H.eq(f.Author, "Decoupled Lane Studio")
    H.eq(f.SavedVariables, "FellowshipLedgerDB, FellowshipLedgerBackupDB")
    H.eq(f.OptionalDeps, "Questie")
end)

H.test("every listed file exists", function()
    for _, toc in ipairs({ FOREVER, MAINLINE, GENERIC }) do
        local _, files = parseToc(toc)
        for _, rel in ipairs(files) do
            H.ok(H.fileExists("FellowshipLedger/" .. rel), toc .. " lists missing file " .. rel)
        end
    end
end)

H.test("pure files load in the same order as the TOC", function()
    local _, files = parseToc(FOREVER)
    local index = {}
    for i, rel in ipairs(files) do index[rel] = i end
    local last = 0
    for _, rel in ipairs(H.PURE_FILES) do
        H.ok(index[rel], rel .. " is not in the TOC")
        H.ok(index[rel] > last, rel .. " is out of order")
        last = index[rel]
    end
end)

H.test("icon file exists for IconTexture", function()
    local f = parseToc(FOREVER)
    local rel = f.IconTexture:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/")
    H.ok(H.fileExists(rel .. ".tga"), "missing " .. rel .. ".tga")
end)

H.test("versions agree between TOCs and Namespace", function()
    local f = parseToc(FOREVER)
    local g = parseToc(GENERIC)
    H.eq(g.Version, f.Version)
    H.eq(H.pureNamespace().VERSION, f.Version)
end)
