proc indent {text regexp command} {
  if {[llength [$text tag ranges sel]] > 0} {
    set from sel.first
    set to sel.last
  } else {
    set from insert
    set to insert
  }

  set indices [$text search -regexp -all -elide -count counts $regexp "$from linestart" "$to lineend"]
  foreach idx $indices count $counts {
    eval $text $command
  }
}

proc dassign {dict args} {
  foreach arg $args {
    upvar 1 $arg var
    set var [dict get $dict $arg]
  }
}

proc argassign {list args} {
  if {[llength $args] != [llength $list]} {
    error "wrong # args: expected [llength $args], got [llength $list]"
  }
  uplevel [list lassign $list {*}$args]
}

proc yieldm {{value {}}} {
  tailcall yieldto string cat $value
}

proc nextrow {} {
  upvar 1 starty starty canvas canvas nodespc nodespc row row
  lassign [$canvas bbox {*}[dict values $row]] x1 y1 x2 y2
  set starty [+ $y2 $nodespc]
  set row {}
}

proc outline {type bbox cx cy} {
  lassign $bbox x1 y1 x2 y2
  switch $type {
    do { list rectangle [- $x1 5] [- $y1 5] [+ $x2 5] [+ $y2 5] -fill yellow }
    if - unless {
      list polygon \
        [- $x1 20] $cy \
        $cx [- $y1 20] \
        [+ $x2 20] $cy \
        $cx [+ $y2 20] \
        -fill "light green" \
        -outline black
    }
    endpoint {
      list polygon \
        [- $x1 10] [- $y1 10] \
        [+ $x2 20] [- $y1 10] \
        [+ $x2 10] [+ $y2 10] \
        [- $x1 20] [+ $y2 10] \
        -fill pink \
        -outline black
    }
  }
}

proc backmove {backmove backmove_nextx} {
  upvar canvas canvas nodesections nodesections
  lassign [$canvas coords $backmove] backmove_x backmove_y
  if {$backmove_y >= $starty || $backmove_x == $backmove_nextx} return
  set dy [- $starty $backmove_y]
  $canvas move $backmove 0 $dy
  dict set row $nodesections($backmove) $backmove
  set lprevs [$canvas find withtag [list lprev $backmove]]
  set lnexts [$canvas find withtag [list lnext $backmove]]
  foreach lprev $lprevs {
    set lprev_y [lindex [$canvas coords $lprev] 1]
    $canvas imove $lnext 3 [+ $lnext_y [- $starty $backmove_y]]
  }

  foreach lnext $lnexts {
    set lnext_y [lindex [$canvas coords $lnext] 3]
    $canvas imove $lprev 1 [+ $lprev_y [- $starty $backmove_y]]
  }

  if {[llength $lprevs] == 0} {
    # there's no line to follow back
    break
  }

  foreach lprev $lprevs {
    foreach {tag value} $lprev {
      if {$tag eq "lnext"} {
        backmove $value $backmove_x          
      }
    }
  }
}

interp alias {} tcl::mathfunc::list {} list
proc tcl::mathfunc::overlap {r1 r2} {
  lassign $r1 x1 x2
  lassign $r2 y1 y2
  expr {
    min($x1, $x2) <= max($y1, $y2)
    && min($y1, $y2) <= max($x1, $x2)
  }
}

proc avg {args} {
  / [+ {*}$args] [llength $args]
}

proc line_overlaps {coords spec} {
  upvar canvas canvas
  if {[llength $coords] < 4} {
    return -code error "Need at least 4 coordinates, got [llength $coords]"
  }
  lassign [lrange $coords 0 1] x1 y1
  foreach {x2 y2} [lrange $coords 2 end] {
    $canvas addtag line_overlaps overlapping [min $x1 $x2] [min $y1 $y2] [max $x1 $x2] [max $y1 $y2]

    # we delete all the lines that intersect while crossing each other
    foreach oline [$canvas find withtag "line_overlaps && line"] {
      set olinecoords [$canvas coords $oline]
      lassign [lrange $olinecoords 0 1] olinex1 oliney1
      set olineskip 1
      # because all the lines are orthogonal, i don't need to whip out the algebraic geometry or whatever
      foreach {olinex2 oliney2} [lrange $olinecoords 2 end] {
        if {
             ($x1 == $x2 && $x2 == $olinex1 && $olinex1 == $olinex2 && overlap(list($y1, $y2), list($oliney1, $oliney2)))
          || ($y1 == $y2 && $y2 == $oliney1 && $oliney1 == $oliney2 && overlap(list($x1, $x2), list($olinex1, $olinex2)))
        } then {
          set olineskip 0
          break
        }
        set olinex1 $olinex2
        set oliney1 $oliney2
      }

      if {$olineskip} {
        $canvas dtag $oline line_overlaps
      }
    }
    set x1 $x2
    set y1 $y2
  }

  set ret [$canvas find withtag "line_overlaps && ($spec)"]

  $canvas dtag line_overlaps
  set ret
}

proc portpos {port node} {
  upvar canvas canvas
  lassign [$canvas bbox $node] x1 y1 x2 y2
  lassign [$canvas coords $node] cx cy
  puts "$node is at $cx $cy between $x1 $y1 $x2 $y2"
  switch $port {
    north { list $cx $y1 }
    west  { list $x1 $cy }
    east  { list $x2 $cy }
    south { list $cx $y2 }
  }
}

proc lnconnect {prevport -> curport {through {}} {thrucoords {}}} {
  upvar lports lports coords coords prev prev cur cur canvas canvas ideal ideal ports ports
  upvar ox1 ox1 oy1 oy1 ox2 ox2 oy2 oy2
  if {${->} ne "->" || $through ni {{} through}} {
    return -code error "invalid args, expected prevport -> curport ?through ?arg arg ...??, got [info level 0]"
  }

  puts [info level 0]
  if {$ideal} return
  upvar k k
  set k 0
  set coordscript [concat list $thrucoords]
  for {set i 0} {$i < 10} {incr i} {
    set finalcoords [uplevel 1 $coordscript]
    incr k

    puts "Trying: $finalcoords"
    if {[llength $finalcoords] < 4} break
    if {[llength [line_overlaps $finalcoords node||line]] == 0} break
  }
  set lports(prev) $prevport
  set lports(cur) $curport
  set coords [list {*}[portpos $prevport $prev] {*}$finalcoords {*}[portpos $curport $cur]]
  set overlapping [line_overlaps $coords node]
  set ideal [expr {
       [try { lindex [dict get $ports $prev $prevport] 0 } trap {TCL LOOKUP DICT} {} {}] ne "in"
    && [try { lindex [dict get $ports $cur  $curport ] 0 } trap {TCL LOOKUP DICT} {} {}] ne "out"
    && [llength $overlapping] == 0
  }]
  lassign [$canvas bbox $prev $cur {*}$overlapping] ox1 oy1 ox2 oy2
}

proc lall {list args} {
  set arglist [lrange args 0 end-1]
  set cond [lrange args end]
  uplevel 1 [list try \
    [list foreach $arglist $list [list if $cond { return -level 0 -code 9 }]] \
    on 9 {} {
      string cat 0
    } on ok {} {
      string cat 1
    }]
}

proc avail_ports {node} {
  upvar ports ports
  lmap port {north east south west} {
    if {[dict exists $ports $node $port]} continue
  }
}

proc connect_nodes {prev cur label} {
  upvar canvas canvas row row starty starty nodespc nodespc nodesections nodesections ports ports
  set ideal 0
  set overlapping {}
  lassign [$canvas coords $cur] cur_x cur_y
  lassign [$canvas coords $prev] prev_x prev_y
  lassign [$canvas bbox $cur] cur_x1 cur_y1 cur_x2 cur_y2
  lassign [$canvas bbox $prev] prev_x1 prev_y1 prev_x2 prev_y2

  puts "$prev_x $cur_x $prev_y $cur_y"
  if {abs($prev_y - $cur_y) < 2} {
    if {$prev_x < $cur_x} {
      lnconnect east -> west
    } elseif {$cur_x < $prev_x} {
      lnconnect west -> east
    }
  } elseif {abs($prev_x - $cur_x) < 2} {
    lnconnect south -> north
    lnconnect west -> west through {[- $ox1 20 [* 10 $k]] $prev_y [- $ox1 20 [* 10 $k]] $cur_y }
    lnconnect east -> east through {[+ $ox2 20 [* 10 $k]] $prev_y [+ $ox2 20 [* 10 $k]] $cur_y }
  } else {
    lnconnect south -> east through {$prev_x $cur_y}
    lnconnect north -> west through {$prev_x $cur_y}
    lnconnect south -> west through {$prev_x $cur_y}
    lnconnect east -> north through {$cur_x $prev_y}
    lnconnect west -> north through {$cur_x $prev_y}
    lnconnect west -> north through {[- $ox1 [* 10 $k]] $prev_y}
    lnconnect south -> north through {$prev_x [avg $cur_y $prev_y] $cur_x [avg $cur_y $prev_y]}
  }



  puts "$prev:$lports(prev) -> $cur:$lports(cur), ideal: $ideal"
  #puts "cur: [$canvas coords $cur] prev: [$canvas coords $prev]"
  dict set ports $prev $lports(prev) [list out $cur]
  dict set ports $cur  $lports(cur)  [list in $prev]
  $canvas create line {*}$coords -tags [list [list lprev $prev] [list lnext $cur] line] -arrow last \
     -fill [expr {$ideal ? "black" : "red"}]
  if {$label ne {}} {
    lassign $coords lx ly
    $canvas create text $lx $ly -text $label -anchor [dict get {
      west se
      east sw
      south ne
    } $lports(prev)] -tags $prev
  }
}

proc place_node {node prev_nodesname} {
  upvar row row nodesections nodesections canvas canvas starty starty nodespc nodespc sectionxs sectionxs maxwidth maxwidth
  upvar nodecounter nodecounter ports ports labels labels active_label active_label
  upvar 1 $prev_nodesname prev_nodes

  set node [lassign $node type]
  set mainlabel {}
  # whether to connect this node to the one after its subnodes
  set maincont yes
  switch $type {
    do { lassign $node section title }
    endpoint { lassign $node section title }
    if {
      lassign $node section title bodies(jā) bodies(nē)
      set maincont no
    }
    label {
      lassign $node jumplabel
      set prev_nodes [expr { [info exists labels($jumplabel)] ? $labels($jumplabel) : [list] }]
      set labels($jumplabel) [list PLACED]
      set active_label $jumplabel
      return
    }
    goto {
      lassign $node jumplabel
      if {[info exists labels($jumplabel)]} { puts labels($jumplabel):$labels($jumplabel) }
      if {[info exists labels($jumplabel)] && [lindex $labels($jumplabel) 0] eq "PLACED"} {
        puts "processing goto $jumplabel with PLACED set"
        set next_node [lindex $labels($jumplabel) 1]
        puts "next_node: $next_node"
        foreach {prev_node label} $prev_nodes {
          connect_nodes $prev_node $next_node $label
        }

        set prev_nodes {}
        return
      }
      lappend labels($jumplabel) {*}$prev_nodes
      set prev_nodes {}
      return
    }
    terminate {
      set prev_nodes {}
      return
    }
    isolate {
      lassign $node bodies(isolate)
      set isolateprev_nodes {}
      foreach subnode $bodies(isolate) {
        place_node $subnode isolateprev_nodes
      }
      return
    }
    default { error "No such type: $type" }
  }
  upvar 0 sectionxs($section) sectionx
  if {![info exists sectionx]} {
    error "No such section: $section"      
  }
  if {[dict exists $row $section]} nextrow

  set nodeid node[incr nodecounter]
  # marker for moveto
  set marker [$canvas create rectangle $sectionx $starty $sectionx $starty -tags $nodeid]
  set text [$canvas create text $sectionx $starty -width $maxwidth -text $title -tags $nodeid -justify center]
  set bbox [$canvas bbox $text]
  set rect [$canvas create {*}[outline $type $bbox $sectionx $starty] -tags $nodeid]
  $canvas lower $rect $text
  $canvas addtag node withtag $nodeid
  while {[
    $canvas addtag place_node_overlap overlapping {*}[$canvas bbox $nodeid]
    set found [$canvas find withtag "place_node_overlap && !$nodeid"]
    $canvas dtag place_node_overlap
    expr {[llength $found] > 0}
  ]} {
    nextrow
    $canvas moveto $nodeid $sectionx $starty
  }
  puts "$nodeid\t| $title"

  if {[info exists prev_nodes]} {
    foreach {prev_node label} $prev_nodes {
      connect_nodes $prev_node $nodeid $label
    }
  }

  if {[info exists active_label]} {
    puts "active_label exists, adding to labels($active_label)"
    lappend labels($active_label) $nodeid
    unset active_label
  }

  dict set row $section $nodeid
  set nodesections($nodeid) $section
  if {$maincont} {
    set prev_nodes [list $nodeid $mainlabel]
  } else {
    set prev_nodes {}
  }
  
  if {[array exists bodies]} {
    foreach {bodylabel body} [lsort -stride 2 -index 0 [array get bodies]] {
      set subprev_nodes [list $nodeid $bodylabel]
      foreach subnode $body {
        place_node $subnode subprev_nodes
      }
      lappend prev_nodes {*}$subprev_nodes
    }
  }
}

proc dbg x {
  puts $x
  return $x
}

# invokes compile_coromake recursively to compile a block.
proc compile_block {block} {
  yieldto eval [subst {
    compile_coro
    processing eval [list $block]
    compile_coro
  }]

  compile_coromake
}

proc compile_coromake {} {
  set sections {}
  set nodes {}
  set maxwidth 200
  while {[llength [set args [yieldm]]] > 0} {
    set args [lassign $args cmd]
    switch $cmd {
      section {
        argassign $args name
        lappend sections $name
      }
      do {
        argassign $args section title
        lappend nodes [list do $section $title]
      }
      endpoint {
        argassign $args section title
        lappend nodes [list endpoint $section $title]
      }
      unless - if {
        if {[llength $args] < 3} {
          return -code error "wrong # args: expected section condition thenbody ?elseif elseifbody? ... ?else elsebody?"
        }
        set args [lassign $args section condition thenbody]
        set elsebody {}
        switch [lindex $args 0] {
          else {
            argassign $args _ elsebody
          }
          elseif {
            set elsebody [list if {*}[lrange $args 1 end]]
          }
          {} {}
          default {
            return -code error "invalid argument [lindex $args 0]: expected either else or elseif"
          }
        }
        set thennodes [dict get [compile_block $thenbody] nodes]
        set elsenodes [dict get [compile_block $elsebody] nodes]
        lappend nodes [list if $section $condition {*}[switch $cmd {
          if { list $thennodes $elsenodes }
          unless { list $elsenodes $thennodes }
        }]]
      }
      label {
        argassign $args name
        lappend nodes [list label $name]
      }
      goto {
        argassign $args label
        lappend nodes [list goto $label]
      }
      isolate {
        argassign $args isolatebody
        lappend nodes [list isolate [dict get [compile_block $isolatebody] nodes]]
      }
      terminate {
        argassign $args
        lappend nodes terminate
      }
      maxwidth {
        argassign $args maxwidth
      }
      default {
        error "Unknown command: $cmd"
      }
    }
  }

  return [concat {*}[lmap name {sections nodes maxwidth} { list $name [set $name] }]]
}

proc compile {canvas text} {
  coroutine compile_coro compile_coromake
  processing eval [$text get 1.0 end]
  dassign [dbg [compile_coro]] sections nodes maxwidth
  
  $canvas delete all

  if {[llength sections] == 0} return
  set sectionunit [/ [winfo width $canvas] [llength $sections]]
  set idx 0
  foreach section $sections {
    if {$idx > 0} {
      set divisorx [* $sectionunit $idx]
      $canvas create line $divisorx 0 $divisorx 20000
    }
    set sectionxs($section) [* [+ $idx 0.5] $sectionunit]

    $canvas create text $sectionxs($section) 20 -text $section
    incr idx
  }

  set nodespc 50
  set starty 100
  set row {}
  set ports {}
  foreach node $nodes {
    place_node $node prev_nodes
  }
}
