pico-8 cartridge // http://www.pico-8.com
version 9
__lua__
-- circuits
-- by codekitchen

layer = {
  bg = 1,
  main = 2,
  player = 3,
  fg = 4,
  max = 4,
}

s1=[[ strings! ]]

function merge(dest, src)
  for k, v in pairs(src) do
    dest[k] = copy(v)
  end
end

function copy(o, t)
  local c
  if type(o) == 'table' then
    if (type(o.clone) == 'function') return o:clone()
    c={}
    merge(c, o)
    if type(t) == 'table' then
      merge(c, t)
    end
  else
    c = o
  end
  return c
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
  if (type(a) == "number") return v{ a + b.x, a + b.y }
  if (type(b) == "number") return v{ b + a.x, b + a.y }
  return v{ a.x + b.x, a.y + b.y }
end
function vector.__sub(a, b)
  if (type(b) == "number") return v{ a.x - b, a.y - b }
  return v{ a.x - b.x, a.y - b.y }
end
-- scalar or cross product
function vector.__mul(a, b)
  if (type(a) == "number") return v{ a * b.x, a * b.y }
  if (type(b) == "number") return v{ a.x * b, a.y * b }
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
function vector:turn_left()
  return id_to_dir[(self.id%4)+1]
end
function vector:turn_right()
  return id_to_dir[(self.id+2)%4+1]
end
function vector:about_face()
  return id_to_dir[(self.id+1)%4+1]
end
function vector:dset(idx)
  dset(idx,self.x) dset(idx+1,self.y)
end
function vector.dget(idx)
  return v{dget(idx),dget(idx+1)}
end

function sample(arr)
  return arr[flr(rnd(#arr))+1]
end
function filter(arr, fn)
  local ret={}
  for x in all(arr) do
    if (fn(x)) add(ret, x)
  end
  return ret
end
function contains(arr, v)
  for x in all(arr) do
    if (x == v) return true
  end
  return false
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

actor=object:copy({
  initialize=function(self,pos,args)
    self.pos=pos
    if (args) merge(self, args)
    self:setroom()
  end,
  delete=function(self)
    if (self.room) del(self.room.actors, self)
  end,
  pos=vector.zero,
  spr=1,
  w=1,
  h=1,
  layer=layer.main,
  update=function(self) end,
  draw=function(self)
    if (self.hide) return
    spr(self.spr, self.pos.x - self.w*4, self.pos.y - self.h*4, self.w, self.h, self.flipx, self.flipy)
  end,
  touching=function(self,other)
    local x=self.pos.x - other.pos.x
    local y=self.pos.y - other.pos.y
    return abs(x) < (self.w*4 + other.w*4) and abs(y) < (self.h*4 + other.h*4)
  end,
  move=function(self,dist,speed)
    speed=speed or 1
    local newpos=self.pos+dist*speed
    if (not self:walkable(newpos)) newpos=self.pos+dist
    if self:walkable(newpos) then
      self.pos=newpos
      self:setroom()
    end
  end,
  walkable=function(self,pos)
    if (self.player and devmode) return true
    -- assumes actor of size 1 for now
    return world:walkable(self, pos+v{-3,2}) and world:walkable(self, pos+v{2,-3}) and world:walkable(self, pos-3) and world:walkable(self, pos+2)
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
  for i,room in pairs(rooms) do
    for a in all(room.actors) do
      a:update()
    end
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
powered_color=9
text_color=6
connflash_color=8
connflash=0
connflash_time=20
connection=object:copy({
  cposs={v{0, -3}, v{-3, 0}, v{0, 3}, v{3, 0}},
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
    local drawpos=self:basepos()+self.offs[self.facing.id]
    local dspr=self.spr+(self.facing.horiz and 2 or 0)
    if (self.powered) pal(wire_color, powered_color)
    if connflash>0 and connflash_check(self) then
      if ((flr(connflash/5))%2==1) pal(wire_color, connflash_color)
    end
    spr(dspr, drawpos.x, drawpos.y, 1, 1, self.facing==east, self.facing==south)
    pal()
  end,
  can_solder=function(self)
    return self.conn == nil
  end,
})
input=connection:copy({
  type='input',
  input=true,
  spr=1,
  offs={v{-1, -4}, v{-4, -1}, v{-1, -3}, v{-3, -1}},
  facing=south,
})
output=connection:copy({
  type='output',
  output=true,
  spr=2,
  offs={v{-2, -4}, v{-4, -2}, v{-2, -3}, v{-3, -2}},
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
  connections={},
  powered=false,
  facing=south,
  initialize=function(self, ...)
    actor.initialize(self, ...)
    foreach(self.connections, function(c) c:add(self) end)
    self.c=self.connections[1]
    if (self.coffs) self.c._pos+=self.coffs
    if (self.cfacing) self.c.facing=self.cfacing
  end,
  draw=function(self)
    foreach(self.connections, function(c) c:draw() end)
    if (self.powered) pal(wire_color, powered_color)
    actor.draw(self)
    pal()
  end,
  tick=function(self)
  end,
  room_switched=function(self)
    for c in all(self.connections) do simulation:disconnect(c) end
  end,
})
and_=component:copy({
  movable=true,
  spr=17,
  h=2,
  connections={i(-3,3),i(1,4),o(-1,-4)},
  tick=function(self)
    self.powered=self.c.powered and self.connections[2].powered
    self.connections[3].powered=self.powered
  end,
})
or_=component:copy({
  movable=true,
  spr=18,
  h=2,
  connections={i(-3,3),i(1,4),o(-1,-4)},
  tick=function(self)
    self.powered=self.c.powered or self.connections[2].powered
    self.connections[3].powered=self.powered
  end,
})
not_=component:copy({
  movable=true,
  spr=16,
  h=2,
  connections={i(-1,3),o(-1,-4)},
  tick=function(self)
    self.powered=not self.c.powered
    self.connections[2].powered=self.powered
  end,
})
switch=component:copy({
  spr=48,
  connections={o(-1,-3)},
  tick=function(self)
    self.c.powered=self.powered
    self.spr=self.powered and 49 or 48
  end,
  interact=function(self)
    self.powered=not self.powered
    self.spr=self.powered and 49 or 48
  end,
})
empty_input=component:copy({
  connections={i(0,0)},
  tick=function(self)
    self.powered=self.c.powered
  end,
})
empty_output=component:copy({
  connections={o(0,0)},
  tick=function(self)
    self.c.powered=self.powered
  end,
})
timed=component:copy({
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
door=component:copy({
  connections={i(0,0)},
  walltile=64,
  transition_tile=65,
  current=0,
  powered=nil,
  tick=function(self)
    local prev=self.open
    self.powered=self.c.powered
    self.open=self.powered
    if (self.invert) self.open=not self.open
    if prev != self.open or self.current == self.transition_tile then
      self.current=self.open and 0 or self.walltile
      if (not prev and self.open and self.transition_tile) self.current=self.transition_tile
      for x=self.pos.x+self.doorway[1]*8,self.pos.x+self.doorway[3]*8 do
        for y=self.pos.y+self.doorway[2]*8,self.pos.y+self.doorway[4]*8 do
          world:tile_set(v({x,y}),self.current)
        end
      end
    end
  end,
})
toggle=component:copy({
  movable=true,
  connections={i(-5,1),i(4,3),o(-5,-4),o(4,-2)},
  spr=19,
  w=2,
  active=1,
  tick=function(self)
    if (self.c.powered) self.active=1
    if (self.connections[2].powered) self.active=2
    self.connections[3].powered=self.active==1
    self.connections[4].powered=self.active==2
  end,
  draw=function(self)
    component.draw(self)
    local pos=self.pos-v{8,4}+v{1+9*(self.active-1),2}
    rectfill(pos.x, pos.y, pos.x+4, pos.y+3, 9)
  end,
})
text_toggle=component:copy({
  connections={i(0,0)},
  text="",
  color=7,
  tick=function(self)
    self.powered=self.c.powered
  end,
  draw=function(self)
    component.draw(self)
    local textsize=#self.text*4-1
    local pos=self.pos
    rect(pos.x-textsize/2,pos.y-8,pos.x+textsize/2+3,pos.y, self.color)
    if self.powered then
      print(self.text, pos.x-textsize/2+2, pos.y-6, self.color)
    end
  end,
})

train=actor:copy({
  type='train',
  facing=north,
  ticks=0,
  initialize=function(self,...)
    actor.initialize(self,...)
    self.tpos=(self.pos-4)*0.125
  end,
  update=function(self)
    if self.ticks == 0 then
      local facing=self.facing
      local pos=self.tpos
      if self.can_move(pos,facing) then 
      elseif self.can_move(pos,facing:turn_right()) then
        self.facing=facing:turn_right()
      elseif self.can_move(pos,facing:turn_left()) then
        self.facing=facing:turn_left()
      else self.facing=facing:about_face()
        self:delete()
      end
      self.tpos=pos+self.facing
      self.ticks=tickframes
    end
    self.ticks-=1
    self.pos=self.tpos*8+4
    self:setroom()
  end,
  can_move=function(pos,facing)
    local target=pos+facing
    return fget(mget(pos.x, pos.y), facing.id) and fget(mget(target.x, target.y), facing:about_face().id)
  end,
  draw=function(self)
    local pos=self.pos-4+self.facing*(-8*self.ticks/tickframes)
    local sprn=self.facing.id%2==1 and 23 or 24
    spr(sprn, pos.x, pos.y, 1, 1, self.facing.id==2, self.facing.id==3)
  end,
})
train_spawn=component:copy({
  spr=9,
  layer=layer.fg,
  interval=10,
  ticks=0,
  facing=south,
  tick=function(self)
    if (self.interval==0) return
    if self.ticks==0 then
      train:new(self.pos, {facing=self.facing})
      self.ticks=self.interval
    end
    self.ticks-=1
  end,
})
actor_sensor=component:copy({
  layer=layer.bg,
  connections={o(0,0)},
  sq={1,0},
  dtype='train',
  tick=function(self)
    self.c.powered=false
    for a in all(self.room.actors) do
      if (a.type == self.dtype and a:touching(self)) self.c.powered=true
    end
  end,
  draw=function(self)
    component.draw(self)
    rectfill(self.pos.x-1, self.pos.y-1, self.pos.x+self.sq[1], self.pos.y+self.sq[2], 10)
  end,
})
track_replacer=component:copy({
  layer=layer.bg,
  connections={i(0,0)},
  tile=0,
  tick=function(self)
    if (not self.orig) self.orig=world:tile_at(self.pos)
    local tile=self.pos:world_to_tile()
    for a in all(self.room.actors) do if a != self and a.tpos == tile then return end end
    self.curtile=self.c.powered and self.tile or self.orig
    world:tile_set(self.pos, self.curtile)
  end,
  draw=function(self)
    component.draw(self)
    local othertile=self.curtile==self.orig and self.tile or self.orig
    pal(5, 10)
    spr(self.curtile, self.pos.x-4, self.pos.y-4)
    pal()
  end,
})
button=component:copy({
  connections={o(4,2)},
  pressed=0,
  reset=-1,
  initialize=function(self,...)
    component.initialize(self,...)
    self.c.spr=0
    if (self.flipx) self.c._pos-=v({9,0})
  end,
  tick=function(self)
    if self.pressed>0 then
      self.pressed-=1
    end
    self.powered=self.pressed!=0
    if (self.invert) self.powered=not self.powered
    self.c.powered=self.powered
    self.spr=self.pressed==0 and 58 or 59
  end,
  interact=function(self)
    self.pressed=self.reset
    self.spr=self.pressed==0 and 58 or 59
  end,
})
robot_spawner=component:copy({
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
robotclass=component:copy({
  movable=true,
  robot=true,
  spr=10,
  wallcolor=6,
  bumpers={},
  thrusters={},
  id=1,
  action2=function(self)
    self.player_pos=player.pos
    player:teleport(self.room_coords+v{26,108})
  end,
  spawned=function(self,pos)
    self.pos=pos
    self.switch.powered=false
    self:setroom()
  end,
  initialize=function(self,...)
    component.initialize(self,...)
    add(robots,self)
    self.room_coords=robot_room_coords+v{self.id * 128, 0}
    self.robot_room=room:new(self.room_coords.x/128,self.room_coords.y/128,{
      actors={
        {empty_output,60,8,{cfacing=south}},
        {empty_output,8,67,{cfacing=east}},
        {empty_output,67,119,{cfacing=north}},
        {empty_output,119,60,{cfacing=west}},
        {empty_input,76,16,{cfacing=south}},
        {empty_input,16,51,{cfacing=east}},
        {empty_input,51,111,{cfacing=north}},
        {empty_input,111,76,{cfacing=west}},
        {toggle,100,84},
        {toggle,100,100},
        {switch,19,95},
        {or_,89,27},
        {and_,97,27},
        {and_,105,27},
        {not_,86,44},
        {not_,94,44},
        {or_,102,44},
      },
    })
    self.robot_room.robot=self
    for i=1,4 do
      self.bumpers[i]=self.robot_room.actors[i]
      self.thrusters[i]=self.robot_room.actors[i+4]
    end
    self.switch=self.robot_room.actors[11]
    self.switch.c.spr=0
    if self.tutorial then
      self.switch.powered=true
      simulation:connect(self.bumpers[1].connections[1],self.robot_room.actors[9].connections[2])
      simulation:connect(self.bumpers[3].connections[1],self.robot_room.actors[9].connections[1])
      simulation:connect(self.thrusters[1].connections[1],self.robot_room.actors[9].connections[4])
      simulation:connect(self.thrusters[3].connections[1],self.robot_room.actors[9].connections[3])
      self.text={
        {23,92,"\x8bpower"},
        {25,106,"\x8bexit"},
        {19,65,"\x8bbumper"},
        {23,49,"\x8bthrust"},
      }
    end
  end,
  delete=function(self)
    notimplemented()
  end,
  update=function(self)
    if (player.pos:overlap(self.room_coords+v{16,108},self.room_coords+v{20,112})) player:teleport(self.player_pos)
    if (player.holding == self) self.switch.powered=false
    local b=self.bumpers
    b[1].powered=not world:walkable(self, self.pos+v{0,-5})
    b[2].powered=not world:walkable(self, self.pos+v{-5,0})
    b[3].powered=not world:walkable(self, self.pos+v{0,4})
    b[4].powered=not world:walkable(self, self.pos+v{4,0})
    if self:active() then
      local t=self.thrusters
      if (t[1].powered) self:move(south*.5)
      if (t[2].powered) self:move(east*.5)
      if (t[3].powered) self:move(north*.5)
      if (t[4].powered) self:move(west*.5)

      for a in all(self.room.actors) do
        if (self:touching(a) and a.interact) self:interact_with(a)
      end
    end
  end,
  active=function(self)
    return not player.room.robot and self.switch.powered 
  end,
  interact_with=function(self,other)
    other:interact(self)
  end,
  tick=function(self)
  end,
  draw=function(self)
    if (self:active()) pal(5,10)
    component.draw(self)
    pal()
    local pos=self.pos
    self.draw_bumper(self.bumpers[1],pos.x-2,pos.y-5,pos.x+1,pos.y-5)
    self.draw_bumper(self.bumpers[2],pos.x-5,pos.y-2,pos.x-5,pos.y+1)
    self.draw_bumper(self.bumpers[3],pos.x-2,pos.y+4,pos.x+1,pos.y+4)
    self.draw_bumper(self.bumpers[4],pos.x+4,pos.y-2,pos.x+4,pos.y+1)
  end,
  draw_bumper=function(r,a,b,c,d)
    line(a,b,c,d,r.powered and powered_color or bumper_color)
  end,
})

simulation={
  tick=function(self)
    for i,room in pairs(rooms) do
      for a in all(room.actors) do
        if(a.tick) a:tick()
      end
    end
    for i,room in pairs(rooms) do
      for a in all(room.actors) do
        for c in all(a.connections or {}) do
          if (c.input and not c.conn) c.powered=false
          if c.output then
            if (c.wire) c.wire.powered=c.powered
            if (c.conn) c.conn.powered=c.powered
          end
        end
      end
    end
  end,
  connect=function(self, a, b, args)
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

flag_walk=0
flag_robot_walk=7
roomsidx={{},{},{},{},{},{}}
rooms={}
room=object:copy({
  actors={},
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
      local a=x[1]:new(v{x[2]+roomcoords.x,x[3]+roomcoords.y},x[4])
      -- actor will add itself
    end
    for w in all(self.wires) do
      simulation:connect(self.actors[w[1]].connections[w[2]], self.actors[w[3]].connections[w[4]])
    end
  end,
})
getroom=function(v)
  local r=(roomsidx[v.y] or {})[v.x]
  if (r) return r
  -- probably only useful in dev mode?
  return room:new(v.x, v.y, {})
end
function init_world()
room:new(0,2,{
  text={
    {10,10,"combine logic gates"},
    {10,17,"to build mechanisms"},
    {40,98,"use the or gate"},
    {40,105,"to open this door"},
    {12,35,"and gate"},
    {60,35,"not gate"},
    {117,62,"\x91"},
  },
  actors={
    {timed,18,120},
    {timed,29, 120, {powered=true}},
    {door,24,87, {doorway={1,0,2,0}}},
    {and_,23,56},
    {switch,18, 76},
    {switch,28, 76},
    {door,48, 45, {doorway={0,1,0,2},cfacing=west}},
    {switch,60, 76, {powered=true}},
    {not_,68,56},
    {door,96, 45, {doorway={0,1,0,2},cfacing=west}},
    {train_spawn,100,4},
  },
  wires={{4,3,7,1}, {8,1,9,1}, {9,2,10,1}},
})
room:new(0,3,{
  text={
    {20,112,"\x8btoggle switch with z"},
    {12,64,"solder wires with x"},
    {12,71,"add/remove wires at"},
    {12,78,"inputs and outputs"},
    {60,20,"or gate->"},
    {60,31,"carry with z"},
    {60,38,"into next room"},
    {100,5,"\x94"},
  },
  actors={
    {switch,12,116},
    {door,29,94, {doorway={1,0,2,0}}},
    {switch,12,44},
    {door,49,20, {doorway={0,1,0,2}, cfacing=west}},
    {or_,112,20},
  },
  wires={{1,1,2,1}},
})
room:new(1,2,{
  actors={
    {toggle,30, 70},
    {actor_sensor,20,28, {coffs=v{0,2},cfacing=south}},
    {actor_sensor,60,44, {coffs=v{0,2},cfacing=south}},
    {track_replacer,44,28,{coffs=v{-2,4},cfacing=west,tile=7}},
    {actor_sensor,108,20, {coffs=v{2,0},cfacing=east,sq={0,1}}},
    {toggle,104,60},
    {door,78,50, {doorway={0,1,0,4},cfacing=east}},
    {and_,107,76},
    {actor_sensor,92,8,{coffs=v{-2,0},cfacing=west,sq={0,1}}},
    {train_spawn,104,0,{interval=0}},
  },
  text={
    {12,102,"toggles retain"},
    {12,109,"their last value"},
    {117,70,"\x91"},
  },
  wires={{2,1,1,1},{3,1,1,2},{4,1,1,4},{5,1,8,2},{8,3,6,2},{6,4,7,1},{9,1,8,1}},
})
room:new(1,3,{
  text={
    {5,102,"\x8btutorial"},
    {100,25,"game\x91"},
    {28,54,"     circuits!\n(err: logo missing)"},
  },
})
room:new(2,2,{
  actors={
    {robotclass,90,60,{id=0,tutorial=true}},
    {door,120,92,{cfacing=west,doorway={-6,-1,-1,-1},walltile=97,invert=true}},
    {button,117,114,{invert=true}},
    {button,11,114,{flipx=true}},
    {door,14,123,{facing=west,doorway={1,0,2,1}}},
  },
  wires={{2,1,3,1},{4,1,5,1}},
  text={
    {14,12,"this is a robot\x91\nhi robot!\nits bumpers sense walls\nthrusters move it around\n\nyou can carry it around\nand press x to climb in\nand rewire its insides!"},
    {14,92,"move the robot over\nto press this button\x91\nyou'll need to switch it\nback on after moving"},
  },
})
room:new(2,3,{
  actors={
    {actor_sensor,104,92,{coffs=v{0,-2},cfacing=north}},
    {actor_sensor,112,28,{coffs=v{0,2},cfacing=south}},
    {toggle,102,72},
    {track_replacer,84,60,{coffs=v{3,2},tile=38}},
    {door,66,6,{doorway={-1,1,-1,14},walltile=80,invert=true}},
    {button,117,14,{invert=true}},
    {button,27,116,{flipx=true,reset=2}},
    {robot_spawner,22,100,{cfacing=west}},
  },
  wires={{1,1,3,2},{2,1,3,1},{3,4,4,1},{6,1,5,1},{8,1,7,1}},
  text={
    {10,121,"robots"},
  },
})
room:new(3,3,{
  actors={
    {train_spawn,52,52},
    {train_spawn,36,44,{interval=0,flipy=true}},
    {train_spawn,36,76,{interval=0}},
    {door,82,81,{doorway={-2,0,-1,0},walltile=97,invert=true,cfacing=north}},
    {button,117,12,{invert=true}},
  },
  wires={{5,1,4,1}},
})
room:new(4,3,{
  text={
    {20,40,"nothing here yet! \x82"},
  },
})
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
    if pos.y >= 1280 then
      pos.x = pos.x % 128
      pos.y = pos.y % 128
    end
    local tile=self:tile_at(pos)
    if (actor.robot and fget(tile, flag_robot_walk)) return true
    return not fget(tile, flag_walk)
  end,
  switch_rooms=function(self, newroom)
    current_room=newroom
    roomcoords=current_room.coord*128
  end,
  update=function(self)
    if (connflash > 0) connflash-=1
  end,
  draw_room=function(self)
    local roomdata=current_room.robot or current_room
    local mapcoords=current_room.robot and vector.zero or current_room.coord*16
    if (roomdata.wallcolor) pal(12, roomdata.wallcolor)
    map(mapcoords.x, mapcoords.y, roomcoords.x, roomcoords.y, 16, 16)
    pal()
    for t in all(roomdata.text or {}) do
      print(t[3], t[1]+roomcoords.x, t[2]+roomcoords.y, text_color)
    end
  end,
}

solder_distance=4
devmode_playerpos=62
playerclass=actor:copy({
  player=true,
  layer=layer.player,
  holding=nil,
  wire_type=1,
  btn4=0,
  btn5=0,
  initialize=function(self,...)
    actor.initialize(self,...)
    if (devmode) self.pos=vector.dget(devmode_playerpos) self:setroom()
  end,
  update=function(self)
    if (btn(0)) self:move(west)
    if (btn(1)) self:move(east)
    if (btn(2)) self:move(north)
    if (btn(3)) self:move(south)
    if (btn(4)) self.btn4+=1
    if (btn(5)) self.btn5+=1
    self:action_check()
  end,
  move=function(self,dist)
    local speed=1
    local oldpos=self.pos
    if (self.btn4>3) speed=3 self.did_run=true
    actor.move(self,dist,speed)
    if self.holding then
      self.holding:move(self.pos-oldpos)
      if (not self:touching(self.holding)) self.holding=nil
    end
    self.pos:dset(devmode_playerpos)
  end,
  teleport=function(self,pos)
    self.holding=nil
    self.pos=pos
    self:setroom()
  end,
  action_check=function(self)
    if not btn(4) and self.btn4 > 0 then
      if (not self.did_run) self:action1()
      self.btn4=0
      self.did_run=false
    end
    if not btn(5) and self.btn5 > 0 then
      self:action2()
      self.btn5=0
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
      self.holding=nil
    else
      for a in all(self.room.actors) do
        if self:touching(a) then
          if (a.movable) self.holding=a
          if (a.interact) a:interact(self)
        end
      end
    end
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
        local d=(self.pos-c:connpos()):length() 
        if d < closest then
          target=c closest=d
          break
        end
      end
    end
    if not target then
      if (solder_start) self.solder_start=nil return
    elseif not solder_start then
      if (target:can_solder()) self.solder_start=target return
      if (target.conn) simulation:disconnect(target) return
    else
      if self.can_solder(solder_start, target) then
        simulation:connect(solder_start, target, {draw_type=self.wire_type})
        self.solder_start=nil
        return
      end
    end
    -- nothing found, flash connections to signal player
    if not solder_start then
      connflash_check=function() return true end
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
      local bpos=self.pos
      wire.draw_types[self.wire_type](apos, bpos, wire_color)
    end
    local color=10
    rect(self.pos.x-2, self.pos.y-2, self.pos.x+1, self.pos.y+1, color)
  end,
})

cartdata_base=0x5e00

function _init()
  cartdata("codekitchen_circuits_v1")
  set_devmode()
  init_world()
  local start_pos=v{150,498}
  player=playerclass:new(start_pos)
end

function _update()
  tick+=1
  update_actors()
  world:update()
  if tick%tickframes==0 then
    simulation.tick()
  end
  room_check()
end

function room_check()
  if (player.room != current_room) world:switch_rooms(player.room)
end

function move_cam()
  camera(roomcoords.x, roomcoords.y)
end

function _draw()
  cls()
  move_cam()
  world:draw_room()
  draw_actors()
  if (devmode) draw_dbg()
end

function draw_dbg()
  camera()
  print(player.pos:str(),2,122,7)
end

function set_devmode()
  devmode=peek(cartdata_base)>0
  menuitem(5, "devmode"..(devmode and " \x82" or ''), function() poke(cartdata_base, devmode and 0 or 1) set_devmode() end)
end

function dbg(str)
  if (devmode) printh(str, "debug")
end
__gfx__
000000000700000000700000070000000070000000000000000000000000000000000000cccccccc000660000000000000000000000000000000000000000000
000000007070000007070000707770000700000000000000000000000000000000000000cccccccc066666600000000000000000000000000000000000000000
000000000700000070707000070000007077700000000000005555555555555555555500cc0000cc066565600000000000000000000000000000000000000000
000000000700000000700000000000000700000000000000005400400040004004004500cc0000cc665656660000000000000000000000000000000000000000
00000000070000000070000000000000007000000000000000504040004000400404050000000000666565660000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500555555555555550050000000000065656600000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000544500000000000054450000000000066666600000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500500000000000050050000000000000660000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500500000330000333000066000000000000000000000000000000000000000000000000000000
00000000000000000000000044444440044444440000000000500500003553003555330000600000000000000000000000000000000000000000000000000000
0000000000000000000000004444444004444444000000000054450003a33a3035335a3066600000000000000000000000000000000000000000000000000000
00000000000000000000000044444444444444440000000000500500035335303533335300060000000000000000000000000000000000000000000000000000
00040000004440000044400044444444444444440000000000500500353333533533335366660000000000000000000000000000000000000000000000000000
000400000440440004404400444444400444444400000000005005003533335335335a3000006000000000000000000000000000000000000000000000000000
00404000040004000400040044444440044444440000000000544500355555533555330066666000000000000000000000000000000000000000000000000000
00040000440004404400044000000000000000000000000000500500033333300333000000000600000000000000000000000000000000000000000000000000
00404000400000404000004000000000000000000000000000500500000000000050050000000000000000000000000000000000000000000000000000000000
04000400400000404004004000000000000000000000000000544500000000000054450000000000000000000000000000000000000000000000000000000000
40000040400000404040404000000000000000000000000000500555555555555550050000000000000000000000000000000000000000000000000000000000
44444440444444404400044000000000000000000000000000504040008000800404050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000540040008000800400450000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000555555555555555555550000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0dddd0000dddd0000000000000000000000000000000000000000000000000000000000000000000000b000000000b0000000000000000000000000000000000
0d0000000d0070000000000000000000000000000000000000000000000000000000000000000000000b000400000b0400000000000000000000000000000000
0d0000070d0070000000000000000000000000000000000000000000000000000000000000000000000bbbb400000bb400000000000000000000000000000000
0d0000700d0070000000000000000000000000000000000000000000000000000000000000000000000bbbb400000bb400000000000000000000000000000000
0d0007000d0070000000000000000000000000000000000000000000000000000000000000000000000b000400000b0400000000000000000000000000000000
0ddd70000ddd70000000000000000000000000000000000000000000000000000000000000000000000b000000000b0000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999900000000ccc11cccccccccccccccccccccc1cccc000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999901010100cc11ccccccc111ccccc11cccccc1cccc000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999900101010c11ccccccc11c11ccccc11ccccc1cccc000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999901010100c1cc1111c11ccc11ccccc11c1cc1cc1c000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999900101010c11cccccc1cc1cc11111cc1c11ccc11c000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999901010100cc11cccccccc1cccccccc11cc11c11cc000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999900101010ccc11ccccccc1ccccccc11cccc111ccc000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc9999999900000000cccccccccccc1cccccc11ccccccccccc000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c11cccccccccccccccccccccccc1cccc000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c111ccccc1111111ccccc11cccc1cccc000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c1111cccc1111111cccc111cccc1cccc000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c1111111cc11111cccc1111ccc111ccc000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c1111cccccc111cc1111111cc11111cc000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c111cccccccc1cccccc1111c1111111c000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000c11ccccccccc1ccccccc111c1111111c000000000000000000000000000000000000000000000000000000000000000000000000
080800800000000000000000cccccccccccc1cccccccc11ccccccccc000000000000000000000000000000000000000000000000000000000000000000000000
08080080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08080088888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08088888888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08888888888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040461040404040000607070707070707080046104040404040404040404040404040404040400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000061000004040000627080000004000061006100040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000062708004040000000061000004000061006100040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404006270707070707061707070708061006100040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000061000004006161006100040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000062707070708262708200040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000000000000040000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000000000000000000000000040000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404000004040404040404040404040000000000000000000000000000040404040404040404040000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040404040404040404040404040404040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040400000404040404040404040404040404040404040404000004040404040404040404040400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040400000404040404040404040404040404040404040404000004040404040404040404040404040404040404040404040404040404
04040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000000000004040000000000000000000000000000040400000000000000000000000000000404000000000404040000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000000000004040000000000000000000000000000000000000000000000000000000000000404000000000404040000040404000000
00000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000000000000000000000000000607070707070707070800404040000040404040404
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000000000000000000000000060820000000404000000610404040000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000000000004040000000000000000000000000000040400000000000000000061000000000404000004610404040000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040400000004040404040404040404040000000000000000000000000000040404000004040400000061000000000404000004040461040404040404000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000060707070707070707070707082040404040404000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000061000000000404000004040404040000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000061000000000404000004610404040000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000062800000000404000000610004040000040404040404
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404000004040404040404040404040000000000000000000000000000040404242424000000000000627070707070707070820004040000040404040404
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000000000000000000000000000000000000040404242424000000000000000000000000000000000004040000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000000000000000000000000000000000000040404242424240000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040404042424240000000000000000000404000000000000000000000000000004
04000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404
04040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccc9ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc899999999999999999999999999999999999999999999999999999999999cccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccc9cccccccccccccccccccccccccccccccccccccccccccccccccccccc9cccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8cccccccccccccccccccccccccccccccccccccccccccccccccccccccccc9cccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8cccccccccccccccccccccccccccccccccccccccccccccccccccccccccc9cccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8cccccccccccccccccccccc9999cccccccccccccccccccccccccccccccc9cccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000000006600000000000000000000000000000000c9cccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000000666666000000000000000000000000000000c9cccccc
cccccccc000000000000000000000000000000000000000000000000080800800000000000000000007066a6a6070000000000000000000000000000c9cccccc
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000766a6a6667000000000000000000000000b000c9cccccc
cccccccc000000000000000000000000000000000000000000000000080800800000000000000000007666a6a667000000000000000000000000b00049cccccc
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000706a6a6607000000000000000000000000bbbb49cccccc
cccccccc000000000000000000000000000000000000000000000000080800800000000000000000000066666600000000000000000000000000bbbb4ccccccc
cccccccc000000000000000000000000000000000000000000000000080800800000000000000000000000660000000000000000000000000000b0004ccccccc
00000000000000000000000000000000000000000000000000000000080800800000000000000000000007777000000000000000000000000000b000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
000000000000000000000000000000000000000000000aaaa0000000080800800000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000a00a0000000080800800000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000a00a0000000080800800000000000000000000000000055555555555555555555555555555555555555
000000000000000000000000000000000000000000000aaaa00000000808008000000000000000000000000000540040004000400040004aaa40004000400040
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000504040004000400040004aaa40004000400040
00000000000000000000000000000000000000000000000000000000080800800000000000000000000000000050055555555555555555555555555555555555
00000000000000000000000000000000000000000000000000000000080800800000000000000000000000000054450000000000000000007000000000000000
00000000000000000000000000000000000000000000000000000000080800800000000000000000000000000050050000000000000000007000000000000000
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000500500000000000000007070700000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000000000000544500000000000000000777000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000055555555500500000000000000000070000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000054004004040500000000000000000070000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000050404004004500000000000000000070000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000050055555555500000000000000000070000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000054450000000000000000000000000070000000cccccccc
000000000000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450000000000000000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000054450000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000054450000000000000000000000000070000000cccccccc
cccccccccccccccc0000000000000000cccccccccccccccccccccccc0808008000000000000000000050050000000000000000000000000070000000cccccccc
cccccccc000000000000000000000000000000000000000000000000080800800000000000000000000000000000000000000000000033307000000000000000
cccccccc000000000000000000000000000000000000000000000000080800800000000000000000000000000000000000000000003355537000000000000000
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000aaaaaa555555555555555553a533537555555555555555
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000a400400040004000400040353333537040004000400040
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000a040400040004000400040353333537040004000400040
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000a00aaa555555555555555553a533537555555555555555
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000a44a090000000000000000003355537000000000000000
cccccccc00000000000000000000000000000000000000000000000008080080000000000000000000a00a090000000000000000000033307000000000000000
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050900000000070000000000000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050059999999999797999999990000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450900000007070700000090000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000070000000999000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000070000009090900070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000044444440044444440070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450000000044444440049999940070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000044444444449999940070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000044444444449999940070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000044444440049999940070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450000000044444440044444440070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000070000000090000070000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000777777777797777770000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000070000000090000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450000000000000000009999000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000009090000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050050000000000000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054450000000000000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050055555555500000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000050404004004500000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000054004004040500000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000055555555500500000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000000000000544500000000009000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000808008000000000000000000000000000500500000000099900000000000000cccccccc
cccccccccccccccc0000000000000000000000000000000000000000080800800000000000000000000000000050050000000090933300000000000000000000
cccccccccccccccc0101010001010100010101000000000000000000080800800000000000000000000000000054450000000000355533000000000000000000
cccccccccccccccc001010100010101000101010000000000000000008080080000000000000000000000000005005555555555535335a355555555555555555
cccccccccccccccc010101000101010001010100000000000000000008080080000000000000000000000000005040400040004a353333530040004000400040
cccccccccccccccc001010100010101000101010000000000000000008080080000000000000000000000000005400400040004a353333530040004000400040
cccccccccccccccc010101000101010001010100000000000000000008080080000000000000000000000000005555555555555535335a355555555555555555
cccccccccccccccc0010101000101010001010100000000000000000080800800000000000000000000000000000000000000000355533000000000000000000
cccccccccccccccc0000000000000000000000000000000000000000080800800000000000000000000000000000000000000000033300000000000000000000
cccccccccccccccc0000000000000000000000000000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
cccccccccccccccc0101010001010100010101000000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
cccccccccccccccc0010101000101010001010100000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
ccccccccccc7cccc0101010001010100010101000000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
cccccccccc77777c0010101000101010001010100000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
ccccccccccc7cccc0101010001010100010101000000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
ccccccccccc7cccc0010101000101010001010100000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
ccccccccccc7cccc0000000000000000000000000000000000000000080800800000000000000000000000000000000000000000000000000000000000000000
ccccccccccc7cccc00000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc01010100010101000101010001010100000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc00101010001010100010101000101010000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc01010100010101000101010001010100000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc00101010001010100010101000101010000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc01010100010101000101010001010100000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc00101010001010100010101000101010000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccc00000000000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccccccccccc000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7cccccccccccc010b01000101010001010100000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7ccccccccccc4001b10100010101000101010000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccc7777777777774bbbb01000101010001010100000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccccccccccccccc4bbbb10100010101000101010000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccccccccccccccc4010b01000101010001010100000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
cccccccccccccccccccccccc001b10100010101000101010000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
cccccccccccccccccccccccc000000000000000000000000000000000808008000000000000000000000000000000000000000000000000000000000cccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc8c8cc8ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

__gff__
00000000000019150d090000000000000000000000000b000000000000000000000000000000130007000000000000000000000000000000000000000000000001010000000000000000000000000000810000000000000000000000000000008181000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000044400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040404040404000005440404040400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0053000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4300000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040190000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0040404040405600004040404040400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000040460000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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

