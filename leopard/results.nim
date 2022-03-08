type
  LeopardResult* = enum
    LeopardCallInitialize = -7.cint ## Call leoInit() first
    LeopardPlatform       = -6.cint ## Platform is unsupported
    LeopardInvalidInput   = -5.cint ## A function parameter was invalid
    LeopardInvalidCounts  = -4.cint ## Invalid counts provided
    LeopardInvalidSize    = -3.cint ## Buffer size must be multiple of 64 bytes
    LeopardTooMuchData    = -2.cint ## Buffer counts are too high
    LeopardNeedMoreData   = -1.cint ## Not enough recovery data received
    LeopardSuccess        =  0.cint ## Operation succeeded
