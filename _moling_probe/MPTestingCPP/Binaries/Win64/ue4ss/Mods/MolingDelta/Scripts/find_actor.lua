-- Resolve gameplay actors from the current world, not UE4SS's global object
-- search (which can also encounter actors from a recently unloaded level).
local engine
local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
local original=FindFirstOf
local retained={}
return function(className)
 local path
 if className=='BP_PlayerCharacter_C' then
  path='/Game/ThirdPersonBP/Blueprints/BP_PlayerCharacter.BP_PlayerCharacter_C'
 elseif className:match('^NPC_%w+_BP_C$') then
  local asset=className:gsub('_C$','')
  path='/Game/ThirdPersonBP/Blueprints/AI/'..asset..'.'..className
 elseif className=='1stController_C' or className=='2ndController_C' or className=='3rdController_C' then
  local asset=className:gsub('_C$','')
  path='/Game/MainScene/Omega_P5/'..asset..'.'..className
 else return original(className)end
 engine=engine or original('Engine')
 if not engine or not engine:IsValid()then return nil end
 local viewport=engine.GameViewport
 if not viewport or not viewport:IsValid()then return nil end
 local class=StaticFindObject(path)
 if not class or not class:IsValid()then return nil end
 -- The loader retains reflected field lookups across map travel. Keep the
 -- corresponding Blueprint class metadata alive in the persistent instance;
 -- never retain actors, widgets or worlds from a completed attempt.
 local instance=viewport.GameInstance
 if instance and instance:IsValid() and not retained[path]then
  local refs=instance.ReferencedObjects
  refs[refs:GetArrayNum()+1]=class
  retained[path]=true
 end
 return gameplay:GetActorOfClass(viewport,class)
end
