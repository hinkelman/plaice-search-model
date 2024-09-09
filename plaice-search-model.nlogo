extensions [
  csv
  profiler
]

globals [
  regeneration-time                                                    ; time until prey have regenerated; not really time, based on number of moves
  giving-up-time                                                       ; time until predator switches back to extensive search; not really time, based on number of moves
  avg-local-density                                                    ; Average number of prey in response radius at start of simulation

  detection-radius                                                     ; Distance from which a predator can detect (and capture) prey item
  step-length                                                          ; Size of step taken when approaching a boundary

  move-lengths
  ml-extensive                                                         ; list of cumulative frequency for move lengths from extensive mode
  ml-intensive                                                         ; list of cumulative frequency for move lengths from intensive mode

  turn-angles
  ta-extensive                                                         ; list of cumulative frequency for turn angles from extensive mode
  ta-intensive                                                         ; list of cumulative frequency for turn angles from intensive mode
  ]

breed [ prey a-prey ]
breed [ predators predator ]

; predators can detect/capture prey within radius of one; assume 100% capture probability
predators-own [
  search-mode
  last-prey-capture                                                    ; number of moves since last prey capture
  prey-captured
]

prey-own [
  selected?                                                            ; prey randomly selected for simulation
  present?                                                             ; set to false when prey consumed
  regeneration-counter                                                 ; number of predator moves since a-prey was eaten
  ]

;; SETUP ------------------------------------------------------------------------------------

to setup
  clear-all
  if (use-scenario?)[ set-scenarios ]
  set-globals
  ask patches [ set pcolor 99 ]
  set-boundary-patches
  create-prey-grid
  distribute-prey
  add-predator
  ask predators[ update-search-mode ]                                  ; sets correct search mode after initial random placement for local-density search tactic
  reset-ticks
end

to set-scenarios
  let data csv:from-file "InputData/Scenarios.csv"
  let header item 0 data
  let sc item scenario data
  set prey-patch-size item (position "PreyPatchSize" header) sc
  set prey-spacing item (position "PreySpacing" header) sc
  set prey-number item (position "PreyNumber" header) sc
end

to set-globals
  set detection-radius 1
  set regeneration-time 1000
  set giving-up-time 10
  set avg-local-density report-avg-local-density
  set step-length 0.1                                                  ; not resolving this to the same scale as the paper (10e-5) b/c slows down model; should be one of first things to check if results don't match paper
  set-move-lengths
  set-turn-angles
end

;to-report report-avg-local-density
;  report ((prey-number * (pi * response-radius ^ 2)) / ((world-width - 2) * (world-height - 2)))
;end

to-report report-avg-local-density
  ;; counting actual patches (i.e., discretized); more similar to way local area is determined in update-search-mode
  ;; relatively small difference from continuous version
  let local-patches nobody
  ask patch (floor world-width / 2) (floor world-height / 2) [  ;; just picking a patch in middle to make sure response-radius is not truncated
    set local-patches patches in-radius response-radius
  ]
  let local-area count local-patches
  let world-area (world-width - 2) * (world-height - 2)
  report prey-number * (local-area / world-area)
end

to set-move-lengths
  ;; reformat data into 3 separate lists (rather than nested lists) for use in calc-piecewise
  let data butfirst csv:from-file "InputData/MoveLength.csv"           ; butfirst drops header row
  let ml []
  let ex []
  let in []
  foreach data [ x ->
    set ml lput (item 0 x) ml
    set ex lput (item 1 x) ex
    set in lput (item 2 x) in
  ]
  set move-lengths ml
  set ml-extensive ex
  set ml-intensive in
end

to set-turn-angles
  ;; reformat data into 3 separate lists (rather than nested lists) for use in calc-piecewise
  let data butfirst csv:from-file "InputData/TurnAngle.csv"           ; butfirst drops header row
  let ta []
  let ex []
  let in []
  foreach data [ x ->
    set ta lput (item 0 x) ta
    set ex lput (item 1 x) ex
    set in lput (item 2 x) in
  ]
  set turn-angles ta
  set ta-extensive ex
  set ta-intensive in
end

to set-boundary-patches
  ask patches with [pxcor = min-pxcor or pxcor = max-pxcor or pycor = min-pycor or pycor = max-pycor][ set pcolor black ]
end

to create-prey-grid
  set-default-shape prey "dot"
  let half-ps prey-patch-size / 2
  let x-center max-pxcor / 2
  let y-center max-pycor / 2
  let grid-pos-x n-values prey-patch-size [ i -> i + (x-center - half-ps + 0.5)]
  let grid-pos-y n-values prey-patch-size [ i -> i + (y-center - half-ps + 0.5)]
  foreach grid-pos-x [ x ->
    foreach grid-pos-y[ y ->
      create-prey 1 [
        setxy x y
        set color 98
        set size 0.5
        set selected? false
        set present? false
        set regeneration-counter 0
      ]
    ]
  ]
end

to distribute-prey
  ifelse (prey-spacing = 0)[
    ;; simple procedure when no constraints on spacing
    ask n-of prey-number prey [
      set color 136
      set size 1
      set selected? true
      set present? true
    ]
  ][
    let fail-counter 0
    while [count prey with [present?] < prey-number][
      let next-prey one-of prey with [not present?]
      let neighbor-prey nobody
      ask next-prey [
        set neighbor-prey prey with [distance myself <= prey-spacing and present?]   ; using distance myself rather than in-radius based on this paper: http://jasss.soc.surrey.ac.uk/20/1/3.html
      ]
      ifelse (any? neighbor-prey)[
        ; next-prey is not selected b/c violates spacing rule
        set fail-counter fail-counter + 1
        if (fail-counter > 1000)[ error "Too many prey for selected patch size and prey spacing"]
      ][
        ask next-prey[
          set color 136
          set size 1
          set selected? true
          set present? true
        ]
      ]
    ]
  ]
  ask prey with [not selected?][ die ]
end

to add-predator
  set-default-shape predators "dot"
  create-predators 1 [
    setxy (random-float (max-pxcor - 1) + 0.5) (random-float (max-pycor - 1) + 0.5)     ; generate random-float between 0.5 and 70.5 (for default world dimensions)
    set color brown
    set size 2
    set search-mode "extensive"
    set last-prey-capture 0
    set prey-captured 0
    if (pen-down?)[ pen-down ]                                                      ; If true, the forager's path will be traced; visualization purposes only
  ]
end


to update-search-mode
  if (search-tactic = "extensive-intensive" and last-prey-capture >= giving-up-time)[
    set search-mode "extensive"
  ]
  if (search-tactic = "local-density")[
    ;    let local-density count prey with [distance myself <= response-radius and present?]        ; based on predator's actual location rather than at the center of patch
    let local-prey nobody
    ask patch-here [ set local-prey prey with [distance myself <= response-radius and present?] ]  ; using distance myself rather than in-radius based on this paper: http://jasss.soc.surrey.ac.uk/20/1/3.html
    let local-density count local-prey
    ifelse (local-density > avg-local-density)[
      set search-mode "intensive"
    ][
      set search-mode "extensive"
    ]
  ]
end


;; GO ------------------------------------------------------------------------------------

to go
  ask prey with [not present?][
    regenerate
  ]
  ask predators [
    check-prey
    move
    update-search-mode
  ]
  tick                                                                              ; Advance the tick counter
end

to regenerate
  set regeneration-counter regeneration-counter + 1
  if (regeneration-counter >= regeneration-time)[
    set regeneration-counter 0
    set color 136
    set present? true
  ]
end

to check-prey
;  let target-prey prey with [distance myself <= detection-radius and present?]     ; finds prey within radius of actual predator position
  let target-prey nobody
  ask patch-here [ set target-prey prey with [distance myself <= detection-radius and present?] ]  ; finds prey within radius of center of grid where predator is located
  ifelse (any? target-prey)[
    let closest-prey min-one-of target-prey [distance myself]                       ; Creates an agent set (of one) indicating the identity of the nearest prey
    ask closest-prey [
      set color black
      set present? false
    ]
    set prey-captured prey-captured + 1
    if (search-tactic = "extensive-intensive")[
      set search-mode "intensive"
      set last-prey-capture 0
    ]
  ][
    if (search-tactic = "extensive-intensive" and search-mode = "intensive")[ set last-prey-capture last-prey-capture + 1 ]
  ]
end

to move
  ifelse (search-tactic = "random-sampling")[
    setxy (random-float (max-pxcor - 1) + 0.5) (random-float (max-pycor - 1) + 0.5) ; randomly relocate predator in virtual tank
  ][
    let dist draw-move-length search-mode                                           ; predator search mode is either intensive or extensive
    let turn draw-turn-angle search-mode
    set heading heading + turn
    let next-patch patch-ahead dist

    ifelse (next-patch != nobody and not shade-of? black [pcolor] of next-patch)[   ; check if next move will take predator outside of boundary patches or to boundary patch
      jump dist                                                                     ; if inside boundaries, simply need to jump to the next point
    ][
      ;; make smaller sub-movements when approaching boundary
      ;; model should not tick during these sub-movements; hence the while loop
      while [dist > 0][
        let sl step-length
        if (dist < step-length) [ set sl dist]
        let pa patch-ahead sl
        if (shade-of? black [pcolor] of pa)[
          let side check-side ([pxcor] of pa) ([pycor] of pa)
          if (side = "left/right")[ set heading (- heading) ]
          if (side = "bottom/top")[ set heading (180 - heading) ]
          ;; was having trouble with predators getting stuck in corners
          ;; decided to try this heavy-handed approach, i.e., setting heading to opposite direction (as if they headed directly into corner)
          if (side = "bottom-left")[ set heading 45 ]
          if (side = "top-left")[ set heading 135 ]
          if (side = "top-right")[ set heading 225 ]
          if (side = "bottom-right")[ set heading 315 ]
          set next-patch patch-ahead dist                                            ; find next patch (after turning) to complete the move length
          if (next-patch != nobody and not shade-of? black [pcolor] of next-patch)[
            jump dist
            set dist 0
          ]
        ]
        fd sl
        set dist dist - sl
      ]
    ]
  ]
end

to-report draw-move-length [ml-type]
  let ml-type-list []
  if (ml-type = "extensive") [ set ml-type-list ml-extensive ]
  if (ml-type = "intensive") [ set ml-type-list ml-intensive ]
  if (empty? ml-type-list) [ report word "ERROR: input must be extensive or intensive; not " ml-type]
  report calc-piecewise random-float 1 ml-type-list move-lengths
end

to-report draw-turn-angle [ta-type]
  let ta-type-list []
  if (ta-type = "extensive") [ set ta-type-list ta-extensive ]
  if (ta-type = "intensive") [ set ta-type-list ta-intensive ]
  if (empty? ta-type-list) [ report word "ERROR: input must be extensive or intensive; not " ta-type]
  report calc-piecewise random-float 1 ta-type-list turn-angles
end

to-report calc-piecewise [#xval #xList #yList]
  ;; https://stackoverflow.com/questions/50506275/table-functions-interpolation-in-netlogo
  if not (length #xList = length #ylist)[ report "ERROR: mismatched points"]
  if #xval <= first #xList [ report first #yList ]
  if #xval >= last #xList [ report last #yList ]
  ; iterate through x values to find first that is larger than input x
  let ii 0
  while [item ii #xlist <= #xval] [ set ii ii + 1 ]
  ; get the xy values bracketing the input x
  let xlow item (ii - 1) #xlist
  let xhigh item ii #xlist
  let ylow item (ii - 1) #ylist
  let yhigh item ii #ylist
  ; interpolate
  report ylow + ( (#xval - xlow) / (xhigh - xlow) ) * ( yhigh - ylow )
end

to-report check-side [x y]
  let out ""
  if (x = min-pxcor or x = max-pxcor) [ set out "left/right"  ]
  if (y = min-pycor or y = max-pycor) [ set out "bottom/top"  ]
  if (x = min-pxcor and y = min-pycor)[ set out "bottom-left" ]
  if (x = min-pxcor and y = max-pycor)[ set out "top-left"    ]
  if (x = max-pxcor and y = max-pycor)[ set out "top-right"   ]
  if (x = max-pxcor and y = min-pycor)[ set out "bottom-right"]
  if (out = "")[ error "Something unexpectedly went wrong..." ]
  report out
end

;; Tests ------------------------------------------------------------------------------------

to profile
  setup                  ;; set up the model
  profiler:start         ;; start profiling
;  repeat 60 [ setup ]    ;; run something you want to measure
  repeat 1000 [ go ]     ;; run something you want to measure
  profiler:stop          ;; stop profiling
  print profiler:report  ;; view the results
  profiler:reset         ;; clear the data
end

to show-response-radius
  ;; helper procedure for 'manually' testing model
  ifelse (search-tactic = "local-density")[
    ask patches with [pcolor = blue][ set pcolor 99 ]
    ask predators[
      let local-prey nobody
      ask patch-here [
        ask patches with [pcolor = 99] in-radius response-radius [set pcolor blue]
        set local-prey prey with [distance myself <= response-radius and present?]
      ]
      print count local-prey
      print search-mode
    ]
  ][
    print "Did you mean to select local-density as the search-tactic?"
  ]
end

to show-GUT
  ifelse (search-tactic = "extensive-intensive")[
    ask predators [
      print search-mode
      print last-prey-capture
    ]
  ][
    print "Did you mean to select extensive-intensive as the search-tactic?"
  ]
end

to test-corners
  setup
  ask predators [
    setxy 0.6 0.6
    set heading 225
    pen-down
    move
  ]
end

to test-random-draws
  let ml [["Extensive" "Intensive"]]
  let ta [["Extensive" "Intensive"]]
  let ctr 0
  while [ctr < 100000][
    set ml lput (list draw-move-length "extensive" draw-move-length "intensive") ml
    set ta lput (list draw-turn-angle "extensive" draw-turn-angle "intensive") ta
    set ctr ctr + 1
  ]
  csv:to-file "InputData/MoveLengthTest.csv" ml
  csv:to-file "InputData/TurnAngleTest.csv" ta
  print "done"
end

;; wasted a bunch of time re-inventing the wheel to try to use geometry to make predators reflect at boundaries
;; ended up with verbose code that never fully solved the problem
;; finally conceded my failure and wrote a much shorter version in idiomatic NetLogo code
;; putting some of the silly code down here as a record of my stupidity for the first git commit

;to-report point-ahead [x1 y1 head dist]
;  let x2 x1 + dist * sin head
;  let y2 y1 + dist * cos head
;  report (list x2 y2)
;end

;to-report slope-intercept [x1 y1 x2 y2]
;  ;; only returns slope and intercept for "sloped" line
;  let diff-x x2 - x1
;  if (diff-x = 0) [ report (list "vertical" x1) ]
;  let diff-y y2 - y1
;  if (diff-y = 0) [ report (list "horizontal" y1) ]
;  let m diff-y / diff-x
;  let b y1 - (m * x1)
;  report (list "sloped" m b)
;end

;to-report point-distance  [x1 y1 x2 y2]
;  report sqrt ( (x2 - x1) ^ 2 + (y2 - y1) ^ 2)
;end

;to-report check-point [xy]                                                     ; check if point is inside of world
;  let x item 0 xy
;  let y item 1 xy
;  let out true
;  if (x < (min-pxcor + 1) or y < (min-pycor + 1) or x > (max-pxcor - 1) or y > (max-pycor - 1)) [ set out false ]
;  report out
;end

;to-report check-region [xy]
;  if (check-point xy) [ error "New point is inside boundary, i.e., no intersection with boundary."]
;  let x item 0 xy
;  let y item 1 xy
;
;  if (y < min-pycor and x < min-pxcor) [ report "bottom-left" ]
;  if (y < min-pycor and x > max-pxcor) [ report "bottom-right"]
;  if (y > max-pycor and x < min-pxcor) [ report "top-left"    ]
;  if (y > max-pycor and x > max-pxcor) [ report "top-right"   ]
;
;  if (x < min-pxcor and y >= min-pycor and y <= max-pycor) [ report "left"  ]
;  if (x > max-pxcor and y >= min-pycor and y <= max-pycor) [ report "right" ]
;  if (y < min-pycor and x >= min-pxcor and x <= max-pxcor) [ report "bottom"]
;  if (y > max-pycor and x >= min-pxcor and x <= max-pxcor) [ report "top"   ]
;end

;to-report find-boundary-point [region si]  ;; si = slope-intercept
;  ;; I'm pretty sure that I'm forgetting some key geometry facts that would make this reporter more general and more robust
;  ;; moving forward for now...
;
;  let line-type item 0 si
;
;  if (line-type = "vertical")[
;    let x item 1 si
;    if (region = "top") [report (list x max-pycor)]
;    if (region = "bottom") [report (list x min-pycor)]
;  ]
;
;  if (line-type = "horizontal")[
;    let y item 1 si
;    if (region = "right") [report (list max-pxcor y)]
;    if (region = "left") [report (list min-pxcor y)]
;  ]
;
;  if (line-type = "sloped")[
;    let m item 1 si                  ;; slope
;    let b item 2 si                  ;; intercept
;
;    ;; values based on re-arranging y = mx + b, i.e., given slope, intercept, and x,y-coordinates of next point, find intersection points with the 4 lines that comprise the world
;    let left-side  (list min-pxcor (min-pxcor * m + b))     ;; not simplified to make rearrangment explicit
;    let right-side (list max-pxcor (max-pxcor * m + b))
;    let bottom (list ((min-pycor - b) / m) min-pycor)
;    let top    (list ((max-pycor - b) / m) max-pycor)
;
;    if (region = "left")  [ report left-side ]
;    if (region = "right") [ report right-side]
;    if (region = "bottom")[ report bottom    ]
;    if (region = "top")   [ report top       ]
;
;    if (region = "bottom-left") [
;      ;; need to check if plausible exit point is on bottom or left; where plausible means that it is in the world
;      if (check-point bottom)     [ report bottom ]
;      if (check-point left-side)  [ report left-side ]
;    ]
;    if (region = "bottom-right") [
;      if (check-point bottom)     [ report bottom ]
;      if (check-point right-side) [ report right-side ]
;    ]
;    if (region = "top-left") [
;      if (check-point top)        [ report top ]
;      if (check-point left-side)  [ report left-side ]
;    ]
;    if (region = "top-right") [
;      if (check-point top)        [ report top ]
;      if (check-point right-side) [ report right-side ]
;    ]
;  ]
;end
@#$#@#$#@
GRAPHICS-WINDOW
220
15
948
744
-1
-1
10.0
1
10
1
1
1
0
0
0
1
0
71
0
71
1
1
1
moves
30.0

BUTTON
25
375
91
408
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
135
375
198
408
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
50
430
172
463
pen-down?
pen-down?
1
1
-1000

TEXTBOX
25
355
200
381
-------------------------------------------
11
0.0
1

SLIDER
20
105
192
138
prey-patch-size
prey-patch-size
5
70
70.0
1
1
NIL
HORIZONTAL

SLIDER
20
150
192
183
prey-spacing
prey-spacing
0
10
7.0
1
1
NIL
HORIZONTAL

SLIDER
20
195
192
228
prey-number
prey-number
1
50
50.0
1
1
NIL
HORIZONTAL

SLIDER
20
295
192
328
response-radius
response-radius
1
9
6.5
0.5
1
NIL
HORIZONTAL

CHOOSER
20
240
195
285
search-tactic
search-tactic
"random-sampling" "extensive-only" "extensive-intensive" "local-density"
3

SWITCH
35
15
177
48
use-scenario?
use-scenario?
1
1
-1000

SLIDER
20
60
192
93
scenario
scenario
1
26
9.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?


## HOW IT WORKS


## CREDITS AND REFERENCES

Code hosted on [GitHub](https://github.com/hinkelman/ADDREPONAME).
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

aphid
true
14
Circle -16777216 true true 96 182 108
Circle -16777216 true true 110 127 80
Circle -16777216 true true 110 75 80
Line -16777216 true 150 100 80 30
Line -16777216 true 150 100 220 30

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

bean aphid
true
0
Circle -16777216 true false 96 182 108
Circle -16777216 true false 110 127 80
Circle -16777216 true false 110 75 80
Line -16777216 false 150 100 80 30
Line -16777216 false 150 100 220 30

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

egg
true
0
Circle -1184463 true false 105 30 90
Rectangle -1184463 true false 105 75 195 240
Circle -1184463 true false 105 195 90

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

ladybug
true
0
Circle -2674135 true false 22 22 256
Circle -16777216 true false 60 90 60
Circle -16777216 true false 180 90 60
Circle -16777216 true false 60 180 60
Circle -16777216 true false 180 180 60
Line -16777216 false 150 30 150 270

ladybug larva
true
14
Rectangle -16777216 true true 105 60 195 240
Circle -16777216 true true 105 15 90
Circle -16777216 true true 105 195 90
Line -16777216 true 195 60 225 45
Line -16777216 true 195 105 255 120
Line -16777216 true 195 150 240 180
Line -16777216 true 45 120 105 105
Line -16777216 true 105 60 75 45
Line -16777216 true 105 150 60 180

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pea aphid
true
0
Circle -2064490 true false 96 182 108
Circle -2064490 true false 110 127 80
Circle -2064490 true false 110 75 80
Line -2064490 false 150 100 80 30
Line -2064490 false 150 100 220 30

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="extensive-intensive_1-13" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;extensive-intensive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="1" step="1" last="13"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="extensive-intensive_14-26" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;extensive-intensive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="14" step="1" last="26"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="local-density_1-13" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;local-density&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="1" step="1" last="13"/>
    <enumeratedValueSet variable="response-radius">
      <value value="4.5"/>
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="local-density_14-26" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;local-density&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="14" step="1" last="26"/>
    <enumeratedValueSet variable="response-radius">
      <value value="4.5"/>
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="extensive-only_1-8" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;extensive-only&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="1" step="1" last="8"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="extensive-only_9-17" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;extensive-only&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="9" step="1" last="17"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="extensive-only_18-26" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;extensive-only&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="18" step="1" last="26"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="random-sampling_group-A" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;random-sampling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="1" step="1" last="8"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="random-sampling_group-B" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;random-sampling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="9" step="1" last="14"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="random-sampling_group-C" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;random-sampling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="15" step="1" last="20"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="random-sampling_group-D" repetitions="60" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;random-sampling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="21" step="1" last="26"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="test_group-A" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;random-sampling&quot;"/>
      <value value="&quot;extensive-only&quot;"/>
      <value value="&quot;extensive-intensive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="1" step="1" last="8"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="test2_group-A" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;local-density&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="1" step="1" last="8"/>
    <enumeratedValueSet variable="response-radius">
      <value value="4.5"/>
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="test_group-BCD" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1000000"/>
    <metric>[prey-captured] of predators</metric>
    <enumeratedValueSet variable="use-scenario?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="search-tactic">
      <value value="&quot;random-sampling&quot;"/>
      <value value="&quot;extensive-only&quot;"/>
      <value value="&quot;extensive-intensive&quot;"/>
      <value value="&quot;local-density&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pen-down?">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="scenario" first="9" step="1" last="26"/>
    <enumeratedValueSet variable="response-radius">
      <value value="9"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
