mode = ScriptMode.Verbose

packageName   = "leopard"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "A wrapper for Leopard-RS"
license       = "Apache License 2.0 or MIT"
installDirs   = @["vendor"]

requires "nim >= 1.2.0",
         "stew",
         "unittest2",
         "upraises >= 0.1.0 & < 0.2.0"
