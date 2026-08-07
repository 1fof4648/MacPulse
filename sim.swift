import Foundation

// Simulates a realistic discharge session and runs two controllers over it:
//   (a) the conventional percentage threshold used by battery utilities
//   (b) MacPulse's chance-constrained Kalman forecast
// Emits assets/forecast.svg. Usage: swift sim.swift

let minutes = 200
let designWh = 83.6          // 2018 15" MBP design capacity
var energy = 47.0            // start at ~56%
var rng = SystemRandomNumberGenerator()

func load(_ t: Int) -> Double {
    switch t {
    case ..<35:    return 11.5           // idle: browsing, notes
    case ..<95:    return 34.0           // sustained build / video call, dGPU awake
    case ..<130:   return 17.0           // tapering
    default:       return 12.5           // idle again
    }
}

// Kalman: local linear trend, innovation-adapted measurement noise
var kL = 11.5, kT = 0.0
var p11 = 25.0, p12 = 0.0, p22 = 1.0, kR = 4.0
let q1 = 0.5, q2 = 0.05, z = 1.645

struct Sample {
    let t: Int, watts: Double, level: Double, forecast: Double, sigma: Double
    let pct: Double, m95: Double
}
var samples: [Sample] = []
var lpmPredictive: Int? = nil
var lpmThreshold: Int? = nil
var engaged = false

for t in 0..<minutes {
    let noise = Double.random(in: -1.8...1.8, using: &rng)
    let w = max(3.0, load(t) + noise)

    // predict
    let lp = kL + kT
    let a11 = p11 + 2 * p12 + p22 + q1
    let a12 = p12 + p22
    let a22 = p22 + q2
    // update
    let y = w - lp
    let s = a11 + kR
    let k1 = a11 / s, k2 = a12 / s
    kL = lp + k1 * y
    kT = kT + k2 * y
    p11 = (1 - k1) * a11
    p12 = (1 - k1) * a12
    p22 = a22 - k2 * a12
    kR = max(0.9 * kR + 0.1 * (y * y - a11), 0.25)

    var pf = kL + 5 * kT
    if pf < kL { pf = kL }
    if pf < 3 { pf = 3 }
    let varF = max(p11 + 10 * p12 + 25 * p22 + kR, 0.01)
    let sigma = varF.squareRoot()
    let m95 = 60 * energy / (pf + z * sigma)
    let pct = energy / designWh * 100

    if !engaged, m95 <= 120 { engaged = true; if lpmPredictive == nil { lpmPredictive = t } }
    if engaged, m95 >= 180 { engaged = false }
    if lpmThreshold == nil, pct <= 20 { lpmThreshold = t }

    samples.append(Sample(t: t, watts: w, level: kL, forecast: pf, sigma: sigma, pct: pct, m95: m95))
    energy = max(0, energy - w / 60.0)
}

// ---- SVG ----------------------------------------------------------------

let W = 1240.0, H = 720.0
let padL = 74.0, padR = 150.0, padT = 54.0
let plotW = W - padL - padR
let topH = 250.0, gap = 92.0, botH = 210.0
let wMax = 50.0

func x(_ t: Int) -> Double { padL + Double(t) / Double(minutes - 1) * plotW }
func yW(_ v: Double) -> Double { padT + topH - (v / wMax) * topH }
let y2Base = padT + topH + gap
func yM(_ v: Double) -> Double { y2Base + botH - (min(v, 240) / 240) * botH }

var svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(W)) \(Int(H))" width="\(Int(W))" height="\(Int(H))" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif">
<style>
  .bg{fill:#0d1420}
  .gr{stroke:#1c2637;stroke-width:1}
  .lbl{fill:#8fa3bf;font-size:12px}
  .ttl{fill:#e9eef6;font-size:15px;font-weight:700}
  .sub{fill:#7d8ea8;font-size:11.5px}
  .raw{fill:none;stroke:#3f5a80;stroke-width:1.4}
  .lvl{fill:none;stroke:#4FC3FF;stroke-width:2.6}
  .fc{fill:none;stroke:#B79CFF;stroke-width:2;stroke-dasharray:5 4}
  .m95{fill:none;stroke:#30D158;stroke-width:2.6}
  .warn{stroke:#FF9F0A;stroke-width:2;stroke-dasharray:6 5}
  .crit{stroke:#FF453A;stroke-width:2;stroke-dasharray:6 5}
  .key{fill:#c7d4e6;font-size:12px}
</style>
<rect class="bg" width="\(Int(W))" height="\(Int(H))" rx="14"/>
<text class="ttl" x="\(padL)" y="26">Discharge session: idle -> sustained load -> idle</text>
<text class="sub" x="\(padL)" y="44">Simulated with MacPulse's actual filter constants. Load steps at t=35 (11.5 W to 34 W) and t=95.</text>
"""

for k in stride(from: 0.0, through: wMax, by: 10.0) {
    let yy = yW(k)
    svg += "<line class=\"gr\" x1=\"\(padL)\" y1=\"\(yy)\" x2=\"\(padL + plotW)\" y2=\"\(yy)\"/>"
    svg += "<text class=\"lbl\" x=\"\(padL - 12)\" y=\"\(yy + 4)\" text-anchor=\"end\">\(Int(k))W</text>"
}
for k in [0.0, 60.0, 120.0, 180.0, 240.0] {
    let yy = yM(k)
    svg += "<line class=\"gr\" x1=\"\(padL)\" y1=\"\(yy)\" x2=\"\(padL + plotW)\" y2=\"\(yy)\"/>"
    svg += "<text class=\"lbl\" x=\"\(padL - 12)\" y=\"\(yy + 4)\" text-anchor=\"end\">\(Int(k))m</text>"
}

func path(_ vals: [(Double, Double)]) -> String {
    vals.enumerated().map { i, p in "\(i == 0 ? "M" : "L")\(String(format: "%.1f", p.0)),\(String(format: "%.1f", p.1))" }.joined()
}

let bandTop = samples.map { (x($0.t), yW(min(wMax, $0.forecast + z * $0.sigma))) }
let bandBot = samples.reversed().map { (x($0.t), yW(max(0, $0.forecast - z * $0.sigma))) }
svg += "<path d=\"\(path(bandTop + bandBot))Z\" fill=\"#B79CFF\" fill-opacity=\"0.09\"/>"
svg += "<path class=\"raw\" d=\"\(path(samples.map { (x($0.t), yW($0.watts)) }))\"/>"
svg += "<path class=\"lvl\" d=\"\(path(samples.map { (x($0.t), yW($0.level)) }))\"/>"
svg += "<path class=\"fc\" d=\"\(path(samples.map { (x($0.t), yW(min(wMax, $0.forecast))) }))\"/>"

svg += "<text class=\"ttl\" x=\"\(padL)\" y=\"\(y2Base - 22)\">95%-confidence runtime remaining</text>"
svg += "<path class=\"m95\" d=\"\(path(samples.map { (x($0.t), yM($0.m95)) }))\"/>"
svg += "<line class=\"warn\" x1=\"\(padL)\" y1=\"\(yM(180))\" x2=\"\(padL + plotW)\" y2=\"\(yM(180))\"/>"
svg += "<text class=\"lbl\" x=\"\(padL + plotW + 8)\" y=\"\(yM(180) + 4)\">release 180m</text>"
svg += "<line class=\"crit\" x1=\"\(padL)\" y1=\"\(yM(120))\" x2=\"\(padL + plotW)\" y2=\"\(yM(120))\"/>"
svg += "<text class=\"lbl\" x=\"\(padL + plotW + 8)\" y=\"\(yM(120) + 4)\">engage 120m</text>"

func marker(_ t: Int, _ color: String, _ label: String, _ dy: Double) {
    let xx = x(t)
    svg += "<line x1=\"\(xx)\" y1=\"\(padT)\" x2=\"\(xx)\" y2=\"\(y2Base + botH)\" stroke=\"\(color)\" stroke-width=\"1.8\" stroke-opacity=\"0.85\"/>"
    svg += "<circle cx=\"\(xx)\" cy=\"\(padT + dy)\" r=\"5\" fill=\"\(color)\"/>"
    svg += "<text x=\"\(xx + 10)\" y=\"\(padT + dy + 4)\" fill=\"\(color)\" font-size=\"12.5\" font-weight=\"600\">\(label)</text>"
}
if let t = lpmPredictive { marker(t, "#30D158", "MacPulse engages - t=\(t)m", 30) }
if let t = lpmThreshold  { marker(t, "#FF453A", "20% threshold fires - t=\(t)m", 58) }

svg += "<g transform=\"translate(\(padL),\(H - 26))\">"
let items: [(String, String)] = [("#3f5a80","measured watts"),("#4FC3FF","Kalman level"),("#B79CFF","5-min forecast band"),("#30D158","95% runtime bound")]
var off = 0.0
for (c, t) in items {
    svg += "<rect x=\"\(off)\" y=\"-9\" width=\"22\" height=\"3.5\" rx=\"1.75\" fill=\"\(c)\"/>"
    svg += "<text class=\"key\" x=\"\(off + 30)\" y=\"-4\">\(t)</text>"
    off += 30 + Double(t.count) * 6.9 + 26
}
svg += "</g></svg>"

try! svg.write(toFile: FileManager.default.currentDirectoryPath + "/assets/forecast.svg",
               atomically: true, encoding: .utf8)

print("predictive engaged t=\(lpmPredictive.map(String.init) ?? "never")")
print("threshold engaged  t=\(lpmThreshold.map(String.init) ?? "never")")
if let a = lpmPredictive, let b = lpmThreshold { print("lead time: \(b - a) min") }
if let b = lpmThreshold { print("runtime left at 20%: \(String(format: "%.0f", samples[b].m95)) min") }
