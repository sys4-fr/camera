--[[
Copyright 2016-2017 - Auke Kok <sofar@foo-projects.org>
Copyright 2017 - Elijah Duffy <theoctacian@gmail.com>
Copyright 2017 - sys4 <sys4@free.fr>
License:
	- Code: MIT
	- Models and textures: CC-BY-SA-3.0
Usage: /camera
	Execute command to start recording. 
	While recording:
	- use up/down to accelerate/decelerate
	  - when rotating (mode 2 or 3) the camera up or down on Y axis
	- use jump to brake
	- use aux1 to stop recording
	- use left/right to rotate if looking target is set
	- use crouch to stop rotating
	Use /camera play to play back the last recording. While playing back:
	- use aux1 to stop playing back
	Use /camera play <name> to play a specific recording
	Use /camera save <name> to save the last recording
	- saved recordings exist through game restarts
	Use /camera list to show all saved recording
	Use /camera mode <0|2|3> to change the velocity behaviour 
	- 0: Velocity follow mouse (default),
	- 2: Velocity locked to player's first look direction with released mouse
	- 3: Same that 2 but if you up or down when rotating then looking target will up or down too
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

-- Table and functions for storing params per players
local player_params = {}

local function get_player_params(playern)
	if not player_params[playern] then
		player_params[playern] = {}
	end

	return player_params[playern]
end

-- Camera definition
local camera = {
	description = "Camera",
	visual = "wielditem",
	textures = {},
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
		self.look_dir_init = player:get_look_dir()
		self.speed = 0
	end,
}


-- [event] On step
function camera:on_step(dtime)
	-- if not driver, remove object
	if not self.driver then
		self.object:remove()
		return
	end

	local pos = self.object:getpos()
	local vel = self.object:getvelocity()
	
	-- if record mode
	if self.mode == 0 or self.mode > 1 then
		-- Calculate pitch and yaw if look target of player is defined
		local look_target = player_params[self.driver:get_player_name()].look_target

		if look_target then
			local vec_pos = vector.subtract(look_target, pos)

			-- Pitch
			if math.abs(vec_pos.z) > math.abs(vec_pos.x) then
				self.driver:set_look_vertical(-math.atan2(vec_pos.y, math.abs(vec_pos.z)))
			else
				self.driver:set_look_vertical(-math.atan2(vec_pos.y, math.abs(vec_pos.x)))
			end

			-- Yaw
			self.driver:set_look_horizontal(-math.atan2(vec_pos.x, vec_pos.z))
		end
		
		-- Update path
		self.path[#self.path + 1] = {
			pos = pos,
			velocity = vel,
			pitch = self.driver:get_look_vertical(),
			yaw = self.driver:get_look_horizontal()
		}

		-- Modify yaw and pitch to match driver (player)
		self.object:set_look_vertical(self.driver:get_look_vertical())
		self.object:set_look_horizontal(self.driver:get_look_horizontal())

		local params = get_player_params(self.driver:get_player_name())

		-- Get controls
		local ctrl = self.driver:get_player_control()

		-- Initialize speed
		--local speed = vector.distance(vector.new(), vel)
		local speed = self.speed

		-- if up, accelerate forward
		if ctrl.up then
			speed = math.min(speed + (params.speed_step or 0.1), 20)
		end

		-- if down, accelerate backward
		if ctrl.down then
			speed = math.max(speed - (params.speed_step or 0.1), -20)
		end

		-- if jump, brake
		if ctrl.jump then
			speed = math.max(speed * 0.9, 0.0)
			params.rotate_speed = math.max((params.rotate_speed or 0) * 0.9, 0.0)
		end

		-- if aux1 (aka key 'e'), stop recording
		if ctrl.aux1 then
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Recorded stopped after " .. #self.path .. " points")
			temp[self.driver:get_player_name()] = table.copy(self.path)
			self.object:remove()
			return
		end

		-- if sneak, stop rotation
		if ctrl.sneak then
			params.rotate = false
			params.rotate_speed = 0.0
		end

		-- if right, accelerate rotation to right
		if ctrl.right and params.look_target then
			params.rotate = true
			params.rotate_speed = math.min((params.rotate_speed or 0.0) + (params.speed_step or 0.1), 0.5)
			speed = 0
		end
		
		-- if left, accelerate rotation to left
		if ctrl.left and params.look_target then
			params.rotate = true
			params.rotate_speed = math.max((params.rotate_speed or 0.0) - (params.speed_step or 0.1), -1)
			speed = 0
		end
		
		-- Set updated velocity

		-- Normal Velocity mode
		if self.mode == 0 then
			self.object:setvelocity(vector.multiply(self.driver:get_look_dir(), speed))
		elseif self.mode > 1 then

			-- Rotation Velocity mode
			if params.rotate then
				self.object:setvelocity(
					vector.multiply(
						{
							x = self.object:get_velocity().x + math.cos(self.driver:get_look_horizontal()),
							y = speed,
							z = self.object:get_velocity().z + math.sin(self.driver:get_look_horizontal())
						},
						{
							x = params.rotate_speed,
							y = 1,
							z = params.rotate_speed
						}
					))

				-- if mode 3 then look target up or down at the same time of the camera during rotation
				if self.mode == 3 then

					-- First step (old_pos = pos)
					if not self.old_pos then self.old_pos = pos end

					look_target.y = look_target.y + (pos.y - self.old_pos.y)
					player_params[self.driver:get_player_name()].look_target = look_target

					-- memorize pos as old_pos for next steps
					self.old_pos = pos
				end
			else
				-- Looking target Velocity mode
				self.object:setvelocity(vector.multiply(self.look_dir_init, speed))
			end
		end

		-- memorize speed for next step
		self.speed = speed
	elseif self.mode == 1 then -- elseif playback mode
		-- Get controls
		local ctrl = self.driver:get_player_control()

		-- if aux1 or no path, stop playback
		if ctrl.aux1 or #self.path < 1 then
			self.driver:set_detach()
			minetest.chat_send_player(self.driver:get_player_name(), "Playback stopped")
			self.object:remove()
			return
		end

		-- Update position
		self.object:moveto(self.path[1].pos, true)
		-- Update yaw/pitch
		self.driver:set_look_horizontal(self.path[1].yaw)
		self.driver:set_look_vertical(self.path[1].pitch)
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
				object:setyaw(player:get_look_horizontal())
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
					get_player_params(name).look_target = nil
					return true, "Looking target removed"
				elseif param2 == "here" then
					local player_params = get_player_params(name)
					if (not player_params.mode) then
						player_params.mode = 2
					end
					player_params.look_target = player:getpos()
					return true, "Looking target fixed"
				else
					local look_target = string.split(param2, ",")
					if #look_target == 3 then
						local player_params = get_player_params(name)
						player_params.mode = 2
						player_params.look_target =
							{ x = tonumber(look_target[1]),
							  y = tonumber(look_target[2]),
							  z = tonumber(look_target[3])
							}
						return true, "Looking target fixed"
					else
						return false, "Looking target wrong format (/camera look <x,y,z>)"
					end
				end
			else
				return false, "Parameters of looking target are missing (/camera look <nil|here|x,y,z>)"
			end
		elseif param1 == "speed" then
			if param2 and param ~= "" then
				local speed = tonumber(param2)
				if speed then
					get_player_params(name).speed_step = 1/speed
					return true, "Speed step fixed to "..get_player_params(name).speed_step
				else
					return false, "Invalid speed step (/camera speed <number>)"
				end
			else return false, "Missing speed step parameter (/camera speed <number>)"
			end
		elseif param1 == "mode" then
			if param2 and param2 ~= "" then
				local mode = tonumber(param2)
				if mode == 0 or mode > 1 then
					get_player_params(name).mode = mode
					if mode == 0 then
						get_player_params(name).look_target = nil
					end
					return true, "Record mode is set"
				else return false, "Invalid mode (0: Velocity follow mouse (default), 2: Velocity locked to player first look direction, 3: Same as 2 but looking target can up/down when rotating)"
				end
			else return false, "Missing mod parameter (/camera mode <0|2|3>)"
			end
		elseif param1 == "help" then
			local str = "Usage: /camera\n"..
				"Execute command to start recording.\n"..
				"While recording:\n"..
				"- use up/down to accelerate/decelerate\n"..
				"  - when rotating (mode 2 or 3) the camera up or down on Y axis\n"..
				"- use jump to brake\n"..
				"- use aux1 to stop recording\n"..
			"- use left/right to rotate if looking target is set\n"..
				"- use crouch to stop rotating\n"..
				"Use /camera play to play back the last recording. While playing back:\n"..
				"- use aux1 to stop playing back\n"..
				"Use /camera play <name> to play a specific recording\n"..
				"Use /camera save <name> to save the last recording\n"..
				"- saved recordings exist through game restarts\n"..
				"Use /camera list to show all saved recording\n"..
				"Use /camera mode <0|2|3> to change the velocity behaviour\n"..
				"- 0: Velocity follow mouse (default),\n"..
				"- 2: Velocity locked to player's first look direction with released mouse\n"..
				"- 3: Same that 2 but if you up or down when rotating then looking target will up or down too\n"..
				"Use /camera look <nil|here|x,y,z>\n"..
				"- nil: remove looking target,\n"..
				"- here: set looking target to player position,\n"..
				"- x,y,z: Coords to look at\n"..
				"Use /camera speed <speed>\n"..
				"- 10 is default speed,\n"..
				"- > 10 decrease speed factor,\n"..
				"- < 10 increase speed factor"
			return true, str
		else -- else, begin recording
			local object = minetest.add_entity(player:getpos(), "camera:camera")
			object:get_luaentity():init(player, get_player_params(name).mode)
			object:setyaw(player:get_look_horizontal())
			player:set_attach(object, "", {x=0,y=10,z=0}, {x=0,y=0,z=0})
			return true, "Recording started"
		end
	end,
})
