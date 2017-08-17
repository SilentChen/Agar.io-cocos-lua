local net = require("net")
local ball = require("ball")
local config = require("config")
local star = require("star")
local M = {}

local scene = {}
scene.__index = scene

M.visibleSize = cc.Director:getInstance():getVisibleSize()
M.origin = cc.Director:getInstance():getVisibleOrigin()
M.delayTick = 120

--场景大小
M.width = config.mapWidth
M.height = config.mapWidth

M.viewBounderyBottomLeft = {
	x = 0 - M.visibleSize.width/2,
	y = 0 - M.visibleSize.height/2
}

M.viewBounderyTopRight = {
	x = M.width + M.visibleSize.width/2,
	y = M.height + M.visibleSize.height/2
}


M.New = function ()
	local o = {}   
	o = setmetatable(o, scene)
	return o
end

--返回通过本地tick估算的serverTick
function scene:GetServerTick()
	return self.gameTick --+ self.serverTickDelta
end

function scene:viewPort2Screen(viewPortPos)
	viewPortPos.x = viewPortPos.x * self.scaleFactor + M.origin.x
	viewPortPos.y = viewPortPos.y * self.scaleFactor + M.origin.y
	return viewPortPos
end

function scene:world2ViewPort(worldPos)
	local screenPos = {}
	screenPos.x = worldPos.x - self.viewPort.leftBottom.x
	screenPos.y = worldPos.y - self.viewPort.leftBottom.y
	return screenPos
end

function scene:isInViewPort(viewPortPos)
	if viewPortPos.x < 0 then
		return false
	end

	if viewPortPos.y < 0 then
		return false
	end

	if viewPortPos.x > self.viewPort.width then
		return false
	end

	if viewPortPos.y > self.viewPort.height then
		return false
	end

	return true	
end


--根据ball的坐标,更新屏幕左下角在世界坐标的位置
function scene:updateViewPortLeftBottom()
	local leftBottom = {}
	leftBottom.x = self.centralPos.x - self.viewPort.width/2
	leftBottom.y = self.centralPos.y - self.viewPort.height/2

	--根据边界修正坐标

	if leftBottom.x < M.viewBounderyBottomLeft.x then
		leftBottom.x = M.viewBounderyBottomLeft.x
	end

	if leftBottom.y < M.viewBounderyBottomLeft.y  then
		leftBottom.y = M.viewBounderyBottomLeft.y
	end

	if leftBottom.x + self.viewPort.width > M.viewBounderyTopRight.x then
		leftBottom.x = M.viewBounderyTopRight.x - self.viewPort.width
	end

	if leftBottom.y + self.viewPort.height > M.viewBounderyTopRight.y then
		leftBottom.y = M.viewBounderyTopRight.y - self.viewPort.height
	end	

	self.viewPort.leftBottom = leftBottom

end

function scene:setViewPort(width,height)
    self.viewPort = self.viewPort or {}	
    self.viewPort.width = width
    self.viewPort.height = height
    self.scaleFactor = M.visibleSize.width/self.viewPort.width
    cclog("scaleFactor:%f",self.scaleFactor)
end

function scene:Init(drawer)
	cclog("(%d, %d, %d, %d)", M.origin.x, M.origin.y, M.visibleSize.width, M.visibleSize.height)
	self.serverTickDelta = 0
	self.gameTick = 0
	self.lastTick = net.GetSysTick()
	self.drawer = drawer
    self.balls = {}
    self.delayMsgQue = {}
    self.centralPos = {x = M.width/2, y = M.height/2 }
    self:setViewPort(M.visibleSize.width,M.visibleSize.height)    
    self:updateViewPortLeftBottom()
	return self
end

function scene:UpdateTick()
	local nowTick = net.GetSysTick()
	if self.lastFixTime then
		if nowTick - self.lastFixTime > 1000 then
			local wpk = net.NewWPacket()
    		wpk:WriteTable({cmd="FixTime",clientTick=nowTick})
    		send2Server(wpk)
			self.lastFixTime = nowTick
		end
	end
	self.elapse = nowTick - self.lastTick	
	self.gameTick = self.gameTick + self.elapse
	self.lastTick = nowTick
end

function scene:Update()
	local elapse = self.elapse
	self:processDelayMsg()
	local ownBallCount = 0
	local cx = 0
	local cy = 0
	for k,v in pairs(self.balls) do
		v:Update(elapse)
		if v.userID == userID then
			cx = cx + v.pos.x
			cy = cy + v.pos.y
			ownBallCount = ownBallCount + 1
		end
	end
	if ownBallCount > 0 then
		self.centralPos.x = cx/ownBallCount --(self.centralPos.x + cx) / 2
		self.centralPos.y = cy/ownBallCount --(self.centralPos.y + cy) / 2
		self:updateViewPortLeftBottom()
	end
end

function scene:Render()
    self.drawer:clear()
    star.Render(self)
    for k,v in pairs(self.balls) do
    	local viewPortPos = self:world2ViewPort(v.pos)

    	local topLeft = {x = viewPortPos.x - v.r , y = viewPortPos.y + v.r}
    	local bottomLeft = {x = viewPortPos.x - v.r , y = viewPortPos.y - v.r}
    	local topRight = {x = viewPortPos.x + v.r , y = viewPortPos.y + v.r}
    	local bottomRight = {x = viewPortPos.x + v.r , y = viewPortPos.y - v.r}

    	if self:isInViewPort(topLeft) or self:isInViewPort(bottomLeft) or self:isInViewPort(topRight) or self:isInViewPort(bottomRight) then
    		local screenPos = self:viewPort2Screen(viewPortPos)
    		self.drawer:drawSolidCircle(cc.p(screenPos.x ,screenPos.y), v.r * self.scaleFactor, math.pi/2, 50, 1.0, 1.0, v.color)
    	end	
    end
end

M.msgHandler = {}


M.msgHandler["Login"] = function (self,event)
	cclog("LoginOK")
    local wpk = net.NewWPacket()
    wpk:WriteTable({cmd="EnterBattle"})
    send2Server(wpk)	
end

M.msgHandler["FixTime"] = function (self,event)
	local nowTick = net.GetSysTick()
	local elapse = nowTick - self.lastTick
	--cclog("FixTime %d %d %d",elapse , nowTick - event.clientTick , event.clientTick)	 
	--print(event.serverTick - self.gameTick)	
	self.gameTick = event.serverTick - elapse
	self.lastFixTime = nowTick
end

M.msgHandler["ServerTick"] = function (self,event)
	local nowTick = net.GetSysTick()
	local elapse = nowTick - self.lastTick 
	self.gameTick = event.serverTick - elapse
	self.lastFixTime = nowTick	
end

M.msgHandler["BeginSee"] = function (self,event)
	--cclog("localServerTick %d,event.timestamp %d",self:GetServerTick(),event.timestamp)
	for k,v in pairs(event.balls) do
		--cclog("BeginSee ballID:%d,pos(%d,%d)",v.id,v.pos.x,v.pos.y)
		local color = config.colors[v.color]
		color = cc.c4f(color[1],color[2],color[3],color[4])
		local newBall = ball.new(self,v.userID,v.id,v.pos,color,v.r,v.velocitys)
		self.balls[newBall.id] = newBall
	end
end

M.msgHandler["EndSee"] = function (self,event)
	cclog("endsee %d",event.id)
	self.balls[event.id] = nil	
	--cclog("localServerTick %d,event.timestamp %d",self:GetServerTick(),event.timestamp)
	--for k,v in pairs(event.balls) do
		--cclog("BeginSee ballID:%d,pos(%d,%d)",v.id,v.pos.x,v.pos.y)
	--	local color = config.colors[v.color]
	--	color = cc.c4f(color[1],color[2],color[3],color[4])
	--	local newBall = ball.new(self,v.userID,v.id,v.pos,color,v.r,v.velocitys)
	--	self.balls[newBall.id] = newBall
	--end
end

M.msgHandler["BallUpdate"] = function(self,event)
	local ball = self.balls[event.id]
	ball:OnBallUpdate(event)
end

M.msgHandler["EnterRoom"] = function(self,event)
	cclog("star count:%d",#event.stars * 32)
	star.OnStars(event)
end

M.msgHandler["StarDead"] = function(self,event)
	star.OnStarDead(event)
end

M.msgHandler["StarRelive"] = function(self,event)
	star.OnStarRelive(event)
end

function scene:processDelayMsg()
	local tick = self:GetServerTick()
	while #self.delayMsgQue > 0 do
		local msg = self.delayMsgQue[1]
		if msg.timestamp <= tick then
			table.remove(self.delayMsgQue,1)
			--cclog("processDelayMsg:%s",msg.cmd)
			local handler = M.msgHandler[msg.cmd]
			if handler then
				handler(self,msg)
			end			
		else
			return
		end
	end
end

function scene:DispatchEvent(event)
	local cmd = event.cmd
	--有timestamp参数的消息需要延时处理
	if event.timestamp then
		--将消息延时M.delayTick处理
		local nowTick = net.GetSysTick()
		local elapse = nowTick - self.lastTick
		--cclog("msg delay:%d,elapse:%d",self:GetServerTick() - event.timestamp + elapse,elapse)		 
		event.timestamp = event.timestamp + M.delayTick - elapse
		table.insert(self.delayMsgQue,event)
		return
	end
	--cclog("DispatchEvent:%s",cmd)
	local handler = M.msgHandler[cmd]
	if handler then
		handler(self,event)
	end
end


return M