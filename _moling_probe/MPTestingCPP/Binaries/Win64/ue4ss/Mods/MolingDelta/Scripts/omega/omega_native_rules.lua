-- Native arrays preserve wave order, but may put either sex first in a wave.
-- The trigger table requires M1,F1,M2,F2. UE object suffixes are not FF14 IDs.
return function(rows)
 assert(#rows==4,'Expected four native clones')
 local result={}
 for wave=1,2 do
  local pair={}
  for i=wave*2-1,wave*2 do
   local row=rows[i];local sex=row.class:match('Omega([MF])_BP_')
   assert(sex and not pair[sex],'Missing/duplicate native clone sex')
   pair[sex]=row
  end
  for _,sex in ipairs({'M','F'})do
   local row=assert(pair[sex],'Incomplete native clone pair')
   result[#result+1]={id=4-#result,position=row.position,
    transformed=(row.class:find('_mid_',1,true)or row.class:find('_yuehuan_',1,true))and 1 or 0}
  end
 end
 return result
end
