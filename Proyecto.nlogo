extensions [ table ]

globals [
  entry-point
  exit-point
  checkout-patches
  product-patches
  total-customers-finished
  total-shopping-time
  avg-shopping-time
  avg-queue-length
  product-data
  num-products
]

patches-own [
  p-type
  product-id
  visits-per-patch
  status
]

breed [customers customer]

customers-own [
  shopping-list
  shopping-cart
  state
  target-product
  entry-time
  exit-time
  time-searching
  items-impulsive
  path-length
  path
  destination
  checkout-timer
  paid?
]


to setup
  clear-all
  if not is-number? num-customers [ set num-customers 10 ]
  if not is-number? rearrangement-policy [ set rearrangement-policy 0 ]
  if not is-number? rearrangement-interval [ set rearrangement-interval 50 ]
  if not is-number? impulse-buy-prob [ set impulse-buy-prob 0.05 ]
  setup-layout
  setup-products
  set total-customers-finished 0
  set total-shopping-time 0
  set avg-shopping-time 0
  set avg-queue-length 0
  reset-ticks
end

to go
  if count customers < num-customers [
    create-new-customer
  ]
  ask customers [ customer-step ]
  if (rearrangement-policy != 0) and (ticks > 0) and (ticks mod rearrangement-interval = 0) [
    rearrange-layout
  ]
  update-global-metrics

  set-current-plot "Tiempo de Compra"
  plot avg-shopping-time

  tick
end


; CONFIGURACIÓN DEL ENTORNO

to setup-layout
  ask patches [
    set pcolor gray - 2
    set p-type "pasillo"
    set visits-per-patch 0
    set product-id 0
  ]


  ask patches with [ (pxcor mod 5 = 0) and (pycor > -12 and pycor < 16) and (pxcor != 0) ] [
    set pcolor brown
    set p-type "producto"
  ]

  set checkout-patches patches with [ pycor = -15 and abs pxcor < 6 and (pxcor mod 3 = 0) ]
  ask checkout-patches [
    set pcolor yellow
    set p-type "caja"
    set plabel "Caja"
    set status "free"
  ]

  set entry-point patch 14 -16
  ask entry-point [
    set pcolor green
    set p-type "entrada"
    set plabel "ENTRADA"
    set plabel-color white
  ]


  set exit-point patch -14 -16
  ask exit-point [
    set pcolor violet
    set p-type "salida"
    set plabel "SALIDA"
    set plabel-color white
  ]

  set product-patches patches with [ p-type = "producto" ]
end

to setup-products
  set num-products count product-patches
  set product-data []
  let i 1
  repeat num-products [
    set product-data lput (list i 0 0 0) product-data
    set i i + 1
  ]
  let available-patches product-patches
  foreach product-data [ p ->
    ask one-of available-patches [
      set product-id item 0 p
      set plabel product-id
      set available-patches other available-patches
    ]
  ]
end



to create-new-customer
  create-customers 1 [
    setxy ([pxcor] of entry-point) ([pycor] of entry-point)
    set shape "person"
    set color white
    set shopping-list generate-shopping-list
    set shopping-cart []
    set state "shopping"
    set target-product 0
    set entry-time ticks
    set time-searching 0
    set items-impulsive 0
    set path-length 0
    set path []
    set destination nobody
    set heading 0
    set checkout-timer 0
    set paid? false ;;
  ]
end

to-report generate-shopping-list
  let all-product-ids map [p -> item 0 p] product-data
  report n-of (min list (3 + random 3) length all-product-ids) all-product-ids
end


to customer-step
  if empty? path [
    decide-what-to-do
  ]

  follow-path

  if empty? path and destination != nobody [
    perform-arrival-action
  ]
end


to decide-what-to-do
  if state = "shopping" [
    ifelse empty? shopping-list [
      if not paid? [
        set state "going-to-checkout"
        set color green
        decide-what-to-do
      ]
    ] [
      set target-product first shopping-list
      set time-searching 0
      let target-patch one-of patches with [product-id = [target-product] of myself]
      if target-patch != nobody [
        set destination target-patch
        set path find-path patch-here destination
      ]
    ]
  ]

  if state = "going-to-checkout" [
    let target-checkout min-one-of checkout-patches with [status = "free"] [distance myself]

    if target-checkout != nobody [
      set destination target-checkout
      set path find-path patch-here destination
    ]
  ]


  if state = "in-queue" [
    ask patch-here [ set status "busy" ]

    if checkout-timer = 0 [
      set checkout-timer (10 + random 11)
    ]

    set checkout-timer checkout-timer - 1

    if checkout-timer <= 0 [
      set paid? true
      set state "leaving"
      set color white
      ask patch-here [ set status "free" ]
    ]
  ]


  if state = "leaving" [
    set destination exit-point
    set path find-path patch-here destination
  ]
end


to follow-path
  if not empty? path [
    let next-step first path
    if patch-here != next-step [
      face next-step
      move-to next-step
      set path-length path-length + 1
    ]
    set path but-first path
  ]
end

to perform-arrival-action
  if state = "shopping" [
    pick-up-product
    check-for-impulse-buy
  ]

  if state = "going-to-checkout" [
    set state "in-queue"
  ]


  if state = "leaving" [
    if patch-here = exit-point [ ;; Comprueba si ha llegado a la salida.
      record-final-stats
      die
    ]
  ]
  set destination nobody
end


to pick-up-product
  set shopping-cart lput target-product shopping-cart
  set shopping-list remove-item (position target-product shopping-list) shopping-list
  update-product-data target-product time-searching
  set target-product 0
  set color white
end

to check-for-impulse-buy
  let potential-impulse-patches neighbors with [p-type = "producto"]


  foreach patches-to-list potential-impulse-patches [ a-patch ->
    if random-float 1.0 < impulse-buy-prob [
      let impulsive-item [product-id] of a-patch
      if not member? impulsive-item shopping-cart [
        set shopping-cart lput impulsive-item shopping-cart
        set items-impulsive items-impulsive + 1
        set color red
      ]
    ]
  ]
end

to-report patches-to-list [ps]
  report [self] of ps
end


to wait-in-queue
  let my-checkout patch-here
  if count other customers-here = 0 and random 10 = 0 [
    set state "leaving"
  ]
end


to-report find-path [start-patch target-patch]
  if target-patch = nobody [ report [] ]

  let valid-goals nobody
  ifelse [p-type] of target-patch = "producto" [

    let target-neighbors [neighbors] of target-patch

    set valid-goals target-neighbors with [p-type != "producto"]

  ]
  [
    set valid-goals patch-set target-patch
  ]

  if not any? valid-goals [ report [] ]

  let queue (list start-patch)
  let visited-patches patch-set start-patch
  let came-from table:make

  while [not empty? queue] [
    let current-patch first queue
    set queue but-first queue

    if member? current-patch valid-goals [
      let path-reversed (list current-patch)
      let current-key (list [pxcor] of current-patch [pycor] of current-patch)
      while [table:has-key? came-from current-key] [
        set current-patch table:get came-from current-key
        set path-reversed lput current-patch path-reversed
        set current-key (list [pxcor] of current-patch [pycor] of current-patch)
      ]
      report but-first reverse path-reversed
    ]

    let current-neighbors [neighbors] of current-patch
    let valid-neighbors current-neighbors with [(p-type != "producto") and not member? self visited-patches]

    ask valid-neighbors [
      set visited-patches (patch-set visited-patches self)
      set queue lput self queue
      let key (list [pxcor] of self [pycor] of self)
      table:put came-from key current-patch
    ]
  ]

  report []
end


to update-product-data [prod-id search-duration]
  let index prod-id - 1
  let old-data item index product-data
  let new-demand (item 1 old-data) + 1
  let new-search-time (item 2 old-data) + search-duration
  let new-num-searches (item 3 old-data) + 1
  set product-data replace-item index product-data (list prod-id new-demand new-search-time new-num-searches)
end

to-report bubble-sort-by-score [list-to-sort]
  if length list-to-sort < 2 [ report list-to-sort ]
  let sorted-list list-to-sort
  let n length sorted-list
  repeat (n - 1) [
    let i 0
    while [ i < n - 1 ] [
      let item1 item i sorted-list
      let item2 item (i + 1) sorted-list
      if ( item 1 item2 ) > ( item 1 item1 ) [
        set sorted-list replace-item i sorted-list item2
        set sorted-list replace-item (i + 1) sorted-list item1
      ]
      set i i + 1
    ]
  ]
  report sorted-list
end

to-report bubble-sort-by-distance [patch-list]
  if length patch-list < 2 [ report patch-list ]
  let sorted-list patch-list
  let n length sorted-list
  let entryx [pxcor] of entry-point
  let entryy [pycor] of entry-point
  repeat (n - 1) [
    let i 0
    while [ i < n - 1 ] [
      let p1 item i sorted-list
      let p2 item (i + 1) sorted-list
      let dx1 ([pxcor] of p1) - entryx
      let dy1 ([pycor] of p1) - entryy
      let d1 dx1 * dx1 + dy1 * dy1
      let dx2 ([pxcor] of p2) - entryx
      let dy2 ([pycor] of p2) - entryy
      let d2 dx2 * dx2 + dy2 * dy2
      if d1 > d2 [
        set sorted-list replace-item i sorted-list p2
        set sorted-list replace-item (i + 1) sorted-list p1
      ]
      set i i + 1
    ]
  ]
  report sorted-list
end


to rearrange-layout
  let product-metrics []
  foreach product-data [ p ->
    let p-id item 0 p
    let p-demand item 1 p
    let p-total-search-time item 2 p
    let p-num-searches item 3 p
    let p-avg-search-time ifelse-value (p-num-searches > 0) [ p-total-search-time / p-num-searches ] [ 0 ]
    let score 0
    if rearrangement-policy = 1 [ set score p-demand * p-avg-search-time ]
    if rearrangement-policy = 2 [ set score (- p-demand) ]
    if rearrangement-policy = 3 [ set score random-float 1.0 ]
    set product-metrics lput (list p-id score) product-metrics
  ]

  let sorted-products bubble-sort-by-score product-metrics
  let patch-list [self] of product-patches
  let locations bubble-sort-by-distance patch-list
  let i 0
  while [ i < length sorted-products and i < length locations ] [
    let prod-info item i sorted-products
    let loc item i locations
    ask loc [
      set product-id item 0 prod-info
      set plabel product-id
    ]
    set i i + 1
  ]
end

to-report compare-products-by-score [p1 p2]
  report (item 1 p1) > (item 1 p2)
end

to-report compare-patches-by-distance [p1 p2]
  let d1 ([distance entry-point] of p1)
  let d2 ([distance entry-point] of p2)
  report d1 < d2
end

to update-global-metrics
  set avg-shopping-time ifelse-value (total-customers-finished > 0)
  [ total-shopping-time / total-customers-finished ]
  [ 0 ]
  let total-queue-length sum [ count customers-here ] of checkout-patches
  if ticks > 0 [
    set avg-queue-length (avg-queue-length * (ticks - 1) + total-queue-length) / ticks
  ]
  ask customers [
    ask patch-here [ set visits-per-patch visits-per-patch + 1 ]
  ]
  update-heatmap
end

to record-final-stats
  set exit-time ticks
  let time-in-store exit-time - entry-time
  set total-customers-finished total-customers-finished + 1
  set total-shopping-time total-shopping-time + time-in-store
end

to update-heatmap
  if max [ visits-per-patch ] of patches > 0 [
    ask patches with [ p-type = "pasillo" ] [
      set pcolor scale-color blue visits-per-patch 0 (max [ visits-per-patch ] of patches)
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
312
101
751
541
-1
-1
13.061
1
10
1
1
1
0
0
0
1
-16
16
-16
16
0
0
1
ticks
30.0

BUTTON
88
46
151
79
setup
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
164
46
227
79
go
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

SLIDER
102
125
274
158
num-customers
num-customers
10
200
200.0
1
1
NIL
HORIZONTAL

SLIDER
102
173
274
206
rearrangement-interval
rearrangement-interval
100
1000
150.0
50
1
NIL
HORIZONTAL

SLIDER
102
226
218
259
impulse-buy-prob
impulse-buy-prob
0.0
1.0
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
101
274
273
307
rearrangement-policy
rearrangement-policy
0
3
2.0
1
1
NIL
HORIZONTAL

MONITOR
314
43
423
88
N° customers
count customers
0
1
11

MONITOR
434
43
557
88
 avg-shopping-time
round avg-shopping-time
0
1
11

MONITOR
568
43
625
88
ticks
ticks
0
1
11

PLOT
782
101
982
251
Tiempo de Compra
ticks
Ticks por Cliente
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot avg-shopping-time"

PLOT
782
280
982
430
Congestión
ticks
Clientes en Cola
0.0
10.0
0.0
2.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot avg-queue-length"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

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

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

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

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
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
0
@#$#@#$#@
