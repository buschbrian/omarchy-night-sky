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
  property real iconSize: Style.font.icon
  property color sunColor: "#f2b347"
  property color moonColor: "#ece6d2"
  property color coreColor: "#72d6db"
  property color radiantColor: "#b48cff"
  // The subject view from the helper: which object to emphasise, its target windows, a radiant curve.
  property var view: null
  readonly property string focusKey: view ? view.focus : "core"
  // The 10° guide gates the core and a shower radiant only.
  readonly property bool guideTen: focusKey === "core" || focusKey === "radiant"
  readonly property color guideTone: focusKey === "radiant" ? radiantColor : coreColor
  property var bandColors: ({ golden: "#dba254", blue: "#507fc4", twilight: "#354568", dark: "#141e33", day: "#8fb4d9" })
  // The right gutter holds the HZN / 10° marks here and the lane readouts below the chart.
  property real plotHeight: Style.space(100)
  readonly property real plotLeft: Style.space(40)
  readonly property real plotWidth: Math.max(1, width - plotLeft - Style.space(52))
  readonly property var series: [
    { key: "sun", name: "Sun", short: "Sun", glyph: "󰖨", tone: sunColor },
    { key: "moon", name: "Moon", short: "Moon", glyph: "󰽢", tone: moonColor },
    { key: "core", name: "Milky Way core", short: "Core", glyph: "󰫢", tone: coreColor }
  ].concat(view && view.radiant ? [{ key: "radiant", name: view.radiant.name + " radiant", short: "Radiant", glyph: "☄", tone: radiantColor }] : [])
  function curve(key) { return key === "radiant" ? (view && view.radiant ? view.radiant.curve : []) : timeline ? timeline.curves[key] : [] }
  readonly property var points: timeline ? timeline.curves.core : []
  property int pinnedIndex: -1
  property int hoverIndex: -1
  readonly property int selectedIndex: hoverIndex >= 0 ? hoverIndex : pinnedIndex >= 0 ? pinnedIndex : defaultIndex()
  readonly property real selectedAt: points.length ? points[selectedIndex][0] : 0
  readonly property string selectedTime: timeline && timeline.times ? timeline.times[selectedIndex] : "–"
  readonly property string selectedPhase: {
    var band = timeline ? timeline.sky.find(function(b) { return selectedAt >= b.a && selectedAt <= b.b }) : null
    return band ? ({ golden: "Golden hour", blue: "Blue hour", twilight: "Twilight", dark: "Night", day: "Daylight" })[band.kind] : ""
  }
  readonly property real altitudeTop: {
    var high = 20
    for (var s of series)
      for (var p of curve(s.key)) high = Math.max(high, p[1])
    return Math.min(90, Math.max(30, Math.ceil((high + 5) / 15) * 15))
  }
  readonly property real altitudeBottom: -24
  height: body.implicitHeight
  activeFocusOnTab: true
  Accessible.role: Accessible.Slider
  Accessible.name: "Sky timeline"
  Accessible.description: "Use left and right arrows to inspect time and the altitude of the sun, moon and " + (focusKey === "radiant" ? "meteor radiant" : "Milky Way core") + ". " + selectedTime + ". " + series.map(function(s) { return readout(s.key) }).join(", ")
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
  function altitude(key) { var c = curve(key); return c.length > selectedIndex ? c[selectedIndex][1] : null }
  function readout(key) { var a = altitude(key); return key + " " + (a === null ? "unavailable" : a.toFixed(1) + " degrees " + (a >= 0 ? "above horizon" : "below horizon")) }
  function rgba(c, alpha) { return Qt.rgba(c.r, c.g, c.b, alpha) }
  // One horizontal gradient through the middle of each sun-altitude band, so golden fades into blue into night.
  function skyGradient(ctx, w, alpha) {
    var g = ctx.createLinearGradient(0, 0, w, 0)
    for (var band of timeline.sky) {
      var c = Qt.lighter(bandColors[band.kind], 1)
      g.addColorStop(Math.max(0, Math.min(1, (band.a + band.b) / 2)), rgba(c, alpha))
    }
    return g
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.spacing.sm

    // Cursor time and phase, then each object's altitude: one line that reads as the chart's caption.
    Row {
      width: parent.width
      spacing: Style.spacing.xxl
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.selectedTime + " " + root.selectedPhase
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Repeater {
        model: root.series
        Row {
          id: readoutItem
          required property var modelData
          readonly property var value: root.altitude(modelData.key)
          spacing: Style.spacing.xs
          Text { anchors.verticalCenter: parent.verticalCenter; text: readoutItem.modelData.glyph; color: readoutItem.modelData.tone; font.family: root.fontFamily; font.pixelSize: root.iconSize }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: readoutItem.modelData.short + " " + (readoutItem.value === null ? "–" : (readoutItem.value > 0 ? "+" : "") + readoutItem.value.toFixed(0) + "°")
            color: readoutItem.value !== null && readoutItem.value < 0 ? Qt.darker(root.foreground, 1.5) : readoutItem.modelData.tone
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(10)
      Canvas {
        id: strip
        x: root.plotLeft
        width: root.plotWidth
        height: parent.height
        property var chart: root.timeline
        onChartChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d"); ctx.reset()
          if (!chart) return
          ctx.fillStyle = root.skyGradient(ctx, width, 1)
          ctx.fillRect(0, 0, width, height)
        }
      }
      Repeater {
        model: root.timeline ? root.timeline.sky : []
        Item {
          id: bandLabel
          required property var modelData
          x: root.plotLeft + modelData.a * root.plotWidth
          width: Math.max(1, (modelData.b - modelData.a) * root.plotWidth)
          height: parent.height
          Text {
            anchors.centerIn: parent
            text: ({ golden: "Golden", blue: "Blue", twilight: "Twilight", dark: "Night", day: "Day" })[bandLabel.modelData.kind]
            visible: implicitWidth + Style.space(8) < parent.width
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: root.fontFamily
            font.pixelSize: Math.round(Style.font.caption * 0.8)
          }
        }
      }
    }

    Item {
      id: plot
      width: parent.width
      height: root.plotHeight
      Canvas {
        id: canvas
        x: root.plotLeft
        width: root.plotWidth
        height: parent.height
        property var chart: root.timeline
        property int cursor: root.selectedIndex
        property real now: root.nowMs
        property var best: root.bestWindow
        property var subject: root.view
        onSubjectChanged: requestPaint()
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
          var r = Style.space(4)
          ctx.fillStyle = "#101725"; ctx.strokeStyle = tone; ctx.lineWidth = 2
          ctx.beginPath(); ctx.arc(x, y, r + 3, 0, Math.PI * 2); ctx.fill()
          var globe = ctx.createRadialGradient(x - r * 0.35, y - r * 0.4, 0, x, y, r + 1)
          globe.addColorStop(0, "#fff9e8"); globe.addColorStop(0.45, tone); globe.addColorStop(1, "#343b48")
          ctx.fillStyle = globe
          if (key === "core" || key === "radiant") {
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
          var skyShade = ctx.createLinearGradient(0, 0, 0, h)
          skyShade.addColorStop(0, "#080e1b"); skyShade.addColorStop(0.65, "#1b2b40"); skyShade.addColorStop(1, "#0b111c")
          ctx.fillStyle = skyShade; ctx.fillRect(0, 0, w, h)
          ctx.fillStyle = root.skyGradient(ctx, w, 0.3)
          ctx.fillRect(0, 0, w, h)
          var groundShade = ctx.createLinearGradient(0, y0, 0, h)
          groundShade.addColorStop(0, "#253341"); groundShade.addColorStop(1, "#0a1018")
          ctx.fillStyle = groundShade; ctx.fillRect(0, y0, w, h - y0)
          ctx.strokeStyle = "rgba(230,237,245,0.12)"; ctx.lineWidth = 1
          for (var alt = 15; alt <= root.altitudeTop; alt += 15) { ctx.beginPath(); ctx.moveTo(0, yOf(alt)); ctx.lineTo(w, yOf(alt)); ctx.stroke() }
          for (var tick of chart.ticks) { ctx.beginPath(); ctx.moveTo(tick.at * w, 0); ctx.lineTo(tick.at * w, h); ctx.stroke() }
          ctx.strokeStyle = "rgba(230,237,245,0.55)"; ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke()
          if (root.guideTen) {
            ctx.setLineDash([3, 5]); ctx.strokeStyle = root.rgba(root.guideTone, 0.35)
            ctx.beginPath(); ctx.moveTo(0, yOf(10)); ctx.lineTo(w, yOf(10)); ctx.stroke(); ctx.setLineDash([])
          }
          // The subject's target windows: a soft wash in the focused object's colour.
          var focusTone = root.focusKey === "moon" ? root.moonColor : root.focusKey === "radiant" ? root.radiantColor
                          : root.focusKey === "core" ? root.coreColor : root.rgba(root.foreground, 1)
          if (subject) for (var target of subject.targets) {
            var wash = ctx.createLinearGradient(0, 0, 0, y0)
            wash.addColorStop(0, root.rgba(focusTone, 0.16)); wash.addColorStop(1, root.rgba(focusTone, 0.02))
            ctx.fillStyle = wash; ctx.fillRect(target.a * w, 0, (target.b - target.a) * w, y0)
          }
          if (best) {
            var left = Math.max(0, (best.start_ms - chart.start_ms) / (chart.end_ms - chart.start_ms)) * w
            var right = Math.min(1, (best.end_ms - chart.start_ms) / (chart.end_ms - chart.start_ms)) * w
            ctx.fillStyle = best.level === "go" ? "rgba(76,175,122,0.12)" : "rgba(227,179,65,0.12)"; ctx.fillRect(left, 0, right - left, h)
            ctx.fillStyle = best.level === "go" ? "#4caf7a" : "#e3b341"; ctx.fillRect(left, 0, right - left, Style.space(3))
          }
          // The subject's object is drawn strong; the others recede.
          for (var series of root.series) {
            var focused = series.key === root.focusKey
            ctx.save(); ctx.beginPath(); ctx.rect(0, 0, w, y0); ctx.clip(); path(ctx, root.curve(series.key), series.tone, focused ? 2.6 : 1.6, focused ? 1 : 0.45, false); ctx.restore()
            ctx.save(); ctx.beginPath(); ctx.rect(0, y0, w, h - y0); ctx.clip(); path(ctx, root.curve(series.key), series.tone, 1.2, focused ? 0.6 : 0.3, true); ctx.restore()
          }
          if (root.focusKey === "core") for (var usable of chart.core) {
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
        model: {
          var marks = [-15], every = root.altitudeTop <= 45 ? 15 : 30
          for (var alt = 0; alt <= root.altitudeTop; alt += every) marks.push(alt)
          return marks
        }
        Text {
          required property var modelData
          x: canvas.x - implicitWidth - Style.space(8)
          y: canvas.yOf(modelData) - implicitHeight / 2
          text: modelData + "°"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Text { x: canvas.x + canvas.width + Style.space(4); y: canvas.yOf(0) - implicitHeight / 2; text: "HZN"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      Text { x: canvas.x + canvas.width + Style.space(4); y: canvas.yOf(10) - implicitHeight / 2; text: "10°"; visible: root.guideTen; color: root.guideTone; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      Rectangle { anchors.fill: canvas; color: "transparent"; border.width: root.activeFocus ? 2 : 1; border.color: root.activeFocus ? root.coreColor : root.rgba(root.foreground, 0.15) }
    }

  }
}
