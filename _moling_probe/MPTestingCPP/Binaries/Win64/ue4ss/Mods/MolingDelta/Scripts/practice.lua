-- Local practice preferences. Marker IDs match the simulator's zero-based IDs.
-- This file stores preferences only; mechanic adapters own assignment changes.
return function(root)
 local M={}
 local rules=dofile(root..'practice_rules.lua')
 local stages={'delta','sigma_front','sigma_hw'}
 local definitions={
  delta={title='一运'},
  sigma_front={title='二运前半'},
  sigma_hw={title='二运后半'},
 }
 local names={[0]='攻击1',[1]='攻击2',[2]='攻击3',[3]='攻击4',[5]='锁链1',[6]='锁链2',[7]='锁链3',[8]='禁止1',[9]='禁止2',[10]='圆圈'}
 for _,stage in ipairs(stages)do definitions[stage].marks=rules.choices[stage]end
 local choices={delta='random',sigma_front='random',sigma_hw='random'}
 local showDeltaIdle=true
 local smallMonitor=false
 local phase='delta'
 local lastPhase,startRequested
 local starting=false
 local panelOpen=true
 local inP5=false
 local hud,labels,pressed,resetRequested,buttons
 local function valid(a)return a and a:IsValid()end
 local function text(s)return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(s)end
 local function active()
  local roles=_G.MolingRoles
  return starting or (roles and roles.isBusy()) or false
 end
 local function accepts(stage,value)
  local d=definitions[stage];if not d then return false end
  if value=='random'then return true end
  return type(value)=='number'and value~=rules.random and rules.valid(stage,value)
 end
 -- Never execute a local settings file. Three stage IDs (-1 means random),
 -- then 0/1 for Delta idle marks and small-monitor practice. Accept older files.
 local saved=io.open(root..'practice-settings.txt','r')
 if saved then
  local value=saved:read(129)or'';saved:close()
  local a,b,c,idle,monitor=value:match('^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$')
  if not a then a,b,c,idle=value:match('^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$')end
  if not a then a,b,c=value:match('^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$')end
  if #value<=128 and a then
   local values={tonumber(a),tonumber(b),tonumber(c)};local visibility=idle and tonumber(idle)or 1
   local target=monitor and tonumber(monitor)or 0
   local ok=(visibility==0 or visibility==1)and(target==0 or target==1)
   for i,stage in ipairs(stages)do
    if values[i]==-1 then values[i]='random'end
    if not accepts(stage,values[i])then ok=false end
   end
   if ok then
    for i,stage in ipairs(stages)do choices[stage]=values[i]end
    showDeltaIdle=visibility==1
    smallMonitor=target==1
    if smallMonitor and type(choices.delta)=='number' and choices.delta<=3 then choices.delta='random'end
   end
  end
 end
 local function persist()
  local f=io.open(root..'practice-settings.txt','w')
  if not f then print('[MolingPractice] Could not save practice preferences\n');return end
  for _,stage in ipairs(stages)do f:write(tostring(choices[stage]=='random'and -1 or choices[stage])..'\n')end
  f:write(showDeltaIdle and'1\n'or'0\n')
  f:write(smallMonitor and'1\n'or'0\n')
  f:close()
 end
 function M.choice(stage)return choices[stage]end
 function M.setScope(value)
  inP5=value==true
  if not inP5 then resetRequested=nil;startRequested=nil;starting=false end
 end
 function M.selectedPhase()return phase end
 function M.lastPhase()return lastPhase end
 function M.isStarting()return starting end
 function M.setStarting(value)
  if not inP5 then return false,'outside P5'end
  if type(value)~='boolean'then return false,'invalid starting state'end
  starting=value;return true
 end
 function M.selectPhase(value)
  if not inP5 then return false,'outside P5'end
  if value~='delta'and value~='sigma'and value~='omega'then return false,'invalid phase'end
  if active()then return false,'mechanic active'end
  phase=value;return true
 end
 function M.markStarted(value)
  if not inP5 then return false,'outside P5'end
  if value~='delta'and value~='sigma'and value~='omega'then return false,'invalid phase'end
  starting=false;lastPhase=value;phase=value;panelOpen=false;return true
 end
 function M.requestStart()
  if not inP5 then return false,'outside P5'end
  if active()then return false,'mechanic active'end
  startRequested=phase;return true
 end
 function M.consumeStart()local result=startRequested;startRequested=nil;return result end
 function M.panelOpen()return panelOpen end
 function M.setPanelOpen(value)
  if not inP5 then return false,'outside P5'end
  if type(value)~='boolean'then return false,'invalid panel visibility'end
  panelOpen=value;return true
 end
 function M.snapshot()
  return {delta=choices.delta,sigma_front=choices.sigma_front,sigma_hw=choices.sigma_hw,show_delta_idle=showDeltaIdle,small_monitor=smallMonitor}
 end
 function M.idleMarks()return showDeltaIdle end
 function M.smallMonitor()return smallMonitor end
 function M.selectSmallMonitor(value)
  if not inP5 then return false,'outside P5'end
  if type(value)~='boolean'then return false,'invalid small monitor setting'end
  if active()then return false,'mechanic active'end
  if smallMonitor~=value then
   smallMonitor=value
   if value and type(choices.delta)=='number' and choices.delta<=3 then choices.delta='random'end
   persist()
  end
  return true
 end
 function M.selectIdleMarks(value)
  if not inP5 then return false,'outside P5'end
  if type(value)~='boolean'then return false,'invalid idle marker visibility'end
  if active()then return false,'mechanic active'end
  if showDeltaIdle~=value then showDeltaIdle=value;persist()end
  return true
 end
 function M.select(stage,value)
  if not inP5 then return false,'outside P5'end
  if not accepts(stage,value)then return false,'invalid practice marker'end
  if active()then return false,'mechanic active'end
  if stage=='delta' and smallMonitor and type(value)=='number' and value<=3 then return false,'small monitor requires a blue tether'end
  if choices[stage]~=value then choices[stage]=value;persist()end
  return true
 end
 function M.requestReset(mode)
  if not inP5 then return false,'outside P5'end
  mode=mode or'restart'
  if mode~='restart'and mode~='prepare'then return false,'invalid reset mode'end
  resetRequested=(mode=='restart'and lastPhase)and'restart'or'prepare'
  panelOpen=resetRequested=='prepare'
  return true
 end
 function M.consumeReset()
  local requested=resetRequested;resetRequested=nil;return requested
 end
 local picker,canvas,backdrop,blur,actions,captions,visible,enabled,colors
 local phaseNames={delta='一运',sigma='二运',omega='三运'}
 local roleOrder={'MT','ST','H1','H2','D1','D2','D3','D4'}
 local function choiceName(value)return value=='random'and'随机'or names[value]end
 function M.attachUI(player,newHud,label)
  if valid(canvas)then canvas:RemoveFromParent()end
  hud=newHud;labels={};pressed={};buttons={};actions={};captions={};visible={};enabled={};colors={};picker=nil
  local tree=hud.WidgetTree;local rootWidget=tree.RootWidget
  local factory=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  local canvasClass=StaticFindObject('/Script/UMG.CanvasPanel')
  local buttonClass=StaticFindObject('/Script/UMG.Button')
  local borderClass=StaticFindObject('/Script/UMG.Border')
  local blurClass=StaticFindObject('/Script/UMG.BackgroundBlur')
  assert(valid(tree)and valid(rootWidget)and valid(canvasClass)and valid(buttonClass)and valid(borderClass)and valid(blurClass),'Practice panel factory unavailable')
  -- The shipped HUD's root is a canvas. Use the engine's reflected object
  -- factory: the UE4SS direct constructor crashes on this UE 5.1 build.
  canvas=factory:SpawnObject(canvasClass,tree);assert(valid(canvas),'Could not construct practice canvas')
  rootWidget:AddChildToCanvas(canvas)
  canvas.Slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
  canvas.Slot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0});canvas.Slot:SetZOrder(500)
  canvas:SetVisibility(4) -- children remain hit-testable; empty canvas does not block the game
  local function position(w,x,y,width,height,z)
   canvas:AddChildToCanvas(w)
   local slot=w.Slot
   slot:SetAnchors({Minimum={X=0.5,Y=0},Maximum={X=0.5,Y=0}})
   slot:SetPosition({X=x,Y=y});slot:SetSize({X=width,Y=height});slot:SetZOrder(z or 1)
  end
  -- Draw the panel from Slate rounded rectangles, not stretched game textures.
  -- The blur is a separate non-interactive layer underneath the translucent tint.
  blur=factory:SpawnObject(blurClass,tree);assert(valid(blur),'Could not construct practice blur')
  position(blur,-380,62,760,470,0)
  blur:SetBlurStrength(7);blur:SetCornerRadius({X=10,Y=10,Z=10,W=10});blur:SetVisibility(3)
  backdrop=factory:SpawnObject(borderClass,tree);assert(valid(backdrop),'Could not construct practice backdrop')
  local panelBrush=backdrop.Background
  panelBrush.DrawAs=4 -- ESlateBrushDrawType::RoundedBox
  panelBrush.OutlineSettings.RoundingType=0 -- fixed corner radius
  panelBrush.OutlineSettings.CornerRadii={X=10,Y=10,Z=10,W=10}
  panelBrush.OutlineSettings.Width=0
  backdrop:SetBrush(panelBrush)
  position(backdrop,-380,62,760,470,1)
  backdrop:SetBrushColor({R=0.025,G=0.038,B=0.055,A=0.84});backdrop:SetVisibility(3)
  -- The live marking widget owns the simulator's ordered SlateBrushAsset
  -- array. Resolve through the current world; do not retain it across travel.
  -- If the widget or an asset is unavailable, leave a fully usable text label.
  local function markAsset(mark)
   local ok,asset=pcall(function()
    local component=player.UMG_Marking
    if not valid(component)then return nil end
    local marking=component:GetWidget()
    if not valid(marking)or marking.Asset:GetArrayNum()<=mark then return nil end
    local value=marking.Asset[mark+1]
    return valid(value)and value or nil
   end)
   return ok and asset or nil
  end
  local function attachMarkIcon(button,captionWidget,asset)
   local horizontalClass=StaticFindObject('/Script/UMG.HorizontalBox')
   local imageClass=StaticFindObject('/Script/UMG.Image')
   local sizeClass=StaticFindObject('/Script/UMG.SizeBox')
   if not valid(horizontalClass)or not valid(imageClass)or not valid(sizeClass)then return end
   local ok=pcall(function()
    local row=factory:SpawnObject(horizontalClass,tree)
    local box=factory:SpawnObject(sizeClass,tree)
    local icon=factory:SpawnObject(imageClass,tree)
    assert(valid(row)and valid(box)and valid(icon),'Could not construct marker icon')
    icon:SetBrushFromAsset(asset);icon:SetVisibility(3)
    box:SetWidthOverride(18);box:SetHeightOverride(18);box:SetContent(icon);box:SetVisibility(4)
    captionWidget:RemoveFromParent();button:SetContent(row)
    row.Slot:SetHorizontalAlignment(2);row.Slot:SetVerticalAlignment(2);row:SetVisibility(4)
    row:AddChildToHorizontalBox(box)
    box.Slot:SetVerticalAlignment(2);box.Slot:SetPadding({Left=0,Top=0,Right=4,Bottom=0})
    row:AddChildToHorizontalBox(captionWidget)
    captionWidget.Slot:SetVerticalAlignment(2)
   end)
   if not ok then
    -- Restore the original text-only button if icon construction failed.
    captionWidget:RemoveFromParent();button:SetContent(captionWidget)
    captionWidget.Slot:SetHorizontalAlignment(2);captionWidget.Slot:SetVerticalAlignment(2)
   end
  end
  local function add(id,caption,x,y,width,height,action,size,marker)
   local w=factory:SpawnObject(buttonClass,tree);assert(valid(w),'Could not construct practice button')
   -- A freshly constructed UButton has no texture resource. Give all four
   -- states a fixed radius, then tint them independently of text length.
   local style=w.WidgetStyle
   for _,state in ipairs({'Normal','Hovered','Pressed','Disabled'})do
    local brush=style[state]
    brush.DrawAs=4
    brush.OutlineSettings.RoundingType=0
    brush.OutlineSettings.CornerRadii={X=6,Y=6,Z=6,W=6}
    brush.OutlineSettings.Width=0
    local value=state=='Pressed'and 0.72 or(state=='Hovered'and 1.0 or(state=='Disabled'and 0.70 or 0.88))
    brush.TintColor.SpecifiedColor={R=value,G=value,B=value,A=1}
   end
   w:SetStyle(style);position(w,x,y,width,height,2)
   buttons[id]=w;actions[id]=action;labels[id]=label(w,caption,size or 16);captions[id]=caption
   if type(marker)=='number'then
    local asset=markAsset(marker)
    if asset then attachMarkIcon(w,labels[id],asset)end
   end
  end
  add('summary','P5 练习',-380,12,385,38,nil,14)
  add('open','设置',15,12,90,38,function()M.setPanelOpen(not panelOpen);picker=nil end)
  add('restart','重开 F5',115,12,120,38,function()M.requestReset('restart')end)
  add('header','P5 练习准备',-354,78,590,42,nil,20)
  add('close','关闭',254,78,95,42,function()M.setPanelOpen(false);picker=nil end)
  for i,value in ipairs({'delta','sigma','omega'})do
   local stage=value
   add('phase_'..stage,phaseNames[stage],-354,139+(i-1)*51,130,42,function()M.selectPhase(stage);picker=nil end,17)
  end
  add('role_select','操控职能',-195,139,385,42,function()picker=picker=='role'and nil or'role'end)
  add('choice_delta','一运点名',-195,192,475,42,function()picker=picker=='delta'and nil or'delta'end)
  add('choice_sigma_front','前半点名',-195,192,475,42,function()picker=picker=='sigma_front'and nil or'sigma_front'end)
  add('choice_sigma_hw','后半点名',-195,245,475,42,function()picker=picker=='sigma_hw'and nil or'sigma_hw'end)
  add('idle','一运禁标',-195,245,475,42,function()M.selectIdleMarks(not showDeltaIdle)end)
  add('small_monitor','小电视点名',-195,298,475,42,function()M.selectSmallMonitor(not smallMonitor)end)
  add('picker_heading','请选择',-195,245,350,38,nil)
  add('picker_back','返回',185,245,95,38,function()picker=nil end)
  for i,value in ipairs(roleOrder)do
   local role=value
   add('role_'..role,role,-195+((i-1)%4)*120,295+math.floor((i-1)/4)*48,110,40,function()
    local roles=_G.MolingRoles;if roles and roles.select then roles.select(role)end;picker=nil
   end,17)
  end
  for _,stage in ipairs(stages)do
   local selectedStage=stage;local options={'random'}
   for _,id in ipairs(definitions[stage].marks)do options[#options+1]=id end
   for i,value in ipairs(options)do
    local marker=value;local id=selectedStage..'_'..tostring(marker)
    add(id,choiceName(marker),-195+((i-1)%5)*96,295+math.floor((i-1)/5)*48,88,40,function()
     M.select(selectedStage,marker);picker=nil
    end,15,marker)
   end
  end
  add('help','',-195,408,475,38,nil,14)
  add('prepare','返回准备',-195,469,145,42,function()M.requestReset('prepare')end)
  add('start','开始练习',90,469,190,42,function()M.requestStart()end,18)
  M.ui={buttons=buttons,canvas=canvas,backdrop=backdrop,blur=blur,bar=hud.SkillBar1}
  -- The first native skill is intentionally preserved. Keep all twelve
  -- equal-width slots so it retains its original size and horizontal position;
  -- hidden placeholders occupy the old practice/phase controls' slots.
  local bar=hud.SkillBar1;local first=bar:GetChildAt(0)
  assert(valid(first),'Missing native first skill')
  for _,field in ipairs({'P5一运','P5二运前半','P5三运前半','P5二运HW','P5三运HW','skill_empty','skill_7','skill_8','skill_9','skill_10','skill_11'})do
   hud[field]:SetIsEnabled(false)
  end
  bar:ClearChildren();bar:AddChildToHorizontalBox(first)
  first.Slot:SetSize({SizeRule=1,Value=1})
  for i=1,11 do
   local placeholder=factory:SpawnObject(buttonClass,tree);assert(valid(placeholder),'Could not construct skill-bar placeholder')
   bar:AddChildToHorizontalBox(placeholder);placeholder.Slot:SetSize({SizeRule=1,Value=1})
   placeholder:SetIsEnabled(false);placeholder:SetVisibility(2)
  end
 end
 function M.resetWorld()
  -- Map reload invalidates all UObject wrappers but keeps the preferences.
  hud=nil;labels=nil;pressed=nil;buttons=nil;canvas=nil;backdrop=nil;blur=nil;actions=nil;captions=nil;visible=nil;enabled=nil;colors=nil;picker=nil;M.ui=nil;resetRequested=nil;startRequested=nil;starting=false;inP5=false
 end
 function M.tick(player,currentHud)
  if not inP5 then return end
  if not valid(player)or not valid(currentHud)or not labels or not valid(hud)then return end
  if hud:GetFullName()~=currentHud:GetFullName()then return end
  local busy=active();local roles=_G.MolingRoles;local role=roles and roles.current()or'--'
  if busy then picker=nil end
  local function show(id,value,canPress)
   local w=buttons[id];local visibility=value and 0 or 1
   if visible[id]~=visibility then w:SetVisibility(visibility);visible[id]=visibility end
   local accept=value and canPress or false
   if enabled[id]~=accept then w:SetIsEnabled(accept);enabled[id]=accept end
  end
  local function caption(id,value)
   if captions[id]~=value then labels[id]:SetText(text(value));captions[id]=value end
  end
  local palette={
   neutral={R=0.10,G=0.15,B=0.20,A=0.82}, selected={R=0.16,G=0.38,B=0.41,A=0.96},
   primary={R=0.13,G=0.44,B=0.39,A=1}, muted={R=0.04,G=0.06,B=0.08,A=0.58},
  }
  local function tint(id,name)
   if colors[id]~=name then buttons[id]:SetBackgroundColor(palette[name]);colors[id]=name end
  end
  for id in pairs(buttons)do
   local tone=(id=='start'and'primary')or((id=='summary'or id=='header'or id=='help'or id=='picker_heading')and'muted')or'neutral'
   for _,value in ipairs({'delta','sigma','omega'})do if id=='phase_'..value and phase==value then tone='selected'end end
   if id=='role_'..role then tone='selected'end
   if id=='small_monitor'and smallMonitor then tone='selected'end
   for _,stage in ipairs(stages)do if id==stage..'_'..tostring(choices[stage])then tone='selected'end end
   tint(id,tone)
  end
  local summary='P5 '..phaseNames[phase]..'  ·  '..role
  if phase=='delta'then summary=summary..'  ·  '..choiceName(choices.delta)..(smallMonitor and'  ·  小电视'or'')
  elseif phase=='sigma'then summary=summary..'  ·  前：'..choiceName(choices.sigma_front)..'  后：'..choiceName(choices.sigma_hw)end
  caption('summary',summary);show('summary',true,false)
  caption('open',panelOpen and'收起'or'设置');show('open',true,true);show('restart',true,true)
  backdrop:SetVisibility(panelOpen and 3 or 1);blur:SetVisibility(panelOpen and 3 or 1)
  caption('header',starting and'正在启动 · 设置只读'or(busy and'练习进行中 · 设置只读'or('P5 '..phaseNames[phase]..' · 练习准备')))
  show('header',panelOpen,false);show('close',panelOpen,true)
  for _,value in ipairs({'delta','sigma','omega'})do
   local id='phase_'..value
   caption(id,(phase==value and'▶  'or'')..phaseNames[value]);show(id,panelOpen,not busy)
  end
  caption('role_select','操控职能：'..role..'  [选择]');show('role_select',panelOpen,not busy)
  for _,stage in ipairs(stages)do
   local id='choice_'..stage
   local onPage=stage=='delta'and phase=='delta'or(stage~='delta'and phase=='sigma')
   -- The chooser occupies the same vertical space as the HW row.
   local itemVisible=panelOpen and onPage and not picker
   caption(id,definitions[stage].title..'点名：'..choiceName(choices[stage])..'  [选择]')
   show(id,itemVisible,not busy)
  end
  caption('idle','一运禁止1/2标记：'..(showDeltaIdle and'开启'or'关闭'))
  show('idle',panelOpen and phase=='delta'and not picker,not busy)
  caption('small_monitor',(smallMonitor and'[✓] 'or'[ ] ')..'自己获得小电视点名')
  show('small_monitor',panelOpen and phase=='delta'and not picker,not busy)
  local heading=picker=='role'and'选择职能：坦克 / 治疗 / 输出'or(picker=='delta'and smallMonitor and'小电视只可搭配蓝线点名'or(picker and('选择'..definitions[picker].title..'点名')or''))
  caption('picker_heading',heading);show('picker_heading',panelOpen and picker~=nil,false)
  show('picker_back',panelOpen and picker~=nil,not busy)
  for _,r in ipairs(roleOrder)do
   local id='role_'..r;caption(id,(role==r and'✓ 'or'')..r)
   show(id,panelOpen and picker=='role',not busy)
  end
  for _,stage in ipairs(stages)do
   local options={'random'};for _,id in ipairs(definitions[stage].marks)do options[#options+1]=id end
   for _,value in ipairs(options)do
    local id=stage..'_'..tostring(value)
    caption(id,(choices[stage]==value and'✓ 'or'')..choiceName(value))
    local compatible=not(stage=='delta'and smallMonitor and type(value)=='number'and value<=3)
    show(id,panelOpen and picker==stage,not busy and compatible)
   end
  end
  local help=phase=='delta'and(smallMonitor and'小电视限定蓝线；随机点名会从蓝线中选择'or'禁止1/2分别对应锁链1/2的连线伙伴') or(phase=='sigma'and'前半结束后自动进入后半；两段点名独立' or'三运保留现有练习功能')
  if starting then help='正在等待练习启动；可重置或返回准备'
  elseif busy then help='机制进行中，请重置后更改设置'end
  caption('help',help);show('help',panelOpen and not picker,false)
  show('prepare',panelOpen and busy,true)
  caption('start','开始'..phaseNames[phase]);show('start',panelOpen,not busy)
  for id,action in pairs(actions)do
   local down=buttons[id]:IsPressed()
   if down and not pressed[id]and visible[id]==0 and enabled[id]then action()end
   pressed[id]=down
  end
 end
 RegisterKeyBindAsync(Key.F5,function()M.requestReset()end)
 _G.MolingPractice=M
 return M
end
