pico-8 cartridge // http://www.pico-8.com
version 9
__lua__
-- circuits
-- by codekitchen

-- ** generic gamelib **

layer = {
  bg = 1,
  main = 2,
  fg = 3,
  max = 3,
}

s1=[[ strings! ]]

vector = {}
vector.__index = vector
function vector.new(o)
  if (not o) return vector.zero
  local v = { x = (o.x or o[1]), y = (o.y or o[2]), id=o.id }
  setmetatable(v, vector)
  return v
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
function vector:facing()
  if abs(self.x) > abs(self.y) then
    if (self.x > 0) return east
    return west
  else
    if (self.y > 0) return south
    return north
  end
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
west  = v{ -1,  0, id=2 }
south = v{  0,  1, id=3 }
east  = v{  1,  0, id=4 }
id_to_dir={north, west, south, east}
function vector:turn_right()
  return id_to_dir[(self.id%4)+1]
end
function vector:turn_left()
  return id_to_dir[(self.id+2)%4+1]
end
function vector:about_face()
  return id_to_dir[(self.id+1)%4+1]
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

object={
  copy=copy,
  new=function(class, ...)
    local o=class:copy()
    o:initialize(...)
    return o
  end,
  initialize=function(self) end,
}

actors={}
actor = object:copy({
  new=function(class, ...)
    local o=object.new(class, ...)
    add(actors, o)
    return o
  end,
  initialize=function(self,pos,args)
    self.pos=pos
    if (args) merge(self, args)
  end,
  delete=function(self)
    del(actors, self)
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
})

function update_actors()
  for a in all(actors) do
    a:update()
  end
end

function draw_actors()
  for l=1,layer.max do
    foreach(actors, function(a)
      if (a.layer == l and (not a.room or (a.room.x == room.x and a.room.y == room.y))) a:draw()
    end)
  end
end

-- base particle system type
psys=actor:copy({
  particles={},
  lifetime=30,
  nparts=10,
  gravity=.5,
  initsys=function(self)
    for i=1,self.nparts do
      self.particles[i]={x=0,y=0,dx=0,dy=0}
      self:initp(self.particles[i])
    end
  end,
  update=function(self)
    for p in all(self.particles) do
      p.dy += self.gravity
      p.x += p.dx
      p.y += p.dy
    end
    self.lifetime -= 1
    if (self.lifetime <= 0) self:delete()
  end,
  draw=function(self)
    for p in all(self.particles) do
      self:drawp(p)
    end
  end,
})

-- ** game code **
tick=0
tickframes=8
wire_color=7
powered_color=9
text_color=6
connflash_color=8
connflash=0
connflash_time=20
connections={}
connection=object:copy({
  _pos=vector.zero,
  conn=nil,
  owner=nil,
  powered=false,
  cposs={v{0, -3}, v{-3, 0}, v{0, 3}, v{3, 0}},
  initialize=function(self,x,y)
    self._pos=v{x,y}
  end,
  add=function(self, owner)
    self.owner=owner
    add(connections, self)
  end,
  delete=function(self)
    del(connections, self)
  end,
  connpos=function(self)
    return self._pos + self.owner.pos + self.cposs[self.facing.id]
  end,
  basepos=function(self)
    return self._pos + self.owner.pos
  end,
  horiz=function(self)
    return self.facing == east or self.facing == west
  end,
  draw=function(self)
    local drawpos=self:basepos()+self.offs[self.facing.id]
    local dspr=self.spr+(self:horiz() and 2 or 0)
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
  end,
  delete=function(self)
    foreach(self.connections, function(c) c:delete(self) end)
    actor.delete(self)
  end,
  draw=function(self)
    foreach(self.connections, function(c) c:draw() end)
    if (self.powered) pal(wire_color, powered_color)
    actor.draw(self)
    pal()
  end,
  tick=function(self)
  end,
  move=function(self,dist)
    self.pos+=dist
    self.room=self.pos:world_to_room()
  end,
})
and_=component:copy({
  movable=true,
  spr=17,
  h=2,
  connections={i(-3,3),i(1,4),o(-1,-4)},
  tick=function(self)
    self.powered=self.connections[1].powered and self.connections[2].powered
    self.connections[3].powered=self.powered
  end,
})
or_=component:copy({
  movable=true,
  spr=18,
  h=2,
  connections={i(-3,3),i(1,4),o(-1,-4)},
  tick=function(self)
    self.powered=self.connections[1].powered or self.connections[2].powered
    self.connections[3].powered=self.powered
  end,
})
not_=component:copy({
  movable=true,
  spr=16,
  h=2,
  connections={i(-1,3),o(-1,-4)},
  tick=function(self)
    self.powered=not self.connections[1].powered
    self.connections[2].powered=self.powered
  end,
})
switch=component:copy({
  spr=48,
  connections={o(-1,-3)},
  tick=function(self)
    self.connections[1].powered=self.powered
    self.spr=self.powered and 49 or 48
  end,
  interact=function(self)
    self.powered=not self.powered
    self.spr=self.powered and 49 or 48
  end,
})
timed=component:copy({
  connections={o(0,0)},
  timing={1,1},
  ticks=1,
  tick=function(self)
    self.ticks-=1
    if (self.ticks <= 0) self:switch()
    self.connections[1].powered=self.powered
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
  facing=south,
  initialize=function(self,...)
    component.initialize(self,...)
    self.connections[1].facing=self.facing
    self.powered=nil
  end,
  tick=function(self)
    local prev=self.powered
    self.powered=self.connections[1].powered
    if prev != self.powered or self.current == self.transition_tile then
      self.current=(self.powered or self.closed_on) and 0 or self.walltile
      if (not prev and self.powered and self.transition_tile) self.current=self.transition_tile
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
  connections={i(-5,1),i(4,3),o(-5,-4),o(4,-3)},
  spr=19,
  w=2,
  active=1,
  tick=function(self)
    if (self.connections[1].powered) self.active=1
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
  coffs=vector.zero,
  tick=function(self)
    self.powered=self.connections[1].powered
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
    self.tpos=self.pos
  end,
  update=function(self)
    self.room=self.pos:world_to_room()
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
  initialize=function(self,...)
    component.initialize(self,...)
    self.tpos=self.pos
  end,
  tick=function(self)
    self.pos=self.tpos*8+4
    if self.ticks==0 then
      train:new(self.tpos, {facing=self.facing})
      self.ticks=self.interval
    end
    self.ticks-=1
  end,
})
actor_sensor=component:copy({
  layer=layer.bg,
  connections={o(0,0)},
  coffs=vector.zero,
  sq={1,0},
  dtype='train',
  initialize=function(self,...)
    component.initialize(self,...)
    self.connections[1]._pos+=self.coffs
    self.connections[1].facing=self.facing
  end,
  tick=function(self)
    local c=self.connections[1]
    c.powered=false
    for a in all(actors) do
      if (a.type == self.dtype and a:touching(self)) c.powered=true
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
  coffs=vector.zero,
  initialize=function(self,...)
    component.initialize(self,...)
    self.tpos=self.pos
    self.connections[1]._pos+=self.coffs
    self.connections[1].facing=self.facing
  end,
  tick=function(self)
    self.pos=self.tpos*8+4
    if (not self.orig) self.orig=world:tile_at(self.pos)
    local tile=self.pos:world_to_tile()
    for a in all(actors) do if a != self and a.tpos == tile then return end end
    self.curtile=self.connections[1].powered and self.tile or self.orig
    world:tile_set(self.pos, self.curtile)
  end,
  draw=function(self)
    component.draw(self)
    local othertile=self.curtile==self.orig and self.tile or self.orig
    -- spr(othertile, self.pos.x-4, self.pos.y-4)
    pal(5, 10)
    spr(self.curtile, self.pos.x-4, self.pos.y-4)
    pal()
  end,
})

simulation={
  tick=function(self)
    for a in all(actors) do
      if(a.tick) a:tick()
    end
    for c in all(connections) do
      if (c.input and not c.conn) c.powered=false
      if c.output then
        if (c.wire) c.wire.powered=c.powered
        if (c.conn) c.conn.powered=c.powered
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
    b.conn=nil
  end,
}

flag_walk=0
world={
  rooms={
    [0]={
      [2]={
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
          timed:new(v{18, 120}),
          timed:new(v{29, 120}, {powered=true}),
          door:new(v{24,87}, {doorway={1,0,2,0}}),
          and_:new(v{23,56}),
          switch:new(v{18, 76}),
          switch:new(v{28, 76}),
          door:new(v{48, 45}, {doorway={0,1,0,2},facing=west}),
          switch:new(v{60, 76}, {powered=true}),
          not_:new(v{68,56}),
          door:new(v{96, 45}, {doorway={0,1,0,2},facing=west}),
          train_spawn:new(v{12, 0}),
        },
        wires={{4,3,7,1}, {8,1,9,1}, {9,2,10,1}},
      },
      [3]={
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
          switch:new(v{12,116}),
          door:new(v{29,94}, {doorway={1,0,2,0}}),
          switch:new(v{12,44}),
          door:new(v{49,20}, {doorway={0,1,0,2}, facing=west}),
          or_:new(v{112,20}),
        },
        wires={{1,1,2,1}},
      }
    },
    [1]={
      [2]={
        actors={
          toggle:new(v{30, 70}),
          actor_sensor:new(v{20,28}, {coffs=v{0,2},facing=south}),
          actor_sensor:new(v{60,44}, {coffs=v{0,2},facing=south}),
          track_replacer:new(v{5,3},{coffs=v{-2,4},facing=west,tile=7}),
          actor_sensor:new(v{108,20}, {coffs=v{2,0},facing=east,sq={0,1}}),
          toggle:new(v{104,60}),
          door:new(v{78,50}, {doorway={0,1,0,4},facing=east}),
          door:new(v{90,121}, {doorway={1,0,2,1},facing=north}),
          switch:new(v{116,116},{flipx=true}),
          and_:new(v{107,76}),
          actor_sensor:new(v{92,8},{coffs=v{-2,0},facing=west,sq={0,1}}),
        },
        text={
          {10,102,"toggles retain"},
          {10,109,"their last value"},
        },
        wires={{2,1,1,1},{3,1,1,2},{4,1,1,4},{5,1,10,2},{10,3,6,2},{6,4,7,1},{8,1,9,1},{11,1,10,1}},
      },
      [3]={
        actors={
          actor_sensor:new(v{104,92},{coffs=v{0,-2},facing=north}),
          actor_sensor:new(v{112,28},{coffs=v{0,2},facing=south}),
          toggle:new(v{102,72}),
          track_replacer:new(v{10,7},{coffs=v{3,2},tile=38}),
        },
        text={
          {5,102,"\x8btutorial"},
          -- {100,22,"game\x91"},
        },
        wires={{1,1,3,2},{2,1,3,1},{3,4,4,1}},
      },
    },
    [2]={
      [3]={
        actors={
          train_spawn:new(v{6,6}),
        },
        text={
        },
      }
    },
    [3]={
    },
  },
  tile_at=function(self, pos)
    return mget(pos.x/8, pos.y/8)
  end,
  tile_set=function(self, pos, tile)
    mset(pos.x/8, pos.y/8, tile)
  end,
  walkable=function(self, pos)
    if (devmode) return true
    local tile=self:tile_at(pos)
    return not fget(tile, flag_walk)
  end,
  switch_rooms=function(self, newroom)
    room=newroom
    roomcoords=room*128
    player:room_switched()
  end,
  init=function(self)
    for x,z in pairs(self.rooms) do
      for y,r in pairs(z) do
        local coord=v{x,y}
        for a in all(r.actors or {}) do
          a.room=coord
          a.pos+=coord*128
          if (a.tpos) a.tpos+=coord*16 a.pos=a.tpos*8+4
        end
        for w in all(r.wires or {}) do
          simulation:connect(r.actors[w[1]].connections[w[2]], r.actors[w[3]].connections[w[4]])
        end
      end
    end
  end,
  update=function(self)
    if (connflash > 0) connflash-=1
  end,
  draw_room=function(self)
    local roomdata=self.rooms[room.x][room.y]
    if roomdata and roomdata.text then
      for t in all(roomdata.text) do
        print(t[3], t[1]+roomcoords.x, t[2]+roomcoords.y, text_color)
      end
    end
  end,
}

pickup_distance=3
playerclass=actor:copy({
  w=.5,
  h=.5,
  holding=nil,
  wire_type=1,
  initialize=function(self,pos)
    self.pos=pos
  end,
  btn4=0,
  btn5=0,
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
    if (self.btn4>3) speed=3 self.did_run=true
    local newpos=self.pos+dist*speed
    if (not world:walkable(newpos)) newpos=self.pos+dist
    if world:walkable(newpos) then
      if (self.holding) self.holding:move(newpos-self.pos)
      self.pos=newpos
    end
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
    else
      self:solder()
    end
  end,
  pickup=function(self)
    if self.holding then
      self.holding=nil
    else
      for a in all(actors) do
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
    for c in all(connections) do
      if (self.pos-c:connpos()):length() < pickup_distance then
        target=c
        break
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
    self.solder_start=nil
  end,
  draw=function(self)
    if self.solder_start then
      local apos=self.solder_start:connpos()
      local bpos=self.pos
      wire.draw_types[self.wire_type](apos, bpos, wire_color)
    end
    local color=10
    rect(self.pos.x-1, self.pos.y-1, self.pos.x+1, self.pos.y+1, color)
  end,
})

cartdata_base=0x5e00

function _init()
  cartdata("codekitchen_circuits_v1")
  set_devmode()
  world:init()
  local start_pos=v{150,498}
  -- start_pos=v{140,320}
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
  local proom=player.pos:world_to_room()
  if (proom != room) world:switch_rooms(proom)
end

function move_cam_draw_map()
  camera(roomcoords.x, roomcoords.y)
  local mapcoords=room*16
  map(mapcoords.x, mapcoords.y, roomcoords.x, roomcoords.y, 16, 16)
end

function _draw()
  cls()
  move_cam_draw_map()
  world:draw_room()
  draw_actors()
end

function set_devmode()
  devmode=peek(cartdata_base)>0
  menuitem(5, "devmode"..(devmode and " \x82" or ''), function() poke(cartdata_base, devmode and 0 or 1) set_devmode() end)
end

function dbg(str)
  if (devmode) printh(str, "debug")
end
__gfx__
000000000700000000700000070000000070000000000000000000000000000000000000cccccccc000000000000000000000000000000000000000000000000
000000007070000007070000707770000700000000000000000000000000000000000000cccccccc000000000000000000000000000000000000000000000000
000000000700000070707000070000007077700000000000005555555555555555555500cc0000cc000000000000000000000000000000000000000000000000
000000000700000000700000000000000700000000000000005400400040004004004500cc0000cc000000000000000000000000000000000000000000000000
00000000070000000070000000000000007000000000000000504040004000400404050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500555555555555550050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000544500000000000054450000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500500000000000050050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000500500000330000333000000000000000000000000000000000000000000000000000000000000
00000000000000000000000044444440044444440000000000500500003553003555330000000000000000000000000000000000000000000000000000000000
0000000000000000000000004444444004444444000000000054450003a33a3035335a3000000000000000000000000000000000000000000000000000000000
00000000000000000000000044444444444444440000000000500500035335303533335300000000000000000000000000000000000000000000000000000000
00040000004440000044400044444444444444440000000000500500353333533533335300000000000000000000000000000000000000000000000000000000
000400000440440004404400444444400444444400000000005005003533335335335a3000000000000000000000000000000000000000000000000000000000
00404000040004000400040044444440044444440000000000544500355555533555330000000000000000000000000000000000000000000000000000000000
00040000440004404400044000000000000000000000000000500500033333300333000000000000000000000000000000000000000000000000000000000000
00404000400000404000004000000000000000000000000000500500000000000050050000000000000000000000000000000000000000000000000000000000
04000400400000404004004000000000000000000000000000544500000000000054450000000000000000000000000000000000000000000000000000000000
40000040400000404040404000000000000000000000000000500555555555555550050000000000000000000000000000000000000000000000000000000000
44444440444444404400044000000000000000000000000000504040008000800404050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000540040008000800400450000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000555555555555555555550000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000880000000000000000000000000000000000000000000
0dddd0000dddd0000000000000000000000000000000000000000000000000000000000000000000008888000000000000000000000000000000000000000000
0d0000000d0070000000000000000000000000000000000000000000000000000000000000000000008888000000000000000000000000000000000000000000
0d0000070d0070000000000000000000000000000000000000000000000000000000000000000000008888000000000000000000000000000000000000000000
0d0000700d0070000000000000000000000000000000000000000000000000000000000000000000008888000000000000000000000000000000000000000000
0d0007000d0070000000000000000000000000000000000000000000000000000000000000000000888888880000000000000000000000000000000000000000
0ddd70000ddd70000000000000000000000000000000000000000000000000000000000000000000008888000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccc999999990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040461040404040000607070707070707080049004040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000061000004040000627080000004000061006100040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000062708004040000000061000004000061006100040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404006270707070707061707070708061006100040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000061000004006161006100040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000062707070708262708200040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000000000000040000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000000000000000000000000040000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000004000004040000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404000004040404040404040404040000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040404040404040404040404000004040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040400000404040404040404040404040404000004040000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040400000404040404040404040404040404040404040404040404040404040404040404040400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000000000004040000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000000000004040000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000060707070707070000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000006082000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000004000000000000000004040000000000000000006100000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040400000004040404040404040404040000000000000000006100000000040400000000006100000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000006070707070707070707070708200000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000006100000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000006100000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000006280000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404000004040404040404040404040000000000000000000062707070707070000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000000000000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000000000000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04000000000000000000000000000004040000000000000000000000000000040400000000000000000000000000000400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
04040404040404040404040404040404040404040404040404040404040404040404040404040404040404040404040400000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
cccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccccccccccccccccccccccccccccccccccc
cccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccccccccccccccccccccccccccccccccccc
cccccccc00555555555555555555555555555555555555555555555555555555555555555555555555555500cccccccccccccccccc0000cccccccccccccccccc
cccccccc00540040004000400040004000400040004000400040004000400040004000400040004004004500cccccccccccccccccc0000cccccccccccccccccc
cccccccc00504040004000400040004000400040004000400040004000400040004000400040004004040500cccccccccccccccc00000000cccccccccccccccc
cccccccc00500555555555555555555555555555555555555555555555555555555555555555555555500500cccccccccccccccc00000000cccccccccccccccc
cccccccc00544500000000000000000000000000000000000000000000000000000000000000000000544500cccccccccccccccc00000000cccccccccccccccc
cccccccc00500500000000000000000000000000000000000000000000000000000000000000000000500500cccccccccccccccc00000000cccccccccccccccc
cccccccc00500500000000000000000000000000000000000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00544500000000000000000000000000000000000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00500555555555555555555555555555555555000000000000000000cccccccc000000000054450000000000000000000054450000000000cccccccc
cccccccc0050404000400040004aaa4000400040040045000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc0054004000400040004aaa4000400040040405000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00555555555555555555555555555555555005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005445000000000000000000cccccccc000000000054450000000000000000000054450000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005445000000000000000000cccccccc000000000054450000000000000000000054450000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
cccccccc00000000000000000000000000000000005445000000000000000000cccccccc000000000054450000000000000000000054450000000000cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000050050000000000000000000050050000000000cccccccc
000000000000000000000000000000000000000000a00a00000000000000000000000000000000000050050000000000000000000050050000000000cccccccc
000000000000000000000000000000000000000000a00a00000000000000000000000000000000000054450000000000000000000050050000000000cccccccc
555555555555555555555555555555555555555500a44a00555555555555555555555555555555555550050000000000000000000054450000000070cccccccc
0040004000400040004aaa40004000400040004000a00a0000400040004000400040004000400040040405000000000000000000005aa50000000700cccccccc
0040004000400040004aaa40004000400040004000a00a0000400040004000400040004000400040040045000000000000000000005aa500000077777ccccccc
555555555555555555555555555555555555555500a00a0055555555555555555555555555555555555555000000000000000000005aa50000000700cccccccc
000000000000000000000000000000000000000000a44a00000000000000000000000000000000000000000000000000000000000054450000000770cccccccc
000000000000000000000000000000000000000000a00a00000000000000000000000000000000000000000000000000000000000050050000000700cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000000000000000000000000000050050000000700cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000000000000000000000000000050050000000700cccccccc
cccccccc00000000000000000000000000000000005445000000000000000000cccccccc000000000000000000000000000000000054450000000700cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000000000000000000000000000050050000000700cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000000000000000000000000000050050000000700cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000000000000000000000000000050050000000700cccccccc
cccccccc00000000000000000000000000000000005445000000000000000000cccccccc000000000000000000000000000000000054450000000700cccccccc
cccccccc00000000000000000000000000000000005005000000000000000000cccccccc000000000000000000000000000000000050050000000700cccccccc
cccccccc0000000000000000000000000000000000500500000000000000000000000000000000000000000000000000000000000050050000000700cccccccc
cccccccc0000000000000000000000000000000000544500000000000000000000000000000000000000000000000000000000000054450000000700cccccccc
cccccccc0000000000000000000000000000000000500555555555555555555555555555555555555555555555555555555555555550050000000700cccccccc
cccccccc0000000000000000000000000000000000504040004000400040004000400040004000400040004000400040004000400404050000000700cccccccc
cccccccc0000000000000000000000000000000000540040004000400040004000400040004000400040004000400040004000400400450000000700cccccccc
cccccccc0000000000000000000000000000000000555555555555555555555555555555555555555555555555555555555555555555550000000700cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
cccccccccccccccccccccccccccccccccccccccccccc7ccccccccccccccccccccccccccccccccccc0000000000000000000000000000000000000700cccccccc
000000000000000000000000000000000000000000007000000000000000000000000000cccccccc0000000000000000000000000000000000000700cccccccc
000000000000000000000000000000000000000000007000000000000000000000000000cccccccc0000000000000000000000000000000000000700cccccccc
000000000000000000000000000000077777777777777700000000000000000000000000cccccccc0000000000000000000000000000000000000700cccccccc
000000000000000000000000000000070000000000007000000000000000000000000000cccccccc0000000000000000000000000000000000000700cccccccc
000000000000000000000000000000070000000000000000000000000000000000000000cccccccc0000000000000000000000000000000000000700cccccccc
000000000000000000000000000000070000000000000000000000000000000000000000cccccccc0700000000000000000000000000000000000700cccccccc
000000000000000000000090000000070000000000000000000000000000000000000000cccccc777777777777777777777777777777777000000700cccccccc
000000000000000000000909000000070000000000000000000000000000000000000000cccccccc0700000000000000000000000000007000000700cccccccc
000000000000000000009090900000777000000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000700cccccccc
000000000000000000000090000007070700000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000700cccccccc
000000000000000000000090000000070000000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000700cccccccc
000000000000000000044444440044444440000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000700cccccccc
000000000000000000049999940044444440000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000700cccccccc
000000000000000000049999944444444440000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000700cccccccc
000000000000000000049999944444444440000000000000000000000000000000000000cccccccc0000000000000000000009000000007000000700cccccccc
000000000000000000049999940044444440000000000000000000000000000000000000cccccccc0000000000000000000090900000007000000700cccccccc
cccccccc0000000000044444440044444440000000000000000000000000000000000000cccccccc0000000000000000000909090000077700000700cccccccc
cccccccc0000000000000070000000070000000000000000000000000000000000000000cccccccc0000000000000000000009000000707070000700cccccccc
cccccccc0000000000000070000000070000000000000000000000000000000000000000cccccccc0000000000000000000009000000007000000700cccccccc
cccccccc0000000000007777000000070000000000000000000000000000000000000000cccccccc0000000000000000004444444004444444000700cccccccc
cccccccc0000000000007070000077777000000000000000000000000000000000000000cccccccc0000000000000000004999994004444444000700cccccccc
cccccccc00000000000070000000700700000000000000000000aaa00000000000000000cccccccc0000000000000000004999994444444444000700cccccccc
cccccccc00000000000070000000700000000000000000000000a0a00000000000000000cccccccc0000000000000000004999994444444444000700cccccccc
cccccccc00000000000070000000700000000000000000000000aaa00000000000000000cccccccc0000000000000000004999994004444444000700cccccccc
cccccccc0000000000007000000070000000000000000000000000000000000000000000cccccccc0000000000000000004444444004444444000700cccccccc
cccccccc0000000000007000000070000000000000000000000000000000000000000000cccccccc0000000000000000000007000000007000000700cccccccc
cccccccc0000000000007000000070000000000000000000000000000000000000000000cccccccc0000000000000000000007000000007000000700cccccccc
cccccccc0000000000007000000070000000000000000000000000000000000000000000cccccccc0000000000000000000070700000007000000700cccccccc
cccccccc0000000000007000000070000000000000000000000000000000000000000000cccccccc0000000000000000000007000000077777777700cccccccc
cccccccc0000000000077700000777000000000000000000000000000000000000000000cccccccc0000000000000000000000000000007000000000cccccccc
cccccccc0000000000707070007070700000000000000000000000000000000000000000cccccccc0000000000000000000000000000000000000000cccccccc
cccccccc0000000000007000000070000000000000000000000000000000000000000000cccccccc0000000000000000000000000000000000000000cccccccc
cccccccccccccccccccc7ccccccc7ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0066606000666066600000666006600660066060006660066000006660660066000000666060606660606000000000000000000000000000cccccccc
cccccccc0060006000060060600000060060606000600060006000600000006060606060600000060060606000606000000000000000000000000000cccccccc
cccccccc0066006000060066600000060060606000600060006600666000006660606060600000060066606600666000000000000000000000000000cccccccc
cccccccc0060006000060060000000060060606060606060006000006000006060606060600000060060606000006000000000000000000000000000cccccccc
cccccccc0060006660666060000000060066006660666066606660660000006060606066600000060060606660666000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0066600660606066606660000060606600666066606000000066606000666066606660666066000000666006606660666066000000000000cccccccc
cccccccc0060606060606060006060000060606060060006006000000060006000060060606060600060600000606060006060060060600000000000cccccccc
cccccccc0066606060606066006600000060606060060006006000000066006000060066606660660060600000666060006660060060600000000000cccccccc
cccccccc0060006060666060006060000060606060060006006000000060006000060060006000600060600000606060606060060060600000000000cccccccc
cccccccc0060006600666066606060000006606060060066606660000060006660666060006000666066600000606066606060666060600000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006666600000000000000cccccccc
cccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000066000660000000000000cccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000660006600000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000666066600000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000066666000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc0000000000000000cccccccccccccccc

__gff__
00000000000019150d090000000000000000000000000b000000000000000000000000000000130007000000000000000000000000000000000000000000000001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000004040404040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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

