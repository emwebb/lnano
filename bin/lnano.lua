local fs = require("filesystem")
local term = require("term")
local computer = require("computer")
local keyboard = require("keyboard")
local event = require("event")
local gpu = require("component").gpu
local serialization = require("serialization")
local io = require("io")
local shell = require("shell")

--Create the logger
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
  self.initTime = os.time()
end 

function logger:ensurelogFolderExists()
  if not fs.exists(self.loggerFolder) then
    fs.makeDirectory(self.loggerFolder)
  end
end

function logger:log(message)
  self:ensurelogFolderExists()
  local file = io.open(self.loggerFolder.."log-"..self.logNumber..".log","a")
  file:write("["..string.format("%07d",(os.time() - self.initTime)).."]"..message.."\n")
  file:close()
end

local versionNum = 0
local versionName = "0.0"
--Initialise the logger
logger:init("lnano")
logger:log("Starting LNANO "..versionName.." ("..versionNum..")")


local args, options = shell.parse(...)
--If we just need to show the help screen or display the version number , no need to load in everything else.
if options.h then
	shell.execute("man lnano")
	return
end
if options.v then
	print("LNANO "..versionName.." ("..versionNum..")");
	return
end


local text = {} -- The text buffer , stored as an array of lines.
local colour = {} -- The colour buffer , mapped to the text buffer rather than the screen.

local cursor = {}
-- The location of the cursor in the text.
cursor.line = 0 
cursor.column = 0

local filename = nil -- The name of the file we are currently editing.
local readOnly = nil -- Should we allow them to edit the file.
local newfile = nil; -- Is this a new file or are we editing a pre existing one?


if #args == 0 then
	-- No file specified. So we will create a new one with no name.
	newfile = true
	filename = "untitled"
	
else
	filename = shell.resolve(args[1])
	if fs.exists(filename) then
		-- A file that exist is specified.
		newfile = false
		readOnly = options.r or fs.get(filename) == nil or fs.get(filename).isReadOnly()
	else
		newfile = true
		-- A file that does not exist is specified.
	end
end

local function loadFileIntoBuffer() --Loads the file into the text buffer.
	local f = io.open(filename)
  	if f then
  		for line in f:lines() do
      		table.insert(text, line)
      	end
    end
end

-- DEBUG
loadFileIntoBuffer()

logger:log(serialization.serialize(text))
	
		
	


		
	