import ./utils/allocs

when defined(amd64) or defined(i386):
  import ./utils/cpuinfo_x86
  export cpuinfo_x86

export allocs
