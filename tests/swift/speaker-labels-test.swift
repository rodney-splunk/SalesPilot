import Foundation
let turns = [SpeakerEvidence(text: "Yes, exactly.", startedAt: 100, mic: false, name: "Jesse"), SpeakerEvidence(text: "Yes, exactly.", startedAt: 102, mic: false, name: "Joe"), SpeakerEvidence(text: "Hello.", startedAt: 101, mic: true, name: "Rodney")]
let labels = SpeakerLookup.labels(turns)
precondition(labels[SpeakerLookup.key(text: "Yes, exactly.", startedAt: 100, mic: false)] == "Jesse")
precondition(labels[SpeakerLookup.key(text: "Yes, exactly.", startedAt: 102, mic: false)] == "Joe")
precondition(labels["Yes, exactly."] == nil)
precondition(labels["Hello."] == "Rodney")
let uncertain = SpeakerLookup.labels([SpeakerEvidence(text: "Yes.", startedAt: nil, mic: false, name: "Jesse"), SpeakerEvidence(text: "Yes.", startedAt: nil, mic: false, name: "Joe")])
precondition(uncertain["Yes."] == nil)
print("speaker labels: 5/5 passed")

precondition(labels[SpeakerLookup.microphoneKey] == "Rodney")
precondition(SpeakerLookup.microphoneName([SpeakerEvidence(text: "Hi", startedAt: nil, mic: true, name: "Rodney White"), SpeakerEvidence(text: "Yes", startedAt: nil, mic: true, name: "You")]) == "Rodney White")
precondition(SpeakerLookup.microphoneName([SpeakerEvidence(text: "Hi", startedAt: nil, mic: true, name: "Rodney White"), SpeakerEvidence(text: "Hi", startedAt: nil, mic: true, name: "Abby")]) == "You")
precondition(SpeakerLookup.microphoneName([SpeakerEvidence(text: "Hi", startedAt: nil, mic: true, name: "Uncertain speaker")]) == "You")
print("microphone display name: 4/4 passed")

precondition(SpeakerLookup.microphoneName([SpeakerEvidence(text: "Hello", startedAt: nil, mic: true, name: "Rodney White"), SpeakerEvidence(text: "unfinished", startedAt: nil, mic: true, name: "Uncertain speaker"), SpeakerEvidence(text: "brief", startedAt: nil, mic: true, name: "Speaker 1")]) == "Rodney White")
print("known microphone identity survives unassigned fragments: passed")
