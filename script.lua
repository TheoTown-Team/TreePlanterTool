local minBrushSize = 3
local maxBrushSize = 25

local treeDrafts

local density
local roughness
local brushSize
local treeSelection

-- Cache drawing functions for performance reasons
local setTile = Drawing.setTile
local drawTileFrame = Drawing.drawTileFrame

-- Gets the storage table we use for saving the settings
local function getStorage()
  return Util.optStorage(TheoTown.getStorage(), script:getDraft():getId())
end

-- Save settings to storage
local function saveState()
  local stg = getStorage()
  stg.density = density
  stg.roughness = roughness
  stg.brushSize = brushSize
  stg.treeSelection = {}
  treeSelection:forEach(function(d)
    table.insert(stg.treeSelection, d:getId())
  end)
end

-- Load settings from storage
local function loadState()
  local stg = getStorage()
  treeSelection = Array()
  density = stg.density or 0.5
  roughness = stg.roughness or 0
  brushSize = stg.brushSize or 5
  if stg.treeSelection then
    for _,id in pairs(stg.treeSelection) do
      local draft = Draft.getDraft(id)
      if draft and draft:getType()=='tree' then
        treeSelection:add(draft)
      end
    end
  end
  if treeSelection:isEmpty() then
    treeSelection:add(Draft.getDraft('$tree00'))
  end
end

-- Show about dialog
local function about()
  -- Create the dialog
  local dialog = GUI.createDialog{
    icon = Icon.ABOUT,
    title = Translation.control_about,
    text = [[Tap on configure to configure the tool. Tap on the map to spawn trees.

Tree planter tool by THEMAX and Lobby.]],
    w=200,
    h=150,
    actions={
      icon=Icon.OK,
      text=Translation.control_ok,
      golden=true
    }
  }
end

-- Show configuration dialog
local function configure()
  -- Create the dialog
  local dialog = GUI.createDialog{
    icon = Icon.MENU,
    title = Translation.treeplanter_cmdconfigure,
    w=220,
    h=125,
    onClose=function() saveState() end
  }

  -- Create a vertical layout to add settings to
  local layout = dialog.content:addLayout{
    vertical = true,
    spacing=2
  }

  -- Prepare drawers
  local selectedDrawers
  local selectionChanged = function()
    selectedDrawers = Array()
    treeSelection:forEach(function(t)
      selectedDrawers:add(City.createDraftDrawer(t))
    end)
  end
  selectionChanged()

  local lw = 60
  local lh = 20
  local line

  -- Species
  line = layout:addCanvas{h=lh}
  line:addLabel{w=lw,text=Translation.treeplanter_species}
  line:addCanvas{x=lw,w=-24,h=lh,onDraw=function(self,x,y,w,h)
    Drawing.drawRect(x,y,w,h)
    if #selectedDrawers>0 then
      Drawing.setClipping(x,y,w,h)
      local size = self:getClientHeight()
      local part = self:getClientWidth() / #selectedDrawers
      for i=1,#selectedDrawers do
        selectedDrawers[i].draw(x + (i-1) * part,y,part,size)
      end
      Drawing.resetClipping()
    end
  end}
  line:addButton{text='...',x=-24,onClick=function(self)
    GUI.createSelectDraftDialog{
      drafts=treeDrafts,
      selection=treeSelection,
      multiple=true,
      minSelection=1,
      onSelect=function(selection)
        treeSelection = selection
        selectionChanged()
      end
    }
  end}

  -- Brush size
  line = layout:addCanvas{h=lh}
  line:addLabel{w=lw,text=Translation.treeplanter_brushsize}
  line:addSlider{
    x=lw,
    minValue=minBrushSize,
    maxValue=maxBrushSize,
    getValue=function() return brushSize end,
    setValue=function(v) brushSize = math.floor(v+0.5) end,
    getText=function(v) return ''..math.floor(v+0.5) end
  }

  -- Density
  line = layout:addCanvas{h=lh}
  line:addLabel{w=lw,text=Translation.treeplanter_density}
  line:addSlider{
    x=lw,
    getValue=function() return density end,
    setValue=function(v) density = v end
  }

  -- Roughness
  line = layout:addCanvas{h=lh}
  line:addLabel{w=lw,text=Translation.treeplanter_roughness}
  line:addSlider{
    x=lw,
    getValue=function() return roughness end,
    setValue=function(v) roughness = v end
  }
end


-- True if trees can be placed here in general
local function isValid(x, y)
  return Tile.isValid(x, y)
      and Tile.isLand(x, y)
      and not Tile.hasRoad(x, y)
end

-- Initialize stuff
function script:init()
  treeDrafts = Draft.getDrafts()
      :filter(function(d) return d:getType()=='tree' end)
  loadState()
end

-- Setup tool
function script:event(x, y, level, event)
  if event == Script.EVENT_TOOL_ENTER then
    -- Setup marker that will draw trees normally
    TheoTown.setToolMarker{
      markTree = true
    }

    -- Add tool action button to configure tool
    TheoTown.registerToolAction{
      icon = Icon.MENU,
      name = Translation.treeplanter_cmdconfigure,
      onClick = function()
        configure()
      end
    }
    TheoTown.registerToolAction{
      icon = Icon.ABOUT,
      name = Translation.control_about,
      onClick = function()
        about()
      end
    }

    -- Use filter for draw function for better performance since 1.9.33
    if TheoTown.setToolFilter then
      TheoTown.setToolFilter{
        water = true,    -- Call it for water
        building = true, -- or for buildings
        road = true,     -- or for road
        mouse = true     -- or for mouse location (desktop only)
      }
    end
  end
end

-- Draw tile based overlay
function script:draw(tileX, tileY, hoverX, hoverY)
  -- Mark green if mouse is over it
  if tileX == hoverX and tileY == hoverY then
    setTile(tileX, tileY)
    drawTileFrame(Icon.TOOLMARK + 16 + 1)
  end

  -- Mark red if not suitable
  if not isValid(tileX, tileY) then
    setTile(tileX, tileY)
    drawTileFrame(Icon.TOOLMARK + 16 + 2)
  end
end

-- Execute action
function script:click(tileX, tileY)
  if isValid(tileX, tileY) and not treeSelection:isEmpty() then
    local radius = math.ceil(brushSize / 2)
    local price = 0

    -- Iterate over all possible tiles and decided whether to spawn a tree
    for y=tileY-radius,tileY+radius do
      for x=tileX-radius,tileX+radius do
        -- Collect trees that can be placed here
        local candidates = Array()
        for i=1,#treeSelection do
          if Builder.isTreeBuildable(treeSelection[i], x, y) then
            candidates:add(i)
          end
        end

        if not candidates:isEmpty() then
          -- Select a tree
          local treeIdx = candidates:pick()
          local tree = treeSelection[treeIdx]

          -- Calculcate probability to spawn that tree
          local dx = x - tileX
          local dy = y - tileY
          local dist = math.sqrt(dx * dx + dy * dy)
          local prob = math.sqrt(1 - dist / (brushSize / 2))
          local alpha = prob*prob*prob*prob
          local scaling = 0.01 * brushSize
          local noise = City.noise(scaling * x, scaling * y, treeIdx)
          prob = prob * density * (alpha + (roughness+(1-roughness)*(1-alpha) * noise))

          -- Spawn the tree considering the probability
          if prob >= math.random() then
            local treePrice = Builder.getTreePrice(tree, x, y)
            if not City.canSpend(price + treePrice) then
              City.spendMoney(price, tileX, tileY)
              Debug.toast(Translation.treeplanter_outofcash)
              return
            else
              Builder.buildTree(tree, x, y)
              price = price + treePrice
            end
          end
        end
      end
    end

    -- Spend the money for the trees
    City.spendMoney(price, tileX, tileY)
  end
end
