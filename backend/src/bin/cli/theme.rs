//! MicroCode CLI — Theme and color definitions

use ratatui::style::Color;

pub struct Theme {
    pub bg: Color,
    pub fg: Color,
    pub accent: Color,
    pub success: Color,
    pub error: Color,
    pub warning: Color,
    pub muted: Color,
    pub border: Color,
    pub border_focused: Color,
}

impl Default for Theme {
    fn default() -> Self {
        Self {
            bg: Color::Rgb(18, 18, 24),
            fg: Color::Rgb(220, 220, 230),
            accent: Color::Rgb(97, 175, 239),
            success: Color::Rgb(152, 195, 121),
            error: Color::Rgb(224, 108, 117),
            warning: Color::Rgb(229, 192, 123),
            muted: Color::Rgb(92, 99, 112),
            border: Color::Rgb(50, 50, 65),
            border_focused: Color::Rgb(97, 175, 239),
        }
    }
}
