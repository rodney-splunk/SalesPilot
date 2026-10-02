import Foundation
let expected = ["Nancy Xiao", "Wei Zhang", "Priya Nair", "Arjun Desai", "Nguyen Tran", "José García", "Amina Hassan", "Siobhán O’Connor"]
precondition(NameHints.names(from: "People: " + expected.joined(separator: ", ")) == expected)
precondition(NameHints.names(from: "Account: Buttercup Enterprises\nPeople: Nancy Xiao, Security Operations; José García — Director\nContext: Splunk Cloud Platform") == ["Nancy Xiao", "José García"])
precondition(NameHints.names(from: "Attendees: Anne-Marie Dubois; María de la Cruz; Nancy Xiao; Nancy Xiao") == ["Anne-Marie Dubois", "María de la Cruz", "Nancy Xiao"])
precondition(NameHints.names(from: "Attendees: Nancy Xiao\nParticipants: Wei Zhang") == ["Nancy Xiao", "Wei Zhang"])
print("name hints: Unicode, people field, roles, particles and duplicate checks passed")

precondition(NameHints.callNames(["turns": [["me": true, "who": "Rodney White"], ["me": true, "who": "You"]], "roster": [["name": "Nancy"], ["name": "Nancy"]]]) == ["Rodney White", "Nancy"])
