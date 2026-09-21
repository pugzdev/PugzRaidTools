---------------------------------------------------------------------------
-- PugzRaidTools - A practical, read-only guide from spreadsheet to raid.
-- Teaching content/example layout belongs here; controls remain in Widgets.
---------------------------------------------------------------------------
local _, PRT = ...
local W = PRT.UI
local NAV_W, WINDOW_H = 190, 740
local BODY_SIZE, CELL_SIZE = 14, 13
local helpWindow
local copyPopup
local NPC_ID_SCRIPT = '/run local g=UnitGUID("target");local t,_,_,_,_,id=strsplit("-",g or "");print((t=="Creature" or t=="Vehicle") and ("NPC ID: "..id) or "Target an NPC first.")'
local NPC_ID_URL = "https://www.wowhead.com/classic/npc=16060/gothik-the-harvester"

local function OpenCopyExample(title, text)
    if not copyPopup then
        copyPopup = W.CreateTextTransferPopup("PRT_HelpCopyPopup", {
            title = "Copy from the guide", width = 680, height = 190,
            boxHeight = 90, frontStrata = "FULLSCREEN_DIALOG",
            instruction = "Press Ctrl+C to copy the selected text. This window does not run commands.",
        })
        PRT.raidGroupsHelpCopyPopup = copyPopup
    end
    copyPopup:Open({ title = title, text = text, highlight = true })
end
PRT.RAID_GROUPS_HELP_NPC_SCRIPT = NPC_ID_SCRIPT

PRT.RAID_GROUPS_HELP_TABS = {
    { key = "import",   label = "1. Plan your roster" },
    { key = "shapes",   label = "2. Copy into PRT" },
    { key = "multiple", label = "3. Several layouts" },
    { key = "names",    label = "4. Check your players" },
    { key = "save",     label = "5. Save your changes" },
    { key = "sorting",  label = "6. Arrange the raid" },
    { key = "autoswap", label = "7. Automatic swaps" },
    { key = "automark", label = "8. Reusable marks" },
}

-- One complete example roster, in group order. All visual variants use these
-- same 40 players; tests feed the displayed cells into the real importers.
local groups = {
    { "Krobian", "Pugzz", "Coltyy", "Sertoh", "Benevolent" },
    { "Udwarrior", "Lilbootay", "Freegoo", "Skalina", "Prestelul" },
    { "Ezi", "Tusqaix", "Salvdali", "Preyqq", "Scrimslave" },
    { "Drstwo", "Wstn", "Panzèrx", "Daiku", "Bokkpriest" },
    { "Straik", "Sniffx", "Ltr", "Zurzur", "Zixes" },
    { "Maasaki", "Elewent", "Sosa", "Clickerxx", "Minicutie" },
    { "Littlechurch", "Shadowelitz", "Driev", "Dunkix", "Jeezppc" },
    { "Fréakazoide", "Mueslii", "Smokess", "Malepalax", "Calimay" },
}
local server = { Udwarrior = "Noggenfogger", Ezi = "Skullflame", Malepalax = "Noggenfogger" }
local function ExampleRoster(withServers)
    local roster = { _prtRealmVersion = 1 }
    for _, group in ipairs(groups) do
        for _, name in ipairs(group) do
            roster[#roster + 1] = withServers and (name .. "-" .. (server[name] or "Firemaw")) or name
        end
    end
    return roster
end

local function ShapeExample(shape, withServers)
    local roster, rows = ExampleRoster(withServers), {}
    if shape == "8col" then
        for slot = 1, 5 do
            local row = {}
            for group = 1, 8 do row[group] = roster[(group - 1) * 5 + slot] end
            rows[#rows + 1] = row
        end
    elseif shape == "2col" then
        for pair = 0, 3 do
            for slot = 1, 5 do rows[#rows + 1] = { roster[pair * 10 + slot], roster[pair * 10 + 5 + slot] } end
        end
    else
        for slot = 1, 40 do rows[#rows + 1] = { roster[slot] } end
    end
    return { rows = rows, columns = #rows[1], roster = roster, shape = shape }
end

local function NamedExample(withServers, multiple)
    local rows, rosters = {}, {}
    local names = multiple and { "Main", "Gothik", "4HM" } or { "Main" }
    for index, name in ipairs(names) do
        local roster = ExampleRoster(withServers)
        -- Illustrative encounter changes, keeping all forty players exactly once.
        if index == 2 then roster[11], roster[14] = roster[14], roster[11] end
        if index == 3 then roster[6], roster[26] = roster[26], roster[6] end
        rosters[#rosters + 1] = { name = name, roster = roster }
        rows[#rows + 1] = { "[" .. name .. "]", "", "", "", "" }
        for group = 1, 8 do
            local row = {}
            for slot = 1, 5 do row[slot] = roster[(group - 1) * 5 + slot] end
            rows[#rows + 1] = row
        end
    end
    return { rows = rows, columns = 5, compositions = rosters, shape = "cooked" }
end

-- Read-only example access also gives tests the actual cells shown to players.
local function CthunExample(marked)
    -- One already-arranged raid, before/after the marking trigger. No player
    -- replacement is implied by applying a composition. Names from the owner.
    local rows = {
        { "Pugzgdkp", "Dreloww", "Genesys", "Panteon", "Shadyw", "Stormqtw", "Cedr", "Smokess" },
        { "Shacarri", "Vamin", "Devalina", "Lolliance", "Kurjam", "Ezcom", "Estel", "Lilpump" },
        { "Fatulolo", "Rekkx", "Pokeadot", "Dzsn", "Superic", "Cidiba", "Jehovazz", "Lawitomage" },
        { "Gwyar", "Ophélia", "Palafriend", "Knorri", "Chloé", "Pelalsol", "Aerith", "Shialabeouf" },
        { "Nolock", "Apolona", "Camillie", "Bootybussy", "Parradox", "Gloves", "Dwarflow", "Hasta" },
    }
    return { rows = rows, columns = 8, icons = marked and { { 1, 6, 7, 8, 2, 5, 4, 3 } } or nil }
end
PRT.RAID_GROUPS_HELP_EXAMPLES = { Shape = ShapeExample, Named = NamedExample, Cthun = CthunExample }

local function ColumnWidths(example, measure)
    local widths = {}
    for column = 1, example.columns do
        local width = 76
        for index, row in ipairs(example.rows) do
            measure:SetText(row[column] or "")
            local icon = example.icons and example.icons[index] and example.icons[index][column]
            width = math.max(width, math.ceil(measure:GetStringWidth()) + 18 + (icon and 22 or 0))
        end
        widths[column] = width
    end
    return widths
end

-- Pool the few kinds of lesson elements. Text is measured at its actual width;
-- examples use separate cells, never one fixed-height multiline FontString.
local function MakeLessonBuilder(page, width)
    local pool = { labels = {}, cells = {}, buttons = {} }
    local measure = W.CreateLabel(page.content, "", CELL_SIZE)
    measure:Hide()
    local used, y = {}, 0
    local b = { pool = pool }
    local function Take(kind, create)
        used[kind] = (used[kind] or 0) + 1
        local item = pool[kind][used[kind]]
        if not item then item = create(); pool[kind][used[kind]] = item end
        item:ClearAllPoints()
        item:Show()
        return item
    end
    function b.Reset()
        for _, items in pairs(pool) do for _, item in ipairs(items) do item:Hide() end end
        used, y = {}, 12
        b.grids = {}
    end
    function b.Text(text, size, color, indent, maxWidth)
        size, color, indent = size or BODY_SIZE, color or PRT.C.WHITE, indent or 0
        local label = Take("labels", function() return W.CreateLabel(page.content, "") end)
        label:SetFont(PRT.FONT, size, "")
        label:SetTextColor(color[1], color[2], color[3])
        label:SetPoint("TOPLEFT", 14 + indent, -y)
        label:SetWidth(math.min(width - indent, maxWidth or 890))
        label:SetHeight(0)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("TOP")
        label:SetWordWrap(true)
        label:SetNonSpaceWrap(false)
        label:SetSpacing(3)
        label:SetText(text)
        local height = math.max(size + 3, math.ceil(label:GetStringHeight()))
        label:SetHeight(height + 2)
        y = y + height + 12
        return label
    end
    function b.Title(text, introduction)
        b.Text(text, 24, PRT.C.TITLE)
        if introduction then b.Text(introduction, 16, { 0.85, 0.89, 0.87 }) end
        y = y + 4
    end
    function b.Heading(text)
        y = y + 10
        b.Text(text, 17, PRT.C.GOLD)
    end
    function b.Step(number, title, instruction)
        b.Text(number .. ".  " .. title, 15, PRT.C.TITLE)
        b.Text(instruction, BODY_SIZE, nil, 23)
    end
    function b.Note(title, text)
        if text then
            b.Text(title .. " — " .. text, BODY_SIZE, PRT.C.GOLD)
        else
            b.Text(title, BODY_SIZE, PRT.C.GOLD)
        end
    end
    function b.Choices(items, selected, callback)
        local x = 14
        for _, item in ipairs(items) do
            local button = Take("buttons", function()
                return W.CreateSelectableButton(page.content, "", { width = 180, height = 30, fontSize = BODY_SIZE })
            end)
            button.label:SetText(item.label)
            button:SetWidth(item.width or 180)
            button:SetPoint("TOPLEFT", x, -y)
            button:SetSelected(item.key == selected)
            local key = item.key
            button:SetScript("OnClick", function() callback(key) end)
            x = x + (item.width or 180) + 8
        end
        y = y + 42
    end
    function b.CopyButton(label, title, text)
        b.Choices({ { key = "copy", label = label, width = 200 } }, nil, function()
            OpenCopyExample(title, text)
        end)
    end
    function b.Sheet(example, caption)
        b.Text(caption, 13, PRT.C.GRAY, 0, width)
        local widths = ColumnWidths(example, measure)
        -- Keep narrow sheets narrow, but use the available width for 8 columns.
        local natural = 0
        for _, value in ipairs(widths) do natural = natural + value end
        local extra = example.columns == 8 and math.max(0, width - 38 - natural) / 8 or 0
        local grid = { example = example, cells = {}, top = y }
        b.grids[#b.grids + 1] = grid
        local function Cell(text, x, row, cellWidth, header, icon)
            local cell = Take("cells", function()
                local frame = CreateFrame("Frame", nil, page.content)
                W.StyleBox(frame, { 0.045, 0.065, 0.055, 1 }, PRT.C.BORDER)
                frame.label = W.CreateLabel(frame, "", CELL_SIZE)
                frame.label:SetPoint("LEFT", 7, 0)
                frame.label:SetJustifyH("LEFT")
                frame.label:SetWordWrap(false)
                frame.icon = frame:CreateTexture(nil, "OVERLAY")
                frame.icon:SetSize(18, 18)
                frame.icon:SetPoint("LEFT", 5, 0)
                return frame
            end)
            cell:SetPoint("TOPLEFT", x, -y - row * 26)
            cell:SetSize(cellWidth, 26)
            cell.icon:SetShown(icon ~= nil)
            if icon then cell.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon) end
            cell.label:ClearAllPoints()
            cell.label:SetPoint("LEFT", icon and 29 or 7, 0)
            cell.label:SetWidth(cellWidth - (icon and 36 or 14))
            cell.label:SetText(text)
            local color = header and PRT.C.TITLE or PRT.C.WHITE
            cell.label:SetTextColor(color[1], color[2], color[3])
            grid.cells[#grid.cells + 1] = cell
        end
        Cell("", 14, 0, 38, true)
        for row = 1, #example.rows do Cell(tostring(row), 14, row, 38, true) end
        local x = 52
        for column = 1, example.columns do
            local cellWidth = widths[column] + extra
            Cell(string.char(64 + column), x, 0, cellWidth, true)
            for row, values in ipairs(example.rows) do
                local icon = example.icons and example.icons[row] and example.icons[row][column]
                Cell(values[column] or "", x, row, cellWidth, (values[1] or ""):sub(1, 1) == "[", icon)
            end
            x = x + cellWidth
        end
        grid.width = x - 14
        y = y + (#example.rows + 1) * 26 + 16
    end
    function b.Finish()
        page:UpdateContentHeight(y + 10)
    end
    return b
end

local chapters = {}
function chapters.import(b)
    b.Title("PRT Helper Guide & Workflow Example", "Learn how Raid Groups works, how it connects to Group Auto Swap and Player Auto Marking, and how these tools can make raid preparation quicker and easier.")
    b.Text("This guide is written to help explain how to use PRT. It provides examples of what an effective workflow might look like so that you can get the best out of the powerful tools the addon provides and how the addon can dramatically simplify raid organization. It starts with preparing and importing your players, then builds towards reusable encounter layouts, automatic group swaps and player marking.")
    b.Text("There are many ways to organise a raid. For this guide, we use the example of a spreadsheet workflow: tools such as Google Sheets make it easy to prepare layouts that can be copied into PRT. There are multiple ways to import rosters into the addon but to begin we'll start with the example of creating a roster shaped with 8 groups of 5 players arranged across 8 columns.")
    b.Heading("Start with a prebuilt roster layout")
    b.Step(1, "Give each group a column", "In your spreadsheet, put Group 1 in the first column, Group 2 in the next, and continue through Group 8. Put five players down each column. The first five players below belong together in Group 1: Krobian, Pugzz, Coltyy, Sertoh and Benevolent.")
    b.Sheet(ShapeExample("8col", false), "Example sheet • A–H are spreadsheet column headings, not part of the roster. Each column is one group; each row is a position within it.")
    b.Step(2, "Use one character name in each cell", "Enter the WoW character who will attend, not a Discord nickname or a list of alts. Spell the name exactly, including accents: Pugz and Púgz are different names. If names are not precisely known, entering a recognizable alias is also okay as the addon provides tools to fix this later. You can also enter Pugzz or Pugzz-Firemaw if server name precision is an important factor for you. Details regarding the server-name options are explained in chapter 4.")
    b.Step(3, "Keep a place for anyone not yet decided", "Type a single - in each unused position. Do not rely on a blank spreadsheet cell to hold that place: copying blank cells can cause later names to move into the wrong columns. For a smaller raid, fill the unused groups with - too.")
    b.Step(4, "For multiple roster imports", "PRT can import several named rosters together. These can be different arrangements of the same raid, not different teams of players. For example, prepare your usual Naxxramas groups and a Sapphiron layout that spreads decursers, or your main AQ40 groups and a C'thun layout.")
    b.Text("Preparing multiple raid composition imports can be extremely useful with as PRT's fast group sort lets you switch instantaneously between those saved arrangements once you are out of combat. This makes preplanned encounter layouts practical even at speedrun pace. You can go further by using configurable triggers to request group swaps and mark the players assigned to each job; later chapters explain how.")
    b.Text("If you are running a very static raid composition, with specific positions in the raid occupying consistent roles week by week, pre-configuring your sheets and PRT can allow you to take things even further offering extremely powerful tools in contexts like speedrunning. With a consistent class and role structure, your sheet can link each encounter position to a position in the main roster. You plan those links once, then fill the source positions with this week's characters. The linked encounter layouts follow automatically; you do not have to work out every group's arrangement again.")
    b.Heading("You do not have to use a spreadsheet")
    b.Text("Spreadsheets are not the only way you can prepare PRT exports. There are many options that you can use for preparing group exports, even something as simple as a text editor. Separate players with spaces or tabs and keep the line breaks shown in the examples. A spreadsheet is simply a convenient way to see the groups while planning.")
    b.Text("Already in a raid? Create a roster with New in Quick Load, then use Set Current Roster to capture the players, their servers, their groups and their exact positions within those groups as they exist in game. It copies the raid into the editor; it does not move anyone. With Auto-Save Changes off, click Save Changes afterwards.")
    b.Text("You can also create a roster with New and type or drag players into its cells. The later chapters on checking names, saving and applying work the same way.")
    b.Note("Ready for the next step", "Once you have one roster laid out, use chapter 2 to copy it into the addon.")
end

function chapters.shapes(b, frame)
    b.Title("Copy your spreadsheet export into PRT", "The import layout tells PRT which cells belong to each group. Choose the option that matches your sheet before pasting.")
    b.Step(1, "Select only the roster cells and copy", "Click and drag across the full rectangle of names and - placeholders in your sheet, then press Ctrl+C. Leave out titles, Group 1 / Group 2 labels, notes and spreadsheet column headings.")
    b.Step(2, "Open Import and choose the matching picture", "In Raid Groups, click Import in the Quick Load area. Select the layout button described below. Check it even if a button is already selected: PRT remembers your last import layout.")
    b.Step(3, "Paste, then name your roster", "Click the paste field and press Ctrl+V. PRT processes the paste automatically. For these three layouts it then asks for a roster name; enter Main (or another unused name) and confirm. Select that roster in Quick Load and compare its groups with your sheet.")
    b.Heading("Find the example that looks like your sheet")
    b.Choices({ { key = "8col", label = "8 group columns" }, { key = "2col", label = "2 group columns" }, { key = "1col", label = "1 player column" } }, frame.exampleShape, function(key)
        frame.exampleShape = key; frame:RenderLesson(true)
    end)
    b.Choices({ { key = false, label = "Without server names" }, { key = true, label = "With server names" } }, frame.exampleServers, function(key)
        frame.exampleServers = key; frame:RenderLesson(true)
    end)
    local shape = frame.exampleShape
    if shape == "8col" then
        b.Text("Choose the import button labelled G1 G2 G3 G4 ... . Your sheet has 8 columns and 5 rows. Column A is Group 1, B is Group 2, through H for Group 8. Keep all eight columns side by side.")
    elseif shape == "2col" then
        b.Text("Choose the button showing G1 G2 above G3 G4, G5 G6 and G7 G8. Your sheet has 2 columns and 20 rows: rows 1–5 hold Groups 1 and 2, rows 6–10 hold Groups 3 and 4, rows 11–15 hold Groups 5 and 6, and rows 16–20 hold Groups 7 and 8.")
    else
        b.Text("Choose the button showing G1, G2, G3, G4 ... downwards. Your sheet has 1 column and 40 rows: the first five names are Group 1, the next five are Group 2, and so on. Each player needs a separate row, not one long line of names.")
    end
    local ranges = { ["8col"] = "A1:H5", ["2col"] = "A1:B20", ["1col"] = "A1:A40" }
    b.Sheet(ShapeExample(shape, frame.exampleServers), "Select " .. ranges[shape] .. " in a sheet laid out like this. Copy every shown player cell; do not copy the letter or row-number headings.")
    b.Note("The same layout works with or without servers", "Adding -Firemaw does not change the import shape. Keep a single - for an empty position. Spaces or tabs separate players in multi-column text; commas and semicolons are not substitutes.")
    b.Heading("Should your sheet include server names?")
    b.Text("Servers help PRT identify the right character when it asks the game to move or mark players. You do not have to provide them in an import. If your sheet says Pugz, PRT can learn the server from an exactly matching character name as the raid fills. With Auto-Accept Unspecified Servers checked, a single available match can be accepted automatically; otherwise you confirm it using the cell's warning triangle.")
    b.Text("On server clusters with multiple connected servers, it is possible for multiple characters with an identical names but different servers to be in the same raid. E.g. Pugz-Firemaw and Pugz-Bloodfang can both be in the raid. If more than one matching character is available, PRT needs you to choose; Auto-Accept does not choose arbitrarily between them. Provide full names in your sheet when you know same-named players will attend or want to avoid accepting a same-named character from the wrong server.")
    b.Text("Importing Pugz-Firemaw tells PRT to expect that exact name and server. Importing Pugz is more convenient when you do not yet know the server, but it needs that extra matching step. Neither option guesses an alt from a different spelling. Chapter 4 shows how to handle these cases as players join.")
    b.Heading("If the result looks wrong")
    b.Text("If Group 1 contains players from several different groups, check the selected import layout. If names have shifted sideways, check for empty cells instead of - . Import a corrected copy under a new name and compare it before deleting the incorrect roster.")
    b.Text("A planner or Discord bot can supply the text too, but check its layout and names first. For example, [cooked]Pugz/Pugzz/Pugzgdkp is not three player choices to PRT. Replace it with the one character who will attend. PRT cannot choose an alt or remove a guild tag for you.")
    b.Note("Ready for the next step", "Use chapter 3 if you need several encounter layouts. Otherwise, go straight to chapter 4 when players start joining.")
end

function chapters.multiple(b, frame)
    b.Title("Importing Multiple Raid Groups Simulatenously", "PRT becomes extremely powerful when multiple roster shapes are needed and swapping the raid groups quickly is required. E.g. A main raid composition, and additional roster shapes for the same raid group such as Sapphiron Groups / C'thun groups etc. PRT Import lets you copy several named rosters in a single paste, instead of importing and naming each one separately.")
    b.Heading("Plan the structure once; change the players each week")
    b.Text("Start with a source roster whose positions have consistent purposes: the same class mix, tanks, healers and other jobs in the same places. Your Main, Gothik and 4HM layouts are example names for different arrangements of those source positions, not three rosters you need to rebuild by hand every week.")
    b.Text("In your sheet, link each encounter position to the source position that supplies its class or job. For example, a Four Horsemen tank position can always refer to the source roster's second tank. When another character fills that source position next week, the linked encounter position updates too. All the placement decisions are already in the template.")
    b.Text("Fill the source positions with this week's characters, check the generated encounter layouts, then copy the displayed names into PRT. The spreadsheet evaluates the links; PRT imports their resulting names, not spreadsheet formulas. If your class mix or assignment structure changes, review the links instead of assuming the old arrangement still fits.")
    b.Text("Keeping the imported roster names and each position's job stable also lets Group Auto Swap and Smart Assign in Player Auto Marking reuse their existing configuration. This is the connection between the spreadsheet planning here and the automation in chapters 7 and 8. Where strict raid compositions and roles aren't something expected, you can still make use of the multi-raid group import tool. Just take with your planning.")
    b.Heading("First, change the sheet to group rows")
    b.Text("For the PRT Import format, put the roster name of your choice in square brackets on its own row. E.g. [Main]. Under it, place all five Group 1 players from left to right. Put Group 2 on the next row, and continue through Group 8. That is a name row followed by eight rows of five players.")
    b.Note("This is a different layout from chapter 2's eight columns", "Do not just add [Main] above an eight-column roster. PRT Import reads Group 1's five players first, then Group 2's five, and so on. The example below shows the actual arrangement to copy.")
    b.Step(1, "Prepare one complete named block", "Put [Main] in column A, leaving the other cells on that title row empty. Fill the next eight rows with the groups. Use - for every empty player position. Do not add 'Group 1' type labels inside the copied cells.")
    b.Step(2, "Add the other encounter layouts underneath", "E.g. Put a second roster shape name; in this case: [Gothik] directly below Main's eighth group, followed by its eight group rows. Repeat for [4HM] and any other roster configurations you'd like to add. If you are making use of the Group Auto Swapping and Player Auto Marking with Smart Assign features, keeping the roster names consistent from week to week will allow you to only need to configure the automation setup once. The Group Auto Swap and Player Auto Marking features are configured by Raid Group names and will base it's automation from that. Therefore there will be no need to reconfigure Marking or Group Swaps before every single raid. This is where PRT really shines as a powerful tool especially for speedrunning raid groups where roster compositions remain consistent and the required automation remains predictable.")
    b.Step(3, "Copy the blocks and choose PRT Import", "Select the five columns covering all the named blocks you want, including their [Name] rows. Press Ctrl+C. Open Import in Quick Load, select PRT Import, then paste with Ctrl+V. PRT creates the named rosters automatically; each will appear in Quick Load.")
    b.Choices({ { key = false, label = "One named roster" }, { key = true, label = "Main + Gothik + 4HM" } }, frame.multipleExamples, function(key)
        frame.multipleExamples = key; frame:RenderLesson(true)
    end)
    b.Choices({ { key = false, label = "Without server names" }, { key = true, label = "With server names" } }, frame.namedServers, function(key)
        frame.namedServers = key; frame:RenderLesson(true)
    end)
    b.Sheet(NamedExample(frame.namedServers, frame.multipleExamples), frame.multipleExamples
        and "Copy A1:E27 for all three rosters. These example encounter layouts make small player swaps so you can see how separate plans work."
        or "Copy A1:E9 for Main only. The blank cells beside [Main] are part of the title row, not empty player positions.")
    b.Heading("Make as many roster shapes as you want")
    b.Text("PRT can import as many roster compositions as you like simulatenously. Bear in mind that this feature is most useful when you know exact character names and better again when you know exact server names. Importing multiple roster shapes using player 'aliases' rather than character names will of course still require you to confirm the character names inside each raid group within PRT. One suggestion here for your workflow if you do not know all character names in advance would be to initially import just a single roster first. As players join the raid you can confirm exact character names and server names. Then export the roster out of PRT back into a spreadsheet where you have multiple pre-configure roster shapes to read from that export by using cell formulas to link the cells into the correct shapes. This will provide you with the precise character names and servers you need to then re-export multiple rosters into PRT simulatenously while ensuring no raid slots remain unconfirmed.")
    b.Note("For multiple raid group imports I recommend careful pre-planning and if possible, ensuring exact player names and servers in advance for the best results.")
end

function chapters.names(b)
    b.Title("Check the players as they join", "Your sheet is the plan; the in-game raid tells PRT which characters are actually here. Use the editor and its warnings to bring the two together before sorting.")
    b.Heading("How PRT knows which player you mean")
    b.Text("PRT accepts rosters with or without server names. When someone joins, PRT can find their server by matching the character name you supplied to a character in the raid. The spelling must match, including accents: Pugz is not Púgz, and Pugz is not Pugzxd.")
    b.Text("A server name matters because two different characters can have the same name on different servers. Pugzz-Firemaw means Pugzz on Firemaw specifically. If you import that full name, PRT will not silently use Pugzz from another server instead.")
    b.Heading("Example: your sheet only says Pugzz")
    b.Step(1, "Wait for the player to join", "When Pugzz-Firemaw joins, PRT can match the name Pugzz and discover Firemaw. A player who has not joined yet cannot supply that information, so you can leave their place in the roster while you wait.")
    b.Step(2, "Choose how servers are accepted", "With Auto-Accept Unspecified Servers checked, PRT can accept a single available matching player automatically. With it unchecked, hover the cell's triangle to see the player found, then click the triangle to confirm. This setting only helps when you did not already specify a server.")
    b.Step(3, "Choose explicitly if two players share a name", "If both Pugzw-Firemaw and Pugzw-Dragonfang join, an entry for Pugzw alone is not enough to choose between them. Click its warning triangle, choose the intended full name, and confirm. Do this for each planned place that needs one of those players.")
    b.Text("A softer gold warning on a confirmed player is a reminder that another player shares the name; it is not the same as an unconfirmed yellow warning. Hover each triangle to see which player has been confirmed and which place still needs a choice.")
    b.Heading("Example: your sheet says Pugz, but Pugzxd joins")
    b.Step(1, "Recognise the difference", "PRT cannot assume that Pugzxd is the person you meant by Pugz. The Pugz cell will not match, and Pugzxd will appear in the Not in Roster list.")
    b.Step(2, "Replace the planned name with the real player", "Once you know Pugzxd is the right person, drag Pugzxd from Not in Roster onto the Pugz cell. That place now uses the player's actual character and server. The same action is useful when a raider brings a different alt or you invite a substitute.")
    b.Step(3, "Save the correction", "With Auto-Save Changes on, the change is saved automatically. With it off, click Save Changes before applying the roster or using it for automation. This fixes the roster you are editing; it does not update your external sheet or every other saved PRT roster.")
    b.Text("In a linked-sheet workflow, enter the actual attending character in the source position for that class and job. The sheet's linked encounter layouts then pick up that character without changing the preplanned structure. The person or alt may change next week; the source position's purpose stays the same. If you already imported several layouts, correct the affected PRT rosters too, or bring in updated copies before relying on them.")
    b.Heading("Use each warning to decide what to do next")
    b.Text("Missing from raid: a planned player is not currently in the raid. Wait for them, replace them if someone else is taking their place, or continue with the players who are here. A red missing-player heading does not, by itself, mean sorting is blocked.")
    b.Text("Not in Roster: these live raid members are not assigned to this saved plan. Drag a replacement onto the appropriate cell, or leave extra players outside the plan if that is intentional. Sorting can move them while making room for the planned groups.")
    b.Text("The same player in two places: one character cannot occupy two raid positions. Correct or clear the repeated entry. Sorting is blocked while that exact character and server is assigned twice; two different characters on different servers are not the same error.")
    b.Text("A different server was found: hover the warning to compare the player you asked for with the one in the raid. Only accept the offered replacement if you really mean that other character. If not, keep the original name and wait for the right player.")
    b.Note("Keep server names visible while learning", "Hide Server Names only shortens the displayed labels. It does not remove servers from the roster or make two same-named characters interchangeable. Tooltips still help you check who each cell means.")
end

function chapters.save(b)
    b.Title("Save the plan you want PRT to use", "Editing the roster and moving the raid are separate actions. Saving changes the stored plan; applying it asks PRT to arrange the players in-game.")
    b.Heading("Choose your editing style")
    b.Step(1, "Use Auto-Save Changes for continuous editing", "Turn it on if you want corrections to become the saved roster as you finish editing. Typing is saved when you finish the active cell; drag-and-drop changes and accepted player corrections are saved too. Apply Groups finishes the active edit, saves, then applies.")
    b.Step(2, "Or leave it off while trying a different arrangement", "With Auto-Save Changes off, you can edit without immediately changing the saved plan. When satisfied, click Save Changes. Save before switching rosters or reopening the tab, because unsaved edits can be discarded when the saved roster is loaded again.")
    b.Heading("Example: you just replaced Pugz with Pugzxd")
    b.Text("If Auto-Save Changes is off and you click Apply Groups immediately, PRT still uses the last saved roster containing Pugz. The yellow/amber Apply Groups label and the floating roster's yellow name warn you about this difference. They do not stop you applying the older plan deliberately.")
    b.Text("Click Save Changes first to make Pugzxd part of the stored roster. Hover Save Changes to review pending edits. The floating list, Group Auto Swap and Smart Assign also use saved rosters, so saving is just as important when you do not intend to click Apply Groups yourself.")
    b.Heading("Saving does not require everyone to be online")
    b.Text("You can save and prepare encounter rosters before raid night. Missing players or names waiting for server confirmation do not prevent saving. Check those players later as they join.")
    b.Note("A saved roster can still need fixing", "Save Changes may pulse amber/red if an edit assigns the same exact player twice. Saving is allowed, but sorting that roster stays blocked until you fix the duplicate. Read the tooltip to see the player and both positions.")
    b.Heading("Before you leave the editor")
    b.Text("Finish the cell you are typing in. If Auto-Save Changes is off, save your work. Hover Apply Groups or the floating roster name to check for remaining warnings. In the next chapter, choose whether you need groups only or exact positions within those groups.")
end

function chapters.sorting(b)
    b.Title("Arrange the raid from your saved roster", "Start with an ordinary group sort. Use exact positions only when the order inside each group matters to your plan.")
    b.Step(1, "Check the roster and your raid permissions", "Select the intended roster in Quick Load and save any changes. You must be in a raid and have leader or assistant permission to move players. Group moves must wait until you are out of combat.")
    b.Step(2, "Put players into the right groups", "Leave Force Positions off and click Apply Groups. This is the fast group sort: players are placed into their planned groups without requiring the same top-to-bottom order. On the floating list, a normal left-click on a roster requests this sort.")
    b.Step(3, "Request exact positions if you need them", "Turn on Force positions before Apply Groups to also request the saved order within each group. On the floating list, use Shift + left-click instead. This can also be near-instant when few changes are needed, but it can require more moves than a group-only sort. The raid leader remains first within their group.")
    b.Text("The game limits how quickly group changes can be made. You may see some players move, then a pause of several seconds, followed by the remaining changes arriving together. A sort can take around 10 seconds or sometimes longer when it has to wait for the game's limits or roster updates. A pause does not necessarily mean it has stopped: allow the current request to finish and watch for PRT's completion or failure message instead of repeatedly clicking Apply.")
    b.Heading("You can still sort when the raid is incomplete")
    b.Text("Suppose Main lists 40 players but only 35 have joined. PRT can arrange the players it can identify who are already here. Missing players and names still waiting for confirmation are skipped; they do not all need to be resolved before a useful sort is possible.")
    b.Text("Those skipped places are not reserved empty seats. Other raid members can move as PRT makes room, and a partial raid may not reproduce every spreadsheet position. When more players join, check their names, save any corrections, then apply again.")
    b.Heading("Read the button or floating tooltip before clicking")
    b.Text("Yellow/amber means there is something to review: unsaved edits, players still needing confirmation, missing players or extra raid members. The tooltip explains what will be used and which players will be skipped. It may also tell you there is nothing useful to sort yet.")
    b.Text("Red Sort blocked means the roster has a problem that prevents this request, such as the same exact character in two positions. Fix the named problem and save before trying again. A missing player's red text in the comparison list is a separate warning, not automatically a block.")
    b.Note("Your first working cycle", "Import, check the players, save corrections, then apply. The next two chapters explain how PRT's Group Auto Swap and Player Auto Marking features use your saved Raid Groups for powerful automation.")
end

function chapters.autoswap(b)
    b.Title("Let an encounter trigger change the groups", "Group Auto Swap requests a saved raid layout after a configured enemy-death condition. You choose both the event and the layout that should follow it.")
    b.Heading("Example: return to your usual groups after Gothik")
    b.Step(1, "Prepare the layouts you want to use", "For this example, suppose you saved your normal groups as Main and your encounter arrangement as Gothik. These are example names, not required names. Confirm and save your own layouts, then apply them manually once to check the groups before adding automation.")
    b.Step(2, "Create a Group Auto Swap preset", "Open Group Auto Swap. Create or select an Active Preset and choose the intended raid in Active in instance. A preset holds the triggers for that raid; make sure you are editing the one you intend to use.")
    b.Step(3, "Add the event and the layout it should request", "Click + Add Trigger, name the row Return after Gothik, and choose Main as its composition. In this example, use NPC ID 16060 for Gothik the Harvester and Count 1, then tick the row's On checkbox. This requests Main after Gothik dies, not before you fight him.")
    b.Text("For another transition, choose the NPC whose death happens before you want the new layout. Count 1 means the first recorded death of that NPC; Count 8 means the eighth. Leave Repeat off for a once-per-counter-cycle transition. Enable Repeat only if you want it again at each count interval.")
    b.Heading("Two ways to find an NPC ID")
    b.Text("In game: target the NPC, open the script below, press Ctrl+C, close the copy window, and paste it into chat with Ctrl+V. Press Enter to print the NPC ID in chat. It only reads your target; it does not change settings or send a message to the raid. Use an NPC, not a player target.")
    b.CopyButton("Copy NPC ID script", "Read your target's NPC ID", NPC_ID_SCRIPT)
    b.Text("On Wowhead: open the NPC's Classic page and look at its address. The number immediately after npc= is the NPC ID. In this Gothik example, the highlighted number is 16060.")
    b.Text("https://www.wowhead.com/classic/npc=|cFFFFFF0016060|r/gothik-the-harvester", 14, PRT.C.WHITE, 0, 1000)
    b.CopyButton("Copy Wowhead URL", "Gothik on Wowhead", NPC_ID_URL)
    b.Step(4, "Enable it for the run", "Check Enable Auto Swap, the Active Preset and its instance. When the trigger is reached, PRT requests the selected saved roster. Group movement waits until you are out of combat. The GAS button on the floating list is a convenient enable/disable control.")
    b.Heading("Use fast group swaps for automation")
    b.Text("Fast sorting is strongly recommended for automated transitions, particularly during speedruns. Exact-position sorts can require many more group changes, cause extra raid-frame updates or possibly even lag for other players, and leave less time to finish before the next pull.")
    b.Text("Group Auto Swap already always uses the fast group-only sort. There is no Force positions option on its triggers, and the Raid Groups Force positions checkbox does not change this. Use manual exact-position sorting only when within-group order is genuinely needed and you have time before the next fight.")
    b.Text("Auto Swap uses the saved roster, not unsaved editor changes. Missing or unconfirmed players can be skipped while the others are sorted; an exact duplicate still needs fixing.")
    b.Heading("Important: /reload resets the kill counters")
    b.Text("Group Auto Swap starts every preset's kill counts at zero when the addon loads, including after /reload or a new login. It cannot reconstruct kills that happened before that. For example, if a trigger needs 8 kills and you reload after 5, it will now need 8 newly recorded kills, not the remaining 3.")
    b.Text("Do not reload mid-raid assuming counted automation will continue from where it left off. Review any affected triggers and apply the needed layout manually when appropriate. Player Auto Marking also loses its own NPC counts and already-fired tracking on reload; its counters are separate from Auto Swap's.")
    b.Text("For a normal new raid session next week, login or reload has already started fresh counts, so you generally do not need a separate weekly reset. PRT does not watch the weekly raid-lockout reset itself. If the same session continues, use Reset Kill Counters deliberately before a fresh run.")
    b.Text("Other Auto Swap resets are explicit: Reset Kill Counters clears the active preset; Reset on zone out clears it when you leave its specifically selected instance (not Any Raid); Reset on NPC death clears it when that configured death count is reached. Repeat makes a trigger eligible at count intervals; it does not clear the displayed counter.")
    b.Note("Next: marks that follow the plan", "Player Auto Marking can react when a saved layout is applied, whether you requested it manually or Group Auto Swap requested it for you.")
end

function chapters.automark(b)
    b.Title("Set up the jobs once; let the players change", "When using Player Auto Marking, Smart Assign is powerful when a position in your encounter roster always has the same job, even though a different player may fill that position next week. So long as you keep the same Raid Group names, the Player Auto Marking configuration will only need to be set up once.")
    b.Heading("Example: Skull always belongs to Gothik's Group 3, position 1")
    b.Text("In our Gothik example, Preyqq occupies that place. You want Skull on whoever has that job, not permanently on Preyqq. With Smart Assign, the rule looks up the player saved in Gothik's Group 3, position 1 and finds that character in the current raid, even if their live group order is different.")
    b.Step(1, "Make a Player Auto Marking rule", "Open Player Auto Marking, select or create an Active Preset, and check its instance setting. Click + Add Rule and give it a useful name such as Gothik assignments. Set Apply By to Raid Position, check Smart Assign, and select Gothik under Select Raid Group.")
    b.Step(2, "Give the roster position its icon", "Under the marking assignments, click + Add Mark. Choose Skull and position 11. Positions 1–5 are Group 1, 6–10 are Group 2, and 11–15 are Group 3, so 11 means Group 3's first player. Add other icons for the other jobs; use each icon once.")
    b.Step(3, "Choose when those marks should be applied", "In the rule's group-swap triggers, click + Add Trigger and choose Gothik as the composition. This lets applying Gothik request the marks too. You can instead use an NPC-death trigger for a rule that should fire after a particular enemy dies. Check Fire when if the rule has several triggers.")
    b.Step(4, "Enable and test the complete workflow", "Check Enable Auto Marking, the Active Preset and its instance. Save Gothik in Raid Groups, then apply it and verify that Skull goes to the intended character. The floating PAM toggle controls Player Auto Marking. Repeatable allows the rule to run again; Retry unavailable players can help if a player is temporarily unavailable to be marked.")
    b.Heading("Next week: Ezi takes the same job")
    b.Text("If Ezi takes the same job next week, enter Ezi in the corresponding source position in your sheet. A linked Gothik layout places Ezi in Group 3, position 1 automatically. After the new Gothik roster is imported and saved in PRT, the unchanged position-11 Skull assignment now looks up Ezi instead of Preyqq.")
    b.Text("You are reusing the class/role plan, the sheet's encounter-position links and the PRT marking configuration. The player names are the weekly input. This works while the class composition, jobs and destination positions stay consistent; a change to that structure needs a review of the links and assignments.")
    b.Note("Keep the 'meanin'g of the position consistent from week to week", "The rule does not understand a tank, healer or mechanic by itself. You decide which job belongs in each roster position. If you move a job to another position, update the marking assignment too. In a consistent raid comp from week to week, so long as you keep the Raid Group names and raid slot positions consistent in terms of their role within your raid, all that will need to be updated is the player names from week to week.")
    b.Heading("Example: C'thun groups and melee-camp marks")
    b.Text("For C'thun, you might spread melee players so each group has no more than three, then mark a player for each melee camp to stack on. Save that arrangement as C'thun. The same idea can be used for other preplanned encounter assignments, such as Kel'Thuzad.")
    b.Text("Create a Player Auto Marking rule with Apply By: Raid Position, Smart Assign on, and C'thun selected. Give the first saved position in each group an icon: positions 1, 6, 11, 16, 21, 26, 31 and 36. Add C'thun as a Group Swap Trigger and enable Repeatable if you want reapplying the layout to request the marks again.")
    b.Text("Below, the raid is already in its intended encounter groups. This illustrative eight-icon rule adds the camp marks without changing anyone's group. It demonstrates the marking trigger, not a class-by-class encounter strategy.")
    b.Sheet(CthunExample(false), "Before: the current raid already matches the saved C'thun groups; no camp marks have been applied. Columns A-H are Groups 1-8.")
    b.Sheet(CthunExample(true), "After applying C'thun: the same players stay in the same groups; the rule marks each group's first saved player.")
    b.Text("Use a normal left-click on C'thun in the floating list, or select it and click Apply Groups with Force positions off. The matching Player Auto Marking rule can fire even when no group move is necessary. If your C'thun layout does need different groups, the same action requests those changes and the marks together. Smart Assign follows each saved player, not whoever happens to be first in the live group.")
    b.Note("Be close enough to mark the players", "The game may not make distant or otherwise unavailable raid members accessible to automatic marking. Being listed in the raid is not a guarantee that PRT can mark them. Apply your encounter setup while the raid is gathered, enable Retry unavailable players where useful, and check the actual icons before everyone spreads out.")
    b.Text("Retries only help if the player becomes available during the configured retry time. They cannot bypass the game's visibility or marking restrictions, and there is no guaranteed yard range in this guide. If marks are missing, gather closer and request them again with a repeatable rule. A blocked or unusable roster request does not guarantee that the marking trigger will run.")
    b.Heading("Replace weekly rosters without rebuilding your rules")
    b.Step(1, "Prepare the next roster set", "Fill the source positions in your sheet with this week's characters, then check the linked encounter layouts and prepare the complete import. Do this before the raid, while no group swap or marking rule is running. Keeping an Export All copy of the old rosters is an optional precaution, not a required weekly chore.")
    b.Note("If you replace rosters while automation is enabled", "Turn off GAS and PAM and let any requested group change finish first. This avoids a rule acting at the same moment that you replace its saved player layout, especially during a raid.")
    b.Step(2, "Resolve each existing roster name", "When an imported name such as [Gothik] already exists, PRT asks whether to Overwrite or Rename. Choose Overwrite to replace the saved player layout while keeping the exact roster name used by your automation. Choose Rename only when you intend to create a separate roster under a different name. A multi-roster import asks about every collision before it changes anything.")
    b.Note("Cancel is safe", "Cancel Import, the window's close button and Escape all abandon the complete import. Rosters already considered earlier in a multi-roster paste are not partially added or overwritten.")
    b.Step(3, "Check before turning automation back on", "Confirm that all required roster names exist, inspect the group positions, resolve player-name warnings and save corrections. Recheck the selected rosters and positions in your swap and marking rules. Once those checks are complete, re-enable automation and test the intended assignments before the encounter.")
    b.Text("Do not let a Smart Assign rule run while its selected roster is missing. The current addon can fall back to the live raid position in that situation, which is not the saved-plan assignment you intended. Names still awaiting confirmation in an existing selected roster are skipped instead; resolve and save them before relying on their marks.")
    b.Heading("When a simpler marking mode is enough")
    b.Text("Use Apply By: Player Name when the icon should always follow one specific character. Use Raid Position without Smart Assign only when you deliberately mean the current live raid position. Smart Assign is the choice when you mean the player occupying a job in a named saved plan.")
    b.Note("The reusable workflow", "Plan the jobs in your sheet, import the new players into the same named layouts, check and save them, then reuse the existing swap and marking rules. Keep roster names and job positions consistent, and the long configuration work only needs to be done once.")
end

local function EnsureHelpWindow()
    if helpWindow then return helpWindow end
    -- Size for the real full-server eight-column example, not a split diagram.
    local measure = W.CreateLabel(UIParent, "", CELL_SIZE)
    local columns = ColumnWidths(ShapeExample("8col", true), measure)
    measure:Hide()
    local gridWidth = 38
    for _, width in ipairs(columns) do gridWidth = gridWidth + width end
    local windowWidth = math.max(1260, gridWidth + NAV_W + 80)
    local pageWidth, pageHeight = windowWidth - NAV_W - 34, WINDOW_H - 90
    local frame = W.CreatePopupFrame("PugzRaidToolsHelpWindow", windowWidth, WINDOW_H, {
        title = "PugzRaidTools • From your sheet to your raid",
        titleBarHeight = 30, titleFontSize = 20,
        bgColor = { 0.015, 0.02, 0.015, 0.99 }, frontStrata = "FULLSCREEN_DIALOG",
    })
    frame.exampleShape, frame.exampleServers = "8col", false
    frame.multipleExamples, frame.namedServers = true, true
    frame.tabButtons = {}
    local nav = CreateFrame("Frame", nil, frame)
    nav:SetPoint("TOPLEFT", 10, -40)
    nav:SetSize(NAV_W, WINDOW_H - 52)
    W.StyleBox(nav, PRT.C.SIDEBAR_BG, PRT.C.BORDER)
    local navTitle = W.CreateLabel(nav, "YOUR RAID-NIGHT GUIDE", 12, 0.55, 0.6, 0.55)
    navTitle:SetPoint("TOPLEFT", 10, -12)
    for index, info in ipairs(PRT.RAID_GROUPS_HELP_TABS) do
        local button = W.CreateSelectableButton(nav, info.label, {
            width = NAV_W - 12, height = 39, fontSize = BODY_SIZE,
            bgColor = { 0, 0, 0, 0 }, selectedBgColor = PRT.C.MENU_SEL,
            borderColor = PRT.C.SIDEBAR_BG, selectedBorderColor = PRT.C.MENU_SEL,
            justifyH = "LEFT", labelPoint = { "LEFT", 9, 0 },
            selectedTextColor = { 1, 1, 1, 1 },
            selectedFontOutline = "OUTLINE",
        })
        button:SetPoint("TOPLEFT", 6, -34 - (index - 1) * 42)
        local key = info.key
        button:SetScript("OnClick", function() frame:SelectHelpTab(key) end)
        frame.tabButtons[key] = button
    end
    local hint = W.CreateLabel(nav, "Read in order the first time.\nReturn to any chapter later.\n\nExamples here do not change\nyour saved rosters.", 12, 0.6, 0.65, 0.6)
    hint:SetPoint("TOPLEFT", 12, -400)
    hint:SetWidth(NAV_W - 24)
    hint:SetWordWrap(true)
    hint:SetJustifyH("LEFT")
    local page = W.CreateScrollFrame(frame, pageWidth, pageHeight)
    page:SetPoint("TOPLEFT", nav, "TOPRIGHT", 10, 0)
    W.StyleBox(page, PRT.C.CONTENT_BG, PRT.C.BORDER)
    frame.page = page
    local builder = MakeLessonBuilder(page, pageWidth - 42)
    frame.builder = builder
    local previous = W.CreateButton(frame, "Previous chapter", 155, 28)
    previous:SetPoint("BOTTOMLEFT", NAV_W + 20, 10)
    local nextButton = W.CreateButton(frame, "Next chapter", 200, 28)
    nextButton:SetPoint("BOTTOMRIGHT", -12, 10)
    local progress = W.CreateLabel(frame, "", BODY_SIZE, 0.65, 0.7, 0.65)
    progress:SetPoint("BOTTOM", 60, 17)
    frame.previousButton, frame.nextButton = previous, nextButton

    function frame:RenderLesson(keepScroll)
        local offset = keepScroll and page.scroll:GetVerticalScroll() or 0
        builder.Reset()
        chapters[self.activeTab](builder, self)
        page.scroll:SetVerticalScroll(offset)
        builder.Finish() -- Also clamps/synchronizes the shared scrollbar thumb.
    end
    function frame:SelectHelpTab(key)
        if not chapters[key] then key = "import" end
        self.activeTab = key
        for index, info in ipairs(PRT.RAID_GROUPS_HELP_TABS) do
            self.tabButtons[info.key]:SetSelected(info.key == key)
            if info.key == key then self.chapterIndex = index end
        end
        previous:SetShown(self.chapterIndex > 1)
        nextButton:SetShown(self.chapterIndex < #PRT.RAID_GROUPS_HELP_TABS)
        progress:SetText("Chapter " .. self.chapterIndex .. " of " .. #PRT.RAID_GROUPS_HELP_TABS)
        self:RenderLesson(false)
    end
    previous:SetScript("OnClick", function()
        frame:SelectHelpTab(PRT.RAID_GROUPS_HELP_TABS[frame.chapterIndex - 1].key)
    end)
    nextButton:SetScript("OnClick", function()
        frame:SelectHelpTab(PRT.RAID_GROUPS_HELP_TABS[frame.chapterIndex + 1].key)
    end)
    frame:HookScript("OnShow", function(self)
        -- Preserve diagram geometry on smaller displays; never fold columns.
        self:SetScale(math.min(1, (UIParent:GetWidth() - 24) / windowWidth, (UIParent:GetHeight() - 24) / WINDOW_H))
        if self.activeTab then self:RenderLesson(true) end
    end)
    frame:SelectHelpTab("import")
    helpWindow, PRT.raidGroupsHelpWindow = frame, frame
    return frame
end

function PRT:OpenRaidGroupsHelp(tabKey)
    local frame = EnsureHelpWindow()
    frame:Show()
    frame:SelectHelpTab(tabKey or frame.activeTab or "import")
    frame:BringToFront()
end

function PRT:ToggleRaidGroupsHelp(tabKey)
    local frame = EnsureHelpWindow()
    if frame:IsShown() and (not tabKey or tabKey == frame.activeTab) then frame:Hide(); return end
    self:OpenRaidGroupsHelp(tabKey)
end
