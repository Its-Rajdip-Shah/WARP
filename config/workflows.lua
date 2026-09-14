-- Finder and ChatGPT are global: WARP never manages them.
-- Safari settings are preserved; VS Code membership is learned from focus.
-- Add tmux/Figma/Docker sections when ready; see README.md.
return {
  elec3609 = {
    label = "ELEC3609",
    key = "1",

    safari = {
      tabGroup = "ELEC3609",
    },

    vscode = true,
    primary = "none",
  },

  soft2412 = {
    label = "SOFT2412",
    key = "2",

    safari = {
      tabGroup = "SOFT2412",
    },

    vscode = true,
    primary = "none",
  },
}