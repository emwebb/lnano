-- SECTION REQUIREMENTS 
local fs = require("filesystem")
local term = require("term")
local computer = require("computer")
local keyboard = require("keyboard")
local event = require("event")
local gpu = require("component").gpu
local serialization = require("serialization")
local io = require("io")
local shell = require("shell")
-- SECTION PRE INIT
--Create the logger
function createLogger()
    local logger = {}
    function logger:init(program)
          self.loggerFolder = "/var/" .. program .. "/"
          local logNumber = 0
          local found = false
          while not found do
            if (fs.exists(self.loggerFolder .. "log-" .. logNumber .. ".log")) then
                  logNumber = logNumber + 1
            else
                  self.logNumber = logNumber
                  found = true
               end     
          end
      self.logFile = self.loggerFolder.."log-"..self.logNumber..".log"
      self.initTime = os.time()
    end 

    function logger:ensurelogFolderExists()
          if not fs.exists(self.loggerFolder) then
            fs.makeDirectory(self.loggerFolder)
          end
    end

    function logger:log(message)
          self:ensurelogFolderExists()
          local file = io.open(self.logFile ,"a")
          file:write("["..string.format("%07d",(os.time() - self.initTime)).."]"..message.."\n")
          file:close()
    end
    
    return logger
end

local logger = createLogger()

local versionNum = 0
local versionName = "0.0"
--Initialise the logger
logger:init("lnano")
logger:log("Starting LNANO "..versionName.." ("..versionNum..")")

--SECTION ARGUMENTS
local args, options = shell.parse(...)

local rtconfig = {} -- Runtime Config
-- These process the options.
rtconfig.readonly = options.r or options.readonly      -- Should we allow them to edit the file.
rtconfig.backup = options.b or options.backup            -- Should we make a backup?
rtconfig.backupdir = shell.resolve(options.c or options.backupdir or "")   -- If so, where?
rtconfig.showhelp = options.h or options.help          -- Should we display the help?
rtconfig.showversion = options.v or options.version    -- Should we display the version?

logger:log("Runtime config :"..serialization.serialize(rtconfig))
-- Have we been asked to do something which means we don't need to actually load/make a file?
local doPreFileShutdown = rtconfig.showhelp or rtconfig.showversion


if rtconfig.showhelp then 
    logger:log("h(elp) option present. Running \"man lnano\" then exiting")
    shell.execute("man lnano")
end
if rtconfig.showversion then
    logger:log("v(ersion) option present. Displaying version then exiting")
    print("LNANO "..versionName.." ("..versionNum..")");
end

if doPreFileShutdown then return end -- If we have been asked to do something that doesn't require us to load/make a file then exit now.

-- SECTION INIT

local text = {} -- The text buffer , stored as an array of lines.
local colourBuffer = {} -- The colour buffer , mapped to the text buffer rather than the screen.

local cursor = {}
-- The location of the cursor in the text.
cursor.line = 1 
cursor.column = 1


local view = {}
view.x = 0
view.y = 0

function view.getCursorViewPos() -- returns the cursor location with in the view index starts at 1
    return cursor.column - view.x , cursor.line - view.y
end


local filename = nil  -- The name of the file we are currently editing.
local newfile = nil   -- Is this a new file or are we editing a pre existing one?

local colours = {}
if gpu.getDepth() == 1 then
    colours = {
        viewBackground          = 0x000000,
        menuBackground          = 0x000000,
        normalText              = 0xFFFFFF,
        menuText                = 0xFFFFFF,
        syntax                  = {
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF,
                                    0xFFFFFF
                                    }
    }
else
    colours = {
        viewBackground          = 0x000000,
        menuBackground          = 0x333333,
        normalText              = 0xFFFFFF,
        menuText                = 0x9AA1A1,
        syntax                  = {
                                    gpu.getPaletteColor(0),
                                    gpu.getPaletteColor(1),
                                    gpu.getPaletteColor(2),
                                    gpu.getPaletteColor(3),
                                    gpu.getPaletteColor(4),
                                    gpu.getPaletteColor(5),
                                    gpu.getPaletteColor(6),
                                    gpu.getPaletteColor(7),
                                    gpu.getPaletteColor(8),
                                    gpu.getPaletteColor(9),
                                    gpu.getPaletteColor(10),
                                    gpu.getPaletteColor(11),
                                    gpu.getPaletteColor(12),
                                    gpu.getPaletteColor(13),
                                    gpu.getPaletteColor(14),
                                    gpu.getPaletteColor(15)
                                    }
    }
end


logger:log(serialization.serialize(colours))


local renderer = {};
renderer.sideBarWidth = 7
renderer.topBarHeight = 2
renderer.bottomBarHeight = 4

function renderer.drawTextViewLine(texty,textviewy) 
    if text[texty] then
        for x = view.x,  view.x + renderer.textViewWidth do
            local c = text[texty]:sub(x,x) 
            if c == "" then c = " " end
            gpu.setForeground(colours.normalText)
            gpu.setBackground(colours.viewBackground)
            gpu.set(x+renderer.textViewX - view.x,textviewy+renderer.textViewY ,c)
        end
    else
        gpu.fill(renderer.textViewX,textviewy+renderer.textViewY ,renderer.textViewWidth,1," ")
    end

end 


function renderer.drawTextView() 
    screenwidth,screenheight = gpu.getResolution()
    renderer.textViewWidth = screenwidth - renderer.sideBarWidth
    renderer.textViewHeight = screenheight - renderer.topBarHeight - renderer.bottomBarHeight
    renderer.textViewX = renderer.sideBarWidth
    renderer.textViewY = renderer.topBarHeight
    for y = 1, renderer.textViewHeight  , 1 do
        renderer.drawTextViewLine(y + view.y,y) 
    end
    
end

function renderer.update() end

function renderer.getCursorScreenLocation()
    local viewx, viewy = view.getCursorViewPos()
    
    return viewx + renderer.sideBarWidth , viewy + renderer.topBarHeight
end

function renderer.drawLineNumber()
    gpu.setBackground(colours.menuBackground)
    gpu.setForeground(colours.menuText)
    gpu.fill(1,renderer.topBarHeight+1,renderer.sideBarWidth,renderer.textViewHeight," ")
    for y = 1, renderer.textViewHeight , 1 do
     gpu.set(0,y + renderer.topBarHeight ,string.format ("%6.0f", y + view.y).."┃ ")
    end
end

function renderer.drawHeader()
    screenwidth,screenheight = gpu.getResolution()
    gpu.setBackground(colours.menuBackground)
    gpu.setForeground(colours.menuText)
    gpu.fill(1,1,screenwidth,renderer.topBarHeight," ")
    local info = "lnano "..versionName.." ("..versionNum..") file: "..filename
    if rtconfig.readonly then info = info.." [read only]" end
    gpu.set(1,1,info)
    gpu.fill(1,renderer.topBarHeight,screenwidth,1,"━")
    gpu.set(renderer.sideBarWidth-1,renderer.topBarHeight,"┳")
end

function renderer.drawFooter()
    screenwidth,screenheight = gpu.getResolution()
    gpu.setBackground(colours.menuBackground)
    gpu.setForeground(colours.menuText)
    gpu.fill(1,renderer.textViewHeight + renderer.topBarHeight + 1 ,screenwidth,renderer.bottomBarHeight," ")
    gpu.fill(1,renderer.textViewHeight + renderer.topBarHeight + 1 ,screenwidth,1,"━")
    gpu.set(renderer.sideBarWidth-1,renderer.textViewHeight + renderer.topBarHeight + 1,"┻")
end

function renderer.redraw()

    screenwidth,screenheight = gpu.getResolution()
    
    gpu.setForeground(colours.normalText)
    gpu.setBackground(colours.viewBackground)
    
    gpu.fill(1,1,screenwidth,screenheight," ")
    renderer.drawTextView() 
    renderer.drawLineNumber()
    renderer.drawHeader()
    renderer.drawFooter()
end

function cursor.move(x,y) 

    
    local cx,cy = renderer.getCursorScreenLocation()
    local str , fore = gpu.get(cx,cy)
    gpu.setForeground(fore)
        
    gpu.setBackground(0x000000)
    gpu.set(cx,cy,str)
    
    cursor.line = cursor.line + y
    cursor.column = cursor.column + x
    
    cx,cy = renderer.getCursorScreenLocation()
    str , fore = gpu.get(cx,cy)
    gpu.setForeground(fore)
        
    gpu.setBackground(0xFFFFFF)
    gpu.set(cx,cy,str)
end


function writeChar(char)

end


local function lnanoerror() 

end

local function loadFileIntoBuffer() --Loads the file into the text buffer.
    local f = io.open(filename,'r')
      if f then
          for line in f:lines() do
              table.insert(text, line)
          end
        if #text == 0 then
            table.insert(text,"")
        end
        f:close()
    end
end

local function saveFileFromBuffer() --Save the buffer into a file.
    if rtconfig.readonly or fs.get(filename).isReadOnly() then
        logger:log("Attempted to save buffer to \""..filename.."\" but can not due to read only. This should never happen.")
        lnanoerror()
        return
    end
    
    if rtconfig.backup and fs.exists(filename) then
        local backupLoc = rtconfig.backupdir.."~"..filename:match( "([^/]+)$")
        logger:log("Backing up \""..filename.."\" to \""..backupLoc.."\".")
        fs.copy(filename,backupLoc)
    end
        
    
    local f = io.open(filename,'w')
      if f then
          for line in text do
              f:write(line..'\n')
          end
          
    f:close()
    end
    
end

local timerManager = {}
function timerManager.registerFlashTimer()
    local flash = true
    
    timerManager.flashTimer = event.timer(0.5, function()
        if flash then
            flash = false
            gpu.setBackground(0xFFFFFF)
        else       
            flash = true
            gpu.setBackground(0x000000)
        end
        
        local x,y = renderer.getCursorScreenLocation()
        local str , fore = gpu.get(x,y)
        gpu.setForeground(fore)
        gpu.set(x,y,str)
        gpu.setBackground(0x000000)
    end, math.huge)

end
function timerManager.registerTimers() 
    timerManager.registerFlashTimer()

end

function timerManager.unregister() 
    event.cancel(timerManager.flashTimer)

end 


local running = true

local keyboardHandler = {
    normal = {
        [keyboard.keys.down] = function() 
            cursor.move(0,1)
        
        end,
        [keyboard.keys.up] = function() 
            cursor.move(0,-1)
        
        end,
        [keyboard.keys.left] = function() 
            cursor.move(-1,0)
        
        end,
        [keyboard.keys.right] = function() 
            cursor.move(1,0)
        
        end,
    },
    control = {},
    alt = {},
    controlAlt = {}
}






local eventHandler = {}
eventHandler.events = {}

function eventHandler.events.key_down(keyBoardAdress,char,code,playerName) 

    if char then
        keyboard.pressedChars[char] = true
    end
    if code then
        keyboard.pressedCodes[code] = true
    end
    
    if not (keyboard.isControlDown() or keyboard.isAltDown()) then
        
            logger:log("Correct Section"..tostring(char))
        if char then
            if not (keyboard.isControl(char) or ( char >= 0xE000 and char <= 0xF8FF)) then
                writeChar(char)
            else
                if keyboardHandler.normal[code] then
                    keyboardHandler.normal[code]()
                end
            end
        else
            if keyboardHandler.normal[code] then
                keyboardHandler.normal[code]()
            end
        
        end
    
    end
    
    if  keyboard.isControlDown() and keyboard.pressedCodes[keyboard.keys.q] then 
        running = false
    end
    
    if  keyboard.isControlDown() and keyboard.pressedCodes[keyboard.keys.r] then 
        renderer.redraw()
    end
end

function eventHandler.events.key_up(keyBoardAdress,char,code,playerName) 
    if char then
        keyboard.pressedChars[char] = false
    end
    
     if code then
        keyboard.pressedCodes[code] = false
    end
end


function eventHandler.handle(eventName, arg1, arg2, arg3, arg4)

    if eventName then
    
        if eventHandler.events[eventName] then
            eventHandler.events[eventName](arg1,arg2,arg3,arg4)
        end
    end
    
end

-- Start the program

if #args == 0 then
    
    -- No file specified. So we will create a new one with no name.
    newfile = true
    filename = shell.resolve("untitled")
    logger:log("No file specified. New file with filename \""..filename.."\".")
    
else
    filename = shell.resolve(args[1])
    if fs.exists(filename) then
        -- A file that exist is specified.
        newfile = false
        rtconfig.readonly = rtconfig.readonly or fs.get(filename).isReadOnly()
        logger:log("An existing file with filename\""..filename.."\" has been specified")
        if rtconfig.readonly then
            logger:log("Opening file as read only.")
        end
    else
        newfile = true
        logger:log("A new file with filename\""..filename.."\" has been specified")
        -- A file that does not exist is specified.
    end
end

if newfile then
    table.insert(text,"") -- We need a starting point
else
    loadFileIntoBuffer()
end
renderer.redraw()

timerManager.registerTimers() 



while running do
    local eventName, arg1, arg2, arg3, arg4 = event.pull()
    eventHandler.handle(eventName, arg1, arg2, arg3, arg4)
end
timerManager.unregister() 
term.clear()