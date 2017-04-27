pico-8 cartridge // http://www.pico-8.com
version 9
__lua__
-- circuits
-- by codekitchen

allow_devmode=true
layer = {
  bg = 1,
  main = 2,
  player = 3,
  fg = 4,
  max = 4,
}

function merge(dest, src)
  for k, v in pairs(src or {}) do
    dest[k] = copy(v)
  end
  return dest
end
function concat(dest, src)
  for i=1,#src do
    dest[1+#dest]=src[i]
  end
end

function copy(o, t)
  if type(o) == 'table' then
    if (o.clone) return o:clone()
    local c=merge({}, o)
    if (t) merge(c, t)
    return c
  else
    return o
  end
end

vector = {}
vector.__index = vector
function vector.new(o)
  if (not o) return vector.zero
  merge(o, { x = (o.x or o[1]), y = (o.y or o[2]) })
  setmetatable(o, vector)
  return o
end
v=vector.new
vector.zero=v{0,0}
function vector.__add(a, b)
  if (type(b) == "number") return v{ b + a.x, b + a.y }
  if (type(a) == "number") return b+a
  return v{ a.x + b.x, a.y + b.y }
end
function vector.__sub(a, b)
  if (type(b) == "number") return v{ a.x - b, a.y - b }
  return v{ a.x - b.x, a.y - b.y }
end
-- scalar or cross product
function vector.__mul(a, b)
  if (type(b) == "number") return v{ a.x * b, a.y * b }
  if (type(a) == "number") return b*a
  return a.x * b.x + a.y * b.y
end
function vector.__eq(a, b)
  return a.x == b.x and a.y == b.y
end
function vector:clone()
  return self
end
function vector:length()
  local d = max(abs(self.x),abs(self.y))
  local n = min(abs(self.x),abs(self.y)) / d
  return sqrt(n*n + 1) * d
end
function vector:normalize()
  local len = self:length()
  return v{ self.x / len, self.y / len }
end
function vector:overlap(p1, p2)
  return self.x >= p1.x and self.x <= p2.x and self.y >= p1.y and self.y <= p2.y
end
function vector:str()
  return "{" .. self.x .. "," .. self.y .. "}"
end
function vector:world_to_room()
  return v{ flr(self.x/128), flr(self.y/128) }
end
function vector:world_to_tile()
  return v{ flr(self.x/8), flr(self.y/8) }
end
north = v{  0, -1, id=1 }
west  = v{ -1,  0, id=2, horiz=true }
south = v{  0,  1, id=3 }
east  = v{  1,  0, id=4, horiz=true }
id_to_dir={north, west, south, east}
dirs={north=north,west=west,south=south,east=east}
function vector:turn_left()
  return id_to_dir[(self.id%4)+1]
end
function vector:turn_right()
  return id_to_dir[(self.id+2)%4+1]
end
function vector:about_face()
  return id_to_dir[(self.id+1)%4+1]
end
if allow_devmode then
  function vector:dset(idx)
    dset(idx,self.x) dset(idx+1,self.y)
  end
  function vector.dget(idx)
    return v{dget(idx),dget(idx+1)}
  end
end

object={
  copy=copy,
  new=function(class, ...)
    local o=class:copy()
    o:initialize(...)
    return o
  end,
  initialize=function(self) end,
}

all_actors={}
actor=object:copy({
  initialize=function(self,pos,args)
    self.pos=pos
    if (args) merge(self, args)
    self:setroom()
    add(all_actors,self)
  end,
  start=function(self) end,
  reset=function(self) end,
  delete=function(self)
    if (self.room) del(self.room.actors, self)
    del(all_actors,self)
  end,
  pos=vector.zero,
  roompos=function(self)
    return self.pos-roomcoords
  end,
  spr=1,
  w=1,
  h=1,
  layer=layer.main,
  blocked_flag=0,
  actor_update=function(self)
    if (not self.started) self:start() self.started=true
    self:update()
  end,
  update=function(self) end,
  draw=function(self)
    if (self.hide) return
    local w,h=flr(self.w),flr(self.h)
    spr(self.spr, self.pos.x - w*4, self.pos.y - h*4, w, h, self.flipx, self.flipy)
  end,
  touching=function(self,other)
    local x=self.pos.x - other.pos.x
    local y=self.pos.y - other.pos.y
    return abs(x) < (self.w*4 + other.w*4) and abs(y) < (self.h*4 + other.h*4)
  end,
  touch=function(self,other) end,
  move=function(self,dist,speed)
    speed=speed or 1
    local newpos=self.pos+dist*speed
    if (not self:walkable(newpos)) newpos=self.pos+dist
    local o={w=self.w,h=self.h,pos=newpos}
    for a in all(self.room.actors) do
      if (a != self and a:touching(o)) a:touch(self)
    end
    if self:walkable(newpos) then
      self.pos=newpos
      self:setroom()
      return true
    end
  end,
  stuck=function(self)
    return not self:walkable(self.pos)
  end,
  walkable=function(self,pos)
    if (self.player and devmode) return true
    -- assumes actor of size 1 for now
    return world:walkable(self, pos+v{-3,2}) and world:walkable(self, pos+v{2,-3}) and world:walkable(self, pos+v{-3,-3}) and world:walkable(self, pos+v{2,2})
  end,
  setroom=function(self)
    local r=getroom(self.pos:world_to_room())
    if (r == self.room) return
    if (self.room) del(self.room.actors, self)
    self.room=r
    add(self.room.actors, self)
    self:room_switched()
  end,
  room_switched=function(self)
  end,
})

function update_actors()
  -- update in all rooms, not just current
  for a in all(all_actors) do
    a:actor_update()
  end
end

function draw_actors()
  for l=1,layer.max do
    for a in all(current_room.actors) do
      if (a.layer == l) a:draw()
    end
  end
end

tick=0
tickframes=8
wire_color=7
conn_color=6
powered_color=9
component_color=4
text_color=7
connflash_color=8
connflash=0
connflash_time=20
connection=object:copy({
  cposs={v{0, -3}, v{-3, 0}, v{0, 3}, v{3, 0}},
  offs={v{-2, -4}, v{-4, -2}, v{-2, -3}, v{-3, -2}},
  initialize=function(self,x,y,args)
    self._pos=v{x,y}
    if (args) merge(self,args)
  end,
  add=function(self, owner)
    self.owner=owner
  end,
  connpos=function(self)
    return self._pos + self.owner.pos + self.cposs[self.facing.id]
  end,
  basepos=function(self)
    return self._pos + self.owner.pos
  end,
  draw=function(self)
    if (self.hidden) return
    local drawpos=self:basepos()+self.offs[self.facing.id]
    local dspr=self.spr+(self.facing.horiz and 2 or 0)
    pal(wire_color, self.powered and powered_color or (self.conn and conn_color or conn_color))
    if (self.conn) pal(3,7)
    if connflash>0 and connflash_check(self) then
      if ((flr(connflash/5))%2==1) pal(wire_color, connflash_color)
    end
    spr(dspr, drawpos.x, drawpos.y, 1, 1, self.facing==east, self.facing==south)
    pal()
  end,
  can_solder=function(self)
    return not self.locked and self.conn == nil and not self.hidden
  end,
})
input=connection:copy({
  type='input',
  input=true,
  spr=1,
  facing=south,
})
output=connection:copy({
  type='output',
  output=true,
  spr=2,
  -- offs={v{-2, -4}, v{-4, -2}, v{-2, -3}, v{-3, -2}},
  facing=north,
})
function i(...) return input:new(...) end
function o(...) return output:new(...) end

wire=actor:copy({
  layer=layer.bg,
  a=v(),
  b=v(),
  powered=false,
  draw_type=1,
  initialize=function(self, a, b, ...)
    a.wire=self
    b.wire=self
    actor.initialize(self,a:connpos(),...)
    self.a=a
    self.b=b
  end,
  delete=function(self)
    if (self.a) self.a.wire=nil
    if (self.b) self.b.wire=nil
    actor.delete(self)
  end,
  draw=function(self)
    local c=self.powered and powered_color or wire_color
    local apos=self.a:connpos()
    local bpos=self.b:connpos()
    wire.draw_types[self.draw_type](apos, bpos, c)
  end,
  draw_types={
    function(apos, bpos, c)
      line(apos.x, apos.y, apos.x, bpos.y, c)
      line(apos.x, bpos.y, bpos.x, bpos.y, c)
    end,
    function(apos, bpos, c)
      line(apos.x, apos.y, bpos.x, apos.y, c)
      line(bpos.x, apos.y, bpos.x, bpos.y, c)
    end,
  }
})
component=actor:copy({
  spr=0,
  blocked_flag=7,
  connections={},
  powered=false,
  facing=south,
  cshow=true,
  initialize=function(self, ...)
    actor.initialize(self, ...)
    foreach(self.connections, function(c) c:add(self) end)
    self.c=self.connections[1]
    self.c2=self.connections[2]
    self.c3=self.connections[3]
    if (self.coffs) self.c._pos+=self.coffs
    if (self.cfacing) self.c.facing=self.cfacing
    if (not self.cshow) self.c.hidden=true
  end,
  draw=function(self)
    foreach(self.connections, function(c) c:draw() end)
    if (self.powered) pal(wire_color, powered_color) pal(component_color, powered_color)
    actor.draw(self)
    pal()
  end,
  tick=function(self)
  end,
  room_switched=function(self)
    for c in all(self.connections) do simulation:disconnect(c) end
  end,
})
types={}
types.arrow=actor:copy({
  draw=function(self)
    if (current_room.text[self.text][4]) return
    local dspr=self.facing.horiz and 36 or 35
    pal(7,text_color)
    spr(dspr, self.pos.x, self.pos.y, 1, 1, self.facing==east, self.facing==south)
    pal()
  end,
})
types.splitter=component:copy({
  movable=true,
  spr=0,
  connections={i(0,0),o(0,4,{facing=south}),o(0,2)},
  tick=function(self)
    self.powered=self.c.powered
    self.c2.powered=self.powered
    self.c3.powered=self.powered
  end,
})
gate=component:copy({
  movable=true,
  h=2,
  gate=true,
})
types.and_=gate:copy({
  spr=17,
  connections={i(-3,3),i(1,4),o(-1,-4)},
  tick=function(self)
    self.powered=self.c.powered and self.c2.powered
    self.c3.powered=self.powered
  end,
})
types.or_=gate:copy({
  spr=18,
  connections={i(-3,3),i(1,4),o(-1,-4)},
  tick=function(self)
    self.powered=self.c.powered or self.c2.powered
    self.c3.powered=self.powered
  end,
})
types.not_=gate:copy({
  spr=16,
  connections={i(-1,3),o(-1,-4)},
  tick=function(self)
    self.powered=self.c.conn and not self.c.powered
    self.c2.powered=self.powered
  end,
})
types.switch=component:copy({
  spr=48,
  connections={o(-1,-3)},
  tick=function(self)
    self.c.powered=self.powered
    self.spr=self.powered and 49 or 48
  end,
  interact=function(self)
    sfx(3)
    self.powered=not self.powered
    self.spr=self.powered and 49 or 48
  end,
})
types.relay=component:copy({
  connections={i(0,0),o(0,0)},
  initialize=function(self,...)
    component.initialize(self,...)
    self.c.facing=self.facing:about_face()
    self.c2.facing=self.facing
  end,
  tick=function(self)
    self.c2.powered=self.c.powered
  end,
})
types.empty_input=component:copy({
  connections={i(0,0)},
  tick=function(self)
    self.powered=self.c.powered
  end,
  reset=function(self)
    self.powered=false
    self.c.powered=false
  end,
})
types.empty_output=component:copy({
  connections={o(0,0)},
  cfacing=north,
  tick=function(self)
    self.c.powered=self.powered
  end,
})
types.timed=component:copy({
  connections={o(0,0)},
  timing={1,1},
  ticks=1,
  tick=function(self)
    self.ticks-=1
    if (self.ticks <= 0) self:switch()
    self.c.powered=self.powered
  end,
  switch=function(self)
    self.powered=not self.powered
    self.ticks=self.timing[self.powered and 1 or 2]
  end,
})
doorbase=component:copy({
  transition_tile=65,
  current=0,
  powered=nil,
  facing=west,
  opentile=0,
  initialize=function(self,...)
    component.initialize(self,...)
    self.walltile = self.facing.horiz and 72 or 87
  end,
  tick=function(self)
    local prev=self.open
    self.open=self.powered
    if (self.invert) self.open=not self.open
    if prev != self.open or self.current == self.transition_tile then
      self.current=self.open and self.opentile or self.walltile
      if (not prev and self.open and self.transition_tile) self.current=self.transition_tile
      self:set_tiles()
      if (player:stuck()) self.open=true self.current=self.opentile self:set_tiles()
    end
  end,
  set_tiles=function(self)
    for x=self.pos.x+self.doorway[1]*8,self.pos.x+self.doorway[3]*8,8 do
      for y=self.pos.y+self.doorway[2]*8,self.pos.y+self.doorway[4]*8,8 do
        world:tile_set(v({x,y}),self.current)
      end
    end
  end,
})
types.door=doorbase:copy({
  connections={i(0,0)},
  tick=function(self)
    self.powered=self.c.powered
    doorbase.tick(self)
  end,
})
types.energydoor=types.door:copy({
  spr=96,
  initialize=function(self,...)
    types.door.initialize(self,...)
    self.walltile = self.facing.horiz and 97 or 113
    if (not self.facing.horiz) self.spr=112
    self.flipy=self.facing==north
    self.flipx=self.facing==west
  end,
  draw=function(self)
    types.door.draw(self)
    if (self.current == self.transition_tile) pal(8,9) actor.draw(self)
    if (self.current == self.opentile) pal(8,6) actor.draw(self) pal() return
    if (self.current == self.transition_tile) pal(2,0) pal(8,9)
    local tile=self.walltile+(self.facing.id<3 and -1 or 1)*flr(tick/2)%4
    for x=self.pos.x+self.doorway[1]*8,self.pos.x+self.doorway[3]*8,8 do
      for y=self.pos.y+self.doorway[2]*8,self.pos.y+self.doorway[4]*8,8 do
        rectfill(x-4,y-4,x+3,y+3,0)
        spr(tile,x-4,y-4)
      end
    end
    pal()
  end,
})
key_colors={2,3,12,8,10,12}
types.keydoor=doorbase:copy({
  spr=21,
  w=1.2,
  h=1.2,
  layer=layer.bg,
  initialize=function(self,...)
    doorbase.initialize(self,...)
    self.opentile = self.facing.horiz and 81 or 82
    self.walltile = self.facing.horiz and 72 or 87
  end,
  start=function(self)
    if peek(cartdata_base+self.id)>0 then
      for a in all(all_actors) do
        if (a.key and a.id == self.id) self:powerup(a)
      end
    end
  end,
  reset_progress=function(self)
    poke(cartdata_base+self.id, 0)
  end,
  touch=function(self,other)
    local h=other.holding
    if h and h.key and h.id == self.id then
      self:powerup(h)  
      other:drop()
    end
  end,
  powerup=function(self,key)
    self.powered=true
    key.pos=self.pos
    key:setroom()
    poke(cartdata_base+self.id, 0xff)
  end,
  draw=function(self)
    pal(8, self.powered and 8 or key_colors[self.id])
    doorbase.draw(self)
    pal()
  end,
})
types.key=component:copy({
  key=true,
  movable=true,
  spr=5,
  blocked_flag=0,
  draw=function(self)
    pal(8, key_colors[self.id])
    component.draw(self)
    pal()
  end,
})
types.toggle=component:copy({
  movable=true,
  connections={i(-5,1),i(4,2),o(-4,-4),o(5,-3)},
  spr=19,
  w=2,
  active=1,
  tick=function(self)
    if (self.c.powered) self.active=1
    if (self.c2.powered) self.active=2
    self.c3.powered=self.active==1
    self.connections[4].powered=self.active==2
  end,
  reset=function(self)
    self.active=1
  end,
  draw=function(self)
    component.draw(self)
    local pos=self.pos-v{8,4}+v{1+9*(self.active-1),2}
    rectfill(pos.x, pos.y, pos.x+4, pos.y+3, 9)
  end,
})
types.button=component:copy({
  connections={o(4,-3,{facing=south,locked=true})},
  pressed=0,
  reset=-1,
  cshow=false,
  color=11,
  initialize=function(self,...)
    component.initialize(self,...)
    if (self.flipx) self.c._pos-=v({9,0})
    self:setspr()
  end,
  setspr=function(self)
    self.spr=self.pressed==0 and 58 or 59
  end,
  tick=function(self)
    if self.pressed>0 then
      self.pressed-=1
    end
    self.powered=self.pressed!=0
    if (self.invert) self.powered=not self.powered
    self.c.powered=self.powered
    self:setspr()
  end,
  interact=function(self,other)
    if (self.norobot and other.robot) return
    if (self.pressed==0) sfx(3)
    self.pressed=self.reset
    self:setspr()
  end,
  draw=function(self)
    pal(11,self.color)
    if (self.powered) pal(6,powered_color)
    component.draw(self)
    pal()
  end
})
types.robot_spawner=component:copy({
  connections={i(-8,0)},
  robot_id=1,
  tick=function(self)
    local waspowered=self.powered
    self.powered=self.c.powered
    if (not waspowered and self.powered) self:spawn()
  end,
  spawn=function(self)
    local robot
    for a in all(robots) do
      if (a.id == self.robot_id) robot=a
    end
    robot=robot or robotclass:new(self.pos,{id=self.robot_id})
    robot:spawned(self.pos)
  end,
})

bumper_color=7
robot_room_coords=v{0,512}
robots={}
robot_components={
  'toggle/90/84',
  'toggle/92/100',
  'or_/89/27',
  'and_/97/27',
  'and_/105/27',
  'not_/86/44',
  'not_/94/44',
  'or_/102/44',
  'splitter/20/20',
  'splitter/26/22',
  'splitter/32/20',
  'splitter/38/22',
  'and_/26/42',
  'and_/34/44',
  'or_/42/42',
}
robot_components_by_id={
  {1},
  {1,6,7},
  {1,3,6,7,8,9,10},
}
robot_components_by_id[0]={}
robotclass=component:copy({
  movable=true,
  robot=true,
  spr=10,
  bumpers={},
  thrusters={},
  id=1,
  smoke={},
  action2=function(self)
    self.player_pos=player.pos
    player.last_robot=self
    player:teleport(self.room_coords+v{26,108})
  end,
  view=function(self)
    world:view_room(self.robot_room)
  end,
  spawned=function(self,pos)
    self.pos=pos
    self:setroom()
    for a in all(self.actors) do a:reset() end
  end,
  initialize=function(self,...)
    component.initialize(self,...)
    add(robots,self)
    self.room_coords=robot_room_coords+v{self.id * 128, 0}
    local actors={
      'switch/19/95/cshow=false',
      -- always-on outputs
      'empty_output/82/112/powered=true',
      'empty_output/88/112/powered=true',
      'empty_output/94/112/powered=true',
      -- thrusters
      'empty_input/76/16/cfacing=south',
      'empty_input/16/51/cfacing=east',
      'empty_input/51/111/cfacing=north',
      'empty_input/111/76/cfacing=west',
    }
    if self.id>0 then
      concat(actors,{
        -- bumpers
        'empty_output/60/8/cfacing=south',
        'empty_output/8/67/cfacing=east',
        'empty_output/67/119/cfacing=north',
        'empty_output/119/60/cfacing=west',
      })
    end
    local cids=robot_components_by_id[self.id]
    if cids then
      for id in all(cids) do add(actors,robot_components[id]) end
    else
      concat(actors,robot_components)
    end
    local text={}
    local wires={}
    if self.id == 0 then
      text={
        {24,84,"power"},
        {30,106,"exit"},
        {26,44,"thrust"},
        {84,24,"thrust"},
        {88,64,"thrust"},
        {58,98,"thrust"},
      }
      concat(actors,{
        'arrow/17/81/facing=south/text=1',
        'arrow/24/106/facing=west/text=2',
        'arrow/20/44/facing=west/text=3',
        'arrow/78/24/facing=north/text=4',
        'arrow/95/70/facing=east/text=5',
        'arrow/52/95/facing=south/text=6',
      })
      wires={{2,1,6,1}}
    elseif self.id == 1 then
      text={
        {27,65,"bumper"},
        {65,22,"bumper"},
        {78,58,"bumper"},
        {72,102,"bumper"},
      }
      concat(actors,{
        'arrow/20/65/facing=west/text=1',
        'arrow/58/22/facing=north/text=2',
        'arrow/100/58/facing=east/text=3',
        'arrow/65/99/facing=south/text=4',
      })
      wires={split(
[[{9,1,13,1
{13,3,5,1
{13,2,11,1
{7,1,13,4]],'\n',true)}
    end
    self.robot_room=room:new(self.room_coords.x/128,self.room_coords.y/128,{ actors=actors, text=text, wires=wires })
    self.actors=self.robot_room.actors
    self.robot_room.robot=self
    for i=1,4 do
      self.thrusters[i]=self.actors[i+4]
      if (self.id>0) self.bumpers[i]=self.actors[i+8]
    end
    self.switch=self.actors[1]
    self.switch.powered=true
  end,
  delete=function(self)
    notimplemented()
  end,
  bumper_offset={v{0,-5},v{-5,0},v{0,4},v{4,0}},
  thruster_offset={{v{0,-4},-.25},{v{-4,0},0},{v{0,4},.25},{v{4,0},.5}},
  update=function(self)
    if (player.pos:overlap(self.room_coords+v{16,108},self.room_coords+v{20,112})) player:teleport(self.player_pos)
    for i,b in pairs(self.bumpers) do
      local bumped=b.powered
      b.powered=not world:walkable(self, self.pos+self.bumper_offset[i])
      if (not bumped and b.powered) self.room:sfx(1)
    end
    if self:active() then
      local moved
      for i,t in pairs(self.thrusters) do  
        local offs=self.thruster_offset[i]
        local ang=rnd(.3)+.35
        if (t.powered) self:move(id_to_dir[i]:about_face()*.5) add(self.smoke,merge(self.pos+offs[1], {dx=cos(ang+offs[2]),dy=sin(ang+offs[2]),ticks=6})) moved=true
      end

      -- if (moved) self.room:sfx(2)

      for a in all(self.room.actors) do
        if (self:touching(a) and a.interact) self:interact_with(a)
      end
    end
    for s in all(self.smoke) do
      s.ticks-=1
      if (s.ticks <= 0) del(self.smoke, s)
      s.x+=s.dx
      s.y+=s.dy
    end
  end,
  active=function(self)
    return not player.room.robot and self.switch.powered and player.holding != self
  end,
  interact_with=function(self,other)
    other:interact(self)
  end,
  tick=function(self)
  end,
  draw=function(self)
    local pos=self.pos
    for s in all(self.smoke) do
      local color=s.ticks>2 and 7 or 10
      pset(s.x, s.y, color)
    end
    if (self.switch.powered) pal(5,10)
    component.draw(self)
    pal()
    self.draw_bumper(self.bumpers[1],pos.x-2,pos.y-5,pos.x+1,pos.y-5)
    self.draw_bumper(self.bumpers[2],pos.x-5,pos.y-2,pos.x-5,pos.y+1)
    self.draw_bumper(self.bumpers[3],pos.x-2,pos.y+4,pos.x+1,pos.y+4)
    self.draw_bumper(self.bumpers[4],pos.x+4,pos.y-2,pos.x+4,pos.y+1)
  end,
  draw_bumper=function(r,a,b,c,d)
    line(a,b,c,d,(r and r.powered or false) and powered_color or bumper_color)
  end,
  walkable=function(self,pos)
    -- todo: this is a hacky way to make the robot a little bigger
    return world:walkable(self, pos+v{-4,3}) and world:walkable(self, pos+v{3,-4}) and world:walkable(self, pos+v{-4,-4}) and world:walkable(self, pos+v{3,3})
  end,
})

simulation={
  tick=function(self)
    for a in all(all_actors) do
      if(a.tick) a:tick()
    end
    for a in all(all_actors) do
      for c in all(a.connections or {}) do
        if (c.input and not c.conn) c.powered=false
        if c.output then
          if (c.wire) c.wire.powered=c.powered
          if (c.conn) c.conn.powered=c.powered
        end
      end
    end
  end,
  connect=function(self, a, b, args)
    if (a.connections) a=a.connections[1]
    if (b.connections) b=b.connections[1]
    a.conn=b b.conn=a
    wire:new(a, b, args)
  end,
  disconnect=function(self, a)
    local b=a.conn
    if (a.wire) a.wire:delete()
    a.conn=nil
    if (b) b.conn=nil
  end,
}

function split(str,sep,parse,start)
  start=start or 1
  local l=#str+1
  for i=start,#str do
    if (sub(str,i,i)==sep) l=i break
  end
  local ss=sub(str,start,l-1)
  if (ss=='') return nil
  if (parse) ss=parse_val(ss)
  if (l>#str) return ss
  return ss, split(str,sep,parse,l+1)
end
function isnum(c) return c >= '0' and c <= '9' end
function parse_actor(str)
  local parts={split(str,'/')}
  local opts={}
  for i=4,#parts do
    local k,v=split(parts[i],'=')
    opts[k]=parse_val(v)
  end
  return {types[parts[1]],parts[2]+0,parts[3]+0,opts}
end
function parse_int(str) return str+0 end
function parse_val(val)
  if (dirs[val]) return dirs[val]
  local f=sub(val,1,1)
  if (isnum(f)) return val+0
  if (f=='t') return true
  if (f=='f') return false
  if (f=='{') return {split(val,',',true,2)}
  if (f=='v') return v{split(val,',',true,3)}
  return val
end

roomsidx={{},{},{},{},{},{}}
rooms={}
room=object:copy({
  initialize=function(self,x,y,args)
    self.coord=v{x,y}
    merge(self, args)
    add(rooms,self)
    roomsidx[y]=roomsidx[y] or {}
    roomsidx[y][x]=self
    self:create_actors()
  end,
  create_actors=function(self)
    local roomcoords=self.coord*128
    local actors=self.actors
    self.actors={}
    for x in all(actors) do
      x=parse_actor(x)
      x[1]:new(v{x[2]+roomcoords.x,x[3]+roomcoords.y},x[4])
      -- actor will add itself
    end
    for w in all(self.wires) do
      simulation:connect(self.actors[w[1]].connections[w[2]], self.actors[w[3]].connections[w[4]])
    end
  end,
  sfx=function(self,id)
    if (self == current_room) sfx(id)
  end,
})
function getroom(v)
  local r=(roomsidx[v.y] or {})[v.x]
  if (r) return r
  -- probably only useful in dev mode?
  return room:new(v.x, v.y, {})
end
function parse_room(str,opts)
  local coords,actors,wires=split(str,'|')
  flip() -- todo: this is fixing some sort of pico-8 timing bug, or maybe a gc issue, need to investigate/report
  local x,y=split(coords,',',true)
  room:new(x,y,merge({
    actors={split(actors,'\n')},
    wires={split(wires,'\n',true)},
  },opts))
end
function init_world()
cls()
print("loading...", 45, 60)
flip()
robotclass:new(v{0,0},{id=0})
parse_room([[1,0
|button/10/68/cshow=false/flipx=true/reset=2
door/60/51/doorway={1,0,5,0/cfacing=west/walltile=72
button/18/108/cshow=false/flipx=true/reset=2/color=6/norobot=true
robot_spawner/16/96/cfacing=west/robot_id=0/coffs=v{-2,0
energydoor/60/84/doorway={0,-3,0,-1/facing=north/cshow=false
|{1,1,2,1
{4,1,3,1
]],{
  text={
    {12,13,"hi, robot!\n\ncarry the robot with z\nclimb inside with x\nand you can rewire it!"},
    {12,13,"hold z+x to peek inside\nwhile the robot is moving", true},
  },
  update=function(self)
    for a in all(self.actors) do
      if (player.last_robot == a) self.text[1][4]=true self.text[2][4]=nil
    end
  end
})
parse_room([[1,1
|energydoor/20/84/facing=east/cfacing=south/coffs=v{1,3/doorway={1,0,3,0
button/10/116/flipx=true/reset=6
energydoor/92/52/facing=south/cfacing=west/doorway={0,1,0,2/coffs=v{-4,1
button/10/76/flipx=true
button/18/28/cshow=false/flipx=true/reset=2/color=6/norobot=true
robot_spawner/16/16/cfacing=west/robot_id=0/coffs=v{-2,0
button/118/16/cfacing=south/cshow=false/reset=5
energydoor/60/44/doorway={0,-4,0,-1/facing=north/cfacing=east/coffs=v{3,-2
key/113/73/id=1
keydoor/20/44/id=1/doorway={1,0,3,0
relay/7/108/facing=east
relay/7/68/facing=east
arrow/20/113/facing=west/text=1
arrow/20/66/facing=west/text=2
arrow/110/30/facing=south/text=3
|{11,1,2,1
{11,2,1,1
{12,1,4,1
{6,1,5,1
{7,1,8,1
]],{
  text={
    {20,113,"  press button with z"},
    {20,66,"  solder wires\n  with x",true},
    {74,26,"carry items\nwith z",true}
  },
  update=function(self)
    self.actors[1].c.locked=true
    if player:roompos().y<78 then
      self.text[2][4]=nil
      if (player:roompos().x>96) self.text[3][4]=nil
    end
  end
})
parse_room([[2,0
|button/118/20/reset=2
energydoor/92/60/doorway={1,0,3,0/facing=east/cfacing=north/coffs=v{1,-4/opentile=81
button/10/116/flipx=true/reset=2
energydoor/60/84/doorway={1,0,3,0/facing=east/cfacing=north/coffs=v{1,-4
toggle/54/28
key/56/112/id=2
relay/116/31/facing=south
relay/7/108/facing=east
|{1,1,7,1
{7,2,2,1
{8,1,3,1
{8,2,4,1
]],{
  text={
    {28,9,"\"flip-flop\" switch"},
    {12,52,"flips power\nfrom one output\nto the other"},
    {46,91,"one side is always\n           powered"},
  }
})
parse_room([[2,1
|keydoor/36/92/id=2/doorway={-3,0,-1,0
button/34/52/cshow=false/flipx=true/reset=2/color=6/norobot=true
robot_spawner/16/24/cfacing=west/robot_id=1/coffs=v{-2,0
button/118/112/cfacing=south/cshow=false
door/100/68/doorway={0,-2,0,-1/facing=north/coffs=v{0,-3
key/112/56/id=3
keydoor/124/36/id=3/doorway={0,-3,1,-1/facing=north
energydoor/60/68/doorway={1,0,2,0/facing=east/cshow=false
|{3,1,2,1
{4,1,5,1
]],{
  text={
    {36,16,"circuits\nby @codekitchen"},
    {24,11," robot bumpers detect\n when the robot\n is touching a wall",true}
  },
  update=function(self)
    if (player:roompos().y<84) self.text[1][4]=true self.text[2][4]=nil
  end
})
parse_room[[3,0
|button/110/116/reset=2/cshow=false/color=6/norobot=true
robot_spawner/112/104/cfacing=east/robot_id=2/coffs=v{17,0
button/54/28/cshow=false/cfacing=south/reset=2
splitter/10/8
energydoor/20/92/doorway={1,0,1,0/cfacing=west/facing=east
|{2,1,1,1
{3,1,4,1
{4,3,5,1
]]
parse_room([[3,1
|keydoor/116/92/id=4/doorway={-6,0,-1,0
keydoor/60/116/id=5/doorway={0,-2,0,-1/facing=north
and_/83/24
or_/83/48
not_/83/72
empty_output/50/88/cfacing=north/powered=true
empty_output/58/88/cfacing=north
keydoor/84/4/doorway={-2,-1,-1,1/facing=west/id=6
energydoor/28/68/doorway={0,1,0,2/facing=south/cfacing=north/coffs=v{0,-4
energydoor/36/68/doorway={0,1,0,2/facing=south/cfacing=north/coffs=v{0,-4
key/17/79/id=6
|
]],{
  text={
    {92,19,"\"and\"\ngate"},
    {92,43,"\"or\"\ngate"},
    {92,67,"\"not\"\ngate"},
    {16,14,"logic gates\noutput power\nbased on\ntheir inputs\n\npick up a gate\nfor more info"},
    {16,14,"and gates are\npowered when\nboth inputs\nare powered\n\ntry it out",true},
    {16,14,"or gates are\npowered when\neither input\nis powered\n\ntry it out",true},
    {16,14,"not gates are\npowered when\nthe input is\nnot powered\n\ntry it out",true},
    {67,113,"hold z to run"},
  },
  update=function(self)
    self.text[5][4]=player.holding != self.actors[3]
    self.text[6][4]=player.holding != self.actors[4]
    self.text[7][4]=player.holding != self.actors[5]
    if (player.holding and player.holding.gate) self.text[4][4]=true
  end
})
room:new(3,2,{
  text={{20,40,"under construction \130"}},
})
parse_room[[4,0
|button/10/12/reset=2/cshow=false/flipx=true/color=6/norobot=true
robot_spawner/24/16/robot_id=3/cfacing=north/coffs=v{7,-10
button/54/108
splitter/3/120
energydoor/36/36/doorway={0,-3,0,-1/cfacing=south/facing=north
key/103/119/id=4
|{1,1,2,1
{3,1,4,1
{4,2,5,1
]]
room:new(4,1,{
  text={{20,40,"under construction \130"}},
})
parse_room[[4,2
|button/110/68/reset=2/cshow=false/color=6/norobot=true
robot_spawner/112/56/robot_id=4/coffs=v{17,0/cfacing=east
button/26/68/flipx=true/cshow=false
door/59/94/doorway={0,1,0,3/cfacing=north/facing=south
energydoor/84/28/doorway={0,-1,0,-1/facing=north/cshow=false
|{2,1,1,1
{3,1,4,1
]]
end
world={ 
  tile_at=function(self, pos)
    return mget(pos.x/8, pos.y/8)
  end,
  tile_set=function(self, pos, tile)
    mset(pos.x/8, pos.y/8, tile)
  end,
  walkable=function(self, actor, pos)
    -- hacky robot room handling
    if pos.y >= 512 then
      pos.x = pos.x % 128
      pos.y = pos.y % 128
    end
    local tile=self:tile_at(pos)
    return not fget(tile, actor.blocked_flag)
  end,
  switch_rooms=function(self, newroom)
    current_room=newroom
    roomcoords=current_room.coord*128
  end,
  -- view a different room without switching to it
  view_room=function(self, room)
    self.viewing_room=room
  end,
  update=function(self)
    self.viewing_room=nil
    room_check()
    update_actors()
    if (connflash > 0) connflash-=1
    if (current_room and current_room.update) current_room:update()
  end,
  draw=function(self)
    local room=current_room
    if (self.viewing_room) self:switch_rooms(self.viewing_room)
    camera(roomcoords.x, roomcoords.y)
    self:draw_room()
    draw_actors()
    self:switch_rooms(room)
  end,
  draw_room=function(self)
    local mapcoords=current_room.robot and vector.zero or current_room.coord*16
    if (current_room.wallcolor) pal(12, current_room.wallcolor)
    map(mapcoords.x, mapcoords.y, roomcoords.x, roomcoords.y, 16, 16)
    pal()
    for t in all(current_room.text or {}) do
      if (not t[4]) print(t[3], t[1]+roomcoords.x, t[2]+roomcoords.y, text_color)
    end
  end,
}

solder_distance=5
devmode_playerpos=62
playerclass=actor:copy({
  spr=26,
  sprs={41,42,43,44,45},
  sprs={26, 27, 28, 29},
  sidx=1,
  swt=4,
  player=true,
  layer=layer.player,
  holding=nil,
  wire_type=1,
  btn4=0,
  btn5=0,
  solder_offsets={v{-5,0},v{4,0}},
  initialize=function(self,...)
    actor.initialize(self,...)
    if (devmode) self.pos=vector.dget(devmode_playerpos) self:setroom()
  end,
  update=function(self)
    local oldpos=self.pos
    self.didmove=false
    if (btn(4)) self.btn4+=1
    if (btn(5)) self.btn5+=1
    self:action_check()
    if (btn(0)) self:move(west)
    if (btn(1)) self:move(east)
    if (btn(2)) self:move(north)
    if (btn(3)) self:move(south)
    if self.didmove then
      self.swt-=1
      if (self.swt==0) self.sidx=(self.sidx%#self.sprs)+1 self.swt=4
      self.spr=self.sprs[self.sidx]
    end
    self.solder_pos=self.pos+self.solder_offsets[self.flipx and 2 or 1]
  end,
  move=function(self,dist)
    if (btn(5)) return
    self.didmove=true
    local speed=1
    local oldpos=self.pos
    if (self.btn4>3) speed=3 self.action_held=true
    actor.move(self,dist,speed)
    if self.holding then
      self.holding:move(self.pos-oldpos)
      if (not self:touching(self.holding)) self:drop()
    end
    self.pos:dset(devmode_playerpos)
    if (dist.horiz) self.flipx=dist==east
  end,
  teleport=function(self,pos)
    self:drop()
    self.pos=pos
    self:setroom()
  end,
  action_check=function(self)
    if not btn(4) and self.btn4 > 0 then
      if (not self.action_held) self:action1()
      self.btn4=0
    elseif not btn(5) and self.btn5 > 0 then
      if (not self.action_held) self:action2()
      self.btn5=0
    elseif self.btn4 > 2 and self.btn5 > 2 then
      self.action_held=true
      if (self.last_robot) self.last_robot:view()
    else
      self.action_held=false
    end
  end,
  action1=function(self)
    if self.solder_start then
      self.wire_type=(self.wire_type%#wire.draw_types)+1
    else
      self:pickup()
    end
  end,
  action2=function(self)
    if self.holding then
      if (self.holding.action2) self.holding:action2()
    else
      for a in all(self.room.actors) do
        if (a != self and self:touching(a) and a.action2) a:action2() return
      end
      self:solder()
    end
  end,
  pickup=function(self)
    if self.holding then
      self:drop()
    else
      for a in all(self.room.actors) do
        if self:touching(a) then
          if (a.movable) sfx(4) self.holding=a a.held_by=self
          if (a.interact) a:interact(self)
        end
      end
    end
  end,
  drop=function(self)
    if (self.holding) self.holding.held_by=nil sfx(5)
    self.holding=nil
  end,
  solder_start=nil,
  can_solder=function(a,b)
    return b:can_solder() and b.owner != a.owner and b.type != a.type
  end,
  solder=function(self)
    local target
    local solder_start=self.solder_start
    local closest=solder_distance+.1
    for a in all(self.room.actors) do
      for c in all(a.connections) do
        local d=(self.solder_pos-c:connpos()):length() 
        if (not (c.locked or (c.conn and c.conn.locked))) and d < closest then
          target=c closest=d
          break
        end
      end
    end
    if not target then
      if (solder_start) self.solder_start=nil return
    elseif not solder_start then
      if (target:can_solder()) self.solder_start=target sfx(6) return
      if (target.conn) simulation:disconnect(target) sfx(6) return
    else
      if self.can_solder(solder_start, target) then
        sfx(6)
        simulation:connect(solder_start, target, {draw_type=self.wire_type})
        self.solder_start=nil
        return
      end
    end
    -- nothing found, flash connections to signal player
    sfx(7)
    if not solder_start then
      connflash_check=function(c) return c:can_solder() end
    else
      connflash_check=function(c) return self.can_solder(solder_start, c) end
    end
    connflash=connflash_time
  end,
  room_switched=function(self)
    actor.room_switched(self)
    self.solder_start=nil
  end,
  draw=function(self)
    if self.solder_start then
      local apos=self.solder_start:connpos()
      local bpos=self.solder_pos
      wire.draw_types[self.wire_type](apos, bpos, wire_color)
    end
    actor.draw(self)
    if self.solder_start then
      local p=self.solder_pos-v{2,2}
      spr(46, p.x, p.y)
    end
  end,
})

cartdata_base=0x5e00

function _init()
  init_savedata()
  set_devmode()
  init_world()
  local start_pos=v{270,240}
  player=playerclass:new(start_pos)
end

function init_savedata()
  cartdata("codekitchen_circuits_v1")
  menuitem(5, "reset progress \130", function()
    for a in all(all_actors) do
      if (a.reset_progress) a:reset_progress()
    end
    run()
  end)
end

function _update()
  tick+=1
  world:update()
  if tick%tickframes==0 then
    simulation.tick()
  end
end

function room_check()
  if (player.room != current_room) world:switch_rooms(player.room)
end

function _draw()
  cls()
  if (not current_room) return
  world:draw()
  if (devmode) draw_dbg()
end

function draw_dbg()
  camera()
  print(player.pos:str()..current_room.coord:str()..player:roompos():str(),2,122,7)
end

function set_devmode()
  if (not allow_devmode) return
  devmode=peek(cartdata_base)>0
  menuitem(4, "devmode is "..(devmode and "on" or "off"), function() poke(cartdata_base, devmode and 0 or 1) set_devmode() end)
end

function dbg(str)
  if (devmode) printh(str, "debug")
end
__gfx__
000000000070000000700000000000000070000000000000000000000000000000000000cccccccc000660000000800000080000000000000000000000000000
000000000707000007070000070000000700000000888800000000000000000000000000cccccccc066666600000080000808000000000000000000000000000
000000000070000070707000707770007077700008886800005555555555555555555500cc0000cc066565600000808008080800000000000000000000000000
000000000070000000700000070000000700000008866880005400400040004004004500cc0000cc665656660000080880808080000000000000000000000000
00000000007000000070000000000000007000000866868000504040004000400404050000000000666565660000808000000000000000000000000000000000
00000000000000000000000000000000000000000888888000500555555555555550050000000000065656600000080000000000000000000000000000000000
00000000000000000000000000000000000000000098989000544500000000000054450000000000066666600000800000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500500000000000050050000000000000660000000000000000000000000000000000000000000
00000000000000000000000000000000000000000dddddd0005005000003300003330000660000000000000000000000000e0e00000e0e000000000000000000
0000000000000000000000004444444004444444d188881500500500003553003555330000600000000e0e00000e0e0000dddd0000dddd00000e0e0000000000
0000000000000000000000004666664004666664d85558150054450003a33a3035335a306660000000dddd0000dddd000a5a5ad00a5a5ad000dddd0000000000
0000000000000000000000004666664444666664d8555585005005000353353035333353000600000a5a5ad00a5a5ad00a5a5a400a5a5a400a5a5ad000000000
0004000000444000004440004666664444666664d8555585005005003533335335333353666600000a5a5a400a5a5a4094aaa40094aaa4000a5a5a4000000000
0004000004404400044044004666664004666664d8555585005005003533335335335a300000600094aaa40094aaa4000ddadd000ddadd0094aaa40000000000
0040400004000400040004004444444004444444d1989895005445003555555335553300666660000ddadd000ddadd0000400400004040000ddadd0000000000
00040000440004404400044000000000000000000555555000500500033333300333000000000600040040000400040000000000000000000040400000000000
00404000400000404000004000700000007000000000000000500500000000000050050000000000000000000222222002222220000000000020000000000000
040004004000004040040040077700000700000000000000005445000000000000544500022222200222222022f222f222f222f2022222200080000000000000
40000040400000404040404070707000777770000000000000500555555555555550050022f222f222f222f22f5fff5f2f5fff5f22f222f22808200000000000
4444444044444440440004400070000007000000000000000050404000800080040405002f5fff5f2f5fff5fffffffffffffffff2f5fff5f0080000000000000
000000000000000000000000007000000070000000000000005400400080008004004500ffffffffffffffff0ffffff00ffffff0ffffffff0020000000000000
0000000000000000000000000000000000000000000000000055555555555555555555000ffffff00ffffff006bbbbb606bbbbb60ffffff00000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000006bbbbb606bbbbb6000600600006060006bbbbb60000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000600600006000600000000000000000006006000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0dddd0000dddd000000000000000000000000000000000000000000000000000000000000000000000b000000000b00000000000000000000000000000000000
0d0000000d007000000000000000000000000000000000000000000000000000000000000000000000b000400000b04000000000000000000000000000000000
0d0000070d007000000000000000000000000000000000000000000000000000000000000000000000bbbb460000bb4600000000000000000000000000000000
0d0000700d007000000000000000000000000000000000000000000000000000000000000000000000bbbb460000bb4600000000000000000000000000000000
0d0007000d007000000000000000000000000000000000000000000000000000000000000000000000b000400000b04000000000000000000000000000000000
0ddd70000ddd7000000000000000000000000000000000000000000000000000000000000000000000b000000000b00000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
111111119999999900000000d11cc1150ddddddd0dddddd0dddcddd000000000dddddddd0000000011111115d111111100000000000000000000000000000000
111111119999999901010100d1cc1115d11ccc11d11cc115111c111500000000111111110000000011111115d111111100000000000000000000000000000000
111111119999999900101010dcc11115d1cc1cc1d111cc15111c111500000000111111110000000011111115d111111100000000000000000000000000000000
111111119999999901010100dc11ccccdcc111ccd1111cc5c11c11c500000000111111110000000011111115d111111100000000000000000000000000000000
111111119999999900101010dcc11115dc11c11ccccc11c5cc111cc500000000111111110000000011111115d111111100000000000000000000000000000000
111111119999999901010100d1cc1115d111c111d1111cc51cc1cc1500000000111111110000000011111115d111111100000000000000000000000000000000
111111119999999900101010d11cc115d111c111d111cc1511ccc11500000000111111110000000011111115d111111100000000000000000000000000000000
111111119999999900000000055555500555c555d11cc11555555550000000005555555500000000555555500555555500000000000000000000000000000000
000000000000000000033030dcc111150ddddddd0dddddd0dddcddd0d11111150000000000000000ddddddd00ddddddd00000000000000000000000000000000
000000000303030303033000dccc1115dcccccccd1111cc5111c1115d1111115000000000000000011111115d111111100000000000000000000000000000000
000000000000000000033030dcccc115dcccccccd111ccc5111c1115d1111115000000000007700011111115d111111100000000000000000000000000000000
000000003333333303033000dcccccccd1ccccc1d11cccc511ccc115d1111115000000000000700011111115d111111100000000000000000000000000000000
000000003333333300033030dcccc115d11ccc11ccccccc51ccccc15d1111115000000000000000011111115d111111100000000000000000000000000000000
000000000000000003033000dccc1115d111c111d11cccc5ccccccc5d1111115000000000000000011111115d111111100000000000000000000000000000000
000000003030303000033030dcc11115d111c111d111ccc5ccccccc5d1111115000000000000000011111115d111111100000000000000000000000000000000
000000000000000003033000055555500555c555d1111cc555555550d1111115000000000000000011111115d111111100000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000dddddd0d11111111111111100000000000000000000000000000000
000668888888888888888888888888888888888800000000000000000000000000000000d1111115d11111111111111100000000000000000000000000000000
000082882222222222222222222222222222222200000000000000000000000000000000d1111115d11111111111111100000000000000000000000000000000
000082828822882228822882228822888228822800000000000000000000000000077000d1111115d11111111111111100000000000000000000000000000000
000082822288228882288228882288222882288200000000000000000000000000007000d1111115d11111111111111100000000000000000000000000000000
000082882222222222222222222222222222222200000000000000000000000000000000d1111115d11111111111111100000000000000000000000000000000
000668888888888888888888888888888888888800000000000000000000000000000000d1111115d11111111111111100000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000d1111115d11111115555555500000000000000000000000000000000
00000000082282800828228008282280082282800000000000000000ddddddd00dddddddd1111115dddddddd1111111500000000000000000000000000000000
0000000008228280082282800828228008282280000000000000000011111115d1111111d1111115111111111111111500000000000000000000000000000000
0000000008282280082282800822828008282280000000000000000011111115d1111111d1111115111111111111111500000000000000000000000000000000
0600006008282280082822800822828008228280000000000000000011111115d1111111d1111115111111111111111500000000000000000000000000000000
0688886008228280082822800828228008228280000000000000000011111115d1111111d1111115111111111111111500000000000000000000000000000000
0822228008228280082282800828228008282280000000000000000011111115d1111111d1111115111111111111111500000000000000000000000000000000
0888888008282280082282800822828008282280000000000000000011111115d1111111d1111115111111111111111500000000000000000000000000000000
08822880082822800828228008228280082282800000000000000000555555500555555505555550111111111111111500000000000000000000000000000000
04040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404b6b6a4242424b4b6b6b6b6b6b6b604
04b6b6b6b6b60404b6b6b7151515b404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b70000000000a6a400009700000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b70000000000970000001700960000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b7000000000000000000b584a40000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b700b5848477000096007500000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b70097000000000075007500000024a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b700000096000087a4007500242424a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b70000007500000000007500242424a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b7009624750000000000750024248704000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b700b484a400000000007500000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000a6
b70000000000000000007500000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000b4
b6848484848484848484a400000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b7000000000000000000000000000025
242400000000007524240000000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b7000000000000000000000000000025
242400000000007524000000000000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004b70000000000000000000000000000b5
a52424240000007524242424240000a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404a7a7a7a7a7a7a7a7a7a7a7a7a7a704
04a7a7a7a7a7a7a7a7a7a7a7a7a7a704000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404
04040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404
04040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115000000000000000000000000d111111111111111
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115010101000101010001010100d111111111111111
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115001010100010101000101010d111111111111111
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115010101000101010001010100d111111111111111
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115001010100010101000101010d111111111111111
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115010101000101010001010100d111111111111111
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111115001010100010101000101010d111111111111111
11111111555555555555555555555555555555555555555555555555555555555555555555555555555555500000000000000000000000000555555511111111
111111150000000000000000000000000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1111111
111111150101010001010100010101000101010000000000000000000822828000000000010101000101010001010100010101000101010001010100d1111111
111111150010101000101010001010100010101000000000000000000828228000000000001010100010101000101010001010100010101000101010d1111111
111111150101010001010100010101000101010000000000000000000828228000000000010101000101010001010100010101000101010001010100d1111111
111111150010101000101010001010100010101000000000000000000822828000000000001010100010101000101010001010100010101000101010d1111111
11111115010101000101010001010100010101000000000000000000082282800000000001010100010101000101010001010100010101000101b100d1111111
11111115001010100010101000101010001010100000000000000000082822800000000000101010001010100010101000101010001010100010b01041111111
11171115000000000000000000000000000000000000000000000000082822800000000000000000000000000000000000000000000000000000bbbb47111111
11777775000000000000000000000000000000000000000000000000082282800000000000000000000000000000000000000000000000000000bbbb47711111
11171115010101000101010001010100000000000000000000000000082282800000000000000000000000000000000001010100010101000000b00041711111
11171115001010100010101000101010000000000000000000000000082822800000000000000000000000000000000000101010001010100000b000d1711111
111711150101010001010100010101000000000000000000000000000828228000000000000000000000000000000000010101000101010000000000d1711111
111711150010101000101010001010100000000000000000000000000822828000000000000000000000000000000000001010100010101000000000d1711111
111711150101010001010100010101000000000000000000000000000822828000000000000000000000000000000000010101000101010000000000d1711111
111711150010101000101010001010100000000000000000000000000828228000000000000000000000000000000000001010100010101000000000d1711111
111711150000000000000000000000000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
11171111ddddddd000000000000000000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
1117111111111115010b0100010101000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
1117111111111114001b1010001010100000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
1117111111111174bbbb0100010101000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
1117777777777774bbbb1010001010100000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
1111111111111114010b0100010101000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
1111111111111115001b1010001010100000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
111111115555555000000000000000000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
111111150000000000000000000000000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
111111150101010001010100000000000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
111111150010101000101010000000000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
111111150101010001010100000000000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
111111150010101000101010000000000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
111111150101010001010100000000000000000000000000000000000822828000000000000000000000000000000000000000000000000000000000d1711111
111111150010101000101010000000000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
111111150000000000000000000000000000000000000000000000000828228000000000000000000000000000000000000000000000000000000000d1711111
11111111ddddddd00dddddd0dddddddddddddddddddddddd0dddddddd882288ddddddddddddddddddddddddddddddddddddddddddddddddddddddddd11711111
1111111111111115d1222215111111111111111111111111d1111111188888811171111111111111111111111111111111111111111111111111111111711111
1111111111111115d2555215111111111111111111111111d1111111182222877777777777777777777777777777777777777777777777777777777777711111
1111111111111115d2555525111111111111111111111111d1111111168888611171111111111111111111111111111111111111111111111111111111111111
1111111111111115d2555525111111111111111111111111d1111111161111611111111111111111111111111111111111111111111111111111111111111111
1111111111111115d2555525111111111111111111111111d1111111111111111111111111111111111111111111111111111111111111111111111111111111
1111111111111115d1929295111111111111111111111111d1111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111555555500555555055555555555555555555555505555555555555555555555555555555555555551111111155555555555555555555555511111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000000d1111115000000000000000000000000d1111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000000d1111115000000000000000000000000d1111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000000d1111115000000000000000000000000d1111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000000d6111165000000000000000000000000d1111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000700d6888865000000000000000000000000d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000707778222285000000000000000000000000d1111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000700d8888885000000000000000000000000d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008822880000000000000000000000000d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000000000000d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000001010100d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000000101010d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000001010100d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000000101010d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000001010100d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000000101010d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000000000000d1111111
111111150000000000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000000000000d1111111
111111150101010000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000001010100d1111111
111111150710101000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000000101010d1111111
111171150171010000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000001010100d1111111
111777777717101000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000000101010d1111111
111171150171010000000000000000000000000000000000000000000000000000000000000000000000000008228280000000000000000001010100d1111111
111171150710101000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000000222201010d1111111
111171150000000000000000000000000000000000000000000000000000000000000000000000000000000008282280000000000000002226200000d1111111
11117115000000000000000000000000000000000000000000000000000000000000000000000000000000000dddddd0000000000000002266220000d1111111
11117115010b0100010101000000000000000000000000000000000000000000000000000000000000000000d1111115000000000101012662620100d1111111
11117114001b1010001010100000000000000000000000000000000000000000000000000000000000000000d1111115000000000010102222221010d1111111
11117174bbbb0100010101000000000000000000000000000000000000000000000000000000000000000000d1111115000000000101010929290100d1111111
11117774bbbb1010001010100000000000000000000000000000000000000000000000000000000000000000d1111115000000000010101000101010d1111111
11111114010b0100010101000000000000000000000000000000000000000000000000000000000000000000d1111115000000000101010001010100d1111111
11111115001b1010001010100000000000000000000000000000000000000000000000000000000000000000d1111115000000000010101000101010d1111111
1111111500000000000000000000000000000000000000000000000000000000000000000000000000000000d1111115000000000000000000000000d1111111
11111111ddddddddddddddd00000000000000000000000000ddddddddddddddddddddddddddddddddddddddd11111111dddddddddddddddddddddddd11111111
111111111111111111166888888888888888888888888888d1111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111118288222222222222222222222222d1111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111118282882288228822882288228822d1111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111118282228822882288228822882288d1111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111118288222222222222222222222222d1111111111111111111111111111111111111111111111111111111111111111111111111111111
111111111111111111166888888888888888888888888888d1111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111555555555555575000000000000000000000000005555555555555555555555555555555555555555555555555555555555555555555555511111111
111111150000000000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1111111
111111150000000000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010100d1111111
111111150077777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010d1111111
111111150070000000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010100d1111111
111111150070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010d1111111
111111150070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010100d1111111
111111150070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010d1111111
11111115007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005555555
11111115007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11111115007000000000000000000000000000000000000000000000000002222220000000000000000000000000000000000000010101000101010001010100
1111111500700000000000000000000000000000000000000000000000002f222f22000000000000000000000000000000000000001010100010101000101010
111111150070000000000000000000000000000000000000000000000000f5fff5f2000000000000000000000000000000000000010101000101010001010100
111111150070000000000000000000000000000000000000000000000000ffffffff000000000000000000000000000000000000001010100010101000101010
1111111500700000000000000000000000000000000000000000000000000ffffff0000000000000000000000000000000000000010101000101010001010100
1111111500700000000000000000000000000000000000000000000000006bbbbb60000000000000000000000000000000000000001010100010101000101010
11111115007000000000000000000000000000000000000000000000000000600600000000000000000000000000000000000000000000000000000000000000
11111115007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11111115017101000101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010001010100
11111115077010100010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010101000101010
11117115017101000101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010001010100
11177777777710100010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010101000101010
11117115017101000101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010001010100
11117115071010100010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010101000101010
11117115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11117115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11117115010b01000000066666006660666066600660066000006660606066606660066066000000606066606660606000006660000000000000000001010100
11117114001b10100000666006606060606060006000600000006060606006000600606060600000606006000600606000000060000000000000000000101010
11117174bbbb01000000660006606660660066006660666000006600606006000600606060600000606006000600666000000600000000000000000001010100
11117774bbbb10100000666006606000606060000060006000006060606006000600606060600000666006000600606000006000000000000000000000101010
11111114010b01000000066666006000606066606600660000006660066006000600660060600000666066600600606000006660000000000000000001010100
11111115001b10100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010
11111115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11111111dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111

__gff__
00000000000019150d090000000000000000000000810b000000000000000000000000000000130007000000000000000000000000000000000000000000000081810001010101818181818100000000008080010101018100008181000000000101010101000081008181810000000000010101010000818181818100000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
00000000000000447700000000000000406b6b6b6b6b6b6b6b6b6b6b6b6b6b40406b6b6b6b6b6b6b6b6b6b6b6b6b6b404040404040404040404040406b6b6b40406b6b6b6b6b6b6b6b6b6b6b6b6b6b40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005b4848484877000054484848485a007b00000000000000000000000000004b4a42420000000000000000000042426a4040406b6b4040404040407b4242424b4a42424271000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057007b0000000000000000000000000000424242420000000000000069000000426a40404a00004b6b404040407b424242525242420071000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057007b000000000000000000000000004242424200000000000000004b4848484840407b00000042426a406b6b4a004242525242000071000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057007b0000000000000000000000000042424200000000000000000000000000006a407b00000000426a7b0000000000425b7a7a7a7a7a5a4200005b7a7a5a00006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057007b00000000000000000000000042425b7a4848484848484848485a000000006a407b00000000004b4a0000000000426a40404040407b4242426a40407b00006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00530000000000000000000000007900404848484848487748484848487848407b00000000000000000057000000006a407b000000000000000000000000426a406b6b6b6b6b4848486b6b6b4a00006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
690000000000000000000000000000457b42420000000071000000000000006a7b0000000000000000004b774848486a407b000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
430000000000000000000000000000797b42000000000071000000000000006a7b00000000000000000000000000006a40405a0000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
006900000000000000000000000055007b42420000000071000000000000006a7b00006900000000000000000000006a40407b0000000000000000000000006a7b00005b7a7a5a000042425b7a7a7a40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057004048484848484877000000000000006a7b00006a48484877484848784848484040407b0000000000000000000000006a7b00006a40407b004242426a40404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057007b42424242000000000000000000006a7b00005700000000000000000000006a40407b617848484848484848484848407b00004b6b6b6b484848486b6b6b6b40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005700000000000000000000000057007b42424200000000000000000000006a7b00005700000000000000000000006a40404a4200000000000000004242426a7b00000000004252000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
005719000000000000000000000057004077424200000000000000000000426a7b42005700000042000000000000006a404a424200000000000000004242426a7b00000000004269000000000000426a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
004b4848484856000078484848484a007b42420000000000000000000042426a7b42425700004242424200000000006a7b424242424200000000000042425b40407a5a4242425b405a0000004242426a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000784600000000000000407a7a7a7a7a7a7a7a7a5a4242425b40407a7a405a424242425b7a7a7a7a7a40407a7a7a7a7a7a5a00005b7a7a7a40404040407a7a7a4040407a5a4242425b40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
40404040404040404040404040404040406b6b6b6b6b6b6b6b6b4a4242424b40406b6b6b4a424242424b6b6b6b6b6b6b6b6b6b6b6b6b6b4a0000156b6b6b6b40406b6b6b6b6b6b6b6b6b4a5151514b40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b42424242000071004242424242426a7b4200000000000000000000000042575700000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b42424200000071000000004242006a7b4200000000000000000000000042575700000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000404077424200000071000000000000006a7b4242000000000000000000004242575700000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b42420000000071000000000000006a7b4242424200000000000000424242155a00000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004040771548484878484848487a484848407b42424242000000000000007848487a7b00000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b00000000000000000000790000006a4048487742000000000000005700426a7b00000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b00000000000000000000710000426a7b00000000000000000000005742426a7b00000000000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b42000000000000000000710000426a7b000000005b487761617848484848404048484877000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b42420000000000000000690042426a7b00000000570000000000000000006a7b42427171000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004040487761616178484848486b484848407b000000006a4848484848770000006a7b42427171000000000000000000006a7b00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b00000000000000000000000000424b4a48484815570000000000000000006a4048484848484877484848484848154b4a00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b000000000000000000000000424242000000000057000000784848484848407b0000000000005700000000000000525200000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b4242000000000000000000000042424200000000570000000000000000426a7b0000004242005700000000000000525200000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
400000000000000000000000000000407b42000000000000000000000000004242420000006a7a7a7a7a7a7a5a42426a7b00424242424215000000000000005b5a00000000000000000000000000006a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
40404040404040404040404040404040407a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a40404040404040407a7a40407a7a5a4242425b7a7a7a7a7a7a7a40407a7a7a7a7a7a7a7a7a5a5151515b40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a000007320073200731007300051001b2000220002200012000120018200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
000a00000861007610086100761000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00080000095300d550115500050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
00060000071400c140001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
000600000c14007140001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
000200002844024430244200040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400004000040000400
000c0000144500b4400b4300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

