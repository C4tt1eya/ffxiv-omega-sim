-- One role resolver for all three mechanics. Physical actors and their native
-- network/team IDs stay stable; the player swaps practice roles with one AI.
return function(root)
 local FindFirstOf=MolingFindActor
 local M={order={'MT','ST','H1','H2','D1','D2','D3','D4'},generation=0}
 local ranks={};for i,r in ipairs(M.order)do ranks[r]=i end
 local selected='D4'
 local saved=io.open(root..'player-role.txt','r')
 if saved then local r=saved:read('*a'):match('%w+');saved:close();if ranks[r]then selected=r end end
 local player,baseRole,hud,originals,roster,lookup
 local pending,wasPressed,roleLabel
 local function valid(a)return a and a:IsValid()end
 local function key(a)return a:GetFullName()end
 local function text(s)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(s)end
 local function busy()
  for _,cl in ipairs({'1stController_C','2ndController_C','3rdController_C'})do local a=FindFirstOf(cl);if valid(a)and a.IsActive then return true end end
  for _,name in ipairs({'MolingDelta','MolingSigma','MolingOmega'})do local api=_G[name];if api and api.getState()then return true end end
  return false
 end
 function M.role(a)
  if lookup then return lookup[key(a)]end
 end
 function M.current()return selected end
 function M.actors()return roster end
 function M.isBusy()return busy()end
 local function labels()
  if not valid(hud)then return end
  for _,name in ipairs({'一运','P5二运前半img','P5三运前半img'})do if hud[name]:GetVisibility()~=1 then hud[name]:SetVisibility(1)end end
  if valid(roleLabel)and roleLabel:GetText():ToString()~=selected then roleLabel:SetText(text(selected))end
  hud.skill_empty:SetToolTipText(text('操控职能：'..selected..'\n点击依次切换；Alt+1—8直选 MT/ST/H1/H2/D1/D2/D3/D4\n仅机制未开始时可切换'))
  local names={};for _,a in ipairs(roster or{})do
   names[a.TeamNumber]=a.Name
   -- OnRep_Name does not update the already-created MateName widget on NPCs.
   -- Update the actual visible nameplate, including after native refreshes.
   local component=a:GetClass():GetFullName():find('/AI/',1,true)and a.MateNameUI or a.UMG_Name
   if valid(component)then
    local plate=component:GetWidget()
    if valid(plate)and valid(plate.Name_1)and plate.Name_1:GetText():ToString()~=a.Name:ToString()then plate.Name_1:SetText(a.Name)end
   end
  end
  local list=hud.UMG_TeamList
  if valid(list)and valid(list.TeamList_V)then
   for i=0,list.TeamList_V:GetChildrenCount()-1 do
    local row=list.TeamList_V:GetChildAt(i);local name=names[row.PlayerId]
    if name then row.PlayerName=name;row.TextBlock_Name:SetText(name)end
   end
   list.IDs:ForEach(function(i,w)local name=names[w:get()];if name then list.NameList[i]=name end end)
  end
 end
 local function apply(r,reset)
  local before=lookup
  local previous=before and before[key(player)]or baseRole
  selected=r;lookup={}
  for _,a in ipairs(roster)do
   local old=originals[key(a)]
   local current=before and before[key(a)]or old.role
   -- Swap with the AI currently holding the requested role. Repeated changes
   -- must pass the player's immediately previous role to that same AI.
   local role=key(a)==key(player)and selected or(current==selected and previous or current)
   lookup[key(a)]=role
   local name=key(a)==key(player)and(old.name..' ['..selected..']')or role
   a.Name=text(name);a:OnRep_Name()
   local max=(role=='MT'or role=='ST')and 100000 or 20000
   local ratio=a.MaxHP>0 and a.HP/a.MaxHP or 1
   a.MaxHP=max;a.HP=math.min(max,math.max(0,ratio*max))
   if reset then
    a:ClearMark();a.HelloWorld=0;a.DiveEnegy=0;a.HurtHeavily=false
    for n=0,4 do a:RemoveBUFF(n)end
   end
  end
  M.generation=M.generation+1;labels()
 end
 function M.select(r)
  if not ranks[r]then return false,'invalid role'end
  if not roster then return false,'party unavailable'end
  if busy()then return false,'mechanic active'end
  if r==selected then return true end
  apply(r,true)
  local f=io.open(root..'player-role.txt','w');if f then f:write(r..'\n');f:close()end
  print('[MolingRoles] Player role='..r..'\n')
  return true
 end
 local function attachUI()
  local bar=hud.SkillBar1
  if M.ui then for _,owner in ipairs(M.ui.owners)do if valid(owner)then owner:RemoveFromParent()end end end
  local buttons={bar:GetChildAt(0),hud['P5一运'],hud['P5二运前半'],hud['P5三运前半'],hud.skill_empty,
   hud['P5二运HW'],hud['P5三运HW'],hud.skill_7,hud.skill_8,hud.skill_9,hud.skill_10,hud.skill_11}
  bar:ClearChildren()
  for _,button in ipairs(buttons)do bar:AddChildToHorizontalBox(button)end
  local owners={}
  local function label(button,value,size)
   -- Use the engine widget factory and an initialized native text template.
   -- Keep its owner in the HUD tree so garbage collection retains the font
   -- and widget resources after moving the text into the actual button.
   local factory=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
   local owner=factory:Create(player,StaticFindObject('/Game/ThirdPersonBP/Blueprints/UI/UMG_CharacterState.UMG_CharacterState_C'),player:GetController())
   owners[#owners+1]=owner
   local w=owner.TextBlock_Name;w:RemoveFromParent()
   owner:SetVisibility(1);bar:GetParent():AddChild(owner)
   w:SetText(text(value))
   -- Set the font before attaching, when Slate first measures this text.
   w.Font.Size=size
   w:SetJustification(1);w:SetVisibility(3)
   w:SetShadowColorAndOpacity({R=0,G=0,B=0,A=1});w:SetShadowOffset({X=1,Y=1})
   button:SetContent(w)
   w.Slot:SetHorizontalAlignment(2);w.Slot:SetVerticalAlignment(2)
   w.Slot:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
   return w
  end
  local entries={}
  for i,pair in ipairs({{'P5一运','一运'},{'P5二运前半','P5二运前半img'},{'P5三运前半','P5三运前半img'}})do
   hud[pair[2]]:SetVisibility(1)
   entries[i]=label(hud[pair[1]],tostring(i),24)
  end
  hud.Dancekey:SetVisibility(1)
  roleLabel=label(hud.skill_empty,selected,18)
  M.ui={bar=bar,entries=entries,roleLabel=roleLabel,owners=owners}
  -- Preserve twelve equal slots, with all unused buttons after the entries.
  for i=0,bar:GetChildrenCount()-1 do
   local button=bar:GetChildAt(i)
   button:SetVisibility(0);button.Slot:SetSize({SizeRule=1,Value=1})
  end
  for _,name in ipairs({'P5二运HW','P5三运HW','skill_7','skill_8','skill_9','skill_10','skill_11'})do hud[name]:SetIsEnabled(false)end
 end
 -- Map restart destroys the old HUD and roster. Drop wrappers without
 -- asking destroyed objects for their names, flags, widgets or properties.
 function M.resetWorld()
  player=nil;baseRole=nil;hud=nil;originals=nil;roster=nil;lookup=nil
  pending=nil;wasPressed=nil;roleLabel=nil;M.ui=nil
  M.generation=M.generation+1
 end
 function M.tick()
  local p=FindFirstOf('BP_PlayerCharacter_C');if not valid(p)or not valid(p.PlayerUIRef)then return end
  local changed=not valid(player)or key(player)~=key(p)
  if not changed and roster then for _,a in ipairs(roster)do if not valid(a)then changed=true;break end end end
  if changed or not roster then
   if busy()then return end
   local actors,seen={},{}
   for _,r in ipairs(M.order)do local a=FindFirstOf('NPC_'..r..'_BP_C');if valid(a)then actors[#actors+1]=a;seen[r]=true end end
   if #actors~=7 then return end
   for _,r in ipairs(M.order)do if not seen[r]then baseRole=r end end
   player=p;actors[#actors+1]=p;roster=actors;originals={};lookup=nil
   for _,a in ipairs(actors)do originals[key(a)]={role=a:GetClass():GetFullName():match('NPC_(%w+)_BP_C')or baseRole,name=a.Name:ToString():gsub(' %[%w+%]$','')}end
   hud=p.PlayerUIRef;attachUI();apply(selected,false)
  end
  if key(hud)~=key(p.PlayerUIRef)then hud=p.PlayerUIRef;attachUI();labels()end
  local active=busy();hud.skill_empty:SetIsEnabled(not active)
  local pressed=hud.skill_empty:IsPressed()
  if pressed and not wasPressed then pending=M.order[ranks[selected]%8+1]end
  wasPressed=pressed
  if pending then local r=pending;pending=nil;M.select(r)end
  -- Native team-list refresh can rebuild rows. Update names, never health, here.
  labels()
 end
 for i,k in ipairs({'ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT'})do
  local role=M.order[i]
  RegisterKeyBindAsync(Key[k],{ModifierKey.ALT},function()pending=role end)
 end
 _G.MolingRoles=M
 return M
end
