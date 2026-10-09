import QtQuick
import QtQuick.Controls as QQC
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
  property int tab: 0
  property string mode: String(setting("mode", "milky-way"))
  property string savedLocation: String(setting("savedLocation", ""))
  property var comparison: []
  property string locationMessage: ""
  property var places: []
  readonly property var modes: [
    { key: "milky-way", label: "Milky Way" }, { key: "meteors", label: "Meteors" },
    { key: "aurora", label: "Aurora" }, { key: "moonlit", label: "Moonlit" }
  ]

  // Normalised to null: a "set location" reply or an older cached reply has no panel or shoot.
  readonly property var panel: view && view.panel ? view.panel : null
  readonly property var line: panel && panel.timeline ? panel.timeline : null
  readonly property var shoot: panel && panel.shoot ? panel.shoot : null
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property var bandColors: ({ day: "#8fb4d9", golden: "#e0a050", blue: "#3d63b8", twilight: "#202d55", dark: "#0b101c" })
  readonly property color sunColor: "#f2b347"
  readonly property color moonColor: "#ece6d2"
  readonly property real gutter: Style.space(52)

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("bin/night-sky").toString().replace(/^file:\/\//, ""))
  readonly property real auroraKp: Number(setting("auroraKp", 6))
  readonly property var baseArgs: {
    var args = ["python3", script, "--bar", "--aurora-kp", String(auroraKp), "--mode", mode]
    if (savedLocation !== "") args.push("--saved-location", savedLocation)
    var tz = String(setting("timezone", "")).trim(), name = String(setting("locationName", "")).trim()
    if (tz !== "") args.push("--tz", tz)
    if (name !== "") args.push("--location-name", name)
    var lat = String(setting("latitude", "")).trim(), lon = String(setting("longitude", "")).trim()
    if (lat !== "" && lon !== "" && !isNaN(Number(lat)) && !isNaN(Number(lon))) args.push("--lat", lat, "--lon", lon)
    if (!setting("network", true)) args.push("--offline")
    var focal = Number(setting("focalLength", 0)), aperture = Number(setting("aperture", "")),
        pitch = Number(setting("pixelPitch", "")), crop = Number(setting("cropFactor", "1"))
    if (focal > 0) {
      args.push("--focal", String(focal), "--crop", String(crop > 0 ? crop : 1))
      if (aperture > 0) args.push("--aperture", String(aperture))
      if (pitch > 0) args.push("--pitch", String(pitch))
    }
    return args
  }
  onBaseArgsChanged: { dayOffset = 0; comparison = []; refresh() }

  visible: night !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function close() { popupOpen = false; dayOffset = 0; tab = 0 }
  function open() { view = night; popupOpen = true; placesProc.running = true }
  property bool rerun: false
  // A settings change while a run is in flight would otherwise be dropped.
  property var runArgs: []
  property var browseArgs: []
  property string wantedDate: ""
  function refresh() {
    if (skyProc.running) rerun = true
    else { runArgs = baseArgs.slice(); skyProc.running = true }
  }
  function browse() {
    if (browseProc.running || dayOffset === 0) return
    browseArgs = baseArgs.concat(["--date", wantedDate])
    browseProc.running = true
  }
  function ago(iso) {
    if (!iso) return "never checked"
    var m = Math.max(0, Math.floor((nowMs - new Date(iso).getTime()) / 60000))
    return m < 1 ? "just now" : m < 60 ? m + "m ago" : Math.floor(m / 60) + "h ago"
  }
  function sourceText(key) {
    if (!panel || !panel.sources) return ""
    var s = panel.sources[key], label = ({ clouds: "Clouds / wind", haze: "Haze", kp: "Kp" })[key]
    return label + " · updated " + ago(s.updated) + (s.stale ? " · stale" : "") + (!s.available ? " · no data for this window" : "")
  }
  function comparePlaces() {
    if (compareProc.running) return
    comparison = []
    compareArgs = baseArgs.concat(["--compare-locations", "--date", panel.date])
    compareProc.running = true
  }
  property var compareArgs: []
  property var placeArgs: []
  function savePlace() {
    if (placeProc.running) return
    locationMessage = ""
    placeArgs = ["python3", script, "--save-location", placeName.text, "--lat", placeLat.text,
                 "--lon", placeLon.text, "--tz", placeTz.text]
    placeProc.running = true
  }
  function removePlace(name) {
    if (placeProc.running) return
    locationMessage = ""
    if (savedLocation === name) savedLocation = ""
    placeArgs = ["python3", script, "--remove-location", name]
    placeProc.running = true
  }

  function viewDate() {
    var d = new Date(night.panel.date + "T12:00:00")
    d.setDate(d.getDate() + dayOffset)
    return Qt.formatDate(d, "yyyy-MM-dd")
  }

  function step(days) {
    if (!night || !night.panel) return
    panelScroll.contentY = 0
    dayOffset = Math.max(-30, Math.min(365, dayOffset + days))
    if (dayOffset === 0) { view = night; return }
    wantedDate = viewDate()
    comparison = []
    browse()
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

  readonly property var levelColors: ({ "go": "#4caf7a", "marginal": "#e3b341", "no-go": "#e0574f" })
  readonly property var ratingColors: ({ good: "#4caf7a", marginal: "#e3b341", poor: "#e0574f", unavailable: "#808080", shown: "#808080" })
  readonly property var factorNames: ({ shoot_minutes: "Target window", moon_free_minutes: "Moon-free", cloud_cover_total: "Clouds", cloud_cover_max_hour: "Cloud peak",
    aerosol_optical_depth: "Haze", wind_gust: "Gusts", dew_point_spread: "Dew spread", gc_max_altitude: "Core", jet_stream: "Jet stream" })

  function jetColor(kmh) { return kmh === null || kmh === undefined ? "transparent" : kmh <= 70 ? "#4caf7a" : kmh <= 110 ? "#e3b341" : "#e0574f" }

  function goToDate(iso) {
    if (!night || !night.panel) return
    var base = new Date(night.panel.date + "T12:00:00"), target = new Date(iso + "T12:00:00")
    step(Math.round((target - base) / 86400000) - dayOffset)
    tab = 0
  }

  IpcHandler {
    target: "buschbrian.night-sky"
    function toggle(): void { if (root.popupOpen) root.close(); else root.open() }
    function step(days: int): void { root.step(days) }
    function showTab(index: int): void { root.tab = Math.max(0, Math.min(2, index)); panelScroll.contentY = 0 }
    function selectMode(key: string): void { if (root.modes.some(function(m) { return m.key === key })) root.mode = key }
    function selectLocation(name: string): void { if (name === "" || root.places.some(function(p) { return p.name === name })) root.savedLocation = name }
    function compare(): void { if (root.panel) root.comparePlaces() }
  }

  Process {
    id: skyProc
    command: root.runArgs
    onExited: if (root.rerun) { root.rerun = false; root.refresh() }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (JSON.stringify(root.runArgs) !== JSON.stringify(root.baseArgs)) return
          root.night = JSON.parse(text)
          if (root.night.panel) root.places = root.night.panel.saved_locations
          if (root.dayOffset === 0) root.view = root.night
        } catch (e) { root.night = null }
      }
    }
  }

  Process {
    id: browseProc
    command: root.browseArgs
    onExited: if (root.dayOffset !== 0 && JSON.stringify(root.browseArgs) !== JSON.stringify(root.baseArgs.concat(["--date", root.wantedDate]))) root.browse()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.dayOffset === 0 || JSON.stringify(root.browseArgs) !== JSON.stringify(root.baseArgs.concat(["--date", root.wantedDate]))) return
        try { root.view = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Process {
    id: placesProc
    command: ["python3", root.script, "--list-locations"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.places = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: placeProc
    command: root.placeArgs
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.error) root.locationMessage = result.error
          else {
            root.places = result.saved_locations
            root.locationMessage = "Saved locations updated."
            root.comparison = []
            root.refresh()
          }
        } catch (e) { root.locationMessage = "Could not save. Check the coordinates and time zone." }
      }
    }
  }
  Process {
    id: compareProc
    command: root.compareArgs
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (root.panel && JSON.stringify(root.compareArgs) === JSON.stringify(root.baseArgs.concat(["--compare-locations", "--date", root.panel.date])))
            root.comparison = JSON.parse(text).comparison
        } catch (e) { root.locationMessage = "Could not compare locations." }
      }
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
    contentWidth: popup.fittedContentWidth(Style.space(540))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(620))

    FocusScope {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

    Flickable {
      id: panelScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      QQC.ScrollBar.vertical: QQC.ScrollBar {
        policy: QQC.ScrollBar.AsNeeded
        contentItem: Rectangle { implicitWidth: Style.space(4); radius: width / 2; color: root.fg; opacity: 0.5 }
      }

    Column {
      id: column
      width: panelScroll.width - Style.space(10)
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(6)
        Text {
          width: parent.width - Style.space(30)
          text: root.panel && root.panel.location ? root.panel.location.name + " · " + root.panel.location.tz + " · local times" : ""
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Button {
          iconText: "󰑐"
          foreground: root.fg
          tooltipText: "Refresh"
          focusable: true
          iconSpinning: skyProc.running || browseProc.running
          onClicked: { root.refresh(); if (root.dayOffset !== 0) root.browse() }
        }
      }
      Flow {
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: root.modes
          Button {
            required property var modelData
            text: modelData.label
            selected: root.mode === modelData.key
            bordered: selected
            foreground: root.fg
            fontSize: Style.font.bodySmall
            focusable: true
            onClicked: root.mode = modelData.key
          }
        }
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
            height: Math.max(titleText.implicitHeight, nightNavigation.implicitHeight)

            Text {
              id: titleText
              width: parent.width - nightNavigation.width - Style.space(6)
              wrapMode: Text.WordWrap
              text: root.title()
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Row {
              id: nightNavigation
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              Button { iconText: "󰅁"; foreground: root.fg; tooltipText: "Previous night"; focusable: true; onClicked: root.step(-1) }
              Button { iconText: "󰅂"; foreground: root.fg; tooltipText: "Next night"; focusable: true; onClicked: root.step(1) }
            }
          }

          Row {
            spacing: Style.space(6)
            visible: root.shoot !== null
            Rectangle {
              readonly property color tone: root.shoot ? root.levelColors[root.shoot.level] : root.fg
              width: Math.min(verdictText.implicitWidth + Style.space(16), column.width - Style.space(76))
              height: verdictText.implicitHeight + Style.space(6)
              radius: height / 2
              color: root.rgba(tone, 0.22)
              border.width: 1
              border.color: tone
              Text {
                id: verdictText
                width: parent.width - Style.space(16)
                elide: Text.ElideRight
                anchors.centerIn: parent
                text: root.shoot ? root.shoot.headline : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.shoot !== null && root.shoot.aurora === true
              text: "󰭄"
              color: root.kpColor(root.auroraKp)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            text: root.panel ? root.panel.verdict : ""
            color: Qt.darker(root.fg, 1.15)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.panel ? root.panel.moon.phase + " · " + root.panel.moon.illumination_pct + "% lit · moon " + root.moonTimes() : ""
            color: Qt.darker(root.fg, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        spacing: Style.space(4)
        Repeater {
          model: ["Night", "Week & events", "Locations"]
          Button {
            required property var modelData
            required property int index
            text: modelData
            selected: root.tab === index
            bordered: root.tab === index
            foreground: root.fg
            fontSize: Style.font.bodySmall
            focusable: true
            onClicked: { root.tab = index; panelScroll.contentY = 0 }
          }
        }
      }

      Column {
        id: tonightTab
        width: parent.width
        spacing: Style.space(10)
        visible: root.tab === 0

      Column {
        width: parent.width
        spacing: Style.space(4)
        Text {
          width: parent.width
          text: root.panel && root.panel.best_window ? "Best window · " + root.panel.best_window.headline : "No usable future window for this subject in the available forecast."
          color: root.panel && root.panel.best_window ? root.levelColors[root.panel.best_window.level] : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          visible: root.panel !== null && root.panel.best_window !== null
          text: root.panel && root.panel.best_window ? root.panel.best_window.subject + " · " + root.panel.best_window.minutes + "m"
            + (root.panel.best_window.incomplete ? " · incomplete forecast" : "")
            + (root.panel.best_window.stale ? " · stale forecast" : "") : ""
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: "Assessment above covers the whole target window; the chart highlights the best interval."
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      SkyTimeline {
        id: skyTimeline
        width: parent.width
        visible: root.line !== null
        timeline: root.line
        bestWindow: root.panel ? root.panel.best_window : null
        nowMs: root.nowMs
        moonFraction: root.panel ? root.panel.moon.fraction : 0
        waxing: root.panel ? root.panel.moon.waxing : true
        south: root.panel ? root.panel.south : false
        foreground: root.fg
        fontFamily: root.fontFamily
      }

      // ---- Lanes: cloud by layer (high, mid, low), jet-stream seeing proxy, Kp; then hour ticks
      Item {
        id: lanes
        width: parent.width
        height: Style.space(84)
        visible: root.line !== null

        readonly property real labelW: skyTimeline.plotLeft
        readonly property real laneW: skyTimeline.plotWidth
        readonly property real row: Style.space(7)

        Repeater {
          model: [
            ["Clouds", 0, Style.space(23), root.line && root.line.cloud_pct !== null ? root.line.cloud_pct + "%" : "—"],
            ["Seeing", Style.space(28), Style.space(10), root.line && root.line.clouds && root.line.clouds.length
              ? Math.round(Math.max.apply(null, root.line.clouds.map(function(c) { return c.jet || 0 }))) + " km/h" : "—"],
            ["Aurora", Style.space(44), Style.space(16), root.line && root.line.kp_max !== null ? "Kp " + root.line.kp_max.toFixed(1) : "—"]
          ]
          Item {
            required property var modelData
            y: modelData[1]
            width: lanes.width
            height: modelData[2]
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
              text: parent.modelData[3]
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

        // High, mid and low cloud as three thin rows: high thin cloud often still shoots, low never does.
        Repeater {
          model: root.line && root.line.clouds ? root.line.clouds : []
          Item {
            id: hour
            required property var modelData
            x: lanes.labelW + modelData.a * lanes.laneW
            width: Math.max(1, (modelData.b - modelData.a) * lanes.laneW - 1)
            height: Style.space(23)
            Repeater {
              model: ["high", "mid", "low"]
              Rectangle {
                required property var modelData
                required property int index
                readonly property var pct: hour.modelData[modelData]
                y: index * (lanes.row + Style.space(1))
                width: hour.width
                height: lanes.row
                radius: Style.space(1)
                color: root.rgba(root.fg, 0.06 + 0.8 * ((pct === null || pct === undefined ? hour.modelData.total : pct) / 100))
              }
            }
          }
        }

        Repeater {
          model: root.line && root.line.clouds ? root.line.clouds : []
          Rectangle {
            required property var modelData
            visible: modelData.jet !== null && modelData.jet !== undefined
            x: lanes.labelW + modelData.a * lanes.laneW
            y: Style.space(28)
            width: Math.max(1, (modelData.b - modelData.a) * lanes.laneW - 1)
            height: Style.space(10)
            radius: Style.space(2)
            color: root.jetColor(modelData.jet)
            opacity: 0.8
          }
        }

        Repeater {
          model: root.line && root.line.kp ? root.line.kp : []
          Rectangle {
            required property var modelData
            readonly property real fill: Math.max(0.12, Math.min(1, modelData.kp / 9))
            x: lanes.labelW + modelData.a * lanes.laneW
            y: Style.space(44) + Style.space(16) * (1 - fill)
            width: Math.max(1, (modelData.b - modelData.a) * lanes.laneW - 1)
            height: Style.space(16) * fill
            radius: Style.space(2)
            color: root.kpColor(modelData.kp)
            opacity: modelData.observed === "predicted" ? 0.75 : 1
          }
        }

        // The aurora threshold from the widget settings (Kp 6 by default).
        Rectangle {
          visible: root.line !== null && root.line.kp !== null
          x: lanes.labelW; width: lanes.laneW; height: 1
          y: Style.space(44) + Style.space(16) * (1 - root.auroraKp / 9)
          color: root.rgba(root.fg, 0.35)
        }

        Repeater {
          model: root.line ? root.line.ticks : []
          Text {
            required property var modelData
            x: lanes.labelW + modelData.at * lanes.laneW - implicitWidth / 2
            y: Style.space(66)
            text: modelData.label
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Repeater {
        model: ["clouds", "haze", "kp"]
        Text {
          required property var modelData
          width: tonightTab.width
          text: root.sourceText(modelData)
          color: root.panel && root.panel.sources && root.panel.sources[modelData].stale ? Color.urgent : Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
      Text {
        width: parent.width
        text: "Kp " + root.auroraKp + " is a planning guide, not a visibility prediction. Solid bins: observed / estimated; faded: forecast."
        color: Qt.darker(root.fg, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      // ---- Every factor behind the verdict, coloured by its rating; gating ones carry a dot
      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: root.shoot !== null && root.shoot.factors.length > 0

        Repeater {
          model: root.shoot ? root.shoot.factors : []
          Rectangle {
            required property var modelData
            readonly property color tone: root.ratingColors[modelData.rating]
            width: Math.min(chip.implicitWidth + Style.space(14), parent.width)
            height: chip.implicitHeight + Style.space(6)
            radius: Style.space(5)
            color: root.rgba(tone, 0.14)
            border.width: 1
            border.color: root.rgba(tone, modelData.gates ? 0.9 : 0.4)
            Text {
              id: chip
              width: parent.width - Style.space(14)
              elide: Text.ElideRight
              anchors.centerIn: parent
              text: (parent.modelData.gates ? "● " : "") + (root.factorNames[parent.modelData.key] || parent.modelData.label)
                    + " " + parent.modelData.value
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
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
                    width: column.width - Style.space(90)
                wrapMode: Text.WordWrap
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
              ["󰫢", Color.accent, root.panel.core_times
                ? "Core " + (root.panel.core_times.rise ? "rises " + root.panel.core_times.rise.time + " " + root.panel.core_times.rise.dir : "up all night")
                  + " · highest " + root.panel.core_times.transit.time + " " + root.panel.core_times.transit.alt + "° " + root.panel.core_times.transit.dir
                  + (root.panel.core_times.set ? " · sets " + root.panel.core_times.set.time + " " + root.panel.core_times.set.dir : "")
                : "Core never rises here"],
              ["󰽢", root.moonColor, root.line.moon_dir
                ? "Moonrise " + root.line.moon_dir.time + " · " + root.line.moon_dir.dir + " (" + root.line.moon_dir.az + "°)"
                : "No moonrise in this window"]
            ].concat(root.panel.exposure ? [["󰄀", root.fg,
                root.panel.exposure.focal + " mm" + (root.panel.exposure.aperture ? " f/" + root.panel.exposure.aperture : "") + ": "
                + (root.panel.exposure.npf ? root.panel.exposure.npf + " s NPF (core) · " : "")
                + root.panel.exposure.rule500 + " s 500 rule"]] : []).concat(root.panel.notes.map(function(n) {
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
                width: column.width - Style.space(90)
                wrapMode: Text.WordWrap
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

      // ---- Week & events
      Column {
        id: weekTab
        width: parent.width
        spacing: Style.space(10)
        visible: root.tab === 1

        Repeater {
          model: root.panel && root.panel.week ? root.panel.week.filter(function(n) { return n.recommended }) : []
          Text {
            required property var modelData
            width: weekTab.width
            text: "Best upcoming · " + modelData.day + " " + modelData.date + " · " + modelData.best_window.headline
              + " · " + modelData.best_window.minutes + "m · "
              + modelData.best_window.factors.filter(function(f) { return f.key === "wind_gust" }).map(function(f) { return "gusts " + f.value }).join("")
            color: root.levelColors[modelData.best_window.level]
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            wrapMode: Text.WordWrap
          }
        }
        Text {
          width: parent.width
          visible: root.panel !== null && root.panel.week !== null && !root.panel.week.some(function(n) { return n.recommended })
          text: "No best night yet: a recommendation needs a usable interval with a complete, fresh forecast."
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Row {
          id: weekRow
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.panel && root.panel.week ? root.panel.week : []
            Rectangle {
              id: dayCard
              activeFocusOnTab: true
              Keys.onReturnPressed: root.goToDate(modelData.date)
              required property var modelData
              readonly property color tone: root.levelColors[modelData.level]
              width: (weekRow.width - Style.space(6) * 6) / 7
              height: Style.space(122)
              radius: Style.space(8)
              color: root.rgba(tone, 0.12)
              border.width: modelData.recommended ? 2 : 1
              border.color: modelData.recommended ? root.fg : root.rgba(tone, 0.45)

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: dayCard.modelData.recommended ? "Best" : ""; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: dayCard.modelData.day; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(new Date(dayCard.modelData.date + "T12:00:00"), "d"); color: Qt.darker(root.fg, 1.5); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: dayCard.modelData.glyph; color: root.moonColor; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: Style.space(28); height: Style.space(5); radius: height / 2; color: dayCard.tone }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.floor(dayCard.modelData.moon_free_minutes / 60) + "h" + ("0" + dayCard.modelData.moon_free_minutes % 60).slice(-2); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰖐 " + dayCard.modelData.cloud + (dayCard.modelData.incomplete ? "?" : ""); color: Qt.darker(root.fg, 1.3); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onEntered: if (root.bar) root.bar.showTooltip(dayCard, dayCard.modelData.headline + (dayCard.modelData.best_window ? "\nBest interval: " + dayCard.modelData.best_window.headline : "") + (dayCard.modelData.aurora ? " · aurora possible" : ""))
                onExited: if (root.bar) root.bar.hideTooltip(dayCard)
                onClicked: root.goToDate(dayCard.modelData.date)
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Colour: whole target-window assessment. Best: rating, complete/fresh coverage, then duration; only complete, fresh forecasts qualify. ? means incomplete data. Click a night to open it."
          color: Qt.darker(root.fg, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.fg }

        Text {
          text: "Next 30 days"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Repeater {
          model: root.panel && root.panel.events ? root.panel.events : []
          Row {
            id: eventLine
            required property var modelData
            width: weekTab.width
            spacing: Style.space(8)
            Text {
              width: Style.space(76)
              text: eventLine.modelData.date
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              width: Style.space(14)
              text: ({ moon: "󰽢", season: "󰖨", shower: "󰫢", festival: "󰋼", other: "󰋼" })[eventLine.modelData.kind] || "•"
              color: eventLine.modelData.good ? "#4caf7a" : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Column {
              width: eventLine.width - Style.space(76) - Style.space(14) - Style.space(16)
              Text {
                width: parent.width
                text: eventLine.modelData.title
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: eventLine.modelData.good
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: text !== ""
                text: eventLine.modelData.detail
                color: Qt.darker(root.fg, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }
        }
      }
      Column {
        id: locationsTab
        width: parent.width
        visible: root.tab === 2
        spacing: Style.space(8)
        Flow {
          width: parent.width
          spacing: Style.space(4)
          Button {
            text: "Weather / configured location"
            selected: root.savedLocation === ""
            foreground: root.fg
            focusable: true
            onClicked: root.savedLocation = ""
          }
          Repeater {
            model: root.places
            Button {
              required property var modelData
              text: modelData.name.length > 30 ? modelData.name.slice(0, 27) + "…" : modelData.name
              tooltipText: modelData.name
              selected: root.savedLocation === modelData.name
              foreground: root.fg
              focusable: true
              onClicked: root.savedLocation = modelData.name
            }
          }
        }
        Button {
          text: compareProc.running ? "Comparing…" : "Compare locations for this night"
          enabled: !compareProc.running
          foreground: root.fg
          focusable: true
          onClicked: root.comparePlaces()
        }
        Repeater {
          model: root.comparison
          Column {
            required property var modelData
            width: locationsTab.width
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: parent.modelData.location.name + " · " + parent.modelData.location.tz
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: parent.modelData.best_window ? parent.modelData.best_window.headline + (parent.modelData.best_window.incomplete ? " · incomplete forecast" : "") + (parent.modelData.best_window.stale ? " · stale forecast" : "")
                : parent.modelData.shoot.headline + " · no future usable interval"
              color: root.levelColors[parent.modelData.best_window ? parent.modelData.best_window.level : parent.modelData.shoot.level]
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
        PanelSeparator { foreground: root.fg }
        Text {
          width: parent.width
          text: "Save a location. Use its IANA time zone; times and evening dates are local to that place. Reusing a name replaces that saved location."
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        TextField { id: placeName; width: parent.width; placeholderText: "Location name"; foreground: root.fg; Keys.onEscapePressed: root.close() }
        Row {
          width: parent.width
          spacing: Style.space(6)
          TextField { id: placeLat; width: (parent.width - parent.spacing) / 2; placeholderText: "Latitude"; foreground: root.fg; Keys.onEscapePressed: root.close() }
          TextField { id: placeLon; width: (parent.width - parent.spacing) / 2; placeholderText: "Longitude"; foreground: root.fg; Keys.onEscapePressed: root.close() }
        }
        TextField { id: placeTz; width: parent.width; placeholderText: "Time zone · e.g. America/Denver"; foreground: root.fg; Keys.onEscapePressed: root.close() }
        Row {
          spacing: Style.space(6)
          Button {
            text: "Use displayed location"
            foreground: root.fg
            focusable: true
            onClicked: {
              if (!root.panel || !root.panel.location) return
              var p = root.panel.location
              placeName.text = p.name; placeLat.text = String(p.lat); placeLon.text = String(p.lon); placeTz.text = p.tz
            }
          }
          Button { text: "Save / replace"; foreground: root.fg; enabled: !placeProc.running; focusable: true; onClicked: root.savePlace() }
        }
        Text {
          width: parent.width
          text: root.locationMessage
          visible: text !== ""
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        Repeater {
          model: root.places
          Row {
            required property var modelData
            width: locationsTab.width
            spacing: Style.space(6)
            Text {
              width: parent.width - removeButton.width - parent.spacing
              text: parent.modelData.name + " · " + parent.modelData.tz
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Button { id: removeButton; text: "Remove"; foreground: root.fg; focusable: true; enabled: !placeProc.running; onClicked: root.removePlace(parent.modelData.name) }
          }
        }
      }
    }
    }
    }
  }
}
