import Foundation
// Real strings taken verbatim from archived calls.
let drop = [
  "Thank you for watching.", "Thank you for your attention.", "Thank you for listening.",
  "Thank you for joining.", "Thank you for joining!", "Thank you for joining us today.",
  "Thank you for your time.", "Thank you for reaching out!", "Thank you so much for watching.",
  "Thanks for joining us on this journey.", "That's it for this week.",
  "For more information, visit our website at splunk.com/sci.",
  "For more information on the new platform, visit www.plastics-car.com",
  "To learn more about our products, visit our website at www. plastics-car.com",
  "Please see the complete disclaimer at PissedConsumer.com for more information.",
]
// Must survive untouched: real customer and rep speech.
let keep = [
  "Thanks for sharing that, guys. Thanks for catching me up to speed.",
  "Thank you for that. Liam, what questions do you have?",
  "We can't stand up the other data center until CGNAT exists in that side of the state.",
  "I think the license needs to be purchased in December, so I think that's when it renews.",
  "So once we get all the logs in, it's the presentation and access to it.",
  "Thanks, I appreciate you walking through the architecture with us in that much detail today.",
]
// Artifact with real speech attached: strip the artifact, keep the speech.
let partial = [("Thanks for your time. My internal developers.", "My internal developers.")]

var pass = 0, fail = 0
func ck(_ n: String, _ ok: Bool, _ detail: String = "") {
  ok ? (pass += 1, print("  PASS  \(n)")).1 : (fail += 1, print("  FAIL  \(n)  \(detail)")).1
}
for s in drop {
  let out = StreamingMicTranscriber.stripHallucination(s)
  ck("dropped: \(s.prefix(46))", out.isEmpty, "-> \(out.debugDescription)")
}
for s in keep {
  let out = StreamingMicTranscriber.stripHallucination(s)
  ck("kept:    \(s.prefix(46))", out == s, "-> \(out.debugDescription)")
}
for (inp, want) in partial {
  let out = StreamingMicTranscriber.stripHallucination(inp)
  ck("stripped to real speech", out == want, "-> \(out.debugDescription) want \(want.debugDescription)")
}
print("\nhallucination filter: \(pass)/\(pass + fail) passed")
exit(fail == 0 ? 0 : 1)

precondition(StreamingMicTranscriber.stripHallucination("And if you are looking for a solution to the COVID-19 pandemic, please contact your local") == "")
precondition(StreamingMicTranscriber.stripHallucination("We changed our monitoring approach during the COVID-19 pandemic.") == "We changed our monitoring approach during the COVID-19 pandemic.")
print("PASS observed stock hallucination removed; ordinary pandemic discussion preserved")

precondition(StreamingMicTranscriber.stripHallucination("And if you are looking for a solution to the COVID-19 pand emic, please contact your local") == "")
