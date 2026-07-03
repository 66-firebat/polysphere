# PolySphere — Manual Test Script

This file contains all **[MANUAL]** tests for Phase 3. You perform these on your own time and report back the answers. I'll evaluate pass/fail from your report.

---

## How to Run

### Prerequisites

- You **must** be in the `input` user group for kbd-capture to work:
  ```bash
  groups $USER  # verify 'input' appears
  ```
- No Hyprland keybinds needed — kbd-capture intercepts keys directly from the kernel

### Start (one terminal)

```bash
cd /run/media/fireshark/FORGE_CELL/data/github_repositories/hypr-comp
./manual_start.sh
```

### Open overlay

The overlay opens when you press **Alt+Tab** (handled by kbd-capture). No IPC command needed.

### Close everything when done

```bash
pkill -f quickshell; pkill -f guile.*daemon; rm -f /run/user/1000/polysphere.sock
```

---

## kbd-capture Validation Tests

These tests verify that kbd-capture is working correctly — intercepting keys before Hyprland, and forwarding them to QML.

---

### Test K0 — kbd-capture Process Starts

**Objective:** Verify kbd-capture starts when the overlay opens and stops when it closes.

**Sequence:**
1. `./manual_start.sh`
2. Press and hold **Alt**, press **Tab** once → overlay opens
3. Release **Alt** (or press Escape to close)

**Report:**
```
Q1: Did you see any kbd-related errors in the console output?
Q2: Did the overlay respond to Alt+Tab (proving kbd-capture is running)?
```

---

### Test K1 — Alt+Letter Reaches Search (Not Hyprland)

**Objective:** Verify keys typed while holding Alt go to the search bar instead of triggering Hyprland binds (e.g., Alt+F should NOT fullscreen).

**Known Hyprland binds that should NOT fire:**
- `Alt+F` would normally fullscreen → should type "f" in search instead
- `Alt+J` would normally focus down → should type "j" in search instead
- `Alt+H` would normally focus left → should type "h" in search instead

**Sequence:**
1. Hold **Alt**, press **Tab** → overlay opens
2. While still holding Alt, type **"fi"**
3. Wait ~1 second (debounce timer)
4. Observe the sphere

**Report:**
```
Q1: Did typing "fi" filter the sphere to show only matching apps?
Q2: Did any Hyprland keybind fire during step 2 (e.g., window fullscreened, focus moved)?
Q3: How many apps are shown after filtering?
Q4: Did the search bar show the text "fi"?
```

---

### Test K2 — Alt+All Letters Work for Search

**Objective:** Verify various Alt+letter combinations reach search without interference.

**Sequence:**
1. Hold **Alt**, press **Tab** → overlay opens
2. While still holding Alt, type **"firefox"** (all 7 letters)
3. Wait ~1 second
4. Observe

**Report:**
```
Q1: Did the text "firefox" appear in the search bar?
Q2: Did the sphere filter to show Firefox?
Q3: Did any Hyprland bind fire during typing (Alt+F, Alt+I, Alt+R, etc.)?
```

---

### Test K3 — Alt Key Tracking (Press + Release)

**Objective:** Verify kbd-capture correctly tracks Alt state for activation.

**Sequence:**
1. Hold **Alt**, press **Tab** → overlay opens
2. While still holding Alt, press **Tab** 2-3 times → cycle through apps
3. Release **Alt**
4. Observe

**Report:**
```
Q1: Did each Tab press cycle to the next app while Alt was held?
Q2: Did releasing Alt activate the selected app?
Q3: Did the overlay close after activation?
```

---

### Test K4 — Search + Backspace

**Objective:** Verify Backspace works for correcting search queries while holding Alt.

**Sequence:**
1. Hold **Alt**, press **Tab** → overlay opens
2. Type **"fir"** → sphere should filter to "fir" matches
3. Press **Backspace** once → text becomes "fi"
4. Wait ~1 second
5. Observe

**Report:**
```
Q1: Did "fir" filter the sphere?
Q2: After Backspace, did the search text change to "fi"?
Q3: Did the sphere re-filter to show "fi" matches?
```

---

### Test K5 — Escape While Holding Alt

**Objective:** Verify Escape closes the overlay even when Alt is still held.

**Sequence:**
1. Hold **Alt**, press **Tab** → overlay opens
2. While still holding Alt, press **Escape**
3. Observe

**Report:**
```
Q1: Did the overlay close?
Q2: Did the window that was focused before Alt+Tab remain focused?
```

---

### Test K6 — kbd-capture Stops When Overlay Closes

**Objective:** Verify the keyboard returns to normal after closing the overlay.

**Sequence:**
1. Hold **Alt**, press **Tab** → overlay opens
2. Press **Escape** → overlay closes
3. Try typing normally in another app (e.g., press **Alt+F**)

**Report:**
```
Q1: After closing the overlay, does typing work normally in other apps?
Q2: Does Alt+F trigger Hyprland's fullscreen bind (as expected when overlay is closed)?
```

---

## Original Alt+Tab Flow Tests

These are the original tests from the initial design. They now work through kbd-capture instead of IPC.

---

### Test A — Overlay Opens on Alt+Tab

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

**Note:** Release Alt BEFORE typing. Hyprland intercepts Alt+letter combos.

The search bar is auto-focused when the overlay opens, so typing works without holding Alt.

**Sequence:**
1. Press and hold **Alt**, press **Tab** once (overlay appears)
2. **Release Alt**
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
1. Press and hold **Alt**, press **Tab** once
2. **Release Alt**
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
1. Press and hold **Alt**, press **Tab** once
2. **Release Alt**
3. Type **"fi"**, wait ~1 second (sphere filters)
4. Press and hold **Alt**, press **Tab** once — observe which app is highlighted
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
1. Press and hold **Alt**, press **Tab** once
2. **Release Alt**
3. Type **"fi"**, wait ~1 second
4. Press and hold **Alt**, press **Tab** once or twice to pick a specific filtered app
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
1. Press and hold **Alt**, press **Tab** once
2. **Release Alt**
3. Type **"fi"**, wait ~1 second → filtered results show
4. Press **Escape** → search clears, full sphere restored
5. Type **"th"**, wait ~1 second → filtered results for "th" show
6. Press and hold **Alt**, then release **Alt** to activate the selected app

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
