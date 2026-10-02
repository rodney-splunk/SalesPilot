import Foundation

/// Fictional, local presentation data. Never replaces a saved call.
enum DemoSession {
    static func make() -> SessionData {
        var session = try! JSONDecoder().decode(SessionData.self, from: Data(json.utf8))
        session.framework = Coaching.selectedName
        session.coverage = Coaching.selectedElements.enumerated().map { CovData(name: $0.element, status: $0.offset < 3 ? "done" : "partial") }
        session.callPurpose = UserDefaults.standard.string(forKey: "callPurpose") ?? "standard"
        if let previous = session.liveAnswer { session.answerHistory = (session.answerHistory ?? []) + [previous] }
        let question = "How does Splunk differ from Sumo Logic for our logging workflow?"
        session.turns.append(TurnData(me: false, who: "Dana Reyes", time: "8:45", text: question, coachTarget: nil, coachQ: nil, side: "customer"))
        session.liveAnswer = LiveAnswer(q: question, answer: "Both provide log analytics. Splunk offers a managed Cloud Platform and self-managed Enterprise deployments. Sumo Logic documents a cloud analytics platform with its Search Query Language. Compare the collection, retention and investigation workflows that matter to your team.", sources: ["https://www.splunk.com/en_us/products/splunk-cloud-platform.html", "https://www.splunk.com/en_us/products/splunk-enterprise.html", "https://www.sumologic.com/help/docs/get-started/"], status: "grounded", sourceTitles: ["https://www.splunk.com/en_us/products/splunk-cloud-platform.html": "Splunk Cloud Platform", "https://www.splunk.com/en_us/products/splunk-enterprise.html": "Splunk Enterprise", "https://www.sumologic.com/help/docs/get-started/": "Sumo Logic documentation"], category: "competition")
        session.competition = [CompetitiveSignal(id: "sumo", name: "Sumo Logic", quote: question, speaker: "Dana Reyes", probe: "How do your analysts search older logs during an investigation?", themes: ["Collection and retention", "Investigation workflow", "Comparable licensing scope"], resources: [CompetitiveResource(title: "Sumo Logic battlecards · Klue", url: "https://v2.app.klue.com/profile/88593/battlecard/view", scope: "Internal enablement · Cisco sign-in required", verifiedAt: "2026-10-02")])]
        if session.callPurpose == "discovery" {
            let question = "When firewall data takes six hours to arrive, what does that mean for an urgent investigation?"
            session.nextq = [NextQData(q: question, tag: "Implication", reason: "Understand the consequence of the current workflow before planning a tailored demo.")]
            for index in session.turns.indices {
                if session.turns[index].text == "Let me show you the correlated search view." { session.turns[index].text = "Walk me through how your team correlates those logs today." }
                if session.turns[index].coachQ?.contains("just showed") == true { session.turns[index].coachQ = question }
            }
        }
        return session
    }
    private static let json = #"""
{
  "name": "Fictional discovery example",
  "title": "Buttercup Enterprises discovery",
  "subtitle": "Fictional example · Security operations",
  "framework": "SPIN",
  "coveragePct": 75,
  "customerName": "Dana Reyes",
  "customerRole": "leads security operations",
  "turns": [
    {
      "me": true,
      "who": "Rodney White",
      "time": "0:05",
      "text": "Hunter did your last demo. Jennifer is the Splunk RSM joining our follow-up planning.",
      "side": "seller"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "0:22",
      "id": 1,
      "text": "We're using Palo Alto firewalls and bringing in 45 gigs of those logs.",
      "side": "customer"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "1:04",
      "id": 2,
      "text": "Our analysts wait six hours for the network team to send firewall logs.",
      "side": "customer"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "1:35",
      "id": 3,
      "text": "That delay means we miss our triage SLA.",
      "side": "customer"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "2:01",
      "id": 4,
      "text": "My team works weekends to catch up instead of doing our planned engineering work.",
      "side": "customer"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "2:26",
      "id": 5,
      "text": "We need to investigate without waiting for another team.",
      "side": "customer"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "2:45",
      "text": "We also have too many low-priority alerts. Important incidents get buried while our analysts work through the queue.",
      "side": "customer"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "2:55",
      "text": "Which is more expensive, Splunk Cloud or Enterprise?",
      "side": "customer"
    },
    {
      "me": true,
      "who": "You",
      "time": "3:04",
      "id": 6,
      "text": "Let me show you the correlated search view.",
      "side": "seller"
    },
    {
      "me": false,
      "who": "Dana Reyes",
      "time": "4:10",
      "id": 7,
      "text": "Actually, I meant roughly 46 gigs of firewall logs.",
      "side": "customer"
    }
  ],
  "coverage": [
    {
      "name": "Identify Pain",
      "status": "done"
    },
    {
      "name": "Metrics",
      "status": "partial"
    },
    {
      "name": "Economic Buyer",
      "status": "done"
    },
    {
      "name": "Champion",
      "status": "partial"
    },
    {
      "name": "Decision Criteria",
      "status": "open"
    },
    {
      "name": "Decision Process",
      "status": "open"
    },
    {
      "name": "Paper Process",
      "status": "open"
    },
    {
      "name": "Competition",
      "status": "open"
    }
  ],
  "nextq": [
    {
      "q": "How does the investigation view I just showed compare with the way your team works today?",
      "tag": "Implication",
      "reason": "Dana described a six-hour wait for firewall data. Explore whether this changes that workflow before positioning a solution."
    }
  ],
  "followups": [
    "Before we go further — are you SOC 2 compliant, and how long do you retain logs?"
  ],
  "liveAnswer": {
    "q": "Which is more expensive, Splunk Cloud or Enterprise?",
    "answer": "There is no universal price ranking. Compare the same workload, support and deployment scope. Enterprise also requires you to account for infrastructure and operations. Confirm the total with your account team.",
    "status": "grounded",
    "sources": [
      "https://www.splunk.com/en_us/products/pricing.html"
    ],
    "sourceTitles": {
      "https://www.splunk.com/en_us/products/pricing.html": "Splunk pricing"
    },
    "receivedAt": 0
  },
  "recap": "Dana’s security team relies on Palo Alto firewall logs. A six-hour handoff delays investigations and risks the triage SLA. Analysts spend weekends catching up, and low-priority alerts bury important incidents. Explore the demonstrated workflow and validate whether prioritization and faster access to logs address the stated need.",
  "nextSteps": [
    "Validate the current investigation workflow and required data sources.",
    "Compare the demonstrated view with the team’s process before selecting a solution."
  ],
  "roster": [
    {
      "name": "Dana Reyes",
      "role": "Security Operations Director",
      "side": "customer",
      "organization": "Buttercup Enterprises",
      "decisionMaker": false
    },
    {
      "name": "Rodney White",
      "role": "Solutions Engineer",
      "side": "seller",
      "organization": "Splunk",
      "decisionMaker": false
    }
  ],
  "phase": "discover",
  "solutions": {
    "status": "leaning",
    "note": "Security operations is the consistent thread. Response automation is a secondary signal.",
    "areas": [
      {
        "id": "es",
        "name": "Enterprise Security",
        "area": "security operations",
        "score": 16,
        "probes": [
          "When an alert fires after hours, what happens next?"
        ],
        "evidence": [
          "legacy siem",
          "retention gaps",
          "triage slas",
          "audit"
        ]
      },
      {
        "id": "soar",
        "name": "SOAR",
        "area": "response automation",
        "score": 6,
        "probes": [
          "Which of those manual steps happens on every single incident?"
        ],
        "evidence": [
          "a ton of manual work",
          "analysts are drowning"
        ]
      }
    ]
  },
  "delivery": {
    "talkRatio": 33,
    "fillerPerMin": 2,
    "longestMonologueSec": 6,
    "openingFramed": false
  },
  "notes": [
    {
      "id": "1-0",
      "turnId": 1,
      "quote": "We're using Palo Alto firewalls and bringing in 45 gigs of those logs.",
      "categories": [
        "technical"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": false,
      "at": "0:22",
      "startedAt": null,
      "correction": false
    },
    {
      "id": "2-1",
      "turnId": 2,
      "quote": "Our analysts wait six hours for the network team to send firewall logs.",
      "categories": [
        "business",
        "technical"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": false,
      "at": "1:04",
      "startedAt": null,
      "correction": false
    },
    {
      "id": "3-2",
      "turnId": 3,
      "quote": "That delay means we miss our triage SLA.",
      "categories": [
        "business"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": false,
      "at": "1:35",
      "startedAt": null,
      "correction": false
    },
    {
      "id": "4-3",
      "turnId": 4,
      "quote": "My team works weekends to catch up instead of doing our planned engineering work.",
      "categories": [
        "personal"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": false,
      "at": "2:01",
      "startedAt": null,
      "correction": false
    },
    {
      "id": "5-4",
      "turnId": 5,
      "quote": "We need to investigate without waiting for another team.",
      "categories": [
        "business",
        "technical",
        "outcomes"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": false,
      "at": "2:26",
      "startedAt": null,
      "correction": false
    },
    {
      "id": "7-5",
      "turnId": 7,
      "quote": "Actually, I meant roughly 46 gigs of firewall logs.",
      "categories": [
        "technical"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": true,
      "at": "4:10",
      "startedAt": null,
      "correction": true
    },
    {
      "id": "demo-alerts",
      "turnId": 6,
      "quote": "We also have too many low-priority alerts. Important incidents get buried while our analysts work through the queue.",
      "categories": [
        "technical"
      ],
      "speaker": "Dana Reyes",
      "speakerUnconfirmed": false,
      "tentative": false,
      "at": "2:45",
      "startedAt": null,
      "correction": false
    }
  ],
  "answerHistory": [
    {
      "q": "Which is more expensive, Splunk Cloud or Enterprise?",
      "answer": "There is no universal price ranking. Compare the same workload, support and deployment scope. Enterprise also requires you to account for infrastructure and operations. Confirm the total with your account team.",
      "status": "grounded",
      "sources": [
        "https://www.splunk.com/en_us/products/pricing.html"
      ],
      "sourceTitles": {
        "https://www.splunk.com/en_us/products/pricing.html": "Splunk pricing"
      },
      "receivedAt": 0
    }
  ],
  "opportunities": [
    {
      "id": "core",
      "name": "Splunk Core",
      "area": "Data platform",
      "status": "Start here",
      "capability": "Start discovery with the data sources, search and investigation workflow on Splunk Cloud Platform or Splunk Enterprise.",
      "evidence": [
        {
          "quote": "We're using Palo Alto firewalls and bringing in 45 gigs of those logs.",
          "turnId": 1,
          "who": "Dana Reyes",
          "roleUnconfirmed": false
        },
        {
          "quote": "Our analysts wait six hours for the network team to send firewall logs.",
          "turnId": 2,
          "who": "Dana Reyes",
          "roleUnconfirmed": false
        },
        {
          "quote": "We need to investigate without waiting for another team.",
          "turnId": 5,
          "who": "Dana Reyes",
          "roleUnconfirmed": false
        },
        {
          "quote": "Actually, I meant roughly 46 gigs of firewall logs.",
          "turnId": 7,
          "who": "Dana Reyes",
          "roleUnconfirmed": false
        }
      ],
      "question": "How do you bring your data together and search it when you need to investigate something today?",
      "businessQuestion": "What happens while the team waits for that information?",
      "personalQuestion": "What work does that investigation take your team away from?",
      "sources": [
        {
          "title": "Splunk Platform",
          "url": "https://www.splunk.com/en_us/products/platform.html"
        }
      ],
      "needsValidation": [
        "Validate sources, workflow and desired outcomes before considering additional applications."
      ],
      "ciscoContext": [],
      "ciscoExplanation": "Start with the data platform; explore additional applications only when customer evidence supports them.",
      "contested": false
    },
    {
      "id": "es",
      "name": "Enterprise Security",
      "area": "security operations",
      "status": "Additional fit to validate",
      "capability": "Risk-based alerting groups risk signals around assets and identities to help prioritize investigations.",
      "evidence": [
        {
          "quote": "Our analysts wait six hours for the network team to send firewall logs.",
          "who": "Dana Reyes",
          "turnId": 2,
          "roleUnconfirmed": false
        },
        {
          "quote": "We also have too many low-priority alerts. Important incidents get buried while our analysts work through the queue.",
          "who": "Dana Reyes",
          "turnId": 6,
          "roleUnconfirmed": false
        }
      ],
      "question": "When those logs take six hours to arrive, what happens to an urgent investigation?",
      "businessQuestion": "What happens when an important alert waits in the queue?",
      "personalQuestion": "What does that triage work take your team away from?",
      "sources": [
        {
          "title": "ES risk-based alerting",
          "url": "https://help.splunk.com/en/splunk-enterprise-security-7/risk-based-alerting/7.2/introduction/how-risk-scores-work-in-splunk-enterprise-security"
        }
      ],
      "needsValidation": [
        "Confirm the current workflow and desired outcome.",
        "Validate product version, data availability and deployment requirements with a specialist."
      ],
      "ciscoContext": [],
      "ciscoExplanation": "Use the customer statements to explore this capability with a Splunk specialist. Existing Cisco products alone do not establish a fit.",
      "contested": false
    }
  ],
  "mentionedPeople": [
    {
      "name": "Hunter",
      "role": "Demo presenter",
      "organization": "",
      "inferred": true,
      "attendance": "unconfirmed",
      "quote": "Hunter did your last demo. Jennifer is the Splunk RSM joining our follow-up planning.",
      "who": "Rodney White",
      "turnId": 0
    },
    {
      "name": "Jennifer",
      "role": "RSM",
      "organization": "Splunk",
      "inferred": false,
      "attendance": "unconfirmed",
      "quote": "Hunter did your last demo. Jennifer is the Splunk RSM joining our follow-up planning.",
      "who": "Rodney White",
      "turnId": 0
    }
  ]
}
"""#
}
