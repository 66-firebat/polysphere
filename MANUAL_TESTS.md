# PolySphere — Manual Test Script

This file contains all **[MANUAL]** tests for Phase 3. You perform these on your own time and report back the answers. I'll evaluate pass/fail from your report.

---

## How to Run

### Start (one terminal)

```bash
cd /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp
./manual_start.sh
```

### Open overlay (second terminal, or Hyprland keybind)

Use `cycle` — first call opens, subsequent calls cycle forward.
```bash
quickshell ipc -p /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/shell.qml call polysphere cycle
```

### Keybind for Hyprland

Hyprland intercepts Alt+Tab before QML can see the key event, so cycling must go through IPC. Use `cycle`:

Add to `~/.config/hypr/keymaps.lua`:
```lua
hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.exec_cmd(
        "quickshell ipc -p /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp/shell.qml call polysphere cycle"
    ))
end)
```

### Clean up when done

```bash
pkill -f quickshell; pkill -f guile.*daemon; rm -f /run/user/1000/polysphere.sock
```

---

## Test A — Overlay Opens on Alt+Tab

**Objective:** Verify the overlay appears with the 3D sphere when Alt+Tab is pressed.

**Sequence:**
1. Press and hold **Alt**
2. While holding Alt, press **Tab** once
3. Keep holding Alt — observe the screen
4. Release **Alt**

**Report:**
```
Q1: Did the overlay appear with the 3D sphere?
Q2: How many app cards do you see on the sphere?
Q3: Is one app highlighted with a satellite detail view (looks like a spacecraft panel with solar panels, antenna, app icon/name)?
Q4: If yes, what app name is shown in that satellite view?
Q5: After you released Alt, did the overlay close?
```

---

## Test B — Tab Cycles Through ALL Apps

**Objective:** Verify Tab cycles through every app visible on the sphere, not just a subset.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once (overlay appears)
3. Press **Tab** again — observe which app is highlighted
4. Press **Tab** 3-4 more times
5. Keep pressing Tab until the selection wraps back to the first app
6. Release **Alt**

**Report:**
```
Q1: Did the selection move to a DIFFERENT app each time you pressed Tab?
Q2: Did the sphere rotate to center the selected app each time?
Q3: Did the selection wrap back to the first app after cycling through all of them?
Q4: How many unique apps did you see highlighted before it wrapped around? (should match the total visible on sphere)
Q5: Did the satellite detail view update its icon and name each time?
```

---

## Test C — Shift+Tab Cycles Backward

**Objective:** Verify Shift+Tab goes in the opposite direction.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** twice to advance forward
3. Press **Shift+Tab** once — observe
4. Press **Shift+Tab** again — observe
5. Release **Alt**

**Report:**
```
Q1: After pressing Shift+Tab, did the selection move BACK one step (to the app that was highlighted BEFORE your last Tab press)?
Q2: Did it continue moving backward with each Shift+Tab press?
Q3: Did it wrap around at the beginning?
```

---

## Test D — Release Alt Activates Running App

**Objective:** Verify releasing Alt focuses the selected running app.

**Prerequisite:** Have a running app visible on the sphere (e.g., Firefox, Kitty).

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** until a **running** app is highlighted (the satellite shows its name)
3. Release **Alt**

**Report:**
```
Q1: Did the overlay close?
Q2: Did the selected app's window come into focus (you can see/type in it)?
Q3: Did the exit animation play (roughly 400ms fade out)?
```

---

## Test E — Release Alt Activates Non-Running App

**Objective:** Verify releasing Alt launches a non-running whitelisted app.

**Prerequisite:** Have a non-running whitelisted app visible (e.g., spotify, discord, obsidian — whichever you have in your whitelist).

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** until a **non-running** app is highlighted (the user's report mentioned "spotify" or "discord")
3. Release **Alt**

**Report:**
```
Q1: Did the overlay close?
Q2: Did the app launch (new window appeared)?
Q3: Now press Alt+Tab again — is the newly launched app visible on the sphere?
```

---

## Test F — Escape Closes Without Focus Change

**Objective:** Verify Escape closes the overlay without switching focus.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once (overlay appears)
3. Press **Escape** (you can release Alt or keep holding — either way)
4. Observe

**Report:**
```
Q1: Did the overlay close?
Q2: Did the exit animation play (fade out)?
Q3: Did the window that was focused BEFORE Alt+Tab remain focused (no window switching)?
```

---

## Test G — Search Filters the Sphere

**Objective:** Verify typing filters the sphere using Fuse.js fuzzy search.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once (overlay appears)
3. Type **"fi"** (don't press Enter — just type the letters)
4. Wait ~1 second (the 500ms debounce timer fires, then search executes)
5. Observe the sphere

**Report:**
```
Q1: Did the sphere change to show only apps matching "fi"?
Q2: How many apps are shown after filtering?
Q3: Is the first result auto-selected (zoomed in with satellite view)?
Q4: What is the name of the first result?
Q5: Did the satellite view update to show that app's icon and name?
```

---

## Test H — Escape Clears Search, Restores Full Sphere

**Objective:** Verify Escape clears the search and restores the full sphere without closing.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once
3. Type **"fi"**, wait ~1 second (sphere filters)
4. Press **Escape** once
5. Observe

**Report:**
```
Q1: Did the search bar text clear?
Q2: Did the full sphere restore with ALL apps?
Q3: Was the previous selection (before you typed "fi") restored?
Q4: Did the overlay stay open (did NOT close)?
```

---

## Test I — Empty Escape Closes Overlay

**Objective:** Verify pressing Escape with an empty search bar closes the overlay.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once
3. Immediately press **Escape** (don't type anything)

**Report:**
```
Q1: Did the overlay close immediately?
Q2: Did the previously focused window stay focused?
```

---

## Test J — Tab Cycles During Search (Filtered Cycling)

**Objective:** Verify Tab only cycles through filtered search results, not the full list.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once
3. Type **"fi"**, wait ~1 second (sphere filters)
4. Press **Tab** once — observe which app is highlighted
5. Press **Tab** again — observe
6. Press **Tab** until selection wraps around

**Report:**
```
Q1: After pressing Tab, did the highlight move to the NEXT app WITHIN the filtered "fi" results?
Q2: Did the selection WRAP around within the filtered results?
Q3: Did it ever jump to an app whose name does NOT match "fi"?
Q4: How many unique apps did you cycle through? (should match the filtered count from Test G Q2)
```

---

## Test K — Release Alt During Search Activates Filtered Selection

**Objective:** Verify releasing Alt while search is active activates the correct filtered app.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once
3. Type **"fi"**, wait ~1 second
4. Press **Tab** once or twice to pick a specific filtered app
5. Release **Alt**

**Report:**
```
Q1: Did the overlay close?
Q2: Did it activate/launch the app that was highlighted in the filtered results?
Q3: Was it the correct app (matching "fi" pattern)?
```

---

## Test L — Full Cycle: Open, Cycle, Activate, Reopen

**Objective:** Verify the overlay works cleanly through multiple complete cycles without degradation.

**Sequence:**
1. Press and hold **Alt**, press **Tab** once → overlay opens
2. Press **Tab** 2-3 times → cycle through apps
3. Release **Alt** → activates, overlay closes
4. Wait 2 seconds
5. Press and hold **Alt**, press **Tab** once → overlay opens again
6. Observe

**Report:**
```
Q1: Did the overlay open again cleanly (no glitches)?
Q2: Does the app you just activated appear FIRST on the sphere?
Q3: Are all apps still visible and correctly positioned?
Q4: Any visual glitches, freezes, or crashes?
```

---

## Test M — Mouse Drag Rotates Sphere

**Objective:** Verify mouse drag rotates the sphere.

**Sequence:**
1. Press and hold **Alt**, press **Tab** once (overlay opens)
2. Click and drag on the sphere area
3. Observe rotation
4. Release mouse

**Report:**
```
Q1: Did the sphere rotate smoothly following your mouse drag?
Q2: Did the auto-rotation pause while you were dragging?
Q3: Did auto-rotation resume after releasing the mouse?
```

---

## Test N — Escape + Alt Release During Search (Edge Case Combo)

**Objective:** Verify the combined flow of searching, clearing, searching again, and activating.

**Sequence:**
1. Press and hold **Alt**
2. Press **Tab** once
3. Type **"fi"**, wait ~1 second → filtered results show
4. Press **Escape** → search clears, full sphere restored
5. Type **"th"**, wait ~1 second → filtered results for "th" show
6. Release **Alt** (WITHOUT clearing search this time)

**Report:**
```
Q1: After step 4 (Escape), did the full sphere restore correctly?
Q2: After step 5, did the sphere correctly filter to show "th" results?
Q3: After step 6 (release Alt), did it activate the currently selected app?
Q4: Any crashes or glitches during the whole sequence?
```

---

## How to Report

Copy the section below, fill in your answers, and paste into your reply.

<details>
<summary>Click to expand report template</summary>

```
Test A:
Q1: (yes/no)
Q2: (number)
Q3: (yes/no)
Q4: (app name or "N/A")
Q5: (yes/no)

Test B:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)
Q4: (number)
Q5: (yes/no)

Test C:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)

Test D:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)

Test E:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)

Test F:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)

Test G:
Q1: (yes/no)
Q2: (number)
Q3: (yes/no)
Q4: (app name)
Q5: (yes/no)

Test H:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)
Q4: (yes/no)

Test I:
Q1: (yes/no)
Q2: (yes/no)

Test J:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)
Q4: (number)

Test K:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)

Test L:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)
Q4: (describe if any)

Test M:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)

Test N:
Q1: (yes/no)
Q2: (yes/no)
Q3: (yes/no)
Q4: (describe if any)
```

</details>
