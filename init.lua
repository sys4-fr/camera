
--[[

Copyright 2016-2017 - Auke Kok <sofar@foo-projects.org>
Copyright 2017 - Elijah Duffy <theoctacian@gmail.com>
Copyright 2017 - sys4 <sys4@free.fr>

License:
	- Code: MIT
	- Models and textures: CC-BY-SA-3.0
Usage: /camera
	Execute command to start recording. While recording:
	- use up/down to accelerate/decelerate
	- use jump to brake
	- use crouch to stop recording
	Use /camera play to play back the last recording. While playing back:
	- use crouch to stop playing back
	Use /camera play <name> to play a specific recording
	Use /camera save <name> to save the last recording
	- saved recordings exist through game restarts
	Use /camera list to show all saved recording
	Use /camera mode <0|2> to change the velocity behaviour 
	- 0: Velocity follow mouse (default),
	- 2: Velocity locked to player's first look direction with released mouse
	Use /camera look <nil|here|x,y,z>
	- nil: remove looking target,
	- here: set looking target to player position,
	- x,y,z: Coords to look at
	Use /camera speed <speed>
	- 10 is default speed,
	- > 10 decrease speed factor,
	- < 10 increase speed factor
--]]

local recordings = {}

-- [function] Load recordings
local path = minetest.get_worldpath()

local function load()
	local res = io.open(path.."/recordings.txt", "r")
	if res then
		res = minetest.deserialize(res:read("*all"))
		if type(res) == "table" then
			recordings = res
		end
	end
end

-- Call load
load()

-- [function] Save recordings
function save()
	io.open(path.."/recordings.txt", "w"):write(minetest.serialize(recordings))
end

-- [function] Get recording list per-player for chat
function get_recordings(name)
	local recs = recordings[name]
	local list = ""

	if recs then
		for name, path in pairs(recs) do
			list = list..name..", "
		end
		return list
	else
		return "You do not saved any recordings."
	end
end

-- [event] On shutdown save recordings
minetest.register_on_shutdown(save)

-- Table for storing unsaved temporary recordings
local temp = {}

-- Camera definition
local camera = {
	description = "Camera",
	visual = "wielditem",
	textures = {},
	physical = false,
	is_visible = false,
	collide_with_objects = false,
	collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	physical = false,
	visual = "cube",
	driver = nil,
	mode = 0,
	velocity = {x=0, y=0, z=0},
	old_pos = nil,
	old_velocity = nil,
	pre_stop_dir = nil,
	MAX_V = 20,
	init = function(self, player, mode)
		self.driver = player
		self.mode = mode
		self.path = {}
	end,
}

local player_look_dir = nil -- player look direction when starting record
local target_look_position = nil -- looking target
local speed_factor = 0.1 -- default speed factor
local rec_mode = 0 -- record mode

-- [event] On step
function camera:on_step(dtime)
	-- if not driver, remove object
	if not self.driver then
		self.object:remove()
		return
	end

	local pos = self.object:getpos()
	local vel = self.object:getvelocity()
	local dir = self.driver:get_look_dir()

	-- if record mode
	if self.mode == 0 or self.mode == 2 then
		-- Calculate pitch and yaw if target_look_position defined
		if target_look_position then
			local vec_pos = vector.subtract(target_look_position, pos)
			print("vec_pos "..dump(vec_pos))

			-- Pitch
			local opp = vec_pos.y
			local adj = vec_pos.x

			if math.abs(vec_pos.z) > math.abs(vec_pos.x) then
				adj = vec_pos.z
			end

			self.driver:set_look_vertical(math.atan((opp*-1)/math.abs(adj)))
			
			-- Yaw
			opp = vec_pos.x
			adj = vec_pos.z

			local yaw = math.atan(opp/adj)
			
			if math.abs(vec_pos.x) > math.abs(vec_pos.z) then
				yaw = math.atan(adj/opp)

				if adj < 0 and opp < 0 then
					yaw = yaw + math.pi/2
				end
				
				if adj > 0 and opp > 0 then
					yaw = yaw + math.pi + math.pi/2
				end

				if yaw < 0 then
					if opp > 0 then
						yaw = math.pi + math.pi/2 + yaw
					else
						yaw = math.pi/2 + yaw
					end
				end
				
			else
				if adj < 0 and opp < 0 then
					yaw = yaw - math.pi
				end

				if adj > 0 and opp > 0 then
					yaw = math.pi*2 - yaw
				end
				
				if yaw < 0 then
					if opp > 0 then
						yaw = math.pi - yaw
					else
						yaw = math.pi*2 - yaw
					end
				end
			end
			
			self.driver:set_look_horizontal(yaw)
		end
		
		-- Update path
		self.path[#self.path + 1] = {
			pos = pos,
			velocity = vel,
			pitch = self.driver:get_look_pitch(),
			yaw = self.driver:get_look_yaw()
		}

		-- Modify yaw and pitch to match driver (player)
		self.object:set_look_pitch(self.driver:get_look_pitch())
		self.object:set_look_yaw(self.driver:get_look_yaw())

		-- Get controls
		local ctrl = self.driver:get_player_control()

		-- Initialize speed
		local speed = vector.distance(vector.new(), vel)

		-- if up, accelerate forward
		if ctrl.up then
			speed = math.min(speed + speed_factor, 20)
		end

		-- if down, accelerate backward
		if ctrl.down then
			speed = math.max(speed - speed_factor, -20)
		end

		-- if jump, brake
		if ctrl.jump then
			speed = math.max(speed * 0.9, 0.0)
		end

		-- if sneak, stop recording
		if ctrl.sneak then
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Recorded stopped after " .. #self.path .. " points")
			temp[self.driver:get_player_name()] = table.copy(self.path)
			self.object:remove()
			return
		end

		-- Set updated velocity
		if self.mode == 0 then
			self.object:setvelocity(vector.multiply(self.driver:get_look_dir(), speed))
		elseif self.mode == 2 then
			self.object:setvelocity(vector.multiply(player_look_dir, speed))
		end
	elseif self.mode == 1 then -- elseif playback mode
		-- Get controls
		local ctrl = self.driver:get_player_control()

		-- if sneak or no path, stop playback
		if ctrl.sneak or #self.path < 1 then
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Playback stopped")
			self.object:remove()
			return
		end

		-- Update position
		self.object:moveto(self.path[1].pos, true)
		-- Update yaw/pitch
		self.driver:set_look_yaw(self.path[1].yaw - (math.pi/2))
		self.driver:set_look_pitch(0 - self.path[1].pitch)
		-- Update velocity
		self.object:setvelocity(self.path[1].velocity)
		-- Remove path table
		table.remove(self.path, 1)
	end
end

-- Register entity
minetest.register_entity("camera:camera", camera)

-- Register chatcommand
minetest.register_chatcommand("camera", {
	description = "Manipulate recording",
	params = "<option> <value>",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local param1, param2 = param:split(" ")[1], param:split(" ")[2]

		-- if play, begin playback preperation
		if param1 == "play" then
			local function play(path)
				local object = minetest.add_entity(player:getpos(), "camera:camera")
				object:get_luaentity():init(player, 1)
				object:setyaw(player:get_look_yaw())
				player:set_attach(object, "", {x=5,y=10,z=0}, {x=0,y=0,z=0})
				object:get_luaentity().path = path
			end

			-- Check for param2 (recording name)
			if param2 and param2 ~= "" then
				-- if recording exists, start
				if recordings[name][param2] then
					play(table.copy(recordings[name][param2]))
				else -- else, return error
					return false, "Invalid recording "..param2..". Use /camera list to list recordings."
				end
			else -- else, check temp for a recording path
				if temp[name] then
					play(table.copy(temp[name]))
				else
					return false, "No recordings could be found"
				end
			end

			return true, "Playback started"
		elseif param1 == "save" then -- elseif save, prepare to save path
			-- if no table for player in recordings, initialize
			if not recordings[name] then
				recordings[name] = {}
			end

			-- if param2 is not blank, save
			if param2 and param2 ~= "" then
				recordings[name][param2] = temp[name]
				return true, "Saved recording as "..param2
			else -- else, return error
				return false, "Missing name to save recording under (/camera save <name>)"
			end
		elseif param1 == "list" then -- elseif list, list recordings
			return true, "Recordings: "..get_recordings(name)
		elseif param1 == "look" then
			if param2 and param2 ~= "" then
				if param2 == "nil" then
					target_look_position = nil
					return true, "Looking target removed"
				elseif param2 == "here" then
					rec_mode = 2
					target_look_position = player:getpos()
					return true, "Looking target fixed"
				else
					local coord = string.split(param2, ",")
					if #coord == 3 then
						target_look_position = {x=tonumber(coord[1]), y=tonumber(coord[2]), z=tonumber(coord[3])}
						rec_mode = 2
						return true, "Looking target fixed"
					else
						return false, "Wrong formated look coords (/camera look <x,y,z>)"
					end
				end
			else
				return false, "Missing look parameter (/camera look <nil|here|x,y,z>)"
			end
		elseif param1 == "speed" then
			if param2 and param2 ~= "" then
				local speed = tonumber(param2)
				if speed then
					speed_factor = 1/speed
					return true, "Speed factor fixed to "..speed_factor
				else
					return false, "Invalid speed factor (/camera speed <number>)"
				end
			else
				return false, "Missing speed parameter (/camera speed <number>)"
			end
		elseif param1 == "mode" then
			if param2 and param2 ~= "" then
				local mode = tonumber(param2)
				if mode == 0 or mode == 2 then
					rec_mode = mode
					return true, "Record mode is set"
				else
					return false, "Invalid mode (0: Velocity follow mouse (default), 2: Velocity locked to player first look direction)"
				end
			else
				return false, "Missing mode parameter (/camera mode <0|2>)"
			end
					
		else -- else, begin recording
			player_look_dir = player:get_look_dir()
			local object = minetest.add_entity(player:getpos(), "camera:camera")
			object:get_luaentity():init(player, rec_mode)
			object:setyaw(player:get_look_yaw())
			player:set_attach(object, "", {x=0,y=10,z=0}, {x=0,y=0,z=0})
			return true, "Recording started"
		end
	end,
})
