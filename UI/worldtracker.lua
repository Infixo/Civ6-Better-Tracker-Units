print("Loading WorldTracker.lua from Better World Tracker Units version 1.0");
-- Copyright 2014-2019, Firaxis Games.

--	Hotloading note: The World Tracker button check now positions based on how many hooks are showing.  
--	You'll need to save "LaunchBar" to see the tracker button appear.

include("InstanceManager");
include("TechAndCivicSupport");
include("SupportFunctions");
include("GameCapabilities");

g_TrackedItems = {};		-- Populated by WorldTrackerItems_* scripts;
include("WorldTrackerItem_", true);

-- Include self contained additional tabs
g_ExtraIconData = {};
include("CivicsTreeIconLoader_", true);

-- check extensions, modes and mods ;)
local m_isHeroes:boolean     = GameCapabilities.HasCapability("CAPABILITY_HEROES"); -- Heroes & Legends Mode
local m_isApocalypse:boolean = GameCapabilities.HasCapability("CAPABILITY_MEGADISASTERS"); -- Apocalypse Mode
local m_isBES:boolean        = Modding.IsModActive("07D5DFAB-44CE-8F63-8344-93E427E9376E"); -- Better Espionage Screen for new spy icons
local m_isCQUI:boolean       = Modding.IsModActive("1d44b5e7-753e-405b-af24-5ee634ec8a01"); -- for new apostle icons
print("Apocalypse: ", (m_isApocalypse and "YES" or "no"));
print("Heroes    : ", (m_isHeroes and "YES" or "no"));
print("BES       : ", (m_isBES and "YES" or "no"));
print("CQUI      : ", (m_isCQUI and "YES" or "no"));


-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID					:string = "WorldTracker"; -- Must be unique (usually the same as the file name)
local CHAT_COLLAPSED_SIZE				:number = 118;
local CIVIC_RESEARCH_MIN_SIZE			:number = 96;
local MAX_BEFORE_TRUNC_TRACKER			:number = 180;
local MAX_BEFORE_TRUNC_CHECK			:number = 160;
local MAX_BEFORE_TRUNC_TITLE			:number = 225;
local LAUNCH_BAR_PADDING				:number = 50;
local STARTING_TRACKER_OPTIONS_OFFSET	:number = 75;
local WORLD_TRACKER_PANEL_WIDTH			:number = 300;
local MINIMAP_PADDING					:number = 40;

local UNITS_PANEL_MIN_HEIGHT			:number = 85;
--local UNITS_PANEL_PADDING				:number = 65;
local TOPBAR_PADDING					:number = 100;

local WORLD_TRACKER_TOP_PADDING			:number = 200;


-- ===========================================================================
--	GLOBALS
-- ===========================================================================
g_TrackedInstances	= {};				-- Any instances created as a result of g_trackedItems

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_hideAll					:boolean = false;
local m_hideChat				:boolean = false;
local m_hideCivics				:boolean = false;
local m_hideResearch			:boolean = false;
local m_hideUnitList			:boolean = true;

--local m_dropdownExpanded		:boolean = false; -- Infixo: remove dropdown
local m_unreadChatMsgs			:number  = 0;		-- number of chat messages unseen due to the chat panel being hidden.

local m_researchInstance		:table	 = {};		-- Single instance wired up for the currently being researched tech
local m_civicsInstance			:table	 = {};		-- Single instance wired up for the currently being researched civic
local m_unitListInstance		:table	 = {};

local m_unitEntryIM				:table	 = {};

local m_CachedModifiers			:table	 = {};

local m_currentResearchID		:number = -1;
local m_lastResearchCompletedID	:number = -1;
local m_currentCivicID			:number = -1;
local m_lastCivicCompletedID	:number = -1;
local m_minimapSize				:number = 199;
local m_isTrackerAlwaysCollapsed:boolean = false;	-- Once the launch bar extends past the width of the world tracker, we always show the collapsed version of the backing for the tracker element
local m_isDirty					:boolean = false;	-- Note: renamed from "refresh" which is a built in Forge mechanism; this is based on a gamecore event to check not frame update
local m_isMinimapCollapsed		:boolean = false;
local m_startingChatSize		:number = 0;

local m_unitSearchString		:string = "";
local m_remainingRoom			:number = 0;
local m_isUnitListSizeDirty		:boolean = false;
local m_isMinimapInitialized	:boolean = false;

--local m_uiCheckBoxes			:table = {Controls.ChatCheck, Controls.CivicsCheck, Controls.ResearchCheck, Controls.UnitCheck}; -- Infixo: not used
local m_isUnitListMilitary		:boolean = false;
local m_showTrader				:boolean = false;


-- debug routine - prints a table (no recursion)
function dshowtable(tTable:table)
	for k,v in pairs(tTable) do
		print(k, type(v), tostring(v));
	end
end

-- debug routine - prints a table, and tables inside recursively (up to 5 levels)
function dshowrectable(tTable:table, iLevel:number)
	local level:number = 0;
	if iLevel ~= nil then level = iLevel; end
	for k,v in pairs(tTable) do
		print(string.rep("---:",level), k, type(v), tostring(v));
		if type(v) == "table" and level < 5 then dshowrectable(v, level+1); end
	end
end


-- ===========================================================================
--	FUNCTIONS
-- ===========================================================================

-- ===========================================================================
--	The following are a accessors for Expansions/MODs so they can obtain status
--	of the common panels but don't have access to toggling them.
-- ===========================================================================
function IsChatHidden()			return m_hideChat;		end
function IsResearchHidden()		return m_hideResearch;	end
function IsCivicsHidden()		return m_hideCivics;	end
function IsUnitListHidden()		return m_hideUnitList;	end

-- ===========================================================================
--	Checks all panels, static and dynamic as to whether or not they are hidden.
--	Returns true if they are. 
-- ===========================================================================
function IsAllPanelsHidden()
	local isHide	:boolean = false;
	local uiChildren:table = Controls.PanelStack:GetChildren();
	for i,uiChild in ipairs(uiChildren) do			
		if uiChild:IsVisible() then
			return false;
		end
	end
	return true;
end

-- ===========================================================================
function RealizeEmptyMessage()	
	-- First a quick check if all native panels are hidden.
	if m_hideChat and m_hideCivics and m_hideResearch and m_hideUnitList then		
		local isAllPanelsHidden:boolean = IsAllPanelsHidden();	-- more expensive iteration
		Controls.EmptyPanel:SetHide( isAllPanelsHidden==false );	
	else
		Controls.EmptyPanel:SetHide(true);
	end
end

-- ===========================================================================
function ToggleAll(hideAll:boolean)

	-- Do nothing if value didn't change
	if m_hideAll == hideAll then return; end

	m_hideAll = hideAll;
	
	if(not hideAll) then
		Controls.PanelStack:SetHide(false);
		UI.PlaySound("Tech_Tray_Slide_Open");
	end

	Controls.ToggleAllButton:SetCheck(not m_hideAll);

	if ( not m_isTrackerAlwaysCollapsed) then
		Controls.TrackerHeading:SetHide(hideAll);
		Controls.TrackerHeadingCollapsed:SetHide(not hideAll);
	else
		Controls.TrackerHeading:SetHide(true);
		Controls.TrackerHeadingCollapsed:SetHide(false);
	end

	if( hideAll ) then
		UI.PlaySound("Tech_Tray_Slide_Closed");
	end

	Controls.WorldTrackerAlpha:Reverse();
	Controls.WorldTrackerSlide:Reverse();
	CheckUnreadChatMessageCount();

	LuaEvents.WorldTracker_ToggleCivicPanel(m_hideCivics or m_hideAll);
	LuaEvents.WorldTracker_ToggleResearchPanel(m_hideResearch or m_hideAll);
end

-- ===========================================================================
function OnWorldTrackerAnimationFinished()
	if(m_hideAll) then
		Controls.PanelStack:SetHide(true);
	end
end

-- ===========================================================================
-- When the launch bar is resized, make sure to adjust the world tracker 
-- button position/size to accommodate it
-- ===========================================================================
function OnLaunchBarResized( buttonStackSize: number)
	Controls.TrackerHeading:SetSizeX(buttonStackSize + LAUNCH_BAR_PADDING);
	Controls.TrackerHeadingCollapsed:SetSizeX(buttonStackSize + LAUNCH_BAR_PADDING);
	if( buttonStackSize > WORLD_TRACKER_PANEL_WIDTH - LAUNCH_BAR_PADDING) then
		m_isTrackerAlwaysCollapsed = true;
		Controls.TrackerHeading:SetHide(true);
		Controls.TrackerHeadingCollapsed:SetHide(false);
	else
		m_isTrackerAlwaysCollapsed = false;
		Controls.TrackerHeading:SetHide(m_hideAll);
		Controls.TrackerHeadingCollapsed:SetHide(not m_hideAll);
	end
	Controls.ToggleAllButton:SetOffsetX(buttonStackSize - 7);
end

-- ===========================================================================
function RealizeStack()
	if(m_hideAll) then ToggleAll(true); end
end

-- ===========================================================================
function UpdateResearchPanel( isHideResearch:boolean )

	-- If not an actual player (observer, tuner, etc...) then we're done here...
	local ePlayer		:number = Game.GetLocalPlayer();
	if (ePlayer == PlayerTypes.NONE or ePlayer == PlayerTypes.OBSERVER) then
		return;
	end
	local pPlayerConfig : table = PlayerConfigurations[ePlayer];

	if not HasCapability("CAPABILITY_TECH_CHOOSER") or not pPlayerConfig:IsAlive() then
		isHideResearch = true;
		Controls.ResearchButton:SetHide(true);
	end
	if isHideResearch ~= nil then
		m_hideResearch = isHideResearch;		
	end
	
	m_researchInstance.MainPanel:SetHide( m_hideResearch );
	LuaEvents.WorldTracker_ToggleResearchPanel(m_hideResearch or m_hideAll);
	RealizeEmptyMessage();
	RealizeStack();

	-- Set the technology to show (or -1 if none)...
	local iTech			:number = m_currentResearchID;
	if m_currentResearchID == -1 then 
		iTech = m_lastResearchCompletedID; 
	end
	local pPlayer		:table  = Players[ePlayer];
	local pPlayerTechs	:table	= pPlayer:GetTechs();
	local kTech			:table	= (iTech ~= -1) and GameInfo.Technologies[ iTech ] or nil;
	local kResearchData :table = GetResearchData( ePlayer, pPlayerTechs, kTech );
	if iTech ~= -1 then
		if m_currentResearchID == iTech then
			kResearchData.IsCurrent = true;
		elseif m_lastResearchCompletedID == iTech then
			kResearchData.IsLastCompleted = true;
		end
	end
	
	RealizeCurrentResearch( ePlayer, kResearchData, m_researchInstance);
	
	-- No tech started (or finished)
	if kResearchData == nil then
		m_researchInstance.TitleButton:SetHide( false );
		TruncateStringWithTooltip(m_researchInstance.TitleButton, MAX_BEFORE_TRUNC_TITLE, Locale.ToUpper(Locale.Lookup("LOC_WORLD_TRACKER_CHOOSE_RESEARCH")) );
	end
end

-- ===========================================================================
function UpdateCivicsPanel(hideCivics:boolean)

	-- If not an actual player (observer, tuner, etc...) then we're done here...
	local ePlayer		:number = Game.GetLocalPlayer();
	if (ePlayer == PlayerTypes.NONE or ePlayer == PlayerTypes.OBSERVER) then
		return;
	end
	local pPlayerConfig : table = PlayerConfigurations[ePlayer];

	if not HasCapability("CAPABILITY_CIVICS_CHOOSER") or (localPlayerID ~= PlayerTypes.NONE and not pPlayerConfig:IsAlive()) then
		hideCivics = true;
		Controls.CivicsButton:SetHide(true);
	end
	if hideCivics ~= nil then
		m_hideCivics = hideCivics;		
	end

	m_civicsInstance.MainPanel:SetHide(m_hideCivics); 
	LuaEvents.WorldTracker_ToggleCivicPanel(m_hideCivics or m_hideAll);
	RealizeEmptyMessage();
	RealizeStack();

	-- Set the civic to show (or -1 if none)...
	local iCivic :number = m_currentCivicID;
	if iCivic == -1 then 
		iCivic = m_lastCivicCompletedID; 
	end	
	local pPlayer		:table  = Players[ePlayer];
	local pPlayerCulture:table	= pPlayer:GetCulture();
	local kCivic		:table	= (iCivic ~= -1) and GameInfo.Civics[ iCivic ] or nil;
	local kCivicData	:table = GetCivicData( ePlayer, pPlayerCulture, kCivic );
	if iCivic ~= -1 then
		if m_currentCivicID == iCivic then
			kCivicData.IsCurrent = true;
		elseif m_lastCivicCompletedID == iCivic then
			kCivicData.IsLastCompleted = true;
		end
	end

	for _,iconData in pairs(g_ExtraIconData) do
		iconData:Reset();
	end
	RealizeCurrentCivic( ePlayer, kCivicData, m_civicsInstance, m_CachedModifiers );

	-- No civic started (or finished)
	if kCivicData == nil then
		m_civicsInstance.TitleButton:SetHide( false );
		TruncateStringWithTooltip(m_civicsInstance.TitleButton, MAX_BEFORE_TRUNC_TITLE, Locale.ToUpper(Locale.Lookup("LOC_WORLD_TRACKER_CHOOSE_CIVIC")) );
	else
		TruncateStringWithTooltip(m_civicsInstance.TitleButton, MAX_BEFORE_TRUNC_TITLE, m_civicsInstance.TitleButton:GetText() );
	end
end

-- ===========================================================================
function UpdateUnitListPanel(hideUnitList:boolean)

	-- If not an actual player (observer, tuner, etc...) then we're done here...
	local ePlayer		:number = Game.GetLocalPlayer();
	if (ePlayer == PlayerTypes.NONE or ePlayer == PlayerTypes.OBSERVER) then
		return;
	end
	local pPlayerConfig : table = PlayerConfigurations[ePlayer];

	if not HasCapability("CAPABILITY_UNIT_LIST") or (ePlayer ~= PlayerTypes.NONE and not pPlayerConfig:IsAlive()) then
		hideUnitList = true;
		m_unitListInstance.UnitListMainPanel:SetHide(true);
		return;
	end

	if(hideUnitList ~= nil) then m_hideUnitList = hideUnitList; end
	
	m_unitEntryIM:ResetInstances();

	m_unitListInstance.UnitListMainPanel:SetHide(m_hideUnitList); 

	local pPlayer : table = Players[ePlayer];
	local pPlayerUnits : table = pPlayer:GetUnits();
	local numUnits : number = pPlayerUnits:GetCount();

	if(pPlayerUnits:GetCount() > 0)then
		m_unitListInstance.NoUnitsLabel:SetHide(true);
		m_unitListInstance.UnitsSearchBox:LocalizeAndSetToolTip("LOC_WORLDTRACKER_UNITS_SEARCH_TT");

		local militaryUnits : table = {};
		local civilianUnits : table = {};

		for i, pUnit in pPlayerUnits:Members() do
			if((m_unitSearchString ~= "" and string.find(Locale.ToUpper(pUnit:GetName()), m_unitSearchString) ~= nil) or m_unitSearchString == "")then
				local pUnitInfo : table = GameInfo.Units[pUnit:GetUnitType()];
				-- Infixo: just split into 2 categories
				-- Infixo: a better way to group the units is to use FormationClass
				if pUnitInfo.FormationClass ~= "FORMATION_CLASS_CIVILIAN" then
					table.insert(militaryUnits, pUnit);
				elseif m_showTrader or not pUnitInfo.MakeTradeRoute then
					table.insert(civilianUnits, pUnit);
				end
			end
		end

		-- Alphabetize groups
		local sortFunc = function(a, b) 
			-- Infixo: sort by an actual name (asc) and experience (desc)
			local aName:string = Locale.Lookup(a:GetName());
			local bName:string = Locale.Lookup(b:GetName());
			if aName == bName then
				return a:GetExperience():GetExperiencePoints() > b:GetExperience():GetExperiencePoints();
			end
			return aName < bName;
		end

		-- Add units by sorted groups
		if m_isUnitListMilitary then
			table.sort(militaryUnits, sortFunc);
			for _, pUnit in ipairs(militaryUnits) do AddUnitToUnitList( pUnit ); end
		else -- civilian
			table.sort(civilianUnits, sortFunc);
			for _, pUnit in ipairs(civilianUnits) do AddUnitToUnitList( pUnit ); end
		end
	else
		m_unitListInstance.TraderCheck:SetHide(true);
		m_unitListInstance.NoUnitsLabel:SetHide(false);
		m_unitListInstance.UnitsSearchBox:SetDisabled(true);
		m_unitListInstance.UnitsSearchBox:LocalizeAndSetToolTip("LOC_WORLDTRACKER_NO_UNITS");
	end

	RealizeEmptyMessage();
	RealizeStack();
end

-- ===========================================================================
function StartUnitListSizeUpdate()
	m_isUnitListSizeDirty = true;
	ContextPtr:RequestRefresh();
end

-- ===========================================================================
-- WorldTrackerVerticalContainer:
--   = ResearchInstance
--   = CivicInstance
--   = .OtherContainer - emergencies, multiple * 144 per one
--   = UnitListInstance
--   = .ChatPanelContainer
--   = .TutorialGoals

function UpdateUnitListSize()
	if(not m_isMinimapInitialized)then
		UpdateWorldTrackerSize();
	end
	if(not m_hideUnitList)then
		m_isUnitListSizeDirty = false;
	end
end

-- ===========================================================================
function UpdateWorldTrackerSize()
	local uiMinimap : table  = ContextPtr:LookUpControl("/InGame/MinimapPanel/MinimapContainer");
	if(uiMinimap ~= nil)then
		local _, screenHeight : number = UIManager:GetScreenSizeVal();
		if(m_isMinimapCollapsed)then
			Controls.WorldTrackerVerticalContainer:SetSizeY(screenHeight - WORLD_TRACKER_TOP_PADDING);
		else
			Controls.WorldTrackerVerticalContainer:SetSizeY(screenHeight - uiMinimap:GetSizeY() - WORLD_TRACKER_TOP_PADDING);
		end
		m_isMinimapInitialized = true;
	else
		m_isMinimapInitialized = false;
	end

	if(not m_unitListInstance.UnitListMainPanel:IsHidden())then
		StartUnitListSizeUpdate()
	end
end



-- ===========================================================================
-- INFIXO: BOLBAS' CODE, USED WITH PERMISSION
-- Refactoring (new icons, simplifications) by Infixo

local BQUI_PreviousUnitEntrySum = nil;    -- bolbas (Middle Click on Unit List entries added - shows total number of units of that type)
local BQUI_UnitDifferentReligions:number = 0;    -- bolbas (Religion icons added)

local BQUI_ApostlePromotionIcons:table = {
	PROMOTION_CHAPLAIN =			{Icon = "ICON_UNIT_MEDIC",			Size = 16,	OffsetY = -1},
	PROMOTION_DEBATER =				{Icon = "ICON_STRENGTH",			Size = 14,	OffsetY = -1},
	PROMOTION_HEATHEN_CONVERSION =	{Icon = "ICON_NOTIFICATION_NEW_BARBARIAN_CAMP",	Size = 18,	OffsetY = -1},
	PROMOTION_INDULGENCE_VENDOR =	{Icon = "ICON_MAP_PIN_CIRCLE",		Size = 12,	OffsetY = -1},
	PROMOTION_PROSELYTIZER =		{Icon = "ICON_UNIT_INQUISITOR",		Size = 17,	OffsetY = 0},
	PROMOTION_TRANSLATOR =			{Icon = "ICON_QUEUE",				Size = 18,	OffsetY = -1},
	PROMOTION_MARTYR =				{Icon = "ICON_GREATWORKOBJECT_RELIC",	Size = 12,	OffsetY = 0},
	PROMOTION_ORATOR =				{Icon = "ICON_STATS_SPREADCHARGES",	Size = 16,	OffsetY = 0},
	PROMOTION_PILGRIM =				{Icon = "ICON_STATS_TERRAIN",		Size = 16,	OffsetY = 0},
};

-- Infixo: icons update to be in sync with CQUI
local CQUI_ApostlePromotionIcons:table = {
	PROMOTION_CHAPLAIN 			 = {Icon = "Religion",		  Size = 20, OffsetY = 0},-- medic
	PROMOTION_DEBATER 			 = {Icon = "Ability",		  Size = 20, OffsetY = 0},-- +20 combat
	PROMOTION_HEATHEN_CONVERSION = {Icon = "Barbarian",		  Size = 20, OffsetY = 0},-- barbs
	PROMOTION_INDULGENCE_VENDOR  = {Icon = "Gold",		 	  Size = 18, OffsetY = 0},-- gold
	PROMOTION_PROSELYTIZER 		 = {Icon = "Damaged",		  Size = 20, OffsetY = 0},-- 75% reduce
	PROMOTION_TRANSLATOR 		 = {Icon = "Bombard",		  Size = 20, OffsetY = 0},-- 3x pressure
	PROMOTION_MARTYR 			 = {Icon = "GreatWork_Relic", Size = 18, OffsetY = 0},-- relic
	PROMOTION_ORATOR 			 = {Icon = "ICON_STATS_SPREADCHARGES", Size = 16, OffsetY = 0}, -- adds charges
	PROMOTION_PILGRIM 			 = {Icon = "ICON_STATS_TERRAIN",	   Size = 16, OffsetY = 0}, -- adds charges
};

local BQUI_RockBandPromotionIcons:table = {
	PROMOTION_ALBUM_COVER_ART =	{Icon = "ICON_STAT_WONDERS",		Size = 16,	OffsetY = -1},
	PROMOTION_ARENA_ROCK =		{Icon = "ICON_AMENITIES",			Size = 17,	OffsetY = 0},
	PROMOTION_GLAM_ROCK =		{Icon = "ICON_UNIT_GREAT_WRITER",	Size = 16,	OffsetY = 0},
	PROMOTION_GOES_TO =			{Icon = "PressureRight",			Size = 16,	OffsetY = 0},
	PROMOTION_INDIE =			{Icon = "ICON_STAT_CULTURAL_FLAG",	Size = 15,	OffsetY = 0},
	PROMOTION_MUSIC_FESTIVAL =	{Icon = "ICON_STATS_TERRAIN",		Size = 16,	OffsetY = 0},
	PROMOTION_POP =				{Icon = "ICON_MAP_PIN_CIRCLE",		Size = 12,	OffsetY = -1},
	PROMOTION_REGGAE_ROCK =		{Icon = "ICON_AMENITIES",			Size = 17,	OffsetY = 0},    -- Infixo: fixed
	PROMOTION_RELIGIOUS_ROCK =	{Icon = "ICON_RELIGION",			Size = 18,	OffsetY = 0},
	PROMOTION_ROADIES =			{Icon = "ICON_MOVES",				Size = 14,	OffsetY = 0},
	PROMOTION_SPACE_ROCK =		{Icon = "ICON_UNIT_GREAT_SCIENTIST",Size = 15,	OffsetY = 0},
	PROMOTION_SURF_ROCK =		{Icon = "ICON_UNIT_GREAT_ADMIRAL",	Size = 15,	OffsetY = 0},
};

-- Infixo: updated icons to better reflect description (e.g. district icons used)
local CQUI_RockBandPromotionIcons:table = {
	PROMOTION_ALBUM_COVER_ART =	{Icon = "ICON_STAT_WONDERS",    Size = 16, OffsetY = 0},
	PROMOTION_ARENA_ROCK =		{Icon = "ICON_AMENITIES",		Size = 16, OffsetY = 0},
	PROMOTION_GLAM_ROCK =		{Icon = "ICON_DISTRICT_THEATER",Size = 16, OffsetY = 0},
	PROMOTION_GOES_TO =			{Icon = "PressureRight",		Size = 18, OffsetY = 0},
	PROMOTION_INDIE =			{Icon = "PressureDown",			Size = 22, OffsetY = 0},
	PROMOTION_MUSIC_FESTIVAL =	{Icon = "ICON_STATS_TERRAIN",	Size = 16, OffsetY = 0},
	PROMOTION_POP =				{Icon = "Gold",					Size = 20, OffsetY = 0},
	PROMOTION_REGGAE_ROCK =		{Icon = "ICON_DISTRICT_WATER_ENTERTAINMENT_COMPLEX", Size = 16, OffsetY = 0}, -- Infixo: fixed
	PROMOTION_RELIGIOUS_ROCK =	{Icon = "ICON_RELIGION",		Size = 20, OffsetY = 0},
	PROMOTION_ROADIES =			{Icon = "ICON_MOVES",			Size = 14, OffsetY = 0},
	PROMOTION_SPACE_ROCK =		{Icon = "ICON_DISTRICT_CAMPUS", Size = 16, OffsetY = 0},
	PROMOTION_SURF_ROCK =		{Icon = "ICON_DISTRICT_HARBOR", Size = 16, OffsetY = 0},
};

local BQUI_SpyPromotionIcons:table = {
	PROMOTION_SPY_ACE_DRIVER =		{Icon = "ICON_NOTIFICATION_SPY_CHOOSE_ESCAPE_ROUTE",	Size = 18,	OffsetY = 0},
	PROMOTION_SPY_CAT_BURGLAR =		{Icon = "ICON_NOTIFICATION_SPY_HEIST_GREAT_WORK",		Size = 16,	OffsetY = -1},
	PROMOTION_SPY_CON_ARTIST =		{Icon = "ICON_NOTIFICATION_SPY_SIPHONED_FUNDS",			Size = 18,	OffsetY = -1},
	PROMOTION_SPY_DEMOLITIONS =		{Icon = "ICON_NOTIFICATION_SPY_SABOTAGED_PRODUCTION",	Size = 16,	OffsetY = -1},
	PROMOTION_SPY_DISGUISE =		{Icon = "ICON_UNITCOMMAND_AIRLIFT",						Size = 17,	OffsetY = -1},
	PROMOTION_SPY_GUERILLA_LEADER =	{Icon = "ICON_NOTIFICATION_SPY_RECRUIT_PARTISANS",		Size = 16,	OffsetY = -1},
	PROMOTION_SPY_LINGUIST =		{Icon = "Turn",											Size = 18,	OffsetY = -1},
	PROMOTION_SPY_QUARTERMASTER =	{Icon = "ICON_UNITOPERATION_FOUND_CITY",				Size = 16,	OffsetY = -1},
	PROMOTION_SPY_ROCKET_SCIENTIST ={Icon = "ICON_NOTIFICATION_SPY_DISRUPTED_ROCKETRY",		Size = 18,	OffsetY = 0},
	PROMOTION_SPY_SEDUCTION =		{Icon = "ICON_UNITOPERATION_SPY_COUNTERSPY_ACTION",		Size = 16,	OffsetY = -1},
	PROMOTION_SPY_TECHNOLOGIST =	{Icon = "ICON_NOTIFICATION_SPY_STOLE_TECH_BOOST",		Size = 16,	OffsetY = -1},
	PROMOTION_SPY_COVERT_ACTION =	{Icon = "ICON_STAT_CULTURAL_FLAG",						Size = 15,	OffsetY = 0},
	PROMOTION_SPY_LICENSE_TO_KILL =	{Icon = "ICON_NOTIFICATION_GOVERNOR_PROMOTION_AVAILABLE", Size = 16, OffsetY = -1},
	PROMOTION_SPY_SMEAR_CAMPAIGN =	{Icon = "ICON_NOTIFICATION_GIVE_INFLUENCE_TOKEN",		Size = 16,	OffsetY = -1},
	PROMOTION_SPY_POLYGRAPH =		{Icon = "ICON_UNITOPERATION_SPY_TRAVEL_NEW_CITY",		Size = 16,	OffsetY = -2},
	PROMOTION_SPY_SATCHEL_CHARGES =	{Icon = "ICON_NOTIFICATION_SPY_BREACH_DAM",				Size = 16,	OffsetY = -1},
	PROMOTION_SPY_SURVEILLANCE =	{Icon = "ICON_STAT_DISTRICTS",							Size = 16,	OffsetY = -1},
};

local BQUI_SoothsayerPromotionIcons:table = {
	PROMOTION_SOOTHSAYER_MESSENGER =   {Icon = "ICON_MOVES",				  Size = 14, OffsetY = 0},
	PROMOTION_SOOTHSAYER_INQUISITOR =  {Icon = "ICON_NOTIFICATION_SPY_GROUP", Size = 14, OffsetY = -1},
	PROMOTION_SOOTHSAYER_ZEALOT =	   {Icon = "ICON_MAP_PIN_CHARGES",		  Size = 14, OffsetY = -1},
	PROMOTION_SOOTHSAYER_INCANTATION = {Icon = "ICON_STRENGTH",				  Size = 14, OffsetY = -1},
	PROMOTION_SOOTHSAYER_PLAGUE_BEARER = {Icon = "ICON_UNITOPERATION_SPY_TRAVEL_NEW_CITY", Size = 16, OffsetY = -2},
};

local BQUI_GreatPersonEras:table = {
	ERA_CLASSICAL =   {Icon_1 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_CLASSICAL",   Size_1 = 13, OffsetY_1 = -1, Icon_2 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_MEDIEVAL",    Size_2 = 14, OffsetY_2 = -1},
	ERA_MEDIEVAL =    {Icon_1 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_MEDIEVAL",    Size_1 = 14, OffsetY_1 = -1, Icon_2 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_RENAISSANCE", Size_2 = 14, OffsetY_2 = -1},
	ERA_RENAISSANCE = {Icon_1 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_RENAISSANCE", Size_1 = 14, OffsetY_1 = -1, Icon_2 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_INDUSTRIAL",  Size_2 = 14, OffsetY_2 = -1},
	ERA_INDUSTRIAL =  {Icon_1 = "ICON_GREATWORKOBJECT_ARTIFACT_ERA_INDUSTRIAL",  Size_1 = 14, OffsetY_1 = -1, Icon_2 = "ICON_IMPROVEMENT_OIL_WELL",                     Size_2 = 18, OffsetY_2 = 0},
	ERA_MODERN =      {Icon_1 = "ICON_IMPROVEMENT_OIL_WELL",                     Size_1 = 18, OffsetY_1 = 0,  Icon_2 = "ICON_PROJECT_BUILD_NUCLEAR_DEVICE",             Size_2 = 18, OffsetY_2 = 0},
	ERA_ATOMIC =      {Icon_1 = "ICON_PROJECT_BUILD_NUCLEAR_DEVICE",             Size_1 = 18, OffsetY_1 = 0,  Icon_2 = "ICON_PROJECT_BUILD_THERMONUCLEAR_DEVICE",       Size_2 = 18, OffsetY_2 = 0},
	ERA_INFORMATION = {Icon_1 = "ICON_PROJECT_BUILD_THERMONUCLEAR_DEVICE",       Size_1 = 18, OffsetY_1 = 0},
};

local BQUI_PromotionTreeCheck:table = {
	["11"] = true,
	["21"] = true,
	["31"] = true,
	["13"] = true,
	["23"] = true,
	["33"] = true,
	["42"] = true,
};

local BQUI_UnitAbilitiesIcons:table = {
	-- XP Abilities
	-- +25% XP
	ABILITY_BARRACKS_TRAINED_UNIT_XP =		1,
	ABILITY_STABLE_TRAINED_UNIT_XP =		2,
	ABILITY_BASILIKOI_TRAINED_UNIT_XP =		3,
	ABILITY_ORDU_TRAINED_UNIT_XP =			4,
	ABILITY_LIGHTHOUSE_TRAINED_UNIT_XP =	5,
	ABILITY_HANGAR_TRAINED_AIRCRAFT_XP =	6,
	ABILITY_ARMORY_TRAINED_UNIT_XP =		7,
	ABILITY_SHIPYARD_TRAINED_UNIT_XP =		8,
	ABILITY_MILITARY_ACADEMY_TRAINED_UNIT_XP =		9,
	ABILITY_SEAPORT_TRAINED_UNIT_XP =		10,
	ABILITY_TOQUI_XP_FROM_GOVERNOR =		11,
	ABILITY_TIMUR_BONUS_EXPERIENCE =		12,
	-- +50% XP
	ABILITY_AIRPORT_TRAINED_AIRCRAFT_XP =	13,
	ABILITY_LASKARINA_BOUBOULINA_BONUS_EXPERIENCE =	14,
	-- +75% XP
	ABILITY_JOHN_MONASH_BONUS_EXPERIENCE =	15,
	-- +100% XP
	ABILITY_SERGEY_GORSHKOV_BONUS_EXPERIENCE =    16,
	ABILITY_VIJAYA_WIMALARATNE_BONUS_EXPERIENCE = 17,
	-- > +100% XP
	ABILITY_CLANCY_FERNANDO_BONUS_EXPERIENCE = 18,
	-- Strength Abilities
	ABILITY_ALPINE_TRAINING =				 19,
	ABILITY_SPEAR_OF_FIONN =				 20,
	ABILITY_COMMANDANTE_CAVALRY_BUFF =		 21,
	ABILITY_COMMANDANTE_MELEE_ANTICAV_BUFF = 22,
	ABILITY_COMMANDANTE_UNIT_STRENGTH_BUFF = 23,
	ABILITY_COMMANDANTE_UNIT_STR_VS_DISTRICTS =	24,
	-- GP Abilities
	ABILITY_GREAT_ADMIRAL_STRENGTH =	25,
	ABILITY_GREAT_GENERAL_STRENGTH =	26,
	-- Comandante Abilities
	ABILITY_COMANDANTE_AOE_STRENGTH =	27,
};


-- bolbas (Religion icons added)
function BQUI_SetReligionIconUnitList(pUnit, unitEntry_ReligionIcon)
	local BQUI_religionID = pUnit:GetReligionType();
	if BQUI_religionID > 0 then
		unitEntry_ReligionIcon:SetShow(true);
		local religion:table = GameInfo.Religions[BQUI_religionID];
		local ReligionType = religion.ReligionType;
		--if BQUI_ReligionsStandard[ReligionType] == true then    -- bolbas (Fixed Standard Religions Icons when set their Size to 18)
			--unitEntry_ReligionIcon:SetIcon("BQUI_BUL_ICON_" .. ReligionType);
		--else
			unitEntry_ReligionIcon:SetSizeVal(22,22);
			unitEntry_ReligionIcon:SetIcon("ICON_" .. ReligionType);
			unitEntry_ReligionIcon:SetSizeVal(18,18);
		--end
		if BQUI_UnitDifferentReligions ~= -1 then
			if BQUI_UnitDifferentReligions == 0 then
				BQUI_UnitDifferentReligions = BQUI_religionID;
			elseif BQUI_UnitDifferentReligions ~= BQUI_religionID then
				BQUI_UnitDifferentReligions = -1;
			end
			--table.insert(BQUI_ReligionIconEntry, unitEntry_ReligionIcon);    -- bolbas: A table to hide Religion Icons if all player unints believe in the same Religion
		end
	else
		unitEntry_ReligionIcon:SetShow(false);
		BQUI_UnitDifferentReligions = -1;
	end
end

-- bolbas (Middle Click on Unit List entries added - shows total number of units of that type)
function BQUI_CalculateUnits(BQUI_UnitType, unitEntrySum)
	if unitEntrySum:IsHidden() then
		local UnitNumber = 0;
		local pPlayer:table = Players[Game.GetLocalPlayer()];
		local pPlayerUnits:table = pPlayer:GetUnits();
		for i, pUnit in pPlayerUnits:Members() do
			local pUnitType = GameInfo.Units[pUnit:GetUnitType()].UnitType;
			if pUnitType == BQUI_UnitType then
				UnitNumber = UnitNumber + 1;
			end
		end

		unitEntrySum:SetText(UnitNumber);
		unitEntrySum:SetShow(true);

		if BQUI_PreviousUnitEntrySum == nil then
			BQUI_PreviousUnitEntrySum = unitEntrySum;
		else
			BQUI_PreviousUnitEntrySum:SetShow(false);
			BQUI_PreviousUnitEntrySum = unitEntrySum;
		end
	else
		unitEntrySum:SetShow(false);
		BQUI_PreviousUnitEntrySum = nil;
	end
end

--function AddUnitToUnitList(pUnit:table, BQUI_localPlayerID:number, BQUI_IfUnitListFitsTheScreen:boolean)    -- bolbas (Scrollbar area is removed from the Unit List and appears only when scrollbar available)
function AddUnitToUnitList(pUnit:table)
	local BQUI_localPlayerID:number = Game.GetLocalPlayer();
	local unitEntry:table = m_unitEntryIM:GetInstance();

	-- check formation and prepare suffix
	local suffix:string = " ";
	if     pUnit:GetMilitaryFormation() == MilitaryFormationTypes.CORPS_FORMATION then suffix = "[ICON_Corps]";
	elseif pUnit:GetMilitaryFormation() == MilitaryFormationTypes.ARMY_FORMATION  then suffix = "[ICON_Army]"; end
	
	-- Infixo: Heroes Mode
	if m_isHeroes then
		local eHeroClass = Game.GetHeroesManager():GetUnitHeroClass( pUnit:GetUnitType() );
		if eHeroClass > -1 then
			suffix = "[ICON_Capital]";
		end
	end
	
	-- name and tooltip
	local tt:table = {};
	local name:string = pUnit:GetName();
	local tooltip:string = Locale.Lookup(name);
	if suffix ~= " " then tooltip = tooltip.." "..suffix; end
	local unitInfo:table = GameInfo.Units[pUnit:GetUnitType()];
	local unitTypeName:string = unitInfo.Name;
	if name ~= unitTypeName then
		tooltip = tooltip.." "..Locale.Lookup("LOC_UNIT_UNIT_TYPE_NAME_SUFFIX", unitTypeName); -- <Text> ({1_UnitTypeName})</Text>
		table.insert(tt, tooltip);
	end
	unitEntry.BQUI_UnitName:SetText(Locale.ToUpper(Locale.Lookup(name))); -- actual name
	unitEntry.BQUI_UnitNameSuffix:SetText(suffix); -- corps/army icon
	
	-- attach unit ID to the control for future use
	local BQUI_UnitID = pUnit:GetID();
	unitEntry.Button:SetVoid1(BQUI_UnitID);

	local BQUI_UnitType = unitInfo.UnitType;
	local BQUI_unitExperience = pUnit:GetExperience();
	local BQUI_PromotionList :table = BQUI_unitExperience:GetPromotions();
	local BQUI_ExperiencePoints = BQUI_unitExperience:GetExperiencePoints();
	local BQUI_MaxExperience = BQUI_unitExperience:GetExperienceForNextLevel();
	local BQUI_SpreadCharges = pUnit:GetSpreadCharges();
	local BQUI_ReligiousHealCharges = pUnit:GetReligiousHealCharges();
	local BQUI_CombatStrength = pUnit:GetCombat();
	local BQUI_RangedCombatStrength = pUnit:GetRangedCombat();

	-- promotions are off by default
	unitEntry.BQUI_PromotionIcons_UnitList:SetShow(false); -- graphical representation
	unitEntry.BQUI_RealPromotion_1_UnitList:SetShow(false);
	unitEntry.BQUI_RealPromotion_2_UnitList:SetShow(false);
	unitEntry.BQUI_RealPromotion_3_UnitList:SetShow(false);
	unitEntry.BQUI_UNIT_ABILITIES_XP_UnitList:SetShow(false);
	unitEntry.BQUI_UNIT_ABILITIES_STRENGTH_UnitList:SetShow(false);
	unitEntry.BQUI_UNIT_ABILITIES_GP_UnitList:SetShow(false);
	unitEntry.BQUI_UNIT_ABILITIES_COMANDANTE_UnitList:SetShow(false);
	unitEntry.BQUI_UNIT_ABILITIES_DOUBLE_GP_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_11_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_21_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_31_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_13_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_23_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_33_UnitList:SetShow(false);
	unitEntry.BQUI_TierPromotion_42_UnitList:SetShow(false);
	
	local function SetPromotionIconByName(unitEntry:table, idx:number, iconName:string, size:number, offsetY:number)
		--print("FUN SetPromotionIconByName",idx,iconName,size,offsetY);
		unitEntry["BQUI_RealPromotion_" .. idx .. "_UnitList"]:SetShow(true);
		unitEntry["PromotionIcon"..idx]:SetIcon(iconName);
		unitEntry["PromotionIcon"..idx]:SetSizeVal(size, size);
		unitEntry["PromotionIcon"..idx]:SetOffsetY(offsetY);
	end
	
	local function SetPromotionIconByIcon(unitEntry:table, idx:number, iconInfo:table)
		SetPromotionIconByName(unitEntry, idx, iconInfo.Icon, iconInfo.Size, iconInfo.OffsetY);
	end

	if #BQUI_PromotionList > 0 then
		if BQUI_ExperiencePoints == BQUI_MaxExperience and ( ( BQUI_UnitType ~= "UNIT_LAHORE_NIHANG" and #BQUI_PromotionList < 7 ) or ( BQUI_UnitType == "UNIT_LAHORE_NIHANG" and #BQUI_PromotionList < 5 ) ) then
			unitEntry.BQUI_IconPromotionAvailable_UnitList:SetShow(true);
		end

		if BQUI_CombatStrength > 0 or BQUI_RangedCombatStrength > 0 then
			unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
			unitEntry.BQUI_PromotionsCount_UnitList:SetText(#BQUI_PromotionList);

			-- bolbas (Promotion tree added)
			if BQUI_UnitType ~= "UNIT_LAHORE_NIHANG" and #BQUI_PromotionList < 7 then
				for i = 1, #BQUI_PromotionList do
					local b = GameInfo.UnitPromotions[BQUI_PromotionList[i]].Column;
					if b > 0 then
						local a = GameInfo.UnitPromotions[BQUI_PromotionList[i]].Level;
						if BQUI_PromotionTreeCheck[a .. b] ~= nil then
							unitEntry["BQUI_TierPromotion_" .. a .. b .. "_UnitList"]:SetShow(true);
						else
							for number, value in pairs(BQUI_PromotionTreeCheck) do
								unitEntry["BQUI_TierPromotion_" .. number .. "_UnitList"]:SetShow(false);
							end
							break;
						end
					else
						break;
					end
				end
			elseif BQUI_UnitType == "UNIT_LAHORE_NIHANG" and #BQUI_PromotionList < 5 then
				for i = 1, #BQUI_PromotionList do
					local b = GameInfo.UnitPromotions[BQUI_PromotionList[i]].Column;
					if b > 0 then
						local a = GameInfo.UnitPromotions[BQUI_PromotionList[i]].Level;
						if a == 3 and b == 2 then
							a = 4;
						end
						if BQUI_PromotionTreeCheck[a .. b] ~= nil then
							unitEntry["BQUI_TierPromotion_" .. a .. b .. "_UnitList"]:SetShow(true);
						else
							for number, value in pairs(BQUI_PromotionTreeCheck) do
								unitEntry["BQUI_TierPromotion_" .. number .. "_UnitList"]:SetShow(false);
							end
							break;
						end
					else
						break;
					end
				end
			end
				
		--- *** RELIGIOUS UNITS ***
		elseif BQUI_SpreadCharges > 0 then
			unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
			unitEntry.BQUI_PromotionsCount_UnitList:SetText(BQUI_SpreadCharges);

			for i,promo in ipairs(BQUI_PromotionList) do
				local promoInfo:table = GameInfo.UnitPromotions[promo];
				--dshowtable(promoInfo);
				local iconInfo:table = BQUI_ApostlePromotionIcons[ promoInfo.UnitPromotionType ];
				if m_isCQUI then iconInfo = CQUI_ApostlePromotionIcons[ promoInfo.UnitPromotionType ]; end
				if iconInfo ~= nil and i <= 3 then SetPromotionIconByIcon(unitEntry, i, iconInfo); end
				table.insert(tt, "[ICON_Promotion] "..Locale.Lookup(promoInfo.Name)); -- add to the tooltip
			end

		-- *** SPY ***
		elseif BQUI_UnitType == "UNIT_SPY" then
			local TruncateWidth = 185;
			if #BQUI_PromotionList > 2 or ( #BQUI_PromotionList == 2 and BQUI_ExperiencePoints == BQUI_MaxExperience ) then
				TruncateWidth = 135;
			end
			for i,promo in ipairs(BQUI_PromotionList) do
				local promoInfo:table = GameInfo.UnitPromotions[promo];
				if m_isBES then
					--local iconInfo:table = BQUI_SpyPromotionIcons[ promoInfo.UnitPromotionType ];
					if i <= 3 then SetPromotionIconByName(unitEntry, i, promoInfo.UnitPromotionType, 16, 0); end
				else
					local iconInfo:table = BQUI_SpyPromotionIcons[ promoInfo.UnitPromotionType ];
					if iconInfo ~= nil and i <= 3 then SetPromotionIconByIcon(unitEntry, i, iconInfo); end
				end
				table.insert(tt, "[ICON_Promotion] "..Locale.Lookup(promoInfo.Name)); -- add to the tooltip
			end

		-- *** ROCK BAND ***
		elseif BQUI_UnitType == "UNIT_ROCK_BAND" then
			local TruncateWidth = 185;
			if #BQUI_PromotionList > 2 or ( #BQUI_PromotionList == 2 and BQUI_ExperiencePoints == BQUI_MaxExperience ) then
				TruncateWidth = 135;
			end
			for i,promo in ipairs(BQUI_PromotionList) do
				local promoInfo:table = GameInfo.UnitPromotions[promo];
				local iconInfo:table = BQUI_RockBandPromotionIcons[ promoInfo.UnitPromotionType ];
				if m_isCQUI then iconInfo = CQUI_RockBandPromotionIcons[ promoInfo.UnitPromotionType ]; end
				if iconInfo ~= nil and i <= 3 then SetPromotionIconByIcon(unitEntry, i, iconInfo); end
				table.insert(tt, "[ICON_Promotion] "..Locale.Lookup(promoInfo.Name)); -- add to the tooltip
			end
				
		-- *** SOOTHSAYER ***
		elseif pUnit:GetDisasterCharges() > 0 then
			unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
			unitEntry.BQUI_PromotionsCount_UnitList:SetText(pUnit:GetDisasterCharges());

			for i = 1, #BQUI_PromotionList do
				if i > 3 then
					break;
				end

				local BQUI_PromotionType = GameInfo.UnitPromotions[BQUI_PromotionList[i]].UnitPromotionType;
				if BQUI_SoothsayerPromotionIcons[BQUI_PromotionType] ~= nil then
					unitEntry["BQUI_RealPromotion_" .. i .. "_UnitList"]:SetShow(true);
					local PromotionIconSize = BQUI_SoothsayerPromotionIcons[BQUI_PromotionType].Size;
					unitEntry["BQUI_IconRealPromotion_" .. i .. "_UnitList"]:SetSizeVal(PromotionIconSize, PromotionIconSize);
					unitEntry["BQUI_IconRealPromotion_" .. i .. "_UnitList"]:SetIcon(BQUI_SoothsayerPromotionIcons[BQUI_PromotionType].Icon);
					unitEntry["BQUI_IconRealPromotion_" .. i .. "_UnitList"]:SetOffsetY(BQUI_SoothsayerPromotionIcons[BQUI_PromotionType].OffsetY);
				else
					if i > 1 then
						for j = 1, i - 1 do
							unitEntry["BQUI_RealPromotion_" .. j .. "_UnitList"]:SetShow(false);
						end
					end
					break;
				end
			end
		end

	elseif BQUI_ExperiencePoints == BQUI_MaxExperience then -- TODO: add check if the unit can be promoted at all
		unitEntry.BQUI_IconPromotionAvailable_UnitList:SetShow(true);
		if BQUI_SpreadCharges > 0 then
			unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
			unitEntry.BQUI_PromotionsCount_UnitList:SetText(BQUI_SpreadCharges);
		end
	
	elseif pUnit:GetBuildCharges() > 0 and BQUI_CombatStrength == 0 and BQUI_RangedCombatStrength == 0 then
		unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
		unitEntry.BQUI_PromotionsCount_UnitList:SetText(pUnit:GetBuildCharges());
		
	elseif BQUI_SpreadCharges > 0 then
		unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
		unitEntry.BQUI_PromotionsCount_UnitList:SetText(BQUI_SpreadCharges);
		
	elseif BQUI_ReligiousHealCharges > 0 then
		unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
		unitEntry.BQUI_PromotionsCount_UnitList:SetText(BQUI_ReligiousHealCharges);
		
	elseif BQUI_UnitType == "UNIT_ARCHAEOLOGIST" then
		--local localPlayer = Players[Game.GetLocalPlayer()];
		--local idArchaeologyHomeCity = pUnit:GetArchaeologyHomeCity();
		local pCity = Players[Game.GetLocalPlayer()]:GetCities():FindID( pUnit:GetArchaeologyHomeCity() );
		local pCityBldgs:table = pCity:GetBuildings();
		local ArchaeologicalMuseumIndex = GameInfo.Buildings["BUILDING_MUSEUM_ARTIFACT"].Index
		local numSlots:number = pCityBldgs:GetNumGreatWorkSlots(ArchaeologicalMuseumIndex);
		local ArchaeologistCharges = 0;
		for index:number = 0, numSlots - 1 do
			local greatWorkIndex:number = pCityBldgs:GetGreatWorkInSlot(ArchaeologicalMuseumIndex, index);
			if (greatWorkIndex == -1) then
				ArchaeologistCharges = ArchaeologistCharges + 1;
			end
		end
		unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
		unitEntry.BQUI_PromotionsCount_UnitList:SetText(ArchaeologistCharges);
		
	-- *** GREAT GENERAL / ADMIRAL ***
	elseif BQUI_UnitType == "UNIT_GREAT_ADMIRAL" or BQUI_UnitType == "UNIT_GREAT_GENERAL" then    -- bolbas (Apostle, Spy, Rock Band, Soothsayer promotion and Great Person passive ability icons added)
		local individual:number = pUnit:GetGreatPerson():GetIndividual();
		if individual >= 0 then
			local individualEraType:string = GameInfo.GreatPersonIndividuals[individual].EraType;
			if BQUI_GreatPersonEras[individualEraType] ~= nil then
				for i = 1, 2 do
					if BQUI_GreatPersonEras[individualEraType]["Icon_" .. i] ~= nil then
						unitEntry["BQUI_RealPromotion_" .. i .. "_UnitList"]:SetShow(true);
						unitEntry["BQUI_IconRealPromotion_" .. i .. "_UnitList"]:SetSizeVal(BQUI_GreatPersonEras[individualEraType]["Size_" .. i], BQUI_GreatPersonEras[individualEraType]["Size_" .. i]);
						unitEntry["BQUI_IconRealPromotion_" .. i .. "_UnitList"]:SetIcon(BQUI_GreatPersonEras[individualEraType]["Icon_" .. i]);
						unitEntry["BQUI_IconRealPromotion_" .. i .. "_UnitList"]:SetOffsetY(BQUI_GreatPersonEras[individualEraType]["OffsetY_" .. i]);
					end
				end
				--table.insert (BQUI_GreatPersonEntriesToSetOffset, {unitEntry = unitEntry});
			end
		end
		
	elseif pUnit:GetDisasterCharges() > 0 then
		unitEntry.BQUI_PromotionIcons_UnitList:SetShow(true);
		unitEntry.BQUI_PromotionsCount_UnitList:SetText(pUnit:GetDisasterCharges());
	end

	-- bolbas (Icons for levied units added)
	if BQUI_CombatStrength > 0 then
		local iOwner = pUnit:GetOwner();
		local iOriginalOwner = pUnit:GetOriginalOwner();
		if (iOwner ~= iOriginalOwner) then
			local pOriginalOwner = Players[iOriginalOwner];
			if (pOriginalOwner ~= nil and pOriginalOwner:GetInfluence() ~= nil) then
				local iLevyTurnCounter = pOriginalOwner:GetInfluence():GetLevyTurnCounter();
				if (iLevyTurnCounter >= 0 and iOwner == pOriginalOwner:GetInfluence():GetSuzerain()) then
					unitEntry.BQUI_LeviedUnits_UnitList:SetShow(true);
					if #BQUI_PromotionList > 0 then
						unitEntry.BQUI_LeviedUnits_UnitList:SetOffsetX(-18);
						unitEntry.BQUI_PromotionsCount_UnitList:SetHide(true);

						-- bolbas (Promotion tree added)
						if #BQUI_PromotionList == 7 then
							for number, value in pairs(BQUI_PromotionTreeCheck) do
								unitEntry["BQUI_TierPromotion_" .. number .. "_UnitList"]:SetShow(true);
							end
						end
					end
				end
			end
		end
	end
	--end

	-- bolbas (Religion icons added)
	if BQUI_SpreadCharges > 0 or BQUI_ReligiousHealCharges > 0 then
		BQUI_SetReligionIconUnitList(pUnit, unitEntry.BQUI_ReligionIcon);
	else
		unitEntry.BQUI_ReligionIcon:SetShow(false);
	end

	-- bolbas (Upgrade icon added)
	local BQUI_upgradeCost = pUnit:GetUpgradeCost();
	if BQUI_upgradeCost > 0 then
		unitEntry.BQUI_IconUpgrade:SetShow(true);
		local bCanStart = UnitManager.CanStartCommand( pUnit, UnitCommandTypes.UPGRADE, true);
		if bCanStart then
			local bCanStartNow = UnitManager.CanStartCommand( pUnit, UnitCommandTypes.UPGRADE, false, true);
			if not bCanStartNow then
				unitEntry.BQUI_IconUpgrade:SetColorByName("UnitPanelTextDisabledCS");
			end
		else
			unitEntry.BQUI_IconUpgrade:SetColorByName("UnitPanelTextDisabledCS");
		end
	else
		unitEntry.BQUI_IconUpgrade:SetShow(false);
	end

	-- bolbas (Unit Abilities added to Unit List and Unit Panel)
	--if BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] ~= nil and (BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] < 2 or BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] == 5) then    -- bolbas (Right Click on Unit List popup and Unit List entries added, entry with selected unit highlighted)
	if BQUI_CombatStrength > 0 or BQUI_RangedCombatStrength > 0 then
		local BQUI_AbilitiesXP = 0;
		local BQUI_AbilitiesStrength = 0;
		local BQUI_ShowAbilities_GP = false;
		local BQUI_ShowAbilities_COMANDANTE = false;
		local unitAbilitiesList = pUnit:GetAbility():GetAbilities();
		if (unitAbilitiesList ~= nil and table.count(unitAbilitiesList) > 0) then
			for i, ability in ipairs (unitAbilitiesList) do
				local abilityDef = GameInfo.UnitAbilities[ability];
				if (abilityDef ~= nil) then
					if (abilityDef.Description ~= nil) then
						local BQUI_AbilityType = abilityDef.UnitAbilityType;
						if BQUI_UnitAbilitiesIcons[BQUI_AbilityType] ~= nil then
							if BQUI_UnitAbilitiesIcons[BQUI_AbilityType] <= 18 then    -- bolbas: XP abilities
								if #BQUI_PromotionList < 7 then
									if BQUI_UnitAbilitiesIcons[BQUI_AbilityType] < 13 then
										BQUI_AbilitiesXP = BQUI_AbilitiesXP + 1;    -- bolbas: +25% XP
									elseif BQUI_UnitAbilitiesIcons[BQUI_AbilityType] < 15 then
										BQUI_AbilitiesXP = BQUI_AbilitiesXP + 2;    -- bolbas: +50% XP
									elseif BQUI_UnitAbilitiesIcons[BQUI_AbilityType] < 16 then
										BQUI_AbilitiesXP = BQUI_AbilitiesXP + 3;    -- bolbas: +75% XP
									elseif BQUI_UnitAbilitiesIcons[BQUI_AbilityType] < 18 then
										BQUI_AbilitiesXP = BQUI_AbilitiesXP + 4;    -- bolbas: +100% XP
									else
										BQUI_AbilitiesXP = BQUI_AbilitiesXP + 5;    -- bolbas: > +100% XP
									end
								end
							elseif BQUI_UnitAbilitiesIcons[BQUI_AbilityType] <= 24 then    -- bolbas: Strength abilities
								BQUI_AbilitiesStrength = BQUI_AbilitiesStrength + 1;
							elseif BQUI_UnitAbilitiesIcons[BQUI_AbilityType] <= 26 then    -- bolbas: GP abilities
								BQUI_ShowAbilities_GP = true;
							else    -- bolbas: Comandante abilities
								BQUI_ShowAbilities_COMANDANTE = true;
							end
						end
					end
				end
			end
		end

		if BQUI_AbilitiesXP > 0 or BQUI_AbilitiesStrength > 0 or BQUI_ShowAbilities_GP == true or BQUI_ShowAbilities_COMANDANTE == true then
			unitEntry.BQUI_AllAbilities_UnitList:SetShow(true);
			if not unitEntry.BQUI_IconPromotionAvailable_UnitList:IsHidden() then
				unitEntry.BQUI_AllAbilities_UnitList:SetOffsetX(-20);
			end

			if BQUI_AbilitiesXP > 0 then
				unitEntry.BQUI_UNIT_ABILITIES_XP_UnitList:SetShow(true);
				if BQUI_AbilitiesXP == 2 then
					unitEntry.BQUI_UNIT_ABILITIES_XP_TIER_UnitList:SetColorByName("PolicyEconomic");
				elseif BQUI_AbilitiesXP == 3 then
					unitEntry.BQUI_UNIT_ABILITIES_XP_TIER_UnitList:SetColorByName("StatGoodCS");
				elseif BQUI_AbilitiesXP == 4 then
					unitEntry.BQUI_UNIT_ABILITIES_XP_TIER_UnitList:SetColorByName("COLOR_FLOAT_SCIENCE");
				elseif BQUI_AbilitiesXP >= 5 then
					unitEntry.BQUI_UNIT_ABILITIES_XP_TIER_UnitList:SetColor( BQUI_Color_Tier_5 );
				end
			end

			if BQUI_AbilitiesStrength > 0 then
				unitEntry.BQUI_UNIT_ABILITIES_STRENGTH_UnitList:SetShow(true);
				if BQUI_AbilitiesStrength == 2 then
					unitEntry.BQUI_UNIT_ABILITIES_STRENGTH_TIER_UnitList:SetColorByName("Gray");
				elseif BQUI_AbilitiesStrength == 3 then
					unitEntry.BQUI_UNIT_ABILITIES_STRENGTH_TIER_UnitList:SetColorByName("AirportDark");
				elseif BQUI_AbilitiesStrength == 4 then
					unitEntry.BQUI_UNIT_ABILITIES_STRENGTH_TIER_UnitList:SetColorByName("Airport");
				elseif BQUI_AbilitiesStrength >= 5 then
					unitEntry.BQUI_UNIT_ABILITIES_STRENGTH_TIER_UnitList:SetColorByName("MilitaryDark");
				end
			end

			if BQUI_ShowAbilities_GP == true then
				if BQUI_ShowAbilities_COMANDANTE == false then
					unitEntry.BQUI_UNIT_ABILITIES_GP_UnitList:SetShow(true);
				else
					unitEntry.BQUI_UNIT_ABILITIES_DOUBLE_GP_UnitList:SetShow(true);
				end
			elseif BQUI_ShowAbilities_COMANDANTE == true then
				unitEntry.BQUI_UNIT_ABILITIES_COMANDANTE_UnitList:SetShow(true);
			end
				
		else
			unitEntry.BQUI_AllAbilities_UnitList:SetShow(false);
		end
	end
	--end

	-- Infixo: highlight the currently selected unit or use default control
	unitEntry.Button:SetTexture( UI.IsUnitSelected(pUnit) and "Controls_ButtonControl_Tan" or "Controls_ButtonControl");
	
	unitEntry.Button:RegisterCallback( Mouse.eLClick, function() OnUnitEntryClicked(pUnit:GetID(), unitEntry, true)  end); -- left click closes
	unitEntry.Button:RegisterCallback( Mouse.eMClick, function() BQUI_CalculateUnits( BQUI_UnitType, unitEntry.BQUI_UnitsSum ); end );    -- bolbas (Middle Click on Unit List entries added - shows total number of units of that type)
	unitEntry.Button:RegisterCallback( Mouse.eRClick, function() OnUnitEntryClicked(pUnit:GetID(), unitEntry, false) end); -- right click does not close

	-- HEALTH
	-- Infixo: this is Firaxis' function from UnitPanel.lua
	local function GetPercentFromDamage( damage:number, maxDamage:number )
		if damage > maxDamage then
			damage = maxDamage;
		end
		return (damage / maxDamage);
	end
	local percent:number = 1 - GetPercentFromDamage( pUnit:GetDamage(), pUnit:GetMaxDamage() );
	if percent < 1 then
		unitEntry.BQUI_HPBarBG:SetShow(true);
		unitEntry.BQUI_HPBar:SetShow(true);
		local sizeY = math.max ( math.floor( (14 * percent) + 0.5 ), 2 );    -- bolbas: !!!!! next 3 lines here because Direction="Up" is bugged for bars in UnitPanel.xml. It works only when Speed="1" or more and doesn't work when Speed="0" !!!!! -- bolbas: added "math.max" to make low hp bars more visible
		unitEntry.BQUI_HPBar:SetSizeY( sizeY );
		unitEntry.BQUI_HPBar:SetPercent( 1 );

		if	( percent > 0.7 )	then
			unitEntry.BQUI_HPBar:SetColor( COLORS.METER_HP_GOOD );
		elseif ( percent > 0.4 )	then
			unitEntry.BQUI_HPBar:SetColor( COLORS.METER_HP_OK );
		else
			unitEntry.BQUI_HPBar:SetColor( COLORS.METER_HP_BAD );
		end
	else -- no damage
		unitEntry.BQUI_HPBarBG:SetShow(false);
		unitEntry.BQUI_HPBar:SetShow(false);
	end

	UpdateUnitIcon(pUnit, unitEntry);

	-- Update status icon
	unitEntry.UnitStatusIcon:SetShow(true); -- default, hidden in some cases only
	local activityType:number = UnitManager.GetActivityType(pUnit);
	if UnitManager.GetQueuedDestination( pUnit ) then    -- bolbas ("Move to" unit status icon added)
		unitEntry.UnitStatusIcon:SetSizeVal(20,20);
		unitEntry.UnitStatusIcon:SetIcon("ICON_MOVES");
		--unitEntry.UnitStatusIcon:SetHide(false);
	elseif activityType == ActivityTypes.ACTIVITY_SLEEP then
		--SetUnitEntryStatusIcon(unitEntry, "ICON_STATS_SLEEP");
		unitEntry.UnitStatusIcon:SetIcon("ICON_STATS_SLEEP");
	elseif activityType == ActivityTypes.ACTIVITY_HOLD then
		--SetUnitEntryStatusIcon(unitEntry, "ICON_STATS_SKIP");
		unitEntry.UnitStatusIcon:SetIcon("ICON_STATS_SKIP");
	elseif activityType ~= ActivityTypes.ACTIVITY_AWAKE and pUnit:GetFortifyTurns() > 0 then
		--SetUnitEntryStatusIcon(unitEntry, "ICON_DEFENSE");
		unitEntry.UnitStatusIcon:SetIcon("ICON_DEFENSE");
	else
		unitEntry.UnitStatusIcon:SetHide(true);
	end

	-- Update entry color if unit cannot take any action
	if pUnit:IsReadyToMove() then
		unitEntry.Button:GetTextControl():SetColorByName("UnitPanelTextCS");
		unitEntry.UnitTypeIcon:SetColorByName("UnitPanelTextCS");
	else
		unitEntry.Button:GetTextControl():SetColorByName("UnitPanelTextDisabledCS");
		unitEntry.UnitTypeIcon:SetColorByName("UnitPanelTextDisabledCS");

		-- bolbas (Upgrade, promotion and charges icons and numbers added)
		unitEntry.BQUI_UnitName:SetColorByName("UnitPanelTextDisabledCS");
		--if BQUI_ReligionIconsState[BQUI_localPlayerID] == 0 or BQUI_ReligionIconsState[BQUI_localPlayerID] == 3 then    -- bolbas (Right Click on Religion Strength Icon added)
			unitEntry.BQUI_ReligionIcon:SetColorByName("UnitPanelTextDisabledCS");
		--end

		if pUnit:GetMovementMovesRemaining() == 0 then
			if unitEntry.UnitStatusIcon:GetSizeX() == 20 then    -- bolbas ("Move to" unit status icon added)
				unitEntry.UnitStatusIcon:SetColorByName("UnitPanelTextDisabledCS");
			end

			--if BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] ~= nil and BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] ~= 4 then    -- bolbas (Right Click on Unit List popup and Unit List entries added, entry with selected unit highlighted)
				if BQUI_ExperiencePoints == BQUI_MaxExperience then
					unitEntry.BQUI_IconPromotionAvailable_UnitList:SetColorByName("UnitPanelTextDisabledCS");
				end
			--end
		end

		--if BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] ~= nil and BQUI_IconsAndAbilitiesState[BQUI_localPlayerID] ~= 4 then    -- bolbas (Right Click on Unit List popup and Unit List entries added, entry with selected unit highlighted)
			unitEntry.BQUI_PromotionsCount_UnitList:SetColorByName("UnitPanelTextDisabledCS");
			unitEntry.BQUI_LeviedUnits_UnitList:SetColorByName("UnitPanelTextDisabledCS");
			unitEntry.BQUI_IconRealPromotion_1_UnitList:SetColorByName("UnitPanelTextDisabledCS");
			unitEntry.BQUI_IconRealPromotion_2_UnitList:SetColorByName("UnitPanelTextDisabledCS");
			unitEntry.BQUI_IconRealPromotion_3_UnitList:SetColorByName("UnitPanelTextDisabledCS");
			--[[
			if BQUI_UnitType == "UNIT_ROCK_BAND" then    -- bolbas (new Water Park icon for Rock Band promotions added)
				for i = 1, 3 do
					for j = 1, 4 do
						unitEntry["BQUI_WaterParkIcon_" .. i .. "_P" .. j .. "_UnitList"]:SetColorByName("UnitPanelTextDisabledCS");
					end
				end
			end
			--]]
		--end
	end
	
	-- simplified logic to show/hide controls
	--local isCivilian:boolean = ( unitInfo.FormationClass == "FORMATION_CLASS_CIVILIAN" );
	--local isSupport:boolean  = ( unitInfo.FormationClass == "FORMATION_CLASS_SUPPORT" );
	unitEntry.UnitTypeIcon:SetShow(true); -- always show
	--BQUI_UnitsSum -- separate logic
	--BQUI_IconUpgrade -- separate logic
	--BQUI_ReligionIcon -- separate logic
	--UnitStatusIcon -- separate logic
	--BQUI_UnitName_UnitList -- always visible
	--BQUI_PromotionIcons_UnitList -- graphical representation
	--BQUI_AllAbilities_UnitList -- dots for abilities
	--BQUI_RealPromotion_1_UnitList
	--BQUI_RealPromotion_2_UnitList
	--BQUI_RealPromotion_3_UnitList
	--BQUI_HPBarBG -- separate logic
	--BQUI_HPBar -- separate logic
	
	-- Infixo: build and show the tooltip
	unitEntry.Button:SetToolTipString(table.concat(tt, "[NEWLINE]"));
end

-- Infixo: why is this function overwritten?
--function SetUnitEntryStatusIcon(unitEntry:table, icon:string)
	--local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas(icon,22);
	--unitEntry.UnitStatusIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
	--unitEntry.UnitStatusIcon:SetHide(false);
--end

-- INFIXO: END OF BOLBAS' CODE
-- ===========================================================================


--[[ Infixo: original code
-- ===========================================================================
function AddUnitToUnitList(pUnit:table)
	local uiUnitEntry : table = m_unitEntryIM:GetInstance();

	local formation : number = pUnit:GetMilitaryFormation();
	local suffix : string = "";
	local unitType = pUnit:GetUnitType();
	local unitInfo : table = GameInfo.Units[unitType];
	if (unitInfo.Domain == "DOMAIN_SEA") then
		if (formation == MilitaryFormationTypes.CORPS_FORMATION) then
			suffix = " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_FLEET_SUFFIX");
		elseif (formation == MilitaryFormationTypes.ARMY_FORMATION) then
			suffix = " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_ARMADA_SUFFIX");
		end
	else
		if (formation == MilitaryFormationTypes.CORPS_FORMATION) then
			suffix = " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_CORPS_SUFFIX");
		elseif (formation == MilitaryFormationTypes.ARMY_FORMATION) then
			suffix = " " .. Locale.Lookup("LOC_HUD_UNIT_PANEL_ARMY_SUFFIX");
		end
	end

	local name : string = pUnit:GetName();
	local uniqueName : string = Locale.Lookup( name ) .. suffix;

	local tooltip : string = "";
	local pUnitDef = GameInfo.Units[unitType];
	if pUnitDef then
		local unitTypeName:string = pUnitDef.Name;
		if name ~= unitTypeName then
			tooltip = uniqueName .. " " .. Locale.Lookup("LOC_UNIT_UNIT_TYPE_NAME_SUFFIX", unitTypeName);
		end
	end
	uiUnitEntry.Button:SetToolTipString(tooltip);

	uiUnitEntry.Button:SetText( Locale.ToUpper(uniqueName) );
	uiUnitEntry.Button:RegisterCallback(Mouse.eLClick, function() OnUnitEntryClicked(pUnit:GetID())  end);

	UpdateUnitIcon(pUnit, uiUnitEntry);

	-- Update status icon
	local activityType:number = UnitManager.GetActivityType(pUnit);
	if activityType == ActivityTypes.ACTIVITY_SLEEP then
		SetUnitEntryStatusIcon(uiUnitEntry, "ICON_STATS_SLEEP");
		uiUnitEntry.UnitStatusIcon:SetHide(false);
	elseif activityType == ActivityTypes.ACTIVITY_HOLD then
		SetUnitEntryStatusIcon(uiUnitEntry, "ICON_STATS_SKIP");
		uiUnitEntry.UnitStatusIcon:SetHide(false);
	elseif activityType ~= ActivityTypes.ACTIVITY_AWAKE and pUnit:GetFortifyTurns() > 0 then
		SetUnitEntryStatusIcon(uiUnitEntry, "ICON_DEFENSE");
		uiUnitEntry.UnitStatusIcon:SetHide(false);
	else
		uiUnitEntry.UnitStatusIcon:SetHide(true);
	end

	-- Update entry color if unit cannot take any action
	if pUnit:GetMovementMovesRemaining() > 0 then
		uiUnitEntry.Button:GetTextControl():SetColorByName("UnitPanelTextCS");
		uiUnitEntry.UnitTypeIcon:SetColorByName("UnitPanelTextCS");
	else
		uiUnitEntry.Button:GetTextControl():SetColorByName("UnitPanelTextDisabledCS");
		uiUnitEntry.UnitTypeIcon:SetColorByName("UnitPanelTextDisabledCS");
	end
end
--]]


-- ===========================================================================
function UpdateUnitIcon(pUnit:table, uiUnitEntry:table)
	local iconInfo:table, iconShadowInfo:table = GetUnitIcon(pUnit, 22, true);
	if iconInfo.textureSheet then
		uiUnitEntry.UnitTypeIcon:SetTexture( iconInfo.textureOffsetX, iconInfo.textureOffsetY, iconInfo.textureSheet );
	end
end

-- ===========================================================================
function OnUnitEntryClicked(unitID:number, unitEntry:table, closeList:boolean)
	local playerUnits:table = Players[Game.GetLocalPlayer()]:GetUnits();
	local selectedUnit:table = nil;
	if playerUnits then
		selectedUnit = playerUnits:FindID(unitID);
		if selectedUnit then
			UI.LookAtPlot(selectedUnit:GetX(), selectedUnit:GetY());
			UI.SelectUnit( selectedUnit );
		end
	end
	-- Infixo: close list, no tricks here
	if closeList then
		UpdateUnitListPanel(true); 
		StartUnitListSizeUpdate();
		return;
	end
	-- Infixo: remove highlight from all units and toggle the selected one
	for _,uiChild in ipairs(m_unitListInstance.UnitStack:GetChildren()) do
		uiChild:SetTexture("Controls_ButtonControl");
	end
	if selectedUnit then
		unitEntry.Button:SetTexture("Controls_ButtonControl_Tan");
	end
end

-- ===========================================================================
function OnUnitListSearch()
	local searchBoxString : string = m_unitListInstance.UnitsSearchBox:GetText();
	if(searchBoxString == nil)then
		m_unitSearchString = "";
	else
		m_unitSearchString = string.upper(searchBoxString);
	end
	UpdateUnitListPanel();
end

-- ===========================================================================
function UpdateChatPanel(hideChat:boolean)
	m_hideChat = hideChat; 
	Controls.ChatPanelContainer:SetHide(m_hideChat);
	--Controls.ChatCheck:SetCheck(not m_hideChat);
	RealizeEmptyMessage();
	RealizeStack();
	CheckUnreadChatMessageCount();
end

-- ===========================================================================
function CheckUnreadChatMessageCount()
	-- Unhiding the chat panel resets the unread chat message count.
	if(not hideAll and not m_hideChat) then
		m_unreadChatMsgs = 0;
		UpdateUnreadChatMsgs();
		LuaEvents.WorldTracker_OnChatShown();
	end
end

-- ===========================================================================
function UpdateUnreadChatMsgs()
	if(GameConfiguration.IsPlayByCloud()) then
		Controls.ChatButton:SetText(Locale.Lookup("LOC_PLAY_BY_CLOUD_PANEL"));
	elseif(m_unreadChatMsgs > 0) then
		Controls.ChatButton:SetText(Locale.Lookup("LOC_HIDE_CHAT_PANEL_UNREAD_MESSAGES", m_unreadChatMsgs));
	else
		Controls.ChatButton:SetText(Locale.Lookup("LOC_HIDE_CHAT_PANEL"));
	end
end

-- ===========================================================================
--	Obtains full refresh and views most current research and civic IDs.
-- ===========================================================================
function Refresh()
	local localPlayer :number = Game.GetLocalPlayer();
	if localPlayer < 0 then
		ToggleAll(true);
		return;
	end

	UpdateWorldTrackerSize();

	local pPlayerTechs :table = Players[localPlayer]:GetTechs();
	m_currentResearchID = pPlayerTechs:GetResearchingTech();
	
	-- Only reset last completed tech once a new tech has been selected
	if m_currentResearchID >= 0 then	
		m_lastResearchCompletedID = -1;
	end	

	UpdateResearchPanel();

	local pPlayerCulture:table = Players[localPlayer]:GetCulture();
	m_currentCivicID = pPlayerCulture:GetProgressingCivic();

	-- Only reset last completed civic once a new civic has been selected
	if m_currentCivicID >= 0 then	
		m_lastCivicCompletedID = -1;
	end	

	UpdateCivicsPanel();
	UpdateUnitListPanel();

	-- Hide world tracker by default if there are no tracker options enabled
	if IsAllPanelsHidden() then
		ToggleAll(true);
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnLocalPlayerTurnBegin()
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 then
		m_isDirty = true;
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnCityInitialized( playerID:number, cityID:number )
	if playerID == Game.GetLocalPlayer() then	
		m_isDirty = true;
	end
end

-- ===========================================================================
--	GAME EVENT
--	Buildings can change culture/science yield which can effect 
--	"turns to complete" values
-- ===========================================================================
function OnBuildingChanged( plotX:number, plotY:number, buildingIndex:number, playerID:number, cityID:number, iPercentComplete:number )
	if playerID == Game.GetLocalPlayer() then	
		m_isDirty = true; 
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnDirtyCheck()
	if m_isDirty then
		Refresh();
		m_isDirty = false;
	end
end

-- ===========================================================================
--	GAME EVENT
--	A civic item has changed, this may not be the current civic item
--	but an item deeper in the tree that was just boosted by a player action.
-- ===========================================================================
function OnCivicChanged( ePlayer:number, eCivic:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then		
		ResetOverflowArrow( m_civicsInstance );
		local pPlayerCulture:table = Players[localPlayer]:GetCulture();
		m_currentCivicID = pPlayerCulture:GetProgressingCivic();
		m_lastCivicCompletedID = -1;
		if eCivic == m_currentCivicID then
			UpdateCivicsPanel();
		end
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnCivicCompleted( ePlayer:number, eCivic:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
		m_currentCivicID = -1;
		m_lastCivicCompletedID = eCivic;		
		UpdateCivicsPanel();
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnCultureYieldChanged( ePlayer:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
		UpdateCivicsPanel();
	end
end

-- ===========================================================================
--	GAME EVENT
-- ===========================================================================
function OnInterfaceModeChanged(eOldMode:number, eNewMode:number)
	if eNewMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		ContextPtr:SetHide(true); 
	end
	if eOldMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		ContextPtr:SetHide(false);
	end
end

-- ===========================================================================
--	GAME EVENT
--	A research item has changed, this may not be the current researched item
--	but an item deeper in the tree that was just boosted by a player action.
-- ===========================================================================
function OnResearchChanged( ePlayer:number, eTech:number )
	if ShouldUpdateResearchPanel(ePlayer, eTech) then
		ResetOverflowArrow( m_researchInstance );
		UpdateResearchPanel();
	end
end

-- ===========================================================================
--	This function was separated so behavior can be modified in mods/expasions
-- ===========================================================================
function ShouldUpdateResearchPanel(ePlayer:number, eTech:number)
	local localPlayer = Game.GetLocalPlayer();
	
	if localPlayer ~= -1 and localPlayer == ePlayer then
		local pPlayerTechs :table = Players[localPlayer]:GetTechs();
		m_currentResearchID = pPlayerTechs:GetResearchingTech();
		
		-- Only reset last completed tech once a new tech has been selected
		if m_currentResearchID >= 0 then	
			m_lastResearchCompletedID = -1;
		end

		if eTech == m_currentResearchID then
			return true;
		end
	end
	return false;
end

-- ===========================================================================
function OnResearchCompleted( ePlayer:number, eTech:number )
	if (ePlayer == Game.GetLocalPlayer()) then
		m_currentResearchID = -1;
		m_lastResearchCompletedID = eTech;
		UpdateResearchPanel();
	end
end

-- ===========================================================================
function OnUpdateDueToCity(ePlayer:number, cityID:number, plotX:number, plotY:number)
	if (ePlayer == Game.GetLocalPlayer()) then
		UpdateResearchPanel();
		UpdateCivicsPanel();
	end
end

-- ===========================================================================
function OnResearchYieldChanged( ePlayer:number )
	local localPlayer = Game.GetLocalPlayer();
	if localPlayer ~= -1 and localPlayer == ePlayer then
		UpdateResearchPanel();
	end
end


-- ===========================================================================
function OnMultiplayerChat( fromPlayer, toPlayer, text, eTargetType )
	-- If the chat panels are hidden, indicate there are unread messages waiting on the world tracker panel toggler.
	if(m_hideAll or m_hideChat) then
		m_unreadChatMsgs = m_unreadChatMsgs + 1;
		UpdateUnreadChatMsgs();
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnInit(isReload:boolean)	
	LateInitialize();
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	else		
		Refresh();	-- Standard refresh.
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnShutdown()
	Unsubscribe();

	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentResearchID",		m_currentResearchID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_lastResearchCompletedID",	m_lastResearchCompletedID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_currentCivicID",			m_currentCivicID);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "m_lastCivicCompletedID",		m_lastCivicCompletedID);	
end

-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)	
	if context == RELOAD_CACHE_ID then
		m_currentResearchID			= contextTable["m_currentResearchID"];
		m_lastResearchCompletedID	= contextTable["m_lastResearchCompletedID"];
		m_currentCivicID			= contextTable["m_currentCivicID"];
		m_lastCivicCompletedID		= contextTable["m_lastCivicCompletedID"];

		if m_currentResearchID == nil		then m_currentResearchID = -1; end
		if m_lastResearchCompletedID == nil then m_lastResearchCompletedID = -1; end
		if m_currentCivicID == nil			then m_currentCivicID = -1; end
		if m_lastCivicCompletedID == nil	then m_lastCivicCompletedID = -1; end

		-- Don't call refresh, use cached data from last hotload.
		UpdateResearchPanel();
		UpdateCivicsPanel();
		UpdateUnitListPanel();
	end
end

-- ===========================================================================
function OnTutorialGoalsShowing()
	Controls.TutorialGoals:SetHide(false);
	RealizeStack();
end

-- ===========================================================================
function OnTutorialGoalsHiding()
	RealizeStack();
end

-- ===========================================================================
function Tutorial_ShowFullTracker()
	Controls.ToggleAllButton:SetHide(true);
	-- Controls.ToggleDropdownButton:SetHide(true); -- Infixio: dropdown removed
	UpdateCivicsPanel(false);
	UpdateResearchPanel(false);
	ToggleAll(false);
end

-- ===========================================================================
function Tutorial_ShowTrackerOptions()
	Controls.ToggleAllButton:SetHide(false);
	--Controls.ToggleDropdownButton:SetHide(false); -- Infixo: dropdown removed
end

-- ===========================================================================
function OnSetMinimapCollapsed(isMinimapCollapsed:boolean)
	m_isMinimapCollapsed = isMinimapCollapsed;
	--CheckEnoughRoom();
	UpdateWorldTrackerSize();
end

-- ===========================================================================
function OnUnitAddedToMap(playerID:number, unitID:number)
	if UI.IsInGame() == false then
		return;
	end
	if(playerID == Game.GetLocalPlayer())then
		UpdateUnitListPanel();
		StartUnitListSizeUpdate();
	end
end

-- ===========================================================================
--	Game Engine Event
function OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
	if playerID ~= Game.GetLocalPlayer() then 
		return;
	end
	if isSelected then
		-- Infixo: toggle the selected one
		for _,uiChild in ipairs(m_unitListInstance.UnitStack:GetChildren()) do
			if uiChild:GetVoid1() == unitID then
				uiChild:SetTexture("Controls_ButtonControl_Tan");
				break;
			end
		end
	else
		-- Infixo: remove highlight
		for _,uiChild in ipairs(m_unitListInstance.UnitStack:GetChildren()) do
			if uiChild:GetVoid1() == unitID then
				uiChild:SetTexture("Controls_ButtonControl");
				break;
			end
		end
	end
end


-- ===========================================================================
function OnUnitMovementPointsChanged(playerID:number, unitID:number)
	if(playerID == Game.GetLocalPlayer())then
		UpdateUnitListPanel();
	end
end

-- ===========================================================================
function OnUnitRemovedFromMap(playerID:number, unitID:number)
	if(playerID == Game.GetLocalPlayer())then
		UpdateUnitListPanel();
		StartUnitListSizeUpdate();
	end
end

-- ===========================================================================
function OnUnitOperationDeactivated(playerID:number)
	--Update UnitList in case we put one of our units to sleep
	if(playerID == Game.GetLocalPlayer()) then
		UpdateUnitListPanel();
	end
end

-- ===========================================================================
function OnUnitOperationStarted(ownerID : number, unitID : number, operationID : number)
	if(ownerID == Game.GetLocalPlayer() and (operationID == UnitOperationTypes.FORTIFY or operationID == UnitOperationTypes.ALERT))then
		UpdateUnitListPanel();
	end
end

-- ===========================================================================
function OnUnitCommandStarted(playerID:number, unitID:number, hCommand:number)
    if (hCommand == UnitCommandTypes.WAKE and playerID == Game.GetLocalPlayer()) then
        UpdateUnitListPanel();
	end
end

-- ===========================================================================
--	Add any UI from tracked items that are loaded.
--	Items are expected to be tables with the following fields:
--		Name			localization key for the title name of panel
--		InstanceType	the instance (in XML) to create for the control
--		SelectFunc		if instance has "IconButton" the callback when pressed
-- ===========================================================================
function AttachDynamicUI()
	for i,kData in ipairs(g_TrackedItems) do
		local uiInstance:table = {};
		ContextPtr:BuildInstanceForControl( kData.InstanceType, uiInstance, Controls.WorldTrackerVerticalContainer );
		if uiInstance.IconButton then
			uiInstance.IconButton:RegisterCallback(Mouse.eLClick, function() kData.SelectFunc() end);
		end
		table.insert(g_TrackedInstances, uiInstance);

		if(uiInstance.TitleButton) then
			uiInstance.TitleButton:LocalizeAndSetText(kData.Name);
		end
	end
end

-- ===========================================================================
function OnForceHide()
	ContextPtr:SetHide(true);
end

-- ===========================================================================
function OnForceShow()
	ContextPtr:SetHide(false);
end

-- ===========================================================================
function OnStartObserverMode()
	UpdateResearchPanel();
	UpdateCivicsPanel();
end

-- ===========================================================================
function OnRefresh()
	ContextPtr:ClearRequestRefresh();
	if(not m_isMinimapInitialized)then
		UpdateWorldTrackerSize();
	elseif(m_isUnitListSizeDirty)then
		UpdateUnitListSize();
	end
end

-- ===========================================================================
function OnLoadGameViewStateDone()
	m_isDirty =true;
	OnDirtyCheck();
end

-- ===========================================================================
function OnChatPanelContainerSizeChanged()
	LuaEvents.WorldTracker_ChatContainerSizeChanged(Controls.ChatPanelContainer:GetSizeY());
end

-- ===========================================================================
-- FOR OVERRIDE
-- ===========================================================================
function GetMinimapPadding()
	return MINIMAP_PADDING;
end

function GetTopBarPadding()
	return TOPBAR_PADDING;
end

-- ===========================================================================
function Subscribe()
	Events.CityInitialized.Add(OnCityInitialized);
	Events.BuildingChanged.Add(OnBuildingChanged);
	Events.CivicChanged.Add(OnCivicChanged);
	Events.CivicCompleted.Add(OnCivicCompleted);
	Events.CultureYieldChanged.Add(OnCultureYieldChanged);
	Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
	Events.LocalPlayerTurnBegin.Add(OnLocalPlayerTurnBegin);
	Events.MultiplayerChat.Add( OnMultiplayerChat );
	Events.ResearchChanged.Add(OnResearchChanged);
	Events.ResearchCompleted.Add(OnResearchCompleted);
	Events.ResearchYieldChanged.Add(OnResearchYieldChanged);
	Events.GameCoreEventPublishComplete.Add( OnDirtyCheck ); --This event is raised directly after a series of gamecore events.
	Events.CityWorkerChanged.Add( OnUpdateDueToCity );
	Events.CityFocusChanged.Add( OnUpdateDueToCity );
	Events.UnitAddedToMap.Add( OnUnitAddedToMap );
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged ); -- Infixo
	Events.UnitCommandStarted.Add( OnUnitCommandStarted );
	Events.UnitMovementPointsChanged.Add( OnUnitMovementPointsChanged );
	Events.UnitOperationDeactivated.Add( OnUnitOperationDeactivated );
	Events.UnitOperationStarted.Add( OnUnitOperationStarted );
	Events.UnitRemovedFromMap.Add( OnUnitRemovedFromMap );
	Events.LoadGameViewStateDone.Add(OnLoadGameViewStateDone);

	LuaEvents.LaunchBar_Resize.Add(OnLaunchBarResized);
	
	LuaEvents.CivicChooser_ForceHideWorldTracker.Add(	OnForceHide );
	LuaEvents.CivicChooser_RestoreWorldTracker.Add(		OnForceShow);
	LuaEvents.EndGameMenu_StartObserverMode.Add(		OnStartObserverMode );
	LuaEvents.ResearchChooser_ForceHideWorldTracker.Add(OnForceHide);
	LuaEvents.ResearchChooser_RestoreWorldTracker.Add(	OnForceShow);
	LuaEvents.Tutorial_ForceHideWorldTracker.Add(		OnForceHide);
	LuaEvents.Tutorial_RestoreWorldTracker.Add(			Tutorial_ShowFullTracker);
	LuaEvents.Tutorial_EndTutorialRestrictions.Add(		Tutorial_ShowTrackerOptions);
	LuaEvents.TutorialGoals_Showing.Add(				OnTutorialGoalsShowing );
	LuaEvents.TutorialGoals_Hiding.Add(					OnTutorialGoalsHiding );
	LuaEvents.WorldTracker_OnSetMinimapCollapsed.Add(	OnSetMinimapCollapsed );
end

-- ===========================================================================
function Unsubscribe()
	Events.CityInitialized.Remove(OnCityInitialized);
	Events.BuildingChanged.Remove(OnBuildingChanged);
	Events.CivicChanged.Remove(OnCivicChanged);
	Events.CivicCompleted.Remove(OnCivicCompleted);
	Events.CultureYieldChanged.Remove(OnCultureYieldChanged);
	Events.InterfaceModeChanged.Remove( OnInterfaceModeChanged );
	Events.LocalPlayerTurnBegin.Remove(OnLocalPlayerTurnBegin);
	Events.MultiplayerChat.Remove( OnMultiplayerChat );
	Events.ResearchChanged.Remove(OnResearchChanged);
	Events.ResearchCompleted.Remove(OnResearchCompleted);
	Events.ResearchYieldChanged.Remove(OnResearchYieldChanged);
	Events.GameCoreEventPublishComplete.Remove( OnDirtyCheck ); --This event is raised directly after a series of gamecore events.
	Events.CityWorkerChanged.Remove( OnUpdateDueToCity );
	Events.CityFocusChanged.Remove( OnUpdateDueToCity );
	Events.UnitAddedToMap.Remove( OnUnitAddedToMap );
	Events.UnitSelectionChanged.Remove( OnUnitSelectionChanged ); -- Infixo
	Events.UnitCommandStarted.Remove( OnUnitCommandStarted );
	Events.UnitMovementPointsChanged.Remove( OnUnitMovementPointsChanged );
	Events.UnitOperationDeactivated.Remove( OnUnitOperationDeactivated );
	Events.UnitOperationStarted.Remove( OnUnitOperationStarted );
	Events.UnitRemovedFromMap.Remove( OnUnitRemovedFromMap );
	Events.LoadGameViewStateDone.Remove(OnLoadGameViewStateDone);

	LuaEvents.LaunchBar_Resize.Remove(OnLaunchBarResized);
	
	LuaEvents.CivicChooser_ForceHideWorldTracker.Remove(	OnForceHide );
	LuaEvents.CivicChooser_RestoreWorldTracker.Remove(		OnForceShow);
	LuaEvents.EndGameMenu_StartObserverMode.Remove(			OnStartObserverMode );
	LuaEvents.ResearchChooser_ForceHideWorldTracker.Remove(	OnForceHide);
	LuaEvents.ResearchChooser_RestoreWorldTracker.Remove(	OnForceShow);
	LuaEvents.Tutorial_ForceHideWorldTracker.Remove(		OnForceHide);
	LuaEvents.Tutorial_RestoreWorldTracker.Remove(			Tutorial_ShowFullTracker);
	LuaEvents.Tutorial_EndTutorialRestrictions.Remove(		Tutorial_ShowTrackerOptions);
	LuaEvents.TutorialGoals_Showing.Remove(					OnTutorialGoalsShowing );
	LuaEvents.TutorialGoals_Hiding.Remove(					OnTutorialGoalsHiding );
	LuaEvents.WorldTracker_OnSetMinimapCollapsed.Remove(	OnSetMinimapCollapsed );
end

-- ===========================================================================
function LateInitialize()

	Subscribe();

	-- InitChatPanel
	if(UI.HasFeature("Chat") 
		and (GameConfiguration.IsNetworkMultiplayer() or GameConfiguration.IsPlayByCloud()) ) then
		UpdateChatPanel(false);
	else
		UpdateChatPanel(true);
		Controls.ChatButton:SetHide(true);
	end

	UpdateUnreadChatMsgs();
	AttachDynamicUI();
	UpdateWorldTrackerSize();
end

-- ===========================================================================
function Initialize()
	
	if not GameCapabilities.HasCapability("CAPABILITY_WORLD_TRACKER") then
		ContextPtr:SetHide(true);
		return;
	end

	ContextPtr:SetRefreshHandler( OnRefresh );	
	
	m_CachedModifiers = TechAndCivicSupport_BuildCivicModifierCache();

	-- Create semi-dynamic instances; hack: change parent back to self for ordering:
	ContextPtr:BuildInstanceForControl( "ResearchInstance", m_researchInstance, Controls.WorldTrackerVerticalContainer );
	ContextPtr:BuildInstanceForControl( "CivicInstance",	m_civicsInstance,	Controls.WorldTrackerVerticalContainer );
	Controls.OtherContainer:ChangeParent( Controls.WorldTrackerVerticalContainer );
	ContextPtr:BuildInstanceForControl( "UnitListInstance", m_unitListInstance, Controls.WorldTrackerVerticalContainer );
	
	m_researchInstance.IconButton:RegisterCallback(	Mouse.eLClick,	function() LuaEvents.WorldTracker_OpenChooseResearch(); end);
	m_civicsInstance.IconButton:RegisterCallback(	Mouse.eLClick,	function() LuaEvents.WorldTracker_OpenChooseCivic(); end);
	
	m_unitEntryIM = InstanceManager:new( "UnitListEntry", "Button", m_unitListInstance.UnitStack);

	Controls.ChatPanelContainer:ChangeParent( Controls.WorldTrackerVerticalContainer );
	Controls.TutorialGoals:ChangeParent( Controls.WorldTrackerVerticalContainer );	
	
	-- Hot-reload events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);
	
	Controls.ToggleAllButton:SetCheck(true);

	Controls.ChatButton:RegisterCallback( Mouse.eLClick, function() UpdateChatPanel(not m_hideChat);
																			   StartUnitListSizeUpdate();
																			   --CheckEnoughRoom();
																			   end);
	Controls.CivicsButton:RegisterCallback(	Mouse.eLClick, function() UpdateCivicsPanel(not m_hideCivics);
																			   StartUnitListSizeUpdate();
																			   --CheckEnoughRoom();
																			   end);
	Controls.ResearchButton:RegisterCallback( Mouse.eLClick, function() UpdateResearchPanel(not m_hideResearch);
																			   StartUnitListSizeUpdate();
																			   --CheckEnoughRoom();
																			   end);
	Controls.CivilianListButton:RegisterCallback( Mouse.eLClick,
		function()
			if not m_hideUnitList and m_isUnitListMilitary then m_hideUnitList = true; end -- showing military units -> change to civilian -> simulate "hidden"
			m_isUnitListMilitary = false;
			m_unitListInstance.TraderCheck:SetHide(false);
			UpdateUnitListPanel(not m_hideUnitList); 
			StartUnitListSizeUpdate();
			--CheckEnoughRoom();
		end);
	Controls.MilitaryListButton:RegisterCallback( Mouse.eLClick,
		function()
			if not m_hideUnitList and not m_isUnitListMilitary then m_hideUnitList = true; end -- showing civilian units -> change to military -> simulate "hidden"
			m_isUnitListMilitary = true;
			m_unitListInstance.TraderCheck:SetHide(true);
			UpdateUnitListPanel(not m_hideUnitList);
			StartUnitListSizeUpdate();
			--CheckEnoughRoom();
		end);
	m_unitListInstance.CloseButton:RegisterCallback( Mouse.eLClick,
		function()
			m_hideUnitList = true;
			UpdateUnitListPanel(m_hideUnitList);
			StartUnitListSizeUpdate();
			--CheckEnoughRoom();
		end);
	m_unitListInstance.TraderCheck:SetCheck(m_showTrader);
	m_unitListInstance.TraderCheck:RegisterCheckHandler(
		function()
			m_showTrader = not m_showTrader;
			m_unitListInstance.TraderCheck:SetCheck(m_showTrader);
			UpdateUnitListPanel(m_hideUnitList);
			StartUnitListSizeUpdate();
			--CheckEnoughRoom();
		end);
	Controls.ToggleAllButton:RegisterCheckHandler( function() ToggleAll(not Controls.ToggleAllButton:IsChecked()) end);
	--Controls.ToggleDropdownButton:RegisterCallback(	Mouse.eLClick, ToggleDropdown); -- Infixo: dropdown removed
	Controls.WorldTrackerAlpha:RegisterEndCallback( OnWorldTrackerAnimationFinished );
	m_unitListInstance.UnitsSearchBox:RegisterStringChangedCallback( OnUnitListSearch );
	Controls.ChatPanelContainer:RegisterSizeChanged(OnChatPanelContainerSizeChanged);
end
Initialize();

print("Loaded WorldTracker.lua from Better World Tracker Units");