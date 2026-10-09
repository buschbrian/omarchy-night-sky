import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Night sky for the Omarchy bar. Runs bin/night-sky --bar from this plugin's folder every
// few minutes. Pill: next sunrise/sunset, moon glyph and moon-free dark hours, plus a cloud
// or aurora glyph when the night calls for it. Left click opens the night panel: a sky chart
// from evening golden hour to the end of morning golden hour (golden, blue, twilight and
// night bands; sun, moon and Milky Way core altitude), cloud and Kp lanes, the evening and
// morning times, and where to point. ‹ › or the wheel browse other nights. Right click refreshes.
BarWidget {
  id: root
  moduleName: "buschbrian.night-sky"

  property var night: null
  property var view: null
  property int dayOffset: 0
  property bool popupOpen: false
  property real nowMs: Date.now()

  readonly property var panel: view ? view.panel : null
  readonly property var line: panel ? panel.timeline : null
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property var bandColors: ({ day: "#8fb4d9", golden: "#e0a050", blue: "#3d63b8", twilight: "#202d55", dark: "#0b101c" })
  readonly property color sunColor: "#f2b347"
  readonly property color moonColor: "#ece6d2"
  readonly property real gutter: Style.space(52)

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("bin/night-sky").toString().replace(/^file:\/\//, ""))
  readonly property real auroraKp: Number(setting("auroraKp", 6))
  readonly property var baseArgs: {
    var args = ["python3", script, "--bar", "--aurora-kp", String(auroraKp)]
    var lat = String(setting("latitude", "")).trim(), lon = String(setting("longitude", "")).trim()
    if (lat !== "" && lon !== "" && !isNaN(Number(lat)) && !isNaN(Number(lon))) args.push("--lat", lat, "--lon", lon)
    if (!setting("network", true)) args.push("--offline")
    return args
  }
  onBaseArgsChanged: refresh()

  visible: night !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function close() { popupOpen = false; dayOffset = 0 }
  function open() { view = night; popupOpen = true }
  function refresh() { if (!skyProc.running) skyProc.running = true }

  function viewDate() {
    var d = new Date(night.panel.date + "T12:00:00")
    d.setDate(d.getDate() + dayOffset)
    return Qt.formatDate(d, "yyyy-MM-dd")
  }

  function step(days) {
    if (!night || !night.panel) return
    dayOffset = Math.max(-30, Math.min(365, dayOffset + days))
    if (dayOffset === 0) { view = night; return }
    browseProc.command = baseArgs.concat(["--date", viewDate()])
    browseProc.running = true
  }

  function title() {
    if (!panel) return ""
    var label = Qt.formatDate(new Date(panel.date + "T12:00:00"), "ddd d MMM")
    if (dayOffset === 0) return "Tonight · " + label
    return dayOffset === 1 ? "Tomorrow · " + label : label
  }

  function moonTimes() {
    var spans = line ? line.moon : []
    if (!spans.length) return "not up"
    var first = spans[0], last = spans[spans.length - 1]
    var start = first.a === 0 ? "up at dusk" : "rises " + first.start
    return last.b === 1 ? (first.a === 0 ? "up all night" : start) : start + ", sets " + last.end
  }

  function minutesBetween(a, b) {
    if (a === "--" || b === "--") return ""
    var m = (parseInt(b.slice(0, 2)) * 60 + parseInt(b.slice(3))) - (parseInt(a.slice(0, 2)) * 60 + parseInt(a.slice(3)))
    return " " + ((m + 1440) % 1440) + "m"
  }

  function kpColor(kp) {
    if (kp >= 7) return "#c24bd6"
    if (kp >= 6) return "#e0457b"
    if (kp >= 5) return "#e08a3a"
    if (kp >= 4) return "#d9c34a"
    return "#4caf7a"
  }

  function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  IpcHandler {
    target: "buschbrian.night-sky"
    function toggle(): void { if (root.popupOpen) root.close(); else root.open() }
    function step(days: int): void { root.step(days) }
  }

  Process {
    id: skyProc
    command: root.baseArgs
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.night = JSON.parse(text)
          if (root.dayOffset === 0) root.view = root.night
        } catch (e) { root.night = null }
      }
    }
  }

  Process {
    id: browseProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.view = JSON.parse(text) } catch (e) {} }
    }
  }

  Timer {
    interval: Math.max(5, Number(root.setting("refreshMinutes", 10))) * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60 * 1000
    running: root.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.night ? root.night.text : ""
    active: root.night !== null && root.night.class === "go"
    horizontalMargin: 6
    tooltipText: root.popupOpen ? "" : (root.night ? root.night.tooltip : "")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (root.popupOpen) root.close()
      else root.open()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen && root.panel !== null
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      WheelHandler {
        onWheel: function(event) { root.step(event.angleDelta.y > 0 ? -1 : 1) }
      }

      // ---- Header: drawn moon, date, verdict
      Row {
        width: parent.width
        spacing: Style.space(12)

        Canvas {
          id: moonCanvas
          width: Style.space(52)
          height: width
          property real fraction: root.panel ? root.panel.moon.fraction : 0
          property bool waxing: root.panel ? root.panel.moon.waxing : true
          onFractionChanged: requestPaint()
          onWaxingChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var r = width / 2 - 1, cx = width / 2, cy = height / 2
            // Lit on the right while waxing as seen from the northern hemisphere; mirrored south.
            var side = (waxing ? 1 : -1) * (root.panel && root.panel.south ? -1 : 1), k = 1 - 2 * fraction
            ctx.fillStyle = root.rgba(root.fg, 0.12)
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
            // Lit limb from the top round to the bottom, back up along the terminator.
            ctx.fillStyle = root.moonColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2, side < 0)
            for (var i = 0; i <= 32; i++) {
              var t = Math.PI / 2 - Math.PI * i / 32
              ctx.lineTo(cx + side * k * r * Math.cos(t), cy + r * Math.sin(t))
            }
            ctx.fill()
          }
        }

        Column {
          width: parent.width - moonCanvas.width - parent.spacing
          spacing: Style.space(3)
          anchors.verticalCenter: parent.verticalCenter

          Item {
            width: parent.width
            height: titleText.implicitHeight

            Text {
              id: titleText
              text: root.title()
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              Button { iconText: "󰅁"; foreground: root.fg; tooltipText: "Previous night"; onClicked: root.step(-1) }
              Button { iconText: "󰅂"; foreground: root.fg; tooltipText: "Next night"; onClicked: root.step(1) }
            }
          }

          Text {
            width: parent.width
            text: root.panel ? root.panel.verdict : ""
            color: root.view && root.view.class === "go" ? Color.accent : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            text: root.panel ? root.panel.moon.phase + " · " + root.panel.moon.illumination_pct + "% lit · moon " + root.moonTimes() : ""
            color: Qt.darker(root.fg, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- Sky chart: sky colour by sun altitude, altitude curves, now marker
      Item {
        id: chartBox
        width: parent.width
        height: Style.space(150)
        visible: root.line !== null

        readonly property real altTop: 70
        readonly property real altBottom: -20

        Canvas {
          id: sky
          x: root.gutter
          width: parent.width - root.gutter * 2
          height: parent.height
          property var data: root.line
          property real now: root.nowMs
          property bool showNow: root.dayOffset === 0
          onDataChanged: requestPaint()
          onNowChanged: requestPaint()
          onShowNowChanged: requestPaint()
          onWidthChanged: requestPaint()

          function yOf(alt) {
            return (chartBox.altTop - Math.max(chartBox.altBottom, Math.min(chartBox.altTop, alt))) / (chartBox.altTop - chartBox.altBottom) * height
          }

          function curve(ctx, points, color, widthPx, alpha, minAlt) {
            ctx.strokeStyle = root.rgba(color, alpha)
            ctx.lineWidth = widthPx
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.beginPath()
            var drawing = false
            for (var i = 0; i < points.length; i++) {
              var p = points[i]
              if (p[1] < minAlt) { drawing = false; continue }
              var x = p[0] * width, y = yOf(p[1])
              if (drawing) ctx.lineTo(x, y); else ctx.moveTo(x, y)
              drawing = true
            }
            ctx.stroke()
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (!data) return
            var w = width, h = height, r = Style.space(8)

            ctx.save()
            ctx.beginPath()
            ctx.roundedRect(0, 0, w, h, r, r)
            ctx.clip()

            // Sky: a horizontal gradient through each band's centre, so the eleven
            // minutes of blue hour bleed into golden hour and twilight like the real sky.
            var g = ctx.createLinearGradient(0, 0, w, 0)
            var bands = data.sky
            g.addColorStop(0, root.bandColors[bands[0].kind])
            for (var i = 0; i < bands.length; i++)
              g.addColorStop((bands[i].a + bands[i].b) / 2, root.bandColors[bands[i].kind])
            g.addColorStop(1, root.bandColors[bands[bands.length - 1].kind])
            ctx.fillStyle = g
            ctx.fillRect(0, 0, w, h)

            // Fade towards the ground below the horizon.
            var y0 = yOf(0)
            var ground = ctx.createLinearGradient(0, y0, 0, h)
            ground.addColorStop(0, "rgba(0,0,0,0.15)")
            ground.addColorStop(1, "rgba(0,0,0,0.55)")
            ctx.fillStyle = ground
            ctx.fillRect(0, y0, w, h - y0)

            // A deterministic star field inside the dark band.
            var dark = bands.filter(function(b) { return b.kind === "dark" })
            ctx.fillStyle = "rgba(255,255,255,0.55)"
            for (var d = 0; d < dark.length; d++) {
              var seed = 7
              for (var s = 0; s < 70; s++) {
                seed = (seed * 16807) % 2147483647
                var sx = (dark[d].a + (dark[d].b - dark[d].a) * (seed % 1000) / 1000) * w
                seed = (seed * 16807) % 2147483647
                var sy = (seed % 1000) / 1000 * (y0 - 6)
                var sr = (s % 7 === 0) ? 1.1 : 0.6
                ctx.beginPath(); ctx.arc(sx, sy, sr, 0, 2 * Math.PI); ctx.fill()
              }
            }

            // Horizon and the core's 10° line.
            ctx.strokeStyle = "rgba(255,255,255,0.45)"
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke()
            var y10 = yOf(10)
            ctx.strokeStyle = "rgba(255,255,255,0.18)"
            ctx.setLineDash([3, 4])
            ctx.beginPath(); ctx.moveTo(0, y10); ctx.lineTo(w, y10); ctx.stroke()
            ctx.setLineDash([])

            // Curves: sun, moon (brighter and thicker the fuller it is), core (bold
            // where it is above 10° in moon-free dark).
            var frac = root.panel.moon.fraction
            curve(ctx, data.curves.sun, root.sunColor, 2, 0.95, -25)
            curve(ctx, data.curves.moon, root.moonColor, 1.5 + 2 * frac, 0.45 + 0.55 * frac, -25)
            curve(ctx, data.curves.core, Color.accent, 1.5, 0.55, -25)
            for (var c = 0; c < data.core.length; c++) {
              var span = data.core[c]
              var pts = data.curves.core.filter(function(p) { return p[0] >= span.a - 0.005 && p[0] <= span.b + 0.005 })
              curve(ctx, pts, Color.accent, 4, 1, -25)
            }

            // Now.
            var at = (now - data.start_ms) / (data.end_ms - data.start_ms)
            if (showNow && at >= 0 && at <= 1) {
              ctx.strokeStyle = Color.urgent
              ctx.lineWidth = 2
              ctx.beginPath(); ctx.moveTo(at * w, 0); ctx.lineTo(at * w, h); ctx.stroke()
            }
            ctx.restore()
          }
        }

        // Band names along the top edge, where a band is wide enough to hold one.
        Repeater {
          model: root.line ? root.line.sky : []
          Text {
            required property var modelData
            readonly property real span: (modelData.b - modelData.a) * sky.width
            visible: span > implicitWidth + Style.space(6)
            x: sky.x + (modelData.a + modelData.b) / 2 * sky.width - implicitWidth / 2
            y: Style.space(4)
            text: modelData.kind === "dark" ? "night" : modelData.kind
            color: "white"
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Repeater {
            model: [["Sun", root.sunColor], ["Moon", root.moonColor], ["Core", Color.accent]]
            Row {
              required property var modelData
              spacing: Style.space(4)
              Rectangle { width: Style.space(10); height: 3; radius: 1.5; color: modelData[1]; anchors.verticalCenter: parent.verticalCenter }
              Text { text: modelData[0]; color: Qt.darker(root.fg, 1.3); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            }
          }
        }

        Repeater {
          model: [60, 30, 10, 0]
          Text {
            required property var modelData
            x: sky.x + sky.width + Style.space(6)
            y: sky.yOf(modelData) - implicitHeight / 2
            text: modelData + "°"
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- Lanes: clouds by hour, Kp by 3-hour bin, then hour ticks
      Item {
        id: lanes
        width: parent.width
        height: Style.space(48)
        visible: root.line !== null

        readonly property real labelW: root.gutter
        readonly property real laneW: width - labelW * 2

        Repeater {
          model: [
            ["Clouds", 0, root.line && root.line.cloud_pct !== null ? root.line.cloud_pct + "%" : "—"],
            ["Aurora", Style.space(18), root.line && root.line.kp_max !== null ? "Kp " + root.line.kp_max.toFixed(1) : "—"]
          ]
          Item {
            required property var modelData
            y: modelData[1]
            width: lanes.width
            height: Style.space(14)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData[0]
              color: Qt.darker(root.fg, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData[2]
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              x: lanes.labelW; width: lanes.laneW; height: parent.height
              radius: Style.space(3)
              color: root.rgba(root.fg, 0.06)
            }
          }
        }

        Repeater {
          model: root.line && root.line.clouds ? root.line.clouds : []
          Rectangle {
            required property var modelData
            x: lanes.labelW + modelData.a * lanes.laneW
            width: Math.max(1, (modelData.b - modelData.a) * lanes.laneW - 1)
            height: Style.space(14)
            radius: Style.space(2)
            color: root.rgba(root.fg, 0.08 + 0.72 * modelData.total / 100)
          }
        }

        Repeater {
          model: root.line && root.line.kp ? root.line.kp : []
          Rectangle {
            required property var modelData
            readonly property real fill: Math.max(0.12, Math.min(1, modelData.kp / 9))
            x: lanes.labelW + modelData.a * lanes.laneW
            y: Style.space(18) + Style.space(14) * (1 - fill)
            width: Math.max(1, (modelData.b - modelData.a) * lanes.laneW - 1)
            height: Style.space(14) * fill
            radius: Style.space(2)
            color: root.kpColor(modelData.kp)
            opacity: modelData.observed === "predicted" ? 0.75 : 1
          }
        }

        // The aurora threshold from the widget settings (Kp 6 by default).
        Rectangle {
          visible: root.line !== null && root.line.kp !== null
          x: lanes.labelW; width: lanes.laneW; height: 1
          y: Style.space(18) + Style.space(14) * (1 - root.auroraKp / 9)
          color: root.rgba(root.fg, 0.35)
        }

        Repeater {
          model: root.line ? root.line.ticks : []
          Text {
            required property var modelData
            x: lanes.labelW + modelData.at * lanes.laneW - implicitWidth / 2
            y: Style.space(36)
            text: modelData.label
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator { foreground: root.fg }

      // ---- Evening and morning, in the colours of the chart
      Repeater {
        model: root.line ? [
          ["Evening", [
            ["golden", "󰖛", "Golden", root.line.events.evening.golden],
            ["golden", "󰖚", "Sunset", root.line.events.evening.sunset],
            ["blue", "󰖔", "Blue" + root.minutesBetween(root.line.events.evening.blue, root.line.events.evening.blue_end), root.line.events.evening.blue],
            ["dark", "󰽤", "Dark", root.line.events.evening.dark]]],
          ["Morning", [
            ["dark", "󰽥", "Dawn", root.line.events.morning.dawn],
            ["blue", "󰖔", "Blue" + root.minutesBetween(root.line.events.morning.blue, root.line.events.morning.golden), root.line.events.morning.blue],
            ["golden", "󰖜", "Sunrise", root.line.events.morning.sunrise],
            ["golden", "󰖨", "Golden", "to " + root.line.events.morning.golden_end]]]
        ] : []

        Row {
          id: eventRow
          required property var modelData
          width: column.width
          spacing: Style.space(6)

          Text {
            width: root.gutter - Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: eventRow.modelData[0]
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: eventRow.modelData[1]
            Rectangle {
              required property var modelData
              width: (column.width - root.gutter - Style.space(6) * 3) / 4
              height: Style.space(34)
              radius: Style.space(6)
              color: root.rgba(root.bandColors[modelData[0]], modelData[0] === "dark" ? 0.55 : 0.22)
              border.width: 1
              border.color: root.rgba(root.bandColors[modelData[0]], 0.6)

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                spacing: Style.space(5)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData[1]
                  color: modelData[0] === "golden" ? root.sunColor : root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    text: modelData[2]
                    color: Qt.darker(root.fg, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    text: modelData[3]
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }
        }
      }

      PanelSeparator { foreground: root.fg }

      // ---- Where to point, and what might spoil it
      Row {
        width: parent.width
        spacing: Style.space(12)
        visible: root.line !== null

        Canvas {
          id: compassCanvas
          width: Style.space(64)
          height: width
          property var core: root.line ? root.line.core_best : null
          property var moonDir: root.line ? root.line.moon_dir : null
          onCoreChanged: requestPaint()
          onMoonDirChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, r = width / 2 - 8
            ctx.strokeStyle = root.rgba(root.fg, 0.3)
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke()
            ctx.fillStyle = root.rgba(root.fg, 0.6)
            ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillText("N", cx, 5)
            function arrow(az, color, len, w) {
              var a = (az - 90) * Math.PI / 180
              ctx.strokeStyle = color
              ctx.lineWidth = w
              ctx.lineCap = "round"
              ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(a) * len, cy + Math.sin(a) * len); ctx.stroke()
              ctx.fillStyle = color
              ctx.beginPath(); ctx.arc(cx + Math.cos(a) * len, cy + Math.sin(a) * len, w + 1, 0, 2 * Math.PI); ctx.fill()
            }
            if (moonDir) arrow(moonDir.az, root.moonColor, r - 2, 1.5)
            if (core) arrow(core.az, Color.accent, r - 2, 2.5)
            ctx.fillStyle = root.fg
            ctx.beginPath(); ctx.arc(cx, cy, 2, 0, 2 * Math.PI); ctx.fill()
          }
        }

        Column {
          width: parent.width - compassCanvas.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Repeater {
            model: root.line ? [
              ["󰫢", Color.accent, root.line.core_best
                ? "Core best " + root.line.core_best.time + " · " + root.line.core_best.alt + "° " + root.line.core_best.dir + " (" + root.line.core_best.az + "°)"
                  + (root.line.core_best.moon_free ? "" : " · moonlit")
                : "Milky Way core stays below the horizon in the dark"],
              ["󰽢", root.moonColor, root.line.moon_dir
                ? "Moonrise " + root.line.moon_dir.time + " · " + root.line.moon_dir.dir + " (" + root.line.moon_dir.az + "°)"
                : "No moonrise in this window"]
            ].concat(root.panel.notes.map(function(n) {
              return [n.indexOf("Aurora") === 0 ? "󰭄" : "󰖐", n.indexOf("Aurora") === 0 ? root.kpColor(root.auroraKp) : root.fg, n]
            })) : []

            Row {
              required property var modelData
              spacing: Style.space(6)
              Text {
                width: Style.space(14)
                text: modelData[0]
                color: modelData[1]
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: modelData[2]
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
