package abbott

import rl "vendor:raylib"

Theme :: struct {
    background, panel, raised, border: rl.Color,
    text, muted, accent:               rl.Color,
}

theme: Theme
ui_font: rl.Font

apply_theme :: proc() {
    if lib.light {
        theme = Theme {
            background = rl.GetColor(0xe9e5d2ff),
            panel      = rl.GetColor(0xded9c7ff),
            raised     = rl.GetColor(0xd2cdbdff),
            border     = rl.GetColor(0xb9b3aaff),
            text       = rl.GetColor(0x43436cff),
            muted      = rl.GetColor(0x716e61ff),
            accent     = rl.GetColor(0x4d699bff),
        }
    } else {
        theme = Theme {
            background = rl.GetColor(0x181616ff),
            panel      = rl.GetColor(0x282727ff),
            raised     = rl.GetColor(0x393836ff),
            border     = rl.GetColor(0x625e5aff),
            text       = rl.GetColor(0xc5c9c5ff),
            muted      = rl.GetColor(0x90988fff),
            accent     = rl.GetColor(0x8ba4b0ff),
        }
    }
    colors := [12]rl.Color {
        theme.border,
        theme.raised,
        theme.text,
        theme.accent,
        rl.ColorBrightness(theme.raised, 0.08),
        theme.text,
        theme.accent,
        theme.accent,
        theme.background,
        theme.border,
        theme.panel,
        theme.muted,
    }
    for color, i in colors {rl.GuiSetStyle(.DEFAULT, i32(i), transmute(i32)rl.ColorToInt(color))}
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiControlProperty.BORDER_WIDTH), 1)
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), 16)
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SPACING), 0)
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_LINE_SPACING), 26)
    rl.GuiSetStyle(
        .DEFAULT,
        i32(rl.GuiDefaultProperty.BACKGROUND_COLOR),
        transmute(i32)rl.ColorToInt(theme.background),
    )
    rl.GuiSetStyle(
        .DEFAULT,
        i32(rl.GuiDefaultProperty.LINE_COLOR),
        transmute(i32)rl.ColorToInt(theme.border),
    )
    rl.GuiSetStyle(
        .TEXTBOX,
        i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
        transmute(i32)rl.ColorToInt(theme.background),
    )
}

bevel :: proc(bounds: rl.Rectangle) {
    pressed :=
        rl.GuiGetState() != i32(rl.GuiState.STATE_DISABLED) &&
        rl.IsMouseButtonDown(.LEFT) &&
        rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    top := rl.ColorBrightness(theme.raised, 0.25)
    bottom := rl.ColorBrightness(theme.raised, -0.3)
    if pressed {top, bottom = bottom, top}
    x, y := i32(bounds.x), i32(bounds.y)
    right, last := i32(bounds.x + bounds.width) - 2, i32(bounds.y + bounds.height) - 2
    rl.DrawLine(x + 1, y + 1, right, y + 1, top)
    rl.DrawLine(x + 1, y + 1, x + 1, last, top)
    rl.DrawLine(x + 1, last, right, last, bottom)
    rl.DrawLine(right, y + 1, right, last, bottom)
}

panel :: proc(bounds: rl.Rectangle, title: string) {
    rl.DrawRectangleRec(bounds, theme.panel)
    rl.DrawRectangleLinesEx(bounds, 2, theme.border)
    rl.DrawRectangleRec({bounds.x + 3, bounds.y + 3, bounds.width - 6, 26}, theme.accent)
    rl.DrawTextEx(ui_font, cstr(title), {bounds.x + 10, bounds.y + 7}, 16, 0, theme.background)
}

