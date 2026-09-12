-- Example roots: edit these to match your folders before switching.
-- VS Code discovery requires the title setting documented in README.md.


-- return {
--   elec3609 = {
--     label = 'ELEC3609', key = '1',
--     finder = {leftRoot = '~/Uni/ELEC3609'},
--     safari = {tabGroup = 'ELEC3609'},
--     terminal = {tmuxSession = 'elec3609'},
--     vscode = {allowedRoots = {'~/Uni/ELEC3609'}},
--     apps = {{id = 'figma', preferredFullscreen = true}},
--     primary = 'figma', coldAfterMinutes = 30,
--   },
--   soft2412 = {
--     label = 'SOFT2412', key = '2',
--     finder = {leftRoot = '~/Uni/SOFT2412'},
--     safari = {tabGroup = 'SOFT2412'},
--     terminal = {tmuxSession = 'soft2412'},
--     vscode = {allowedRoots = {'~/Uni/SOFT2412'}},
--     apps = {{id = 'docker', warm = 'preserve', cold = 'resource_aware'}},
--     primary = 'vscode', coldAfterMinutes = 30,
--   },
-- }


return {
  elec3609 = {
    label = "ELEC3609",
    key = "1",

    finder = {
      leftRoot = "~/UNI/Y3S1 - 2026 sem 2/ELEC3609",
    },

    primary = "finder",
  },

  soft2412 = {
    label = "SOFT2412",
    key = "2",

    finder = {
      leftRoot = "~/UNI/Y3S1 - 2026 sem 2/SOFT2412",
    },

    primary = "finder",
  },
}
