#!/usr/bin/env python3
"""Offline ink-footprint audit of real QML vectors/glyphs and installed tray SVGs.

Use QT_SCALE_FACTOR=2 to audit at the desktop's scale. No shell instance, hardware,
preferences or application/tray logos are changed. Optional PNGs contain icons only.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PyQt6.QtCore import QRectF, QUrl, Qt
from PyQt6.QtGui import QGuiApplication, QImage, QPainter
from PyQt6.QtQuick import QQuickView
from PyQt6.QtSvg import QSvgRenderer
from PyQt6.QtTest import QTest

CONFIG=Path(__file__).resolve().parents[1] / ".config/quickshell"


def footprint(image, scale, transparent=False):
    pixels=[]
    weight=0
    for y in range(image.height()):
        for x in range(image.width()):
            color=image.pixelColor(x,y)
            coverage=color.alphaF() if transparent else color.redF()
            weight+=coverage
            if coverage>.12: pixels.append((x,y))
    return {"width":round((max(p[0] for p in pixels)-min(p[0] for p in pixels)+1)/scale,2),
            "height":round((max(p[1] for p in pixels)-min(p[1] for p in pixels)+1)/scale,2),
            "inkArea":round(weight/scale**2,2),
            "centerOffsetY":round(((min(p[1] for p in pixels)+max(p[1] for p in pixels)+1)/2-image.height()/2)/scale,3)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sound",type=int)
    parser.add_argument("--battery",type=int)
    parser.add_argument("--gear",type=int)
    parser.add_argument("--slot-size",type=int,choices=(14,15),default=14)
    parser.add_argument("--wifi",type=Path,default=Path("/usr/share/icons/Papirus-Dark/16x16@2x/panel/nm-signal-75-secure.svg"))
    parser.add_argument("--bluetooth",type=Path,default=Path("/usr/share/icons/Papirus-Dark/16x16@2x/panel/blueman-tray.svg"))
    parser.add_argument("--images",type=Path)
    args=parser.parse_args()
    theme=(CONFIG / "theme/Theme.qml").read_text()
    sizes={name:int(re.search(r'bar'+role+r'PaintSize: (\d+)',theme).group(1)) for name,role in (("sound","Sound"),("battery","Battery"),("gear","Settings"))}
    for name in sizes:
        if getattr(args,name) is not None: sizes[name]=getattr(args,name)
    if args.images: args.images.mkdir(parents=True,exist_ok=True)
    app=QGuiApplication([])
    results=[]
    def record(name, image, scale, transparent=False, **values):
        results.append({"icon":name,**values,**footprint(image,scale,transparent)})
        if args.images: image.save(str(args.images / (name+".png")))
    with tempfile.TemporaryDirectory() as tmp:
        root=Path(tmp)
        (root / "qs/theme").mkdir(parents=True)
        (root / "qs/theme/qmldir").write_text("module qs.theme\nsingleton Theme 1.0 Theme.qml\n")
        (root / "qs/theme/Theme.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property color surfaceText: "white"
    readonly property font iconFont: Qt.font({family:"Symbols Nerd Font",pixelSize:14,hintingPreference:Font.PreferVerticalHinting})
    function fontForRole(role) { return iconFont; }
}
''')
        for name in ("StatusIcon.qml","GlyphIcon.qml","ThemeText.qml"):
            shutil.copy2(CONFIG / "components" / name, root / name)
        (root / "audit.qml").write_text('''import QtQuick
Rectangle {
    id: root; width:64; height:40; color:"black"
    property string mode:"vector"
    property real paintSize:14
    property real slotSize:14
    property alias reading: vector.reading
    property alias glyph: glyph.glyph
    property string face:"Symbols Nerd Font"
    property bool boldFace:false
    StatusIcon { id:vector; anchors.horizontalCenter:parent.horizontalCenter; y:(parent.height-height)/2; visible:root.mode==="vector"; size:root.slotSize; inkSize:root.paintSize; color:"white" }
    GlyphIcon { id:glyph; anchors.horizontalCenter:parent.horizontalCenter; y:(parent.height-height)/2; visible:root.mode==="glyph"; size:root.slotSize; inkSize:root.paintSize; color:"white"; font.family:root.face; font.bold:root.boldFace }
}
''')
        view=QQuickView()
        view.engine().addImportPath(str(root))
        view.setSource(QUrl.fromLocalFile(str(root / "audit.qml")))
        assert not view.errors(),view.errors()
        view.show(); QTest.qWait(70)
        item=view.rootObject()
        item.setProperty("slotSize",args.slot_size)
        scale=view.devicePixelRatio()
        for name,path in (("wifi",args.wifi),("bluetooth",args.bluetooth)):
            svg=QSvgRenderer(str(path))
            if not svg.isValid(): raise RuntimeError(f"Invalid tray SVG: {path}")
            image=QImage(round(15*scale),round(15*scale),QImage.Format.Format_ARGB32_Premultiplied)
            image.fill(Qt.GlobalColor.transparent)
            painter=QPainter(image)
            svg.render(painter,QRectF(0,0,image.width(),image.height())); painter.end()
            record(name,image,scale,True,paintSize=15)
        vectors=[("sound-low",{"kind":"volume","value":20},sizes["sound"]),
                 ("sound",{"kind":"volume","value":50},sizes["sound"]),
                 ("sound-high",{"kind":"volume","value":80},sizes["sound"]),
                 ("sound-boost",{"kind":"volume","value":140},sizes["sound"]),
                 ("sound-muted",{"kind":"volume","value":50,"muted":True},sizes["sound"]),
                 ("sound-bluetooth",{"kind":"volume","value":50,"bluetooth":True},sizes["sound"]),
                 ("battery-empty",{"kind":"battery","value":0},sizes["battery"]),
                 ("battery",{"kind":"battery","value":50},sizes["battery"]),
                 ("battery-full",{"kind":"battery","value":100,"full":True},sizes["battery"]),
                 ("battery-charging",{"kind":"battery","value":50,"charging":True},sizes["battery"]),
                 ("battery-plugged",{"kind":"battery","value":50,"plugged":True},sizes["battery"]),
                 ("brightness-low",{"kind":"brightness","value":10},14),
                 ("brightness-medium",{"kind":"brightness","value":40},14),
                 ("brightness",{"kind":"brightness","value":100},14)]
        for name,reading,size in vectors:
            item.setProperty("reading",reading); item.setProperty("paintSize",size); QTest.qWait(35)
            record(name,view.grabWindow(),scale,paintSize=size)
        item.setProperty("mode","glyph")
        for name,glyph,size in (("settings","󰒓",sizes["gear"]),("notifications","󰂚",14),("dnd","󰂛",14),
                               ("clock","",14),("applications","󰀻",14),("media-playing","󰎆",14),("media-paused","󰏤",14)):
            item.setProperty("glyph",glyph); item.setProperty("paintSize",size); QTest.qWait(35)
            record(name,view.grabWindow(),scale,paintSize=size)
        item.setProperty("face","JetBrainsMono Nerd Font Propo"); item.setProperty("boldFace",True)
        item.setProperty("glyph",""); item.setProperty("paintSize",15); QTest.qWait(35)
        record("current-arch",view.grabWindow(),scale,paintSize=15)
        view.close()
    print(json.dumps({"scale":scale,"sizes":sizes,"icons":results},indent=2))


if __name__=="__main__": main()
