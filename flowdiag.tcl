package require Tk

namespace path [list {*}[namespace path] ::tcl::mathop ::tcl::mathfunc]
interp alias {} ::tcl::mathfunc::list {} list

grid [ttk::frame .c] -sticky nwes
  grid [canvas .c.canvas -background white -state normal] -sticky nwes -columnspan 2
    bind .c.canvas <1> { focus %W }
    bind .c.canvas <MouseWheel> {
      puts "%D"
      %W yview scroll [expr {-%D/120}] units
    }

  text .c.input -undo yes
    bind .c.input <Return> {
      set this_line [.c.input get {insert linestart} {insert lineend}]
      regexp {^\s*} $this_line indentation
      if {![info complete $this_line]} {
        append indentation "  "
      }
      .c.input insert insert "\n$indentation"
      break
    }

    bind .c.input <Tab> {
      indent %W ^ {insert $idx "  "}
      break
    }

    bind .c.input <Control-Tab> {
      puts "bark"
      indent %W {^  } {delete $idx "$idx + $count chars"}
      break
    }
  text .c.errors -state disabled
  grid .c.input .c.errors -sticky nwes

  grid rowconfigure .c 0 -weight 2
  grid rowconfigure .c 1 -weight 1
  grid columnconfigure .c 0 -weight 1
  grid columnconfigure .c 0 -weight 2

grid rowconfigure . 0 -weight 1
grid columnconfigure . 0 -weight 1

bind .c.input <Control-s> {
  set file [tk_getSaveFile]
  set chan [open $file w]
  if {$file ne {}} {
    try {
      puts $chan [string trimright [%W get 1.0 end]]
    } finally {
      close $chan
    }
  }
}

bind .c.input <Control-o> {
  set file [tk_getOpenFile]
  if {$file ne {}} {
    set chan [open $file r]
    try {
      %W replace 1.0 end [read $chan]
    } finally {
      close $chan
    }
  }
}

bind all <Button-4> {event generate [focus -displayof %W] <MouseWheel> -delta  120}
bind all <Button-5> {event generate [focus -displayof %W] <MouseWheel> -delta -120}

interp create processing
processing eval { namespace delete :: }
interp alias processing unknown {} compile_coro

source dyn.tcl

proc redraw {} {
    .c.errors configure -state normal
    try {
      compile .c.canvas .c.input
      .c.errors delete 1.0 end
    } on error {} {
      .c.errors replace 1.0 end $::errorInfo
    } finally {      
      .c.errors configure -state disabled
    }
    .c.input edit modified 0 
}

bind .c.input <<Modified>> {
  if {[.c.input edit modified]} {
    redraw
  }
}
