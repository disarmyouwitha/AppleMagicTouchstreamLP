#!/usr/bin/env python3
"""Read-only registry evidence, scoped to the two prototype trackpads."""
import json,plistlib,subprocess
SERIALS={'J84HMA00H0B0000501','D0:C0:50:D4:75:6C'}
roots=plistlib.loads(subprocess.check_output(['ioreg','-a','-l','-w','0','-p','IOService']))
if isinstance(roots,dict):roots=[roots]
rows=[]
def visit(node,serial=None):
    current=node.get('StreamSerial',node.get('SerialNumber',serial))
    if isinstance(current,str) and current in SERIALS:serial=current
    cls=node.get('IOObjectClass','')
    name=node.get('IORegistryEntryName','')
    if serial in SERIALS and (cls in ['IOHIDInterface','AppleMultitouchDevice','IOUserService'] or 'Multitouch' in str(cls)):
        row={'serial':serial,'class':cls,'name':name,'registryID':node.get('IORegistryEntryID')}
        for key in ['StreamBuild','StreamOpened','StreamHandoffRequested','StreamSequence','HandoffOperation','HandoffCloseOrOpenResult','HandoffTerminateResult']:
            if key in node:row[key]=node[key]
        rows.append(row)
    for child in node.get('IORegistryEntryChildren',[]):visit(child,serial)
for root in roots:visit(root)
print(json.dumps(rows,indent=2))
