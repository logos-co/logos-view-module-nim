## A Qt plugin with no Logos dependencies at all, written entirely in Nim.
##
## The point of the test is that nothing here is special: `QPluginLoader` loads
## it, `QMetaObject` introspects it, and neither has any idea it is not C++.

import nimside
import seaqt/qobject, seaqt/QtCore/qtcore_pkg

qobject:
  type VanillaNim* = ref object of VirtualQObject
    count {.qproperty(write = true, notify = true).}: int32

  proc increment*(self: VanillaNim) {.slot.} =
    self.setCount(self.count + 1'i32)

when appType == "lib":
  Q_PLUGIN_METADATA(
    VanillaNim, QObject, "org.logos.VanillaNimInterface",
    uri = "https://logos.co/vanilla_nim", QtCoreCFlags
  )
else:
  {.error: "This module must be compiled as a shared library".}
