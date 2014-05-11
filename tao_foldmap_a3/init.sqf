// Tao Folding Map functions and initialization.
// (C) 20132-14 Ryan Schultz. See LICENSE.

tao_foldmap = false;



///////////////////////////////////////////////////////////////////////////////

// Include BI DIK codes.
#include "\a3\editor_f\Data\Scripts\dikCodes.h"
// Include the userconfig key file.
#include "\userconfig\tao_foldmap_a3\tao_foldmap_a3.hpp"

#undef TAO_FOLDMAP_PAPER
#define TAO_FOLDMAP_PAPER false

// These parameters were added after the first config file was released
// so users might not have them in their userconfig file.
#ifndef TAO_FOLDMAP_ENABLESHAKE
	#define TAO_FOLDMAP_ENABLESHAKE true
#endif
#ifndef TAO_FOLDMAP_REPOSITION
	#define TAO_FOLDMAP_REPOSITION DIK_M
#endif
#ifndef TAO_FOLDMAP_REPOSITION_SHIFT
	#define TAO_FOLDMAP_REPOSITION_SHIFT true
#endif
#ifndef TAO_FOLDMAP_REPOSITION_CTRL
	#define TAO_FOLDMAP_REPOSITION_CTRL true
#endif
#ifndef TAO_FOLDMAP_REPOSITION_ALT
	#define TAO_FOLDMAP_REPOSITION_ALT true
#endif

// Global to track if userconfig file is being used or Tao Configuration System.
tao_foldmap_usingTCS = false;

// Get a rsc layer from the BI system.
tao_foldmap_rscLayer = ["TMR_FoldMap"] call BIS_fnc_rscLayer;

// Set appropriate map scale for the island being used.
// Default map scale computed as 0.2 * 8192 / mapsize
/* map size:
Stratis: 8192
Altis: 30720
Zargabad: 8192
Takistan: 12800
proving grounds: 2048  ("ProvingGrounds_PMC")
Shapur: 2048		("Shapur_BAF")
Utes: 5120		("utes")
Chernarus: 15360
Desert: 2048		("Desert_E")
*/
_island = worldname;
switch (_island) do
{
	case "Stratis": { tao_foldmap_mapScale = 0.2;};
	case "Zargabad": { tao_foldmap_mapScale = 0.2;};
	case "Altis": { tao_foldmap_mapScale = 0.053;};
	case "Takistan": { tao_foldmap_mapScale = 0.128;};
	case "ProvingGrounds_PMC": { tao_foldmap_mapScale = 0.8;};
	case "Shapur_BAF": { tao_foldmap_mapScale = 0.8;};
	case "Desert_E": { tao_foldmap_mapScale = 0.8;};
	case "Chernarus": { tao_foldmap_mapScale = 0.107;};
	case "utes": { tao_foldmap_mapScale = 0.32;};
	default { tao_foldmap_mapScale = 0.2;};
};

// Scale tracking globals.
tao_foldmap_needsScaleReset = false; 
tao_foldmap_baseScale = tao_foldmap_mapScale;

// Display the night vision map?
tao_foldmap_isNightMap = false; 

// Is the map open?
tao_foldmap_isOpen = false;


// Main GUI positioning data.
// -----
// Paper map needs to be slightly lower on screen.
tao_foldmap_paperTabletYDelta = 0;
if (TAO_FOLDMAP_PAPER) then {
	tao_foldmap_paperTabletYDelta = 0.057;
};

// Hardcoded defaults.
#define DEFAULT_MAP_XPOS (safezoneX + (safezoneW * 0.035))
#define DEFAULT_MAP_YPOS (safezoneY + (safezoneH * (0.304 + tao_foldmap_paperTabletYDelta)))
tao_foldmap_mapPosX = DEFAULT_MAP_XPOS;
tao_foldmap_mapPosY = DEFAULT_MAP_YPOS;

// Get positions from config if possible. Otherwise, defaults.
if (!isNil "tao_configsys") then {
	// Write defaults if necessary.
	["Tao Folding Map", "MapPosX", DEFAULT_MAP_XPOS] call tao_configsys_fnc_writeDefaultKey;
	["Tao Folding Map", "MapPosY", DEFAULT_MAP_YPOS] call tao_configsys_fnc_writeDefaultKey;

	// Read values from config file.
	_posX = ["Tao Folding Map", "MapPosX"] call tao_configsys_fnc_readKey;
	_posY = ["Tao Folding Map", "MapPosY"] call tao_configsys_fnc_readKey;

	// Make sure it's on the screen.
	if (typeName _posX == "SCALAR" && typeName _posY == "SCALAR" && _posX > safeZoneXAbs && _posY > safeZoneY && _posX < safeZoneWAbs && _posY < safeZoneH) then {

		tao_foldmap_mapPosX = _posX;
		tao_foldmap_mapPosY = _posY;
	};
};
// -----

// Scroll time for map.
#define SCROLLTIME 0.45

// Relative positioning defines.
#define MAP_XPOS (tao_foldmap_mapPosX)
#define MAP_YPOS (tao_foldmap_mapPosY)
#define BACK_XPOS (MAP_XPOS - (safezoneH * 0.093))
#define BACK_YPOS (MAP_YPOS - (safezoneH * 0.046))
#define STATUS_YOFFSET (safezoneH * 0.015)
#define STATUSTEXT_YOFFSET (STATUS_YOFFSET + (safezoneH * 0.001))

// Display control ID defines.
#define FOLDMAP (uiNamespace getVariable "Tao_FoldMap")
#define MOVEME (uiNamespace getVariable "Tao_FoldMap_MovingDialog")
#define BACKGROUND 23
#define DAYMAP 40
#define NIGHTMAP 41
#define STATUSBAR 30
#define STATUSRIGHT 31
#define STATUSLEFT 32

///////////////////////////////////////////////////////////////////////////////

// ----------------------------------------------------------------------------
// Per-frame draw handler for map.
// ----------------------------------------------------------------------------
tao_foldmap_fnc_drawUpdate = {
	// Draw location of player if in Vet/Expert and has a GPS and is tablet (no magic for paper map)
	if (!cadetMode && {("ItemGPS" in assignedItems player)} && {!TAO_FOLDMAP_PAPER}) then {
		_pos = getPos player;

		(FOLDMAP displayCtrl DAYMAP) drawIcon [getText(configFile >> "CfgMarkers" >> "mil_arrow2" >> "icon"), [0.06, 0.08, 0.06, 0.87], _pos, 19, 25, direction vehicle player, "", false];
		(FOLDMAP displayCtrl NIGHTMAP) drawIcon [getText(configFile >> "CfgMarkers" >> "mil_arrow2" >> "icon"), [0.9, 0.9, 0.9, 0.8], _pos, 19, 25, direction vehicle player, "", false];
	};

	if (TAO_FOLDMAP_PAPER) then {
		// Darken paper map based on time. Based on ShackTac Map Brightness by zx64 & Dslyecxi.
		_alpha = 0.6 min abs(sunOrMoon - 1);
		_rectPos = (FOLDMAP displayCtrl DAYMAP) ctrlMapScreenToWorld [MAP_XPOS, MAP_YPOS];
		
		// Draw a dark rectangle covering the map.
		(FOLDMAP displayCtrl DAYMAP) drawRectangle [_rectPos, tao_foldmap_pageWidth * 2.5, tao_foldmap_pageHeight * 2.5, 0, [0, 0, 0, _alpha], "#(rgb,1,1,1)color(0,0,0,1)"];
	};
};

// ----------------------------------------------------------------------------
// onLoad function for foldmap dialog.
// ----------------------------------------------------------------------------
tao_foldmap_fnc_onLoadDialog = {
	// If config set, change to paper map.
	if (TAO_FOLDMAP_PAPER) then {
		// Change to paper background.
		(FOLDMAP displayCtrl BACKGROUND) ctrlSetText "\tao_foldmap_a3\data\paper_ca.paa";

		// Hide the status bar.
		(FOLDMAP displayCtrl STATUSBAR) ctrlShow false;
		(FOLDMAP displayCtrl STATUSLEFT) ctrlShow false;
		(FOLDMAP displayCtrl STATUSRIGHT) ctrlShow false;
	};

	// Determine if it's day or night so we can use the correct map (tablet only).
	tao_foldmap_mapCtrlActive = DAYMAP;
	tao_foldmap_mapCtrlInactive = NIGHTMAP;
	if (!TAO_FOLDMAP_PAPER && {tao_foldmap_isNightMap}) then {
		tao_foldmap_mapCtrlActive = NIGHTMAP;
		tao_foldmap_mapCtrlInactive = DAYMAP;
	};
	
	// On first run, get the center pos. This is used for all paging thereafter.
	if (isNil "tao_foldmap_centerPos") then {
		tao_foldmap_centerPos = getPos player;
	};
	
	// Off-map check: if the player passed off the map while it was closed, recenter it.
	_dX = abs ((tao_foldmap_centerPos select 0) - (getPos player select 0));
	_dY = abs ((tao_foldmap_centerPos select 0) - (getPos player select 0));
	
	// Fudge factor here to avoid opening on the edge of the map, which isn't very helpful.
	if (_dX + 150 > tao_foldmap_pageWidth || _dY + 150 > tao_foldmap_pageHeight) then {
		tao_foldmap_centerPos = getPos player;
	};
	
	// Center map on current centering position.
	(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, tao_foldmap_centerPos];
	ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
	
	// Hide the unused map.
	(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlShow true;
	(FOLDMAP displayCtrl tao_foldmap_mapCtrlInactive) ctrlShow false;

	// Place everything in position to be scrolled.
	[0] call tao_foldmap_fnc_moveMapOffscreen;
	
	// Add per-frame draw handler to update the player marker and darken map.
	(FOLDMAP displayCtrl DAYMAP) ctrlAddEventHandler ["Draw", "[] call tao_foldmap_drawUpdate"];
	if (!TAO_FOLDMAP_PAPER) then {
		(FOLDMAP displayCtrl NIGHTMAP) ctrlAddEventHandler ["Draw", "[] call tao_foldmap_drawUpdate"];
	};
};

// ----------------------------------------------------------------------------
// Move the map to its displayed position in time. 
// [time] call tao_foldmap_fnc_moveMapOnscreen;
// ----------------------------------------------------------------------------
tao_foldmap_fnc_moveMapOnscreen = {
	_t = _this select 0;
	(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlSetPosition [MAP_XPOS, MAP_YPOS];
	(FOLDMAP displayCtrl BACKGROUND) ctrlSetPosition [BACK_XPOS, BACK_YPOS];
	(FOLDMAP displayCtrl STATUSBAR) ctrlSetPosition [MAP_XPOS, MAP_YPOS - STATUS_YOFFSET];
	(FOLDMAP displayCtrl STATUSRIGHT) ctrlSetPosition [MAP_XPOS, MAP_YPOS - STATUSTEXT_YOFFSET];
	(FOLDMAP displayCtrl STATUSLEFT) ctrlSetPosition [MAP_XPOS, MAP_YPOS - STATUSTEXT_YOFFSET];

	(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlCommit _t;
	(FOLDMAP displayCtrl BACKGROUND) ctrlCommit _t;
	(FOLDMAP displayCtrl STATUSBAR) ctrlCommit _t;
	(FOLDMAP displayCtrl STATUSRIGHT) ctrlCommit _t;
	(FOLDMAP displayCtrl STATUSLEFT) ctrlCommit _t;
};

// ----------------------------------------------------------------------------
// Move the map off screen in time.
// [time] call tao_foldmap_fnc_moveMapOffscreen;
// ----------------------------------------------------------------------------
tao_foldmap_fnc_moveMapOffscreen = {
	_t = _this select 0;
	(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlSetPosition [MAP_XPOS, safezoneH - (BACK_YPOS - MAP_YPOS)];
	(FOLDMAP displayCtrl BACKGROUND) ctrlSetPosition [BACK_XPOS, safezoneH];
	(FOLDMAP displayCtrl STATUSBAR) ctrlSetPosition [MAP_XPOS, safezoneH - (BACK_YPOS - MAP_YPOS) - STATUS_YOFFSET];
	(FOLDMAP displayCtrl STATUSRIGHT) ctrlSetPosition [MAP_XPOS, safezoneH - (BACK_YPOS - MAP_YPOS) - STATUSTEXT_YOFFSET];
	(FOLDMAP displayCtrl STATUSLEFT) ctrlSetPosition [MAP_XPOS, safezoneH - (BACK_YPOS - MAP_YPOS) - STATUSTEXT_YOFFSET];

	(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlCommit _t;
	(FOLDMAP displayCtrl BACKGROUND) ctrlCommit _t;
	(FOLDMAP displayCtrl STATUSBAR) ctrlCommit _t;
	(FOLDMAP displayCtrl STATUSRIGHT) ctrlCommit _t;
	(FOLDMAP displayCtrl STATUSLEFT) ctrlCommit _t;
};

// ----------------------------------------------------------------------------
// Opens foldmap and monitors it until receiving a signal to close (tao_foldmap_doShow == false).
// ----------------------------------------------------------------------------
tao_foldmap_fnc_openFoldmap = {
	// Exit without effect if map is already open.
	if (tao_foldmap_isOpen) exitWith {};

	// Exit if in an invalid state for foldmap to open.
	if (!(cameraView in ["INTERNAL","EXTERNAL"]) || {!alive player} || {!isNil "BIS_DEBUG_CAM"}) exitWith {};

	// Initialize the dialog.
	tao_foldmap_isOpen = true;
	tao_foldmap_rscLayer cutRsc ["Tao_FoldMap","PLAIN",0];
	
	// Match background color to map darkening code if night.
	_darkFactor = (0.6 min (abs(sunOrMoon - 1)));
	if (_darkFactor != 0) then {
		_color = 1 - _darkFactor - 0.2454;
		(FOLDMAP displayCtrl BACKGROUND) ctrlSetTextColor [_color, _color, _color, 1];
	} else {
		(FOLDMAP displayCtrl BACKGROUND) ctrlSetTextColor [1, 1, 1, 1];
	};
	
	// Scroll up map and decorations.
	[SCROLLTIME] call tao_foldmap_fnc_moveMapOnscreen;
	
	// Monitor and update map until closed.
	tao_foldmap_doShow = true;

	// Initialize shaking values.
	_oldTime = time; _shakeTime = 0; _oldShakeTime = 0;

	// ------------
	while {tao_foldmap_doShow && {!visibleMap} && {cameraView in ["INTERNAL","EXTERNAL"]} && {alive player}} do {
		// Update the time and grid on the tablet status bar.
		if (!TAO_FOLDMAP_PAPER) then {
			_grid = format ["GRID %1", mapGridPosition player];
			(FOLDMAP displayCtrl STATUSLEFT) ctrlSetText _grid;

			_min = date select 4;
			if (_min < 10) then {
				_min = format ["0%1", _min];
			};
			_date = format ["%1/%2/%3  %4:%5  ||||||", date select 0, date select 1, date select 2, date select 3, _min];
			(FOLDMAP displayCtrl STATUSRIGHT) ctrlSetText _date;
		};

		if (TAO_FOLDMAP_ENABLESHAKE && {ctrlCommitted (FOLDMAP displayCtrl BACKGROUND)}) then {
			// If the player is moving, shake the map back and forth a little.
			_v = (velocity player) call bis_fnc_magnitude;

			// On foot, running. 
			if (vehicle player == player && {_v > 2} && {time >= _oldTime + _oldShakeTime}) then {

				// Shake back and forth by flipping the value.
				if (isNil "tao_foldmap_shake") then {tao_foldmap_shake = false};
				tao_foldmap_shake = !tao_foldmap_shake;

				_shakeMod = 0;
				if (_v > 4.8) then {
					_shakeMod = (safeZoneW * 0.005); // More shake at higher v
				};
				_shakeX = 0;
				_shakeY = 0;
				if (tao_foldmap_shake) then {
					_shakeX = (safeZoneW * 0.0015);
					_shakeY = -(safeZoneH * 0.0002);
				} else {
					_shakeX = -(safeZoneW * 0.0014 + _shakeMod + random (safeZoneW * 0.002));
					_shakeY = (safeZoneH * 0.0016 + _shakeMod + random (safeZoneW * 0.002));
				};

				// Shake period is shorter at higher speeds.
				_shakeTime = 0.4;

				// Do shake.
				(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlSetPosition [MAP_XPOS + _shakeX, MAP_YPOS + _shakeY];
				(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlCommit _shakeTime;
				(FOLDMAP displayCtrl BACKGROUND) ctrlSetPosition [BACK_XPOS + _shakeX, BACK_YPOS + _shakeY];
				(FOLDMAP displayCtrl BACKGROUND) ctrlCommit _shakeTime;
				(FOLDMAP displayCtrl STATUSBAR) ctrlSetPosition [MAP_XPOS + _shakeX, MAP_YPOS - STATUS_YOFFSET + _shakeY];
				(FOLDMAP displayCtrl STATUSBAR) ctrlCommit _shakeTime;
				(FOLDMAP displayCtrl STATUSRIGHT) ctrlSetPosition [MAP_XPOS + _shakeX , MAP_YPOS - STATUSTEXT_YOFFSET + _shakeY];
				(FOLDMAP displayCtrl STATUSRIGHT) ctrlCommit _shakeTime;
				(FOLDMAP displayCtrl STATUSLEFT) ctrlSetPosition [MAP_XPOS + _shakeX, MAP_YPOS - STATUSTEXT_YOFFSET + _shakeY];
				(FOLDMAP displayCtrl STATUSLEFT) ctrlCommit _shakeTime;

				_oldTime = time;
				_oldShakeTime = _shakeTime;
			} else {
				// Restore map to neutral position.
				if ((ctrlPosition (FOLDMAP displayCtrl BACKGROUND)) select 0 != BACK_XPOS) then {
					[0.1] call tao_foldmap_fnc_moveMapOnscreen;
				};
			};
		};

		// Update the delta number for map paging updates if needed.
		if (tao_foldmap_needsScaleReset || {isNil "tao_foldmap_pageWidth"}) then {
			_mapWidth = (ctrlPosition (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive)) select 2;
			_mapHeight = (ctrlPosition (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive)) select 3;

			_upperLeftCornerPos = (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapScreenToWorld [MAP_XPOS, MAP_YPOS];
			_bottomRightCornerPos = (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapScreenToWorld [MAP_XPOS + _mapWidth, MAP_YPOS + _mapHeight];

			// Compute page width and height (in meters on the map) for paging.
			tao_foldmap_pageWidth = abs ((_upperLeftCornerPos select 0) - (_bottomRightCornerPos select 0));
			tao_foldmap_pageHeight = abs ((_upperLeftCornerPos select 1) - (_bottomRightCornerPos select 1));
		};
			
		// If the player has gotten off the page somehow, re-center the map.
		_wts = (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapWorldToScreen getPos player;
		_mapWidth = (ctrlPosition (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive)) select 2;
		_mapHeight = (ctrlPosition (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive)) select 3;
		_upperLeftCorner = [MAP_XPOS, MAP_YPOS];
		_lowerRightCorner = [MAP_XPOS + _mapWidth, MAP_YPOS + _mapHeight];
		
		_fudgeFactor = 0.2; // Prevents flickering along edges.

		if (_wts select 0 < (_upperLeftCorner select 0) - _fudgeFactor ||
		   {_wts select 1 < (_upperLeftCorner select 1) - _fudgeFactor} ||
		   {_wts select 0 > (_lowerRightCorner select 0) + _fudgeFactor} ||
		   {_wts select 1 > (_lowerRightCorner select 1) + _fudgeFactor}
		   ) 
		then {
			tao_foldmap_centerPos = getPos player;
			(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, [tao_foldmap_centerPos select 0, tao_foldmap_centerPos select 1, 0]];
			ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		};
		
		// Deltas between player pos and map center pos.
		_deltaX = (tao_foldmap_centerPos select 0) - (getPos player select 0);
		_deltaY = (tao_foldmap_centerPos select 1) - (getPos player select 1);

		// Prevent flickering along edges and ensure paging before too close.
		_pagingFudgeFactor = 80 * tao_foldmap_mapScale / tao_foldmap_baseScale;

		// Need to page left?
		if (_deltaX > tao_foldmap_pageWidth/2 - _pagingFudgeFactor) then {
			_oldX = tao_foldmap_centerPos select 0;
			_oldY = tao_foldmap_centerPos select 1;
			tao_foldmap_centerPos = [_oldX - tao_foldmap_pageWidth + _pagingFudgeFactor*2.2, _oldY];

			(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, tao_foldmap_centerPos];
			ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		};
		
		// Need to page right?
		if (_deltaX < -tao_foldmap_pageWidth/2 + _pagingFudgeFactor) then {
			_oldX = tao_foldmap_centerPos select 0;
			_oldY = tao_foldmap_centerPos select 1;
			tao_foldmap_centerPos = [_oldX + tao_foldmap_pageWidth - _pagingFudgeFactor*2.2, _oldY];

			(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, tao_foldmap_centerPos];
			ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		};

		// Need to page up?
		if (_deltaY < -tao_foldmap_pageHeight/2 + _pagingFudgeFactor) then {
			_oldX = tao_foldmap_centerPos select 0;
			_oldY = tao_foldmap_centerPos select 1;
			tao_foldmap_centerPos = [_oldX, _oldY + tao_foldmap_pageHeight - _pagingFudgeFactor*2.2];

			(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, tao_foldmap_centerPos];
			ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		};

		// Need to page down?
		if (_deltaY > tao_foldmap_pageHeight/2 - _pagingFudgeFactor) then {
			_oldX = tao_foldmap_centerPos select 0;
			_oldY = tao_foldmap_centerPos select 1;
			tao_foldmap_centerPos = [_oldX, _oldY - tao_foldmap_pageHeight + _pagingFudgeFactor*2.2];

			(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, tao_foldmap_centerPos];
			ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		};
		

		// Sleep a bit.
		sleep 0.2;
	};
	// ------------

	// Map is no longer showing.
	tao_foldmap_doShow = false;
	
	// Scroll the map off the screen.
	[SCROLLTIME] call tao_foldmap_fnc_moveMapOffscreen;

	waitUntil {sleep 0.1; ctrlCommitted (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive)};

	// Destroy the rsc.
	tao_foldmap_rscLayer cutText ["", "PLAIN"];

	// Map is now scrolled away and can be opened again.
	tao_foldmap_isOpen = false;
};

// ----------------------------------------------------------------------------
// onLoad function for the MoveMe dialog.
// ----------------------------------------------------------------------------
tao_foldmap_fnc_onLoadMovingDialog = {
	// Put the Moving Dialog right on top of the existing map.
	_width = (ctrlPosition (MOVEME displayCtrl 10)) select 2;
	_height = (ctrlPosition (MOVEME displayCtrl 10)) select 3;
	(MOVEME displayCtrl 10) ctrlSetPosition [MAP_XPOS, MAP_YPOS];
	(MOVEME displayCtrl 11) ctrlSetPosition [MAP_XPOS, MAP_YPOS];
	(MOVEME displayCtrl 12) ctrlSetPosition [MAP_XPOS + (_width / 4), MAP_YPOS + (_height / 8)];
	(MOVEME displayCtrl 10) ctrlCommit 0;
	(MOVEME displayCtrl 11) ctrlCommit 0;
	(MOVEME displayCtrl 12) ctrlCommit 0;
};

// ----------------------------------------------------------------------------
// Move the foldmap to the position of the moving dialog and save the result.
// ----------------------------------------------------------------------------
tao_foldmap_fnc_confirmMove = {
	_pos = ctrlPosition (MOVEME displayCtrl 10);
	_posX = _pos select 0;
	_posY = _pos select 1;

	MOVEME closeDisplay 0;

	// Make sure new positions are reasonable.
	if (_posX > safeZoneXAbs && _posY > safeZoneY && _posX < safeZoneWAbs && _posY < safeZoneH) then {
		// Commit positions and move map.
		tao_foldmap_mapPosX = _posX;
		tao_foldmap_mapPosY = _posY;
		[0.2] call tao_foldmap_fnc_moveMapOnscreen;

		if (!isNil "tao_configsys") then {
			// Save to config file.
			["Tao Folding Map", "MapPosX", _posX] call tao_configsys_fnc_writeKey;
			["Tao Folding Map", "MapPosY", _posY] call tao_configsys_fnc_writeKey;
		};
	} else {
		["Invalid position."] call cba_fnc_systemChat;
	};
};

// ----------------------------------------------------------------------------
// Process keybinds from config file. If config file binds are disabled, do 
// nothing.
// ----------------------------------------------------------------------------
tao_foldmap_fnc_processKeyConfig = {
	// Key config format is [dikCode, shift?, ctrl?, alt?]
	if (TAO_FOLDMAP_USECUSTOMKEYS) then {
		// User has asked us to use config keys, parse them into a keyHandler check expression
		tao_foldmap_keyOpen = [TAO_FOLDMAP_OPEN, TAO_FOLDMAP_OPEN_SHIFT, TAO_FOLDMAP_OPEN_CTRL, TAO_FOLDMAP_OPEN_ALT];
		tao_foldmap_keyCenter = [TAO_FOLDMAP_CENTER, TAO_FOLDMAP_CENTER_SHIFT, TAO_FOLDMAP_CENTER_CTRL, TAO_FOLDMAP_CENTER_ALT];
		tao_foldmap_keyZoomIn = [TAO_FOLDMAP_ZOOMIN, TAO_FOLDMAP_ZOOMIN_SHIFT, TAO_FOLDMAP_ZOOMIN_CTRL, TAO_FOLDMAP_ZOOMIN_ALT];
		tao_foldmap_keyZoomOut = [TAO_FOLDMAP_ZOOMOUT, TAO_FOLDMAP_ZOOMOUT_SHIFT, TAO_FOLDMAP_ZOOMOUT_CTRL, TAO_FOLDMAP_ZOOMOUT_ALT];
		tao_foldmap_keyNVMode = [TAO_FOLDMAP_NVMODE, TAO_FOLDMAP_NVMODE_SHIFT, TAO_FOLDMAP_NVMODE_CTRL, TAO_FOLDMAP_NVMODE_ALT];
		tao_foldmap_keyReposition = [TAO_FOLDMAP_REPOSITION, TAO_FOLDMAP_REPOSITION_SHIFT, TAO_FOLDMAP_REPOSITION_CTRL, TAO_FOLDMAP_REPOSITION_ALT];
	} else {
		// Default: Use modified actionKeys for all keybinds.
		tao_foldmap_keyOpen = [actionKeys "ShowMap" select 0, true, false, false];
		tao_foldmap_keyCenter = [actionKeys "ShowMap" select 0, true, true, false];
		tao_foldmap_keyZoomIn = [actionKeys "ZoomIn" select 0, true, true, false];
		tao_foldmap_keyZoomOut = [actionKeys "ZoomOut" select 0, true, true, false];
		tao_foldmap_keyNVMode = [actionKeys "NightVision" select 0, true, true, false];
		tao_foldmap_keyReposition = [actionKeys "ShowMap" select 0, true, true, true];
	};
};

// ----------------------------------------------------------------------------
// XNOR for SQF booleans.   [a, b] call tao_fnc_xnor;
// ----------------------------------------------------------------------------
tao_fnc_xnor = {
	// The last SQF XNOR built-in operator is in captivity.
	// The galaxy is at peace.
	_a = _this select 0;
	_b = _this select 1;

	_ret = true;
	if (_a) then {
		if (_b) then {
			_ret = true;
		} else {
			_ret = false;
		};
	} else {
		if (!_b) then {
			_ret = true;
		} else {
			_ret = false;
		};
	};

	_ret;
};

// ---------------------------------------------------------------------------- 
// Checks if a given key input [dikcode, shift, ctrl, alt] is equal to a key 
// config array (same format).
// [keyconfig array, dikcode, shift, ctrl, alt] call tao_foldmap_fnc_checkKey
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_checkKey = {
	// Exit immediately with false if TCS is available.
	if (tao_foldmap_usingTCS) exitWith {false};

	_keyConfig = _this select 0;
	_compareKeyConfig = _this select 1;

	_kcDikCode = _keyConfig select 0;
	_kcShift = _keyConfig select 1;
	_kcCtrl = _keyConfig select 2;
	_kcAlt = _keyConfig select 3;

	_dikCode = _compareKeyConfig select 0;
	_shift = _compareKeyConfig select 1;
	_ctrl = _compareKeyConfig select 2;
	_alt = _compareKeyConfig select 3;

	// Return true if all are equal, false if not.

	//_dikCode == _kcDikCode && _shift == _kcShift && _ctrl == _kcCtrl && _alt == _kcAlt;
	_dikCode == _kcDikCode && ([_shift, _kcShift] call tao_fnc_xnor) && ([_ctrl, _kcCtrl] call tao_fnc_xnor) && ([_alt, _kcAlt] call tao_fnc_xnor);
};

// ---------------------------------------------------------------------------- 
// Key handler for all map-related functions.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_handleKey = {
	private["_handled", "_display", "_ctrl", "_dikCode", "_shift", "_alt"];
	_display = _this select 0;
	_dikCode = _this select 1;
	_shift = _this select 2;
	_ctrl = _this select 3;
	_alt = _this select 4;
	  
	_handled = false;

	// If opening gear, close foldmap.
	if (_dikCode in (actionKeys "Gear")) then {
		tao_foldmap_doShow = false;
		_handled = false;
	};
	
	// Toggle.
	if ([tao_foldmap_keyOpen, [_dikCode, _shift, _ctrl, _alt]] call tao_foldmap_fnc_checkKey) then {
		_handled = [] call tao_foldmap_fnc_toggle;
	};
	
	// Refold.
	if ([tao_foldmap_keyCenter, [_dikCode, _shift, _ctrl, _alt]] call tao_foldmap_fnc_checkKey && tao_foldmap_isOpen) then {
		_handled = [] call tao_foldmap_fnc_refold;
	};

	// Center and zoom in.
	if ([tao_foldmap_keyZoomIn, [_dikCode, _shift, _ctrl, _alt]] call tao_foldmap_fnc_checkKey) then {
		_handled = [] call tao_foldmap_fnc_zoomIn;
	};
	
	// Center and zoom out.
	if ([tao_foldmap_keyZoomOut, [_dikCode, _shift, _ctrl, _alt]] call tao_foldmap_fnc_checkKey) then {

		_handled = [] call tao_foldmap_fnc_zoomOut;
	};

	// Toggle the map's nightvision view if available.
	if ([tao_foldmap_keyNVMode, [_dikCode, _shift, _ctrl, _alt]] call tao_foldmap_fnc_checkKey) then {
		_handled = [] call tao_foldmap_fnc_nvMode;
	};

	// Reposition the map.
	if ([tao_foldmap_keyReposition, [_dikCode, _shift, _ctrl, _alt]] call tao_foldmap_fnc_checkKey) then {
		_handled = [] call tao_foldmap_fnc_reposition;
	};
	
	_handled;
};

// ---------------------------------------------------------------------------- 
// Fired EH to close the foldmap.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_firedEH = {
	if ((_this select 0) == player) then {
		tao_foldmap_doShow = false;
	};
};

// ---------------------------------------------------------------------------- 
// Toggle the folding map open and closed.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_toggle = {
	_handled = false;

	if (!visibleMap && ("ItemMap" in assignedItems player)) then {	
		if (!tao_foldmap_isOpen) then {
			[] spawn tao_foldmap_fnc_openFoldmap;
		} else {
			tao_foldmap_doShow = false; // Ends the monitor loop. Map is not ready again until scroll away finishes.
		};

		_handled = true;
	};

	_handled;
};

// ---------------------------------------------------------------------------- 
// 'Refolds' the map to recenter it.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_refold = {
	_handled = false;

	if (tao_foldmap_isOpen) then {
		tao_foldmap_centerPos = getPos player;
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, [tao_foldmap_centerPos select 0, tao_foldmap_centerPos select 1, 0]];
		ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		_handled = true;
	};

	_handled;
};

// ---------------------------------------------------------------------------- 
// Center map and zoom in.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_zoomIn = {
	_handled = false;

	if (tao_foldmap_isOpen) then {
		if (tao_foldmap_mapscale / 2 > 0.005) then { // Don't allow excessive zoom
			tao_foldmap_centerPos = getPos player;
			tao_foldmap_mapScale = tao_foldmap_mapScale /2;
			(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, [tao_foldmap_centerPos select 0, tao_foldmap_centerPos select 1, 0]];
			ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
			tao_foldmap_needsScaleReset = true;
			_handled = true;
		};
	};
	_handled = true;

	_handled;
};

// ---------------------------------------------------------------------------- 
// Center map and zoom out.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_zoomOut = {
	_handled = false;

	if (tao_foldmap_isOpen) then {
		tao_foldmap_centerPos = getPos player;
		tao_foldmap_mapScale = tao_foldmap_mapScale * 2;
		if (tao_foldmap_mapScale > 1) then { 
			tao_foldmap_mapScale = 1;
		};

		(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, [tao_foldmap_centerPos select 0, tao_foldmap_centerPos select 1, 0]];
		ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);
		tao_foldmap_needsScaleReset = true;

		_handled = true;
	};

	_handled;
};

// ---------------------------------------------------------------------------- 
// Toggle the map's nightvision view (if using tablet map).
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_nvMode = {
	_handled = false;

	if (tao_foldmap_isOpen && !TAO_FOLDMAP_PAPER) then {
		// Change which map is in use
		tao_foldmap_isNightMap = !tao_foldmap_isNightMap;
		if (tao_foldmap_isNightMap) then {
			tao_foldmap_mapCtrlActive = NIGHTMAP;
			tao_foldmap_mapCtrlInactive = DAYMAP;
		} else {
			tao_foldmap_mapCtrlActive = DAYMAP;
			tao_foldmap_mapCtrlInactive = NIGHTMAP;
		};

		// Give new map the scale/centering properties of the old map.
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlMapAnimAdd [0, tao_foldmap_mapScale, [tao_foldmap_centerPos select 0, tao_foldmap_centerPos select 1, 0]];
		ctrlMapAnimCommit (FOLDMAP displayCtrl tao_foldmap_mapCtrlActive);

		// Show the new map.
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlSetPosition (ctrlPosition (FOLDMAP displayCtrl tao_foldmap_mapCtrlInactive));
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlCommit 0;
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlActive) ctrlShow true;

		// Hide the old map.
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlInactive) ctrlShow false;
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlInactive) ctrlSetPosition [MAP_XPOS, safezoneH];
		(FOLDMAP displayCtrl tao_foldmap_mapCtrlInactive) ctrlCommit 0;

		_handled = true;
	};

	_handled;
};

// ---------------------------------------------------------------------------- 
// Reposition the map.
// ---------------------------------------------------------------------------- 
tao_foldmap_fnc_reposition = {
	_handled = false;

	if (tao_foldmap_isOpen) then {
		MOVEME closeDisplay 0; // Close any other moving dialogs.

		createDialog "Tao_FoldMap_MovingDialog";
		_handled = true;
	};

	_handled;
};

/////////////////////////////////////////////////////////////////////////////////

// Read config file keys.
[] call tao_foldmap_fnc_processKeyConfig;

// Check if Tao Configuration System is available.
if (!isNil "tao_configsys") then {
	// Do not use config file key binds.
	tao_foldmap_usingTCS = true;

	// Register TCS keybinds (defaults are read from config file).
	["Tao Folding Map", "Toggle folding map", "tao_foldmap_fnc_toggle", tao_foldmap_keyOpen, false] call tao_configsys_fnc_registerKeyHandler;
	["Tao Folding Map", "Refold map", "tao_foldmap_fnc_refold", tao_foldmap_keyCenter, false] call tao_configsys_fnc_registerKeyHandler;
	["Tao Folding Map", "Zoom in", "tao_foldmap_fnc_zoomIn", tao_foldmap_keyZoomIn, false] call tao_configsys_fnc_registerKeyHandler;
	["Tao Folding Map", "Zoom out", "tao_foldmap_fnc_zoomOut", tao_foldmap_keyZoomOut, false] call tao_configsys_fnc_registerKeyHandler;
	["Tao Folding Map", "Night mode (tablet only)", "tao_foldmap_fnc_nvMode", tao_foldmap_keyNVMode, false] call tao_configsys_fnc_registerKeyHandler;
	["Tao Folding Map", "Reposition map", "tao_foldmap_fnc_reposition", tao_foldmap_keyReposition, false] call tao_configsys_fnc_registerKeyHandler;
};

// Add display key handler. This will only register binds if TCS is not available.
["KeyDown", "_this call tao_foldmap_fnc_handleKey"] call cba_fnc_addDisplayHandler;

/////////////////////////////////////////////////////////////////////////////////

tao_foldmap = true; // Init done.