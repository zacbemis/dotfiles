import QtQuick

// Original small vector indicators. They use actual state rather than a clock
// glyph or a percentage label; no external icon assets or extra hardware reads.
Item {
    id: root
    property var reading: ({})
    property real size: 14
    property real inkSize: size
    property color color: "white"
    readonly property string kind: reading.kind || ""
    readonly property real value: Number.isFinite(reading.value) ? Math.max(0, reading.value) : 0
    readonly property real fraction: Math.min(100, value) / 100
    readonly property int waves: reading.muted || value === 0 ? 0 : value <= 33 ? 1 : value <= 66 ? 2 : 3
    readonly property string description: reading.available === false ? "Unavailable" : kind === "volume"
        ? (reading.muted ? "Muted" : value === 0 ? "Silent" : value > 100 ? "Boosted volume" : ["", "Low volume", "Medium volume", "High volume"][waves])
        : kind === "brightness" ? (value === 0 ? "Minimum brightness" : value <= 33 ? "Low brightness" : value <= 66 ? "Medium brightness" : "High brightness")
        : reading.charging ? "Charging" : reading.full ? "Fully charged" : reading.plugged ? "Plugged in" : value <= 20 ? "Low battery" : "On battery"
    Accessible.role: Accessible.Graphic
    Accessible.name: description + (reading.available === false ? "" : ", " + Math.round(value) + " percent")
        + (kind === "volume" && reading.bluetooth ? ", Bluetooth" : "")
    implicitWidth: size * (kind === "battery" ? 1.2 : kind === "volume" && reading.bluetooth ? 1.5 : 1)
    implicitHeight: size
    onReadingChanged: if (ink) ink.requestPaint()
    onColorChanged: if (ink) ink.requestPaint()
    onSizeChanged: if (ink) ink.requestPaint()
    onInkSizeChanged: if (ink) ink.requestPaint()
    onWidthChanged: if (ink) ink.requestPaint()
    onHeightChanged: if (ink) ink.requestPaint()
    Canvas {
        id: ink
        anchors.horizontalCenter: parent.horizontalCenter
        // Keep half-logical-pixel centers at HiDPI instead of rounding odd
        // paint heights up/down relative to the speaker/tray center line.
        y: (parent.height - height) / 2
        width: root.width * root.inkSize / root.size
        height: root.height * root.inkSize / root.size
        antialiasing: true
        onPaint: {
            const c = getContext("2d");
            c.reset();
            c.clearRect(0, 0, width, height);
            c.scale(root.inkSize / 24, root.inkSize / 24);
            c.strokeStyle = root.color;
            c.fillStyle = root.color;
            c.lineWidth = 1.8;
            c.lineCap = "round";
            c.lineJoin = "round";
            function line(x1, y1, x2, y2) { c.beginPath(); c.moveTo(x1,y1); c.lineTo(x2,y2); c.stroke(); }
            function polygon(points) {
                c.beginPath(); c.moveTo(points[0][0],points[0][1]);
                for (let i=1; i<points.length; ++i) c.lineTo(points[i][0],points[i][1]);
                c.closePath(); c.fill();
            }
            if (root.reading.available === false) { line(6,12,18,12); return; }
            if (root.kind === "battery") {
                c.strokeRect(2,5,21,14);
                c.fillRect(24,9,2.5,6);
                c.fillRect(4.5,7.5,16 * root.fraction,9);
                if (root.reading.charging) {
                    // A transparent halo separates the bolt from every fill
                    // level, including an empty battery, on any bar backplate.
                    const points = [[14,5],[8,13],[12,13],[10,19],[18,10],[14,10]];
                    c.globalCompositeOperation = "destination-out";
                    polygon(points); c.lineWidth = 3; c.stroke();
                    c.globalCompositeOperation = "source-over";
                    polygon(points);
                } else if (root.reading.full || root.reading.plugged) {
                    function badge() {
                        if (root.reading.full) { line(8,12,11,15); line(11,15,17,9); }
                        else { line(10,8,10,11); line(15,8,15,11); line(9,11,16,11); line(10,11,10,14); line(15,11,15,14); line(10,14,15,14); line(12.5,14,12.5,17); }
                    }
                    c.globalCompositeOperation = "destination-out"; c.lineWidth = 4; badge();
                    c.globalCompositeOperation = "source-over"; c.lineWidth = 1.8; badge();
                }
            } else if (root.kind === "brightness") {
                c.beginPath(); c.arc(12,12,4,0,Math.PI*2); c.stroke();
                if (root.fraction > 0) {
                    c.beginPath(); c.moveTo(12,12); c.arc(12,12,3,-Math.PI/2,-Math.PI/2+Math.PI*2*root.fraction); c.closePath(); c.fill();
                    // Opposite pairs keep the sun centered at every level.
                    const pairs = Math.ceil(root.fraction*4);
                    for (let i=0; i<pairs; ++i) for (const direction of [1,-1]) {
                        const a = -Math.PI/2+i*Math.PI/4;
                        line(12+direction*Math.cos(a)*7,12+direction*Math.sin(a)*7,12+direction*Math.cos(a)*10,12+direction*Math.sin(a)*10);
                    }
                }
            } else if (root.kind === "volume") {
                polygon([[2,9],[6,9],[11,5],[11,19],[6,15],[2,15]]);
                if (root.reading.muted) { line(15,8,22,16); line(22,8,15,16); }
                else for (let i=0; i<root.waves; ++i) {
                    c.beginPath(); c.arc(9,12,5+i*3,-.8,.8); c.stroke();
                }
                if (root.value > 100 && !root.reading.muted) { line(19,3,23,3); line(21,1,21,5); }
                if (root.reading.bluetooth) {
                    line(28,5,28,19); line(28,5,33,9); line(33,9,24,16); line(24,8,33,15); line(33,15,28,19);
                }
            }
        }
    }
}
