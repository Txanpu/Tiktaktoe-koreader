local WidgetContainer = require("ui/widget/container/widgetcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")

local EnRaya = WidgetContainer:extend({
    name = "enraya",
})

function EnRaya:init()
    -- Modos: "3_normal", "3_move" (3 fichas movibles), "5_raya"
    self.mode = "3_move"
    self.vs_ai = true
    self.scores = { X = 0, O = 0 }
    self.window = nil

    self:_initBoard()
    self.ui.menu:registerToMainMenu(self)
end

function EnRaya:addToMainMenu(menu_items)
    menu_items.enraya = {
        text = _("3 y 5 en Raya"),
        sorting_hint = "tools",
        callback = function()
            self:show()
        end,
    }
end

function EnRaya:_initBoard()
    if self.mode == "5_raya" then
        self.grid_size = 8
        self.win_len = 5
    else
        self.grid_size = 3
        self.win_len = 3
    end

    self.board = {}
    for r = 1, self.grid_size do
        self.board[r] = {}
        for c = 1, self.grid_size do
            self.board[r][c] = nil
        end
    end

    self.turn = "X"
    self.placed = { X = 0, O = 0 }
    self.selected = nil
    self.winner = nil
    self.is_draw = false
end

function EnRaya:_makeText(text, font_size)
    return TextWidget:new({
        text = text,
        face = Font:getFace("cfont", font_size or 19),
    })
end

function EnRaya:_makeButton(text, callback, width, height, bordersize)
    return Button:new({
        text = text,
        callback = function()
            callback()
        end,
        width = width,
        height = height,
        bordersize = bordersize or 2,
        radius = 0,
        margin = 1,
        padding = 1,
    })
end

function EnRaya:_closeWindow(is_exiting)
    if self.window then
        UIManager:close(self.window)
        self.window = nil
        if is_exiting then
            UIManager:setDirty("all", "ui")
        end
    end
end

function EnRaya:_setMode(new_mode)
    self.mode = new_mode
    self:_initBoard()
    self:show()
end

function EnRaya:_toggleOpponent()
    self.vs_ai = not self.vs_ai
    self:_initBoard()
    self:show()
end

function EnRaya:_resetScores()
    self.scores.X = 0
    self.scores.O = 0
    self:_initBoard()
    self:show()
end

-- Comprueba si 'player' tiene 'win_len' en línea en el tablero dado
function EnRaya:_checkWinOnBoard(b, player)
    local n = self.grid_size
    local k = self.win_len
    local dirs = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }

    for r = 1, n do
        for c = 1, n do
            if b[r][c] == player then
                for _, d in ipairs(dirs) do
                    local count = 1
                    for step = 1, k - 1 do
                        local nr = r + d[1] * step
                        local nc = c + d[2] * step
                        if nr >= 1 and nr <= n and nc >= 1 and nc <= n and b[nr][nc] == player then
                            count = count + 1
                        else
                            break
                        end
                    end
                    if count >= k then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function EnRaya:_isBoardFull()
    for r = 1, self.grid_size do
        for c = 1, self.grid_size do
            if not self.board[r][c] then
                return false
            end
        end
    end
    return true
end

function EnRaya:_finishTurn()
    if self:_checkWinOnBoard(self.board, self.turn) then
        self.winner = self.turn
        self.scores[self.turn] = self.scores[self.turn] + 1
        return
    end

    if self.mode ~= "3_move" and self:_isBoardFull() then
        self.is_draw = true
        return
    end

    self.turn = (self.turn == "X") and "O" or "X"

    if self.vs_ai and self.turn == "O" and not self.winner and not self.is_draw then
        self:_aiPlay()
    end
end

-- Lógica al tocar una casilla (r, c)
function EnRaya:_onCellTap(r, c)
    if self.winner or self.is_draw then
        return
    end
    if self.vs_ai and self.turn == "O" then
        return
    end

    local p = self.turn
    local cell_val = self.board[r][c]

    if self.mode == "3_move" and self.placed[p] >= 3 then
        -- Fase de mover una de las 3 fichas ya colocadas
        if cell_val == p then
            self.selected = { r = r, c = c }
            self:show()
            return
        elseif not cell_val and self.selected then
            self.board[self.selected.r][self.selected.c] = nil
            self.board[r][c] = p
            self.selected = nil
            self:_finishTurn()
            self:show()
            return
        end
    else
        -- Fase de colocar ficha en casilla vacía
        if not cell_val then
            self.board[r][c] = p
            self.placed[p] = self.placed[p] + 1
            self:_finishTurn()
            self:show()
        end
    end
end

-- IA para 3 en raya (Normal y Modo 3 piezas movibles)
function EnRaya:_aiPlay3x3()
    local b = self.board

    if self.mode == "3_move" and self.placed.O >= 3 then
        local my_pieces = {}
        local empties = {}
        for r = 1, 3 do
            for c = 1, 3 do
                if b[r][c] == "O" then
                    table.insert(my_pieces, { r = r, c = c })
                elseif not b[r][c] then
                    table.insert(empties, { r = r, c = c })
                end
            end
        end

        -- 1. Buscar movimiento ganador inmediato
        for _, from in ipairs(my_pieces) do
            for _, to in ipairs(empties) do
                b[from.r][from.c] = nil
                b[to.r][to.c] = "O"
                local wins = self:_checkWinOnBoard(b, "O")
                b[to.r][to.c] = nil
                b[from.r][from.c] = "O"
                if wins then
                    b[from.r][from.c] = nil
                    b[to.r][to.c] = "O"
                    return
                end
            end
        end

        -- 2. Buscar un movimiento donde X no pueda ganar en el turno siguiente
        local safe_moves = {}
        local all_moves = {}
        for _, from in ipairs(my_pieces) do
            for _, to in ipairs(empties) do
                table.insert(all_moves, { from = from, to = to })
                b[from.r][from.c] = nil
                b[to.r][to.c] = "O"

                local x_can_win = false
                local x_pieces = {}
                local next_empties = {}
                for r = 1, 3 do
                    for c = 1, 3 do
                        if b[r][c] == "X" then
                            table.insert(x_pieces, { r = r, c = c })
                        elseif not b[r][c] then
                            table.insert(next_empties, { r = r, c = c })
                        end
                    end
                end

                for _, xf in ipairs(x_pieces) do
                    for _, xt in ipairs(next_empties) do
                        b[xf.r][xf.c] = nil
                        b[xt.r][xt.c] = "X"
                        if self:_checkWinOnBoard(b, "X") then
                            x_can_win = true
                        end
                        b[xt.r][xt.c] = nil
                        b[xf.r][xf.c] = "X"
                    end
                end

                b[to.r][to.c] = nil
                b[from.r][from.c] = "O"

                if not x_can_win then
                    table.insert(safe_moves, { from = from, to = to })
                end
            end
        end

        local chosen = (#safe_moves > 0)
            and safe_moves[math.random(#safe_moves)]
            or all_moves[math.random(#all_moves)]

        if chosen then
            b[chosen.from.r][chosen.from.c] = nil
            b[chosen.to.r][chosen.to.c] = "O"
        end
        return
    end

    -- Fase de colocación (menos de 3 piezas o 3 en raya normal)
    local empties = {}
    for r = 1, 3 do
        for c = 1, 3 do
            if not b[r][c] then
                table.insert(empties, { r = r, c = c })
            end
        end
    end

    -- 1. Ganar si es posible
    for _, pos in ipairs(empties) do
        b[pos.r][pos.c] = "O"
        if self:_checkWinOnBoard(b, "O") then
            self.placed.O = self.placed.O + 1
            return
        end
        b[pos.r][pos.c] = nil
    end

    -- 2. Bloquear victoria de X (por colocación o por movimiento)
    for _, pos in ipairs(empties) do
        local x_wins_here = false
        if self.mode == "3_move" and self.placed.X >= 3 then
            for r = 1, 3 do
                for c = 1, 3 do
                    if b[r][c] == "X" then
                        b[r][c] = nil
                        b[pos.r][pos.c] = "X"
                        if self:_checkWinOnBoard(b, "X") then
                            x_wins_here = true
                        end
                        b[pos.r][pos.c] = nil
                        b[r][c] = "X"
                    end
                end
            end
        else
            b[pos.r][pos.c] = "X"
            if self:_checkWinOnBoard(b, "X") then
                x_wins_here = true
            end
            b[pos.r][pos.c] = nil
        end

        if x_wins_here then
            b[pos.r][pos.c] = "O"
            self.placed.O = self.placed.O + 1
            return
        end
    end

    -- 3. Tomar centro o casilla libre aleatoria
    if not b[2][2] then
        b[2][2] = "O"
        self.placed.O = self.placed.O + 1
        return
    end

    if #empties > 0 then
        local pick = empties[math.random(#empties)]
        b[pick.r][pick.c] = "O"
        self.placed.O = self.placed.O + 1
    end
end

-- Evaluador de línea para la IA del 5 en raya
function EnRaya:_scorePoint5(r, c, player)
    local n = self.grid_size
    local b = self.board
    local dirs = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }
    local total = 0

    for _, d in ipairs(dirs) do
        local count = 1
        local open_ends = 0

        for step = 1, 4 do
            local nr, nc = r + d[1] * step, c + d[2] * step
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                if b[nr][nc] == player then
                    count = count + 1
                elseif not b[nr][nc] then
                    open_ends = open_ends + 1
                    break
                else
                    break
                end
            else
                break
            end
        end

        for step = 1, 4 do
            local nr, nc = r - d[1] * step, c - d[2] * step
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                if b[nr][nc] == player then
                    count = count + 1
                elseif not b[nr][nc] then
                    open_ends = open_ends + 1
                    break
                else
                    break
                end
            else
                break
            end
        end

        if count >= 5 then
            total = total + 100000
        elseif count == 4 and open_ends >= 1 then
            total = total + (open_ends == 2 and 12000 or 4000)
        elseif count == 3 and open_ends >= 1 then
            total = total + (open_ends == 2 and 1200 or 250)
        elseif count == 2 and open_ends == 2 then
            total = total + 80
        end
    end

    return total
end

function EnRaya:_aiPlay5x5()
    local n = self.grid_size
    local best_score = -1
    local best_moves = {}

    for r = 1, n do
        for c = 1, n do
            if not self.board[r][c] then
                local attack = self:_scorePoint5(r, c, "O")
                local defense = self:_scorePoint5(r, c, "X")
                local center_bonus = 8 - (math.abs(r - 4.5) + math.abs(c - 4.5))
                local score = attack * 1.15 + defense + center_bonus

                if score > best_score then
                    best_score = score
                    best_moves = { { r = r, c = c } }
                elseif score == best_score then
                    table.insert(best_moves, { r = r, c = c })
                end
            end
        end
    end

    if #best_moves > 0 then
        local pick = best_moves[math.random(#best_moves)]
        self.board[pick.r][pick.c] = "O"
        self.placed.O = self.placed.O + 1
    end
end

function EnRaya:_aiPlay()
    if self.mode == "5_raya" then
        self:_aiPlay5x5()
    else
        self:_aiPlay3x3()
    end

    if self:_checkWinOnBoard(self.board, "O") then
        self.winner = "O"
        self.scores.O = self.scores.O + 1
    elseif self.mode ~= "3_move" and self:_isBoardFull() then
        self.is_draw = true
    else
        self.turn = "X"
    end
end

function EnRaya:_getStatusText()
    if self.winner then
        if self.vs_ai then
            return self.winner == "X"
                and _("¡Has ganado la partida! (X)")
                or _("¡Gana el Ordenador! (O)")
        end
        return string.format(_("¡Victoria para el jugador %s!"), self.winner)
    elseif self.is_draw then
        return _("¡Empate! Tablero completo.")
    end

    local who = (self.vs_ai and self.turn == "O")
        and _("Ordenador (O)")
        or string.format(_("Jugador %s"), self.turn)

    if self.mode == "3_move" then
        local count = self.placed[self.turn]
        if count < 3 then
            return string.format(_("Turno: %s — Coloca ficha (%d/3)"), who, count + 1)
        elseif self.selected then
            return string.format(_("Turno: %s — Toca casilla vacía destino"), who)
        else
            return string.format(_("Turno: %s — Toca una ficha %s para moverla"), who, self.turn)
        end
    end

    return string.format(_("Turno de %s"), who)
end

function EnRaya:show()
    self:_closeWindow(false)

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local panel_w = screen_w - 24

    local btn_w_3 = math.floor((panel_w - 18) / 3)
    local btn_w_4 = math.floor((panel_w - 24) / 4)
    local ctrl_h = math.max(40, math.min(54, math.floor(screen_h * 0.055)))

    -- Barra de selección de modo de juego
    local mode_row = HorizontalGroup:new({
        align = "center",
        self:_makeButton(
            self.mode == "3_normal" and _("• 3 Normal •") or _("3 Normal"),
            function() self:_setMode("3_normal") end,
            btn_w_3, ctrl_h, self.mode == "3_normal" and 4 or 1
        ),
        self:_makeButton(
            self.mode == "3_move" and _("• 3 Mueve •") or _("3 Mueve"),
            function() self:_setMode("3_move") end,
            btn_w_3, ctrl_h, self.mode == "3_move" and 4 or 1
        ),
        self:_makeButton(
            self.mode == "5_raya" and _("• 5 en Raya •") or _("5 en Raya"),
            function() self:_setMode("5_raya") end,
            btn_w_3, ctrl_h, self.mode == "5_raya" and 4 or 1
        ),
    })

    -- Cálculo del tamaño del tablero para que encaje siempre en pantalla
    local board_max_px = math.min(panel_w - 12, screen_h - (ctrl_h * 2) - 135)
    local cell_px = math.floor((board_max_px - (self.grid_size * 4)) / self.grid_size)

    local board_rows = VerticalGroup:new({ align = "center" })
    for r = 1, self.grid_size do
        local row_group = HorizontalGroup:new({ align = "center" })
        for c = 1, self.grid_size do
            local val = self.board[r][c] or ""
            local is_sel = self.selected and self.selected.r == r and self.selected.c == c
            local label = is_sel and ("[" .. val .. "]") or val
            local border = is_sel and 5 or 2

            table.insert(row_group, self:_makeButton(
                label,
                function() self:_onCellTap(r, c) end,
                cell_px,
                cell_px,
                border
            ))
        end
        table.insert(board_rows, row_group)
    end

    local board_frame = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 2,
        padding = 4,
        margin = 4,
        board_rows,
    })

    -- Barra inferior con cambio IA/Humano, Reiniciar, Puntos a 0 y Salir
    local rival_label = self.vs_ai and _("Rival: IA") or _("Rival: 2 Jug.")
    local bottom_row = HorizontalGroup:new({
        align = "center",
        self:_makeButton(rival_label, function()
            self:_toggleOpponent()
        end, btn_w_4, ctrl_h, 2),
        self:_makeButton(_("Reiniciar"), function()
            self:_initBoard()
            self:show()
        end, btn_w_4, ctrl_h, 2),
        self:_makeButton(_("Puntos 0"), function()
            self:_resetScores()
        end, btn_w_4, ctrl_h, 2),
        self:_makeButton(_("Salir"), function()
            self:_closeWindow(true)
        end, btn_w_4, ctrl_h, 2),
    })

    local rival_title = self.vs_ai and _("Ordenador (O)") or _("Jugador O")
    local score_banner = self:_makeText(
        string.format(_("MARCADOR   |   Jugador X: %d   —   %s: %d"), self.scores.X, rival_title, self.scores.O),
        18
    )

    local main_layout = VerticalGroup:new({
        align = "center",
        score_banner,
        self:_makeText(self:_getStatusText(), 19),
        mode_row,
        board_frame,
        bottom_row,
    })

    self.window = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        CenterContainer:new({
            dimen = Screen:getSize(),
            main_layout,
        }),
    })

    UIManager:show(self.window)
    UIManager:setDirty(self.window, "ui")
    UIManager:setDirty("all", "ui")
end

return EnRaya
