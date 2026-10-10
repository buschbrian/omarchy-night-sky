import QtQuick
import qs.Commons

// Lanes on the sky chart's time axis: cloud by layer (high, mid, low), the jet-stream seeing
// proxy and planetary Kp. `rows` picks which, in order; the hour axis closes the stack.
Column {
  id: root
  required property var timeline
  property var rows: ["clouds", "seeing", "aurora"]
  property real plotLeft: 0
  property real plotWidth: width
  property real auroraKp: 6
  property var kpColor: function(kp) { return "#4caf7a" }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.5)
  spacing: Style.spacing.sm

  function jetColor(kmh) { return kmh === null || kmh === undefined ? "transparent" : kmh <= 70 ? "#4caf7a" : kmh <= 110 ? "#e3b341" : "#e0574f" }
  function value(key) {
    if (!timeline) return "—"
    if (key === "clouds") return timeline.cloud_pct !== null ? timeline.cloud_pct + "%" : "—"
    if (key === "seeing") return timeline.clouds && timeline.clouds.length
      ? Math.round(Math.max.apply(null, timeline.clouds.map(function(c) { return c.jet || 0 }))) + " km/h" : "—"
    return timeline.kp_max !== null ? "Kp " + timeline.kp_max.toFixed(1) : "—"
  }

  Repeater {
    model: root.rows
    Item {
      id: lane
      required property string modelData
      readonly property real row: Style.space(4)
      width: root.width
      height: modelData === "clouds" ? row * 3 + Style.space(2) : modelData === "seeing" ? Style.space(6) : Style.space(12)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ({ clouds: "Clouds", seeing: "Seeing", aurora: "Aurora" })[lane.modelData]
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        x: root.plotLeft + root.plotWidth + Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: root.value(lane.modelData)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Rectangle { x: root.plotLeft; width: root.plotWidth; height: parent.height; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) }

      // High thin cloud often still shoots, low never does.
      Repeater {
        model: lane.modelData === "clouds" && root.timeline && root.timeline.clouds ? root.timeline.clouds : []
        Item {
          id: hour
          required property var modelData
          x: root.plotLeft + modelData.a * root.plotWidth
          width: Math.max(1, (modelData.b - modelData.a) * root.plotWidth - 1)
          height: lane.height
          Repeater {
            model: ["high", "mid", "low"]
            Rectangle {
              required property var modelData
              required property int index
              readonly property var pct: hour.modelData[modelData]
              y: index * (lane.row + Style.space(1))
              width: hour.width
              height: lane.row
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                             0.06 + 0.8 * ((pct === null || pct === undefined ? hour.modelData.total : pct) / 100))
            }
          }
        }
      }

      Repeater {
        model: lane.modelData === "seeing" && root.timeline && root.timeline.clouds ? root.timeline.clouds : []
        Rectangle {
          required property var modelData
          visible: modelData.jet !== null && modelData.jet !== undefined
          x: root.plotLeft + modelData.a * root.plotWidth
          width: Math.max(1, (modelData.b - modelData.a) * root.plotWidth - 1)
          height: lane.height
          color: root.jetColor(modelData.jet)
          opacity: 0.8
        }
      }

      // Kp bins rise from the lane floor and fade toward it; forecast bins are lighter.
      Repeater {
        model: lane.modelData === "aurora" && root.timeline && root.timeline.kp ? root.timeline.kp : []
        Rectangle {
          id: kpBin
          required property var modelData
          readonly property real fill: Math.max(0.12, Math.min(1, modelData.kp / 9))
          readonly property color tone: root.kpColor(modelData.kp)
          x: root.plotLeft + modelData.a * root.plotWidth
          y: lane.height * (1 - fill)
          width: Math.max(1, (modelData.b - modelData.a) * root.plotWidth - 1)
          height: lane.height * fill
          opacity: modelData.observed === "predicted" ? 0.6 : 1
          gradient: Gradient {
            GradientStop { position: 0; color: kpBin.tone }
            GradientStop { position: 1; color: Qt.rgba(kpBin.tone.r, kpBin.tone.g, kpBin.tone.b, 0.25) }
          }
        }
      }

      // The aurora threshold from the widget settings.
      Rectangle {
        visible: lane.modelData === "aurora" && root.timeline !== null && root.timeline.kp !== null
        x: root.plotLeft; width: root.plotWidth; height: 1
        y: lane.height * (1 - root.auroraKp / 9)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
      }
    }
  }

  Item {
    width: root.width
    height: Style.font.caption + Style.space(2)
    Repeater {
      model: root.timeline ? root.timeline.ticks : []
      Text {
        required property var modelData
        x: root.plotLeft + modelData.at * root.plotWidth - implicitWidth / 2
        text: modelData.label + ":00"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
