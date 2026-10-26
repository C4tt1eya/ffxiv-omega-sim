-- Acquisition points lie on the observed boss-to-holder segment, inside the
-- arena. No target assignment or native collision/damage is changed here.
local T={}
function T.pickup(startPoint,endPoint,center)
 -- Native spline begins at Z=295, above NPC centres (~177). Intersect near
 -- its low end, not the high boss end; otherwise XY overlap cannot pick up.
 return {X=startPoint.X+(endPoint.X-startPoint.X)*0.96,
         Y=startPoint.Y+(endPoint.Y-startPoint.Y)*0.96,Z=center.Z}
end
function T.intercept(boss,holder,center)
 local dx,dy=holder.X-boss.X,holder.Y-boss.Y
 local length=math.sqrt(dx*dx+dy*dy);assert(length>1,'Degenerate tether')
 local along=math.min(850,length*0.65)
 local p={X=boss.X+dx/length*along,Y=boss.Y+dy/length*along,Z=center.Z}
 -- A holder near the rim can make the first point too far out. Move farther
 -- along the same line, so the NPC still physically intersects the tether.
 for i=1,20 do
  if (p.X-center.X)^2+(p.Y-center.Y)^2<=1850^2 then return p end
  along=math.min(length*0.95,along+80)
  p.X=boss.X+dx/length*along;p.Y=boss.Y+dy/length*along
 end
 return p
end
return T
