--[[
Initializing : 
	local DragIt = require(PathToModule)
	
	Setting a Gui :
	local GuiData = DragIt.Drag(Gui,Boundary,Clippings,AutoClip)
	
	Gui : Gui to be dragged
	Boundary  : Boundary for the gui , leave nil if none
	Clippings : Array of Guis to which the Draggable Gui should be clipped to , leave nil if none.
	AutoClip  : Automatically clips to the previous Clipped Gui
	ResponeTime : A number between 0-1 indicating the speed of the Gui's response , leave this as nil if you need instant movement
	Snappings : An array containing guis to which the Dragged gui can be snapped to.
	
	DragIt.Drag returns a dictionary with these methods :
	1) SetData(Data) -- GuiData:SetData(Data)
	Data : A dictionary , example : {Boundary=Boundarygui,Clippings={PlaceHolder1,PlaceHolder2}}
	
	2) Destroy -- GuiData:Destroy()
	To destroy the Dragging connection , makes the Gui unable to drag and cleans its memory.
	
	Settings :
	HoverIcon    : The Icon for mouse while hovering a gui
	DraggingIcon : The Icon for mouse while dragging 
	PriorityIcon : This Defines the Icon to which more priority should be given , "Hover" for HoverIcon "Dragging" for DraggingIcon
	Priority     : This Defines whether "Clipping" or "Snapping" should be more prioritized.
	
	Event :
	DragStart : Fires when the Gui starts to be dragged
	DragEnd : Fires when the Gui stops being dragged
]]


local RS = game:GetService('RunService')
local IsClient = RS:IsClient()

if IsClient then

	local UIS = game:GetService('UserInputService')
	local TWS = game:GetService('TweenService')
	local Utils = require(script.Utils)
	local Player = game.Players.LocalPlayer
	local Mouse = Player:GetMouse()	
	local drag = {}
	local Events = {}
	local Holding = false
	local Hovering = false
	local camera = workspace.Camera.ViewportSize
	local centre = Vector2.new(camera.X/2, camera.Y/2)
	local Tween
	local RenderConnection

	local GuiObject = {}
	GuiObject.__index = GuiObject
	local Objects = {}
	local Settings = {
		HoverIcon = nil,
		DraggingIcon = nil,
		PriorityIcon = nil, -- This Defines the Icon to which more priority should be given , "Hover" for HoverIcon "Dragging" for DraggingIcon
		Priority = 'Snapping' -- This Defines whether "Clipping" or "Snapping" should be more prioritized.
	}

	function GuiObject:SetData(Data)
		for i , v in pairs(Data) do
			self[i]=v
		end
	end

	function GuiObject:Destroy()
		local Index = table.find(Objects,self)
		if Index then
			if Events[self] then
				for _ , v in ipairs(Events[self]) do
					if v then v:Destroy() end
				end
				Events[self] = nil
			end
			if self._InputCheck then
				self._InputCheck:Disconnect() 
				self._InputCheck = nil
			end
			
			
			table.remove(Objects,Index)
			if #Objects == 0 and RenderConnection then
				RenderConnection:Disconnect()
				RenderConnection = nil
			end
		end
	end
	coroutine.wrap(function()
		while Settings.HoverIcon do
			RS.RenderStepped:Wait()
			if Settings.PriorityIcon=='Hover' or not Holding then
				local CanSet = true
				for _ ,v  in ipairs(Objects) do
					if v.CanDrag then
						CanSet = false
						break
					end
				end
				
				if CanSet then
					local MousePos = Vector2.new(Mouse.X,Mouse.Y)
					local Guis = Player.PlayerGui:GetGuiObjectsAtPosition(MousePos.X,MousePos.Y) 
					if #Guis >= 1 then
						Hovering = true
						if Settings.HoverIcon then
							Mouse.Icon = Settings.HoverIcon
						end
					else
						Hovering = false
						Mouse.Icon =''
					end
				end
			end
		end
	
	end)()

	drag.Drag = function(Gui,Boundary,Clippings,AutoClip,ResponseTime,Snappings)
		local self = {}
		self.Boundary = Boundary
		self.Object = Gui
		self.Clippings = Clippings
		self.CanDrag = false
		self.OldPosition = nil
		self.Clipped = nil
		self.AutoClip = AutoClip 
		self.ResponseTime = (ResponseTime and math.abs(ResponseTime))
		self.Snappings = Snappings
		self.Snapped =  nil
		
		self._InputCheck = Gui.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				local CanSet = false
				for _ , v in ipairs(Objects) do
					if v.CanDrag then
						CanSet = true
						break
					end
				end
				
				local Event = Events[self]
				
				if not CanSet then
					
					self.CanDrag = true
					Event[1]:Fire()
					
					
					local Connection
					Connection = Input.Changed:Connect(function()
						if Input.UserInputState == Enum.UserInputState.End  then
							self.CanDrag = false
							Event[2]:Fire()
							Connection:Disconnect()
						end
					end)
				end
			end
		end)
		
		local DragStart = Instance.new('BindableEvent')
		local DragEnd = Instance.new('BindableEvent')
		
		self.DragStart = DragStart.Event
		self.DragEnd = DragEnd.Event
		
		
		Events[self] ={DragStart,DragEnd}
		
		setmetatable(self,GuiObject)
		
		table.insert(Objects,self)
		
		return self
	end
	
	drag.InputBegan = UIS.InputBegan:Connect(function(Input,gp)
		if gp then return end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			for _ , v in ipairs(Objects) do
				if v.CanDrag then 
					v.OldPosition = Vector2.new(Mouse.X,Mouse.Y)
				end
			end
			RenderConnection = 	RS.RenderStepped:Connect(function(DT)
				local MousePos = Vector2.new(Mouse.X,Mouse.Y)
				local Possible = 0
				for _ , v in ipairs(Objects) do
					if v.CanDrag then
						Possible += 1
						local Position = v.Object.Position
						local Change = MousePos-v.OldPosition
						
						
						local ScaleX , ScaleY = Utils.ScaleToOffset({Position.X.Scale,Position.Y.Scale})
						local NewPos = UDim2.new(0,Position.X.Offset + Change.X + ScaleX,0,Position.Y.Offset+ Change.Y + ScaleY)						

						if v.Boundary then
							local X , Y  = Utils.CheckBoundary(v.Boundary,v.Object,Change)
							NewPos = UDim2.new(0,X ,0,Y)
						end
						local Alpha
						if v.ResponseTime then
							Alpha = DT*7*v.ResponseTime
						else
							Alpha = 1
						end
						v._Target = NewPos
						v.Object.Position = v.Object.Position:Lerp(NewPos,Alpha)
						v.OldPosition = v.OldPosition:Lerp(MousePos,Alpha)
						
						local Guis = Player.PlayerGui:GetGuiObjectsAtPosition(MousePos.X,MousePos.Y) 
						local Sorted = Utils.SortTable(v.Clippings,Guis,v.Object)
						if Sorted then
							v.Clipped = Sorted
						else
							if not v.AutoClip then
								v.Clipped = nil
							end
						end
						if v.Snappings then
							local Closest 
							local ChosenSnap 
							for _, snap in ipairs(v.Snappings) do
								if not Closest then
									Closest = (v.Object.AbsolutePosition-snap.AbsolutePosition).Magnitude
									ChosenSnap = snap
								else
									local CurrentMag = (v.Object.AbsolutePosition-snap.AbsolutePosition).Magnitude
									if CurrentMag < Closest then
										Closest = CurrentMag
										ChosenSnap = snap
									end
								end
							end
							if Closest then
								local X,Y = Utils.ScaleToOffset({ChosenSnap.Size.X.Scale,ChosenSnap.Size.Y.Scale})
								X += ChosenSnap.Size.X.Offset
								Y += ChosenSnap.Size.X.Offset
								
								local Right = (v.Object.AbsolutePosition-(ChosenSnap.AbsolutePosition+Vector2.new(X))).Magnitude * 0.0264583333
								local Left = (v.Object.AbsolutePosition-(ChosenSnap.AbsolutePosition-Vector2.new(X))).Magnitude * 0.0264583333
								local Top = (v.Object.AbsolutePosition-(ChosenSnap.AbsolutePosition+Vector2.new(0,Y))).Magnitude * 0.0264583333
								local Bottom = (v.Object.AbsolutePosition-(ChosenSnap.AbsolutePosition-Vector2.new(0,Y))).Magnitude * 0.0264583333
								
								if (Closest * 0.0264583333) <= 3.5 or Top <= 2.5 or Right <= 2.5 or Left <= 2.5 and Bottom <= 2.5 then -- Converting the Pixels to CM for easy comparing 
									v.Snap = ChosenSnap
								else
									v.Snap = nil
								end
							end
						end
					end
				end
				if Possible ~= 0 and (Settings.PriorityIcon == 'Dragging' or not Hovering)  and Settings.DraggingIcon then
					Mouse.Icon = Settings.DraggingIcon
				end
			end)
		end
	end)
	
	drag.InputEnd = UIS.InputEnded:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if RenderConnection then
				RenderConnection:Disconnect()
				RenderConnection = nil
				Mouse.Icon = ''
				for _ , v in ipairs(Objects) do
					coroutine.wrap(function()
						if v.Clipped and( not v.Snap or Settings.Priority == 'Clipping' )then
							if v.ResponseTime then
								if v.ResponseTime > 0 then
									for i = 1,10 do
										RS.RenderStepped:Wait()
										v.Object.Position = v.Object.Position:Lerp(v.Clipped.Position,i/10)
									end
								end
							else
								v.Object.Position = v.Clipped.Position
							end
							v.Object.Rotation = v.Clipped.Rotation
						end
						if v.Snap and (not v.Clipped or Settings.Priority == 'Snapping') then
							local Target = Utils.Snap(v.Snap,v.Object,v._Target )
							if v.ResponseTime then 
								for i = 1,10 do
									RS.RenderStepped:Wait()
									
									v.Object.Position = v.Object.Position :Lerp(Target,i/10)
								end
							else
								v.Object.Position = Target
							end
							v.Snap=nil
						end
					end)()
					if v.CanDrag then 
						v.OldPosition = nil
					end
				end
			end
		end
	end)	
	
	return drag
else
	return {}
end
