--!strict
--[[
	HandbookPanel — «Справочник механик» (§15х ч.5): окно-витрина CardKit; §15ц Ц4б — три вкладки ВОЙНА · ДЕРЖАВА ·
	МИР, внутри — разделы с заголовком (Handbook.Sections). У каждой механики —
	строка-карточка: картинка ItemArt слева, справа название и три строки «Что это · Как запустить · Чем защититься»
	(или «Как помешать»). Список, вкладки и картинки — чистый Shared.Handbook, тексты — Strings «handbook.*».
	Открывается кнопкой «Справочник механик» в окне «Как играть» (H); закрывается «×» и Esc.
	Карточки строятся при первом открытии (картинки — EditableImage, без них окно ничего не стоит).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Handbook = require(Shared:WaitForChild("Handbook"))
local ItemArt = require(Shared:WaitForChild("ItemArt"))
local Strings = require(Shared:WaitForChild("Strings"))

local CardKit = require(script.Parent:WaitForChild("CardKit"))
local MenuKit = require(script.Parent:WaitForChild("MenuKit"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type HandbookPanel = {
	frame: Frame,
	open: (tab: string?) -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
}

local HandbookPanel = {}

local WIDTH = 980
local HEIGHT = 660
local ART_W = 120
local ART_H = math.floor(ART_W * ItemArt.H / ItemArt.W)
local PAD = 8

-- Цвет подписи третьей строки: защита — голубой (как своя ПВО), помешать врагу — оранжевый.
local COUNTER_COLOR: { [string]: string } = { defense = "Sky", hinder = "Orange" }

-- Строка «<b>Подпись:</b> текст» с цветной подписью.
local function line(label: string, color: Color3, text: string): string
	return string.format('<font color="#%s"><b>%s:</b></font> %s', color:ToHex(), label, text)
end

function HandbookPanel.new(gui: ScreenGui, lang: Strings.Lang): HandbookPanel
	local function t(key: string): string
		return Strings.get(key, lang)
	end
	local tabs: { { key: string, label: string } } = {}
	local kinds: { [string]: string } = {}
	for _, tab in Handbook.Tabs do
		table.insert(tabs, { key = tab, label = t("handbook.tab." .. tab) })
		kinds[tab] = "list"
	end
	local win = CardKit.window(gui, "Handbook", t("handbook.title"), t("handbook.subtitle"), WIDTH, HEIGHT, tabs, kinds)
	local frame = win.frame

	local function row(page: Instance, e: Handbook.Entry, order: number)
		local keys = Handbook.textKeys(e)
		local f = Instance.new("Frame")
		f.Name = "Mechanic_" .. e.key
		f.LayoutOrder = order
		f.Size = UDim2.fromScale(1, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.BackgroundColor3 = Theme.Colors.Backdrop
		f.BorderSizePixel = 0
		f.Parent = page
		MenuKit.stroke(f, Theme.Colors.PanelBorder, 2)
		MenuKit.pad(f, PAD, PAD)
		local list = MenuKit.list(f, 14, true)
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		local art = CardKit.art(f, e.art, ART_W, ART_H)
		art.LayoutOrder = 1
		local body = Instance.new("Frame")
		body.Name = "Body"
		body.LayoutOrder = 2
		body.BackgroundTransparency = 1
		body.Size = UDim2.new(1, -(ART_W + 14), 0, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Parent = f
		MenuKit.list(body, 4)
		MenuKit.label(body, t(keys.name), 17, Theme.Colors.Gold, true, 1)
		local counter = Handbook.counter(e)
		local rows = {
			{ label = t("handbook.what"), color = Theme.Colors.Text, text = t(keys.what) },
			{ label = t("handbook.how"), color = Theme.Colors.Good, text = t(keys.how) },
			{ label = t("handbook." .. counter), color = Theme.color(COUNTER_COLOR[counter]), text = t(keys.counter) },
		}
		for k, r in rows do
			local l = MenuKit.wrapLabel(body, line(r.label, r.color, r.text), 13, Theme.Colors.Text, k + 1)
			l.TextYAlignment = Enum.TextYAlignment.Top
		end
	end

	-- §15ц Ц4б: заголовок раздела внутри вкладки-группы.
	local function sectionHead(page: Instance, section: string, order: number)
		local head = MenuKit.label(page, t("handbook.section." .. section), 18, Theme.Colors.Sky, true, order)
		head.Name = "Section_" .. section
	end

	local built = false
	local function build()
		if built then
			return
		end
		built = true
		for _, tab in Handbook.Tabs do
			local page = win.page(tab)
			local order = 0
			for _, section in Handbook.Sections[tab] do
				order += 1
				sectionHead(page, section, order)
				for _, e in Handbook.inSection(tab, section) do
					order += 1
					row(page, e, order)
				end
			end
		end
	end

	local function open(tab: string?)
		build()
		if tab ~= nil and table.find(Handbook.Tabs, tab) ~= nil then
			win.setTab(tab)
		end
		frame.Visible = true
	end

	return {
		frame = frame,
		open = open,
		toggle = function()
			if frame.Visible then
				frame.Visible = false
			else
				open(nil)
			end
		end,
		isOpen = function(): boolean
			return frame.Visible
		end,
	}
end

return table.freeze(HandbookPanel)
