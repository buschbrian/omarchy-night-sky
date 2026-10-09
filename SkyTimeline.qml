import QtQuick
import qs.Commons

Item {
  id: root
  required property var timeline
  property var bestWindow: null
  property real nowMs: Date.now()
  property real moonFraction: 0
  property bool waxing: true
  property bool south: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color sunColor: "#f2b347"
  readonly property color moonColor: "#ece6d2"
  readonly property color coreColor: "#72d6db"
  readonly property real plotLeft: Style.space(52)
  readonly property real plotWidth: Math.max(1, width - plotLeft - Style.space(32))
  readonly property var series: [
    { key: "sun", name: "Sun", glyph: "󰖨", tone: sunColor },
    { key: "moon", name: "Moon", glyph: "󰽢", tone: moonColor },
    { key: "core", name: "Milky Way core", glyph: "󰫢", tone: coreColor }
  ]
  readonly property var points: timeline ? timeline.curves.core : []
  property int pinnedIndex: -1
  property int hoverIndex: -1
  readonly property int selectedIndex: hoverIndex >= 0 ? hoverIndex : pinnedIndex >= 0 ? pinnedIndex : defaultIndex()
  readonly property real selectedAt: points.length ? points[selectedIndex][0] : 0
  readonly property string selectedTime: timeline && timeline.times ? timeline.times[selectedIndex] : "–"
  readonly property string selectedPhase: {
    var band = timeline ? timeline.sky.find(function(b) { return selectedAt >= b.a && selectedAt <= b.b }) : null
    return band ? ({ golden: "Golden hour", blue: "Blue hour", twilight: "Twilight", dark: "Astronomical dark", day: "Daylight" })[band.kind] : ""
  }
  readonly property real altitudeTop: {
    var high = 20
    if (timeline) for (var key in timeline.curves)
      for (var p of timeline.curves[key]) high = Math.max(high, p[1])
    return Math.min(90, Math.max(30, Math.ceil((high + 5) / 15) * 15))
  }
  readonly property real altitudeBottom: -24
  height: body.implicitHeight
  activeFocusOnTab: true
  Accessible.role: Accessible.Slider
  Accessible.name: "Sky timeline"
  Accessible.description: "Use left and right arrows to inspect time and the altitude of the sun, moon and Milky Way core. " + selectedTime + ". " + readout("sun") + ", " + readout("moon") + ", " + readout("core")
  Keys.onLeftPressed: move(-1)
  Keys.onRightPressed: move(1)
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
      hoverIndex = -1; pinnedIndex = event.key === Qt.Key_Home ? 0 : points.length - 1; event.accepted = true
    }
  }
  onTimelineChanged: { pinnedIndex = -1; hoverIndex = -1 }

  function nearest(at) {
    var best = 0
    for (var i = 1; i < points.length; i++) if (Math.abs(points[i][0] - at) < Math.abs(points[best][0] - at)) best = i
    return best
  }
  function defaultIndex() {
    if (!timeline || !points.length) return 0
    var span = timeline.end_ms - timeline.start_ms, at = (nowMs - timeline.start_ms) / span
    if (at >= 0 && at <= 1) return nearest(at)
    if (bestWindow) return nearest(((bestWindow.start_ms + bestWindow.end_ms) / 2 - timeline.start_ms) / span)
    if (timeline.core.length) return nearest((timeline.core[0].a + timeline.core[0].b) / 2)
    var highest = 0
    for (var i = 1; i < points.length; i++) if (points[i][1] > points[highest][1]) highest = i
    return highest
  }
  function move(amount) { var next = selectedIndex + amount; hoverIndex = -1; pinnedIndex = Math.max(0, Math.min(points.length - 1, next)) }
  function altitude(key) { return timeline && timeline.curves[key].length ? timeline.curves[key][selectedIndex][1] : null }
  function readout(key) { var a = altitude(key); return key + " " + (a === null ? "unavailable" : a.toFixed(1) + " degrees " + (a >= 0 ? "above horizon" : "below horizon")) }
  function rgba(c, alpha) { return Qt.rgba(c.r, c.g, c.b, alpha) }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(8)

    Row {
      width: parent.width
      Text { text: "Sky altitude"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
      Text { text: "  ·  " + root.selectedTime + "  ·  " + root.selectedPhase; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)
      Repeater {
        model: root.series
        Column {
          required property var modelData
          width: (body.width - Style.space(16)) / 3
          spacing: Style.space(3)
          Row {
            spacing: Style.space(4)
            Text { text: parent.parent.modelData.glyph; color: parent.parent.modelData.tone; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            Text { text: parent.parent.modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          Text {
            readonly property var value: root.altitude(parent.modelData.key)
            text: value === null ? "–" : (value > 0 ? "+" : "") + value.toFixed(1) + "°"
            color: parent.modelData.tone
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            readonly property var value: root.altitude(parent.modelData.key)
            text: value === null ? "Unavailable" : value < 0 ? "Below horizon" : parent.modelData.key === "core" && value < 10 ? "Low on horizon" : "Above horizon"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(14)
      Repeater {
        model: root.timeline ? root.timeline.sky : []
        Rectangle {
          required property var modelData
          x: root.plotLeft + modelData.a * root.plotWidth
          width: Math.max(1, (modelData.b - modelData.a) * root.plotWidth)
          height: parent.height
          color: ({ golden: "#dba254", blue: "#507fc4", twilight: "#354568", dark: "#141e33", day: "#8fb4d9" })[modelData.kind]
          Text {
            anchors.centerIn: parent
            text: parent.modelData.kind === "dark" ? "NIGHT" : parent.modelData.kind.toUpperCase()
            visible: implicitWidth + Style.space(8) < parent.width
            color: "#f3f6fb"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Item {
      id: plot
      width: parent.width
      height: Style.space(220)
      Canvas {
        id: canvas
        x: root.plotLeft
        width: root.plotWidth
        height: parent.height
        property var chart: root.timeline
        property int cursor: root.selectedIndex
        property real now: root.nowMs
        property var best: root.bestWindow
        property real scaleTop: root.altitudeTop
        onChartChanged: requestPaint()
        onCursorChanged: requestPaint()
        onNowChanged: requestPaint()
        onBestChanged: requestPaint()
        onScaleTopChanged: requestPaint()
        onWidthChanged: requestPaint()
        function yOf(alt) { return (root.altitudeTop - alt) / (root.altitudeTop - root.altitudeBottom) * height }
        function path(ctx, points, color, thickness, alpha, dashed) {
          ctx.strokeStyle = root.rgba(color, alpha); ctx.lineWidth = thickness
          ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.setLineDash(dashed ? [4, 5] : [])
          ctx.beginPath()
          for (var i = 0; i < points.length; i++) {
            var x = points[i][0] * width, y = yOf(points[i][1])
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
          }
          ctx.stroke(); ctx.setLineDash([])
        }
        function marker(ctx, key, x, y, tone) {
          var r = Style.space(5)
          ctx.fillStyle = "#101725"; ctx.strokeStyle = tone; ctx.lineWidth = 2
          ctx.beginPath(); ctx.arc(x, y, r + 3, 0, Math.PI * 2); ctx.fill()
          ctx.fillStyle = tone
          if (key === "core") {
            ctx.beginPath(); ctx.moveTo(x, y - r - 2); ctx.lineTo(x + 2, y - 2); ctx.lineTo(x + r + 2, y); ctx.lineTo(x + 2, y + 2)
            ctx.lineTo(x, y + r + 2); ctx.lineTo(x - 2, y + 2); ctx.lineTo(x - r - 2, y); ctx.lineTo(x - 2, y - 2); ctx.closePath(); ctx.fill()
          } else if (key === "sun") {
            ctx.beginPath(); ctx.arc(x, y, r - 1, 0, Math.PI * 2); ctx.fill()
            for (var i = 0; i < 8; i++) { var a = i * Math.PI / 4; ctx.beginPath(); ctx.moveTo(x + Math.cos(a) * (r + 2), y + Math.sin(a) * (r + 2)); ctx.lineTo(x + Math.cos(a) * (r + 4), y + Math.sin(a) * (r + 4)); ctx.stroke() }
          } else {
            ctx.strokeStyle = tone; ctx.beginPath(); ctx.arc(x, y, r, 0, 2 * Math.PI); ctx.stroke()
            var side = (root.waxing ? 1 : -1) * (root.south ? -1 : 1), k = 1 - 2 * root.moonFraction
            ctx.beginPath(); ctx.arc(x, y, r, -Math.PI / 2, Math.PI / 2, side < 0)
            for (var j = 0; j <= 24; j++) { var t = Math.PI / 2 - Math.PI * j / 24; ctx.lineTo(x + side * k * r * Math.cos(t), y + r * Math.sin(t)) }
            ctx.fill()
          }
        }
        onPaint: {
          var ctx = getContext("2d"); ctx.reset()
          if (!chart) return
          var w = width, h = height, y0 = yOf(0)
          ctx.save(); ctx.beginPath(); ctx.rect(0, 0, w, h); ctx.clip()
          ctx.fillStyle = "#101725"; ctx.fillRect(0, 0, w, h)
          for (var band of chart.sky) {
            ctx.fillStyle = ({ golden: "#dba254", blue: "#507fc4", twilight: "#354568", dark: "#141e33", day: "#8fb4d9" })[band.kind]
            ctx.globalAlpha = band.kind === "golden" ? 0.12 : 0.3
            ctx.fillRect(band.a * w, 0, (band.b - band.a) * w, h); ctx.globalAlpha = 1
          }
          ctx.fillStyle = "rgba(0,0,0,0.3)"; ctx.fillRect(0, y0, w, h - y0)
          ctx.strokeStyle = "rgba(230,237,245,0.12)"; ctx.lineWidth = 1
          for (var alt = 15; alt <= root.altitudeTop; alt += 15) { ctx.beginPath(); ctx.moveTo(0, yOf(alt)); ctx.lineTo(w, yOf(alt)); ctx.stroke() }
          for (var tick of chart.ticks) { ctx.beginPath(); ctx.moveTo(tick.at * w, 0); ctx.lineTo(tick.at * w, h); ctx.stroke() }
          ctx.strokeStyle = "rgba(230,237,245,0.55)"; ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke()
          ctx.setLineDash([3, 5]); ctx.strokeStyle = root.rgba(root.coreColor, 0.35)
          ctx.beginPath(); ctx.moveTo(0, yOf(10)); ctx.lineTo(w, yOf(10)); ctx.stroke(); ctx.setLineDash([])
          if (best) {
            var left = Math.max(0, (best.start_ms - chart.start_ms) / (chart.end_ms - chart.start_ms)) * w
            var right = Math.min(1, (best.end_ms - chart.start_ms) / (chart.end_ms - chart.start_ms)) * w
            ctx.fillStyle = best.level === "go" ? "rgba(76,175,122,0.12)" : "rgba(227,179,65,0.12)"; ctx.fillRect(left, 0, right - left, h)
            ctx.fillStyle = best.level === "go" ? "#4caf7a" : "#e3b341"; ctx.fillRect(left, 0, right - left, Style.space(3))
          }
          for (var body of root.series) {
            ctx.save(); ctx.beginPath(); ctx.rect(0, 0, w, y0); ctx.clip(); path(ctx, chart.curves[body.key], body.tone, 2.2, 0.9, false); ctx.restore()
            ctx.save(); ctx.beginPath(); ctx.rect(0, y0, w, h - y0); ctx.clip(); path(ctx, chart.curves[body.key], body.tone, 1.4, 0.55, true); ctx.restore()
          }
          for (var usable of chart.core) {
            ctx.save(); ctx.beginPath(); ctx.rect(usable.a * w, 0, (usable.b - usable.a) * w, y0); ctx.clip()
            path(ctx, chart.curves.core, root.coreColor, 4, 1, false); ctx.restore()
          }
          var nowAt = (now - chart.start_ms) / (chart.end_ms - chart.start_ms)
          if (nowAt >= 0 && nowAt <= 1) { ctx.strokeStyle = "#e0574f"; ctx.setLineDash([2, 4]); ctx.beginPath(); ctx.moveTo(nowAt * w, 0); ctx.lineTo(nowAt * w, h); ctx.stroke(); ctx.setLineDash([]) }
          var cursorX = root.selectedAt * w
          ctx.strokeStyle = "rgba(230,237,245,0.6)"; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(cursorX, 0); ctx.lineTo(cursorX, h); ctx.stroke()
          for (var object of root.series) { var value = root.altitude(object.key); if (value !== null && value >= root.altitudeBottom && value <= root.altitudeTop) marker(ctx, object.key, cursorX, yOf(value), object.tone) }
          ctx.restore()
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.CrossCursor
          onPositionChanged: function(mouse) { root.hoverIndex = root.nearest(Math.max(0, Math.min(1, mouse.x / width))); if (pressed) root.pinnedIndex = root.hoverIndex }
          onPressed: function(mouse) { root.pinnedIndex = root.nearest(mouse.x / width); root.forceActiveFocus() }
          onExited: root.hoverIndex = -1
        }
      }
      Repeater {
        model: root.altitudeTop <= 45 ? [30, 15, 0, -15] : [60, 30, 0, -15]
        Text {
          required property var modelData
          x: canvas.x - implicitWidth - Style.space(8)
          y: canvas.yOf(modelData) - implicitHeight / 2
          visible: modelData <= root.altitudeTop
          text: modelData === 0 ? "0°" : modelData + "°"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Text { x: canvas.x + canvas.width + Style.space(4); y: canvas.yOf(0) - implicitHeight / 2; text: "HZN"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      Text { x: canvas.x + canvas.width + Style.space(4); y: canvas.yOf(10) - implicitHeight / 2; text: "10°"; color: root.coreColor; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      Rectangle { anchors.fill: canvas; color: "transparent"; border.width: root.activeFocus ? 2 : 1; border.color: root.activeFocus ? root.coreColor : "#344158" }
    }

    Item {
      width: parent.width
      height: Style.space(16)
      Repeater {
        model: root.timeline ? root.timeline.ticks : []
        Text { required property var modelData; x: root.plotLeft + modelData.at * root.plotWidth - implicitWidth / 2; text: modelData.label + ":00"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      }
    }
    Text { width: parent.width; text: "Move over the chart or use ← → to inspect time. Bold core: moon down and ≥10°. Dashed paths: below horizon."; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
  }
}
