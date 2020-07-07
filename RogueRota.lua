local EnergyTickTime = 0;
local LastTickEnergy = 100
local GCD_ID = 0;
local CD_ID = 0;
local Feint_ID = 0;
local Vanish_ID = 0;
local printCounter = 0;

local frameEnergyObserver = CreateFrame("Frame", "EnergyObserver", UIParent);
local buffTool = CreateFrame("GameTooltip", "buffTool", UIParent, "GameTooltipTemplate");
frameEnergyObserver:RegisterEvent("UNIT_ENERGY");
frameEnergyObserver:RegisterEvent("PLAYER_ENTERING_WORLD");
	
function TimeUntilNextEnergyTick()
	return 2-math.mod((GetTime()-EnergyTickTime),2);
end

local function ComboToSND(cp)
	if(cp == 1) then
		return (13.05);
	elseif(cp == 2) then
		return (17.40);
	elseif(cp == 3) then
		return (21.75);
	elseif(cp == 4) then
		return (26.10);
	elseif(cp == 5) then
		return (30.45);
	else
		return 0;
	end
end

local function BuffInfo(name)
    for i=0,64,1 do
        buffTool:SetOwner(UIParent, "ANCHOR_NONE");
        buffTool:ClearLines();
		local index = GetPlayerBuff(i, "HELPFUL|HARMFUL|PASSIVE");
        buffTool:SetPlayerBuff(index);
        local buff = buffToolTextLeft1:GetText();
        if (not buff) then break end
        if (buff == name) then return true, GetPlayerBuffTimeLeft(index) end
        buffTool:Hide();
    end
    return false, 0;
end

local function GetThreat()
	local userThreat = klhtm.table.raiddata[UnitName('player')]
	local data, playerCount, threat100 = KLHTM_GetRaidData()
	local threat = 0
	if userThreat == nil then
		userThreat = 0
	end
	if threat100 == 0 then
		threat = 0
	else
		threat = math.floor(userThreat * 100 / threat100 + 0.5)
	end
	return threat;
end

local function FindSpellID(spellname)
	local s=1; 
	while(true) do 
		local n=GetSpellName(s,"spell"); 
		if not(n) then break; end; 
		if (n==spellname) then return s; end
		s=s+1; 
	end;
end

local function GetItemIDPosition(name)
	for b=0,4 do 
		for s=1,18 do 
			local n = GetContainerItemLink(b,s);
			if n and string.find(n,name) then 
				return b, s;
			end;
		end
	end;
end

local function MobTargetList()
	local players = {};
	local myTarget = ObjectPointer("target");
	if not myTarget then 
		players[table.getn(players)+1] = UnitName("player");
		return players 
	end;
	local g_type;
	local g_size;
	if GetNumRaidMembers() > 0 then
		g_type = "raid";
		g_size = GetNumRaidMembers();
	elseif GetNumPartyMembers() > 0 then
		players[table.getn(players)+1] = UnitName("player");
		g_type = "party";
		g_size = GetNumPartyMembers();
	else
		players[table.getn(players)+1] = UnitName("player");
		return players 
	end
	for i=1,g_size,1 do
		local playerTarget = ObjectPointer(g_type..tostring(i).."target");
		if (playerTarget and myTarget == playerTarget) then
			players[table.getn(players)+1] = UnitName(g_type..tostring(i));
		end
	end
	return players;
end

local function TimeToAttack(mainHandAttackLeft, mainHandSpeed)
	local bestMoment;
	local normalSpeed = (mainHandSpeed/2);
	local superSpeed = (normalSpeed/2);
	if (superSpeed > 0.2) then
		bestMoment = superSpeed;
	else
		bestMoment = normalSpeed;
	end
	if (mainHandAttackLeft >= (mainHandSpeed-bestMoment)) then
		return 1;
	end
end

local function TicksToEnergy2(startEnergy, endEnergy)
	local tickRate = 20;
	if (startEnergy >= endEnergy) then return 0; end
	local aActive, aTimeLeft = BuffInfo("Adrenaline Rush");
	if (aActive) then tickRate = (tickRate*2) end;
	local toLKEnergy = endEnergy-startEnergy;
	local ceilTicks = ceil((toLKEnergy/tickRate));
	if (aActive) then
		local adrenaTicks = ceil((aTimeLeft/2));
		if(adrenaTicks < ceilTicks) then
			local lowerEnergy = toLKEnergy-(tickRate*adrenaTicks);
			local lowerTicks = ceil((lowerEnergy/20));
			ceilTicks = (adrenaTicks+lowerTicks);
		end
	end
	local totalWait;
	if (ceilTicks == 1) then
		totalWait = TimeUntilNextEnergyTick();
	else
		totalWait = TimeUntilNextEnergyTick()+(2*(ceilTicks-1));
	end
	return totalWait;
end

function RogueRotaAR()
	local GCD = GetSpellCooldown(GCD_ID,"BOOKTYPE_SPELL");
	printCounter = printCounter + 1;
	if (GCD == 0) then
		local _, va_cd = GetSpellCooldown(Vanish_ID,"BOOKTYPE_SPELL");
		local tLevel = UnitLevel("target") or 0;
		if(va_cd == 0 and tLevel == -1 and GetThreat() > 85) then
			CastSpellByName("Vanish");
			return;
		elseif(tLevel == -1 and va_cd ~= 0 and GetThreat() > 95) then
			local z,u = GetItemIDPosition("Limited Invulnerability Potion");
			if(z and u) then
				local _, isUseable = GetContainerItemCooldown(z, u);
				if(isUseable == 0) then
					UseContainerItem(z, u);
					return;
				end
			end
		end
		local sliceActive, sliceTimeLeft = BuffInfo("Slice and Dice");
		local holyActive, holyTimeLeft = BuffInfo("Holy Strength");
		local adrenaActive, adrenaTimeLeft = BuffInfo("Adrenaline Rush");
		local escActive, escTimeLeft = BuffInfo("Essence of the Red");
		local cmbPoints = GetComboPoints("player");
		local tickRate = 20;
		if (adrenaActive == true) then tickRate = tickRate*2; end
		local health = MobHealth_GetTargetCurHP() or 999999;
		local healthMax = MobHealth_GetTargetMaxHP() or 999999;
		local mainHandAttackLeft = VGAB_MH_landsAt;
		local mainHandSpeed = VGAB_MH_speed;
		local _, _, latency = GetNetStats();
		if not latency then latency = 35; end
		latency = (latency/1000);
		local inputTime = 0.75;
		local tPrediction = (1+inputTime+latency);
		local evisAmount = 35;
		local sndAmount = 25;
		local cEnergy = UnitMana("player");
		local cTime = GetTime();
		local tickTimeLeft = TimeUntilNextEnergyTick();
		if (mainHandAttackLeft > 0) then
			mainHandAttackLeft = (VGAB_MH_landsAt-cTime);
		end
		if (GCD > 0) then
			GCD = 1-(cTime-GCD);
		end
		local dpsList = 0;
		local playerList = MobTargetList();
		for k=1,table.getn(playerList),1 do
			for x=1, table.getn(DamageMeters_tables[DMT_ACTIVE]), 1 do
				if (DamageMeters_tables[DMT_ACTIVE][x]["player"] == playerList[k] and (DamageMeters_tables[DMT_ACTIVE][x]["lastTime"] == 0 or (cTime-DamageMeters_tables[DMT_ACTIVE][x]["lastTime"]) <= 5)) then
					dpsList = dpsList + DamageMeters_tables[DMT_ACTIVE][x]["dmiData"][1]["q"];
					break;
				end
			end
		end
		local currentFightTime = DamageMeters_combatEndTime - DamageMeters_combatStartTime;
		local targetDPS;
		if (dpsList > 0) then
			targetDPS = (dpsList/currentFightTime);
		else
			targetDPS = 1; -- DEBUG
		end
		if printCounter >= 100 then
			print("FightTime: " .. tostring(ceil((health/targetDPS))) .. " - Total DPS: " .. tostring(targetDPS));
			printCounter = 0;
		end
		local attackFlag = TimeToAttack(mainHandAttackLeft, mainHandSpeed);
		local fightTimeSeconds = (health/targetDPS);
		local perfectPredict = ((TicksToEnergy2(cEnergy,(evisAmount+40+sndAmount)))+(tPrediction*2));
		if(cmbPoints < 5) then
			if ((cmbPoints >= 3 and fightTimeSeconds < (tPrediction*3)) or (cmbPoints >= 2 and fightTimeSeconds < tPrediction*2)) then
				CastSpellByName("Eviscerate")
			elseif (cmbPoints >= 1 and (sliceTimeLeft <= tPrediction+(tPrediction*(cmbPoints*0.15))) and fightTimeSeconds >= (tPrediction*4)) then
				CastSpellByName("Slice and Dice")
			elseif (attackFlag or (holyActive == true and holyTimeLeft <= tPrediction) or escActive == true or (fightTimeSeconds < (tPrediction*2.5)) or (cEnergy == 100 and ((holyActive == true and holyTimeLeft <= (tPrediction*2)) or cmbPoints >= 4 or (tickTimeLeft < tPrediction)))) then
				CastSpellByName("Sinister Strike")
			end
		else
			if (fightTimeSeconds >= (ComboToSND(5)-perfectPredict) and sliceTimeLeft <= ((tPrediction*2)-(2*inputTime))) then
				CastSpellByName("Slice and Dice");
			elseif (escActive == true or (holyActive == true and holyTimeLeft < (tPrediction*2)) or attackFlag or (cEnergy >= (75-tickRate) and tickTimeLeft <= tPrediction) or (fightTimeSeconds < (tPrediction*4)) or (fightTimeSeconds < (ComboToSND(5)-perfectPredict))) then
				CastSpellByName("Eviscerate");
			end
		end
	end
end

frameEnergyObserver:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then 
		EnergyTickTime = GetTime();
		GCD_ID = FindSpellID("Detect Traps");
		CD_ID = FindSpellID("Cold Blood");
		Feint_ID = FindSpellID("Feint");
		Vanish_ID = FindSpellID("Vanish");
	end;
	if event == "UNIT_ENERGY" and arg1 ~= nil and arg1 == "player" then
		local energyGain = 20;
		if (BuffInfo("Adrenaline Rush") == true) then energyGain = 2*energyGain; end
		local ftrEnergy = LastTickEnergy+energyGain;
		if (UnitMana("player") == ftrEnergy) then
			EnergyTickTime = GetTime();
		end
		LastTickEnergy = UnitMana("player");
	end
end)
