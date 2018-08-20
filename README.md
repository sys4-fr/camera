# Camera
This mod allow to record flight paths and replay them.

## Dependencies
* default from minetest_game

## License
* Code: MIT
* Models and textures: CC-BY-SA-3.0

##Usage
* /camera : Execute command to start recording.

**While recording**

* use up/down to accelerate/decelerate
 * when rotating (mode 2 or 3) the camera up or down on Y axis
* use jump to brake
* use aux1 to stop recording
* use left/right to rotate if looking target is set
* use crouch to stop rotating

Use **/camera play** to play back the last recording. While playing back:

* use aux1 to stop playing back

Use **/camera play <name>** to play a specific recording

Use **/camera save <name> ** to save the last recording

* saved recordings exist through game restarts

Use **/camera list** to show all saved recording

Use **/camera mode <0|2|3> ** to change the velocity behaviour 

* 0: Velocity follow mouse (default),
* 2: Velocity locked to player's first look direction with released mouse
* 3: Same that 2 but if you up or down when rotating then looking target will up or down too

Use **/camera look <nil|here|x,y,z> **

* nil: remove looking target,
* here: set looking target to player position,
* x,y,z: Coords to look at

Use **/camera speed <speed> **

* 10 is default speed,
* > 10 decrease speed factor,
* < 10 increase speed factor

>Copyright 2016-2017 - Auke Kok <sofar@foo-projects.org>

>Copyright 2017 - Elijah Duffy <theoctacian@gmail.com>

>Copyright 2017-2018 - sys4 <sys4@free.fr>

