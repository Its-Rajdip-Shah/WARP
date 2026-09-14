-- Named workflows derive Safari from label, enable Code resources, and default primary to none.
-- GENERAL uses the home directory as a neutral Finder location; GENERAL begins Code curation on reload.
return {
  general = {label = "GENERAL", key = "0"},
  elec3609 = {
    label = "ELEC3609", key = "1",
    -- TODO: set finder to your actual absolute ELEC3609 directory; no path is assumed.
  },
  soft2412 = {
    label = "SOFT2412", key = "2",
    finder = "/Users/rajdipshah/UNI/Y3S1 - 2026 sem 2/SOFT2412",
  },
}
